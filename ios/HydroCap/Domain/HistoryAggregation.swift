import Foundation

/// Calendar-day ranges, grouped into hours (Today) / days / weeks / months.
/// Edge buckets retain calendar coverage; unused periods plot as gaps.
/// Free of SwiftUI/Charts so the same math drives the chart, list and tests.
nonisolated enum HistoryAggregation {
    nonisolated enum Range: String, Sendable, CaseIterable, Equatable {
        case day = "1d"
        case week = "7d"
        case month = "30d"
        case quarter = "90d"
        case year = "1y"

        var label: String {
            switch self {
            case .day: "1 D"
            case .week: "7 D"
            case .month: "30 D"
            case .quarter: "90 D"
            case .year: "1 Y"
            }
        }

        var unit: Calendar.Component {
            switch self {
            case .day: .hour
            case .week, .month: .day
            case .quarter: .weekOfYear
            case .year: .month
            }
        }

        var scrolls: Bool { self != .day && self != .week }

        /// Display density only, never the definition of the selected range.
        var visibleBuckets: Int {
            switch self {
            case .day: 24
            case .week: 7
            case .month: 10
            case .quarter: 9
            case .year: 8
            }
        }
    }

    nonisolated struct Bucket: Sendable, Equatable, Identifiable {
        /// Covered calendar interval [start, end), clipped at both range edges.
        let start: Date
        let end: Date
        /// Calendar coverage is retained for labels, never used as the divisor.
        let dayCount: Int
        let recordedDayCount: Int
        /// Sum of the days whose recorded total is positive (raw drinks are untouched).
        let ml: Double

        var id: Date { start }
        var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
        /// No used days means no average, not a measured zero.
        var averagePerDayMl: Double? {
            recordedDayCount > 0 ? ml / Double(recordedDayCount) : nil
        }

        func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// A missing bucket breaks a line/area series instead of drawing a fake
    /// zero or interpolating through a period in which the bottle was unused.
    nonisolated struct PlotPoint: Identifiable, Sendable {
        let bucket: Bucket
        let averagePerDayMl: Double
        let series: Int
        var id: Date { bucket.id }
    }

    static func plotPoints(buckets: [Bucket]) -> [PlotPoint] {
        var series = 0
        var points: [PlotPoint] = []
        for bucket in buckets {
            guard let average = bucket.averagePerDayMl, average.isFinite, average >= 0 else {
                series += 1
                continue
            }
            points.append(PlotPoint(bucket: bucket, averagePerDayMl: average, series: series))
        }
        return points
    }

    nonisolated struct Summary: Sendable, Equatable {
        let averagePerDayMl: Double?
        let recordedDayCount: Int
        let bestDay: (day: Date, ml: Double)?
        let daysOnTarget: Int
        let totalMl: Double

        static func == (lhs: Summary, rhs: Summary) -> Bool {
            lhs.averagePerDayMl == rhs.averagePerDayMl
                && lhs.recordedDayCount == rhs.recordedDayCount
                && lhs.bestDay?.day == rhs.bestDay?.day
                && lhs.bestDay?.ml == rhs.bestDay?.ml
                && lhs.daysOnTarget == rhs.daysOnTarget
                && lhs.totalMl == rhs.totalMl
        }
    }

    /// 7/30/90 calendar days through today. A rolling year is explicitly
    /// [start of tomorrow minus one calendar year, start of tomorrow).
    /// Calendar arithmetic handles month lengths, leap years and DST; neither
    /// boundary is rounded to a week or month for chart presentation.
    static func rangeStart(range: Range, now: Date, calendar: Calendar) -> Date {
        let end = rangeEnd(range: range, now: now, calendar: calendar)
        switch range {
        case .day: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: end) ?? end
        case .month: return calendar.date(byAdding: .day, value: -30, to: end) ?? end
        case .quarter: return calendar.date(byAdding: .day, value: -90, to: end) ?? end
        case .year: return calendar.date(byAdding: .year, value: -1, to: end) ?? end
        }
    }

    /// Calendar coverage ends at tomorrow's midnight. Event admission has a
    /// separate inclusive `now` cutoff, so later-today events cannot leak in.
    static func rangeEnd(range: Range, now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Shared admission predicate for plotted totals, summaries and day lists.
    static func eventsInRange(events: [DrinkEvent], range: Range, now: Date, calendar: Calendar) -> [DrinkEvent] {
        let start = rangeStart(range: range, now: now, calendar: calendar)
        return events.filter {
            let date = Date(timeIntervalSince1970: TimeInterval($0.timestamp))
            return date >= start && date <= now
        }
    }

    static func buckets(events: [DrinkEvent], range: Range, now: Date, calendar: Calendar) -> [Bucket] {
        aggregate(events: events, range: range, unit: range.unit, now: now, calendar: calendar)
    }

    static func dailyTotals(events: [DrinkEvent], range: Range, now: Date, calendar: Calendar) -> [Bucket] {
        aggregate(events: events, range: range, unit: .day, now: now, calendar: calendar)
    }

    private static func aggregate(events: [DrinkEvent], range: Range, unit: Calendar.Component, now: Date, calendar: Calendar) -> [Bucket] {
        if unit == .hour { return hourlyBuckets(events: events, now: now, calendar: calendar) }
        let start = rangeStart(range: range, now: now, calendar: calendar)
        let end = rangeEnd(range: range, now: now, calendar: calendar)
        // Sum by local calendar day first: several sips on one day must
        // count as ONE used day. Zero totals (explicit or missing) never count.
        var daily: [Date: Double] = [:]
        for event in eventsInRange(events: events, range: range, now: now, calendar: calendar) {
            let date = Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            daily[calendar.startOfDay(for: date), default: 0] += event.volumeMl
        }
        var totals: [Date: Double] = [:]
        var recordedDays: [Date: Int] = [:]
        for (day, total) in daily where total > 0 {
            let key = bucketStart(of: day, unit: unit, calendar: calendar)
            totals[key, default: 0] += total
            recordedDays[key, default: 0] += 1
        }
        var result: [Bucket] = []
        var cursor = start
        while cursor < end {
            let naturalStart = bucketStart(of: cursor, unit: unit, calendar: calendar)
            guard let naturalEnd = calendar.date(byAdding: unit, value: 1, to: naturalStart) else { break }
            let coveredEnd = min(naturalEnd, end)
            guard coveredEnd > cursor else { break }
            let days = calendar.dateComponents([.day], from: cursor, to: coveredEnd).day ?? 0
            result.append(Bucket(start: cursor, end: coveredEnd, dayCount: days,
                recordedDayCount: recordedDays[naturalStart] ?? 0, ml: totals[naturalStart] ?? 0))
            cursor = coveredEnd
        }
        return result
    }

    /// Today's detail uses measured ml in each hour, not an hourly average or
    /// a divided daily goal. Calendar hour boundaries retain both repeated DST
    /// hours; absent readings remain gaps. Daily summary still uses `.day`.
    private static func hourlyBuckets(events: [DrinkEvent], now: Date, calendar: Calendar) -> [Bucket] {
        let start = calendar.startOfDay(for: now)
        let end = rangeEnd(range: .day, now: now, calendar: calendar)
        var totals: [Date: Double] = [:]
        for event in eventsInRange(events: events, range: .day, now: now, calendar: calendar) {
            let date = Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            totals[bucketStart(of: date, unit: .hour, calendar: calendar), default: 0] += event.volumeMl
        }
        var result: [Bucket] = []
        var cursor = start
        while cursor < end {
            guard let interval = calendar.dateInterval(of: .hour, for: cursor), interval.end > cursor else { break }
            let coveredEnd = min(interval.end, end)
            let total = max(0, totals[interval.start] ?? 0)
            result.append(Bucket(start: cursor, end: coveredEnd, dayCount: 1,
                recordedDayCount: total > 0 ? 1 : 0, ml: total))
            cursor = coveredEnd
        }
        return result
    }

    /// Whole-range average is weighted by recorded DAYS, not by the number
    /// of weeks/months or sips. Days with zero intake are excluded completely.
    static func summary(events: [DrinkEvent], range: Range, now: Date, calendar: Calendar, targetMl: Double) -> Summary {
        let days = dailyTotals(events: events, range: range, now: now, calendar: calendar).filter { $0.recordedDayCount > 0 }
        let total = days.reduce(0) { $0 + $1.ml }
        let best = days.max { $0.ml < $1.ml }
        return Summary(
            averagePerDayMl: days.isEmpty ? nil : total / Double(days.count),
            recordedDayCount: days.count,
            bestDay: best.map { ($0.start, $0.ml) },
            daysOnTarget: targetMl > 0 ? days.filter { $0.ml >= targetMl }.count : 0,
            totalMl: total,
        )
    }

    /// Calendar-local natural boundary, respecting the locale's week rules.
    static func bucketStart(of date: Date, unit: Calendar.Component, calendar: Calendar) -> Date {
        calendar.dateInterval(of: unit, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Auto follows the finite plotted peak with 10% headroom, not the daily
    /// goal. Hourly detail always uses Auto, including legacy fixed settings.
    /// Only an empty/all-zero series uses the neutral 0...100 ml domain.
    static func yUpperBound(buckets: [Bucket], targetMl: Double, fixedToTarget: Bool, hourly: Bool = false) -> Double {
        let maxMl = plotPoints(buckets: buckets).map(\.averagePerDayMl).max() ?? 0
        if !hourly, fixedToTarget, targetMl.isFinite, targetMl > 0 {
            // Preserve the explicit non-hourly goal scale without clipping data.
            return max(paddedUpperBound(targetMl, factor: 1.2), maxMl)
        }
        return maxMl > 0 ? paddedUpperBound(maxMl, factor: 1.1) : 100
    }

    /// A daily goal is never an hourly requirement or an off-chart rule.
    static func showsGoalRule(targetMl: Double, upperBound: Double, hourly: Bool = false) -> Bool {
        !hourly && targetMl.isFinite && targetMl > 0
            && upperBound.isFinite && upperBound > 0 && targetMl <= upperBound
    }

    private static func paddedUpperBound(_ value: Double, factor: Double) -> Double {
        let padded = value * factor
        return padded.isFinite ? padded : .greatestFiniteMagnitude
    }
}
