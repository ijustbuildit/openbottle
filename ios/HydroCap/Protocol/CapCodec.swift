import Foundation

/// Thrown when a message outside `CapCommand` is handed to the codec.
nonisolated struct DisallowedCommandError: Error, Equatable, CustomStringConvertible {
    let typeName: String

    var description: String { "Request '\(typeName)' is not in the HydroCap command allowlist" }
}

/// A decoded `Any` payload of a response envelope.
nonisolated enum ProtoBody: Equatable, Sendable {
    case uiState(ResponseGetCapUiState)
    case tofSettings(ResponseGetCapTofSettings)
    case tofState(ResponseGetCapTofState)
    case tofLog(ResponseGetCapTofLog)
    case activationLog(ResponseGetCapActivationLog)
    case hydroReminder(ResponseGetCapHydroReminderSettings)
    case dnd(ResponseGetCapDoNotDisturbSettings)
    case lowBattery(ResponseGetCapLowBatterySettings)
    case timeSettings(ResponseGetCapTimeSettings)

    /// Decodes a body by its unqualified message name; nil for an unknown type
    /// (the envelope stays usable, the payload is dropped — same as Android).
    static func decode(typeName: String, value: Data) throws -> ProtoBody? {
        switch typeName {
        case ResponseGetCapUiState.protoName: try .uiState(ResponseGetCapUiState(protoDecodedFrom: value))
        case ResponseGetCapTofSettings.protoName: try .tofSettings(ResponseGetCapTofSettings(protoDecodedFrom: value))
        case ResponseGetCapTofState.protoName: try .tofState(ResponseGetCapTofState(protoDecodedFrom: value))
        case ResponseGetCapTofLog.protoName: try .tofLog(ResponseGetCapTofLog(protoDecodedFrom: value))
        case ResponseGetCapActivationLog.protoName: try .activationLog(ResponseGetCapActivationLog(protoDecodedFrom: value))
        case ResponseGetCapHydroReminderSettings.protoName: try .hydroReminder(ResponseGetCapHydroReminderSettings(protoDecodedFrom: value))
        case ResponseGetCapDoNotDisturbSettings.protoName: try .dnd(ResponseGetCapDoNotDisturbSettings(protoDecodedFrom: value))
        case ResponseGetCapLowBatterySettings.protoName: try .lowBattery(ResponseGetCapLowBatterySettings(protoDecodedFrom: value))
        case ResponseGetCapTimeSettings.protoName: try .timeSettings(ResponseGetCapTimeSettings(protoDecodedFrom: value))
        default: nil
        }
    }

    var typeName: String {
        switch self {
        case .uiState: ResponseGetCapUiState.protoName
        case .tofSettings: ResponseGetCapTofSettings.protoName
        case .tofState: ResponseGetCapTofState.protoName
        case .tofLog: ResponseGetCapTofLog.protoName
        case .activationLog: ResponseGetCapActivationLog.protoName
        case .hydroReminder: ResponseGetCapHydroReminderSettings.protoName
        case .dnd: ResponseGetCapDoNotDisturbSettings.protoName
        case .lowBattery: ResponseGetCapLowBatterySettings.protoName
        case .timeSettings: ResponseGetCapTimeSettings.protoName
        }
    }

    var protoText: String {
        switch self {
        case .uiState(let body): body.protoText
        case .tofSettings(let body): body.protoText
        case .tofState(let body): body.protoText
        case .tofLog(let body): body.protoText
        case .activationLog(let body): body.protoText
        case .hydroReminder(let body): body.protoText
        case .dnd(let body): body.protoText
        case .lowBattery(let body): body.protoText
        case .timeSettings(let body): body.protoText
        }
    }

    /// Typed accessors used by `CapClient`.
    var uiState: ResponseGetCapUiState? { if case .uiState(let body) = self { body } else { nil } }
    var tofSettings: ResponseGetCapTofSettings? { if case .tofSettings(let body) = self { body } else { nil } }
    var tofState: ResponseGetCapTofState? { if case .tofState(let body) = self { body } else { nil } }
    var tofLog: ResponseGetCapTofLog? { if case .tofLog(let body) = self { body } else { nil } }
    var activationLog: ResponseGetCapActivationLog? { if case .activationLog(let body) = self { body } else { nil } }
    var hydroReminder: ResponseGetCapHydroReminderSettings? { if case .hydroReminder(let body) = self { body } else { nil } }
    var dnd: ResponseGetCapDoNotDisturbSettings? { if case .dnd(let body) = self { body } else { nil } }
    var lowBattery: ResponseGetCapLowBatterySettings? { if case .lowBattery(let body) = self { body } else { nil } }
    var timeSettings: ResponseGetCapTimeSettings? { if case .timeSettings(let body) = self { body } else { nil } }
}

