import SwiftUI

/// Bottle silhouette (neck, shoulder, straight body, rounded base), filled
/// from the bottom by `BottleFillView`.
nonisolated struct BottleShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let neckWidth = width * 0.46
        let neckHeight = height * 0.16
        let shoulderHeight = height * 0.12
        let corner = min(width, height) * 0.14
        let neckCorner = neckWidth * 0.22
        let neckLeft = rect.midX - neckWidth / 2
        let neckRight = rect.midX + neckWidth / 2
        let shoulderTop = rect.minY + neckHeight
        let bodyTop = shoulderTop + shoulderHeight

        path.move(to: CGPoint(x: neckLeft + neckCorner, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight - neckCorner, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: neckRight, y: rect.minY), tangent2End: CGPoint(x: neckRight, y: rect.minY + neckCorner), radius: neckCorner)
        path.addLine(to: CGPoint(x: neckRight, y: shoulderTop))
        // Shoulder: curve out to the body.
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bodyTop), control: CGPoint(x: rect.maxX, y: shoulderTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - corner, y: rect.maxY), radius: corner)
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - corner), radius: corner)
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: neckLeft, y: shoulderTop), control: CGPoint(x: rect.minX, y: shoulderTop))
        path.addLine(to: CGPoint(x: neckLeft, y: rect.minY + neckCorner))
        path.addArc(tangent1End: CGPoint(x: neckLeft, y: rect.minY), tangent2End: CGPoint(x: neckLeft + neckCorner, y: rect.minY), radius: neckCorner)
        path.closeSubpath()
        return path
    }
}

/// Bottle silhouette filled from the bottom with the water gradient.
/// `fraction` is 0…1; nil renders the empty outline (unknown value).
struct BottleFillView: View {
    let fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let level = min(max(fraction ?? 0, 0), 1)
            ZStack(alignment: .bottom) {
                BottleShape()
                    .fill(Color(.tertiarySystemFill))
                // Full-size container with the water pinned to the bottom, so
                // the mask (the whole silhouette) lines up with the outline.
                Rectangle()
                    .fill(HydroCapTheme.waterGradient)
                    .frame(height: proxy.size.height * level)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .mask { BottleShape() }
                    .animation(reduceMotion ? nil : .snappy, value: level)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ring gauge (`Circle().trim`) with a centred label; `fraction` nil = empty
/// track only.
struct RingGauge<Label: View>: View {
    let fraction: Double?
    let color: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder let label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level = min(max(fraction ?? 0, 0), 1)
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: level)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy, value: level)
            label()
        }
        .accessibilityHidden(true)
    }
}

/// Thin horizontal water progress bar (Home hero card).
struct WaterProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let level = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(HydroCapTheme.waterGradientHorizontal)
                    .frame(width: max(proxy.size.width * level, level > 0 ? proxy.size.height : 0))
                    .animation(reduceMotion ? nil : .snappy, value: level)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Signal strength as four bars from an RSSI value (scan list).
struct RssiBars: View {
    let rssi: Int

    private var activeBars: Int {
        switch rssi {
        case ..<(-90): 1
        case ..<(-78): 2
        case ..<(-65): 3
        default: 4
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index < activeBars ? HydroCapTheme.accent : Color(.tertiarySystemFill))
                    .frame(width: 4, height: 6 + CGFloat(index) * 4)
            }
        }
        .accessibilityLabel("Signal \(activeBars) of 4")
    }
}
