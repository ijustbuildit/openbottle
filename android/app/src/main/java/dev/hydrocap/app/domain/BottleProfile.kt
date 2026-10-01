package dev.hydrocap.app.domain

/**
 * Volume-conversion parameters for one bottle body: a 4th-degree polynomial
 * `V(d) = c0·d⁴ + c1·d³ + c2·d² + c3·d + c4` over the ToF distance d in mm,
 * plus the thresholds of the fill/intake state machine (protocol doc §5).
 *
 * The coefficient sets are hypotheses until calibrated on the real bottle; the
 * user can override them with a custom profile.
 */
data class BottleProfile(
    val id: String,
    val label: String,
    val nominalMl: Int,
    val coefficients: DoubleArray,
    val minVolumeMl: Double = 0.0,
    /** Upper clamp (brim volume); null = unclamped like the community curves. */
    val maxVolumeMl: Double? = null,
    val tofMaxMm: Int = 250,
    val drinkThresholdMl: Double = 15.0,
    val fillThresholdMl: Double = 100.0,
) {
    init {
        require(coefficients.size == 5) { "polynomial needs exactly 5 coefficients (c0..c4)" }
    }

    /** Estimated volume in ml for a raw ToF distance, clamped at [minVolumeMl]. */
    fun volumeMl(distanceMm: Int): Double {
        val d = distanceMm.toDouble()
        val v = ((((coefficients[0] * d) + coefficients[1]) * d + coefficients[2]) * d + coefficients[3]) * d + coefficients[4]
        val lower = maxOf(v, minVolumeMl)
        return maxVolumeMl?.let { minOf(lower, it) } ?: lower
    }

    /** Practical "full" reference for percentages: the brim clamp if known, else the volume at distance 0. */
    val fullVolumeMl: Double get() = maxVolumeMl ?: volumeMl(0)

    override fun equals(other: Any?): Boolean =
        other is BottleProfile && other.id == id && other.coefficients.contentEquals(coefficients) &&
            other.minVolumeMl == minVolumeMl && other.maxVolumeMl == maxVolumeMl && other.tofMaxMm == tofMaxMm &&
            other.drinkThresholdMl == drinkThresholdMl && other.fillThresholdMl == fillThresholdMl

    override fun hashCode(): Int = id.hashCode() * 31 + coefficients.contentHashCode()

    companion object {
        const val ID_680_CAL = "body_680_nofilter_cal1"
        const val ID_680 = "body_680"
        const val ID_1000 = "body_1000"
        const val ID_CUSTOM = "custom"

        /**
         * Calibrated on a BRITA LARQ iQ 680 ml body, straw in, no filter
         * (11 fill levels 0–717 ml, 3–5 cap readings each, weighted
         * cubic fit; residual RMSE 9.5 ml, leave-one-out 15.5 ml). Brim-full is
         * ~717 ml at 16 mm; empty reads 207 mm. Readings beyond 212 mm are
         * below the straw tip / sensor floor and count as empty; the curve is
         * clamped at 0 and at the brim volume.
         */
        val BODY_680_NO_FILTER_CAL = BottleProfile(
            id = ID_680_CAL,
            label = "680 ml body, no filter (calibrated)",
            nominalMl = 680,
            coefficients = doubleArrayOf(0.0, -6.208893338e-5, 0.02199185096, -5.70134644, 791.0281811),
            maxVolumeMl = 720.0,
            tofMaxMm = 230,
        )

        val BODY_680 = BottleProfile(
            id = ID_680,
            label = "680 ml body",
            nominalMl = 680,
            coefficients = doubleArrayOf(-1.19e-6, 5.0264e-4, -0.06522747, -0.81937241, 715.15212206),
        )

        val BODY_1000 = BottleProfile(
            id = ID_1000,
            label = "1000 ml body",
            nominalMl = 1000,
            coefficients = doubleArrayOf(-1.1e-6, 5.5211e-4, -0.08516349, -0.2839113, 1026.71212239),
        )

        /** Hardware session 1: the cap's bottleSizeInMilliliter is not authoritative; default to the calibrated small body. */
        val DEFAULT: BottleProfile = BODY_680_NO_FILTER_CAL

        val BUILT_IN: List<BottleProfile> = listOf(BODY_680_NO_FILTER_CAL, BODY_680, BODY_1000)

        fun builtIn(id: String): BottleProfile? = BUILT_IN.firstOrNull { it.id == id }

        /** Maps the cap-reported bottle size to a built-in profile (informational only). */
        fun forCapReportedSize(bottleSizeMl: Int): BottleProfile? = BUILT_IN.firstOrNull { it.nominalMl == bottleSizeMl }
    }
}
