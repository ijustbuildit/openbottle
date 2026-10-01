package dev.hydrocap.app.sync

import android.content.Intent
import dev.hydrocap.app.domain.DndValues
import dev.hydrocap.app.domain.ReminderPatch
import dev.hydrocap.app.domain.ReminderValues
import dev.hydrocap.app.domain.RingColor

/**
 * Carries a [ReminderPatch] through [SyncService]'s start intent so the cap
 * write runs inside the foreground service and not in a ViewModel coroutine
 * that dies with the screen. Absent extras mean "keep the cap's value".
 */
object ReminderPatchExtras {
    private const val PREFIX = "reminder_patch."
    private const val HAS_REMINDER = PREFIX + "has_reminder"
    private const val R_MODE = PREFIX + "r_mode"
    private const val R_START = PREFIX + "r_start"
    private const val R_STOP = PREFIX + "r_stop"
    private const val R_INTERVAL = PREFIX + "r_interval"
    private const val R_HAS_COLOR = PREFIX + "r_has_color"
    private const val R_RED = PREFIX + "r_red"
    private const val R_GREEN = PREFIX + "r_green"
    private const val R_BLUE = PREFIX + "r_blue"
    private const val HAS_DND = PREFIX + "has_dnd"
    private const val D_MODE = PREFIX + "d_mode"
    private const val D_START = PREFIX + "d_start"
    private const val D_STOP = PREFIX + "d_stop"

    /** Sentinel for "not set" (all real values are ≥ 0). */
    private const val UNSET = Int.MIN_VALUE

    fun write(intent: Intent, patch: ReminderPatch): Intent {
        patch.reminder?.let { r ->
            intent.putExtra(HAS_REMINDER, true)
            intent.putExtra(R_MODE, r.mode ?: UNSET)
            intent.putExtra(R_START, r.startSec ?: UNSET)
            intent.putExtra(R_STOP, r.stopSec ?: UNSET)
            intent.putExtra(R_INTERVAL, r.intervalSec ?: UNSET)
            r.color?.let { c ->
                intent.putExtra(R_HAS_COLOR, true)
                intent.putExtra(R_RED, c.red).putExtra(R_GREEN, c.green).putExtra(R_BLUE, c.blue)
            }
        }
        patch.dnd?.let { d ->
            intent.putExtra(HAS_DND, true)
            intent.putExtra(D_MODE, d.mode ?: UNSET)
            intent.putExtra(D_START, d.startSec ?: UNSET)
            intent.putExtra(D_STOP, d.stopSec ?: UNSET)
        }
        return intent
    }

    fun read(intent: Intent): ReminderPatch? {
        val hasReminder = intent.getBooleanExtra(HAS_REMINDER, false)
        val hasDnd = intent.getBooleanExtra(HAS_DND, false)
        if (!hasReminder && !hasDnd) return null
        val reminder = if (hasReminder) {
            ReminderValues(
                mode = intent.optionalInt(R_MODE),
                startSec = intent.optionalInt(R_START),
                stopSec = intent.optionalInt(R_STOP),
                intervalSec = intent.optionalInt(R_INTERVAL),
                color = if (intent.getBooleanExtra(R_HAS_COLOR, false)) {
                    RingColor(intent.getFloatExtra(R_RED, 0f), intent.getFloatExtra(R_GREEN, 0f), intent.getFloatExtra(R_BLUE, 0f), 1f)
                } else {
                    null
                },
            )
        } else {
            null
        }
        val dnd = if (hasDnd) {
            DndValues(mode = intent.optionalInt(D_MODE), startSec = intent.optionalInt(D_START), stopSec = intent.optionalInt(D_STOP))
        } else {
            null
        }
        return ReminderPatch(reminder, dnd)
    }

    private fun Intent.optionalInt(key: String): Int? = getIntExtra(key, UNSET).takeIf { it != UNSET }
}
