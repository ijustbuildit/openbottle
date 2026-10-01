package dev.hydrocap.app.ui

import kotlin.math.sqrt

/** Monotonic cubic geometry for the approved smooth line/area style.
 * Apply separately to each nonempty series; never interpolate across gaps. */
object MonotoneCurve {
    data class Point(val x: Double, val y: Double)
    data class Segment(val start: Point, val control1: Point, val control2: Point, val end: Point)

    fun segments(points: List<Point>): List<Segment> {
        if (points.size < 2) return emptyList()
        require(points.all { it.x.isFinite() && it.y.isFinite() })
        val h = points.zipWithNext { a, b -> b.x-a.x }
        require(h.all { it > 0 })
        val delta = points.zipWithNext().mapIndexed { i, (a,b) -> (b.y-a.y)/h[i] }
        val slope = DoubleArray(points.size)
        slope[0]=delta.first(); slope[slope.lastIndex]=delta.last()
        for (i in 1 until points.lastIndex) {
            val before=delta[i-1]; val after=delta[i]
            slope[i] = if (before == 0.0 || after == 0.0 || (before>0)!=(after>0)) 0.0
                else (h[i-1]+h[i])/(h[i-1]/before+h[i]/after)
        }
        delta.forEachIndexed { i,d ->
            if (d==0.0) { slope[i]=0.0; slope[i+1]=0.0 }
            else {
                val alpha=slope[i]/d; val beta=slope[i+1]/d
                val norm=alpha*alpha+beta*beta
                if (norm>9) { val scale=3/sqrt(norm); slope[i]=scale*alpha*d; slope[i+1]=scale*beta*d }
            }
        }
        return points.zipWithNext().mapIndexed { i,(a,b) ->
            val third=h[i]/3
            Segment(a,Point(a.x+third,a.y+slope[i]*third),Point(b.x-third,b.y-slope[i+1]*third),b)
        }
    }
}
