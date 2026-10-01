import Foundation

// Test-only CLI harness. Compiles the untouched production iOS sources;
// no replacement algorithms, fake Health APIs or bottle/device access.
@main
struct IosParityReference {
    static func number(_ value: String) -> Double? {
        if value == "nil" { return nil }
        if value == "NaN" { return .nan }
        if value == "Infinity" { return .infinity }
        return Double(value)
    }
    static func sex(_ value: String) -> HydrationTarget.Sex? {
        value == "nil" ? nil : HydrationTarget.Sex(rawValue: value)
    }
    static func epoch(_ date: Date) -> String { String(Int64(date.timeIntervalSince1970)) }
    static func value(_ n: Double?) -> String { n.map { String(format: "%.9f", $0) } ?? "nil" }
    static func rows(_ path: String) throws -> [[String]] {
        try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }
    static func calendar(zone: String, locale: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: locale.replacingOccurrences(of: "-", with: "_"))
        return c
    }
    static func main() throws {
        let dir = CommandLine.arguments[1]
        var targetOutput: [String] = []
        for r in try rows(dir + "/target-input.tsv") {
            let result = HydrationTarget.resolve(useEstimate: r[1] == "true", overrideMl: Int(r[2]),
                healthWeightKg: number(r[3]), healthSex: sex(r[4]), manualWeightKg: number(r[5]), manualSex: sex(r[6]))
            let basis: [String]
            switch result.basis {
            case .weight(let kg, let source): basis = ["weight", source == .health ? "health" : "manual", value(kg)]
            case .sex(let s, let source): basis = ["sex", source == .health ? "health" : "manual", s.rawValue]
            case .default: basis = ["default", "nil", "nil"]
            case .manual: basis = ["manual", "nil", "nil"]
            }
            targetOutput.append(([r[0], String(result.ml)] + basis).joined(separator: "\t"))
        }
        try targetOutput.joined(separator: "\n").appending("\n").write(toFile: dir + "/target-expected.tsv", atomically: true, encoding: .utf8)
        var historyOutput: [String] = []
        for r in try rows(dir + "/history-input.tsv") {
            let range = HistoryAggregation.Range(rawValue: r[1])!
            let now = Date(timeIntervalSince1970: Double(r[2])!)
            let c = calendar(zone: r[3], locale: r[4])
            let events: [DrinkEvent] = r[6] == "nil" ? [] : r[6].split(separator: ";").map { pair in
                let p = pair.split(separator: ":")
                let ts = Int64(p[0])!
                return DrinkEvent(timestamp: ts, volumeMl: Double(p[1])!, sourceLogTimestamp: ts, profileId: "synthetic-parity")
            }
            let buckets = HistoryAggregation.buckets(events: events, range: range, now: now, calendar: c)
            let summary = HistoryAggregation.summary(events: events, range: range, now: now, calendar: c, targetMl: Double(r[5])!)
            historyOutput.append([r[0], "R", epoch(HistoryAggregation.rangeStart(range: range, now: now, calendar: c)), epoch(HistoryAggregation.rangeEnd(range: range, now: now, calendar: c)), String(c.firstWeekday), String(c.minimumDaysInFirstWeek)].joined(separator: "\t"))
            for (i, b) in buckets.enumerated() {
                historyOutput.append([r[0], "B", String(i), epoch(b.start), epoch(b.end), String(b.dayCount), String(b.recordedDayCount), value(b.ml), value(b.averagePerDayMl)].joined(separator: "\t"))
            }
            for (i, p) in HistoryAggregation.plotPoints(buckets: buckets).enumerated() {
                historyOutput.append([r[0], "P", String(i), epoch(p.bucket.start), value(p.averagePerDayMl), String(p.series)].joined(separator: "\t"))
            }
            historyOutput.append([r[0], "S", value(summary.averagePerDayMl), String(summary.recordedDayCount), summary.bestDay.map { epoch($0.day) } ?? "nil", value(summary.bestDay?.ml), String(summary.daysOnTarget), value(summary.totalMl)].joined(separator: "\t"))
            historyOutput.append([r[0], "Y", value(HistoryAggregation.yUpperBound(buckets: buckets, targetMl: Double(r[5])!, fixedToTarget: false, hourly: range == .day)), value(HistoryAggregation.yUpperBound(buckets: buckets, targetMl: Double(r[5])!, fixedToTarget: true, hourly: range == .day))].joined(separator: "\t"))
        }
        try historyOutput.joined(separator: "\n").appending("\n").write(toFile: dir + "/history-expected.tsv", atomically: true, encoding: .utf8)
        var reminderOutput: [String] = []
        for r in try rows(dir + "/reminder-input.tsv") {
            let now = Date(timeIntervalSince1970: Double(r[1])!)
            let c = calendar(zone: r[2], locale: "en-GB")
            let window = DrinkReminderPlanner.Window(startSec: Int(r[3])!, stopSec: Int(r[4])!)
            let input = DrinkReminderPlanner.Input(enabled: r[8] == "true", now: now, window: window,
                frequencyMinutes: Int(r[5])!, targetMl: Double(r[6])!, consumedTodayMl: Double(r[7])!,
                drinkTimestampsToday: [], onlyWhenBehind: r[9] == "true", calendar: c)
            reminderOutput.append([r[0], "W", String(window.isUsable), String(window.durationSec)].joined(separator: "\t"))
            if let day = DrinkReminderPlanner.dayRange(now: now, calendar: c) {
                reminderOutput.append([r[0], "D", epoch(day.start), epoch(day.end)].joined(separator: "\t"))
            }
            reminderOutput.append([r[0], "L", DrinkReminderPlanner.slotSecondsOfDay(window: window, frequencyMinutes: input.frequencyMinutes).map(String.init).joined(separator: ";")].joined(separator: "\t"))
            for (i, n) in DrinkReminderPlanner.plan(input).enumerated() {
                reminderOutput.append([r[0], "N", String(i), epoch(n.fireAt), n.identifier].joined(separator: "\t"))
            }
        }
        try reminderOutput.joined(separator: "\n").appending("\n").write(toFile: dir + "/reminder-expected.tsv", atomically: true, encoding: .utf8)
        print("Production iOS reference executed: target=\(targetOutput.count), historyRows=\(historyOutput.count), reminderRows=\(reminderOutput.count)")
    }
}
