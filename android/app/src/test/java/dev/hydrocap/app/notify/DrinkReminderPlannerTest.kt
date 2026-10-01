package dev.hydrocap.app.notify

import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

/** Synthetic last-sync snapshots; no notification/Android framework or test-only planner. */
class DrinkReminderPlannerTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private fun date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant()
    private fun time(hour: Int, minute: Int = 0) = date(2026, 9, 30, hour, minute)
    private fun tomorrow(hour: Int, minute: Int = 0) = date(2026, 10, 1, hour, minute)
    private val window = DrinkReminderPlanner.Window(28_800, 78_300)
    private fun input(
        now: Instant = time(13, 5), enabled: Boolean = true,
        window: DrinkReminderPlanner.Window = this.window, frequency: Int = 120,
        target: Double = 2450.0, consumed: Double? = 0.0, onlyBehind: Boolean = false,
        drinks: List<Long> = emptyList(),
    ) = DrinkReminderPlanner.Input(enabled, now, window, frequency, target, consumed, drinks, onlyBehind, zone, Locale.UK)
    private fun fires(input: DrinkReminderPlanner.Input) = DrinkReminderPlanner.plan(input).map { it.fireAt }

    @Test fun slotsAreAnchoredAndStopExclusive() {
        assertEquals(listOf(28_800, 36_000, 43_200, 50_400, 57_600, 64_800, 72_000), DrinkReminderPlanner.slotSecondsOfDay(window, 120))
        assertEquals(64_800, DrinkReminderPlanner.slotSecondsOfDay(DrinkReminderPlanner.Window(28_800, 72_000), 120).last())
        assertTrue(DrinkReminderPlanner.slotSecondsOfDay(window, 90).all { window.contains(it) })
    }

    @Test fun midnight86400MeansActualLocalMidnight() {
        val late = DrinkReminderPlanner.Window(79_200, 86_400)
        assertTrue(late.isUsable)
        assertEquals(7200, late.durationSec)
        assertEquals(listOf(79_200, 82_800), DrinkReminderPlanner.slotSecondsOfDay(late, 60))
        assertEquals(listOf(time(22), time(23), tomorrow(22)), fires(input(now = time(21), window = late, frequency = 60)))
        val early = DrinkReminderPlanner.Window(86_400, 21_600)
        assertEquals(listOf(0, 7200, 14_400), DrinkReminderPlanner.slotSecondsOfDay(early, 120))
        assertEquals(listOf(time(2), time(4), tomorrow(0)), fires(input(now = time(0), window = early)))
        assertFalse(late.contains(0))
        assertTrue(early.contains(86_400))
    }

    @Test fun overnightNeverFallsBackToDaytime() {
        val overnight = DrinkReminderPlanner.Window(79_200, 28_800)
        assertTrue(overnight.isUsable)
        assertEquals(36_000, overnight.durationSec)
        assertEquals(listOf(3600, 14_400, 25_200, 79_200), DrinkReminderPlanner.slotSecondsOfDay(overnight, 180))
        assertEquals(listOf(time(22), tomorrow(1)), fires(input(now = time(7), window = overnight, frequency = 180)))
        assertTrue(overnight.contains(0))
        assertFalse(overnight.contains(28_800))
        assertFalse(overnight.contains(43_200))
    }

    @Test fun invalidWindowsAndFrequenciesDoNotUseFallback() {
        for (bad in listOf(DrinkReminderPlanner.Window(0, 3600), DrinkReminderPlanner.Window(3600, 0),
            DrinkReminderPlanner.Window(86_401, 3600), DrinkReminderPlanner.Window(3600, 3600), DrinkReminderPlanner.Window(-1, 86_400))) {
            assertFalse(bad.isUsable)
            assertEquals(0, bad.durationSec)
            assertTrue(fires(input(window = bad)).isEmpty())
        }
        for (frequency in listOf(0, -1, 1441, Int.MAX_VALUE)) assertTrue(fires(input(frequency = frequency)).isEmpty())
    }

    @Test fun pastAndExactlyNowSlotsAreSkipped() {
        assertEquals(listOf(time(14), time(16), time(18), time(20), tomorrow(8)), fires(input()))
        assertEquals(time(16), fires(input(now = time(14))).first())
        assertTrue(DrinkReminderPlanner.plan(input()).all { it.fireAt > time(13, 5) })
    }

    @Test fun stableIdentifiersAndDatesDoNotSlideOnEverySync() {
        val first = DrinkReminderPlanner.plan(input())
        val later = DrinkReminderPlanner.plan(input(now = time(13, 10), drinks = listOf(time(13, 9).epochSecond)))
        assertEquals(first.map { it.fireAt }, later.map { it.fireAt })
        assertEquals(first.map { it.identifier }, later.map { it.identifier })
        assertEquals(first.map { "hydrocap.drink.${it.fireAt.epochSecond}" }, first.map { it.identifier })
    }

    @Test fun behindTargetIsStrictProRataAndZeroElapsedNeverBehind() {
        assertTrue(DrinkReminderPlanner.isBehind(2450.0, 1000.0, window, 50_400))
        assertFalse(DrinkReminderPlanner.isBehind(2450.0, 1100.0, window, 50_400))
        assertFalse(DrinkReminderPlanner.isBehind(2450.0, 0.0, window, 28_800))
        assertTrue(DrinkReminderPlanner.isBehind(2450.0, 2400.0, window, 86_400))
        assertEquals(0.0, DrinkReminderPlanner.elapsedFraction(window, 20_000), 0.0)
        assertEquals(1.0, DrinkReminderPlanner.elapsedFraction(window, 90_000), 0.0)
        val simple = DrinkReminderPlanner.Window(28_800, 72_000)
        assertFalse(DrinkReminderPlanner.isBehind(2400.0, 1200.0, simple, 50_400))
        assertTrue(DrinkReminderPlanner.isBehind(2400.0, -10.0, simple, 50_400))
    }

    @Test fun onlyBehindUsesSameRuleTodayAndFirstEligibleTomorrow() {
        assertEquals(listOf(time(16), time(18), time(20), tomorrow(10)), fires(input(consumed = 1200.0, onlyBehind = true)))
        assertEquals(listOf(tomorrow(10)), fires(input(consumed = 2500.0, onlyBehind = true)))
        val early = DrinkReminderPlanner.Window(86_400, 21_600)
        assertEquals(listOf(tomorrow(2)), fires(input(now = time(23), window = early, onlyBehind = true)))
    }

    @Test fun overnightProgressDoesNotResetInEvening() {
        val overnight = DrinkReminderPlanner.Window(79_200, 28_800)
        assertEquals(0.1, DrinkReminderPlanner.elapsedFraction(overnight, 3600), 0.0)
        assertEquals(0.8, DrinkReminderPlanner.elapsedFraction(overnight, 28_800), 0.0)
        assertEquals(0.8, DrinkReminderPlanner.elapsedFraction(overnight, 75_600), 0.0)
        assertEquals(0.8, DrinkReminderPlanner.elapsedFraction(overnight, 79_200), 0.0)
        assertEquals(0.9, DrinkReminderPlanner.elapsedFraction(overnight, 82_800), 0.0)
        assertEquals(1.0, DrinkReminderPlanner.elapsedFraction(overnight, 86_400), 0.0)
        assertEquals(listOf(time(23), tomorrow(1)), fires(input(now = time(21), window = overnight, frequency = 60, target = 1000.0, consumed = 800.0, onlyBehind = true)))
    }

    @Test fun pendingIsCappedAtEightUniqueSortedDates() {
        val planned = DrinkReminderPlanner.plan(input(now = time(7), window = DrinkReminderPlanner.Window(28_800, 79_200), frequency = 60))
        assertEquals(8, planned.size)
        assertEquals(DrinkReminderPlanner.maxPending, planned.size)
        assertEquals(time(15), planned.last().fireAt)
        assertEquals(8, planned.map { it.identifier }.toSet().size)
        assertEquals(planned.map { it.fireAt }.sorted(), planned.map { it.fireAt })
    }

    @Test fun disabledNoTargetOrNonFiniteInputsPlanNothing() {
        assertTrue(fires(input(enabled = false)).isEmpty())
        for (target in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) assertTrue(fires(input(target = target)).isEmpty())
        for (consumed in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) assertTrue(fires(input(consumed = consumed)).isEmpty())
        assertFalse(DrinkReminderPlanner.isBehind(Double.NaN, 0.0, window, 50_400))
        assertFalse(DrinkReminderPlanner.isBehind(2450.0, Double.NaN, window, 50_400))
    }

    @Test fun queryFailureIsNotSyntheticZeroIncludingTomorrow() {
        assertTrue(fires(input(consumed = null)).isEmpty())
        assertTrue(fires(input(consumed = null, onlyBehind = true)).isEmpty())
        assertTrue(DrinkReminderPlanner.body(input(consumed = null), tomorrow = false).contains("unavailable"))
        assertFalse(fires(input(consumed = 0.0)).isEmpty())
    }

    @Test fun bodyExplicitlyLabelsLastSyncedKnownBottleSnapshot() {
        val noDrinks = DrinkReminderPlanner.plan(input(consumed = 800.0))
        assertEquals("Last sync at 13:05: 0.8 L logged from your bottle toward 2.45 L. Take a sip if you need one.", noDrinks.first().body)
        assertEquals("Time to drink", noDrinks.first().title)
        assertEquals("Check your bottle progress today. Your drink goal is 2.45 L.", noDrinks.last().body)
        val whole = DrinkReminderPlanner.plan(input(target = 2000.0, consumed = 1000.0))
        assertTrue(whole.first().body.contains("1.0 L logged from your bottle toward 2.0 L"))
        assertTrue(DrinkReminderPlanner.body(input(consumed = 1235.0), tomorrow = false).contains("1.24 L"))
    }

    @Test fun windowLabelsAndSupportedFrequenciesMatchCapSettings() {
        assertEquals("Between 08:00 and 21:45", DrinkReminderPlanner.windowLabel(window))
        assertEquals("Between 08:00 and 22:00", DrinkReminderPlanner.windowLabel(DrinkReminderPlanner.Window.fallback))
        assertEquals("Between 22:00 and 00:00", DrinkReminderPlanner.windowLabel(DrinkReminderPlanner.Window(79_200, 86_400)))
        assertEquals(listOf(60, 90, 120, 180), DrinkReminderPlanner.frequencyChoicesMinutes)
        assertEquals(120, DrinkReminderPlanner.defaultFrequencyMinutes)
    }

    @Test fun dayRangesUseLocalMidnightsAndDstLengths() {
        for ((at, hours) in listOf(date(2026, 3, 29, 12) to 23L, date(2026, 10, 25, 12) to 25L, time(12) to 24L)) {
            val range = DrinkReminderPlanner.dayRange(at, zone)
            assertEquals(0, range.start.atZone(zone).hour)
            assertEquals(0, range.end.atZone(zone).hour)
            assertEquals(hours, Duration.between(range.start, range.end).toHours())
            assertTrue(range.contains(range.start))
            assertTrue(range.contains(at))
            assertFalse(range.contains(range.end))
            assertFalse(range.contains(range.start.minusNanos(1)))
        }
    }

    @Test fun springGapUsesFirstValidWallTimeNotElapsedMidnightSeconds() {
        val at = date(2026, 3, 29, 0)
        val input = input(now = at, window = DrinkReminderPlanner.Window(5400, 19_800), frequency = 60)
        assertEquals(listOf(date(2026, 3, 29, 1, 30), date(2026, 3, 29, 3), date(2026, 3, 29, 3, 30),
            date(2026, 3, 29, 4, 30), date(2026, 3, 30, 1, 30)), fires(input))
    }

    @Test fun dstResolvedSlotsDeduplicateAndRecheckStopExclusive() {
        val at = date(2026, 3, 29, 0)
        assertEquals(listOf(date(2026, 3, 29, 1), date(2026, 3, 29, 3), date(2026, 3, 29, 4), date(2026, 3, 30, 1)),
            fires(input(now = at, window = DrinkReminderPlanner.Window(3600, 18_000), frequency = 60)))
        assertEquals(listOf(date(2026, 3, 29, 1), date(2026, 3, 30, 1)),
            fires(input(now = at, window = DrinkReminderPlanner.Window(3600, 10_800), frequency = 60)))
    }

    @Test fun fallOverlapUsesFirstOccurrenceOnly() {
        val wall = LocalDateTime.of(2026, 10, 25, 2, 30).atZone(zone)
        val first = wall.withEarlierOffsetAtOverlap().toInstant()
        val second = wall.withLaterOffsetAtOverlap().toInstant()
        val overlapWindow = DrinkReminderPlanner.Window(5400, 16_200)
        val planned = fires(input(now = date(2026, 10, 25, 0), window = overlapWindow, frequency = 60))
        assertEquals(listOf(date(2026, 10, 25, 1, 30), first, date(2026, 10, 25, 3, 30), date(2026, 10, 26, 1, 30)), planned)
        assertFalse(planned.contains(second))
        val afterFirst = LocalDateTime.of(2026, 10, 25, 2, 40).atZone(zone).withEarlierOffsetAtOverlap().toInstant()
        assertEquals(date(2026, 10, 25, 3, 30), fires(input(now = afterFirst, window = overlapWindow, frequency = 60)).first())
    }

    @Test fun tomorrowUsesCalendarDateAndSameDstWallClockPolicy() {
        val planned = fires(input(now = date(2026, 3, 28, 23), window = DrinkReminderPlanner.Window(9000, 19_800), frequency = 60))
        assertEquals(listOf(date(2026, 3, 29, 3)), planned)
        assertEquals(1, planned.size)
    }
}
