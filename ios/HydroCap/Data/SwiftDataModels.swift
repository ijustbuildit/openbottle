import Foundation

#if !HYDROCAP_TYPE_CHECK

import SwiftData

/// Production persistence: SwiftData `@Model` classes mapping the plain records
/// in `Data/Records.swift` 1:1 (same columns as the Room schema of the Android
/// port), plus a `@ModelActor` store that implements `HydroCapStore`.
///
/// This whole file is skipped during the Mac Catalyst typecheck
/// (`-D HYDROCAP_TYPE_CHECK`): the SwiftData macros plugin ships only with
/// Xcode, so `@Model` / `@ModelActor` cannot be expanded by the Command Line
/// Tools toolchain. `ios/scripts/typecheck.sh` runs a parse-only pass over it
/// and `Data/InMemoryStore.swift` provides the fallback the typecheck uses.

@Model
final class TofLogEntryModel {
    @Attribute(.unique) var timestamp: Int64
    var triggerType: Int32
    var distanceMm: Int
    var kcps: Int
    var uvLedTempOhm: Float

    init(_ entry: TofLogEntry) {
        timestamp = entry.timestamp
        triggerType = entry.triggerType
        distanceMm = entry.distanceMm
        kcps = entry.kcps
        uvLedTempOhm = entry.uvLedTempOhm
    }

    var value: TofLogEntry {
        TofLogEntry(
            timestamp: timestamp,
            triggerType: triggerType,
            distanceMm: distanceMm,
            kcps: kcps,
            uvLedTempOhm: uvLedTempOhm,
        )
    }
}

@Model
final class ActivationLogEntryModel {
    @Attribute(.unique) var timestamp: Int64
    var mode: Int32
    var batterySocPercent: Int

    init(_ entry: ActivationLogEntry) {
        timestamp = entry.timestamp
        mode = entry.mode
        batterySocPercent = entry.batterySocPercent
    }

    var value: ActivationLogEntry {
        ActivationLogEntry(timestamp: timestamp, mode: mode, batterySocPercent: batterySocPercent)
    }
}

@Model
final class DrinkEventModel {
    @Attribute(.unique) var timestamp: Int64
    var volumeMl: Double
    var sourceLogTimestamp: Int64
    var profileId: String
    var version: Int64

    init(_ event: DrinkEvent) {
        timestamp = event.timestamp
        volumeMl = event.volumeMl
        sourceLogTimestamp = event.sourceLogTimestamp
        profileId = event.profileId
        version = event.version
    }

    var value: DrinkEvent {
        DrinkEvent(
            timestamp: timestamp,
            volumeMl: volumeMl,
            sourceLogTimestamp: sourceLogTimestamp,
            profileId: profileId,
            version: version,
        )
    }
}

@Model
final class BatterySampleModel {
    @Attribute(.unique) var timestamp: Int64
    var percent: Int

    init(_ sample: BatterySample) {
        timestamp = sample.timestamp
        percent = sample.percent
    }

    var value: BatterySample { BatterySample(timestamp: timestamp, percent: percent) }
}

@Model
final class HealthSyncRecordModel {
    @Attribute(.unique) var timestamp: Int64
    var clientRecordId: String
    var writtenVersion: Int64
    var writtenAtMs: Int64

    init(_ record: HealthSyncRecord) {
        timestamp = record.timestamp
        clientRecordId = record.clientRecordId
        writtenVersion = record.writtenVersion
        writtenAtMs = record.writtenAtMs
    }

    var value: HealthSyncRecord {
        HealthSyncRecord(
            timestamp: timestamp,
            clientRecordId: clientRecordId,
            writtenVersion: writtenVersion,
            writtenAtMs: writtenAtMs,
        )
    }
}

@Model
final class DeviceRecordModel {
    @Attribute(.unique) var deviceIdHex: String
    var name: String
    var lastAddress: String?
    var bottleSizeMl: Int?
    var manufacturer: String?
    var model: String?
    var serial: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
    var lastSeenMs: Int64

    init(_ device: DeviceRecord) {
        deviceIdHex = device.deviceIdHex
        name = device.name
        lastAddress = device.lastAddress
        bottleSizeMl = device.bottleSizeMl
        manufacturer = device.manufacturer
        model = device.model
        serial = device.serial
        firmwareRevision = device.firmwareRevision
        hardwareRevision = device.hardwareRevision
        softwareRevision = device.softwareRevision
        lastSeenMs = device.lastSeenMs
    }

