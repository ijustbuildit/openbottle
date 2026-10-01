package dev.hydrocap.app.domain

import kotlin.math.roundToInt

/**
 * Reminder ring + quiet hours as the cap stores them (protocol doc §4,
 * `CapHydroReminderSettings` / `CapDoNotDisturbSettings`), kept as plain
 * Kotlin so the screen, the ADB hooks and the unit tests share one model.
 * Modes are raw wire values so an unknown value reported by the cap survives
 * a read → write round trip untouched.
 */
data class RingColor(val red: Float, val green: Float, val blue: Float, val alpha: Float = 1f) {
    /** Hardware session 1: the cap reports {0,0,0,1} out of the box — "firmware default", not black. */
    val isFirmwareDefault: Boolean get() = red == 0f && green == 0f && blue == 0f

    fun red255(): Int = to255(red)
    fun green255(): Int = to255(green)
    fun blue255(): Int = to255(blue)

    private fun to255(component: Float): Int = (component.coerceIn(0f, 1f) * 255f).roundToInt()

    companion object {
        val FIRMWARE_DEFAULT = RingColor(0f, 0f, 0f, 1f)

        fun fromRgb255(red: Int, green: Int, blue: Int): RingColor =
            RingColor(red.coerceIn(0, 255) / 255f, green.coerceIn(0, 255) / 255f, blue.coerceIn(0, 255) / 255f, 1f)

        /** Swatches offered on the Reminder screen; the cap only ever receives 0..1 floats with alpha 1. */
        val PRESETS: List<Pair<String, RingColor>> = listOf(
            "Blue" to fromRgb255(0, 120, 255),
            "Cyan" to fromRgb255(0, 200, 220),
            "Green" to fromRgb255(40, 200, 80),
            "Yellow" to fromRgb255(255, 200, 0),
            "Orange" to fromRgb255(255, 110, 0),
            "Pink" to fromRgb255(255, 60, 160),
        )
    }
}

data class ReminderSettings(
    val mode: Int,
    /** Seconds of day, 1..86400 (midnight = 86400). */
    val startSec: Int,
    val stopSec: Int,
    val intervalSec: Int,
    val color: RingColor,
) {
    companion object {
        const val MODE_OFF = 0
        const val MODE_FIXED = 1
        const val MODE_ADAPTIVE = 2
    }
}

data class DndSettings(
    val mode: Int,
    val startSec: Int,
    val stopSec: Int,
    /** Never exposed in the UI; whatever the cap reported is written back unchanged. */
    val snoozeMinutes: Int,
) {
    companion object {
        const val MODE_OFF = 0
        /** The wire value the cap calls ON; HydroCap shows it as "Custom hours". */
        const val MODE_CUSTOM = 1
        const val MODE_AUTO = 2
    }
}

/** Both settings as last read from the cap (the cap is the source of truth). */
data class CapReminderConfig(val reminder: ReminderSettings, val dnd: DndSettings)

/** Partial reminder values; null fields keep what the cap currently holds. */
data class ReminderValues(
    val mode: Int? = null,
    val startSec: Int? = null,
    val stopSec: Int? = null,
    val intervalSec: Int? = null,
    val color: RingColor? = null,
)

/** Partial quiet-hours values; for [DndSettings.MODE_AUTO] the hours are derived from the reminder. */
data class DndValues(
    val mode: Int? = null,
    val startSec: Int? = null,
    val stopSec: Int? = null,
)

/**
 * What to write: a null part is not written at all (the ADB hooks write one
 * setting at a time; the screen writes both).
 */
data class ReminderPatch(val reminder: ReminderValues? = null, val dnd: DndValues? = null) {
    val isEmpty: Boolean get() = reminder == null && dnd == null
}

class ReminderValidationException(message: String) : IllegalArgumentException(message)

/** Pure rules shared by the screen, the engine and the tests. */
object ReminderRules {
    const val MIN_SEC_OF_DAY = 1
    const val MAX_SEC_OF_DAY = 86_400

    /** Interval chips on the screen, in minutes. */
    val INTERVAL_CHOICES_MINUTES: List<Int> = listOf(15, 20, 30, 45, 60, 90, 120)

