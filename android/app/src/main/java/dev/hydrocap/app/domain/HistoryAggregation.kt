package dev.hydrocap.app.domain

import dev.hydrocap.app.data.DrinkEvent
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/** Calendar-local coverage; positive used-day averages, never cumulative chart values. */
object HistoryAggregation {
    enum class Unit { HOUR, DAY, WEEK, MONTH }
    enum class Range(
        val rawValue: String,
        val label: String,
        val unit: Unit,
        val scrolls: Boolean,
        val visibleBuckets: Int,
    ) {
        DAY("1d", "1 D", Unit.HOUR, false, 24),
        WEEK("7d", "7 D", Unit.DAY, false, 7),
        MONTH("30d", "30 D", Unit.DAY, true, 10),
        QUARTER("90d", "90 D", Unit.WEEK, true, 9),
        YEAR("1y", "1 Y", Unit.MONTH, true, 8);

        companion object {
            fun fromRawValue(value: String): Range? = entries.firstOrNull { it.rawValue == value }
        }
    }

    data class Bucket(
        val start: Instant,
        val end: Instant,
        val dayCount: Int,
        val recordedDayCount: Int,
        val ml: Double,
    ) {
        val id: Instant get() = start
        val midpoint: Instant get() = start.plus(Duration.between(start, end).dividedBy(2))
        val averagePerDayMl: Double? get() = if (recordedDayCount > 0) ml / recordedDayCount else null
        fun contains(date: Instant): Boolean = date >= start && date < end
    }

    data class PlotPoint(val bucket: Bucket, val averagePerDayMl: Double, val series: Int) {
        val id: Instant get() = bucket.id
    }
    data class BestDay(val day: Instant, val ml: Double)
    data class Summary(
        val averagePerDayMl: Double?,
        val recordedDayCount: Int,
        val bestDay: BestDay?,
        val daysOnTarget: Int,
        val totalMl: Double,
    )

    fun rangeStart(range: Range, now: Instant, zoneId: ZoneId): Instant {
        val today = now.atZone(zoneId).toLocalDate()
        val tomorrow = today.plusDays(1)
        val start = when (range) {
            Range.DAY -> today
            Range.WEEK -> tomorrow.minusDays(7)
            Range.MONTH -> tomorrow.minusDays(30)
            Range.QUARTER -> tomorrow.minusDays(90)
            Range.YEAR -> tomorrow.minusYears(1)
        }
        return start.atStartOfDay(zoneId).toInstant()
    }

    fun rangeEnd(range: Range, now: Instant, zoneId: ZoneId): Instant =
        now.atZone(zoneId).toLocalDate().plusDays(1).atStartOfDay(zoneId).toInstant()

    /** The same inclusive-now predicate drives chart, summary and raw-record lists. */
    fun eventsInRange(events: List<DrinkEvent>, range: Range, now: Instant, zoneId: ZoneId): List<DrinkEvent> {
        val start = rangeStart(range, now, zoneId)
        return events.filter { event -> Instant.ofEpochSecond(event.timestamp).let { it >= start && it <= now } }
    }

    fun buckets(
        events: List<DrinkEvent>, range: Range, now: Instant, zoneId: ZoneId,
        locale: Locale = Locale.getDefault(),
    ): List<Bucket> = if (range.unit == Unit.HOUR) hourlyBuckets(events, now, zoneId, locale)
        else aggregate(events, range, range.unit, now, zoneId, locale)

    fun dailyTotals(
        events: List<DrinkEvent>, range: Range, now: Instant, zoneId: ZoneId,
        locale: Locale = Locale.getDefault(),
    ): List<Bucket> = aggregate(events, range, Unit.DAY, now, zoneId, locale)

    private fun aggregate(
        events: List<DrinkEvent>, range: Range, unit: Unit, now: Instant, zoneId: ZoneId, locale: Locale,
    ): List<Bucket> {
        val start = rangeStart(range, now, zoneId)
        val end = rangeEnd(range, now, zoneId)
        // Several sips on one local day count once. Zero/negative daily totals are not used days.
        val daily = mutableMapOf<LocalDate, Double>()
        for (event in eventsInRange(events, range, now, zoneId)) {
            val day = Instant.ofEpochSecond(event.timestamp).atZone(zoneId).toLocalDate()
            daily[day] = (daily[day] ?: 0.0) + event.volumeMl
        }
        val totals = mutableMapOf<Instant, Double>()
        val recordedDays = mutableMapOf<Instant, Int>()
        for ((day, total) in daily) {
            if (total <= 0 || total.isNaN()) continue
            val key = bucketStart(day.atStartOfDay(zoneId).toInstant(), unit, zoneId, locale)
            totals[key] = (totals[key] ?: 0.0) + total
            recordedDays[key] = (recordedDays[key] ?: 0) + 1
        }
        val result = mutableListOf<Bucket>()
        var cursor = start
        while (cursor < end) {
            val naturalStart = bucketStart(cursor, unit, zoneId, locale)
            val naturalDay = naturalStart.atZone(zoneId).toLocalDate()
            val nextDay = when (unit) {
                Unit.DAY -> naturalDay.plusDays(1)
                Unit.WEEK -> naturalDay.plusWeeks(1)
                Unit.MONTH -> naturalDay.plusMonths(1)
                Unit.HOUR -> error("Hourly detail uses distinct instant intervals")
            }
            val coveredEnd = minOf(nextDay.atStartOfDay(zoneId).toInstant(), end)
            if (coveredEnd <= cursor) break
            val days = ChronoUnit.DAYS.between(cursor.atZone(zoneId).toLocalDate(), coveredEnd.atZone(zoneId).toLocalDate()).toInt()
            result += Bucket(cursor, coveredEnd, days, recordedDays[naturalStart] ?: 0, totals[naturalStart] ?: 0.0)
            cursor = coveredEnd
        }
        return result
    }

