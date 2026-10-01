import Foundation
import Testing

@testable import HydroCap

/// Golden vectors copied verbatim from docs/protocol/ble-protocol.md §7
/// (generated with protoc 36.0 against the vendor schema). Every request must
/// encode byte-for-byte; every response must decode to the documented message.
@Suite("Protocol golden vectors")
struct ProtocolGoldenTest {

    // MARK: - Requests

    @Test func request1GetCapUiState() throws {
        let expected = "0d01000000122a0a28747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617055695374617465"
        let bytes = try CapCodec.encodeRequest(requestId: 1, body: RequestGetCapUiState())
        #expect(Hex.encode(bytes) == expected)
        #expect(bytes == (try Hex.decode(expected)))
    }

    @Test func request7SetCapTimeSettings() throws {
        let expected = "0d07000000123a0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737453657443617054696d6553657474696e677312090a070880d8c1a28c34"
        let body = RequestSetCapTimeSettings(settings: CapTimeSettings(timeInMillisec: 1_790_000_000_000))
        let bytes = try CapCodec.encodeRequest(requestId: 7, body: body)
        #expect(Hex.encode(bytes) == expected)
    }

    @Test func request3GetCapTofLog() throws {
        let expected = "0d0300000012380a27747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f664c6f67120d0a0b08fff6c4d5061505000000"
        let body = RequestGetCapTofLog(query: CapLogQuery(fromTimestamp: 1_789_999_999, limit: 5, algo: CapLogQuerySearchAlgo.timestamp))
        let bytes = try CapCodec.encodeRequest(requestId: 3, body: body)
        #expect(Hex.encode(bytes) == expected)
    }

    @Test func request12GetCapActivationLogWithZeroFromTimestamp() throws {
        let expected = "0d0c00000012390a2e747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617041637469766174696f6e4c6f6712070a051506000000"
        let body = RequestGetCapActivationLog(query: CapLogQuery(fromTimestamp: 0, limit: 6, algo: CapLogQuerySearchAlgo.timestamp))
        let bytes = try CapCodec.encodeRequest(requestId: 12, body: body)
        #expect(Hex.encode(bytes) == expected)
    }

    @Test func request11SetCapHydroReminderSettings() throws {
        let expected = "0d0b00000012520a36747970652e676f6f676c65617069732e636f6d2f52657175657374536574436170487964726f52656d696e64657253657474696e677312180a1615010000001d805101002a0a1d0000803f250000803f"
        let body = RequestSetCapHydroReminderSettings(settings: CapHydroReminderSettings(
            state: CapHydroReminderState.off,
            startTimeInSec: 1,
            stopTimeInSec: 86_400,
            intervalInSec: 0,
            color: CapColor(red: 0, green: 0, blue: 1, alpha: 1),
        ))
        let bytes = try CapCodec.encodeRequest(requestId: 11, body: body)
        #expect(Hex.encode(bytes) == expected)
    }

    // MARK: - Responses

