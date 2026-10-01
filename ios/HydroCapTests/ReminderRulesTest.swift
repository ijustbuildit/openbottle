import Foundation
import Testing

@testable import HydroCap

@Suite("Reminder rules")
struct ReminderRulesTest {

    /// Interoperability settings observed during read-only hardware validation.
    private let factory = CapReminderConfig(
        reminder: ReminderSettings(mode: ReminderSettings.modeAdaptive, startSec: 28_800, stopSec: 78_300, intervalSec: 1_800, color: .firmwareDefault),
        dnd: DndSettings(mode: DndSettings.modeAuto, startSec: 78_300, stopSec: 28_800, snoozeMinutes: 0),
    )

    @Test func factoryValuesValidate() {
        #expect(ReminderRules.validate(factory) == nil)
    }

    @Test func emptyPatchReproducesTheCapValues() {
        #expect(ReminderRules.resolve(current: factory, patch: ReminderPatch(reminder: ReminderValues(), dnd: DndValues())) == factory)
    }

    @Test func autoQuietHoursMirrorTheReminderWindow() {
        let resolved = ReminderRules.resolve(
            current: factory,
            patch: ReminderPatch(
                reminder: ReminderValues(startSec: 25_200, stopSec: 79_200),
                dnd: DndValues(mode: DndSettings.modeAuto),
            ),
        )
        #expect(resolved.reminder.startSec == 25_200)
        #expect(resolved.dnd.startSec == 79_200)
        #expect(resolved.dnd.stopSec == 25_200)
        #expect(resolved.dnd.mode == DndSettings.modeAuto)
    }

    @Test func customQuietHoursKeepTheirOwnWindowAndTheSnoozeValue() {
        var current = factory
        current.dnd.snoozeMinutes = 15
        let resolved = ReminderRules.resolve(
            current: current,
            patch: ReminderPatch(dnd: DndValues(mode: DndSettings.modeCustom, startSec: 80_000, stopSec: 21_600)),
        )
        #expect(resolved.dnd == DndSettings(mode: DndSettings.modeCustom, startSec: 80_000, stopSec: 21_600, snoozeMinutes: 15))
        #expect(resolved.reminder == factory.reminder)
    }

    @Test func validationRejectsBadIntervalsHoursAndColours() {
        var on = factory.reminder
        var config = factory

        on.intervalSec = 0
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        on = factory.reminder
        on.startSec = 0
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        on = factory.reminder
        on.stopSec = 86_401
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        on = factory.reminder
        on.startSec = 3_600
        on.stopSec = 3_600
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        on = factory.reminder
        on.color = RingColor(red: 1.2, green: 0, blue: 0)
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        on = factory.reminder
        on.mode = 7
        config.reminder = on
        #expect(ReminderRules.validate(config) != nil)

        config = factory
        config.dnd = DndSettings(mode: DndSettings.modeCustom, startSec: 100, stopSec: 100, snoozeMinutes: 0)
        #expect(ReminderRules.validate(config) != nil)

        config = factory
        config.dnd.mode = 9
        #expect(ReminderRules.validate(config) != nil)

        // validateOrThrow surfaces the same problem as an error.
        config = factory
        config.reminder.mode = 7
        #expect(throws: (any Error).self) { _ = try ReminderRules.validateOrThrow(config) }
    }

    @Test func offModeIgnoresIntervalAndHoursButStillWritesWireSafeValues() {
        var off = factory.reminder
        off.startSec = 0
        off.stopSec = 0
        off.intervalSec = 0
        var current = factory
        current.reminder = off
        let resolved = ReminderRules.resolve(
            current: current,
            patch: ReminderPatch(reminder: ReminderValues(mode: ReminderSettings.modeOff)),
        )
        #expect(ReminderRules.validate(resolved) == nil)
        #expect(resolved.reminder.startSec == 86_400)
        #expect(resolved.reminder.stopSec == 86_400)
        #expect(resolved.reminder.intervalSec == 0)
    }

    @Test func secondsOfDayRoundTripWithMidnightAs86400() {
        #expect(ReminderRules.secOfDay(hour: 0, minute: 0) == 86_400)
        #expect(ReminderRules.secOfDay(hour: 8, minute: 0) == 28_800)
        #expect(ReminderRules.secOfDay(hour: 21, minute: 45) == 78_300)
        #expect(ReminderRules.hourOf(86_400) == 0)
        #expect(ReminderRules.hourOf(78_300) == 21)
        #expect(ReminderRules.minuteOf(78_300) == 45)
        #expect(ReminderRules.formatSecOfDay(78_300) == "21:45")
        #expect(ReminderRules.formatSecOfDay(86_400) == "00:00")
        #expect(ReminderRules.intervalChoicesMinutes == [15, 20, 30, 45, 60, 90, 120])
    }

    @Test func colourConversion() {
        let color = RingColor.fromRgb255(255, 128, 0)
        #expect(color.red == 1)
        #expect(color.green255 == 128)
        #expect(color.blue255 == 0)
        #expect(color.alpha == 1)
        #expect(RingColor.firmwareDefault.isFirmwareDefault)
        #expect(!color.isFirmwareDefault)
        #expect(RingColor.presets.count == 6)
    }

    @Test func protoMappingRoundTripsAndAlwaysSendsAlpha1() {
        let proto = ReminderMapping.toProto(ReminderSettings(
            mode: ReminderSettings.modeFixed,
            startSec: 28_800,
            stopSec: 79_200,
            intervalSec: 3_600,
            color: RingColor(red: 1, green: 0.5, blue: 0.25),
        ))
        #expect(proto.state == CapHydroReminderState.intervalFixed)
        #expect(proto.color?.alpha == 1)
        #expect(proto.color?.green == 0.5)
        #expect(ReminderMapping.fromProto(proto) == ReminderSettings(
            mode: ReminderSettings.modeFixed,
            startSec: 28_800,
            stopSec: 79_200,
            intervalSec: 3_600,
            color: RingColor(red: 1, green: 0.5, blue: 0.25),
        ))

        let dnd = ReminderMapping.toProto(DndSettings(mode: DndSettings.modeAuto, startSec: 78_300, stopSec: 28_800, snoozeMinutes: 5))
        #expect(dnd.state == CapDoNotDisturbState.auto)
        #expect(dnd.snoozeTimeInMinutes == 5)
        #expect(ReminderMapping.fromProto(dnd) == DndSettings(mode: DndSettings.modeAuto, startSec: 78_300, stopSec: 28_800, snoozeMinutes: 5))

        // The hardware session 1 reading: colour present with alpha only.
        let capReminder = CapHydroReminderSettings(
            state: CapHydroReminderState.intervalAdaptive,
            startTimeInSec: 28_800,
            stopTimeInSec: 78_300,
            intervalInSec: 1_800,
            color: CapColor(red: 0, green: 0, blue: 0, alpha: 1),
        )
        #expect(ReminderMapping.fromProto(capReminder) == factory.reminder)
        let capDnd = CapDoNotDisturbSettings(state: CapDoNotDisturbState.auto, startTimeInSec: 78_300, stopTimeInSec: 28_800, snoozeTimeInMinutes: 0)
        #expect(ReminderMapping.fromProto(capDnd) == factory.dnd)

        // No colour field at all → firmware default, not black-with-alpha-0.
        let colorless = CapHydroReminderSettings(state: CapHydroReminderState.off, startTimeInSec: 1, stopTimeInSec: 86_400, intervalInSec: 0, color: nil)
        #expect(ReminderMapping.fromProto(colorless).color == RingColor.firmwareDefault)
    }
}
