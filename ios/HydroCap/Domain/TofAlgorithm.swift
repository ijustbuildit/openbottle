import Foundation

/// One raw ToF reading, time-ordered input to `TofAlgorithm`.
nonisolated struct TofReading: Sendable, Equatable {
    let timestampSec: Int64
    let distanceMm: Int
    let kcps: Int

    init(timestampSec: Int64, distanceMm: Int, kcps: Int) {
        self.timestampSec = timestampSec
        self.distanceMm = distanceMm
        self.kcps = kcps
    }
}

nonisolated enum TofEventKind: String, Sendable {
    case fill = "FILL"
    case intake = "INTAKE"
    case skip = "SKIP"
}

/// Classification of one reading. `countedMl` is non-zero only for INTAKE and
/// the fill-after-skip branch.
nonisolated struct TofEvent: Sendable, Equatable {
    let reading: TofReading
    let kind: TofEventKind
    let volumeMl: Double
    let countedMl: Double
}

/// Mutable state of the fill/intake state machine (protocol doc §5). Kept as a
/// plain value so the sync engine can run the algorithm over the entire stored
/// log deterministically and unit tests can inspect it.
nonisolated struct TofAlgorithmState: Sendable, Equatable {
    var lastCalcMl: Double? = nil
    var lastCountedMl: Double? = nil
    var lastSkippedMl: Double? = nil
    var previousWasSkipped: Bool = false

    init(lastCalcMl: Double? = nil, lastCountedMl: Double? = nil, lastSkippedMl: Double? = nil, previousWasSkipped: Bool = false) {
        self.lastCalcMl = lastCalcMl
        self.lastCountedMl = lastCountedMl
        self.lastSkippedMl = lastSkippedMl
        self.previousWasSkipped = previousWasSkipped
    }
}

/// Distance → volume polynomial plus the event classifier, exactly as written
/// in docs/protocol/ble-protocol.md §5. Parameters come from `BottleProfile`.
///
/// 1. `v = clamp(poly(d), minVolume)`; `d ≥ tofMax` → SKIP (state unchanged).
/// 2. `Δfill = v − lastCalc`, `Δdrink = lastCounted − v`.
/// 3. `Δfill > fillThreshold` → FILL (counted 0, except when the previous
///    reading was skipped: count `lastCounted − lastSkipped` if > 0).
/// 4. else `Δdrink > drinkThreshold` → INTAKE of Δdrink ml.
/// 5. else SKIP, remember `lastSkipped = v`.
/// 6. `lastCounted = v` on every non-skipped reading.
nonisolated struct TofAlgorithm: Sendable {
    let profile: BottleProfile

    init(profile: BottleProfile) {
        self.profile = profile
    }

    func volumeMl(_ distanceMm: Int) -> Double { profile.volumeMl(distanceMm) }

    /// Whether a raw distance is a usable measurement.
    func isInRange(_ distanceMm: Int) -> Bool { distanceMm < profile.tofMaxMm }

    func step(state: TofAlgorithmState, reading: TofReading) -> (TofAlgorithmState, TofEvent) {
        guard isInRange(reading.distanceMm) else {
            // Sensor could not read (d ≥ tofMax): state is kept untouched.
            return (state, TofEvent(reading: reading, kind: .skip, volumeMl: .nan, countedMl: 0.0))
        }
        let v = volumeMl(reading.distanceMm)
        guard let lastCalc = state.lastCalcMl, let lastCounted = state.lastCountedMl else {
            // First usable reading seeds the state without producing a countable event.
            let next = TofAlgorithmState(lastCalcMl: v, lastCountedMl: v, lastSkippedMl: nil, previousWasSkipped: false)
            return (next, TofEvent(reading: reading, kind: .skip, volumeMl: v, countedMl: 0.0))
        }

        let deltaFill = v - lastCalc
        let deltaDrink = lastCounted - v

        if deltaFill > profile.fillThresholdMl {
            var counted = 0.0
            if state.previousWasSkipped, let lastSkipped = state.lastSkippedMl {
                let candidate = lastCounted - lastSkipped
                counted = candidate > 0.0 ? candidate : 0.0
            }
            let next = TofAlgorithmState(lastCalcMl: v, lastCountedMl: v, lastSkippedMl: nil, previousWasSkipped: false)
            return (next, TofEvent(reading: reading, kind: .fill, volumeMl: v, countedMl: counted))
        }

        if deltaDrink > profile.drinkThresholdMl {
            let next = TofAlgorithmState(lastCalcMl: v, lastCountedMl: v, lastSkippedMl: nil, previousWasSkipped: false)
            return (next, TofEvent(reading: reading, kind: .intake, volumeMl: v, countedMl: deltaDrink))
        }

        // Jitter below the thresholds: not counted, but remembered for the
        // fill-after-skip branch.
        var next = state
        next.lastCalcMl = v
        next.lastSkippedMl = v
        next.previousWasSkipped = true
        return (next, TofEvent(reading: reading, kind: .skip, volumeMl: v, countedMl: 0.0))
    }

    /// Runs the state machine over time-ordered readings and returns every
    /// event (including skips).
    func run(_ readings: [TofReading], initial: TofAlgorithmState = TofAlgorithmState()) -> [TofEvent] {
        var state = initial
        var events: [TofEvent] = []
        events.reserveCapacity(readings.count)
        for reading in readings.sorted(by: { $0.timestampSec < $1.timestampSec }) {
            let (next, event) = step(state: state, reading: reading)
            state = next
            events.append(event)
        }
        return events
    }

    /// Convenience: only the events that add to the intake total.
    func drinkEvents(_ readings: [TofReading]) -> [TofEvent] {
        run(readings).filter { $0.countedMl > 0.0 }
    }
}
