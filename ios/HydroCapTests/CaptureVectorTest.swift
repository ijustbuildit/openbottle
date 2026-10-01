import Foundation
import Testing

@testable import HydroCap

/// Interoperability vectors: generic settings retain their observed wire values.
/// Clock/history vectors are regenerated with a uniform time shift to the
/// synthetic ToF epoch 1_600_000_000 s; measurement fields and intervals are
/// retained. Device identity uses a generated patterned integer, not a real cap.
/// These rebased vectors are not raw hardware captures.
@Suite("Protocol interoperability vectors")
struct CaptureVectorTest {

    // Generic settings wire values (request ids 1…6), not synthetic captures.
    @Test func nusProbeUiState() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0100000010011a310a29747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170556953746174651204080f1001",
        ))
        #expect(decoded.requestId == 1)
        #expect(decoded.isSuccess)
        #expect(decoded.body == .uiState(ResponseGetCapUiState(state: CapUiState.allOff, powerSavingMode: CapPowerSavingMode.off)))
    }

    @Test func nusProbeTofSettings() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0200000010011a490a2d747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f6653657474696e677312180a1608021db004000025040000002de803000035b4000000",
        ))
        #expect(decoded.requestId == 2)
        let settings = try #require(decoded.body?.tofSettings?.settings)
        #expect(settings.mode == CapTofMode.event)
        #expect(settings.isIntervalTriggerEnabled == false)
        #expect(settings.triggerIntervalInSec == 1200)
        #expect(settings.accelerometerCheckIntervalInSec == 4)
        // Hardware session 1: the cap reports 1000 ml for a 680 ml body — the value is
        // informational and must never switch the profile.
        #expect(settings.bottleSizeInMilliliter == 1000)
        #expect(settings.accelerometerTimeoutInSec == 180)
    }

    @Test func nusProbeLowBatterySettings() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0300000010011a440a34747970652e676f6f676c65617069732e636f6d2f526573706f6e73654765744361704c6f774261747465727953657474696e6773120c0a0a0d140000001505000000",
        ))
        #expect(decoded.requestId == 3)
        let settings = try #require(decoded.body?.lowBattery?.settings)
        #expect(settings.alertThresholdInPercentage == 20)
        #expect(settings.lockoutThresholdInPercentage == 5)
    }

    @Test func nusProbeHydroReminder() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0400000010011a550a37747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170487964726f52656d696e64657253657474696e6773121a0a18080215807000001ddc31010025080700002a05250000803f",
        ))
        #expect(decoded.requestId == 4)
        let config = try #require(decoded.body?.hydroReminder?.settings)
        let reminder = ReminderMapping.fromProto(config)
        #expect(reminder.mode == ReminderSettings.modeAdaptive)
        #expect(reminder.startSec == 28_800)
        #expect(reminder.stopSec == 78_300)
        #expect(reminder.intervalSec == 1_800)
        #expect(reminder.color.isFirmwareDefault)
        #expect(reminder.color.alpha == 1)
    }

    @Test func nusProbeDoNotDisturb() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0500000010011a480a36747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170446f4e6f744469737475726253657474696e6773120e0a0c080215dc3101001d80700000",
        ))
        #expect(decoded.requestId == 5)
        let config = try #require(decoded.body?.dnd?.settings)
        let dnd = ReminderMapping.fromProto(config)
        #expect(dnd.mode == DndSettings.modeAuto)
        #expect(dnd.startSec == 78_300)
        #expect(dnd.stopSec == 28_800)
        #expect(dnd.snoozeMinutes == 0)
    }

    @Test func nusProbeLiveTofState() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d5b00000015d2020000",
        ))
        #expect(decoded.requestId == 6)
        let state = try #require(decoded.body?.tofState?.state)
        #expect(state.distanceInMillimeter == 91)
        #expect(state.kcps == 722)
        // With the calibrated 680 ml curve, 91 mm is ≈ 400 ml (uncalibrated
        // curves disagree badly — that is why calibration happened).
        let volume = BottleProfile.body680NoFilterCal.volumeMl(91)
        #expect(abs(volume - 400.0) <= 20.0)
    }

    // Synthetic clock, shifted by the same whole-second offset as both logs.
    @Test func syntheticCapClockIsReadBack() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0700000010011a3b0a2e747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617054696d6553657474696e677312090a070883e982b4f72e",
        ))
        #expect(decoded.requestId == 7)
        let settings = try #require(decoded.body?.timeSettings?.settings)
        #expect(settings.timeInMillisec == 1_612_600_882_307)
    }

    /// Synthetic SetTime request for exactly the regenerated clock above.
    @Test func syntheticSetTimeReencodesTheRebasedClock() throws {
        let expected = "0d07000000123a0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737453657443617054696d6553657474696e677312090a070883e982b4f72e"
        let body = RequestSetCapTimeSettings(settings: CapTimeSettings(timeInMillisec: 1_612_600_882_307))
        #expect(Hex.encode(try CapCodec.encodeRequest(requestId: 7, body: body)) == expected)
    }

    /// Synthetic rebased-time 179-byte page, retaining the one-notification
    /// MTU 247 boundary regression, five measurements and original wire widths.
    @Test func syntheticTofLogPage() throws {
        let bytes = try Hex.decode(
            "0d0800000010011aa9010a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f67127d0a170880a0f8fa0510041d3a00000025b20100002dd84534460a17089dbaf8fa0510041d6200000025920000002d249c35460a1708dbbaf8fa0510041d7500000025bd0000002dd89036460a170888c5f8fa0510021d7500000025960000002d52d034460a170897c5f8fa0510041da7000000251a0000002dd2eb3346",
        )
        #expect(bytes.count == 179)
        let decoded = try CapCodec.decodeResponse(bytes)
        #expect(decoded.requestId == 8)
        let items = try #require(decoded.body?.tofLog?.items)
        #expect(items.count == 5)
        #expect(items.map { $0.timestamp } == [1_600_000_000, 1_600_003_357, 1_600_003_419, 1_600_004_744, 1_600_004_759])
        #expect(items.map { $0.distanceInMillimeter } == [58, 98, 117, 117, 167])
        #expect(items.map { $0.kcps } == [434, 146, 189, 150, 26])
        #expect(items[0].triggerType == CapTofTriggerType.capOnFlapOpenSip)
        #expect(items[3].triggerType == CapTofTriggerType.cap)
    }

    /// Synthetic activation history using the same time shift as the ToF page.
    @Test func syntheticActivationLogPage() throws {
        let decoded = try CapCodec.decodeResponse(try Hex.decode(
            "0d0900000010011a740a2f747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617041637469766174696f6e4c6f6712410a0b08e8d7c7ff051d330000000a0b08a191c8ff051d290000000a0b08dbcac8ff051d2d0000000a0b089484c9ff051d340000000a0b08cebdc9ff051d2a000000",
        ))
        #expect(decoded.requestId == 9)
        let items = try #require(decoded.body?.activationLog?.items)
        #expect(items.count == 5)
        #expect(items.map { $0.timestamp } == [1_609_690_088, 1_609_697_441, 1_609_704_795, 1_609_712_148, 1_609_719_502])
        #expect(items.map { $0.batterySocInPercentage } == [51, 41, 45, 52, 42])
        #expect(items.allSatisfy { $0.mode == CapUvActivationMode.maintenance })
    }

    /// Generic GET wire vectors must re-encode exactly from the request structs.
    @Test func nusProbeRequestHexesReencodeByteForByte() throws {
        let vectors: [(UInt32, String)] = [
            (1, "0d01000000122a0a28747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617055695374617465"),
            (2, "0d02000000122e0a2c747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f6653657474696e6773"),
            (3, "0d0300000012350a33747970652e676f6f676c65617069732e636f6d2f526571756573744765744361704c6f774261747465727953657474696e6773"),
            (4, "0d0400000012380a36747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170487964726f52656d696e64657253657474696e6773"),
            (5, "0d0500000012370a35747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170446f4e6f744469737475726253657474696e6773"),
            (6, "0d06000000122b0a29747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f665374617465"),
            (7, "0d07000000122f0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617054696d6553657474696e6773"),
            (8, "0d0800000012320a27747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f664c6f6712070a051505000000"),
            (9, "0d0900000012390a2e747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617041637469766174696f6e4c6f6712070a051505000000"),
        ]
        for (id, expectedHex) in vectors {
            let body: Data
            switch id {
            case 1: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapUiState())
            case 2: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapTofSettings())
            case 3: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapLowBatterySettings())
            case 4: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapHydroReminderSettings())
            case 5: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapDoNotDisturbSettings())
            case 6: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapTofState())
            case 7: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapTimeSettings())
            case 8: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapTofLog(query: CapLogQuery(fromTimestamp: 0, limit: 5, algo: CapLogQuerySearchAlgo.timestamp)))
            default: body = try CapCodec.encodeRequest(requestId: id, body: RequestGetCapActivationLog(query: CapLogQuery(fromTimestamp: 0, limit: 5, algo: CapLogQuerySearchAlgo.timestamp)))
            }
            #expect(Hex.encode(body) == expectedHex, "request \(id) re-encode mismatch")
        }
    }

    /// Synthetic ID: base62(0xFEDCBA9876543210), alphabet 0-9A-Za-z;
    /// its ASCII serial hex is generated from the same 16-character string.
    /// Other DIS/battery constants are non-unique interoperability examples.
    @Test func gattProbeDeviceInformationMatchesTheScanName() throws {
        let serial = try #require(DeviceName.decodeDeviceId("LARQ_LscmunaixMG"))
        #expect(serial == "FEDCBA9876543210")
        #expect(String(data: try Hex.decode("4c415251"), encoding: .utf8) == "LARQ")
        #expect(String(data: try Hex.decode("434150"), encoding: .utf8) == "CAP")
        #expect(String(data: try Hex.decode("46454443424139383736353433323130"), encoding: .utf8) == serial)
        #expect(String(data: try Hex.decode("3030303030313031"), encoding: .utf8) == "00000101")
        #expect(String(data: try Hex.decode("312e303437"), encoding: .utf8) == "1.047")
        #expect(try Hex.decode("62").first == 98)
    }
}
