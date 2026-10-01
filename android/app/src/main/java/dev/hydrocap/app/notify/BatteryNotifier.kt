package dev.hydrocap.app.notify

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import dev.hydrocap.app.R
import dev.hydrocap.app.data.SettingsRepository
import dev.hydrocap.app.debug.DebugLog

/**
 * Battery notifications on channel "battery". Thresholds (default 10 % / 5 %)
 * come from settings; the fired/re-armed state is persisted so a threshold
 * fires exactly once per crossing across app restarts.
 */
class BatteryNotifier(
    private val context: Context,
    private val settings: SettingsRepository,
    private val debugLog: DebugLog,
) {
    private val notificationManager: NotificationManager
        get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun ensureChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_battery),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = context.getString(R.string.notification_channel_battery_description) }
        notificationManager.createNotificationChannel(channel)
    }

    /** Evaluates [percent] against the configured thresholds and notifies on new crossings. */
    suspend fun onBatteryLevel(percent: Int) {
        val current = settings.current()
        val policy = BatteryAlertPolicy(
            thresholds = setOf(current.batteryAlertPercent, current.batteryCriticalPercent),
            firedThresholds = current.firedBatteryThresholds,
        )
        val crossed = policy.onLevel(percent)
        if (policy.firedThresholds != current.firedBatteryThresholds) {
            settings.setFiredBatteryThresholds(policy.firedThresholds)
        }
        if (crossed.isEmpty()) return
        val lowest = crossed.min()
        debugLog.log(TAG, "battery $percent % crossed threshold(s) $crossed → notify")
        show(percent, lowest)
    }

    private fun show(percent: Int, threshold: Int) {
        ensureChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            debugLog.log(TAG, "POST_NOTIFICATIONS not granted, battery alert suppressed")
            return
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_drop)
            .setContentTitle(context.getString(R.string.notification_battery_title, percent))
            .setContentText(context.getString(R.string.notification_battery_text, threshold))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .apply { if (contentIntent != null) setContentIntent(contentIntent) }
            .build()
        notificationManager.notify(NOTIFICATION_ID_BASE + threshold, notification)
    }

    companion object {
        const val TAG = "battery"
        const val CHANNEL_ID = "battery"
        private const val NOTIFICATION_ID_BASE = 1_000
    }
}
