import Foundation

/// `Any.type_url` construction; the cap dispatches on the unqualified message
/// name (the vendor schema has no package statement).
nonisolated enum TypeUrls {
    static let prefix = "type.googleapis.com/"

    static func of(_ messageName: String) -> String { prefix + messageName }

    static func messageName(_ typeUrl: String) -> String {
        String(typeUrl.split(separator: "/").last ?? "")
    }
}

/// Compile-time inventory of every request the cap understands that HydroCap is
/// allowed to send. A request whose message type is not listed here is rejected
/// by `CapCodec` before it reaches the BLE layer, so the out-of-scope commands
/// from the protocol doc (UV activate, DFU, factory reset, calibration,
/// thresholds, ADC, power saving, ToF/low-battery/bottle-sensor setters) can
/// never be encoded, let alone transmitted.
nonisolated struct CapCommandSpec: Sendable, Hashable {
    let requestTypeName: String
    let responseTypeName: String?
}

nonisolated enum CapCommand: String, CaseIterable, Sendable {
    case setTime
    case getTime
    case getUiState
    case getTofSettings
    case getTofState
    case getTofLog
    case getActivationLog
    case getHydroReminder
    case setHydroReminder
    case getDnd
    case setDnd
    case getLowBattery

    var spec: CapCommandSpec {
        switch self {
        case .setTime: CapCommandSpec(requestTypeName: "RequestSetCapTimeSettings", responseTypeName: nil)
        case .getTime: CapCommandSpec(requestTypeName: "RequestGetCapTimeSettings", responseTypeName: "ResponseGetCapTimeSettings")
        case .getUiState: CapCommandSpec(requestTypeName: "RequestGetCapUiState", responseTypeName: "ResponseGetCapUiState")
        case .getTofSettings: CapCommandSpec(requestTypeName: "RequestGetCapTofSettings", responseTypeName: "ResponseGetCapTofSettings")
        case .getTofState: CapCommandSpec(requestTypeName: "RequestGetCapTofState", responseTypeName: "ResponseGetCapTofState")
        case .getTofLog: CapCommandSpec(requestTypeName: "RequestGetCapTofLog", responseTypeName: "ResponseGetCapTofLog")
        case .getActivationLog: CapCommandSpec(requestTypeName: "RequestGetCapActivationLog", responseTypeName: "ResponseGetCapActivationLog")
        case .getHydroReminder: CapCommandSpec(requestTypeName: "RequestGetCapHydroReminderSettings", responseTypeName: "ResponseGetCapHydroReminderSettings")
        case .setHydroReminder: CapCommandSpec(requestTypeName: "RequestSetCapHydroReminderSettings", responseTypeName: nil)
        case .getDnd: CapCommandSpec(requestTypeName: "RequestGetCapDoNotDisturbSettings", responseTypeName: "ResponseGetCapDoNotDisturbSettings")
        case .setDnd: CapCommandSpec(requestTypeName: "RequestSetCapDoNotDisturbSettings", responseTypeName: nil)
        case .getLowBattery: CapCommandSpec(requestTypeName: "RequestGetCapLowBatterySettings", responseTypeName: "ResponseGetCapLowBatterySettings")
        }
    }

    var requestTypeName: String { spec.requestTypeName }
    var responseTypeName: String? { spec.responseTypeName }
    var requestTypeUrl: String { TypeUrls.of(spec.requestTypeName) }
    var responseTypeUrl: String? { spec.responseTypeName.map(TypeUrls.of) }

    /// Request message names allowed on the wire (unqualified proto names).
    static var allowedRequestTypeNames: Set<String> {
        Set(allCases.map { $0.spec.requestTypeName })
    }

    /// Commands the firmware supports but which HydroCap must never send
    /// (docs/protocol/ble-protocol.md §4). Kept here so the unit test can
    /// assert the two sets are disjoint and the forbidden ones are absent.
    static let forbiddenRequestTypeNames: Set<String> = [
        "RequestSetCapUvActivate",
        "RequestSetCapConfig",
        "RequestSetCapThreshold",
        "RequestSetCapAdcProtection",
        "RequestSetCapLowBatterySettings",
        "RequestSetCapTofSettings",
        "RequestSetCapCalibrationSettings",
        "RequestCapStartCapCalibration",
        "RequestCapStopCapCalibration",
        "RequestCapEnterLowBatteryMode",
        "RequestCapEnterDfuMode",
        "RequestCapFactoryReset",
        "RequestSetCapPowerSavingMode",
        "RequestSetCapBottleSensorState",
    ]

    static func forRequestTypeName(_ name: String) -> CapCommand? {
        allCases.first { $0.spec.requestTypeName == name }
    }
}
