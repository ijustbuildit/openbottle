import Foundation

/// Volume-conversion parameters for one bottle body: a 4th-degree polynomial
/// `V(d) = c0·d⁴ + c1·d³ + c2·d² + c3·d + c4` over the ToF distance d in mm,
/// plus the thresholds of the fill/intake state machine (protocol doc §5).
///
/// The coefficient sets are hypotheses until calibrated on the real bottle; the
/// user can override them with a custom profile.
nonisolated struct BottleProfile: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let nominalMl: Int
    /// Exactly five coefficients, c0..c4.
    let coefficients: [Double]
    let minVolumeMl: Double
    /// Upper clamp (brim volume); nil = unclamped like the community curves.
    let maxVolumeMl: Double?
    let tofMaxMm: Int
    let drinkThresholdMl: Double
    let fillThresholdMl: Double

    init(
        id: String,
        label: String,
        nominalMl: Int,
        coefficients: [Double],
        minVolumeMl: Double = 0.0,
        maxVolumeMl: Double? = nil,
        tofMaxMm: Int = 250,
        drinkThresholdMl: Double = 15.0,
        fillThresholdMl: Double = 100.0,
    ) {
        precondition(coefficients.count == 5, "polynomial needs exactly 5 coefficients (c0..c4)")
        self.id = id
        self.label = label
        self.nominalMl = nominalMl
        self.coefficients = coefficients
        self.minVolumeMl = minVolumeMl
        self.maxVolumeMl = maxVolumeMl
        self.tofMaxMm = tofMaxMm
        self.drinkThresholdMl = drinkThresholdMl
        self.fillThresholdMl = fillThresholdMl
    }

    /// Estimated volume in ml for a raw ToF distance, clamped at `minVolumeMl`
    /// and (when set) at `maxVolumeMl`.
    func volumeMl(_ distanceMm: Int) -> Double {
        let d = Double(distanceMm)
        var v = coefficients[0]
        v = v * d + coefficients[1]
        v = v * d + coefficients[2]
        v = v * d + coefficients[3]
        v = v * d + coefficients[4]
        let lower = max(v, minVolumeMl)
        if let maxVolumeMl { return min(lower, maxVolumeMl) }
        return lower
    }

    /// Practical "full" reference for percentages: the brim clamp if known,
    /// else the volume at distance 0.
    var fullVolumeMl: Double { maxVolumeMl ?? volumeMl(0) }

    // MARK: - Built-ins

    static let id680Cal = "body_680_nofilter_cal1"
    static let id680 = "body_680"
    static let id1000 = "body_1000"
    static let idCustom = "custom"

    /// Calibrated on a BRITA LARQ iQ 680 ml body, straw in, no filter
    /// (11 fill levels 0–717 ml, 3–5 cap readings each, weighted
    /// cubic fit; residual RMSE 9.5 ml, leave-one-out 15.5 ml). Brim-full is
    /// ~717 ml at 16 mm; empty reads 207 mm. Readings beyond the straw tip /
    /// sensor floor count as empty; the curve is clamped at 0 and at the brim.
    static let body680NoFilterCal = BottleProfile(
        id: id680Cal,
        label: "680 ml body, no filter (calibrated)",
        nominalMl: 680,
        coefficients: [0.0, -6.208893338e-5, 0.02199185096, -5.70134644, 791.0281811],
        maxVolumeMl: 720.0,
        tofMaxMm: 230,
    )

    static let body680 = BottleProfile(
        id: id680,
        label: "680 ml body",
        nominalMl: 680,
        coefficients: [-1.19e-6, 5.0264e-4, -0.06522747, -0.81937241, 715.15212206],
    )

    static let body1000 = BottleProfile(
        id: id1000,
        label: "1000 ml body",
        nominalMl: 1000,
        coefficients: [-1.1e-6, 5.5211e-4, -0.08516349, -0.2839113, 1026.71212239],
    )

    /// Hardware session 1: the cap's `bottleSizeInMilliliter` is not
    /// authoritative; default to the calibrated small body.
    static let `default`: BottleProfile = body680NoFilterCal

    static let builtIn: [BottleProfile] = [body680NoFilterCal, body680, body1000]

    static func builtIn(id: String) -> BottleProfile? {
        builtIn.first { $0.id == id }
    }

    /// Maps the cap-reported bottle size to a built-in profile (informational
    /// only — never used to switch the active profile).
    static func forCapReportedSize(_ bottleSizeMl: Int) -> BottleProfile? {
        builtIn.first { $0.nominalMl == bottleSizeMl }
    }
}
