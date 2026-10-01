package dev.hydrocap.app.ui

import org.junit.Assert.*
import org.junit.Test

class MonotoneCurveTest {
    private fun sample(s: MonotoneCurve.Segment,t: Double): Double {
        val one=1-t
        return one*one*one*s.start.y+3*one*one*t*s.control1.y+3*one*t*t*s.control2.y+t*t*t*s.end.y
    }
    @Test fun peaksValleysAndUnequalDistancesNeverOvershootAdjacentMeasuredValues() {
        val points=listOf(MonotoneCurve.Point(0.0,300.0),MonotoneCurve.Point(1.0,900.0),MonotoneCurve.Point(3.0,100.0),MonotoneCurve.Point(4.0,100.0),MonotoneCurve.Point(7.0,700.0))
        val segments=MonotoneCurve.segments(points)
        assertEquals(points.size-1,segments.size)
        segments.forEach { s ->
            assertEquals(s.start.y,sample(s,0.0),0.000001); assertEquals(s.end.y,sample(s,1.0),0.000001)
            for (step in 0..100) { val y=sample(s,step/100.0); assertTrue(y>=minOf(s.start.y,s.end.y)-0.000001 && y<=maxOf(s.start.y,s.end.y)+0.000001) }
        }
    }
    @Test fun singletonAndGapSeriesDoNotInventConnections() {
        assertTrue(MonotoneCurve.segments(emptyList()).isEmpty())
        assertTrue(MonotoneCurve.segments(listOf(MonotoneCurve.Point(1.0,200.0))).isEmpty())
    }
    @Test fun twoPointsKeepLinearInterpolation() {
        val s=MonotoneCurve.segments(listOf(MonotoneCurve.Point(0.0,100.0),MonotoneCurve.Point(3.0,700.0))).single()
        assertEquals(400.0,sample(s,.5),0.000001)
    }
}
