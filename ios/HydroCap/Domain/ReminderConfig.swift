import Foundation

/// Reminder ring + quiet hours as the cap stores them (protocol doc §4,
/// `CapHydroReminderSettings` / `CapDoNotDisturbSettings`), kept as plain Swift
/// so the screen, the URL hooks and the unit tests share one model. Modes are
/// raw wire values so an unknown value reported by the cap survives a
/// read → write round trip untouched.
nonisolated struct RingPreset: Sendable, Equatable, Identifiable {
    let name: String
    let color: RingColor

    var id: String { name }
}

nonisolated struct RingColor: Sendable, Equatable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Hardware session 1: the cap reports {0,0,0,1} out of the box —
    /// "firmware default", not black.
    var isFirmwareDefault: Bool { red == 0 && green == 0 && blue == 0 }

    var red255: Int { Self.to255(red) }
    var green255: Int { Self.to255(green) }
    var blue255: Int { Self.to255(blue) }

    private static func to255(_ component: Float) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }

    static let firmwareDefault = RingColor(red: 0, green: 0, blue: 0, alpha: 1)

    static func fromRgb255(_ red: Int, _ green: Int, _ blue: Int) -> RingColor {
        RingColor(
            red: Float(min(max(red, 0), 255)) / 255,
            green: Float(min(max(green, 0), 255)) / 255,
            blue: Float(min(max(blue, 0), 255)) / 255,
            alpha: 1,
        )
    }

    /// Swatches offered on the Reminder screen; the cap only ever receives
    /// 0..1 floats with alpha 1.
    static let presets: [RingPreset] = [
        RingPreset(name: "Blue", color: fromRgb255(0, 120, 255)),
        RingPreset(name: "Cyan", color: fromRgb255(0, 200, 220)),
        RingPreset(name: "Green", color: fromRgb255(40, 200, 80)),
        RingPreset(name: "Yellow", color: fromRgb255(255, 200, 0)),
        RingPreset(name: "Orange", color: fromRgb255(255, 110, 0)),
        RingPreset(name: "Pink", color: fromRgb255(255, 60, 160)),
    ]
}

nonisolated struct ReminderSettings: Sendable, Equatable {
    var mode: Int32
    /// Seconds of day, 1..86400 (midnight = 86400).
    var startSec: Int
    var stopSec: Int
    var intervalSec: Int
    var color: RingColor

    init(mode: Int32, startSec: Int, stopSec: Int, intervalSec: Int, color: RingColor) {
        self.mode = mode
        self.startSec = startSec
        self.stopSec = stopSec
        self.intervalSec = intervalSec
        self.color = color
    }

    static let modeOff: Int32 = 0
    static let modeFixed: Int32 = 1
    static let modeAdaptive: Int32 = 2
}

nonisolated struct DndSettings: Sendable, Equatable {
    var mode: Int32
    var startSec: Int
    var stopSec: Int
    /// Never exposed in the UI; whatever the cap reported is written back unchanged.
    var snoozeMinutes: Int

    init(mode: Int32, startSec: Int, stopSec: Int, snoozeMinutes: Int) {
        self.mode = mode
        self.startSec = startSec
        self.stopSec = stopSec
        self.snoozeMinutes = snoozeMinutes
    }

    static let modeOff: Int32 = 0
    /// The wire value the cap calls ON; HydroCap shows it as "Custom hours".
    static let modeCustom: Int32 = 1
    static let modeAuto: Int32 = 2
}

/// Both settings as last read from the cap (the cap is the source of truth).
nonisolated struct CapReminderConfig: Sendable, Equatable {
    var reminder: ReminderSettings
    var dnd: DndSettings

    init(reminder: ReminderSettings, dnd: DndSettings) {
        self.reminder = reminder
        self.dnd = dnd
    }
}

/// Partial reminder values; nil fields keep what the cap currently holds.
nonisolated struct ReminderValues: Sendable, Equatable {
    var mode: Int32?
    var startSec: Int?
    var stopSec: Int?
    var intervalSec: Int?
    var color: RingColor?

    init(mode: Int32? = nil, startSec: Int? = nil, stopSec: Int? = nil, intervalSec: Int? = nil, color: RingColor? = nil) {
        self.mode = mode
        self.startSec = startSec
        self.stopSec = stopSec
        self.intervalSec = intervalSec
        self.color = color
    }
}

/// Partial quiet-hours values; for `DndSettings.modeAuto` the hours are derived
/// from the reminder.
nonisolated struct DndValues: Sendable, Equatable {
    var mode: Int32?
    var startSec: Int?
    var stopSec: Int?

    init(mode: Int32? = nil, startSec: Int? = nil, stopSec: Int? = nil) {
        self.mode = mode
        self.startSec = startSec
        self.stopSec = stopSec
    }
}

/// What to write: a nil part is not written at all (the URL hooks write one
/// setting at a time; the screen writes both).
nonisolated struct ReminderPatch: Sendable, Equatable {
    var reminder: ReminderValues?
    var dnd: DndValues?

    init(reminder: ReminderValues? = nil, dnd: DndValues? = nil) {
        self.reminder = reminder
        self.dnd = dnd
    }

    var isEmpty: Bool { reminder == nil && dnd == nil }
}

nonisolated struct ReminderValidationError: Error, Equatable, CustomStringConvertible {
    let message: String

    var description: String { message }
}

