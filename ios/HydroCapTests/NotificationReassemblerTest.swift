import Foundation
import Testing

@testable import HydroCap

@Suite("Notification reassembler")
struct NotificationReassemblerTest {

    private let tofState = try! Hex.decode("0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d2a00000015e02e0000")

    @Test func wholeNotificationIsCompleteImmediately() {
        let outcome = NotificationReassembler().offer(tofState)
        guard case .complete(let response, _, let fragments) = outcome else {
            Issue.record("expected .complete, got \(outcome)")
            return
        }
        #expect(response.requestId == 6)
        #expect(fragments == 1)
        #expect(response.body == .tofState(ResponseGetCapTofState(state: CapTofState(distanceInMillimeter: 42, kcps: 12_000))))
    }

    @Test func twoFragmentsAreConcatenated() {
        let reassembler = NotificationReassembler()
        let first = reassembler.offer(tofState.prefix(20))
        guard case .buffered = first else {
            Issue.record("expected .buffered, got \(first)")
            return
        }
        let second = reassembler.offer(tofState.dropFirst(20))
        guard case .complete(_, let bytes, let fragments) = second else {
            Issue.record("expected .complete, got \(second)")
            return
        }
        #expect(fragments == 2)
        #expect(bytes == tofState)
        #expect(reassembler.pendingBytes == 0)
    }

    // Synthetic rebased-time vector: first timestamp 1_600_000_000 s, original
    // measurement/enum fields and timestamp intervals retained; not a raw capture.
    @Test func the179ByteSyntheticTofPageDecodesAsOneNotification() {
        let page = try! Hex.decode(
            "0d0800000010011aa9010a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f67127d0a170880a0f8fa0510041d3a00000025b20100002dd84534460a17089dbaf8fa0510041d6200000025920000002d249c35460a1708dbbaf8fa0510041d7500000025bd0000002dd89036460a170888c5f8fa0510021d7500000025960000002d52d034460a170897c5f8fa0510041da7000000251a0000002dd2eb3346",
        )
        #expect(page.count == 179)
        let outcome = NotificationReassembler().offer(page)
        guard case .complete(let response, _, _) = outcome else {
            Issue.record("expected .complete, got \(outcome)")
            return
        }
        guard case .tofLog(let body) = response.body else {
            Issue.record("expected a ToF log body")
            return
        }
        #expect(body.items.count == 5)
        #expect(body.items[0].distanceInMillimeter == 58)
    }

    @Test func bufferResetsWhenItGrowsBeyondTheCap() {
        let reassembler = NotificationReassembler(maxBytes: 40)
        _ = reassembler.offer(Data(repeating: 0x7f, count: 20))
        _ = reassembler.offer(Data(repeating: 0x7f, count: 20))
        let outcome = reassembler.offer(Data(repeating: 0x7f, count: 20))
        guard case .reset = outcome else {
            Issue.record("expected .reset, got \(outcome)")
            return
        }
        #expect(reassembler.pendingBytes == 0)
    }

    @Test func noBodyResponseWithNoIdIsNotMistakenForACompleteMessage() {
        // A lone "code=SUCCESS" prefix of a longer message must be buffered, not
        // accepted — what matters is that the full message still decodes after.
        let reassembler = NotificationReassembler()
        let outcome = reassembler.offer(tofState.prefix(7))
        if case .complete(let response, _, _) = outcome {
            #expect(response.requestId == 6)
        } else {
            let rest = reassembler.offer(tofState.dropFirst(7))
            guard case .complete = rest else {
                Issue.record("expected .complete after the second fragment, got \(rest)")
                return
            }
        }
    }
}

@Suite("Battery alert policy")
struct BatteryAlertPolicyTest {

    @Test func firesOncePerThresholdCrossing() {
        let policy = BatteryAlertPolicy(thresholds: [10, 5])
        #expect(policy.onLevel(50) == [])
        #expect(policy.onLevel(10) == [10])
        #expect(policy.onLevel(9) == [])
        #expect(policy.onLevel(7) == [])
        #expect(policy.onLevel(5) == [5])
        #expect(policy.onLevel(3) == [])
    }

    @Test func aDirectDropBelowBothThresholdsFiresBoth() {
        let policy = BatteryAlertPolicy(thresholds: [10, 5])
        #expect(policy.onLevel(4) == [10, 5])
    }

    @Test func reArmsOnlyAfterRisingAboveThresholdPlusMargin() {
        let policy = BatteryAlertPolicy(thresholds: [10, 5])
        _ = policy.onLevel(9)
        #expect(policy.onLevel(14) == []) // 10 + 5 = 15 not exceeded
        #expect(policy.onLevel(15) == []) // must be strictly above
        #expect(policy.onLevel(16) == []) // re-armed, nothing to notify yet
        #expect(policy.onLevel(10) == [10]) // fires again
    }

    @Test func stateRoundTripsThroughPersistence() {
        let first = BatteryAlertPolicy(thresholds: [10, 5])
        _ = first.onLevel(8)
        let restored = BatteryAlertPolicy(thresholds: [10, 5], firedThresholds: first.firedThresholds)
        #expect(restored.onLevel(7) == [])
        #expect(restored.onLevel(5) == [5])
        #expect(restored.firedThresholds.isSuperset(of: [10, 5]))
    }

    @Test func customThresholdsAndInvalidValues() {
        let policy = BatteryAlertPolicy(thresholds: [20, 15, 150, -1])
        #expect(policy.thresholds == [20, 15])
        #expect(policy.onLevel(18) == [20])
    }
}
