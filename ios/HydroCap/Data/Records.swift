import Foundation

/// Value records for everything HydroCap persists.
///
/// They are plain `Sendable` structs so the algorithm, the drink-event builder,
/// the health sync planner and the tests stay free of SwiftData. The SwiftData
/// `@Model` classes in `Data/SwiftDataModels.swift` are thin adapters that map
/// to and from these values.

/// Raw ToF log record as pulled from the cap (protocol doc §4, `CapTofLog`).
nonisolated struct TofLogEntry: Sendable, Equatable {
    /// Unix seconds; the cap guarantees uniqueness per entry.
    var timestamp: Int64
    var triggerType: Int32
    var distanceMm: Int
    var kcps: Int
    var uvLedTempOhm: Float

    init(timestamp: Int64, triggerType: Int32, distanceMm: Int, kcps: Int, uvLedTempOhm: Float) {
        self.timestamp = timestamp
        self.triggerType = triggerType
        self.distanceMm = distanceMm
        self.kcps = kcps
        self.uvLedTempOhm = uvLedTempOhm
    }
}

/// UV activation record (`CapActivationLog`), doubles as battery SoC history.
nonisolated struct ActivationLogEntry: Sendable, Equatable {
    var timestamp: Int64
    var mode: Int32
    var batterySocPercent: Int

    init(timestamp: Int64, mode: Int32, batterySocPercent: Int) {
        self.timestamp = timestamp
        self.mode = mode
        self.batterySocPercent = batterySocPercent
    }
}

/// A counted drink derived from the ToF log by `TofAlgorithm`.
nonisolated struct DrinkEvent: Sendable, Equatable {
    /// Unix seconds of the reading that produced the event.
    var timestamp: Int64
    var volumeMl: Double
    /// Timestamp of the source ToF log entry (== `timestamp` today; kept
    /// explicit for the HealthKit sync identifiers).
    var sourceLogTimestamp: Int64
    /// Bottle profile id the volume was computed with.
    var profileId: String
    /// Incremented when the value changes so HealthKit can detect updates.
    var version: Int64

    init(timestamp: Int64, volumeMl: Double, sourceLogTimestamp: Int64, profileId: String, version: Int64 = 1) {
        self.timestamp = timestamp
        self.volumeMl = volumeMl
        self.sourceLogTimestamp = sourceLogTimestamp
        self.profileId = profileId
        self.version = version
    }
}

nonisolated struct BatterySample: Sendable, Equatable {
    var timestamp: Int64
    var percent: Int

    init(timestamp: Int64, percent: Int) {
        self.timestamp = timestamp
        self.percent = percent
    }
}

/// One drink event as written to the health store. Lets the writer skip
/// unchanged events, re-write bumped versions and delete records for events
/// that no longer exist — without reading the health store back.
nonisolated struct HealthSyncRecord: Sendable, Equatable {
    /// `DrinkEvent.timestamp` the record was written for.
    var timestamp: Int64
    /// The exact sync identifier used, so deletes hit the record we wrote even
    /// after re-pairing.
    var clientRecordId: String
    /// `DrinkEvent.version` at the time of the write.
    var writtenVersion: Int64
    var writtenAtMs: Int64

    init(timestamp: Int64, clientRecordId: String, writtenVersion: Int64, writtenAtMs: Int64) {
        self.timestamp = timestamp
        self.clientRecordId = clientRecordId
        self.writtenVersion = writtenVersion
        self.writtenAtMs = writtenAtMs
    }
}

/// The paired cap. The cap uses a rotating resolvable private address, so the
/// identity is the advertised name + decoded serial; `lastAddress` is only the
/// address seen at the most recent scan and must never be used to connect
/// without a fresh scan.
nonisolated struct DeviceRecord: Sendable, Equatable {
    var deviceIdHex: String
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

    init(
        deviceIdHex: String,
        name: String,
        lastAddress: String? = nil,
        bottleSizeMl: Int? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        serial: String? = nil,
        firmwareRevision: String? = nil,
        hardwareRevision: String? = nil,
        softwareRevision: String? = nil,
        lastSeenMs: Int64,
    ) {
        self.deviceIdHex = deviceIdHex
        self.name = name
        self.lastAddress = lastAddress
        self.bottleSizeMl = bottleSizeMl
        self.manufacturer = manufacturer
        self.model = model
        self.serial = serial
        self.firmwareRevision = firmwareRevision
        self.hardwareRevision = hardwareRevision
        self.softwareRevision = softwareRevision
        self.lastSeenMs = lastSeenMs
    }
}
