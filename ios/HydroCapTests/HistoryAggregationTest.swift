import Foundation
import Testing

@testable import HydroCap

@Suite("History aggregation")
struct HistoryAggregationTest {
    /// Synthetic calendar fixture: Berlin, Monday-first weeks.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ date: Date, _ ml: Double) -> DrinkEvent {
        DrinkEvent(timestamp: Int64(date.timeIntervalSince1970), volumeMl: ml, sourceLogTimestamp: Int64(date.timeIntervalSince1970), profileId: "test")
    }

    // Wednesday 2026-09-30 14:00 Berlin.
    private var now: Date { date(2026, 9, 30, 14) }

    @Test func dayViewGroupsTodaysDrinksByHour() {
        let events = [event(date(2026, 9, 29, 23), 999),
            event(date(2026, 9, 30, 8, 5), 100), event(date(2026, 9, 30, 8, 45), 200),
            event(date(2026, 9, 30, 13, 20), 400), event(date(2026, 9, 30, 18), 999)]
        let hours = HistoryAggregation.buckets(events: events, range: .day, now: now, calendar: calendar)
        #expect(hours.count == 24)
        #expect(hours.first?.start == date(2026, 9, 30, 0))
        #expect(hours.last?.end == date(2026, 10, 1, 0))
        #expect(hours[8].ml == 300)
        #expect(hours[13].ml == 400)
        #expect(hours[18].averagePerDayMl == nil)
        #expect(hours.reduce(0) { $0 + $1.ml } == 700)
        let summary = HistoryAggregation.summary(events: events, range: .day, now: now, calendar: calendar, targetMl: 2_000)
        #expect(summary.recordedDayCount == 1)
        #expect(summary.averagePerDayMl == 700)
        #expect(summary.totalMl == 700)
        #expect(abs(HistoryAggregation.yUpperBound(buckets: hours, targetMl: 2_000, fixedToTarget: false, hourly: true) - 440) < 0.001)
    }

    @Test func dayViewHandlesDstHourCountsAndRepeatedHours() {
        let spring = HistoryAggregation.buckets(events: [], range: .day, now: date(2026, 3, 29, 12), calendar: calendar)
        #expect(spring.count == 23)
        let fallNow = date(2026, 10, 25, 12)
        let first = calendar.date(bySettingHour: 2, minute: 10, second: 0, of: fallNow, matchingPolicy: .strict, repeatedTimePolicy: .first)!
        let second = calendar.date(bySettingHour: 2, minute: 10, second: 0, of: fallNow, matchingPolicy: .strict, repeatedTimePolicy: .last)!
        #expect(first != second)
        let fall = HistoryAggregation.buckets(events: [event(first, 100), event(second, 200)], range: .day, now: fallNow, calendar: calendar)
        #expect(fall.count == 25)
        let repeated = fall.filter { calendar.component(.hour, from: $0.start) == 2 }
        #expect(repeated.count == 2)
        #expect(repeated.map(\.ml) == [100, 200])
        #expect(Set(fall.map(\.start)).count == 25)
        #expect(fall.last?.end == date(2026, 10, 26, 0))
    }

    @Test func weekHasSevenDayBucketsEndingToday() {
        let buckets = HistoryAggregation.buckets(events: [], range: .week, now: now, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.first?.start == date(2026, 9, 24, 0))
        #expect(buckets.last?.start == date(2026, 9, 30, 0))
        #expect(buckets.allSatisfy { $0.ml == 0 })
    }

    @Test func monthHasThirtyDayBuckets() {
        let buckets = HistoryAggregation.buckets(events: [], range: .month, now: now, calendar: calendar)
        #expect(buckets.count == 30)
        #expect(buckets.first?.start == date(2026, 9, 1, 0))
        #expect(buckets.last?.start == date(2026, 9, 30, 0))
    }

    @Test(arguments: 0..<7)
    func quarterCoversExactlyNinetyDaysOnEveryWeekday(_ weekdayOffset: Int) {
        let now = calendar.date(byAdding: .day, value: weekdayOffset, to: date(2026, 9, 28))!
        let start = date(2026, 7, 1 + weekdayOffset, 0)
        let events = [event(start.addingTimeInterval(-1), 999), event(start, 100), event(now, 200), event(now.addingTimeInterval(1), 999)]
        let buckets = HistoryAggregation.buckets(events: events, range: .quarter, now: now, calendar: calendar)
        #expect(HistoryAggregation.rangeStart(range: .quarter, now: now, calendar: calendar) == start)
        #expect(buckets.first?.start == start)
        #expect(buckets.last?.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(buckets.reduce(0) { $0 + $1.dayCount } == 90)
        #expect(buckets.reduce(0) { $0 + $1.ml } == 300)
        #expect(buckets.count == (weekdayOffset >= 5 ? 13 : 14))
        #expect(buckets.dropFirst().allSatisfy { calendar.component(.weekday, from: $0.start) == 2 })
        #expect(HistoryAggregation.dailyTotals(events: events, range: .quarter, now: now, calendar: calendar).count == 90)
    }

    @Test func rollingYearIncludesPartialEdgeMonths() {
        let now = date(2026, 9, 15)
        let buckets = HistoryAggregation.buckets(events: [], range: .year, now: now, calendar: calendar)
        #expect(buckets.count == 13)
        #expect(buckets.first?.start == date(2025, 9, 16, 0))
        #expect(buckets.first?.dayCount == 15)
        #expect(buckets.last?.start == date(2026, 9, 1, 0))
        #expect(buckets.last?.end == date(2026, 9, 16, 0))
        #expect(buckets.last?.dayCount == 15)
        #expect(buckets.reduce(0) { $0 + $1.dayCount } == 365)
        let endOfMonth = HistoryAggregation.buckets(events: [], range: .year, now: self.now, calendar: calendar)
        #expect(endOfMonth.count == 12)
        #expect(endOfMonth.first?.start == date(2025, 10, 1, 0))
    }

    @Test func rollingYearHonorsLeapDaysAndMonthLengths() {
        for (now, start, dayCount) in [
            (date(2024, 2, 29), date(2023, 3, 1, 0), 366),
            (date(2025, 2, 28), date(2024, 3, 1, 0), 365),
            (date(2025, 2, 27), date(2024, 2, 28, 0), 366),
            (date(2024, 3, 15), date(2023, 3, 16, 0), 366),
        ] {
            let buckets = HistoryAggregation.buckets(events: [], range: .year, now: now, calendar: calendar)
            #expect(buckets.first?.start == start)
            #expect(buckets.reduce(0) { $0 + $1.dayCount } == dayCount)
        }
        let months = HistoryAggregation.buckets(events: [], range: .year, now: date(2024, 3, 15), calendar: calendar)
        #expect(months.first { $0.start == date(2024, 2, 1, 0) }?.dayCount == 29)
        #expect(months.first { $0.start == date(2024, 1, 1, 0) }?.dayCount == 31)
        #expect(months.first { $0.start == date(2023, 4, 1, 0) }?.dayCount == 30)
        let commonYear = HistoryAggregation.buckets(events: [], range: .year, now: date(2025, 3, 15), calendar: calendar)
        #expect(commonYear.first { $0.start == date(2025, 2, 1, 0) }?.dayCount == 28)
    }

    @Test func sumsPerBucketAndIgnoresEventsOutsideTheRange() {
        let events = [
            event(date(2026, 9, 30, 8), 250),
            event(date(2026, 9, 30, 13, 30), 300),
            event(date(2026, 9, 24, 0, 0), 100), // first second of the range
            event(date(2026, 9, 23, 23, 59), 999), // just before the range
            event(date(2026, 10, 1, 0, 0), 999), // tomorrow (never happens, but must not crash the sums)
        ]
        let buckets = HistoryAggregation.buckets(events: events, range: .week, now: now, calendar: calendar)
        #expect(buckets.last?.ml == 550)
        #expect(buckets.first?.ml == 100)
        #expect(buckets.reduce(0) { $0 + $1.ml } == 650)
    }

    @Test func dayBoundariesFollowTheCalendarTimeZoneAcrossDst() {
        // DST ends in Berlin on 2025-10-26: that day has 25 hours. An event at
        // 02:30 (the repeated hour) still lands on the 26th, not the 25th.
        let dstNow = date(2025, 10, 27, 10)
        let events = [event(date(2025, 10, 26, 2, 30), 200), event(date(2025, 10, 25, 23, 30), 100)]
        let buckets = HistoryAggregation.buckets(events: events, range: .week, now: dstNow, calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: buckets.map { ($0.start, $0.ml) })
        #expect(byDay[date(2025, 10, 26, 0)] == 200)
        #expect(byDay[date(2025, 10, 25, 0)] == 100)
        // Every bucket start is a local midnight, even across the DST change.
        for bucket in buckets {
            #expect(calendar.component(.hour, from: bucket.start) == 0)
        }
    }

    @Test func utcAndBerlinDisagreeOnTheDayOfALateEvening() {
        // 23:30 Berlin on the 29th is 21:30 UTC (still the 29th) but 10:30 on
        // the 30th in Auckland (NZDT). `now` = 08:00 Berlin on the 30th is the
        // 30th in all three zones, so "today" is the last bucket everywhere.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let morning = date(2026, 9, 30, 8)
        let evening = date(2026, 9, 29, 23, 30)
        let events = [event(evening, 150)]
        let berlinBuckets = HistoryAggregation.buckets(events: events, range: .week, now: morning, calendar: calendar)
        let utcBuckets = HistoryAggregation.buckets(events: events, range: .week, now: morning, calendar: utc)
        let aucklandBuckets = HistoryAggregation.buckets(events: events, range: .week, now: morning, calendar: auckland)
        #expect(berlinBuckets[5].ml == 150) // index 5 = the 29th (last = 30th)
        #expect(utcBuckets[5].ml == 150)
        #expect(aucklandBuckets[6].ml == 150) // already the 30th in Auckland
        #expect(aucklandBuckets[5].ml == 0)
    }

    @Test func summaryAveragesOverRecordedDaysAndCountsDaysOnTarget() {
        let events = [
            event(date(2026, 9, 30, 8), 2_100),
            event(date(2026, 9, 29, 8), 1_000),
            event(date(2026, 9, 29, 18), 1_000),
            event(date(2026, 9, 27, 8), 3_000),
        ]
        let summary = HistoryAggregation.summary(events: events, range: .week, now: now, calendar: calendar, targetMl: 2_000)
        #expect(summary.totalMl == 7_100)
        #expect(abs((summary.averagePerDayMl ?? .nan) - 7_100.0 / 3) < 0.001)
        #expect(summary.recordedDayCount == 3)
        #expect(summary.bestDay?.day == date(2026, 9, 27, 0))
        #expect(summary.bestDay?.ml == 3_000)
        #expect(summary.daysOnTarget == 3)
        let empty = HistoryAggregation.summary(events: [], range: .month, now: now, calendar: calendar, targetMl: 2_000)
        #expect(empty.bestDay == nil)
        #expect(empty.daysOnTarget == 0)
        #expect(empty.averagePerDayMl == nil)
        #expect(empty.recordedDayCount == 0)
    }

    @Test func summaryForWeekBucketsStillCountsDays() {
        // 90 D uses week buckets for the chart, but "days on target" is per day.
        let events = [event(date(2026, 9, 30, 8), 2_500), event(date(2026, 9, 1, 8), 2_500)]
        let summary = HistoryAggregation.summary(events: events, range: .quarter, now: now, calendar: calendar, targetMl: 2_000)
        #expect(summary.daysOnTarget == 2)
        let dayCount = HistoryAggregation.dailyTotals(events: events, range: .quarter, now: now, calendar: calendar).count
        #expect(dayCount == 90)
    }

    @Test func yAxisBounds() {
        let end = date(2026, 10, 1, 0)
        let buckets = [HistoryAggregation.Bucket(start: now, end: end, dayCount: 1, recordedDayCount: 1, ml: 1_000)]
        #expect(HistoryAggregation.yUpperBound(buckets: buckets, targetMl: 2_000, fixedToTarget: true) == 2_400)
        let high = [HistoryAggregation.Bucket(start: now, end: end, dayCount: 1, recordedDayCount: 1, ml: 3_000)]
        #expect(HistoryAggregation.yUpperBound(buckets: high, targetMl: 2_000, fixedToTarget: true) == 3_000)
        #expect(HistoryAggregation.yUpperBound(buckets: [], targetMl: 2_000, fixedToTarget: false) == 100)
        #expect(abs(HistoryAggregation.yUpperBound(buckets: high, targetMl: 2_000, fixedToTarget: false) - 3_300) < 0.001)
    }

    @Test func hourlyAxisTracksLowPeaksDespiteLegacyFixedPreference() {
        let amounts = [20.0, 50.0, 100.0]
        for count in 1...amounts.count {
            let events = amounts.prefix(count).enumerated().map { event(date(2026, 9, 30, 8 + $0.offset), $0.element) }
            let hours = HistoryAggregation.buckets(events: events, range: .day, now: now, calendar: calendar)
            for goal in [2_000.0, 6_000.0] {
                for fixed in [false, true] {
                    let upper = HistoryAggregation.yUpperBound(buckets: hours, targetMl: goal, fixedToTarget: fixed, hourly: true)
                    #expect(abs(upper - amounts[count - 1] * 1.1) < 0.001)
                }
            }
        }
    }

    @Test func autoAxisUsesPlottedDailyMeanNotGoalOrPeriodTotal() {
        let bucket = HistoryAggregation.Bucket(start: now, end: now.addingTimeInterval(86_400), dayCount: 7, recordedDayCount: 2, ml: 1_200)
        #expect(bucket.averagePerDayMl == 600)
        for goal in [2_000.0, 6_000.0] {
            #expect(abs(HistoryAggregation.yUpperBound(buckets: [bucket], targetMl: goal, fixedToTarget: false) - 660) < 0.001)
        }
        let higher = HistoryAggregation.Bucket(start: bucket.start, end: bucket.end, dayCount: 7, recordedDayCount: 2, ml: 1_800)
        #expect(abs(HistoryAggregation.yUpperBound(buckets: [higher], targetMl: 2_000, fixedToTarget: false) - 990) < 0.001)
    }

    @Test func emptyZeroAndInvalidAxisValuesHaveSafeFiniteDomains() {
        func bucket(_ ml: Double, _ usedDays: Int = 1) -> HistoryAggregation.Bucket {
            HistoryAggregation.Bucket(start: now, end: now.addingTimeInterval(3_600), dayCount: 1, recordedDayCount: usedDays, ml: ml)
        }
        let invalid = [bucket(.nan), bucket(.infinity), bucket(-.infinity), bucket(-20), bucket(0), bucket(50_000, 0)]
        for hourly in [false, true] {
            for goal in [2_000.0, 6_000.0, 0, -20, .nan, .infinity] {
                for empty in [[], [bucket(0)], invalid] {
                    #expect(HistoryAggregation.yUpperBound(buckets: empty, targetMl: goal, fixedToTarget: false, hourly: hourly) == 100)
                    if hourly {
                        #expect(HistoryAggregation.yUpperBound(buckets: empty, targetMl: goal, fixedToTarget: true, hourly: true) == 100)
                    }
                }
                #expect(abs(HistoryAggregation.yUpperBound(buckets: invalid + [bucket(50)], targetMl: goal, fixedToTarget: false, hourly: hourly) - 55) < 0.001)
            }
        }
        for goal in [0.0, -20, .nan, .infinity, -.infinity] {
            #expect(abs(HistoryAggregation.yUpperBound(buckets: [bucket(50)], targetMl: goal, fixedToTarget: true) - 55) < 0.001)
        }
        for fixed in [false, true] {
            let upper = HistoryAggregation.yUpperBound(buckets: [bucket(.greatestFiniteMagnitude)], targetMl: .greatestFiniteMagnitude, fixedToTarget: fixed)
            #expect(upper.isFinite && upper == .greatestFiniteMagnitude)
        }
    }

    @Test func goalRuleRequiresANonHourlyGoalWithinTheFiniteDomain() {
        let bucket = HistoryAggregation.Bucket(start: now, end: now.addingTimeInterval(86_400), dayCount: 7, recordedDayCount: 2, ml: 1_200)
        let auto = HistoryAggregation.yUpperBound(buckets: [bucket], targetMl: 2_000, fixedToTarget: false)
        #expect(!HistoryAggregation.showsGoalRule(targetMl: 2_000, upperBound: auto))
        #expect(HistoryAggregation.showsGoalRule(targetMl: 600, upperBound: auto))
        #expect(HistoryAggregation.showsGoalRule(targetMl: auto, upperBound: auto))
        #expect(!HistoryAggregation.showsGoalRule(targetMl: 20, upperBound: auto, hourly: true))
        let fixed = HistoryAggregation.yUpperBound(buckets: [bucket], targetMl: 2_000, fixedToTarget: true)
        #expect(HistoryAggregation.showsGoalRule(targetMl: 2_000, upperBound: fixed))
        for invalid in [0.0, -20, .nan, .infinity, -.infinity] {
            #expect(!HistoryAggregation.showsGoalRule(targetMl: invalid, upperBound: auto))
            #expect(!HistoryAggregation.showsGoalRule(targetMl: 600, upperBound: invalid))
        }
    }

    @Test func invalidPlotValuesAreGapsWithoutChangingBucketAverages() {
        let amounts = [20.0, .nan, .infinity, -.infinity, -20, 50]
        let buckets = amounts.enumerated().map { index, amount in
            HistoryAggregation.Bucket(start: now.addingTimeInterval(Double(index) * 3_600), end: now.addingTimeInterval(Double(index + 1) * 3_600), dayCount: 1, recordedDayCount: 1, ml: amount)
        }
        let points = HistoryAggregation.plotPoints(buckets: buckets)
        #expect(points.map(\.averagePerDayMl) == [20, 50])
        #expect(points.first?.series != points.last?.series)
        #expect(buckets[1].averagePerDayMl?.isNaN == true)
        #expect(buckets[4].averagePerDayMl == -20)
    }

    @Test(arguments: HistoryAggregation.Range.allCases)
    func futureEventsExcludedFromChartSummaryAndList(_ range: HistoryAggregation.Range) {
        let start = HistoryAggregation.rangeStart(range: range, now: now, calendar: calendar)
        let included = [event(start, 100), event(now, 200)]
        let events = included + [event(start.addingTimeInterval(-1), 999), event(now.addingTimeInterval(1), 999), event(date(2026, 10, 1), 999)]
        #expect(HistoryAggregation.eventsInRange(events: events, range: range, now: now, calendar: calendar) == included)
        #expect(HistoryAggregation.buckets(events: events, range: range, now: now, calendar: calendar).reduce(0) { $0 + $1.ml } == 300)
        #expect(HistoryAggregation.summary(events: events, range: range, now: now, calendar: calendar, targetMl: 500).totalMl == 300)
        #expect(HistoryAggregation.summary(events: events, range: range, now: now, calendar: calendar, targetMl: 500).daysOnTarget == 0)
    }

    @Test func weeklyAndMonthlyPointsUseDailyAverages() {
        for range in [HistoryAggregation.Range.quarter, .year] {
            let now = date(2024, 3, 15)
            let days = HistoryAggregation.dailyTotals(events: [], range: range, now: now, calendar: calendar)
            let events = days.map { event($0.start, 2_000) }
            let buckets = HistoryAggregation.buckets(events: events, range: range, now: now, calendar: calendar)
            #expect(buckets.allSatisfy { $0.averagePerDayMl == 2_000 })
            #expect(buckets.reduce(0) { $0 + $1.recordedDayCount } == days.count)
            #expect(buckets.allSatisfy { $0.contains($0.midpoint) && !$0.contains($0.end) })
            // Daily-goal scale is independent of week/month length.
            #expect(HistoryAggregation.yUpperBound(buckets: buckets, targetMl: 2_000, fixedToTarget: true) == 2_400)
        }
    }

    @Test func dstDaysCountOnceInRecordedDayAverages() {
        for now in [date(2025, 3, 31), date(2025, 10, 27)] {
            let emptyDays = HistoryAggregation.dailyTotals(events: [], range: .quarter, now: now, calendar: calendar)
            let events = emptyDays.map { event($0.start, 2_000) }
            let days = HistoryAggregation.dailyTotals(events: events, range: .quarter, now: now, calendar: calendar)
            #expect(days.count == 90)
            #expect(days.allSatisfy { $0.dayCount == 1 && $0.recordedDayCount == 1 && $0.averagePerDayMl == 2_000 })
            let weeks = HistoryAggregation.buckets(events: events, range: .quarter, now: now, calendar: calendar)
            #expect(weeks.reduce(0) { $0 + $1.recordedDayCount } == 90)
            #expect(weeks.allSatisfy { $0.averagePerDayMl == 2_000 })
        }
    }

    @Test func zeroDaysDoNotLowerOverallAverage() {
        let events = [
            event(date(2026, 9, 26, 8), 1_000),
            event(date(2026, 9, 28, 8), 500),
            event(date(2026, 9, 28, 18), 1_500),
            event(date(2026, 9, 29, 8), 0),
        ]
        let result = HistoryAggregation.summary(events: events, range: .week, now: now, calendar: calendar, targetMl: 2_000)
        #expect(result.averagePerDayMl == 1_500)
        #expect(result.totalMl == 3_000)
        #expect(result.daysOnTarget == 1)
    }

    @Test func yearAverageWeightsUsedDaysRatherThanMonthlyAverages() {
        let events = [event(date(2026, 1, 10), 1_000)]
            + [1, 2, 3].map { event(date(2026, 2, $0), 3_000) }
        let result = HistoryAggregation.summary(events: events, range: .year, now: now, calendar: calendar, targetMl: 2_000)
        #expect(result.averagePerDayMl == 2_500)
        #expect(result.totalMl == 10_000)
    }

    @Test func januaryUsesOnlyTenRecordedDays() {
        let events = (1...10).map { event(date(2026, 1, $0), 2_000) }
            + [event(date(2026, 1, 20), 0)]
        let buckets = HistoryAggregation.buckets(events: events, range: .year, now: now, calendar: calendar)
        let january = buckets.first { $0.start == date(2026, 1, 1, 0) }!
        #expect(january.ml == 20_000)
        #expect(january.dayCount == 31)
        #expect(january.recordedDayCount == 10)
        #expect(january.averagePerDayMl == 2_000)
        #expect(HistoryAggregation.yUpperBound(buckets: buckets, targetMl: 2_000, fixedToTarget: true) == 2_400)
    }

    @Test func emptyPeriodsAreMissingNotZeroAverages() {
        for range in HistoryAggregation.Range.allCases {
            let events = [event(now, 0)]
            let buckets = HistoryAggregation.buckets(events: events, range: range, now: now, calendar: calendar)
            #expect(buckets.allSatisfy { $0.averagePerDayMl == nil && $0.recordedDayCount == 0 })
            #expect(HistoryAggregation.plotPoints(buckets: buckets).isEmpty)
            #expect(HistoryAggregation.summary(events: events, range: range, now: now, calendar: calendar, targetMl: 2_000).averagePerDayMl == nil)
        }
    }

    @Test func missingPeriodsBreakLineAndAreaSeries() {
        let events = [24, 25, 27, 28].map { event(date(2026, 9, $0), 1_000) }
        let buckets = HistoryAggregation.buckets(events: events, range: .week, now: now, calendar: calendar)
        let points = HistoryAggregation.plotPoints(buckets: buckets)
        #expect(points.count == 4)
        #expect(points.allSatisfy { $0.averagePerDayMl == 1_000 })
        #expect(points[0].series == points[1].series)
        #expect(points[2].series == points[3].series)
        #expect(points[1].series != points[2].series)
    }

    @Test func recordedDaysFollowLocalMidnightNotEventCount() {
        let events = [event(date(2026, 9, 29, 23, 30), 1_000), event(date(2026, 9, 30, 0, 30), 3_000)]
        let local = HistoryAggregation.summary(events: events, range: .week, now: now, calendar: calendar, targetMl: 2_000)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let shifted = HistoryAggregation.summary(events: events, range: .week, now: now, calendar: utc, targetMl: 2_000)
        #expect(local.recordedDayCount == 2)
        #expect(local.averagePerDayMl == 2_000)
        #expect(shifted.recordedDayCount == 1)
        #expect(shifted.averagePerDayMl == 4_000)
    }

    @Test func partialEdgeWeekDividesByItsUsedDaysOnly() {
        let start = HistoryAggregation.rangeStart(range: .quarter, now: now, calendar: calendar)
        let second = calendar.date(byAdding: .day, value: 1, to: start)!
        let third = calendar.date(byAdding: .day, value: 2, to: start)!
        let events = [event(start.addingTimeInterval(-1), 999), event(start, 1_000), event(second, 3_000), event(third, 0)]
        let first = HistoryAggregation.buckets(events: events, range: .quarter, now: now, calendar: calendar).first!
        #expect(first.dayCount == 3)
        #expect(first.recordedDayCount == 2)
        #expect(first.ml == 4_000)
        #expect(first.averagePerDayMl == 2_000)
    }

    @Test func rangeMetadata() {
        #expect(HistoryAggregation.Range.allCases.map(\.label) == ["1 D", "7 D", "30 D", "90 D", "1 Y"])
        #expect(HistoryAggregation.Range.allCases.allSatisfy { $0.label.count <= 4 })
        #expect(!HistoryAggregation.Range.week.scrolls)
        #expect(HistoryAggregation.Range.year.scrolls)
        #expect(HistoryAggregation.Range(rawValue: "90d") == .quarter)
        // Scrolling ranges show fewer buckets than they hold; 7 D shows all.
        for range in HistoryAggregation.Range.allCases {
            let count = HistoryAggregation.buckets(events: [], range: range, now: now, calendar: calendar).count
            #expect(range.scrolls ? range.visibleBuckets < count : range.visibleBuckets == count)
        }
    }
}