    /** Merges [patch] over the cap's [current] values and derives the Auto quiet hours. */
    fun resolve(current: CapReminderConfig, patch: ReminderPatch): CapReminderConfig {
        val r = patch.reminder
        val reminder = ReminderSettings(
            mode = r?.mode ?: current.reminder.mode,
            startSec = r?.startSec ?: current.reminder.startSec,
            stopSec = r?.stopSec ?: current.reminder.stopSec,
            intervalSec = r?.intervalSec ?: current.reminder.intervalSec,
            color = r?.color ?: current.reminder.color,
        ).let { if (it.mode == ReminderSettings.MODE_OFF) it.copy(startSec = usableSecOfDay(it.startSec), stopSec = usableSecOfDay(it.stopSec)) else it }
        val d = patch.dnd
        val dndMode = d?.mode ?: current.dnd.mode
        val dnd = when (dndMode) {
            // Hardware session 1: AUTO holds DND.start = reminder.stop and DND.stop = reminder.start.
            DndSettings.MODE_AUTO -> DndSettings(dndMode, reminder.stopSec, reminder.startSec, current.dnd.snoozeMinutes)
            DndSettings.MODE_CUSTOM -> DndSettings(dndMode, d?.startSec ?: current.dnd.startSec, d?.stopSec ?: current.dnd.stopSec, current.dnd.snoozeMinutes)
            else -> DndSettings(
                dndMode,
                usableSecOfDay(d?.startSec ?: current.dnd.startSec),
                usableSecOfDay(d?.stopSec ?: current.dnd.stopSec),
                current.dnd.snoozeMinutes,
            )
        }
        return CapReminderConfig(reminder, dnd)
    }

    /** Returns the problem with [config] as text, or null when it can be written. */
    fun validate(config: CapReminderConfig): String? {
        val r = config.reminder
        if (r.mode !in ReminderSettings.MODE_OFF..ReminderSettings.MODE_ADAPTIVE) return "unknown reminder mode ${r.mode}"
        if (r.mode != ReminderSettings.MODE_OFF) {
            if (r.intervalSec <= 0) return "interval must be greater than 0"
            secOfDayProblem("active from", r.startSec)?.let { return it }
            secOfDayProblem("active until", r.stopSec)?.let { return it }
            if (r.startSec == r.stopSec) return "active from and until must differ"
        }
        listOf(r.color.red, r.color.green, r.color.blue, r.color.alpha).forEach {
            if (it.isNaN() || it < 0f || it > 1f) return "colour components must be within 0..1"
        }
        val d = config.dnd
        if (d.mode !in DndSettings.MODE_OFF..DndSettings.MODE_AUTO) return "unknown quiet hours mode ${d.mode}"
        if (d.mode == DndSettings.MODE_CUSTOM) {
            secOfDayProblem("quiet from", d.startSec)?.let { return it }
            secOfDayProblem("quiet until", d.stopSec)?.let { return it }
            if (d.startSec == d.stopSec) return "quiet from and until must differ"
        } else {
            secOfDayProblem("quiet from", d.startSec)?.let { return it }
            secOfDayProblem("quiet until", d.stopSec)?.let { return it }
        }
        return null
    }

    fun validateOrThrow(config: CapReminderConfig): CapReminderConfig {
        validate(config)?.let { throw ReminderValidationException(it) }
        return config
    }

    private fun secOfDayProblem(label: String, value: Int): String? =
        if (value in MIN_SEC_OF_DAY..MAX_SEC_OF_DAY) null else "$label must be between 1 and 86400 seconds of day (got $value)"

    /** Values not in use by the current mode are still written; keep them inside the wire range. */
    private fun usableSecOfDay(value: Int): Int = if (value in MIN_SEC_OF_DAY..MAX_SEC_OF_DAY) value else MAX_SEC_OF_DAY

    /** Picker → wire: midnight is 86400, never 0. */
    fun secOfDay(hour: Int, minute: Int): Int {
        val sec = hour.coerceIn(0, 23) * 3600 + minute.coerceIn(0, 59) * 60
        return if (sec == 0) MAX_SEC_OF_DAY else sec
    }

    fun hourOf(secOfDay: Int): Int = (secOfDay.coerceIn(0, MAX_SEC_OF_DAY) % MAX_SEC_OF_DAY) / 3600

    fun minuteOf(secOfDay: Int): Int = (secOfDay.coerceIn(0, MAX_SEC_OF_DAY) % 3600) / 60

    fun formatSecOfDay(secOfDay: Int): String = "%02d:%02d".format(hourOf(secOfDay), minuteOf(secOfDay))
}
