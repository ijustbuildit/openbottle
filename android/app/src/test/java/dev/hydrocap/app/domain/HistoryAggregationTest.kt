package dev.hydrocap.app.domain

import dev.hydrocap.app.data.DrinkEvent
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

/** Every event here is synthetic; aggregation executes the actual production module. */
class HistoryAggregationTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private val locale = Locale.GERMANY
    private fun date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0): Instant =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant()
    private fun event(at: Instant, ml: Double) = DrinkEvent(at.epochSecond, ml, at.epochSecond, "synthetic-test")
    private val now = date(2026, 9, 30, 14)
    private fun buckets(events: List<DrinkEvent> = emptyList(), range: HistoryAggregation.Range = HistoryAggregation.Range.WEEK, at: Instant = now) =
        HistoryAggregation.buckets(events, range, at, zone, locale)
    private fun summary(events: List<DrinkEvent>, range: HistoryAggregation.Range = HistoryAggregation.Range.WEEK, at: Instant = now, target: Double = 2000.0) =
        HistoryAggregation.summary(events, range, at, zone, target, locale)

    @Test fun dayGroupsRecordedAmountsByHourAndExcludesFuture() {
        val events = listOf(event(date(2026, 9, 29, 23), 999.0), event(date(2026, 9, 30, 8, 5), 100.0),
            event(date(2026, 9, 30, 8, 45), 200.0), event(date(2026, 9, 30, 13, 20), 400.0), event(date(2026, 9, 30, 18), 999.0))
        val hours = buckets(events, HistoryAggregation.Range.DAY)
        assertEquals(24, hours.size)
        assertEquals(date(2026, 9, 30, 0), hours.first().start)
        assertEquals(date(2026, 10, 1, 0), hours.last().end)
        assertEquals(300.0, hours[8].ml, 0.0)
        assertEquals(400.0, hours[13].averagePerDayMl!!, 0.0)
        assertNull(hours[18].averagePerDayMl)
        assertEquals(700.0, hours.sumOf { it.ml }, 0.0)
        val summary = summary(events, HistoryAggregation.Range.DAY)
        assertEquals(1, summary.recordedDayCount)
        assertEquals(700.0, summary.averagePerDayMl!!, 0.0)
        assertEquals(440.0, HistoryAggregation.yUpperBound(hours, 2000.0, false, true), 0.001)
    }

    @Test fun dstDayHasTwentyThreeOrTwentyFiveDistinctHours() {
        val spring = buckets(range = HistoryAggregation.Range.DAY, at = date(2026, 3, 29))
        assertEquals(23, spring.size)
        assertFalse(spring.any { it.start.atZone(zone).hour == 2 })
        val wall = LocalDateTime.of(2026, 10, 25, 2, 10)
        val first = wall.atZone(zone).withEarlierOffsetAtOverlap().toInstant()
        val second = wall.atZone(zone).withLaterOffsetAtOverlap().toInstant()
        assertNotEquals(first, second)
        val fall = buckets(listOf(event(first, 100.0), event(second, 200.0)), HistoryAggregation.Range.DAY, date(2026, 10, 25))
        assertEquals(25, fall.size)
        assertEquals(listOf(100.0, 200.0), fall.filter { it.start.atZone(zone).hour == 2 }.map { it.ml })
        assertEquals(25, fall.map { it.id }.toSet().size)
        assertEquals(date(2026, 10, 26, 0), fall.last().end)
        assertTrue(fall.zipWithNext().all { (a, b) -> a.end == b.start })
    }

    @Test fun halfHourDstIntervalsMatchNativeFoundationHourBoundaries() {
        val halfHourZone = ZoneId.of("Australia/Lord_Howe")
        // Independently observed with native Foundation Calendar execution.
        for (at in listOf(
            Instant.parse("2026-10-03T15:40:00Z"), // 02:40 +11 after spring gap
            Instant.parse("2026-04-04T15:10:00Z"), // 01:40 +10:30 in repeated portion
        )) {
            assertEquals(at.minusSeconds(40 * 60L), HistoryAggregation.bucketStart(at, HistoryAggregation.Unit.HOUR, halfHourZone, locale))
            val result = HistoryAggregation.buckets(listOf(event(at, 123.0)), HistoryAggregation.Range.DAY, at.plusSeconds(3600), halfHourZone, locale)
            assertEquals(123.0, result.sumOf { it.ml }, 0.0)
            assertTrue(result.zipWithNext().all { (a, b) -> a.end == b.start })
        }
    }

    @Test fun weekAndMonthAreExactCalendarDaysThroughToday() {
        val week = buckets()
        assertEquals(7, week.size)
        assertEquals(date(2026, 9, 24, 0), week.first().start)
        assertEquals(date(2026, 9, 30, 0), week.last().start)
        assertTrue(week.all { it.averagePerDayMl == null })
        val month = buckets(range = HistoryAggregation.Range.MONTH)
        assertEquals(30, month.size)
        assertEquals(date(2026, 9, 1, 0), month.first().start)
    }

    @Test fun quarterCoversExactlyNinetyDaysOnEveryWeekday() {
        for (offset in 0..6) {
            val at = LocalDate.of(2026, 9, 28).plusDays(offset.toLong()).atTime(12, 0).atZone(zone).toInstant()
            val start = LocalDate.of(2026, 7, 1).plusDays(offset.toLong()).atStartOfDay(zone).toInstant()
            val events = listOf(event(start.minusSeconds(1), 999.0), event(start, 100.0), event(at, 200.0), event(at.plusSeconds(1), 999.0))
            val result = buckets(events, HistoryAggregation.Range.QUARTER, at)
            assertEquals(start, HistoryAggregation.rangeStart(HistoryAggregation.Range.QUARTER, at, zone))
            assertEquals(start, result.first().start)
            assertEquals(90, result.sumOf { it.dayCount })
            assertEquals(300.0, result.sumOf { it.ml }, 0.0)
            assertEquals(if (offset >= 5) 13 else 14, result.size)
            assertTrue(result.drop(1).all { it.start.atZone(zone).dayOfWeek == DayOfWeek.MONDAY })
            assertEquals(90, HistoryAggregation.dailyTotals(events, HistoryAggregation.Range.QUARTER, at, zone, locale).size)
        }
    }

    @Test fun rollingYearIncludesClippedEdgeMonths() {
        val result = buckets(range = HistoryAggregation.Range.YEAR, at = date(2026, 9, 15))
        assertEquals(13, result.size)
        assertEquals(date(2025, 9, 16, 0), result.first().start)
        assertEquals(15, result.first().dayCount)
        assertEquals(date(2026, 9, 1, 0), result.last().start)
        assertEquals(date(2026, 9, 16, 0), result.last().end)
        assertEquals(15, result.last().dayCount)
        assertEquals(365, result.sumOf { it.dayCount })
        val endOfMonth = buckets(range = HistoryAggregation.Range.YEAR)
        assertEquals(12, endOfMonth.size)
        assertEquals(date(2025, 10, 1, 0), endOfMonth.first().start)
    }

    @Test fun rollingYearHonorsLeapDaysAndMonthLengths() {
        val cases = listOf(Triple(date(2024, 2, 29), date(2023, 3, 1, 0), 366),
            Triple(date(2025, 2, 28), date(2024, 3, 1, 0), 365),
            Triple(date(2025, 2, 27), date(2024, 2, 28, 0), 366),
            Triple(date(2024, 3, 15), date(2023, 3, 16, 0), 366))
        for ((at, start, count) in cases) {
            val result = buckets(range = HistoryAggregation.Range.YEAR, at = at)
            assertEquals(start, result.first().start)
            assertEquals(count, result.sumOf { it.dayCount })
        }
        val months = buckets(range = HistoryAggregation.Range.YEAR, at = date(2024, 3, 15))
        assertEquals(29, months.first { it.start == date(2024, 2, 1, 0) }.dayCount)
        assertEquals(31, months.first { it.start == date(2024, 1, 1, 0) }.dayCount)
        assertEquals(30, months.first { it.start == date(2023, 4, 1, 0) }.dayCount)
    }

    @Test fun firstSecondIncludedAndOutsideAndFutureEventsExcluded() {
        val events = listOf(event(date(2026, 9, 30, 8), 250.0), event(date(2026, 9, 30, 13, 30), 300.0),
            event(date(2026, 9, 24, 0), 100.0), event(date(2026, 9, 24, 0).minusSeconds(1), 999.0), event(date(2026, 10, 1, 0), 999.0))
        val result = buckets(events)
        assertEquals(550.0, result.last().ml, 0.0)
        assertEquals(100.0, result.first().ml, 0.0)
        assertEquals(650.0, result.sumOf { it.ml }, 0.0)
    }

    @Test fun allRangesShareChartSummaryAndListAdmission() {
        for (range in HistoryAggregation.Range.entries) {
            val start = HistoryAggregation.rangeStart(range, now, zone)
            val included = listOf(event(start, 100.0), event(now, 200.0))
            val events = included + listOf(event(start.minusSeconds(1), 999.0), event(now.plusSeconds(1), 999.0), event(date(2026, 10, 1), 999.0))
            assertEquals(included, HistoryAggregation.eventsInRange(events, range, now, zone))
            assertEquals(300.0, buckets(events, range).sumOf { it.ml }, 0.0)
            assertEquals(300.0, summary(events, range, target = 500.0).totalMl, 0.0)
            assertEquals(0, summary(events, range, target = 500.0).daysOnTarget)
        }
    }

    @Test fun calendarDaysAcrossDstAreNotFixed86400Seconds() {
        for ((at, expectedHours) in listOf(date(2025, 3, 31) to 23L, date(2025, 10, 27) to 25L)) {
            val result = buckets(range = HistoryAggregation.Range.WEEK, at = at)
            assertTrue(result.all { it.start.atZone(zone).hour == 0 })
            assertTrue(result.any { Duration.between(it.start, it.end).toHours() == expectedHours })
        }
    }

    @Test fun summaryCountsUsedDaysOnceNotDrinks() {
        val events = listOf(event(date(2026, 9, 30, 8), 2100.0), event(date(2026, 9, 29, 8), 1000.0),
            event(date(2026, 9, 29, 18), 1000.0), event(date(2026, 9, 27, 8), 3000.0))
        val result = summary(events)
        assertEquals(7100.0, result.totalMl, 0.0)
        assertEquals(7100.0 / 3, result.averagePerDayMl!!, 0.001)
        assertEquals(3, result.recordedDayCount)
        assertEquals(HistoryAggregation.BestDay(date(2026, 9, 27, 0), 3000.0), result.bestDay)
        assertEquals(3, result.daysOnTarget)
        assertEquals(0, summary(events, target = 0.0).daysOnTarget)
    }

    @Test fun summaryForWeeklyChartStillCountsDailyGoals() {
        val events = listOf(event(date(2026, 9, 30, 8), 2500.0), event(date(2026, 9, 1, 8), 2500.0))
        assertEquals(2, summary(events, HistoryAggregation.Range.QUARTER).daysOnTarget)
    }

    @Test fun weeklyAndMonthlyPointsAreDailyAveragesNotPeriodSums() {
        for (range in listOf(HistoryAggregation.Range.QUARTER, HistoryAggregation.Range.YEAR)) {
            val at = date(2024, 3, 15)
            val days = HistoryAggregation.dailyTotals(emptyList(), range, at, zone, locale)
            val result = buckets(days.map { event(it.start, 2000.0) }, range, at)
            assertTrue(result.all { it.averagePerDayMl == 2000.0 })
            assertEquals(days.size, result.sumOf { it.recordedDayCount })
            assertTrue(result.all { it.contains(it.midpoint) && !it.contains(it.end) })
            assertEquals(2400.0, HistoryAggregation.yUpperBound(result, 2000.0, true), 0.0)
        }
    }

    @Test fun dstDaysCountOnceInUsedDayAverages() {
        for (at in listOf(date(2025, 3, 31), date(2025, 10, 27))) {
            val days = HistoryAggregation.dailyTotals(emptyList(), HistoryAggregation.Range.QUARTER, at, zone, locale)
            val events = days.map { event(it.start, 2000.0) }
            val result = buckets(events, HistoryAggregation.Range.QUARTER, at)
            assertEquals(90, result.sumOf { it.recordedDayCount })
            assertTrue(result.all { it.averagePerDayMl == 2000.0 })
            assertEquals(2000.0, summary(events, HistoryAggregation.Range.QUARTER, at).averagePerDayMl!!, 0.0)
        }
    }

    @Test fun zeroAndNegativeDailyTotalsAreUnused() {
        val events = listOf(event(date(2026, 9, 26, 8), 1000.0), event(date(2026, 9, 28, 8), 500.0),
            event(date(2026, 9, 28, 18), 1500.0), event(date(2026, 9, 29, 8), 0.0),
            event(date(2026, 9, 27, 8), 100.0), event(date(2026, 9, 27, 9), -100.0), event(date(2026, 9, 25), -20.0))
        val result = summary(events)
        assertEquals(1500.0, result.averagePerDayMl!!, 0.0)
        assertEquals(3000.0, result.totalMl, 0.0)
        assertEquals(2, result.recordedDayCount)
        assertEquals(1, result.daysOnTarget)
    }

    @Test fun wholeYearAverageWeightsUsedDaysNotMonthlyMeans() {
        val events = listOf(event(date(2026, 1, 10), 1000.0)) + (1..3).map { event(date(2026, 2, it), 3000.0) }
        val result = summary(events, HistoryAggregation.Range.YEAR)
        assertEquals(2500.0, result.averagePerDayMl!!, 0.0)
        assertEquals(10000.0, result.totalMl, 0.0)
        assertEquals(4, result.recordedDayCount)
    }

    @Test fun monthAverageDividesByOnlyTenRecordedDays() {
        val events = (1..10).map { event(date(2026, 1, it), 2000.0) } + event(date(2026, 1, 20), 0.0)
        val result = buckets(events, HistoryAggregation.Range.YEAR)
        val january = result.first { it.start == date(2026, 1, 1, 0) }
        assertEquals(20000.0, january.ml, 0.0)
        assertEquals(31, january.dayCount)
        assertEquals(10, january.recordedDayCount)
        assertEquals(2000.0, january.averagePerDayMl!!, 0.0)
        assertEquals(2400.0, HistoryAggregation.yUpperBound(result, 2000.0, true), 0.0)
    }

    @Test fun emptyPeriodsHaveNoAverageOrPlotValue() {
        for (range in HistoryAggregation.Range.entries) {
            val events = listOf(event(now, 0.0))
            val result = buckets(events, range)
            assertTrue(result.all { it.averagePerDayMl == null && it.recordedDayCount == 0 })
            assertTrue(HistoryAggregation.plotPoints(result).isEmpty())
            val summary = summary(events, range)
            assertNull(summary.averagePerDayMl)
            assertNull(summary.bestDay)
            assertEquals(0, summary.daysOnTarget)
        }
    }

    @Test fun missingPeriodsBreakLineAndAreaSeries() {
        val result = buckets(listOf(24, 25, 27, 28).map { event(date(2026, 9, it), 1000.0) })
        val points = HistoryAggregation.plotPoints(result)
        assertEquals(4, points.size)
        assertTrue(points.all { it.averagePerDayMl == 1000.0 })
        assertEquals(points[0].series, points[1].series)
        assertEquals(points[2].series, points[3].series)
        assertNotEquals(points[1].series, points[2].series)
    }

    @Test fun usedDaysFollowLocalMidnightNotEventCount() {
        val events = listOf(event(date(2026, 9, 29, 23, 30), 1000.0), event(date(2026, 9, 30, 0, 30), 3000.0))
        val local = summary(events)
        val utc = HistoryAggregation.summary(events, HistoryAggregation.Range.WEEK, now, ZoneId.of("UTC"), 2000.0, locale)
        assertEquals(2, local.recordedDayCount)
        assertEquals(2000.0, local.averagePerDayMl!!, 0.0)
        assertEquals(1, utc.recordedDayCount)
        assertEquals(4000.0, utc.averagePerDayMl!!, 0.0)
    }

    @Test fun timeZoneControlsAdmissionAndDailyGrouping() {
        val morning = date(2026, 9, 30, 8)
        val events = listOf(event(date(2026, 9, 29, 23, 30), 150.0))
        val berlin = buckets(events, at = morning)
        val auckland = HistoryAggregation.buckets(events, HistoryAggregation.Range.WEEK, morning, ZoneId.of("Pacific/Auckland"), locale)
        assertEquals(150.0, berlin[5].ml, 0.0)
        assertEquals(150.0, auckland[6].ml, 0.0)
        assertEquals(0.0, auckland[5].ml, 0.0)
    }

    @Test fun partialEdgeWeekDividesByItsUsedDaysOnly() {
        val start = HistoryAggregation.rangeStart(HistoryAggregation.Range.QUARTER, now, zone)
        val second = start.atZone(zone).plusDays(1).toInstant()
        val third = start.atZone(zone).plusDays(2).toInstant()
        val result = buckets(listOf(event(start.minusSeconds(1), 999.0), event(start, 1000.0), event(second, 3000.0), event(third, 0.0)), HistoryAggregation.Range.QUARTER).first()
        assertEquals(3, result.dayCount)
        assertEquals(2, result.recordedDayCount)
        assertEquals(4000.0, result.ml, 0.0)
        assertEquals(2000.0, result.averagePerDayMl!!, 0.0)
    }

    @Test fun weekBoundariesFollowExplicitLocale() {
        val german = buckets(range = HistoryAggregation.Range.QUARTER)
        val us = HistoryAggregation.buckets(emptyList(), HistoryAggregation.Range.QUARTER, now, zone, Locale.US)
        assertTrue(german.drop(1).all { it.start.atZone(zone).dayOfWeek == DayOfWeek.MONDAY })
        assertTrue(us.drop(1).all { it.start.atZone(zone).dayOfWeek == DayOfWeek.SUNDAY })
        assertEquals(90, us.sumOf { it.dayCount })
    }

    @Test fun yAxisUsesAveragesAndHourlyScaleNotDailyRequirement() {
        val low = listOf(HistoryAggregation.Bucket(now, date(2026, 10, 1, 0), 7, 5, 5000.0))
        assertEquals(2400.0, HistoryAggregation.yUpperBound(low, 2000.0, true), 0.0)
        assertEquals(100.0, HistoryAggregation.yUpperBound(emptyList(), 2000.0, false), 0.0)
        val high = listOf(low.single().copy(recordedDayCount = 1, ml = 3000.0))
        assertEquals(3000.0, HistoryAggregation.yUpperBound(high, 2000.0, true), 0.0)
        assertEquals(3300.0, HistoryAggregation.yUpperBound(high, 2000.0, false), 0.001)
        assertEquals(100.0, HistoryAggregation.yUpperBound(emptyList(), 2000.0, false, true), 0.0)
    }

    @Test fun hourlyAxisTracksLowPeaksDespiteLegacyFixedPreference() {
        val amounts = listOf(20.0, 50.0, 100.0)
        for (count in 1..amounts.size) {
            val events = amounts.take(count).mapIndexed { i, amount -> event(date(2026, 9, 30, 8 + i), amount) }
            val hours = buckets(events, HistoryAggregation.Range.DAY)
            for (goal in listOf(2000.0, 6000.0)) for (fixed in listOf(false, true)) {
                assertEquals(amounts[count - 1] * 1.1, HistoryAggregation.yUpperBound(hours, goal, fixed, true), 0.001)
            }
        }
    }

    @Test fun autoAxisUsesPlottedDailyMeanNotGoalOrPeriodTotal() {
        val bucket = HistoryAggregation.Bucket(now, now.plusSeconds(86400), 7, 2, 1200.0)
        assertEquals(600.0, bucket.averagePerDayMl!!, 0.0)
        for (goal in listOf(2000.0, 6000.0)) {
            assertEquals(660.0, HistoryAggregation.yUpperBound(listOf(bucket), goal, false), 0.001)
        }
        assertEquals(990.0, HistoryAggregation.yUpperBound(listOf(bucket.copy(ml = 1800.0)), 2000.0, false), 0.001)
    }

    @Test fun emptyZeroAndInvalidAxisValuesHaveSafeFiniteDomains() {
        fun bucket(ml: Double, usedDays: Int = 1) = HistoryAggregation.Bucket(now, now.plusSeconds(3600), 1, usedDays, ml)
        val invalid = listOf(bucket(Double.NaN), bucket(Double.POSITIVE_INFINITY), bucket(Double.NEGATIVE_INFINITY), bucket(-20.0), bucket(0.0), bucket(50000.0, 0))
        for (hourly in listOf(false, true)) {
            for (goal in listOf(2000.0, 6000.0, 0.0, -20.0, Double.NaN, Double.POSITIVE_INFINITY)) {
                for (empty in listOf(emptyList(), listOf(bucket(0.0)), invalid)) {
                    assertEquals(100.0, HistoryAggregation.yUpperBound(empty, goal, false, hourly), 0.0)
                    if (hourly) assertEquals(100.0, HistoryAggregation.yUpperBound(empty, goal, true, true), 0.0)
                }
                assertEquals(55.0, HistoryAggregation.yUpperBound(invalid + bucket(50.0), goal, false, hourly), 0.001)
            }
        }
        for (goal in listOf(0.0, -20.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertEquals(55.0, HistoryAggregation.yUpperBound(listOf(bucket(50.0)), goal, true), 0.001)
        }
        for (fixed in listOf(false, true)) {
            val upper = HistoryAggregation.yUpperBound(listOf(bucket(Double.MAX_VALUE)), Double.MAX_VALUE, fixed)
            assertTrue(upper.isFinite())
            assertEquals(Double.MAX_VALUE, upper, 0.0)
        }
    }

    @Test fun goalRuleRequiresANonHourlyGoalWithinTheFiniteDomain() {
        val bucket = HistoryAggregation.Bucket(now, now.plusSeconds(86400), 7, 2, 1200.0)
        val auto = HistoryAggregation.yUpperBound(listOf(bucket), 2000.0, false)
        assertFalse(HistoryAggregation.showsGoalRule(2000.0, auto))
        assertTrue(HistoryAggregation.showsGoalRule(600.0, auto))
        assertTrue(HistoryAggregation.showsGoalRule(auto, auto))
        assertFalse(HistoryAggregation.showsGoalRule(20.0, auto, true))
        val fixed = HistoryAggregation.yUpperBound(listOf(bucket), 2000.0, true)
        assertTrue(HistoryAggregation.showsGoalRule(2000.0, fixed))
        for (invalid in listOf(0.0, -20.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertFalse(HistoryAggregation.showsGoalRule(invalid, auto))
            assertFalse(HistoryAggregation.showsGoalRule(600.0, invalid))
        }
    }

    @Test fun invalidPlotValuesAreGapsWithoutChangingBucketAverages() {
        val amounts = listOf(20.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -20.0, 50.0)
        val buckets = amounts.mapIndexed { i, amount -> HistoryAggregation.Bucket(now.plusSeconds(i * 3600L), now.plusSeconds((i + 1) * 3600L), 1, 1, amount) }
        val points = HistoryAggregation.plotPoints(buckets)
        assertEquals(listOf(20.0, 50.0), points.map { it.averagePerDayMl })
        assertNotEquals(points.first().series, points.last().series)
        assertTrue(buckets[1].averagePerDayMl!!.isNaN())
        assertEquals(-20.0, buckets[4].averagePerDayMl!!, 0.0)
    }

    @Test fun rangeMetadataPreservesIosDisplayDensity() {
        assertEquals(listOf("1 D", "7 D", "30 D", "90 D", "1 Y"), HistoryAggregation.Range.entries.map { it.label })
        assertEquals(HistoryAggregation.Range.QUARTER, HistoryAggregation.Range.fromRawValue("90d"))
        assertNull(HistoryAggregation.Range.fromRawValue("invalid"))
        for (range in HistoryAggregation.Range.entries) {
            val count = buckets(range = range).size
            if (range.scrolls) assertTrue(range.visibleBuckets < count) else assertEquals(range.visibleBuckets, count)
        }
    }
}
