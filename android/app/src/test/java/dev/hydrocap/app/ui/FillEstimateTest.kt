package dev.hydrocap.app.ui

import dev.hydrocap.app.data.TofLogEntry
import dev.hydrocap.app.domain.BottleProfile
import org.junit.Assert.*
import org.junit.Test

class FillEstimateTest {
    private fun reading(distance:Int=50)=TofLogEntry(1,0,distance,10,0f)
    @Test fun zeroCustomCurveNeverProducesNanGaugeFraction() {
        val estimate=FillEstimate.from(reading(),BottleProfile(BottleProfile.ID_CUSTOM,"Synthetic zero",0,DoubleArray(5)))!!
        assertEquals(0.0,estimate.ml,0.0); assertEquals(0.0,estimate.percent,0.0); assertTrue(estimate.percent.isFinite())
    }
    @Test fun finiteCoefficientsThatOverflowAtMeasuredDistanceAreUnknownNotInfinity() {
        assertNull(FillEstimate.from(reading(),BottleProfile(BottleProfile.ID_CUSTOM,"Synthetic overflow",0,doubleArrayOf(1e308,0.0,0.0,0.0,0.0))))
    }
    @Test fun defaultProfileGaugeRemainsFiniteAndNoReadingPastSensorLimit() {
        val estimate=FillEstimate.from(reading(16),BottleProfile.DEFAULT)!!
        assertTrue(estimate.ml.isFinite()); assertTrue(estimate.percent in 0.0..100.0)
        assertNull(FillEstimate.from(reading(BottleProfile.DEFAULT.tofMaxMm),BottleProfile.DEFAULT))
    }
}
