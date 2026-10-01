import SwiftUI

/// Design tokens for the iOS 26 Liquid Glass redesign.
///
/// Rules (see ios/README.md "Design"): content sits on plain system
/// backgrounds in plain rounded cards; glass is used only for the floating
/// control layer (tab bar, toolbar, the primary floating action, segmented
/// selectors, chips). Never glass on large content cards.
enum HydroCapTheme {
    /// Light, clear blue (≈ #3D9EFA); applied with `.tint` at the root.
    static let accent = Color(red: 0.24, green: 0.62, blue: 0.98)
    /// Lighter end of the water gradient.
    static let accentLight = Color(red: 0.45, green: 0.78, blue: 1.0)

    static let cardCornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let screenPadding: CGFloat = 16

    /// Bottom-to-top water gradient used for fill visuals and progress bars.
    static var waterGradient: LinearGradient {
        LinearGradient(colors: [accent, accentLight], startPoint: .bottom, endPoint: .top)
    }

    /// Left-to-right variant for horizontal progress bars.
    static var waterGradientHorizontal: LinearGradient {
        LinearGradient(colors: [accent, accentLight], startPoint: .leading, endPoint: .trailing)
    }

    static func batteryColor(for tier: AppModel.BatteryTier?) -> Color {
        switch tier {
        case .ok: accent
        case .low: .orange
        case .critical: .red
        case nil: Color(.systemGray3)
        }
    }

    static func color(for ring: RingColor) -> Color {
        Color(red: Double(ring.red), green: Double(ring.green), blue: Double(ring.blue))
    }
}

/// Plain content card: rounded rectangle, secondary grouped fill, no border.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(HydroCapTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: HydroCapTheme.cardCornerRadius, style: .continuous),
            )
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

/// Small uppercase-free section caption above a card ("Today", "Bottle").
struct CardTitle: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HydroCapTheme.accent)
            }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// Number formatting shared by the cards.
enum HydroCapFormat {
    static func ml(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func liters(_ value: Double) -> String {
        String(format: "%.1f L", value / 1000)
    }

    /// Two decimals for targets ("2.45 L").
    static func litersPrecise(_ value: Double) -> String {
        String(format: "%.2f L", value / 1000)
    }

    static func time(_ epochSeconds: Int64) -> String {
        AppModel.timeString(Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    static func timeMs(_ epochMs: Int64) -> String {
        AppModel.timeString(Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
    }
}
