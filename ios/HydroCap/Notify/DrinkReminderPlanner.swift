import Foundation

/// Plans local reminder slots using the cap's wall-clock hours. Volumes are
/// the last synced snapshot, not a claim about consumption at delivery time.
nonisolated enum DrinkReminderPlanner {
    static let identifierPrefix = "hydrocap.drink."
    static let maxPending = 8
    static let defaultWindowStartSec = 8 * 3_600
    static let defaultWindowStopSec = 22 * 3_600
    static let frequencyChoicesMinutes: [Int] = [60, 90, 120, 180]
    static let defaultFrequencyMinutes = 120

    nonisolated struct Window: Sendable, Equatable {
        let startSec: Int
        let stopSec: Int
        static let fallback = Window(startSec: defaultWindowStartSec, stopSec: defaultWindowStopSec)
        var isUsable: Bool {
            (1...86_400).contains(startSec) && (1...86_400).contains(stopSec) && startSec != stopSec
        }
        var start: Int { startSec % 86_400 }
        var stop: Int { stopSec % 86_400 }
        var durationSec: Int {
            guard isUsable else { return 0 }
            return stop > start ? stop - start : 86_400 - start + stop
        }
        func contains(second: Int) -> Bool {
            guard isUsable else { return false }
            let value = second % 86_400
            return start < stop ? (value >= start && value < stop) : (value >= start || value < stop)
        }
    }

    nonisolated struct Input: Sendable {
        let enabled: Bool
        let now: Date
        let window: Window
        let frequencyMinutes: Int
        let targetMl: Double
        let consumedTodayMl: Double
        let drinkTimestampsToday: [Int64]
        let onlyWhenBehind: Bool
        let calendar: Calendar
    }

    nonisolated struct PlannedReminder: Sendable, Equatable {
        let identifier: String
        let fireAt: Date
        let title: String
        let body: String
    }

    /// Wall-clock slots, sorted in calendar-day order, including overnight
    /// windows. Midnight on the wire (86400) means local 00:00, not +24 h.
    static func slotSecondsOfDay(window: Window, frequencyMinutes: Int) -> [Int] {
        guard window.isUsable, frequencyMinutes > 0, frequencyMinutes <= 1_440 else { return [] }
        return stride(from: 0, to: window.durationSec, by: frequencyMinutes * 60)
            .map { (window.start + $0) % 86_400 }.sorted()
    }

    /// Fraction of this calendar day's active hours already elapsed. For
    /// 22:00–08:00 the early-morning and evening portions belong to the same
    /// daily goal; there is no arbitrary reset at the evening window start.
    static func elapsedFraction(window: Window, atSecOfDay second: Int) -> Double {
        guard window.isUsable else { return 0 }
        let s = min(max(second, 0), 86_400)
        let elapsed: Int
        if window.start < window.stop {
            elapsed = min(max(s - window.start, 0), window.durationSec)
        } else {
            elapsed = min(s, window.stop) + max(0, s - window.start)
        }
        return min(1, Double(elapsed) / Double(window.durationSec))
    }

    static func isBehind(targetMl: Double, consumedMl: Double, window: Window, atSecOfDay second: Int) -> Bool {
        guard targetMl.isFinite, targetMl > 0, consumedMl.isFinite else { return false }
        return max(0, consumedMl) < targetMl * elapsedFraction(window: window, atSecOfDay: second)
    }

    static func dayRange(now: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .day, for: now)
    }

    static func plan(_ input: Input) -> [PlannedReminder] {
        guard input.enabled, input.targetMl.isFinite, input.targetMl > 0,
              input.consumedTodayMl.isFinite, input.window.isUsable else { return [] }
        let slots = slotSecondsOfDay(window: input.window, frequencyMinutes: input.frequencyMinutes)
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        var planned: [PlannedReminder] = []
        var dates = Set<Date>()
        for (day, isTomorrow) in [(today, false), (tomorrow, true)] {
            for second in slots {
                // Construct wall-clock components: adding seconds to midnight
                // shifts every reminder by an hour on DST transition days.
                guard let fireAt = calendar.date(bySettingHour: second / 3_600,
                    minute: (second % 3_600) / 60, second: second % 60,
                    of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                    calendar.isDate(fireAt, inSameDayAs: day), fireAt > input.now else { continue }
                let components = calendar.dateComponents([.hour, .minute, .second], from: fireAt)
                let actualSecond = (components.hour ?? 0) * 3_600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
                guard input.window.contains(second: actualSecond) else { continue }
                let consumed = isTomorrow ? 0 : input.consumedTodayMl
                if input.onlyWhenBehind, !isBehind(targetMl: input.targetMl, consumedMl: consumed,
                    window: input.window, atSecOfDay: actualSecond) { continue }
                guard dates.insert(fireAt).inserted else { continue }
                planned.append(PlannedReminder(
                    identifier: "\(identifierPrefix)\(Int64(fireAt.timeIntervalSince1970))",
                    fireAt: fireAt, title: "Time to drink",
                    body: body(input: input, lastDrink: nil, tomorrow: isTomorrow)))
                if planned.count == maxPending { return planned }
                // One eligible slot tomorrow, with the same behind-target
                // rule as today; never force a reminder at zero elapsed time.
                if isTomorrow { break }
            }
        }
        return planned
    }

    static func body(input: Input, lastDrink: Date?, tomorrow: Bool) -> String {
        if tomorrow { return "Check your bottle progress today. Your drink goal is \(liters(input.targetMl))." }
        let formatter = DateFormatter()
        formatter.calendar = input.calendar
        formatter.timeZone = input.calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return "Last sync at \(formatter.string(from: input.now)): \(liters(input.consumedTodayMl)) logged from your bottle toward \(liters(input.targetMl)). Take a sip if you need one."
    }

    private static func liters(_ ml: Double) -> String {
        let value = ml / 1000
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() || (rounded * 10) == (rounded * 10).rounded() { return String(format: "%.1f L", rounded) }
        return String(format: "%.2f L", rounded)
    }

    static func windowLabel(_ window: Window) -> String {
        "Between \(ReminderRules.formatSecOfDay(window.startSec)) and \(ReminderRules.formatSecOfDay(window.stopSec))"
    }
}
