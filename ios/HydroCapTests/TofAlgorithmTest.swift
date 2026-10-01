import Foundation
import Testing

@testable import HydroCap

@Suite("ToF algorithm")
struct TofAlgorithmTest {

    private let profile = BottleProfile.body680
    private var algo: TofAlgorithm { TofAlgorithm(profile: profile) }

    private func reading(_ t: Int64, _ mm: Int) -> TofReading {
        TofReading(timestampSec: t, distanceMm: mm, kcps: 5_000)
    }

    @Test func polynomialMatchesTheSanityValuesFromTheProtocolDoc() {
        #expect(abs(profile.volumeMl(0) - 715.15) <= 0.01)
        #expect(abs(profile.volumeMl(37) - 618.77) <= 0.01)
        #expect(abs(profile.volumeMl(200) - 59.30) <= 0.01)
        #expect(abs(profile.volumeMl(215) - 0.0) <= 0.0) // crosses zero → clamped at minVolume
        #expect(abs(BottleProfile.body1000.volumeMl(0) - 1026.71) <= 0.01)
        #expect(abs(BottleProfile.body1000.volumeMl(37) - 926.0) <= 1.0)
    }

    @Test func monotonicDrinkingProducesOneIntakePerSip() {
        let events = algo.run([reading(1, 40), reading(2, 60), reading(3, 80), reading(4, 100)])
        #expect(events[0].kind == .skip) // seeds the state
        #expect(events.dropFirst().map(\.kind) == [.intake, .intake, .intake])
        #expect(abs(events[1].countedMl - (profile.volumeMl(40) - profile.volumeMl(60))) <= 1e-9)
        #expect(abs(events[2].countedMl - (profile.volumeMl(60) - profile.volumeMl(80))) <= 1e-9)
        #expect(abs(events[3].countedMl - (profile.volumeMl(80) - profile.volumeMl(100))) <= 1e-9)
        let total = algo.drinkEvents([reading(1, 40), reading(2, 60), reading(3, 80), reading(4, 100)]).reduce(0) { $0 + $1.countedMl }
        #expect(abs(total - (profile.volumeMl(40) - profile.volumeMl(100))) <= 1e-9)
    }

    @Test func refillIsAFillEventWithZeroCountedVolume() {
        let events = algo.run([reading(1, 40), reading(2, 120), reading(3, 40)])
        #expect(events[1].kind == .intake)
        #expect(events[2].kind == .fill)
        #expect(events[2].countedMl == 0.0)
        // Drinking after the refill counts from the refilled level.
        let more = algo.run([reading(1, 40), reading(2, 120), reading(3, 40), reading(4, 70)])
        #expect(more[3].kind == .intake)
        #expect(abs(more[3].countedMl - (profile.volumeMl(40) - profile.volumeMl(70))) <= 1e-9)
    }

    @Test func outOfRangeReadingIsSkippedAndDoesNotDisturbTheState() {
        let events = algo.run([reading(1, 40), reading(2, 250), reading(3, 300), reading(4, 60)])
        #expect(events[1].kind == .skip)
        #expect(events[1].volumeMl.isNaN)
        #expect(events[2].kind == .skip)
        // The intake is measured against the last good reading (40 mm), not the bogus one.
        #expect(events[3].kind == .intake)
        #expect(abs(events[3].countedMl - (profile.volumeMl(40) - profile.volumeMl(60))) <= 1e-9)
    }

    @Test func tinyJitterBelowDrinkThresholdIsNotCounted() {
        // 40 → 42 mm is 607.1 − 599.2 ≈ 7.9 ml, well below the 15 ml drink threshold.
        let events = algo.run([reading(1, 40), reading(2, 42), reading(3, 41), reading(4, 42)])
        #expect(events.map(\.kind) == [.skip, .skip, .skip, .skip])
        #expect(events.reduce(0) { $0 + $1.countedMl } == 0.0)
    }

    @Test func jitterAccumulatesAgainstLastCountedUntilTheThresholdIsCrossed() {
        // Each step is < 15 ml but the drift from the last counted level exceeds it at 45 mm.
        let events = algo.run([reading(1, 40), reading(2, 42), reading(3, 45)])
        #expect(events[1].kind == .skip)
        #expect(events[2].kind == .intake)
        #expect(abs(events[2].countedMl - (profile.volumeMl(40) - profile.volumeMl(45))) <= 1e-9)
    }

    @Test func fillAfterASkippedReadingCountsTheVolumeDrunkBeforeTheRefill() {
        // 80 mm counted, 82 mm skipped (≈8 ml jitter, remembered as lastSkipped),
        // then a refill to 30 mm (Δfill ≈ 212 ml > 100): the doc says count
        // lastCounted − lastSkipped if > 0.
        let events = algo.run([reading(1, 80), reading(2, 82), reading(3, 30)])
        #expect(events[1].kind == .skip)
        #expect(events[2].kind == .fill)
        let expected = profile.volumeMl(80) - profile.volumeMl(82)
        #expect(expected > 0.0)
        #expect(abs(events[2].countedMl - expected) <= 1e-9)
        #expect(algo.drinkEvents([reading(1, 80), reading(2, 82), reading(3, 30)]).count == 1)
        #expect(algo.drinkEvents([reading(1, 80), reading(2, 82), reading(3, 30)]).first?.kind == .fill)
    }

    @Test func fillAfterASkippedReadingWithNegativeDifferenceCountsNothing() {
        // Skipped reading slightly *fuller* than lastCounted (80 → 79 mm), then refill to 30 mm.
        let events = algo.run([reading(1, 80), reading(2, 79), reading(3, 30)])
        #expect(events[1].kind == .skip)
        #expect(events[2].kind == .fill)
        #expect(events[2].countedMl == 0.0)
    }

    @Test func fillDirectlyAfterACountedReadingCountsNothing() {
        let events = algo.run([reading(1, 80), reading(2, 120), reading(3, 30)])
        #expect(events[1].kind == .intake)
        #expect(events[2].kind == .fill)
        #expect(events[2].countedMl == 0.0)
    }

    @Test func readingsAreProcessedInTimestampOrderRegardlessOfInputOrder() {
        let ordered = algo.run([reading(1, 40), reading(2, 60), reading(3, 80)])
        let shuffled = algo.run([reading(3, 80), reading(1, 40), reading(2, 60)])
        #expect(ordered == shuffled)
    }

    @Test func stateCanBeResumedBetweenRuns() {
        let (afterFirst, _) = algo.step(state: TofAlgorithmState(), reading: reading(1, 40))
        let (afterSecond, event) = algo.step(state: afterFirst, reading: reading(2, 60))
        #expect(event.kind == .intake)
        #expect(abs((afterSecond.lastCountedMl ?? .nan) - profile.volumeMl(60)) <= 1e-9)
    }
}