/// A decoded response envelope. `body` is nil for setters and for
/// NOT_SUPPORTED/FAIL, and for a body type the codec does not know.
nonisolated struct DecodedResponse: Equatable, Sendable {
    let requestId: UInt32
    /// Raw enum value as it was on the wire (unknown codes survive).
    let code: Int32
    let typeName: String?
    let body: ProtoBody?

    var isSuccess: Bool { code == CapResponseCode.success }
    var codeName: String { CapResponseCode.name(code) }
    /// True for `SUCCESS` answers that carry no body at all (setters, and a log
    /// query past the newest entry).
    var hasNoBody: Bool { typeName == nil && body == nil }

    /// Human-readable rendering for the debug log.
    func describe() -> String {
        var out = "id=\(requestId) code=\(codeName)"
        if let typeName { out += " type=\(typeName)" }
        if let body { out += " \(body.protoText)" }
        return out
    }
}

nonisolated enum CapCodecError: Error, Equatable, CustomStringConvertible {
    case malformedEnvelope(String)

    var description: String {
        switch self {
        case .malformedEnvelope(let reason): "malformed response envelope: \(reason)"
        }
    }
}

/// Encodes `CapBleRequest` envelopes and decodes `CapBleResponse` envelopes,
/// including unpacking the `google.protobuf.Any` body by its unqualified
/// message name. Enforces the command allowlist on the encode path.
nonisolated enum CapCodec {

    /// Encodes a request; the allowlist is enforced here, so a body type that
    /// is not one of `CapCommand.allowedRequestTypeNames` throws before any
    /// byte is produced.
    static func encodeRequest<Body: ProtoMessage>(requestId: UInt32, body: Body) throws -> Data {
        try buildRequest(requestId: requestId, body: body).protoEncoded()
    }

    static func buildRequest<Body: ProtoMessage>(requestId: UInt32, body: Body) throws -> CapBleRequest {
        let typeName = Body.protoName
        guard CapCommand.allowedRequestTypeNames.contains(typeName) else {
            throw DisallowedCommandError(typeName: typeName)
        }
        return CapBleRequest(
            requestId: requestId,
            body: AnyMessage(typeUrl: TypeUrls.of(typeName), value: body.protoEncoded()),
        )
    }

    /// Request id as sent on the wire (fixed32 → unsigned).
    static func requestId(of request: CapBleRequest) -> UInt32 { request.requestId }

    static func decodeResponse(_ bytes: Data) throws -> DecodedResponse {
        let envelope = try CapBleResponse(protoDecodedFrom: bytes)
        guard let any = envelope.body, !any.typeUrl.isEmpty else {
            return DecodedResponse(requestId: envelope.requestId, code: envelope.code, typeName: nil, body: nil)
        }
        let typeName = TypeUrls.messageName(any.typeUrl)
        let body = try ProtoBody.decode(typeName: typeName, value: any.value)
        return DecodedResponse(requestId: envelope.requestId, code: envelope.code, typeName: typeName, body: body)
    }

    /// Strict parse used by the reassembly buffer: a truncated message must not
    /// be accepted as a complete one. proto3 parsing tolerates missing trailing
    /// fields, so we additionally require the envelope to round-trip to the
    /// same byte length (no trailing garbage, no unknown data).
    static func tryDecodeComplete(_ bytes: Data) -> DecodedResponse? {
        guard !bytes.isEmpty else { return nil }
        guard let envelope = try? CapBleResponse(protoDecodedFrom: bytes) else { return nil }
        guard envelope.protoEncoded().count == bytes.count else { return nil }
        return try? decodeResponse(bytes)
    }

    /// Text rendering used by the debug log for requests.
    static func describeRequest<Body: ProtoMessage>(_ body: Body) -> String {
        let text = body.protoText
        return text.isEmpty ? "{}" : "{ \(text) }"
    }
}