    var value: DeviceRecord {
        DeviceRecord(
            deviceIdHex: deviceIdHex,
            name: name,
            lastAddress: lastAddress,
            bottleSizeMl: bottleSizeMl,
            manufacturer: manufacturer,
            model: model,
            serial: serial,
            firmwareRevision: firmwareRevision,
            hardwareRevision: hardwareRevision,
            softwareRevision: softwareRevision,
            lastSeenMs: lastSeenMs,
        )
    }
}

/// One actor for the whole database: a single serial executor for the
/// background sync, the UI and the background task.
@ModelActor
actor SwiftDataStore: HydroCapStore {

    // MARK: TofLogStore

    func insertTofLog(_ entries: [TofLogEntry]) async throws -> Int {
        var inserted = 0
        for entry in entries {
            let timestamp = entry.timestamp
            let descriptor = FetchDescriptor<TofLogEntryModel>(predicate: #Predicate { $0.timestamp == timestamp })
            if try modelContext.fetchCount(descriptor) == 0 {
                modelContext.insert(TofLogEntryModel(entry))
                inserted += 1
            }
        }
        try modelContext.save()
        return inserted
    }

    func tofLogMaxTimestamp() async throws -> Int64? {
        var descriptor = FetchDescriptor<TofLogEntryModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.timestamp
    }

    func allTofLog() async throws -> [TofLogEntry] {
        let descriptor = FetchDescriptor<TofLogEntryModel>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func latestTofLog() async throws -> TofLogEntry? {
        var descriptor = FetchDescriptor<TofLogEntryModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.value
    }

    func tofLogCount() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<TofLogEntryModel>())
    }

    func deleteAllTofLog() async throws {
        try modelContext.delete(model: TofLogEntryModel.self)
        try modelContext.save()
    }

    // MARK: ActivationLogStore

    func insertActivationLog(_ entries: [ActivationLogEntry]) async throws -> Int {
        var inserted = 0
        for entry in entries {
            let timestamp = entry.timestamp
            let descriptor = FetchDescriptor<ActivationLogEntryModel>(predicate: #Predicate { $0.timestamp == timestamp })
            if try modelContext.fetchCount(descriptor) == 0 {
                modelContext.insert(ActivationLogEntryModel(entry))
                inserted += 1
            }
        }
        try modelContext.save()
        return inserted
    }

    func activationLogMaxTimestamp() async throws -> Int64? {
        var descriptor = FetchDescriptor<ActivationLogEntryModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.timestamp
    }

    func allActivationLog() async throws -> [ActivationLogEntry] {
        let descriptor = FetchDescriptor<ActivationLogEntryModel>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func activationLogCount() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ActivationLogEntryModel>())
    }

    func deleteAllActivationLog() async throws {
        try modelContext.delete(model: ActivationLogEntryModel.self)
        try modelContext.save()
    }

    // MARK: DrinkEventStore

    func upsertDrinkEvents(_ events: [DrinkEvent]) async throws {
        for event in events {
            let timestamp = event.timestamp
            let descriptor = FetchDescriptor<DrinkEventModel>(predicate: #Predicate { $0.timestamp == timestamp })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.volumeMl = event.volumeMl
                existing.sourceLogTimestamp = event.sourceLogTimestamp
                existing.profileId = event.profileId
                existing.version = event.version
            } else {
                modelContext.insert(DrinkEventModel(event))
            }
        }
        try modelContext.save()
    }

    func allDrinkEvents() async throws -> [DrinkEvent] {
        let descriptor = FetchDescriptor<DrinkEventModel>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func drinkEvents(fromSec: Int64, toSec: Int64) async throws -> [DrinkEvent] {
        let descriptor = FetchDescriptor<DrinkEventModel>(
            predicate: #Predicate { $0.timestamp >= fromSec && $0.timestamp < toSec },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        )
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func deleteDrinkEvents(timestamps: [Int64]) async throws {
        for timestamp in timestamps {
            let descriptor = FetchDescriptor<DrinkEventModel>(predicate: #Predicate { $0.timestamp == timestamp })
            for model in try modelContext.fetch(descriptor) { modelContext.delete(model) }
        }
        try modelContext.save()
    }

    func deleteAllDrinkEvents() async throws {
        try modelContext.delete(model: DrinkEventModel.self)
        try modelContext.save()
    }

    // MARK: BatterySampleStore

    func insertBatterySample(_ sample: BatterySample) async throws {
        let timestamp = sample.timestamp
        let descriptor = FetchDescriptor<BatterySampleModel>(predicate: #Predicate { $0.timestamp == timestamp })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.percent = sample.percent
        } else {
            modelContext.insert(BatterySampleModel(sample))
        }
        try modelContext.save()
    }

    func latestBatterySample() async throws -> BatterySample? {
        var descriptor = FetchDescriptor<BatterySampleModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.value
    }

    func deleteAllBatterySamples() async throws {
        try modelContext.delete(model: BatterySampleModel.self)
        try modelContext.save()
    }

    // MARK: DeviceStore

    func upsertDevice(_ device: DeviceRecord) async throws {
        let deviceIdHex = device.deviceIdHex
        let descriptor = FetchDescriptor<DeviceRecordModel>(predicate: #Predicate { $0.deviceIdHex == deviceIdHex })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = device.name
            existing.lastAddress = device.lastAddress
            existing.bottleSizeMl = device.bottleSizeMl
            existing.manufacturer = device.manufacturer
            existing.model = device.model
            existing.serial = device.serial
            existing.firmwareRevision = device.firmwareRevision
            existing.hardwareRevision = device.hardwareRevision
            existing.softwareRevision = device.softwareRevision
            existing.lastSeenMs = device.lastSeenMs
        } else {
            modelContext.insert(DeviceRecordModel(device))
        }
        try modelContext.save()
    }

    func device(deviceIdHex: String) async throws -> DeviceRecord? {
        let descriptor = FetchDescriptor<DeviceRecordModel>(predicate: #Predicate { $0.deviceIdHex == deviceIdHex })
        return try modelContext.fetch(descriptor).first?.value
    }

    func deleteAllDevices() async throws {
        try modelContext.delete(model: DeviceRecordModel.self)
        try modelContext.save()
    }

    // MARK: HealthSyncStore

    func allHealthSyncRecords() async throws -> [HealthSyncRecord] {
        let descriptor = FetchDescriptor<HealthSyncRecordModel>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func upsertHealthSyncRecords(_ records: [HealthSyncRecord]) async throws {
        for record in records {
            let timestamp = record.timestamp
            let descriptor = FetchDescriptor<HealthSyncRecordModel>(predicate: #Predicate { $0.timestamp == timestamp })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.clientRecordId = record.clientRecordId
                existing.writtenVersion = record.writtenVersion
                existing.writtenAtMs = record.writtenAtMs
            } else {
                modelContext.insert(HealthSyncRecordModel(record))
            }
        }
        try modelContext.save()
    }

    func deleteHealthSyncRecords(timestamps: [Int64]) async throws {
        for timestamp in timestamps {
            let descriptor = FetchDescriptor<HealthSyncRecordModel>(predicate: #Predicate { $0.timestamp == timestamp })
            for model in try modelContext.fetch(descriptor) { modelContext.delete(model) }
        }
        try modelContext.save()
    }

    func healthSyncRecordCount() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<HealthSyncRecordModel>())
    }

    func deleteAllHealthSyncRecords() async throws {
        try modelContext.delete(model: HealthSyncRecordModel.self)
        try modelContext.save()
    }
}

/// Opens the on-disk store. No destructive fallback: the ToF history is months
/// of data (hardware session 1 found entries from April).
enum StoreFactory {
    static func make() throws -> any HydroCapStore {
        let schema = Schema([
            TofLogEntryModel.self,
            ActivationLogEntryModel.self,
            DrinkEventModel.self,
            BatterySampleModel.self,
            HealthSyncRecordModel.self,
            DeviceRecordModel.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        return SwiftDataStore(modelContainer: container)
    }
}

#else

/// Typecheck-only fallback: the SwiftData layer above needs the macro plugin
/// that only Xcode ships.
enum StoreFactory {
    static func make() throws -> any HydroCapStore {
        InMemoryStore()
    }
}

#endif
