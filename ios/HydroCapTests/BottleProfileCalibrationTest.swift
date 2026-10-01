import Foundation
import Testing

@testable import HydroCap

/// Pins the calibrated 680 ml / no-filter curve to the measuring-cup session of
/// 2026-09-29 (tools/captures/calibration-2026-09-29-1702.csv). Tolerances are
/// the fit residuals, not the sensor noise.
@Suite("Bottle profile calibration")
struct BottleProfileCalibrationTest {
    private let profile = BottleProfile.body680NoFilterCal

    @Test func calibrationPointsAreReproducedWithin20Ml() {
        let points: [(mm: Int, ml: Double)] = [
            (207, 0.0), (183, 100.0), (161, 200.0), (139, 250.0), (121, 300.0), (107, 350.0),
            (93, 400.0), (77, 450.0), (68, 500.0), (37, 600.0), (16, 717.0),
        ]
        for point in points {
            let got = profile.volumeMl(point.mm)
            #expect(abs(got - point.ml) <= 20.0, "\(point.mm) mm → \(got) ml, expected ≈ \(point.ml)")
        }
    }

    @Test func curveIsMonotoneOverTheSensorRangeAndClampedAtBothEnds() {
        var last = Double.greatestFiniteMagnitude
        for mm in 0...230 {
            let value = profile.volumeMl(mm)
            #expect(value <= last, "not monotone at \(mm) mm")
            last = value
        }
        #expect(profile.volumeMl(0) == 720.0)
        #expect(profile.volumeMl(215) == 0.0)
        #expect(profile.fullVolumeMl == 720.0)
    }

    @Test func calibratedProfileIsTheDefaultAndBuiltIn() {
        #expect(BottleProfile.default == profile)
        #expect(BottleProfile.builtIn(id: BottleProfile.id680Cal) == profile)
        #expect(BottleProfile.builtIn.count == 3)
        #expect(BottleProfile.forCapReportedSize(1000) == BottleProfile.body1000)
        #expect(BottleProfile.forCapReportedSize(680) == BottleProfile.body680NoFilterCal)
        #expect(BottleProfile.forCapReportedSize(600) == nil)
    }
}
