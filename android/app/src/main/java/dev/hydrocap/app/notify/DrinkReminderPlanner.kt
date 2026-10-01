package dev.hydrocap.app.notify

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor

/** Pure wall-clock slots using verified cap hours and a known, last-synced consumption snapshot. */
object DrinkReminderPlanner {
    const val identifierPrefix = "hydrocap.drink."
    const val maxPending = 8
    const val defaultWindowStartSec = 8 * 3_600
    const val defaultWindowStopSec = 22 * 3_600
    val frequencyChoicesMinutes: List<Int> = listOf(60, 90, 120, 180)
    const val defaultFrequencyMinutes = 120

    data class Window(val startSec: Int, val stopSec: Int) {
        val isUsable: Boolean get() = startSec in 1..86_400 && stopSec in 1..86_400 && startSec != stopSec
        val start: Int get() = startSec % 86_400
        val stop: Int get() = stopSec % 86_400
        val durationSec: Int get() = if (!isUsable) 0 else if (stop > start) stop - start else 86_400 - start + stop
        fun contains(second: Int): Boolean {
            if (!isUsable) return false
            val value = second % 86_400
            return if (start < stop) value >= start && value < stop else value >= start || value < stop
        }
        companion object {
            // Compatibility/display constant only. plan() never substitutes fallback for unknown hours.
            val fallback = Window(defaultWindowStartSec, defaultWindowStopSec)
        }
    }

    data class Input(
        val enabled: Boolean,
        val now: Instant,
        val window: Window,
        val frequencyMinutes: Int,
        val targetMl: Double,
        /** null means unavailable/query failed; it must never be synthesized as measured zero. */
        val consumedTodayMl: Double?,
        val drinkTimestampsToday: List<Long> = emptyList(),
        val onlyWhenBehind: Boolean = true,
        val zoneId: ZoneId,
        val locale: Locale = Locale.UK,
    )

    data class PlannedReminder(val identifier: String, val fireAt: Instant, val title: String, val body: String)
    data class DayRange(val start: Instant, val end: Instant) {
        fun contains(date: Instant): Boolean = date >= start && date < end
    }

    fun slotSecondsOfDay(window: Window, frequencyMinutes: Int): List<Int> {
        if (!window.isUsable || frequencyMinutes !in 1..1_440) return emptyList()
        return (0 until window.durationSec step frequencyMinutes * 60).map { (window.start + it) % 86_400 }.sorted()
    }

    /** Overnight progress belongs to the same daily goal; it does not reset at the evening start. */
    fun elapsedFraction(window: Window, atSecOfDay: Int): Double {
        if (!window.isUsable) return 0.0
        val second = atSecOfDay.coerceIn(0, 86_400)
        val elapsed = if (window.start < window.stop) (second - window.start).coerceIn(0, window.durationSec)
            else minOf(second, window.stop) + maxOf(0, second - window.start)
        return (elapsed.toDouble() / window.durationSec).coerceIn(0.0, 1.0)
    }

    fun isBehind(targetMl: Double, consumedMl: Double, window: Window, atSecOfDay: Int): Boolean {
        if (!targetMl.isFinite() || targetMl <= 0 || !consumedMl.isFinite()) return false
        return maxOf(0.0, consumedMl) < targetMl * elapsedFraction(window, atSecOfDay)
    }

    fun dayRange(now: Instant, zoneId: ZoneId): DayRange {
        val day = now.atZone(zoneId).toLocalDate()
        return DayRange(day.atStartOfDay(zoneId).toInstant(), day.plusDays(1).atStartOfDay(zoneId).toInstant())
    }

    fun plan(input: Input): List<PlannedReminder> {
        val consumedToday = input.consumedTodayMl
        if (!input.enabled || !input.targetMl.isFinite() || input.targetMl <= 0 ||
            consumedToday == null || !consumedToday.isFinite() || !input.window.isUsable) return emptyList()
        val slots = slotSecondsOfDay(input.window, input.frequencyMinutes)
        val today = input.now.atZone(input.zoneId).toLocalDate()
        val planned = mutableListOf<PlannedReminder>()
        val dates = mutableSetOf<Instant>()
        for (dayOffset in 0..1) {
            val day = today.plusDays(dayOffset.toLong())
            val tomorrow = dayOffset == 1
            for (second in slots) {
                val localFire = wallClockSlot(day, second, input.zoneId)
                val fireAt = localFire.toInstant()
                if (localFire.toLocalDate() != day || fireAt <= input.now) continue
                val actualSecond = localFire.toLocalTime().toSecondOfDay()
                if (!input.window.contains(actualSecond)) continue
                val consumed = if (tomorrow) 0.0 else consumedToday
                if (input.onlyWhenBehind && !isBehind(input.targetMl, consumed, input.window, actualSecond)) continue
                if (!dates.add(fireAt)) continue
                planned += PlannedReminder(
                    "$identifierPrefix${fireAt.epochSecond}", fireAt, "Time to drink",
                    body(input, tomorrow = tomorrow),
                )
                if (planned.size == maxPending) return planned
                // First ELIGIBLE future slot tomorrow, with today's same behind rule.
                if (tomorrow) break
            }
        }
        return planned
    }

    /** Foundation .nextTime / .first: gaps jump to first valid wall time, overlaps use first offset. */
    private fun wallClockSlot(day: LocalDate, second: Int, zoneId: ZoneId): ZonedDateTime {
        val local = LocalDateTime.of(day, LocalTime.ofSecondOfDay(second.toLong()))
        val offsets = zoneId.rules.getValidOffsets(local)
        return if (offsets.isEmpty()) zoneId.rules.getTransition(local)!!.dateTimeAfter.atZone(zoneId)
            else ZonedDateTime.ofLocal(local, zoneId, offsets.first())
    }

    @Suppress("UNUSED_PARAMETER")
    fun body(input: Input, lastDrink: Instant? = null, tomorrow: Boolean): String {
        val consumed = input.consumedTodayMl
        if (consumed == null || !consumed.isFinite()) return "Bottle consumption unavailable. Sync your bottle to check progress."
        if (tomorrow) return "Check your bottle progress today. Your drink goal is ${liters(input.targetMl)}."
        val time = DateTimeFormatter.ofPattern("HH:mm", input.locale).format(input.now.atZone(input.zoneId))
        return "Last sync at $time: ${liters(consumed)} logged from your bottle toward ${liters(input.targetMl)}. Take a sip if you need one."
    }

    private fun liters(ml: Double): String {
        val value = ml / 1000.0
        val rounded = (if (value >= 0) floor(value * 100 + 0.5) else ceil(value * 100 - 0.5)) / 100
        val decimals = if (rounded == floor(rounded) || rounded * 10 == floor(rounded * 10)) 1 else 2
        return String.format(Locale.ROOT, "%.${decimals}f L", rounded)
    }

    fun windowLabel(window: Window): String = "Between ${formatSecond(window.startSec)} and ${formatSecond(window.stopSec)}"
    private fun formatSecond(second: Int): String {
        val normalized = second % 86_400
        return String.format(Locale.ROOT, "%02d:%02d", normalized / 3_600, normalized % 3_600 / 60)
    }
}
