package dev.hydrocap.app.parity

import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.domain.HistoryAggregation
import dev.hydrocap.app.domain.HydrationTarget
import dev.hydrocap.app.notify.DrinkReminderPlanner
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/** Independent fixture expectations are real native executions of the frozen
 * iOS production sources, not copied expected arithmetic or fake APIs.
 * All inputs are explicitly synthetic and never enter Room/Health Connect. */
class IosReferenceParityTest {
    private fun rows(name: String): List<List<String>> =
        requireNotNull(javaClass.getResourceAsStream("/parity/$name")) { "Missing reference $name" }
            .bufferedReader().useLines { lines -> lines.filter { it.isNotBlank() && !it.startsWith("#") }
                .map { it.split('\t') }.toList() }

    private fun optional(value: String): Double? = when (value) {
        "nil" -> null
        "NaN" -> Double.NaN
        "Infinity" -> Double.POSITIVE_INFINITY
        else -> value.toDouble()
    }
    private fun sex(value: String): HydrationTarget.Sex? =
        value.takeUnless { it == "nil" }?.let { HydrationTarget.Sex.valueOf(it.uppercase(Locale.ROOT)) }
    private fun n(value: Number?) = value?.toString() ?: "nil"
    private fun compare(expectedName: String, actual: List<List<String>>) {
        val expected = rows(expectedName)
        assertEquals("$expectedName row count", expected.size, actual.size)
        expected.zip(actual).forEachIndexed { row, (want, got) ->
            assertEquals("$expectedName row$row columns $want/$got", want.size, got.size)
            want.zip(got).forEachIndexed { column, (w, g) ->
                val wn = w.toDoubleOrNull()
                val gn = g.toDoubleOrNull()
                if (wn != null && gn != null) assertEquals("$expectedName row$row column$column", wn, gn, 0.000001)
                else assertEquals("$expectedName row$row column$column", w, g)
            }
        }
    }

    @Test fun targetEstimateAndProvenanceMatchesExecutedIosReference() {
        val actual = rows("target-input.tsv").map { r ->
            val t = HydrationTarget.resolve(useEstimate = r[1].toBoolean(), overrideMl = r[2].toIntOrNull(),
                healthWeightKg = optional(r[3]), healthSex = sex(r[4]), manualWeightKg = optional(r[5]), manualSex = sex(r[6]))
            val basis = when (val b = t.basis) {
                is HydrationTarget.Basis.Weight -> listOf("weight", b.source.name.lowercase(Locale.ROOT), n(b.kg))
                is HydrationTarget.Basis.Sex -> listOf("sex", b.source.name.lowercase(Locale.ROOT), b.sex.name.lowercase(Locale.ROOT))
                HydrationTarget.Basis.Default -> listOf("default", "nil", "nil")
                HydrationTarget.Basis.Manual -> listOf("manual", "nil", "nil")
            }
            listOf(r[0], n(t.ml)) + basis
        }
        compare("target-expected.tsv", actual)
    }

    @Test fun calendarBucketsGapsHourlyDstAndWeightedMeansMatchExecutedIosReference() {
        val actual = mutableListOf<List<String>>()
        for (r in rows("history-input.tsv")) {
            val range = requireNotNull(HistoryAggregation.Range.fromRawValue(r[1]))
            val now = Instant.ofEpochSecond(r[2].toLong())
            val zone = ZoneId.of(r[3])
            val locale = Locale.forLanguageTag(r[4])
            val target = r[5].toDouble()
            val events = if (r[6] == "nil") emptyList() else r[6].split(';').map { pair ->
                val p = pair.split(':')
                DrinkEvent(p[0].toLong(), p[1].toDouble(), p[0].toLong(), "synthetic-parity")
            }
            val buckets = HistoryAggregation.buckets(events, range, now, zone, locale)
            val summary = HistoryAggregation.summary(events, range, now, zone, target, locale)
            val weeks = WeekFields.of(locale)
            // Foundation weekdays are Sunday=1; java.time is Monday=1.
            val firstWeekday = weeks.firstDayOfWeek.value % 7 + 1
            actual += listOf(r[0], "R", n(HistoryAggregation.rangeStart(range, now, zone).epochSecond),
                n(HistoryAggregation.rangeEnd(range, now, zone).epochSecond), n(firstWeekday), n(weeks.minimalDaysInFirstWeek))
            buckets.forEachIndexed { i, b -> actual += listOf(r[0], "B", n(i), n(b.start.epochSecond), n(b.end.epochSecond),
                n(b.dayCount), n(b.recordedDayCount), n(b.ml), n(b.averagePerDayMl)) }
            HistoryAggregation.plotPoints(buckets).forEachIndexed { i, p ->
                actual += listOf(r[0], "P", n(i), n(p.bucket.start.epochSecond), n(p.averagePerDayMl), n(p.series))
            }
            actual += listOf(r[0], "S", n(summary.averagePerDayMl), n(summary.recordedDayCount), n(summary.bestDay?.day?.epochSecond),
                n(summary.bestDay?.ml), n(summary.daysOnTarget), n(summary.totalMl))
            actual += listOf(r[0], "Y", n(HistoryAggregation.yUpperBound(buckets, target, false, range == HistoryAggregation.Range.DAY)),
                n(HistoryAggregation.yUpperBound(buckets, target, true, range == HistoryAggregation.Range.DAY)))
        }
        compare("history-expected.tsv", actual)
    }

    @Test fun reminderSlotsBehindRuleAndCalendarDaysMatchExecutedIosReference() {
        val actual = mutableListOf<List<String>>()
        for (r in rows("reminder-input.tsv")) {
            val now = Instant.ofEpochSecond(r[1].toLong())
            val zone = ZoneId.of(r[2])
            val window = DrinkReminderPlanner.Window(r[3].toInt(), r[4].toInt())
            val input = DrinkReminderPlanner.Input(enabled = r[8].toBoolean(), now = now, window = window,
                frequencyMinutes = r[5].toInt(), targetMl = r[6].toDouble(), consumedTodayMl = r[7].toDouble(),
                onlyWhenBehind = r[9].toBoolean(), zoneId = zone)
            actual += listOf(r[0], "W", window.isUsable.toString(), n(window.durationSec))
            val day = DrinkReminderPlanner.dayRange(now, zone)
            actual += listOf(r[0], "D", n(day.start.epochSecond), n(day.end.epochSecond))
            actual += listOf(r[0], "L", DrinkReminderPlanner.slotSecondsOfDay(window, input.frequencyMinutes).joinToString(";"))
            DrinkReminderPlanner.plan(input).forEachIndexed { i, reminder ->
                actual += listOf(r[0], "N", n(i), n(reminder.fireAt.epochSecond), reminder.identifier)
            }
        }
        compare("reminder-expected.tsv", actual)
    }
}
