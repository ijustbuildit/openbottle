package dev.hydrocap.app.debug

import android.content.Context
import android.content.Intent
import dev.hydrocap.app.AppContainer
import dev.hydrocap.app.ble.BleScanner
import dev.hydrocap.app.domain.DndValues
import dev.hydrocap.app.domain.ReminderPatch
import dev.hydrocap.app.domain.ReminderValues
import dev.hydrocap.app.domain.RingColor
import dev.hydrocap.app.sync.SyncService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Headless ADB entry points for the hardware sessions (debug builds only):
 *
 * - `adb shell am start -a dev.hydrocap.app.action.DEBUG_SCAN -n dev.hydrocap.app/.MainActivity`
 * - `adb shell am start -a dev.hydrocap.app.action.DEBUG_SYNC -n dev.hydrocap.app/.MainActivity`
 * - `adb shell am start -a dev.hydrocap.app.action.DEBUG_TOF  -n dev.hydrocap.app/.MainActivity`
 * - `… DEBUG_READ_REMINDER` — logs reminder + quiet hours as the cap holds them
 * - `… DEBUG_SET_REMINDER --ei state 2 --ei start 28800 --ei stop 78300 --ei interval 1800 --ef r 0 --ef g 0.5 --ef b 1`
 *   (every extra optional; absent ones keep the cap's value; r/g/b must be given together)
 * - `… DEBUG_SET_DND --ei state 2 --ei start 78300 --ei stop 28800` (state 0 off, 1 custom hours, 2 auto)
 *
 * Results land in Logcat (tag HydroCap) and `files/debug-log.txt`.
 */
object DebugActions {
    const val ACTION_SCAN = "dev.hydrocap.app.action.DEBUG_SCAN"
    const val ACTION_SYNC = "dev.hydrocap.app.action.DEBUG_SYNC"
    const val ACTION_TOF = "dev.hydrocap.app.action.DEBUG_TOF"
    const val ACTION_READ_REMINDER = "dev.hydrocap.app.action.DEBUG_READ_REMINDER"
    const val ACTION_SET_REMINDER = "dev.hydrocap.app.action.DEBUG_SET_REMINDER"
    const val ACTION_SET_DND = "dev.hydrocap.app.action.DEBUG_SET_DND"

    const val EXTRA_STATE = "state"
    const val EXTRA_START = "start"
    const val EXTRA_STOP = "stop"
    const val EXTRA_INTERVAL = "interval"
    const val EXTRA_RED = "r"
    const val EXTRA_GREEN = "g"
    const val EXTRA_BLUE = "b"

    private const val TAG = "debug"

    private val ACTIONS = setOf(ACTION_SCAN, ACTION_SYNC, ACTION_TOF, ACTION_READ_REMINDER, ACTION_SET_REMINDER, ACTION_SET_DND)

    fun isDebugAction(action: String?): Boolean = action in ACTIONS

    fun handle(intent: Intent, context: Context, container: AppContainer, scope: CoroutineScope) {
        val action = intent.action ?: return
        container.debugLog.log(TAG, "=== $action ===")
        when (action) {
            ACTION_SCAN -> scope.launch { debugScan(container, BleScanner.DEFAULT_SCAN_MS) }
            ACTION_SYNC -> SyncService.start(context, SyncService.MODE_SYNC)
            ACTION_TOF -> SyncService.start(context, SyncService.MODE_LIVE_TOF)
            ACTION_READ_REMINDER -> SyncService.start(context, SyncService.MODE_READ_REMINDER)
            ACTION_SET_REMINDER -> {
                val patch = ReminderPatch(reminder = reminderValues(intent))
                container.debugLog.log(TAG, "set reminder $patch")
                SyncService.applyReminder(context, patch)
            }
            ACTION_SET_DND -> {
                val patch = ReminderPatch(dnd = dndValues(intent))
                container.debugLog.log(TAG, "set dnd $patch")
                SyncService.applyReminder(context, patch)
            }
        }
    }

    /** Parses the DEBUG_SET_REMINDER extras; exposed for tests. */
    fun reminderValues(intent: Intent): ReminderValues {
        val hasColor = intent.hasExtra(EXTRA_RED) || intent.hasExtra(EXTRA_GREEN) || intent.hasExtra(EXTRA_BLUE)
        return ReminderValues(
            mode = intent.optionalInt(EXTRA_STATE),
            startSec = intent.optionalInt(EXTRA_START),
            stopSec = intent.optionalInt(EXTRA_STOP),
            intervalSec = intent.optionalInt(EXTRA_INTERVAL),
            color = if (hasColor) {
                RingColor(intent.getFloatExtra(EXTRA_RED, 0f), intent.getFloatExtra(EXTRA_GREEN, 0f), intent.getFloatExtra(EXTRA_BLUE, 0f), 1f)
            } else {
                null
            },
        )
    }

    fun dndValues(intent: Intent): DndValues = DndValues(
        mode = intent.optionalInt(EXTRA_STATE),
        startSec = intent.optionalInt(EXTRA_START),
        stopSec = intent.optionalInt(EXTRA_STOP),
    )

    /** `am start --ei` sends ints (`--el` longs); `--es` strings are accepted too so quoting mistakes still work. */
    private fun Intent.optionalInt(key: String): Int? {
        if (!hasExtra(key)) return null
        val asInt = getIntExtra(key, Int.MIN_VALUE)
        if (asInt != Int.MIN_VALUE) return asInt
        val asLong = getLongExtra(key, Long.MIN_VALUE)
        if (asLong != Long.MIN_VALUE) return asLong.toInt()
        return getStringExtra(key)?.trim()?.toIntOrNull()
    }

    /** 20 s scan; every match is logged by [BleScanner] with name, address, RSSI, decoded id and raw advertisement. */
    suspend fun debugScan(container: AppContainer, durationMs: Long) {
        val log = container.debugLog
        log.log(TAG, "scan for ${durationMs / 1000} s")
        try {
            val caps = container.scanner.scanFor(durationMs)
            log.log(TAG, "scan finished: ${caps.size} cap(s)")
            caps.forEach { cap ->
                log.log(TAG, "RESULT name=${cap.name} address=${cap.address} rssi=${cap.rssi} id=${cap.deviceIdHex} adv=${cap.rawAdvertisementHex}")
            }
        } catch (e: Exception) {
            log.error(TAG, "scan failed", e)
        }
    }
}
