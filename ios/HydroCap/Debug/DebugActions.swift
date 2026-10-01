import Foundation

/// The URL-scheme debug hooks (`hydrocap://…`), the same actions as the
/// Debug-screen buttons — the iOS answer to the Android ADB intents.
///
///     hydrocap://scan
///     hydrocap://sync
///     hydrocap://tof
///     hydrocap://read-reminder
///     hydrocap://read-all-settings
///     hydrocap://set-reminder?state=2&start=28800&stop=78300&interval=1800&r=0&g=0.5&b=1
///     hydrocap://set-dnd?state=2&start=78300&stop=28800
///
/// Live in Debug builds only (see `HydroCapApp`): a release build ignores them.
@MainActor
final class DebugActions {
    nonisolated static let tag = "debug"

    private let engine: SyncEngine
    private let scanner: BleScanner
    private let settings: SettingsStore
    private let debugLog: DebugLog

    init(engine: SyncEngine, scanner: BleScanner, settings: SettingsStore, debugLog: DebugLog) {
        self.engine = engine
        self.scanner = scanner
        self.settings = settings
        self.debugLog = debugLog
    }

    func handle(_ route: DebugRoute) {
        debugLog.log(Self.tag, "=== \(Self.describe(route)) ===")
        Task { @MainActor in
            do {
                switch route {
                case .scan:
                    await scan()
                case .sync:
                    let summary = try await engine.sync()
                    debugLog.log(Self.tag, "sync finished: \(summary.label)")
                case .liveTof:
                    let measurement = try await engine.liveTof()
                    debugLog.log(Self.tag, "live ToF: \(measurement.distanceMm) mm, \(measurement.kcps) kcps")
                case .readReminder:
                    let config = try await engine.readReminder()
                    debugLog.log(Self.tag, "cap holds reminder{\(ReminderMapping.describe(config))}")
                case .readAllSettings:
                    let lines = try await engine.readAllSettings()
                    debugLog.log(Self.tag, "read all settings: \(lines.count) line(s)")
                case .setReminder(let values):
                    debugLog.log(Self.tag, "set reminder \(Self.describe(values))")
                    let config = try await engine.applyReminder(ReminderPatch(reminder: values))
                    debugLog.log(Self.tag, "cap now holds \(ReminderMapping.describe(config))")
                case .setDnd(let values):
                    debugLog.log(Self.tag, "set dnd \(Self.describe(values))")
                    let config = try await engine.applyReminder(ReminderPatch(dnd: values))
                    debugLog.log(Self.tag, "cap now holds \(ReminderMapping.describe(config))")
                }
            } catch {
                debugLog.error(Self.tag, "\(Self.describe(route)) failed", error: error)
            }
        }
    }

    /// 20 s scan; every match is logged with name, identifier, RSSI, decoded
    /// serial and the raw manufacturer data.
    func scan() async {
        debugLog.log(Self.tag, "scan for \(Int(BleScanner.defaultScanSeconds)) s")
        let caps = await scanner.scanFor(seconds: BleScanner.defaultScanSeconds)
        debugLog.log(Self.tag, "scan finished: \(caps.count) cap(s)")
        for cap in caps {
            debugLog.log(
                Self.tag,
                "RESULT name=\(cap.name ?? "?") id=\(cap.address) rssi=\(cap.rssi) serial=\(cap.deviceIdHex ?? "?") adv=\(cap.rawAdvertisementHex ?? "?")",
            )
        }
    }

    private static func describe(_ route: DebugRoute) -> String {
        switch route {
        case .scan: "scan"
        case .sync: "sync"
        case .liveTof: "live ToF"
        case .readReminder: "read reminder"
        case .readAllSettings: "read all settings"
        case .setReminder(let values): "set reminder \(describe(values))"
        case .setDnd(let values): "set dnd \(describe(values))"
        }
    }

    private static func describe(_ values: ReminderValues) -> String {
        var parts: [String] = []
        if let mode = values.mode { parts.append("state=\(mode)") }
        if let start = values.startSec { parts.append("start=\(start)") }
        if let stop = values.stopSec { parts.append("stop=\(stop)") }
        if let interval = values.intervalSec { parts.append("interval=\(interval)") }
        if let color = values.color { parts.append("rgb=(\(color.red),\(color.green),\(color.blue))") }
        return parts.isEmpty ? "(no values)" : parts.joined(separator: " ")
    }

    private static func describe(_ values: DndValues) -> String {
        var parts: [String] = []
        if let mode = values.mode { parts.append("state=\(mode)") }
        if let start = values.startSec { parts.append("start=\(start)") }
        if let stop = values.stopSec { parts.append("stop=\(stop)") }
        return parts.isEmpty ? "(no values)" : parts.joined(separator: " ")
    }
}
