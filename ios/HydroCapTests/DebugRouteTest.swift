import Foundation
import Testing

@testable import HydroCap

@Suite("Debug URL routes")
struct DebugRouteTest {

    @Test func parsesTheFourRequiredHooks() {
        #expect(DebugRouteParser.parse("hydrocap://sync") == .sync)
        #expect(DebugRouteParser.parse("hydrocap://scan") == .scan)
        #expect(DebugRouteParser.parse("hydrocap://tof") == .liveTof)
        #expect(DebugRouteParser.parse("hydrocap://read-reminder") == .readReminder)
        #expect(DebugRouteParser.parse("hydrocap://read-all-settings") == .readAllSettings)
    }

    @Test func parsesTheWriteHooksWithAllExtras() {
        let reminder = DebugRouteParser.parse("hydrocap://set-reminder?state=2&start=28800&stop=78300&interval=1800&r=0&g=0.5&b=1")
        #expect(reminder == .setReminder(ReminderValues(
            mode: 2,
            startSec: 28_800,
            stopSec: 78_300,
            intervalSec: 1_800,
            color: RingColor(red: 0, green: 0.5, blue: 1, alpha: 1),
        )))

        let dnd = DebugRouteParser.parse("hydrocap://set-dnd?state=2&start=78300&stop=28800")
        #expect(dnd == .setDnd(DndValues(mode: 2, startSec: 78_300, stopSec: 28_800)))
    }

    @Test func absentExtrasKeepTheCapsCurrentValue() {
        #expect(DebugRouteParser.parse("hydrocap://set-reminder?state=1")
            == .setReminder(ReminderValues(mode: 1)))
        #expect(DebugRouteParser.parse("hydrocap://set-reminder")
            == .setReminder(ReminderValues()))
        // r/g/b must be given together; a single component still forms a colour
        // (matching the Android `hasColor` OR-check).
        #expect(DebugRouteParser.parse("hydrocap://set-reminder?g=1")
            == .setReminder(ReminderValues(color: RingColor(red: 0, green: 1, blue: 0, alpha: 1))))
    }

    @Test func rejectsAnythingElse() {
        #expect(DebugRouteParser.parse("https://sync") == nil)
        #expect(DebugRouteParser.parse("hydrocap://") == nil)
        #expect(DebugRouteParser.parse("hydrocap://unknown") == nil)
        #expect(DebugRouteParser.parse("") == nil)
        #expect(DebugRouteParser.parse("hydrocap://set-reminder?state=notanumber") == .setReminder(ReminderValues()))
    }

    @Test func routesAreDerivedFromTheDebugScreenActions() {
        // Every Debug-screen button that talks to the cap has a URL hook.
        let hooks: [DebugRoute] = [.scan, .sync, .liveTof, .readAllSettings, .readReminder]
        let parsed = [
            DebugRouteParser.parse("hydrocap://scan"),
            DebugRouteParser.parse("hydrocap://sync"),
            DebugRouteParser.parse("hydrocap://tof"),
            DebugRouteParser.parse("hydrocap://read-all-settings"),
            DebugRouteParser.parse("hydrocap://read-reminder"),
        ]
        #expect(parsed == hooks)
    }
}