    @Test func response1GetCapUiState() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0100000010011a310a29747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617055695374617465120408081001",
        ))
        #expect(decoded.requestId == 1)
        #expect(decoded.code == CapResponseCode.success)
        #expect(decoded.typeName == "ResponseGetCapUiState")
        #expect(decoded.body == .uiState(ResponseGetCapUiState(state: CapUiState.charging, powerSavingMode: CapPowerSavingMode.off)))
    }

    @Test func response3GetCapTofLog() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0300000010011a5e0a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f6712320a1708e4f7c4d50610021d7800000025641900002d00421c460a1708c8f8c4d50610011d8700000025d41700002d00191c46",
        ))
        #expect(decoded.requestId == 3)
        #expect(decoded.code == CapResponseCode.success)
        let expected = ResponseGetCapTofLog(items: [
            CapTofLog(
                timestamp: 1_790_000_100,
                triggerType: CapTofTriggerType.cap,
                distanceInMillimeter: 120,
                kcps: 6_500,
                uvLedTempInOhm: 10_000.5,
            ),
            CapTofLog(
                timestamp: 1_790_000_200,
                triggerType: CapTofTriggerType.interval,
                distanceInMillimeter: 135,
                kcps: 6_100,
                uvLedTempInOhm: 9_990.25,
            ),
        ])
        #expect(decoded.body == .tofLog(expected))
    }

    @Test func response4GetCapTofSettings() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0400000010011a4b0a2d747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f6653657474696e6773121a0a18080210011d2c01000025050000002da8020000350a000000",
        ))
        #expect(decoded.requestId == 4)
        let expected = ResponseGetCapTofSettings(settings: CapTofSettings(
            mode: CapTofMode.event,
            isIntervalTriggerEnabled: true,
            triggerIntervalInSec: 300,
            accelerometerCheckIntervalInSec: 5,
            bottleSizeInMilliliter: 680,
            accelerometerTimeoutInSec: 10,
        ))
        #expect(decoded.body == .tofSettings(expected))
    }

    @Test func response5GetCapHydroReminderSettings() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0500000010011a640a37747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170487964726f52656d696e64657253657474696e677312290a27080115807000001d6035010025100e00002a140d0000803f150000003f1d0000803e250000803f",
        ))
        #expect(decoded.requestId == 5)
        let expected = ResponseGetCapHydroReminderSettings(settings: CapHydroReminderSettings(
            state: CapHydroReminderState.intervalFixed,
            startTimeInSec: 28_800,
            stopTimeInSec: 79_200,
            intervalInSec: 3_600,
            color: CapColor(red: 1, green: 0.5, blue: 0.25, alpha: 1),
        ))
        #expect(decoded.body == .hydroReminder(expected))
    }

    @Test func response6GetCapTofState() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d2a00000015e02e0000",
        ))
        #expect(decoded.requestId == 6)
        #expect(decoded.body == .tofState(ResponseGetCapTofState(state: CapTofState(distanceInMillimeter: 42, kcps: 12_000))))
    }

    @Test func response8GetCapLowBatterySettings() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0800000010011a440a34747970652e676f6f676c65617069732e636f6d2f526573706f6e73654765744361704c6f774261747465727953657474696e6773120c0a0a0d140000001505000000",
        ))
        #expect(decoded.requestId == 8)
        let expected = ResponseGetCapLowBatterySettings(settings: CapLowBatterySettings(
            alertThresholdInPercentage: 20,
            lockoutThresholdInPercentage: 5,
        ))
        #expect(decoded.body == .lowBattery(expected))
    }

    @Test func response10GetCapActivationLog() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0a00000010011a400a2f747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617041637469766174696f6e4c6f67120d0a0b08acf9c4d5061d57000000",
        ))
        #expect(decoded.requestId == 10)
        let expected = ResponseGetCapActivationLog(items: [
            CapActivationLog(timestamp: 1_790_000_300, mode: CapUvActivationMode.maintenance, batterySocInPercentage: 87),
        ])
        #expect(decoded.body == .activationLog(expected))
    }

    @Test func response9NotSupportedWithoutBody() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode("0d090000001002"))
        #expect(decoded.requestId == 9)
        #expect(decoded.code == CapResponseCode.notSupported)
        #expect(decoded.typeName == nil)
        #expect(decoded.body == nil)
        #expect(!decoded.isSuccess)
    }

    /// Hardware session (2026-09-29): a log query whose `fromTimestamp` is past
    /// the newest entry is answered with `SUCCESS` and no `body` field at all
    /// (`0d 03010000 10 01` = requestId 259, code 1). Log readers must treat
    /// this as an empty page, not as a protocol error.
    @Test func logQueryPastTheNewestEntryIsSuccessWithoutBody() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode("0d030100001001"))
        #expect(decoded.requestId == 259)
        #expect(decoded.code == CapResponseCode.success)
        #expect(decoded.isSuccess)
        #expect(decoded.typeName == nil)
        #expect(decoded.body == nil)
        #expect(decoded.hasNoBody)
    }

    // MARK: - type_url strings

    @Test func typeUrlsUseTheUnqualifiedMessageNamesFromTheProtocolDoc() throws {
        let expectedRequestUrls: [CapCommand: String] = [
            .setTime: "type.googleapis.com/RequestSetCapTimeSettings",
            .getTime: "type.googleapis.com/RequestGetCapTimeSettings",
            .getUiState: "type.googleapis.com/RequestGetCapUiState",
            .getTofSettings: "type.googleapis.com/RequestGetCapTofSettings",
            .getTofState: "type.googleapis.com/RequestGetCapTofState",
            .getTofLog: "type.googleapis.com/RequestGetCapTofLog",
            .getActivationLog: "type.googleapis.com/RequestGetCapActivationLog",
            .getHydroReminder: "type.googleapis.com/RequestGetCapHydroReminderSettings",
            .setHydroReminder: "type.googleapis.com/RequestSetCapHydroReminderSettings",
            .getDnd: "type.googleapis.com/RequestGetCapDoNotDisturbSettings",
            .setDnd: "type.googleapis.com/RequestSetCapDoNotDisturbSettings",
            .getLowBattery: "type.googleapis.com/RequestGetCapLowBatterySettings",
        ]
        #expect(Set(expectedRequestUrls.keys) == Set(CapCommand.allCases))
        for (command, url) in expectedRequestUrls {
            #expect(command.requestTypeUrl == url)
        }

        // The message structs must carry the exact unqualified names (no package prefix).
        let built = try CapCodec.buildRequest(requestId: 1, body: RequestGetCapUiState())
        #expect(built.body?.typeUrl == "type.googleapis.com/RequestGetCapUiState")
        #expect(RequestGetCapUiState.protoName == "RequestGetCapUiState")
        #expect(ResponseGetCapTofLog.protoName == "ResponseGetCapTofLog")
        #expect(TypeUrls.messageName("type.googleapis.com/RequestGetCapUiState") == "RequestGetCapUiState")
    }

    @Test func requestIdIsEncodedAsFixed32AndReadBackUnsigned() throws {
        let built = try CapCodec.buildRequest(requestId: 0xFFFF_FFF0, body: RequestGetCapUiState())
        #expect(CapCodec.requestId(of: built) == 0xFFFF_FFF0)
        let decoded = try CapCodec.decodeResponse(try Hex.decode("0df0ffffff1001"))
        #expect(decoded.requestId == 0xFFFF_FFF0)
    }

    @Test func requestIdZeroIsOmittedLikeProto3Defaults() throws {
        // The counter never produces 0; if it did, the field would be absent —
        // which is exactly why the counter starts at 1.
        let built = try CapCodec.buildRequest(requestId: 0, body: RequestGetCapUiState())
        #expect(built.requestId == 0)
        #expect(!Hex.encode(built.protoEncoded()).hasPrefix("0d"))
    }

    @Test func unknownFieldsAreSkippedNotRejected() throws {
        // Tag 99, wire 0 (unknown) appended to a valid envelope.
        var bytes = try Hex.decode("0d090000001002")
        bytes.append(contentsOf: [0xd8, 0x06, 0x2a])
        let decoded = try CapCodec.decodeResponse(bytes)
        #expect(decoded.requestId == 9)
        #expect(decoded.code == CapResponseCode.notSupported)
    }

    @Test func strictParseRejectsTrailingGarbage() throws {
        var bytes = try Hex.decode("0d090000001002")
        bytes.append(contentsOf: [0xff])
        #expect(CapCodec.tryDecodeComplete(bytes) == nil)
        #expect(CapCodec.tryDecodeComplete(try Hex.decode("0d090000001002")) != nil)
        #expect(CapCodec.tryDecodeComplete(Data()) == nil)
    }
}
