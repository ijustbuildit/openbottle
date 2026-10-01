package dev.hydrocap.app.domain

/** One raw ToF reading, time-ordered input to [TofAlgorithm]. */
data class TofReading(
    val timestampSec: Long,
    val distanceMm: Int,
    val kcps: Int,
)

enum class TofEventKind { FILL, INTAKE, SKIP }

/** Classification of one reading. [countedMl] is non-zero only for INTAKE and the fill-after-skip branch. */
data class TofEvent(
    val reading: TofReading,
    val kind: TofEventKind,
    val volumeMl: Double,
    val countedMl: Double,
)

/**
 * Mutable state of the fill/intake state machine (protocol doc §5). Kept as a
 * plain value so the SyncEngine can run the algorithm over the entire stored
 * log deterministically and unit tests can inspect it.
 */
data class TofAlgorithmState(
    val lastCalcMl: Double? = null,
    val lastCountedMl: Double? = null,
    val lastSkippedMl: Double? = null,
    val previousWasSkipped: Boolean = false,
)

/**
 * Distance → volume polynomial plus the event classifier, exactly as written
 * in docs/protocol/ble-protocol.md §5. Parameters come from [BottleProfile].
 *
 * 1. `v = clamp(poly(d), minVolume)`; `d ≥ tofMax` → SKIP (state unchanged).
 * 2. `Δfill = v − lastCalc`, `Δdrink = lastCounted − v`.
 * 3. `Δfill > fillThreshold` → FILL (counted 0, except when the previous
 *    reading was skipped: count `lastCounted − lastSkipped` if > 0).
 * 4. else `Δdrink > drinkThreshold` → INTAKE of Δdrink ml.
 * 5. else SKIP, remember `lastSkipped = v`.
 * 6. `lastCounted = v` on every non-skipped reading.
 */
class TofAlgorithm(private val profile: BottleProfile) {

    fun volumeMl(distanceMm: Int): Double = profile.volumeMl(distanceMm)

    /** Whether a raw distance is a usable measurement. */
    fun isInRange(distanceMm: Int): Boolean = distanceMm < profile.tofMaxMm

    fun step(state: TofAlgorithmState, reading: TofReading): Pair<TofAlgorithmState, TofEvent> {
        if (!isInRange(reading.distanceMm)) {
            // Sensor could not read (d ≥ tofMax): state is kept untouched.
            val event = TofEvent(reading, TofEventKind.SKIP, Double.NaN, 0.0)
            return state to event
        }
        val v = volumeMl(reading.distanceMm)
        val lastCalc = state.lastCalcMl
        val lastCounted = state.lastCountedMl

        if (lastCalc == null || lastCounted == null) {
            // First usable reading seeds the state without producing a countable event.
            val next = TofAlgorithmState(lastCalcMl = v, lastCountedMl = v, lastSkippedMl = null, previousWasSkipped = false)
            return next to TofEvent(reading, TofEventKind.SKIP, v, 0.0)
        }

        val deltaFill = v - lastCalc
        val deltaDrink = lastCounted - v

        return when {
            deltaFill > profile.fillThresholdMl -> {
                val counted = if (state.previousWasSkipped && state.lastSkippedMl != null) {
                    (lastCounted - state.lastSkippedMl).takeIf { it > 0.0 } ?: 0.0
                } else {
                    0.0
                }
                val next = TofAlgorithmState(lastCalcMl = v, lastCountedMl = v, lastSkippedMl = null, previousWasSkipped = false)
                next to TofEvent(reading, TofEventKind.FILL, v, counted)
            }

            deltaDrink > profile.drinkThresholdMl -> {
                val next = TofAlgorithmState(lastCalcMl = v, lastCountedMl = v, lastSkippedMl = null, previousWasSkipped = false)
                next to TofEvent(reading, TofEventKind.INTAKE, v, deltaDrink)
            }

            else -> {
                // Jitter below the thresholds: not counted, but remembered for the fill-after-skip branch.
                val next = state.copy(lastCalcMl = v, lastSkippedMl = v, previousWasSkipped = true)
                next to TofEvent(reading, TofEventKind.SKIP, v, 0.0)
            }
        }
    }

    /** Runs the state machine over time-ordered readings and returns every event (including skips). */
    fun run(readings: List<TofReading>, initial: TofAlgorithmState = TofAlgorithmState()): List<TofEvent> {
        var state = initial
        val events = ArrayList<TofEvent>(readings.size)
        for (reading in readings.sortedBy { it.timestampSec }) {
            val (next, event) = step(state, reading)
            state = next
            events += event
        }
        return events
    }

    /** Convenience: only the events that add to the intake total. */
    fun drinkEvents(readings: List<TofReading>): List<TofEvent> =
        run(readings).filter { it.countedMl > 0.0 }
}
