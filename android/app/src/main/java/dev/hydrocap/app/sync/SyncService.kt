package dev.hydrocap.app.sync

import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import dev.hydrocap.app.HydroCapApp
import dev.hydrocap.app.R
import dev.hydrocap.app.ble.DiscoveredCap
import dev.hydrocap.app.domain.ReminderPatch
import dev.hydrocap.app.notify.SyncNotifications
import dev.hydrocap.app.ui.AppPermissions
import kotlinx.coroutines.launch

/**
 * Foreground service (type connectedDevice) that hosts one cap job so the
 * GATT link survives screen-off and screen changes. Started by the Home
 * pull-to-refresh, initial pairing, the Ring screen and Debug actions. One
 * application-owned job retains this foreground owner across screen changes.
 * periodic background path is [CapSyncWorker].
 */
class SyncService : LifecycleService() {

    private val owner = ServiceJobOwner()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        val ownerToken = owner.admit(startId) ?: return START_NOT_STICKY
        val container = (application as HydroCapApp).container
        val mode = intent?.getStringExtra(EXTRA_MODE) ?: MODE_SYNC
        val target = intent?.let { readTarget(it) }
        val patch = intent?.let { ReminderPatchExtras.read(it) }
        val initialToken = intent?.getLongExtra(EXTRA_INITIAL_TOKEN, 0L) ?: 0L
        if (!AppPermissions.hasEssential(this)) {
            // connectedDevice foreground services need BLUETOOTH_CONNECT; bail out instead of crashing.
            container.debugLog.log(TAG, "job '$mode' refused: Bluetooth permissions missing")
            if (initialToken != 0L) container.connectionHandoff.failReservation(initialToken, "Bluetooth access is required to connect")
            stopOwned(ownerToken)
            return START_NOT_STICKY
        }
        try {
            startInForeground(mode)
        } catch (e: Exception) {
            container.debugLog.error(TAG, "startForeground failed", e)
            if (initialToken != 0L) container.connectionHandoff.failReservation(initialToken, e.message ?: "Could not start connection")
            stopOwned(ownerToken)
            return START_NOT_STICKY
        }
        if (initialToken != 0L) {
            val job = container.connectionHandoff.startReserved(initialToken,
                operation = { ready -> container.syncEngine.sync(target, onReady = ready) },
                onFinished = {
                    try { container.drinkReminders.replan().join() }
                    finally {
                        BackgroundSync.reconcile(container.appContext, container.settings.current())
                        stopOwned(ownerToken)
                    }
                })
            if (job == null) stopOwned(ownerToken)
            return START_NOT_STICKY
        }
        container.appScope.launch {
            try {
                when (mode) {
                    MODE_LIVE_TOF -> container.syncEngine.liveTof(target)
                    MODE_READ_ALL -> container.syncEngine.readAllSettings(target)
                    MODE_READ_REMINDER -> container.syncEngine.readReminder(target)
                    MODE_APPLY_REMINDER -> container.syncEngine.applyReminder(patch ?: ReminderPatch(), target)
                    else -> container.syncEngine.sync(target)
                }
            } catch (e: Exception) {
                container.debugLog.log(TAG, "service job '$mode' ended with ${e.javaClass.simpleName}: ${e.message}")
            } finally {
                stopOwned(ownerToken)
            }
        }
        return START_NOT_STICKY
    }

    private fun stopOwned(token: Long) { owner.finish(token)?.let { stopSelf(it) } }

    private fun startInForeground(mode: String) {
        val text = when (mode) {
            MODE_LIVE_TOF -> getString(R.string.notification_sync_text_tof)
            MODE_READ_ALL -> getString(R.string.notification_sync_text_read_all)
            MODE_READ_REMINDER -> getString(R.string.notification_sync_text_read_reminder)
            MODE_APPLY_REMINDER -> getString(R.string.notification_sync_text_apply_reminder)
            else -> getString(R.string.notification_sync_text_sync)
        }
        // minSdk 29 ≥ Q: the typed startForeground overload is always available.
        startForeground(NOTIFICATION_ID, SyncNotifications.build(this, text), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
    }

    private fun readTarget(intent: Intent): DiscoveredCap? {
        val address = intent.getStringExtra(EXTRA_TARGET_ADDRESS) ?: return null
        return DiscoveredCap(
            name = intent.getStringExtra(EXTRA_TARGET_NAME),
            address = address,
            rssi = intent.getIntExtra(EXTRA_TARGET_RSSI, 0),
            deviceIdHex = intent.getStringExtra(EXTRA_TARGET_ID),
            rawAdvertisementHex = null,
            matchedByName = true,
            matchedByManufacturerData = false,
            seenAtMs = System.currentTimeMillis(),
        )
    }

    companion object {
        const val TAG = "service"
        const val CHANNEL_ID = SyncNotifications.CHANNEL_ID
        const val NOTIFICATION_ID = 42
        const val EXTRA_MODE = "mode"
        const val MODE_SYNC = "sync"
        const val MODE_LIVE_TOF = "live_tof"
        const val MODE_READ_ALL = "read_all"
        const val MODE_READ_REMINDER = "read_reminder"
        const val MODE_APPLY_REMINDER = "apply_reminder"
        private const val EXTRA_TARGET_ADDRESS = "target_address"
        private const val EXTRA_TARGET_NAME = "target_name"
        private const val EXTRA_TARGET_ID = "target_id"
        private const val EXTRA_TARGET_RSSI = "target_rssi"
        private const val EXTRA_INITIAL_TOKEN = "initial_token"

        fun startInitial(context: Context, target: DiscoveredCap, token: Long) {
            context.startForegroundService(intent(context, MODE_SYNC, target).putExtra(EXTRA_INITIAL_TOKEN, token))
        }

        fun start(context: Context, mode: String = MODE_SYNC, target: DiscoveredCap? = null) {
            context.startForegroundService(intent(context, mode, target))
        }

        /** Writes reminder and/or quiet hours to the cap inside the foreground service. */
        fun applyReminder(context: Context, patch: ReminderPatch, target: DiscoveredCap? = null) {
            context.startForegroundService(ReminderPatchExtras.write(intent(context, MODE_APPLY_REMINDER, target), patch))
        }

        private fun intent(context: Context, mode: String, target: DiscoveredCap?): Intent {
            val intent = Intent(context, SyncService::class.java).putExtra(EXTRA_MODE, mode)
            if (target != null) {
                intent.putExtra(EXTRA_TARGET_ADDRESS, target.address)
                    .putExtra(EXTRA_TARGET_NAME, target.name)
                    .putExtra(EXTRA_TARGET_ID, target.deviceIdHex)
                    .putExtra(EXTRA_TARGET_RSSI, target.rssi)
            }
            return intent
        }
    }
}
