import Foundation

/// The debug hooks reachable without a cable, mirroring the Android ADB hooks:
///
///     hydrocap://scan
///     hydrocap://sync
///     hydrocap://tof
///     hydrocap://read-reminder
///     hydrocap://read-all-settings
///     hydrocap://set-reminder?state=2&start=28800&stop=78300&interval=1800&r=0&g=0.5&b=1
///     hydrocap://set-dnd?state=2&start=78300&stop=28800
///
/// Every extra is optional; absent ones keep the cap's current value, and r/g/b
/// must be given together (exactly like `DEBUG_SET_REMINDER`).
nonisolated enum DebugRoute: Equatable, Sendable {
    case scan
    case sync
    case liveTof
    case readReminder
    case readAllSettings
    case setReminder(ReminderValues)
    case setDnd(DndValues)
}

nonisolated enum DebugRouteParser {
    static let scheme = "hydrocap"

    /// Host-based parsing: `hydrocap://sync` → host "sync".
    static func parse(_ url: URL) -> DebugRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host() ?? "").lowercased()
        let query = queryValues(url)
        switch host {
        case "scan": return .scan
        case "sync": return .sync
        case "tof": return .liveTof
        case "read-reminder": return .readReminder
        case "read-all-settings": return .readAllSettings
        case "set-reminder":
            let hasColor = query["r"] != nil || query["g"] != nil || query["b"] != nil
            return .setReminder(ReminderValues(
                mode: int32(query["state"]),
                startSec: int(query["start"]),
                stopSec: int(query["stop"]),
                intervalSec: int(query["interval"]),
                color: hasColor ? RingColor(
                    red: float(query["r"]) ?? 0,
                    green: float(query["g"]) ?? 0,
                    blue: float(query["b"]) ?? 0,
                    alpha: 1,
                ) : nil,
            ))
        case "set-dnd":
            return .setDnd(DndValues(mode: int32(query["state"]), startSec: int(query["start"]), stopSec: int(query["stop"])))
        default: return nil
        }
    }

    static func parse(_ string: String) -> DebugRoute? {
        guard let url = URL(string: string) else { return nil }
        return parse(url)
    }

    private static func queryValues(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var values: [String: String] = [:]
        for item in items {
            if let value = item.value { values[item.name.lowercased()] = value }
        }
        return values
    }

    private static func int(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return Int(raw)
    }

    private static func int32(_ raw: String?) -> Int32? {
        guard let value = int(raw) else { return nil }
        return Int32(exactly: value)
    }

    private static func float(_ raw: String?) -> Float? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return Float(raw)
    }
}
