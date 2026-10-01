import Foundation

/// Wire ↔ domain mapping for the reminder ring and quiet hours.
nonisolated enum ReminderMapping {

    static func fromProto(_ settings: CapHydroReminderSettings) -> ReminderSettings {
        ReminderSettings(
            mode: settings.state,
            startSec: Int(settings.startTimeInSec),
            stopSec: Int(settings.stopTimeInSec),
            intervalSec: Int(settings.intervalInSec),
            color: settings.color.map { RingColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
                ?? RingColor.firmwareDefault,
        )
    }

    static func fromProto(_ settings: CapDoNotDisturbSettings) -> DndSettings {
        DndSettings(
            mode: settings.state,
            startSec: Int(settings.startTimeInSec),
            stopSec: Int(settings.stopTimeInSec),
            snoozeMinutes: Int(settings.snoozeTimeInMinutes),
        )
    }

    static func toProto(_ settings: ReminderSettings) -> CapHydroReminderSettings {
        CapHydroReminderSettings(
            state: settings.mode,
            startTimeInSec: UInt32(clamping: settings.startSec),
            stopTimeInSec: UInt32(clamping: settings.stopSec),
            intervalInSec: UInt32(clamping: settings.intervalSec),
            color: CapColor(
                red: settings.color.red,
                green: settings.color.green,
                blue: settings.color.blue,
                alpha: settings.color.alpha,
            ),
        )
    }

    static func toProto(_ settings: DndSettings) -> CapDoNotDisturbSettings {
        CapDoNotDisturbSettings(
            state: settings.mode,
            startTimeInSec: UInt32(clamping: settings.startSec),
            stopTimeInSec: UInt32(clamping: settings.stopSec),
            snoozeTimeInMinutes: UInt32(clamping: settings.snoozeMinutes),
        )
    }

    static func describe(_ config: CapReminderConfig) -> String {
        let r = config.reminder
        let d = config.dnd
        return "reminder{mode=\(r.mode) start=\(r.startSec) stop=\(r.stopSec) interval=\(r.intervalSec)s " +
            "color=(\(r.color.red),\(r.color.green),\(r.color.blue),\(r.color.alpha))} " +
            "dnd{mode=\(d.mode) start=\(d.startSec) stop=\(d.stopSec) snooze=\(d.snoozeMinutes)min}"
    }
}