/// Pure rules shared by the screen, the engine and the tests.
nonisolated enum ReminderRules {
    static let minSecOfDay = 1
    static let maxSecOfDay = 86_400

    /// Interval chips on the screen, in minutes.
    static let intervalChoicesMinutes: [Int] = [15, 20, 30, 45, 60, 90, 120]

    /// Merges `patch` over the cap's `current` values and derives the Auto
    /// quiet hours.
    static func resolve(current: CapReminderConfig, patch: ReminderPatch) -> CapReminderConfig {
        let r = patch.reminder
        var reminder = ReminderSettings(
            mode: r?.mode ?? current.reminder.mode,
            startSec: r?.startSec ?? current.reminder.startSec,
            stopSec: r?.stopSec ?? current.reminder.stopSec,
            intervalSec: r?.intervalSec ?? current.reminder.intervalSec,
            color: r?.color ?? current.reminder.color,
        )
        if reminder.mode == ReminderSettings.modeOff {
            reminder.startSec = usableSecOfDay(reminder.startSec)
            reminder.stopSec = usableSecOfDay(reminder.stopSec)
        }
        let d = patch.dnd
        let dndMode = d?.mode ?? current.dnd.mode
        let dnd: DndSettings
        switch dndMode {
        case DndSettings.modeAuto:
            // Hardware session 1: AUTO holds DND.start = reminder.stop and
            // DND.stop = reminder.start.
            dnd = DndSettings(mode: dndMode, startSec: reminder.stopSec, stopSec: reminder.startSec, snoozeMinutes: current.dnd.snoozeMinutes)
        case DndSettings.modeCustom:
            dnd = DndSettings(
                mode: dndMode,
                startSec: d?.startSec ?? current.dnd.startSec,
                stopSec: d?.stopSec ?? current.dnd.stopSec,
                snoozeMinutes: current.dnd.snoozeMinutes,
            )
        default:
            dnd = DndSettings(
                mode: dndMode,
                startSec: usableSecOfDay(d?.startSec ?? current.dnd.startSec),
                stopSec: usableSecOfDay(d?.stopSec ?? current.dnd.stopSec),
                snoozeMinutes: current.dnd.snoozeMinutes,
            )
        }
        return CapReminderConfig(reminder: reminder, dnd: dnd)
    }

    /// Returns the problem with `config` as text, or nil when it can be written.
    static func validate(_ config: CapReminderConfig) -> String? {
        let r = config.reminder
        if r.mode < ReminderSettings.modeOff || r.mode > ReminderSettings.modeAdaptive {
            return "unknown reminder mode \(r.mode)"
        }
        if r.mode != ReminderSettings.modeOff {
            if r.intervalSec <= 0 { return "interval must be greater than 0" }
            if let problem = secOfDayProblem("active from", r.startSec) { return problem }
            if let problem = secOfDayProblem("active until", r.stopSec) { return problem }
            if r.startSec == r.stopSec { return "active from and until must differ" }
        }
        for component in [r.color.red, r.color.green, r.color.blue, r.color.alpha] {
            if component.isNaN || component < 0 || component > 1 { return "colour components must be within 0..1" }
        }
        let d = config.dnd
        if d.mode < DndSettings.modeOff || d.mode > DndSettings.modeAuto { return "unknown quiet hours mode \(d.mode)" }
        if d.mode == DndSettings.modeCustom {
            if let problem = secOfDayProblem("quiet from", d.startSec) { return problem }
            if let problem = secOfDayProblem("quiet until", d.stopSec) { return problem }
            if d.startSec == d.stopSec { return "quiet from and until must differ" }
        } else {
            if let problem = secOfDayProblem("quiet from", d.startSec) { return problem }
            if let problem = secOfDayProblem("quiet until", d.stopSec) { return problem }
        }
        return nil
    }

    static func validateOrThrow(_ config: CapReminderConfig) throws -> CapReminderConfig {
        if let problem = validate(config) { throw ReminderValidationError(message: problem) }
        return config
    }

    private static func secOfDayProblem(_ label: String, _ value: Int) -> String? {
        (minSecOfDay...maxSecOfDay).contains(value)
            ? nil
            : "\(label) must be between 1 and 86400 seconds of day (got \(value))"
    }

    /// Values not in use by the current mode are still written; keep them
    /// inside the wire range.
    private static func usableSecOfDay(_ value: Int) -> Int {
        (minSecOfDay...maxSecOfDay).contains(value) ? value : maxSecOfDay
    }

    /// Picker → wire: midnight is 86400, never 0.
    static func secOfDay(hour: Int, minute: Int) -> Int {
        let sec = min(max(hour, 0), 23) * 3600 + min(max(minute, 0), 59) * 60
        return sec == 0 ? maxSecOfDay : sec
    }

    static func hourOf(_ secOfDay: Int) -> Int {
        (min(max(secOfDay, 0), maxSecOfDay) % maxSecOfDay) / 3600
    }

    static func minuteOf(_ secOfDay: Int) -> Int {
        (min(max(secOfDay, 0), maxSecOfDay) % 3600) / 60
    }

    static func formatSecOfDay(_ secOfDay: Int) -> String {
        String(format: "%02d:%02d", hourOf(secOfDay), minuteOf(secOfDay))
    }
}
