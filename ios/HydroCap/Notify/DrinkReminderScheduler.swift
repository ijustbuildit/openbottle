import Foundation
import UserNotifications

/// Local notifications are rebuilt from the latest successfully-read intake
/// snapshot. All replacement writes are serialized; newer settings always win.
@MainActor
final class DrinkReminderScheduler {
    nonisolated static let tag = "reminders"
    nonisolated static let categoryIdentifier = "drink"

    private let settings: SettingsStore
    private let store: any HydroCapStore
    private let debugLog: DebugLog
    private let center: UNUserNotificationCenter
    private let queue = DrinkReminderQueue()
    var targetMlProvider: () -> Double = { Double(HydrationTarget.defaultMl) }
    private var replanTask: Task<Void, Never>?

    init(settings: SettingsStore, store: any HydroCapStore, debugLog: DebugLog, center: UNUserNotificationCenter = .current()) {
        self.settings = settings
        self.store = store
        self.debugLog = debugLog
        self.center = center
    }

    nonisolated static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: categoryIdentifier, actions: [], intentIdentifiers: [], options: [])
    }

    func replanSoon() {
        replanTask?.cancel()
        replanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.replan()
        }
    }

    func replan(now: Date = Date()) async {
        await queue.submit { [self] lease in
            await replacePlan(now: now, lease: lease)
        }
    }

    private func replacePlan(now: Date, lease: DrinkReminderQueue.Lease) async {
        let pending = await center.pendingNotificationRequests()
        guard lease.isCurrent else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(DrinkReminderPlanner.identifierPrefix)
        })
        let current = settings.current
        guard current.drinkRemindersEnabled, current.hasPairedDevice else { return }
        guard let window = current.ringWindow, window.isUsable else {
            debugLog.log(Self.tag, "no drink reminders: read the cap's ring hours first")
            return
        }
        let range = Self.dayRangeSec(now: now)
        let events: [DrinkEvent]
        do {
            events = try await store.drinkEvents(fromSec: range.from, toSec: range.to)
        } catch {
            // Missing/locked storage is unknown intake, never zero intake.
            debugLog.error(Self.tag, "intake unavailable; no drink reminders scheduled", error: error)
            return
        }
        guard lease.isCurrent, settings.current == current else { return }
        let observed = events.filter { Double($0.timestamp) <= now.timeIntervalSince1970 }
        let input = DrinkReminderPlanner.Input(
            enabled: true, now: now, window: window,
            frequencyMinutes: current.drinkReminderFrequencyMinutes,
            targetMl: targetMlProvider(),
            consumedTodayMl: observed.reduce(0) { $0 + $1.volumeMl },
            drinkTimestampsToday: observed.map(\.timestamp),
            onlyWhenBehind: current.drinkReminderOnlyWhenBehind,
            calendar: Calendar.current)
        let plan = DrinkReminderPlanner.plan(input)
        var scheduled = 0
        for reminder in plan {
            guard lease.isCurrent, settings.current == current else { return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.categoryIdentifier = Self.categoryIdentifier
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                debugLog.error(Self.tag, "could not schedule \(reminder.identifier)", error: error)
            }
            // If disabled/changed while add was in flight, the queued latest
            // replan clears it before that caller returns. Never add the rest.
            guard lease.isCurrent else { return }
        }
        let first = plan.first.map { AppModel.timeString($0.fireAt) } ?? "—"
        debugLog.log(Self.tag, "scheduled \(scheduled) drink reminder(s), first at \(first), every \(input.frequencyMinutes) min, \(DrinkReminderPlanner.windowLabel(window)), onlyWhenBehind=\(input.onlyWhenBehind)")
    }

    nonisolated static func dayRangeSec(now: Date, calendar: Calendar = .current) -> (from: Int64, to: Int64) {
        let range = DrinkReminderPlanner.dayRange(now: now, calendar: calendar)!
        return (Int64(range.start.timeIntervalSince1970), Int64(range.end.timeIntervalSince1970))
    }
}
