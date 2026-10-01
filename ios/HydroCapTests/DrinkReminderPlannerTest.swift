import Foundation
import Testing

@testable import HydroCap

@Suite("Drink reminder planner")
struct DrinkReminderPlannerTest {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func input(
        enabled: Bool = true,
        now: Date,
        window: DrinkReminderPlanner.Window = DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 78_300),
        frequency: Int = 120,
        target: Double = 2_450,
        consumed: Double = 0,
        drinks: [Date] = [],
        onlyWhenBehind: Bool = false,
    ) -> DrinkReminderPlanner.Input {
        DrinkReminderPlanner.Input(
            enabled: enabled,
            now: now,
            window: window,
            frequencyMinutes: frequency,
            targetMl: target,
            consumedTodayMl: consumed,
            drinkTimestampsToday: drinks.map { Int64($0.timeIntervalSince1970) },
            onlyWhenBehind: onlyWhenBehind,
            calendar: calendar,
        )
    }

    @Test func slotsStayStrictlyInsideTheWindow() {
        // 08:00–21:45 every 2 h: 08, 10, 12, 14, 16, 18, 20 (22:00 is past stop).
        let slots = DrinkReminderPlanner.slotSecondsOfDay(window: DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 78_300), frequencyMinutes: 120)
        #expect(slots == [28_800, 36_000, 43_200, 50_400, 57_600, 64_800, 72_000])
        // A stop exactly on a slot excludes it: 08:00–20:00 → last slot 18:00.
        let exact = DrinkReminderPlanner.slotSecondsOfDay(window: DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 72_000), frequencyMinutes: 120)
        #expect(exact.last == 64_800)
    }

    @Test func midnightIs86400AndCountsAsEndOfDay() {
        let window = DrinkReminderPlanner.Window(startSec: 79_200, stopSec: 86_400) // 22:00–24:00
        #expect(window.isUsable)
        let slots = DrinkReminderPlanner.slotSecondsOfDay(window: window, frequencyMinutes: 60)
        #expect(slots == [79_200, 82_800])
        // Planned at 21:00: both slots fire today, then tomorrow's 22:00.
        let planned = DrinkReminderPlanner.plan(input(now: time(21), window: window, frequency: 60))
        #expect(planned.map(\.fireAt) == [time(22), time(23), tomorrow(22)])
    }

    private func tomorrow(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
    }

    @Test func overnightWindowNeverFallsBackToDaytime() {
        let overnight = DrinkReminderPlanner.Window(startSec: 79_200, stopSec: 28_800)
        #expect(overnight.isUsable)
        #expect(DrinkReminderPlanner.slotSecondsOfDay(window: overnight, frequencyMinutes: 180) == [3_600, 14_400, 25_200, 79_200])
        let planned = DrinkReminderPlanner.plan(input(now: time(7), window: overnight, frequency: 180))
        #expect(planned.map(\.fireAt) == [time(22), tomorrow(1)])
        let invalid = DrinkReminderPlanner.Window(startSec: 0, stopSec: 3_600)
        #expect(!invalid.isUsable)
        #expect(DrinkReminderPlanner.plan(input(now: time(7), window: invalid)).isEmpty)
    }

    @Test func pastSlotsAreSkipped() {
        // 13:05: 08, 10, 12 are gone; 14, 16, 18, 20 remain + tomorrow 08.
        let planned = DrinkReminderPlanner.plan(input(now: time(13, 5)))
        #expect(planned.map(\.fireAt) == [time(14), time(16), time(18), time(20), calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!])
        #expect(planned.map(\.identifier) == planned.map { "hydrocap.drink.\(Int64($0.fireAt.timeIntervalSince1970))" })
        // A slot exactly at "now" is not in the future → skipped.
        let atSlot = DrinkReminderPlanner.plan(input(now: time(14)))
        #expect(atSlot.first?.fireAt == time(16))
    }

    @Test func behindTargetIsProRataOverTheWindow() {
        let window = DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 78_300) // 08:00–21:45 = 49 500 s
        // At 14:00: elapsed 21 600 / 49 500 = 0.4364 → 2450 × 0.4364 = 1069 ml expected.
        #expect(DrinkReminderPlanner.isBehind(targetMl: 2_450, consumedMl: 1_000, window: window, atSecOfDay: 50_400))
        #expect(!DrinkReminderPlanner.isBehind(targetMl: 2_450, consumedMl: 1_100, window: window, atSecOfDay: 50_400))
        // At the window start nothing is expected yet → never behind.
        #expect(!DrinkReminderPlanner.isBehind(targetMl: 2_450, consumedMl: 0, window: window, atSecOfDay: 28_800))
        // After the stop the full target is expected.
        #expect(DrinkReminderPlanner.isBehind(targetMl: 2_450, consumedMl: 2_400, window: window, atSecOfDay: 86_400))
        #expect(DrinkReminderPlanner.elapsedFraction(window: window, atSecOfDay: 20_000) == 0)
        #expect(DrinkReminderPlanner.elapsedFraction(window: window, atSecOfDay: 90_000) == 1)
    }

    @Test func onlyWhenBehindPlansOnlyTheSlotsWhereCurrentIntakeIsShort() {
        // 1 200 ml at 13:05. Expected at 14:00 = 1069 (ok), 16:00 = 1425 (behind), later all behind.
        let planned = DrinkReminderPlanner.plan(input(now: time(13, 5), consumed: 1_200, onlyWhenBehind: true))
        #expect(planned.map(\.fireAt) == [time(16), time(18), time(20), tomorrow(10)])
        // Tomorrow's start is not behind (0 < 0 is false); first eligible is 10:00.
        let done = DrinkReminderPlanner.plan(input(now: time(13, 5), consumed: 2_500, onlyWhenBehind: true))
        #expect(done.map(\.fireAt) == [tomorrow(10)])
    }

    @Test func pendingCountIsCappedAtEight() {
        // Every hour 08:00–22:00 from 07:00 → 14 slots today; capped to 8, all today.
        let planned = DrinkReminderPlanner.plan(input(now: time(7), window: DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 79_200), frequency: 60))
        #expect(planned.count == DrinkReminderPlanner.maxPending)
        #expect(planned.count == 8)
        #expect(planned.last?.fireAt == time(15))
        #expect(Set(planned.map(\.identifier)).count == 8)
        #expect(planned.allSatisfy { $0.identifier.hasPrefix(DrinkReminderPlanner.identifierPrefix) })
    }

    @Test func disabledOrNoTargetPlansNothing() {
        #expect(DrinkReminderPlanner.plan(input(enabled: false, now: time(9))).isEmpty)
        #expect(DrinkReminderPlanner.plan(input(now: time(9), target: 0)).isEmpty)
        #expect(DrinkReminderPlanner.plan(input(now: time(9), frequency: 0)).isEmpty)
    }

    @Test func bodyTextLabelsTheLastSyncedSnapshot() {
        let noDrinks = DrinkReminderPlanner.plan(input(now: time(13, 5), consumed: 800))
        #expect(noDrinks.first?.body == "Last sync at 13:05: 0.8 L logged from your bottle toward 2.45 L. Take a sip if you need one.")
        #expect(noDrinks.first?.title == "Time to drink")
        let withDrink = DrinkReminderPlanner.plan(input(now: time(15), consumed: 800, drinks: [time(9, 30), time(14, 10)]))
        #expect(withDrink.first?.body.contains("Last sync at 15:00") == true)
        #expect(withDrink.last?.body == "Check your bottle progress today. Your drink goal is 2.45 L.")
        let whole = DrinkReminderPlanner.plan(input(now: time(13, 5), target: 2_000, consumed: 1_000))
        #expect(whole.first?.body.contains("1.0 L logged from your bottle toward 2.0 L") == true)
    }

    @Test func windowLabelUsesRingHours() {
        #expect(DrinkReminderPlanner.windowLabel(DrinkReminderPlanner.Window(startSec: 28_800, stopSec: 78_300)) == "Between 08:00 and 21:45")
        #expect(DrinkReminderPlanner.windowLabel(.fallback) == "Between 08:00 and 22:00")
        #expect(DrinkReminderPlanner.frequencyChoicesMinutes == [60, 90, 120, 180])
        #expect(DrinkReminderPlanner.defaultFrequencyMinutes == 120)
    }
}
