package dev.hydrocap.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the calibrated 680 ml / no-filter curve to the measuring-cup session of
 * 2026-09-29 (tools/captures/calibration-2026-09-29-1702.csv). Tolerances are
 * the fit residuals, not the sensor noise.
 */
class BottleProfileCalibrationTest {
    private val p = BottleProfile.BODY_680_NO_FILTER_CAL

    @Test
    fun `calibration points are reproduced within 20 ml`() {
        val points = listOf(207 to 0.0, 183 to 100.0, 161 to 200.0, 139 to 250.0, 121 to 300.0, 107 to 350.0, 93 to 400.0, 77 to 450.0, 68 to 500.0, 37 to 600.0, 16 to 717.0)
        for ((mm, ml) in points) {
            val got = p.volumeMl(mm)
            assertTrue("$mm mm → $got ml, expected ≈ $ml", kotlin.math.abs(got - ml) <= 20.0)
        }
    }

    @Test
    fun `curve is monotone over the sensor range and clamped at both ends`() {
        var last = Double.MAX_VALUE
        for (mm in 0..230) {
            val v = p.volumeMl(mm)
            assertTrue("not monotone at $mm mm", v <= last)
            last = v
        }
        assertEquals(720.0, p.volumeMl(0), 0.0)
        assertEquals(0.0, p.volumeMl(215), 0.0)
        assertEquals(720.0, p.fullVolumeMl, 0.0)
    }

    @Test
    fun `calibrated profile is the default and built in`() {
        assertEquals(p, BottleProfile.DEFAULT)
        assertEquals(p, BottleProfile.builtIn(BottleProfile.ID_680_CAL))
    }
}
