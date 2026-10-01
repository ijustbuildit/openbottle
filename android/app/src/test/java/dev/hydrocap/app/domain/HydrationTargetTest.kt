package dev.hydrocap.app.domain

import org.junit.Assert.*
import org.junit.Test

/** Synthetic body inputs; calls the production object, not a parallel test implementation. */
class HydrationTargetTest {
    @Test fun weightEstimateAllowsThirtyPercentForFood() {
        val result = HydrationTarget.compute(70.0)
        assertEquals(HydrationTarget.TargetResult(1700, HydrationTarget.Basis.Weight(70.0, HydrationTarget.Source.HEALTH)), result)
        assertEquals(0.70, HydrationTarget.beverageShare, 0.0)
        assertEquals(2450, HydrationTarget.compute(100.0, HydrationTarget.Sex.MALE).ml)
        assertEquals(HydrationTarget.compute(80.0, HydrationTarget.Sex.MALE).ml, HydrationTarget.compute(80.0, HydrationTarget.Sex.FEMALE).ml)
    }

    @Test fun estimatesRespectDocumentedProductBounds() {
        assertEquals(1500, HydrationTarget.compute(30.0).ml)
        assertEquals(4000, HydrationTarget.compute(200.0).ml)
    }

    @Test fun nothingKnownIsAnAdjustableDefault() {
        assertEquals(HydrationTarget.TargetResult(2000, HydrationTarget.Basis.Default), HydrationTarget.compute())
    }

    @Test fun sexFallbackHasProvenance() {
        assertEquals(HydrationTarget.TargetResult(1500, HydrationTarget.Basis.Sex(HydrationTarget.Sex.FEMALE, HydrationTarget.Source.HEALTH)), HydrationTarget.compute(sex = HydrationTarget.Sex.FEMALE))
        assertEquals(1750, HydrationTarget.compute(sex = HydrationTarget.Sex.MALE).ml)
        assertEquals(2000, HydrationTarget.compute(sex = HydrationTarget.Sex.OTHER).ml)
    }

    @Test fun roundsToNearestFifty() {
        for ((kg, expected) in listOf(71.0 to 1750, 72.3 to 1750, 64.0 to 1550, 60.0 to 1500, 72.5 to 1800)) {
            assertEquals(expected, HydrationTarget.compute(kg).ml)
        }
    }

    @Test fun invalidWeightsFallThroughToSexOrDefault() {
        for (kg in listOf(0.0, -5.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertEquals(HydrationTarget.Basis.Default, HydrationTarget.compute(kg).basis)
            assertEquals(1750, HydrationTarget.compute(kg, HydrationTarget.Sex.MALE).ml)
        }
    }

    @Test fun finiteExtremesCannotOverflowConversionOrStepping() {
        val extreme = HydrationTarget.compute(Double.MAX_VALUE)
        assertEquals(4000, extreme.ml)
        assertTrue(HydrationTarget.caption(extreme).isNotEmpty())
        assertEquals(1500, HydrationTarget.compute(Double.MIN_VALUE).ml)
        assertEquals(6000, HydrationTarget.clampOverride(Int.MAX_VALUE))
        assertEquals(500, HydrationTarget.clampOverride(Int.MIN_VALUE))
    }

    @Test fun manualOverrideWinsOnlyWhenEstimateIsOff() {
        assertEquals(HydrationTarget.TargetResult(3000, HydrationTarget.Basis.Manual), HydrationTarget.resolve(false, 3000, 70.0, HydrationTarget.Sex.MALE))
        assertEquals(1700, HydrationTarget.resolve(true, 3000, 70.0, HydrationTarget.Sex.MALE).ml)
        assertEquals(HydrationTarget.Basis.Default, HydrationTarget.resolve(false).basis)
    }

    @Test fun manualOverrideClampsAndRoundsHalfUp() {
        assertEquals(2550, HydrationTarget.clampOverride(2530))
        assertEquals(2550, HydrationTarget.clampOverride(2525))
        assertEquals(2500, HydrationTarget.clampOverride(2524))
        assertEquals(500, HydrationTarget.clampOverride(100))
        assertEquals(6000, HydrationTarget.clampOverride(9000))
    }

    @Test fun healthValuesBeatManualValuesPerField() {
        val health = HydrationTarget.resolve(true, healthWeightKg = 80.0, manualWeightKg = 60.0, manualSex = HydrationTarget.Sex.FEMALE)
        assertEquals(1950, health.ml)
        assertEquals(HydrationTarget.Basis.Weight(80.0, HydrationTarget.Source.HEALTH), health.basis)
        val sex = HydrationTarget.resolve(true, healthSex = HydrationTarget.Sex.MALE, manualSex = HydrationTarget.Sex.FEMALE)
        assertEquals(HydrationTarget.Basis.Sex(HydrationTarget.Sex.MALE, HydrationTarget.Source.HEALTH), sex.basis)
    }

    @Test fun manualValuesBeatNothingAndComplementHealthSex() {
        val manual = HydrationTarget.resolve(true, healthSex = HydrationTarget.Sex.MALE, manualWeightKg = 80.0)
        assertEquals(HydrationTarget.Basis.Weight(80.0, HydrationTarget.Source.MANUAL), manual.basis)
        val fallback = HydrationTarget.resolve(true, manualSex = HydrationTarget.Sex.MALE)
        assertEquals(HydrationTarget.TargetResult(1750, HydrationTarget.Basis.Sex(HydrationTarget.Sex.MALE, HydrationTarget.Source.MANUAL)), fallback)
    }

    @Test fun invalidNonNullHealthWeightMatchesFrozenSourceSelection() {
        // Source selects non-null per field before compute validates; Health reader supplies null for invalid records.
        val result = HydrationTarget.resolve(true, healthWeightKg = Double.NaN, manualWeightKg = 80.0, manualSex = HydrationTarget.Sex.FEMALE)
        assertEquals(HydrationTarget.Basis.Sex(HydrationTarget.Sex.FEMALE, HydrationTarget.Source.MANUAL), result.basis)
    }

    @Test fun captionsDistinguishEstimatedManualAndDefaultWithSources() {
        assertEquals("Estimated drink goal 1.70 L · Health weight 70 kg", HydrationTarget.caption(HydrationTarget.compute(70.0)))
        assertEquals("Estimated drink goal 1.80 L · weight 72.5 kg", HydrationTarget.caption(HydrationTarget.compute(72.5, weightSource = HydrationTarget.Source.MANUAL)))
        assertEquals("Drink goal 2.00 L · default, adjustable", HydrationTarget.caption(HydrationTarget.compute()))
        assertEquals("Drink goal 3.00 L · set manually", HydrationTarget.caption(HydrationTarget.resolve(false, 3000)))
        assertEquals("Estimated drink goal 1.75 L · Health Connect", HydrationTarget.caption(HydrationTarget.compute(sex = HydrationTarget.Sex.MALE)))
        assertTrue(HydrationTarget.estimateExplanation.contains("prescribed fluid limit"))
    }
}
