import Foundation

/// Editable adult beverage-goal estimate. The weight reference includes food;
/// this app assumes 30% comes from food and uses 70% for drinks. That share is
/// a product assumption, not a measured dietary input or medical prescription.
/// Pure logic — no HealthKit types — so it compiles into the macOS test
/// binary. `AppModel` feeds it the latest Apple Health values (or the
/// manually entered ones) and the settings.
nonisolated enum HydrationTarget {
    nonisolated enum Sex: String, Sendable, Equatable, CaseIterable {
        case female
        case male
        case other
    }

    /// Where a body value came from — shown in the Home caption.
    nonisolated enum Source: Sendable, Equatable {
        case health
        case manual
    }

    nonisolated enum Basis: Sendable, Equatable {
        case weight(kg: Double, source: Source)
        case sex(Sex, source: Source)
        case `default`
        case manual
    }

    nonisolated struct TargetResult: Sendable, Equatable {
        let ml: Int
        let basis: Basis
    }

    static let mlPerKg = 35.0
    static let beverageShare = 0.70
    static let estimateExplanation = "A rough adult drink goal: 35 ml/kg including food, with 30% allowed for food. Diet, heat and activity vary. Other drinks count too. Adjust the goal to suit you; follow any prescribed fluid limit."
    static let roundingMl = 50
    static let minMl = 1_500
    static let maxMl = 4_000
    static let defaultMl = 2_000
    static let maleFallbackMl = 1_750
    static let femaleFallbackMl = 1_500
    /// Manual override bounds (Settings stepper).
    static let overrideMinMl = 500
    static let overrideMaxMl = 6_000
    static let overrideStepMl = 50

    /// Estimate from weight and/or sex (no override): weight wins, then sex,
    /// then the default.
    static func compute(weightKg: Double?, sex: Sex?, weightSource: Source = .health, sexSource: Source = .health) -> TargetResult {
        if let weightKg, weightKg.isFinite, weightKg > 0 {
            let raw = weightKg * mlPerKg * beverageShare
            // Clamp before Double → Int conversion: invalid extreme values
            // must not overflow the conversion or the subsequent step multiply.
            let bounded = min(max(raw, Double(minMl)), Double(maxMl))
            let rounded = Int((bounded / Double(roundingMl)).rounded()) * roundingMl
            return TargetResult(ml: rounded, basis: .weight(kg: weightKg, source: weightSource))
        }
        if let sex {
            switch sex {
            case .male: return TargetResult(ml: maleFallbackMl, basis: .sex(sex, source: sexSource))
            case .female: return TargetResult(ml: femaleFallbackMl, basis: .sex(sex, source: sexSource))
            case .other: return TargetResult(ml: defaultMl, basis: .sex(sex, source: sexSource))
            }
        }
        return TargetResult(ml: defaultMl, basis: .default)
    }

    /// Full resolution: a manual override (when `useEstimate` is off and a
    /// value is set) beats the estimate; Apple Health values beat manually
    /// entered body values.
    static func resolve(
        useEstimate: Bool,
        overrideMl: Int?,
        healthWeightKg: Double?,
        healthSex: Sex?,
        manualWeightKg: Double?,
        manualSex: Sex?,
    ) -> TargetResult {
        if !useEstimate, let overrideMl {
            return TargetResult(ml: clampOverride(overrideMl), basis: .manual)
        }
        let weight: (Double, Source)? = healthWeightKg.map { ($0, .health) } ?? manualWeightKg.map { ($0, .manual) }
        let sex: (Sex, Source)? = healthSex.map { ($0, .health) } ?? manualSex.map { ($0, .manual) }
        return compute(
            weightKg: weight?.0,
            sex: sex?.0,
            weightSource: weight?.1 ?? .health,
            sexSource: sex?.1 ?? .health,
        )
    }

    static func clampOverride(_ ml: Int) -> Int {
        let bounded = min(max(ml, overrideMinMl), overrideMaxMl)
        return Int((Double(bounded) / Double(overrideStepMl)).rounded()) * overrideStepMl
    }

    /// Always distinguish an estimated goal from a measured requirement.
    static func caption(_ result: TargetResult) -> String {
        let liters = String(format: "%.2f L", Double(result.ml) / 1000)
        switch result.basis {
        case .weight(let kg, let source):
            let kgText = String(format: kg.rounded() == kg ? "%.0f kg" : "%.1f kg", kg)
            return source == .health
                ? "Estimated drink goal \(liters) · Health weight \(kgText)"
                : "Estimated drink goal \(liters) · weight \(kgText)"
        case .sex(_, let source):
            return source == .health
                ? "Estimated drink goal \(liters) · Apple Health"
                : "Estimated drink goal \(liters) · manual profile"
        case .default:
            return "Drink goal \(liters) · default, adjustable"
        case .manual:
            return "Drink goal \(liters) · set manually"
        }
    }
}
