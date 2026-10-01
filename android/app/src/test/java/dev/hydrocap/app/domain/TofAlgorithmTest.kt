package dev.hydrocap.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TofAlgorithmTest {

    private val profile = BottleProfile.BODY_680
    private val algo = TofAlgorithm(profile)
    private fun r(t: Long, mm: Int) = TofReading(timestampSec = t, distanceMm = mm, kcps = 5_000)

    @Test
    fun `polynomial matches the sanity values from the protocol doc`() {
        assertEquals(715.15, profile.volumeMl(0), 0.01)
        assertEquals(618.77, profile.volumeMl(37), 0.01)
        assertEquals(59.30, profile.volumeMl(200), 0.01)
        assertEquals(0.0, profile.volumeMl(215), 0.0) // crosses zero → clamped at minVolume
        assertEquals(1026.71, BottleProfile.BODY_1000.volumeMl(0), 0.01)
        assertEquals(926.0, BottleProfile.BODY_1000.volumeMl(37), 1.0)
    }

    @Test
    fun `monotonic drinking produces one intake per sip`() {
        val events = algo.run(listOf(r(1, 40), r(2, 60), r(3, 80), r(4, 100)))
        assertEquals(TofEventKind.SKIP, events[0].kind) // seeds the state
        assertEquals(listOf(TofEventKind.INTAKE, TofEventKind.INTAKE, TofEventKind.INTAKE), events.drop(1).map { it.kind })
        assertEquals(profile.volumeMl(40) - profile.volumeMl(60), events[1].countedMl, 1e-9)
        assertEquals(profile.volumeMl(60) - profile.volumeMl(80), events[2].countedMl, 1e-9)
        assertEquals(profile.volumeMl(80) - profile.volumeMl(100), events[3].countedMl, 1e-9)
        val total = algo.drinkEvents(listOf(r(1, 40), r(2, 60), r(3, 80), r(4, 100))).sumOf { it.countedMl }
        assertEquals(profile.volumeMl(40) - profile.volumeMl(100), total, 1e-9)
    }

    @Test
    fun `refill is a FILL event with zero counted volume`() {
        val events = algo.run(listOf(r(1, 40), r(2, 120), r(3, 40)))
        assertEquals(TofEventKind.INTAKE, events[1].kind)
        assertEquals(TofEventKind.FILL, events[2].kind)
        assertEquals(0.0, events[2].countedMl, 0.0)
        // Drinking after the refill counts from the refilled level.
        val more = algo.run(listOf(r(1, 40), r(2, 120), r(3, 40), r(4, 70)))
        assertEquals(TofEventKind.INTAKE, more[3].kind)
        assertEquals(profile.volumeMl(40) - profile.volumeMl(70), more[3].countedMl, 1e-9)
    }

    @Test
    fun `out of range reading is skipped and does not disturb the state`() {
        val events = algo.run(listOf(r(1, 40), r(2, 250), r(3, 300), r(4, 60)))
        assertEquals(TofEventKind.SKIP, events[1].kind)
        assertTrue(events[1].volumeMl.isNaN())
        assertEquals(TofEventKind.SKIP, events[2].kind)
        // The intake is measured against the last good reading (40 mm), not the bogus one.
        assertEquals(TofEventKind.INTAKE, events[3].kind)
        assertEquals(profile.volumeMl(40) - profile.volumeMl(60), events[3].countedMl, 1e-9)
    }

    @Test
    fun `tiny jitter below drinkThreshold is not counted`() {
        // 40 → 42 mm is 607.1 − 599.2 ≈ 7.9 ml, well below the 15 ml drink threshold.
        val events = algo.run(listOf(r(1, 40), r(2, 42), r(3, 41), r(4, 42)))
        assertEquals(listOf(TofEventKind.SKIP, TofEventKind.SKIP, TofEventKind.SKIP, TofEventKind.SKIP), events.map { it.kind })
        assertEquals(0.0, events.sumOf { it.countedMl }, 0.0)
    }

    @Test
    fun `jitter accumulates against lastCounted until the threshold is crossed`() {
        // Each step is < 15 ml but the drift from the last counted level exceeds it at 45 mm.
        val events = algo.run(listOf(r(1, 40), r(2, 42), r(3, 45)))
        assertEquals(TofEventKind.SKIP, events[1].kind)
        assertEquals(TofEventKind.INTAKE, events[2].kind)
        assertEquals(profile.volumeMl(40) - profile.volumeMl(45), events[2].countedMl, 1e-9)
    }

    @Test
    fun `fill after a skipped reading counts the volume drunk before the refill`() {
        // 80 mm counted, 82 mm skipped (≈8 ml jitter, remembered as lastSkipped), then a refill to 30 mm
        // (Δfill ≈ 212 ml > 100): the doc says count lastCounted − lastSkipped if > 0.
        val events = algo.run(listOf(r(1, 80), r(2, 82), r(3, 30)))
        assertEquals(TofEventKind.SKIP, events[1].kind)
        assertEquals(TofEventKind.FILL, events[2].kind)
        val expected = profile.volumeMl(80) - profile.volumeMl(82)
        assertTrue(expected > 0.0)
        assertEquals(expected, events[2].countedMl, 1e-9)
        assertTrue(algo.drinkEvents(listOf(r(1, 80), r(2, 82), r(3, 30))).single().kind == TofEventKind.FILL)
    }

    @Test
    fun `fill after a skipped reading with negative difference counts nothing`() {
        // Skipped reading slightly *fuller* than lastCounted (80 → 79 mm), then refill to 30 mm.
        val events = algo.run(listOf(r(1, 80), r(2, 79), r(3, 30)))
        assertEquals(TofEventKind.SKIP, events[1].kind)
        assertEquals(TofEventKind.FILL, events[2].kind)
        assertEquals(0.0, events[2].countedMl, 0.0)
    }

    @Test
    fun `fill directly after a counted reading counts nothing`() {
        val events = algo.run(listOf(r(1, 80), r(2, 120), r(3, 30)))
        assertEquals(TofEventKind.INTAKE, events[1].kind)
        assertEquals(TofEventKind.FILL, events[2].kind)
        assertEquals(0.0, events[2].countedMl, 0.0)
    }

    @Test
    fun `readings are processed in timestamp order regardless of input order`() {
        val ordered = algo.run(listOf(r(1, 40), r(2, 60), r(3, 80)))
        val shuffled = algo.run(listOf(r(3, 80), r(1, 40), r(2, 60)))
        assertEquals(ordered, shuffled)
    }

    @Test
    fun `state can be resumed between runs`() {
        val (afterFirst, _) = algo.step(TofAlgorithmState(), r(1, 40))
        val (afterSecond, event) = algo.step(afterFirst, r(2, 60))
        assertEquals(TofEventKind.INTAKE, event.kind)
        assertEquals(profile.volumeMl(60), afterSecond.lastCountedMl!!, 1e-9)
    }
}
