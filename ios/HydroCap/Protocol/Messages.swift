import Foundation

// Message structs for exactly the types in android/app/src/main/proto/hydrocap.proto.
// Enum values are kept as their raw wire numbers so an unknown value the cap
// reports survives a read → write round trip untouched (the same reason the
// Kotlin port keeps `*Value` fields). Names never reach the wire.

// ---------------------------------------------------------------------------
// Enums (raw numbers + display names)
// ---------------------------------------------------------------------------

nonisolated enum CapResponseCode {
    static let fail: Int32 = 0
    static let success: Int32 = 1
    static let notSupported: Int32 = 2

    static func name(_ value: Int32) -> String {
        switch value {
        case fail: "FAIL"
        case success: "SUCCESS"
        case notSupported: "NOT_SUPPORTED"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapUiState {
    static let unspecified: Int32 = 0
    static let batteryLow: Int32 = 7
    static let charging: Int32 = 8
    static let charged: Int32 = 9
    static let allOff: Int32 = 15

    static func name(_ value: Int32) -> String {
        switch value {
        case unspecified: "UI_STATE_UNSPECIFIED"
        case batteryLow: "UI_STATE_BATTERY_LOW"
        case charging: "UI_STATE_CHARGING"
        case charged: "UI_STATE_CHARGED"
        case allOff: "UI_STATE_ALL_OFF"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapPowerSavingMode {
    static let unspecified: Int32 = 0
    /// Golden vector and hardware session both show OFF encoded as 1.
    static let off: Int32 = 1

    static func name(_ value: Int32) -> String {
        switch value {
        case unspecified: "POWER_SAVING_MODE_UNSPECIFIED"
        case off: "POWER_SAVING_MODE_OFF"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapTofMode {
    static let unspecified: Int32 = 0
    static let event: Int32 = 2

    static func name(_ value: Int32) -> String {
        switch value {
        case unspecified: "DISPLAY_MODE_UNSPECIFIED"
        case event: "DISPLAY_MODE_EVENT"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapTofTriggerType {
    static let unspecified: Int32 = 0
    static let interval: Int32 = 1
    static let cap: Int32 = 2
    static let capOnFlapOpenSip: Int32 = 4

    static func name(_ value: Int32) -> String {
        switch value {
        case unspecified: "TYPE_UNSPECIFIED"
        case interval: "TYPE_INTERVAL"
        case cap: "TYPE_CAP"
        case capOnFlapOpenSip: "TYPE_CAP_ON_FLAP_OPEN_SIP"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapLogQuerySearchAlgo {
    static let timestamp: Int32 = 0

    static func name(_ value: Int32) -> String {
        switch value {
        case timestamp: "SEARCH_ALGO_TIMESTAMP"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapUvActivationMode {
    static let maintenance: Int32 = 0

    static func name(_ value: Int32) -> String {
        switch value {
        case maintenance: "UV_ACTIVATION_MAINTENANCE"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapHydroReminderState {
    static let off: Int32 = 0
    static let intervalFixed: Int32 = 1
    static let intervalAdaptive: Int32 = 2

    static func name(_ value: Int32) -> String {
        switch value {
        case off: "REMINDER_STATE_OFF"
        case intervalFixed: "REMINDER_STATE_INTERVAL_FIXED"
        case intervalAdaptive: "REMINDER_STATE_INTERVAL_ADAPTIVE"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

nonisolated enum CapDoNotDisturbState {
    static let off: Int32 = 0
    static let on: Int32 = 1
    static let auto: Int32 = 2

    static func name(_ value: Int32) -> String {
        switch value {
        case off: "DND_STATE_OFF"
        case on: "DND_STATE_ON"
        case auto: "DND_STATE_AUTO"
        default: "UNRECOGNIZED(\(value))"
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

nonisolated private extension Float {
    /// Stable rendering for the debug log.
    var protoTextValue: String {
        if self == rounded() && abs(self) < 1e15 { return String(Int64(self)) }
        return String(self)
    }
}

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

/// `google.protobuf.Any` (type.googleapis.com/<Message> type URLs).
nonisolated struct AnyMessage: ProtoMessage, Equatable {
    static let protoName = "google.protobuf.Any"
    var typeUrl: String = ""
    var value: Data = Data()

    init(typeUrl: String = "", value: Data = Data()) {
        self.typeUrl = typeUrl
        self.value = value
    }

    func write(to writer: inout ProtoWriter) {
        writer.string(1, typeUrl)
        writer.bytes(2, value)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): typeUrl = try reader.readString()
            case (2, ProtoWireType.lengthDelimited): value = try reader.readBytes()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { "type_url: \"\(typeUrl)\" value_len: \(value.count)" }
}

nonisolated struct CapBleRequest: ProtoMessage, Equatable {
    static let protoName = "CapBleRequest"
    var requestId: UInt32 = 0
    var body: AnyMessage?

    init(requestId: UInt32 = 0, body: AnyMessage? = nil) {
        self.requestId = requestId
        self.body = body
    }

    func write(to writer: inout ProtoWriter) {
        writer.fixed32(1, requestId)
        if let body { writer.message(2, body.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.fixed32): requestId = try reader.readFixed32()
            case (2, ProtoWireType.lengthDelimited): body = try AnyMessage(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { "requestId: \(requestId)" + (body.map { " body { \($0.protoText) }" } ?? "") }
}

nonisolated struct CapBleResponse: ProtoMessage, Equatable {
    static let protoName = "CapBleResponse"
    var requestId: UInt32 = 0
    var code: Int32 = 0
    var body: AnyMessage?

    init(requestId: UInt32 = 0, code: Int32 = 0, body: AnyMessage? = nil) {
        self.requestId = requestId
        self.code = code
        self.body = body
    }

    func write(to writer: inout ProtoWriter) {
        writer.fixed32(1, requestId)
        writer.int32(2, code)
        if let body { writer.message(3, body.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.fixed32): requestId = try reader.readFixed32()
            case (2, ProtoWireType.varint): code = try reader.readInt32()
            case (3, ProtoWireType.lengthDelimited): body = try AnyMessage(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "requestId: \(requestId) code: \(CapResponseCode.name(code))" + (body.map { " body { \($0.protoText) }" } ?? "")
    }
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

nonisolated struct CapTimeSettings: ProtoMessage, Equatable {
    static let protoName = "CapTimeSettings"
    /// Unix epoch milliseconds.
    var timeInMillisec: UInt64 = 0

    init(timeInMillisec: UInt64 = 0) {
        self.timeInMillisec = timeInMillisec
    }

    func write(to writer: inout ProtoWriter) {
        writer.uint64(1, timeInMillisec)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): timeInMillisec = try reader.readVarint()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { "timeInMillisec: \(timeInMillisec)" }
}

nonisolated struct RequestSetCapTimeSettings: ProtoMessage, Equatable {
    static let protoName = "RequestSetCapTimeSettings"
    var settings: CapTimeSettings?

    init(settings: CapTimeSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapTimeSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

nonisolated struct RequestGetCapTimeSettings: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapTimeSettings"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct ResponseGetCapTimeSettings: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapTimeSettings"
    var settings: CapTimeSettings?

    init(settings: CapTimeSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapTimeSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

nonisolated struct RequestGetCapUiState: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapUiState"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct ResponseGetCapUiState: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapUiState"
    var state: Int32 = 0
    var powerSavingMode: Int32 = 0

    init(state: Int32 = 0, powerSavingMode: Int32 = 0) {
        self.state = state
        self.powerSavingMode = powerSavingMode
    }

    func write(to writer: inout ProtoWriter) {
        writer.int32(1, state)
        writer.int32(2, powerSavingMode)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): state = try reader.readInt32()
            case (2, ProtoWireType.varint): powerSavingMode = try reader.readInt32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "state: \(CapUiState.name(state)) powerSavingMode: \(CapPowerSavingMode.name(powerSavingMode))"
    }
}

// ---------------------------------------------------------------------------
// ToF
// ---------------------------------------------------------------------------

nonisolated struct CapTofSettings: ProtoMessage, Equatable {
    static let protoName = "CapTofSettings"
    var mode: Int32 = 0
    var isIntervalTriggerEnabled: Bool = false
    var triggerIntervalInSec: UInt32 = 0
    var accelerometerCheckIntervalInSec: UInt32 = 0
    var bottleSizeInMilliliter: UInt32 = 0
    var accelerometerTimeoutInSec: UInt32 = 0

    init(
        mode: Int32 = 0,
        isIntervalTriggerEnabled: Bool = false,
        triggerIntervalInSec: UInt32 = 0,
        accelerometerCheckIntervalInSec: UInt32 = 0,
        bottleSizeInMilliliter: UInt32 = 0,
        accelerometerTimeoutInSec: UInt32 = 0,
    ) {
        self.mode = mode
        self.isIntervalTriggerEnabled = isIntervalTriggerEnabled
        self.triggerIntervalInSec = triggerIntervalInSec
        self.accelerometerCheckIntervalInSec = accelerometerCheckIntervalInSec
        self.bottleSizeInMilliliter = bottleSizeInMilliliter
        self.accelerometerTimeoutInSec = accelerometerTimeoutInSec
    }

    func write(to writer: inout ProtoWriter) {
        writer.int32(1, mode)
        writer.bool(2, isIntervalTriggerEnabled)
        writer.fixed32(3, triggerIntervalInSec)
        writer.fixed32(4, accelerometerCheckIntervalInSec)
        writer.fixed32(5, bottleSizeInMilliliter)
        writer.fixed32(6, accelerometerTimeoutInSec)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): mode = try reader.readInt32()
            case (2, ProtoWireType.varint): isIntervalTriggerEnabled = try reader.readBool()
            case (3, ProtoWireType.fixed32): triggerIntervalInSec = try reader.readFixed32()
            case (4, ProtoWireType.fixed32): accelerometerCheckIntervalInSec = try reader.readFixed32()
            case (5, ProtoWireType.fixed32): bottleSizeInMilliliter = try reader.readFixed32()
            case (6, ProtoWireType.fixed32): accelerometerTimeoutInSec = try reader.readFixed32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "mode: \(CapTofMode.name(mode)) isIntervalTriggerEnabled: \(isIntervalTriggerEnabled) " +
            "triggerIntervalInSec: \(triggerIntervalInSec) accelerometerCheckIntervalInSec: \(accelerometerCheckIntervalInSec) " +
            "bottleSizeInMilliliter: \(bottleSizeInMilliliter) accelerometerTimeoutInSec: \(accelerometerTimeoutInSec)"
    }
}

nonisolated struct RequestGetCapTofSettings: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapTofSettings"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct ResponseGetCapTofSettings: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapTofSettings"
    var settings: CapTofSettings?

    init(settings: CapTofSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapTofSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

nonisolated struct CapTofState: ProtoMessage, Equatable {
    static let protoName = "CapTofState"
    var distanceInMillimeter: UInt32 = 0
    var kcps: UInt32 = 0

    init(distanceInMillimeter: UInt32 = 0, kcps: UInt32 = 0) {
        self.distanceInMillimeter = distanceInMillimeter
        self.kcps = kcps
    }

    func write(to writer: inout ProtoWriter) {
        writer.fixed32(1, distanceInMillimeter)
        writer.fixed32(2, kcps)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.fixed32): distanceInMillimeter = try reader.readFixed32()
            case (2, ProtoWireType.fixed32): kcps = try reader.readFixed32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { "distanceInMillimeter: \(distanceInMillimeter) kcps: \(kcps)" }
}

nonisolated struct RequestGetCapTofState: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapTofState"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct ResponseGetCapTofState: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapTofState"
    var state: CapTofState?

    init(state: CapTofState? = nil) {
        self.state = state
    }

    func write(to writer: inout ProtoWriter) {
        if let state { writer.message(1, state.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): state = try CapTofState(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { state.map { "state { \($0.protoText) }" } ?? "" }
}

// ---------------------------------------------------------------------------
// Logs
// ---------------------------------------------------------------------------

nonisolated struct CapLogQuery: ProtoMessage, Equatable {
    static let protoName = "CapLogQuery"
    /// Unix epoch seconds; the cap returns entries with timestamp > fromTimestamp.
    var fromTimestamp: UInt64 = 0
    var limit: UInt32 = 0
    var algo: Int32 = 0

    init(fromTimestamp: UInt64 = 0, limit: UInt32 = 0, algo: Int32 = 0) {
        self.fromTimestamp = fromTimestamp
        self.limit = limit
        self.algo = algo
    }

    func write(to writer: inout ProtoWriter) {
        writer.uint64(1, fromTimestamp)
        writer.fixed32(2, limit)
        writer.int32(3, algo)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): fromTimestamp = try reader.readVarint()
            case (2, ProtoWireType.fixed32): limit = try reader.readFixed32()
            case (3, ProtoWireType.varint): algo = try reader.readInt32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "fromTimestamp: \(fromTimestamp) limit: \(limit) algo: \(CapLogQuerySearchAlgo.name(algo))"
    }
}

nonisolated struct CapTofLog: ProtoMessage, Equatable {
    static let protoName = "CapTofLog"
    var timestamp: UInt64 = 0
    var triggerType: Int32 = 0
    var distanceInMillimeter: UInt32 = 0
    var kcps: UInt32 = 0
    var uvLedTempInOhm: Float = 0

    init(
        timestamp: UInt64 = 0,
        triggerType: Int32 = 0,
        distanceInMillimeter: UInt32 = 0,
        kcps: UInt32 = 0,
        uvLedTempInOhm: Float = 0,
    ) {
        self.timestamp = timestamp
        self.triggerType = triggerType
        self.distanceInMillimeter = distanceInMillimeter
        self.kcps = kcps
        self.uvLedTempInOhm = uvLedTempInOhm
    }

    func write(to writer: inout ProtoWriter) {
        writer.uint64(1, timestamp)
        writer.int32(2, triggerType)
        writer.fixed32(3, distanceInMillimeter)
        writer.fixed32(4, kcps)
        writer.float(5, uvLedTempInOhm)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): timestamp = try reader.readVarint()
            case (2, ProtoWireType.varint): triggerType = try reader.readInt32()
            case (3, ProtoWireType.fixed32): distanceInMillimeter = try reader.readFixed32()
            case (4, ProtoWireType.fixed32): kcps = try reader.readFixed32()
            case (5, ProtoWireType.fixed32): uvLedTempInOhm = try reader.readFloat()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "timestamp: \(timestamp) triggerType: \(CapTofTriggerType.name(triggerType)) " +
            "distanceInMillimeter: \(distanceInMillimeter) kcps: \(kcps) uvLedTempInOhm: \(uvLedTempInOhm.protoTextValue)"
    }
}

nonisolated struct RequestGetCapTofLog: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapTofLog"
    var query: CapLogQuery?

    init(query: CapLogQuery? = nil) {
        self.query = query
    }

    func write(to writer: inout ProtoWriter) {
        if let query { writer.message(1, query.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): query = try CapLogQuery(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { query.map { "query { \($0.protoText) }" } ?? "" }
}

nonisolated struct ResponseGetCapTofLog: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapTofLog"
    var items: [CapTofLog] = []

    init(items: [CapTofLog] = []) {
        self.items = items
    }

    func write(to writer: inout ProtoWriter) {
        for item in items { writer.message(1, item.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        var decoded: [CapTofLog] = []
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): decoded.append(try CapTofLog(protoDecodedFrom: reader.readBytes()))
            default: try reader.skip(wire: wire)
            }
        }
        items = decoded
    }

    var protoText: String { "items: \(items.count)" }
}

nonisolated struct CapActivationLog: ProtoMessage, Equatable {
    static let protoName = "CapActivationLog"
    var timestamp: UInt64 = 0
    var mode: Int32 = 0
    var batterySocInPercentage: UInt32 = 0

    init(timestamp: UInt64 = 0, mode: Int32 = 0, batterySocInPercentage: UInt32 = 0) {
        self.timestamp = timestamp
        self.mode = mode
        self.batterySocInPercentage = batterySocInPercentage
    }

    func write(to writer: inout ProtoWriter) {
        writer.uint64(1, timestamp)
        writer.int32(2, mode)
        writer.fixed32(3, batterySocInPercentage)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): timestamp = try reader.readVarint()
            case (2, ProtoWireType.varint): mode = try reader.readInt32()
            case (3, ProtoWireType.fixed32): batterySocInPercentage = try reader.readFixed32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "timestamp: \(timestamp) mode: \(CapUvActivationMode.name(mode)) batterySocInPercentage: \(batterySocInPercentage)"
    }
}

nonisolated struct RequestGetCapActivationLog: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapActivationLog"
    var query: CapLogQuery?

    init(query: CapLogQuery? = nil) {
        self.query = query
    }

    func write(to writer: inout ProtoWriter) {
        if let query { writer.message(1, query.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): query = try CapLogQuery(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { query.map { "query { \($0.protoText) }" } ?? "" }
}

nonisolated struct ResponseGetCapActivationLog: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapActivationLog"
    var items: [CapActivationLog] = []

    init(items: [CapActivationLog] = []) {
        self.items = items
    }

    func write(to writer: inout ProtoWriter) {
        for item in items { writer.message(1, item.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        var decoded: [CapActivationLog] = []
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): decoded.append(try CapActivationLog(protoDecodedFrom: reader.readBytes()))
            default: try reader.skip(wire: wire)
            }
        }
        items = decoded
    }

    var protoText: String { "items: \(items.count)" }
}

// ---------------------------------------------------------------------------
// Hydration reminder (LED ring)
// ---------------------------------------------------------------------------

nonisolated struct CapColor: ProtoMessage, Equatable {
    static let protoName = "CapColor"
    var red: Float = 0
    var green: Float = 0
    var blue: Float = 0
    var alpha: Float = 0

    init(red: Float = 0, green: Float = 0, blue: Float = 0, alpha: Float = 0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func write(to writer: inout ProtoWriter) {
        writer.float(1, red)
        writer.float(2, green)
        writer.float(3, blue)
        writer.float(4, alpha)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.fixed32): red = try reader.readFloat()
            case (2, ProtoWireType.fixed32): green = try reader.readFloat()
            case (3, ProtoWireType.fixed32): blue = try reader.readFloat()
            case (4, ProtoWireType.fixed32): alpha = try reader.readFloat()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "red: \(red.protoTextValue) green: \(green.protoTextValue) blue: \(blue.protoTextValue) alpha: \(alpha.protoTextValue)"
    }
}

nonisolated struct CapHydroReminderSettings: ProtoMessage, Equatable {
    static let protoName = "CapHydroReminderSettings"
    var state: Int32 = 0
    /// Seconds of day, 1..86400.
    var startTimeInSec: UInt32 = 0
    var stopTimeInSec: UInt32 = 0
    var intervalInSec: UInt32 = 0
    var color: CapColor?

    init(
        state: Int32 = 0,
        startTimeInSec: UInt32 = 0,
        stopTimeInSec: UInt32 = 0,
        intervalInSec: UInt32 = 0,
        color: CapColor? = nil,
    ) {
        self.state = state
        self.startTimeInSec = startTimeInSec
        self.stopTimeInSec = stopTimeInSec
        self.intervalInSec = intervalInSec
        self.color = color
    }

    func write(to writer: inout ProtoWriter) {
        writer.int32(1, state)
        writer.fixed32(2, startTimeInSec)
        writer.fixed32(3, stopTimeInSec)
        writer.fixed32(4, intervalInSec)
        if let color { writer.message(5, color.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): state = try reader.readInt32()
            case (2, ProtoWireType.fixed32): startTimeInSec = try reader.readFixed32()
            case (3, ProtoWireType.fixed32): stopTimeInSec = try reader.readFixed32()
            case (4, ProtoWireType.fixed32): intervalInSec = try reader.readFixed32()
            case (5, ProtoWireType.lengthDelimited): color = try CapColor(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "state: \(CapHydroReminderState.name(state)) startTimeInSec: \(startTimeInSec) " +
            "stopTimeInSec: \(stopTimeInSec) intervalInSec: \(intervalInSec)" +
            (color.map { " color { \($0.protoText) }" } ?? "")
    }
}

nonisolated struct RequestGetCapHydroReminderSettings: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapHydroReminderSettings"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct RequestSetCapHydroReminderSettings: ProtoMessage, Equatable {
    static let protoName = "RequestSetCapHydroReminderSettings"
    var settings: CapHydroReminderSettings?

    init(settings: CapHydroReminderSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapHydroReminderSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

nonisolated struct ResponseGetCapHydroReminderSettings: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapHydroReminderSettings"
    var settings: CapHydroReminderSettings?

    init(settings: CapHydroReminderSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapHydroReminderSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

// ---------------------------------------------------------------------------
// Do not disturb
// ---------------------------------------------------------------------------

nonisolated struct CapDoNotDisturbSettings: ProtoMessage, Equatable {
    static let protoName = "CapDoNotDisturbSettings"
    var state: Int32 = 0
    var startTimeInSec: UInt32 = 0
    var stopTimeInSec: UInt32 = 0
    var snoozeTimeInMinutes: UInt32 = 0

    init(state: Int32 = 0, startTimeInSec: UInt32 = 0, stopTimeInSec: UInt32 = 0, snoozeTimeInMinutes: UInt32 = 0) {
        self.state = state
        self.startTimeInSec = startTimeInSec
        self.stopTimeInSec = stopTimeInSec
        self.snoozeTimeInMinutes = snoozeTimeInMinutes
    }

    func write(to writer: inout ProtoWriter) {
        writer.int32(1, state)
        writer.fixed32(2, startTimeInSec)
        writer.fixed32(3, stopTimeInSec)
        writer.fixed32(4, snoozeTimeInMinutes)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.varint): state = try reader.readInt32()
            case (2, ProtoWireType.fixed32): startTimeInSec = try reader.readFixed32()
            case (3, ProtoWireType.fixed32): stopTimeInSec = try reader.readFixed32()
            case (4, ProtoWireType.fixed32): snoozeTimeInMinutes = try reader.readFixed32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "state: \(CapDoNotDisturbState.name(state)) startTimeInSec: \(startTimeInSec) " +
            "stopTimeInSec: \(stopTimeInSec) snoozeTimeInMinutes: \(snoozeTimeInMinutes)"
    }
}

nonisolated struct RequestGetCapDoNotDisturbSettings: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapDoNotDisturbSettings"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct RequestSetCapDoNotDisturbSettings: ProtoMessage, Equatable {
    static let protoName = "RequestSetCapDoNotDisturbSettings"
    var settings: CapDoNotDisturbSettings?

    init(settings: CapDoNotDisturbSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapDoNotDisturbSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

nonisolated struct ResponseGetCapDoNotDisturbSettings: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapDoNotDisturbSettings"
    var settings: CapDoNotDisturbSettings?

    init(settings: CapDoNotDisturbSettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapDoNotDisturbSettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

// ---------------------------------------------------------------------------
// Low battery (read-only for HydroCap)
// ---------------------------------------------------------------------------

nonisolated struct CapLowBatterySettings: ProtoMessage, Equatable {
    static let protoName = "CapLowBatterySettings"
    var alertThresholdInPercentage: UInt32 = 0
    var lockoutThresholdInPercentage: UInt32 = 0

    init(alertThresholdInPercentage: UInt32 = 0, lockoutThresholdInPercentage: UInt32 = 0) {
        self.alertThresholdInPercentage = alertThresholdInPercentage
        self.lockoutThresholdInPercentage = lockoutThresholdInPercentage
    }

    func write(to writer: inout ProtoWriter) {
        writer.fixed32(1, alertThresholdInPercentage)
        writer.fixed32(2, lockoutThresholdInPercentage)
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.fixed32): alertThresholdInPercentage = try reader.readFixed32()
            case (2, ProtoWireType.fixed32): lockoutThresholdInPercentage = try reader.readFixed32()
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String {
        "alertThresholdInPercentage: \(alertThresholdInPercentage) lockoutThresholdInPercentage: \(lockoutThresholdInPercentage)"
    }
}

nonisolated struct RequestGetCapLowBatterySettings: ProtoMessage, Equatable {
    static let protoName = "RequestGetCapLowBatterySettings"
    init() {}
    func write(to writer: inout ProtoWriter) {}
    init(reading reader: inout ProtoReader) throws {
        while let (_, wire) = try reader.nextTag() { try reader.skip(wire: wire) }
    }
    var protoText: String { "" }
}

nonisolated struct ResponseGetCapLowBatterySettings: ProtoMessage, Equatable {
    static let protoName = "ResponseGetCapLowBatterySettings"
    var settings: CapLowBatterySettings?

    init(settings: CapLowBatterySettings? = nil) {
        self.settings = settings
    }

    func write(to writer: inout ProtoWriter) {
        if let settings { writer.message(1, settings.protoEncoded()) }
    }

    init(reading reader: inout ProtoReader) throws {
        while let (field, wire) = try reader.nextTag() {
            switch (field, wire) {
            case (1, ProtoWireType.lengthDelimited): settings = try CapLowBatterySettings(protoDecodedFrom: reader.readBytes())
            default: try reader.skip(wire: wire)
            }
        }
    }

    var protoText: String { settings.map { "settings { \($0.protoText) }" } ?? "" }
}

// ---------------------------------------------------------------------------
// Schema inventory
// ---------------------------------------------------------------------------

/// Every message name this codec knows, exactly as written in
/// `android/app/src/main/proto/hydrocap.proto` (plus `google.protobuf.Any`,
/// which is wire plumbing). The allowlist test asserts the forbidden request
/// names are absent here, which is the Swift equivalent of Android's
/// `Class.forName("dev.hydrocap.app.proto.<name>")` check.
nonisolated enum ProtoRegistry {
    static let knownTypeNames: Set<String> = [
        "google.protobuf.Any",
        "CapBleRequest",
        "CapBleResponse",
        "CapTimeSettings",
        "RequestSetCapTimeSettings",
        "RequestGetCapTimeSettings",
        "ResponseGetCapTimeSettings",
        "RequestGetCapUiState",
        "ResponseGetCapUiState",
        "CapTofSettings",
        "RequestGetCapTofSettings",
        "ResponseGetCapTofSettings",
        "CapTofState",
        "RequestGetCapTofState",
        "ResponseGetCapTofState",
        "CapLogQuery",
        "CapTofLog",
        "RequestGetCapTofLog",
        "ResponseGetCapTofLog",
        "CapActivationLog",
        "RequestGetCapActivationLog",
        "ResponseGetCapActivationLog",
        "CapColor",
        "CapHydroReminderSettings",
        "RequestGetCapHydroReminderSettings",
        "RequestSetCapHydroReminderSettings",
        "ResponseGetCapHydroReminderSettings",
        "CapDoNotDisturbSettings",
        "RequestGetCapDoNotDisturbSettings",
        "RequestSetCapDoNotDisturbSettings",
        "ResponseGetCapDoNotDisturbSettings",
        "CapLowBatterySettings",
        "RequestGetCapLowBatterySettings",
        "ResponseGetCapLowBatterySettings",
    ]

    static var knownRequestTypeNames: Set<String> {
        Set(knownTypeNames.filter { $0.hasPrefix("Request") })
    }
}
