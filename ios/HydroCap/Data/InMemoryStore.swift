import Foundation

/// In-memory `HydroCapStore` used for previews, tests and the Mac Catalyst
/// typecheck fallback (the SwiftData store is the production implementation).
/// An actor, so it is `Sendable` without extra ceremony.
actor InMemoryStore: HydroCapStore {
    private var tofLog: [Int64: TofLogEntry] = [:]
    private var activationLog: [Int64: ActivationLogEntry] = [:]
    private var drinkEvents: [Int64: DrinkEvent] = [:]
    private var batterySamples: [Int64: BatterySample] = [:]
    private var devices: [String: DeviceRecord] = [:]
    private var healthSync: [Int64: HealthSyncRecord] = [:]

    init() {}

    // MARK: TofLogStore

    func insertTofLog(_ entries: [TofLogEntry]) async throws -> Int {
        var inserted = 0
        for entry in entries where tofLog[entry.timestamp] == nil {
            tofLog[entry.timestamp] = entry
            inserted += 1
        }
        return inserted
    }

    func tofLogMaxTimestamp() async throws -> Int64? { tofLog.keys.max() }

    func allTofLog() async throws -> [TofLogEntry] { tofLog.values.sorted { $0.timestamp < $1.timestamp } }

    func latestTofLog() async throws -> TofLogEntry? { try await allTofLog().last }

    func tofLogCount() async throws -> Int { tofLog.count }

    func deleteAllTofLog() async throws { tofLog.removeAll() }

    // MARK: ActivationLogStore

    func insertActivationLog(_ entries: [ActivationLogEntry]) async throws -> Int {
        var inserted = 0
        for entry in entries where activationLog[entry.timestamp] == nil {
            activationLog[entry.timestamp] = entry
            inserted += 1
        }
        return inserted
    }

    func activationLogMaxTimestamp() async throws -> Int64? { activationLog.keys.max() }

    func allActivationLog() async throws -> [ActivationLogEntry] { activationLog.values.sorted { $0.timestamp < $1.timestamp } }

    func activationLogCount() async throws -> Int { activationLog.count }

    func deleteAllActivationLog() async throws { activationLog.removeAll() }

    // MARK: DrinkEventStore

    func upsertDrinkEvents(_ events: [DrinkEvent]) async throws {
        for event in events { drinkEvents[event.timestamp] = event }
    }

    func allDrinkEvents() async throws -> [DrinkEvent] { drinkEvents.values.sorted { $0.timestamp < $1.timestamp } }

    func drinkEvents(fromSec: Int64, toSec: Int64) async throws -> [DrinkEvent] {
        drinkEvents.values
            .filter { $0.timestamp >= fromSec && $0.timestamp < toSec }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func deleteDrinkEvents(timestamps: [Int64]) async throws {
        for timestamp in timestamps { drinkEvents.removeValue(forKey: timestamp) }
    }

    func deleteAllDrinkEvents() async throws { drinkEvents.removeAll() }

    // MARK: BatterySampleStore

    func insertBatterySample(_ sample: BatterySample) async throws { batterySamples[sample.timestamp] = sample }

    func latestBatterySample() async throws -> BatterySample? {
        batterySamples.values.max { $0.timestamp < $1.timestamp }
    }

    func deleteAllBatterySamples() async throws { batterySamples.removeAll() }

    // MARK: DeviceStore

    func upsertDevice(_ device: DeviceRecord) async throws { devices[device.deviceIdHex] = device }

    func device(deviceIdHex: String) async throws -> DeviceRecord? { devices[deviceIdHex] }

    func deleteAllDevices() async throws { devices.removeAll() }

    // MARK: HealthSyncStore

    func allHealthSyncRecords() async throws -> [HealthSyncRecord] { healthSync.values.sorted { $0.timestamp < $1.timestamp } }

    func upsertHealthSyncRecords(_ records: [HealthSyncRecord]) async throws {
        for record in records { healthSync[record.timestamp] = record }
    }

    func deleteHealthSyncRecords(timestamps: [Int64]) async throws {
        for timestamp in timestamps { healthSync.removeValue(forKey: timestamp) }
    }

    func healthSyncRecordCount() async throws -> Int { healthSync.count }

    func deleteAllHealthSyncRecords() async throws { healthSync.removeAll() }
}
