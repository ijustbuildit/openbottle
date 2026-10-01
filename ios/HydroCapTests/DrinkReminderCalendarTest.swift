import Foundation
import Testing
@testable import HydroCap

@Suite("Reminder calendar regressions")
struct DrinkReminderCalendarTest {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    func input(now: Date, window: DrinkReminderPlanner.Window = .fallback) -> DrinkReminderPlanner.Input {
        .init(enabled: true, now: now, window: window, frequencyMinutes: 120, targetMl: 2_000, consumedTodayMl: 0, drinkTimestampsToday: [], onlyWhenBehind: false, calendar: calendar)
    }
    @Test func dstDoesNotShiftRingHours() {
        for (month, day) in [(3, 29), (10, 25)] {
            let plan = DrinkReminderPlanner.plan(input(now: date(month, day, 6)))
            #expect(plan.first?.fireAt == date(month, day, 8))
            #expect(plan.filter { calendar.isDate($0.fireAt, inSameDayAs: date(month, day, 6)) }.allSatisfy {
                let hour = calendar.component(.hour, from: $0.fireAt)
                return hour >= 8 && hour < 22
            })
        }
    }
    @Test func intakeQueryCoversCalendarDayNot86400Seconds() {
        let spring = DrinkReminderPlanner.dayRange(now: date(3, 29, 12), calendar: calendar)!
        let autumn = DrinkReminderPlanner.dayRange(now: date(10, 25, 12), calendar: calendar)!
        #expect(spring.end == date(3, 30, 0))
        #expect(autumn.end == date(10, 26, 0))
        #expect(spring.duration == 23 * 3_600)
        #expect(autumn.duration == 25 * 3_600)
    }
    @Test func midnightStartRemainsMidnightAndEightIsExclusive() {
        let w = DrinkReminderPlanner.Window(startSec: 86_400, stopSec: 28_800)
        #expect(w.isUsable)
        #expect(DrinkReminderPlanner.slotSecondsOfDay(window: w, frequencyMinutes: 120) == [0, 7_200, 14_400, 21_600])
        let plan = DrinkReminderPlanner.plan(input(now: date(9, 30, 1), window: w))
        #expect(plan.first?.fireAt == date(9, 30, 2))
        #expect(plan.allSatisfy { calendar.component(.hour, from: $0.fireAt) < 8 })
    }
    @Test func repeatedReplansKeepTheSameFutureSlot() {
        let early = DrinkReminderPlanner.plan(input(now: date(9, 30, 9)))
        let later = DrinkReminderPlanner.plan(input(now: date(9, 30, 9).addingTimeInterval(900)))
        #expect(early.first?.fireAt == later.first?.fireAt)
        #expect(early.first?.identifier == later.first?.identifier)
    }
}
