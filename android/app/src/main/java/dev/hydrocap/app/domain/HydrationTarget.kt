package dev.hydrocap.app.domain

import java.util.Locale
import kotlin.math.floor

/** Editable adult beverage estimate, not a measured need or a medical prescription. */
object HydrationTarget {
    enum class Sex { FEMALE, MALE, OTHER }
    enum class Source { HEALTH, MANUAL }

    sealed interface Basis {
        data class Weight(val kg: Double, val source: Source) : Basis
        data class Sex(val sex: HydrationTarget.Sex, val source: Source) : Basis
        data object Default : Basis
        data object Manual : Basis
    }

    data class TargetResult(val ml: Int, val basis: Basis)

    const val mlPerKg = 35.0
    const val beverageShare = 0.70
    const val estimateExplanation = "A rough adult drink goal: 35 ml/kg including food, with 30% allowed for food. Diet, heat and activity vary. Other drinks count too. Adjust the goal to suit you; follow any prescribed fluid limit."
    const val roundingMl = 50
    const val minMl = 1_500
    const val maxMl = 4_000
    const val defaultMl = 2_000
    const val maleFallbackMl = 1_750
    const val femaleFallbackMl = 1_500
    const val overrideMinMl = 500
    const val overrideMaxMl = 6_000
    const val overrideStepMl = 50

    fun compute(
        weightKg: Double? = null,
        sex: Sex? = null,
        weightSource: Source = Source.HEALTH,
        sexSource: Source = Source.HEALTH,
    ): TargetResult {
        if (weightKg != null && weightKg.isFinite() && weightKg > 0) {
            // Bound before conversion: even a finite weight can overflow the multiplication.
            val bounded = (weightKg * mlPerKg * beverageShare).coerceIn(minMl.toDouble(), maxMl.toDouble())
            val rounded = floor(bounded / roundingMl + 0.5).toInt() * roundingMl
            return TargetResult(rounded, Basis.Weight(weightKg, weightSource))
        }
        if (sex != null) {
            val ml = when (sex) {
                Sex.MALE -> maleFallbackMl
                Sex.FEMALE -> femaleFallbackMl
                Sex.OTHER -> defaultMl
            }
            return TargetResult(ml, Basis.Sex(sex, sexSource))
        }
        return TargetResult(defaultMl, Basis.Default)
    }

    fun resolve(
        useEstimate: Boolean,
        overrideMl: Int? = null,
        healthWeightKg: Double? = null,
        healthSex: Sex? = null,
        manualWeightKg: Double? = null,
        manualSex: Sex? = null,
    ): TargetResult {
        if (!useEstimate && overrideMl != null) return TargetResult(clampOverride(overrideMl), Basis.Manual)
        return compute(
            weightKg = healthWeightKg ?: manualWeightKg,
            sex = healthSex ?: manualSex,
            weightSource = if (healthWeightKg != null) Source.HEALTH else Source.MANUAL,
            sexSource = if (healthSex != null) Source.HEALTH else Source.MANUAL,
        )
    }

    fun clampOverride(ml: Int): Int =
        floor(ml.coerceIn(overrideMinMl, overrideMaxMl).toDouble() / overrideStepMl + 0.5).toInt() * overrideStepMl

    fun caption(result: TargetResult): String {
        val liters = String.format(Locale.ROOT, "%.2f L", result.ml / 1000.0)
        return when (val basis = result.basis) {
            is Basis.Weight -> {
                val kgText = String.format(Locale.ROOT, if (floor(basis.kg) == basis.kg) "%.0f kg" else "%.1f kg", basis.kg)
                if (basis.source == Source.HEALTH) "Estimated drink goal $liters · Health weight $kgText"
                else "Estimated drink goal $liters · weight $kgText"
            }
            is Basis.Sex -> if (basis.source == Source.HEALTH) "Estimated drink goal $liters · Health Connect"
                else "Estimated drink goal $liters · manual profile"
            Basis.Default -> "Drink goal $liters · default, adjustable"
            Basis.Manual -> "Drink goal $liters · set manually"
        }
    }
}
