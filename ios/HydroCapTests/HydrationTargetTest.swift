import Foundation
import Testing
@testable import HydroCap

@Suite("Hydration target")
struct HydrationTargetTest {
    @Test func weightReferenceAllowsForFoodInsteadOfCountingItAsDrinks() {
        let result = HydrationTarget.compute(weightKg: 70, sex: nil)
        #expect(result.ml == 1_700)
        #expect(result.basis == .weight(kg: 70, source: .health))
        #expect(HydrationTarget.beverageShare == 0.70)
        #expect(HydrationTarget.compute(weightKg: 100, sex: .male).ml == 2_450)
    }
    @Test func lowAndHighEstimatesUseDocumentedProductBounds() {
        #expect(HydrationTarget.compute(weightKg: 30, sex: nil).ml == 1_500)
        #expect(HydrationTarget.compute(weightKg: 200, sex: nil).ml == 4_000)
    }
    @Test func nothingKnownIsAnAdjustableDefault() {
        let result = HydrationTarget.compute(weightKg: nil, sex: nil)
        #expect(result.ml == 2_000)
        #expect(result.basis == .default)
    }
    @Test func sexFallbacksAlsoAllowForFood() {
        let female = HydrationTarget.compute(weightKg: nil, sex: .female)
        #expect(female.ml == 1_500)
        #expect(female.basis == .sex(.female, source: .health))
        #expect(HydrationTarget.compute(weightKg: nil, sex: .male).ml == 1_750)
        #expect(HydrationTarget.compute(weightKg: nil, sex: .other).ml == 2_000)
    }
    @Test func roundsToFiftyMillilitres() {
        #expect(HydrationTarget.compute(weightKg: 71, sex: nil).ml == 1_750)
        #expect(HydrationTarget.compute(weightKg: 72.3, sex: nil).ml == 1_750)
        #expect(HydrationTarget.compute(weightKg: 64, sex: nil).ml == 1_550)
        #expect(HydrationTarget.compute(weightKg: 60, sex: nil).ml == 1_500)
    }
    @Test func invalidWeightFallsThrough() {
        #expect(HydrationTarget.compute(weightKg: 0, sex: .male).ml == 1_750)
        #expect(HydrationTarget.compute(weightKg: -5, sex: nil).basis == .default)
        #expect(HydrationTarget.compute(weightKg: .nan, sex: nil).basis == .default)
        #expect(HydrationTarget.compute(weightKg: .infinity, sex: nil).basis == .default)
    }
    @Test func extremeInputsCannotCrashNumericConversion() {
        let extreme = HydrationTarget.compute(weightKg: .greatestFiniteMagnitude, sex: nil)
        #expect(extreme.ml == 4_000)
        #expect(!HydrationTarget.caption(extreme).isEmpty)
        #expect(HydrationTarget.clampOverride(Int.max) == 6_000)
        #expect(HydrationTarget.clampOverride(Int.min) == 500)
    }
    @Test func manualOverrideWinsOnlyWhenEstimateIsOff() {
        let overridden = HydrationTarget.resolve(useEstimate: false, overrideMl: 3_000, healthWeightKg: 70, healthSex: .male, manualWeightKg: nil, manualSex: nil)
        #expect(overridden == HydrationTarget.TargetResult(ml: 3_000, basis: .manual))
        let estimated = HydrationTarget.resolve(useEstimate: true, overrideMl: 3_000, healthWeightKg: 70, healthSex: .male, manualWeightKg: nil, manualSex: nil)
        #expect(estimated.ml == 1_700)
        #expect(HydrationTarget.resolve(useEstimate: false, overrideMl: nil, healthWeightKg: nil, healthSex: nil, manualWeightKg: nil, manualSex: nil).basis == .default)
    }
    @Test func overrideIsSteppedAndClamped() {
        #expect(HydrationTarget.clampOverride(2_530) == 2_550)
        #expect(HydrationTarget.clampOverride(100) == 500)
        #expect(HydrationTarget.clampOverride(9_000) == 6_000)
    }
    @Test func healthValuesBeatManualValuesAndManualValuesBeatNothing() {
        let health = HydrationTarget.resolve(useEstimate: true, overrideMl: nil, healthWeightKg: 80, healthSex: nil, manualWeightKg: 60, manualSex: .female)
        #expect(health.ml == 1_950)
        #expect(health.basis == .weight(kg: 80, source: .health))
        let manual = HydrationTarget.resolve(useEstimate: true, overrideMl: nil, healthWeightKg: nil, healthSex: nil, manualWeightKg: 60, manualSex: .female)
        #expect(manual.ml == 1_500)
        #expect(manual.basis == .weight(kg: 60, source: .manual))
        let fallback = HydrationTarget.resolve(useEstimate: true, overrideMl: nil, healthWeightKg: nil, healthSex: nil, manualWeightKg: nil, manualSex: .male)
        #expect(fallback.ml == 1_750)
        #expect(fallback.basis == .sex(.male, source: .manual))
    }
    @Test func manualWeightComplementsHealthSex() {
        let result = HydrationTarget.resolve(useEstimate: true, overrideMl: nil, healthWeightKg: nil, healthSex: .male, manualWeightKg: 80, manualSex: nil)
        #expect(result.ml == 1_950)
        #expect(result.basis == .weight(kg: 80, source: .manual))
    }
    @Test func captionsStateEstimateAndSource() {
        #expect(HydrationTarget.caption(HydrationTarget.compute(weightKg: 70, sex: nil)) == "Estimated drink goal 1.70 L · Health weight 70 kg")
        #expect(HydrationTarget.caption(HydrationTarget.compute(weightKg: 72.5, sex: nil, weightSource: .manual)) == "Estimated drink goal 1.80 L · weight 72.5 kg")
        #expect(HydrationTarget.caption(HydrationTarget.compute(weightKg: nil, sex: nil)) == "Drink goal 2.00 L · default, adjustable")
        #expect(HydrationTarget.caption(HydrationTarget.TargetResult(ml: 3_000, basis: .manual)) == "Drink goal 3.00 L · set manually")
        #expect(HydrationTarget.caption(HydrationTarget.compute(weightKg: nil, sex: .male)) == "Estimated drink goal 1.75 L · Apple Health")
    }
}
