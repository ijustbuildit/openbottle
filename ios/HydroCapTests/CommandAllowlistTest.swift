import Foundation
import Testing

@testable import HydroCap

/// Asserts the compile-time command allowlist from docs/protocol/ble-protocol.md §4.
@Suite("Command allowlist")
struct CommandAllowlistTest {

    @Test func allowlistContainsExactlyTheMVPCommands() {
        let expected: Set<String> = [
            "RequestSetCapTimeSettings",
            "RequestGetCapTimeSettings",
            "RequestGetCapUiState",
            "RequestGetCapTofSettings",
            "RequestGetCapTofState",
            "RequestGetCapTofLog",
            "RequestGetCapActivationLog",
            "RequestGetCapHydroReminderSettings",
            "RequestSetCapHydroReminderSettings",
            "RequestGetCapDoNotDisturbSettings",
            "RequestSetCapDoNotDisturbSettings",
            "RequestGetCapLowBatterySettings",
        ]
        #expect(CapCommand.allowedRequestTypeNames == expected)
    }

    @Test func theOnlyAllowedSettersAreReminderQuietHoursAndTime() {
        let setters = Set(CapCommand.allowedRequestTypeNames.filter { !$0.hasPrefix("RequestGet") })
        #expect(setters == [
            "RequestSetCapHydroReminderSettings",
            "RequestSetCapDoNotDisturbSettings",
            "RequestSetCapTimeSettings",
        ])
        let commandsWithoutResponseBody = Set(CapCommand.allCases.filter { $0.responseTypeName == nil })
        #expect(commandsWithoutResponseBody == [CapCommand.setHydroReminder, CapCommand.setDnd, CapCommand.setTime])
    }

    @Test func noForbiddenCommandIsAllowlisted() {
        let overlap = CapCommand.allowedRequestTypeNames.intersection(CapCommand.forbiddenRequestTypeNames)
        #expect(overlap.isEmpty, "forbidden commands present in allowlist: \(overlap)")
        let mustBeForbidden = [
            "RequestSetCapUvActivate",
            "RequestCapEnterDfuMode",
            "RequestCapFactoryReset",
            "RequestSetCapCalibrationSettings",
            "RequestCapStartCapCalibration",
            "RequestCapStopCapCalibration",
            "RequestSetCapThreshold",
            "RequestSetCapAdcProtection",
            "RequestSetCapPowerSavingMode",
            "RequestSetCapTofSettings",
            "RequestSetCapLowBatterySettings",
            "RequestSetCapBottleSensorState",
            "RequestCapEnterLowBatteryMode",
            "RequestSetCapConfig",
        ]
        for name in mustBeForbidden {
            #expect(CapCommand.forbiddenRequestTypeNames.contains(name), "\(name) must be forbidden")
        }
    }

    /// Swift equivalent of Android's `Class.forName` check: the forbidden
    /// request names must not exist in our schema inventory. If someone adds a
    /// setter to the message layer it must also be allowlisted here on purpose.
    @Test func forbiddenMessageTypesDoNotExistInTheSchema() {
        for name in CapCommand.forbiddenRequestTypeNames {
            #expect(!ProtoRegistry.knownTypeNames.contains(name), "forbidden message \(name) must not be part of the schema")
        }
    }

    @Test func everySchemaRequestMessageIsEitherAllowlistedOrForbiddenByName() {
        for name in ProtoRegistry.knownRequestTypeNames {
            #expect(CapCommand.allowedRequestTypeNames.contains(name), "\(name) exists in the schema and must be allowlisted")
        }
        // The setters we ship are exactly three.
        let setters = ProtoRegistry.knownRequestTypeNames.filter { !$0.hasPrefix("RequestGet") }
        #expect(setters == [
            "RequestSetCapTimeSettings",
            "RequestSetCapHydroReminderSettings",
            "RequestSetCapDoNotDisturbSettings",
        ])
    }

    @Test func codecRejectsAMessageThatIsNotAllowlisted() throws {
        // CapBleRequest is a valid proto message but never a request body.
        var threw = false
        do {
            _ = try CapCodec.encodeRequest(requestId: 1, body: CapBleRequest(requestId: 1, body: nil))
        } catch let error as DisallowedCommandError {
            threw = true
            #expect(error.message.contains("CapBleRequest"))
        }
        #expect(threw, "expected DisallowedCommandError")
        #expect(!CapCommand.allowedRequestTypeNames.contains("CapBleRequest"))
    }

    @Test func codecRejectsEveryForbiddenSetterByName() throws {
        // There is no struct for the forbidden setters (that is the point), so
        // the enforcement is asserted on the name level plus a would-be
        // placeholder body that carries a forbidden name.
        struct FakeForbiddenBody: ProtoMessage {
            static let protoName = "RequestCapFactoryReset"
            func write(to writer: inout ProtoWriter) {}
            init() {}
            init(reading reader: inout ProtoReader) throws {}
            var protoText: String { "" }
        }
        #expect(throws: DisallowedCommandError(typeName: "RequestCapFactoryReset")) {
            _ = try CapCodec.encodeRequest(requestId: 1, body: FakeForbiddenBody())
        }
    }
}

extension DisallowedCommandError {
    /// `CustomStringConvertible` calls this `description`; the tests want the
    /// payload under a clearer name.
    var message: String { description }
}