    /** Timeline hour arithmetic retains both offset-distinct occurrences of repeated DST hours. */
    private fun hourlyBuckets(events: List<DrinkEvent>, now: Instant, zoneId: ZoneId, locale: Locale): List<Bucket> {
        val start = rangeStart(Range.DAY, now, zoneId)
        val end = rangeEnd(Range.DAY, now, zoneId)
        val totals = mutableMapOf<Instant, Double>()
        for (event in eventsInRange(events, Range.DAY, now, zoneId)) {
            val key = bucketStart(Instant.ofEpochSecond(event.timestamp), Unit.HOUR, zoneId, locale)
            totals[key] = (totals[key] ?: 0.0) + event.volumeMl
        }
        val result = mutableListOf<Bucket>()
        var cursor = start
        while (cursor < end) {
            val naturalStart = bucketStart(cursor, Unit.HOUR, zoneId, locale)
            val coveredEnd = minOf(naturalStart.atZone(zoneId).plusHours(1).toInstant(), end)
            if (coveredEnd <= cursor) break
            val total = maxOf(0.0, totals[naturalStart] ?: 0.0)
            result += Bucket(cursor, coveredEnd, 1, if (total > 0) 1 else 0, total)
            cursor = coveredEnd
        }
        return result
    }

    fun summary(
        events: List<DrinkEvent>, range: Range, now: Instant, zoneId: ZoneId,
        targetMl: Double, locale: Locale = Locale.getDefault(),
    ): Summary {
        val days = dailyTotals(events, range, now, zoneId, locale).filter { it.recordedDayCount > 0 }
        val total = days.sumOf { it.ml }
        val best = days.maxByOrNull { it.ml }
        return Summary(
            if (days.isEmpty()) null else total / days.size,
            days.size, best?.let { BestDay(it.start, it.ml) },
            if (targetMl > 0) days.count { it.ml >= targetMl } else 0, total,
        )
    }

    fun bucketStart(date: Instant, unit: Unit, zoneId: ZoneId, locale: Locale = Locale.getDefault()): Instant {
        val local = date.atZone(zoneId)
        // Foundation's Gregorian hour interval subtracts the local minute/second
        // on the timeline. Unlike setting minute=0, this also preserves its
        // partial-hour boundaries in zones with 30-minute DST transitions.
        if (unit == Unit.HOUR) return date.minusSeconds((local.minute * 60 + local.second).toLong()).minusNanos(local.nano.toLong())
        val day = local.toLocalDate()
        val naturalDay = when (unit) {
            Unit.DAY -> day
            Unit.WEEK -> day.with(TemporalAdjusters.previousOrSame(WeekFields.of(locale).firstDayOfWeek))
            Unit.MONTH -> day.withDayOfMonth(1)
            Unit.HOUR -> error("Handled above")
        }
        return naturalDay.atStartOfDay(zoneId).toInstant()
    }

    fun plotPoints(buckets: List<Bucket>): List<PlotPoint> {
        var series = 0
        return buildList {
            for (bucket in buckets) {
                val average = bucket.averagePerDayMl
                if (average == null || !average.isFinite() || average < 0) series++ else add(PlotPoint(bucket, average, series))
            }
        }
    }

    /** Auto follows the finite plotted peak with 10% headroom, never the daily goal.
     * Hourly detail always uses Auto, even for legacy fixed settings. Only an
     * empty/all-zero series uses the neutral 0..100 ml domain. */
    fun yUpperBound(buckets: List<Bucket>, targetMl: Double, fixedToTarget: Boolean, hourly: Boolean = false): Double {
        val maxMl = plotPoints(buckets).maxOfOrNull { it.averagePerDayMl } ?: 0.0
        if (!hourly && fixedToTarget && targetMl.isFinite() && targetMl > 0) {
            // Preserve the explicit non-hourly goal scale without clipping data.
            return maxOf(paddedUpperBound(targetMl, 1.2), maxMl)
        }
        return if (maxMl > 0) paddedUpperBound(maxMl, 1.1) else 100.0
    }

    /** A daily goal is never an hourly requirement or an off-chart rule. */
    fun showsGoalRule(targetMl: Double, upperBound: Double, hourly: Boolean = false): Boolean =
        !hourly && targetMl.isFinite() && targetMl > 0 &&
            upperBound.isFinite() && upperBound > 0 && targetMl <= upperBound

    private fun paddedUpperBound(value: Double, factor: Double): Double {
        val padded = value * factor
        return if (padded.isFinite()) padded else Double.MAX_VALUE
    }
}
