import CoreBluetooth
import Foundation

/// Filtered BLE scan over `CapCentral`. The scan filter is the Device
/// Information service `0x180A` (present in the primary advertisement,
/// hardware session 1); results are matched in software by name ("larq",
/// case-insensitive) or the Nordic manufacturer prefix "CAP" in the scan
/// response (which iOS may omit in the background).
///
/// The cap rotates its address, so callers must always connect to the
/// identifier of a *fresh* scan result — never to a stored one.
@MainActor
final class BleScanner {
    nonisolated static let tag = "scan"
    nonisolated static let defaultScanSeconds = 20.0
    nonisolated static let connectScanSeconds = 30.0
    /// Foreground scans re-report every advertisement (live RSSI) for 15 s.
    nonisolated static let foregroundScanWindowSeconds = 15.0

    private let central: CapCentral
    private let debugLog: DebugLog

    init(central: CapCentral, debugLog: DebugLog) {
        self.central = central
        self.debugLog = debugLog
    }

    var isBluetoothEnabled: Bool { central.isPoweredOn }

    /// Starts a foreground scan (duplicates on) and returns everything seen
    /// within `seconds`.
    func scanFor(seconds: Double) async -> [DiscoveredCap] {
        central.startScan(allowDuplicates: true, purpose: "foreground \(Int(seconds)) s")
        defer { central.stopScan() }
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        if let error = central.lastScanError {
            debugLog.log(Self.tag, "scan error: \(error)")
        }
        return central.discoveredSorted
    }

    /// Returns the first cap matching `predicate`, or throws after `seconds`.
    func findCap(seconds: Double, predicate: (DiscoveredCap) -> Bool) async throws -> DiscoveredCap {
        central.startScan(allowDuplicates: false, purpose: "connect")
        defer { central.stopScan() }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let error = central.lastScanError {
                throw BleConnectionError("BLE scan failed: \(error)")
            }
            if let cap = central.discoveredSorted.first(where: predicate) {
                return cap
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        if let error = central.lastScanError {
            throw BleConnectionError("BLE scan failed: \(error)")
        }
        throw CapNotFoundError("no cap matched within \(Int(seconds)) s")
    }

    /// Background scan: service-filtered, no duplicates, kept running while a
    /// cap is paired and background sync is enabled. iOS wakes the app on
    /// discovery; the caller restarts the scan after each sync.
    func startBackgroundScan() {
        central.startScan(allowDuplicates: false, purpose: "background service-filtered")
    }

    func stopBackgroundScan() {
        central.stopScan()
    }
}
