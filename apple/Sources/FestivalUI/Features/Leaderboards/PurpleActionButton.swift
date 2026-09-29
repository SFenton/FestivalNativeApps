import SwiftUI
import FestivalDesign

// MARK: - Purple action surface

/// The one purple "View full leaderboard" / "View all …" button look used everywhere
/// (operator batch 6.29): full-width, 44 pt, white semibold text on accent-purple
/// interactive Liquid Glass, and an opaque purple fill under Reduce Transparency, the
/// app's contrast/transparency overrides, or before iOS/macOS 26 (white stays ≥ 4.5:1).
struct PurpleActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .modifier(PurpleActionSurface())
            .contentShape(RoundedRectangle(cornerRadius: PurpleActionSurface.cornerRadius, style: .continuous))
    }
}

/// Accent-purple glass for ``PurpleActionLabel``.
struct PurpleActionSurface: ViewModifier {
    static let cornerRadius: CGFloat = 12
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.accentPurple, in: shape)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(BrandTokens.accentPurple).interactive(), in: shape)
        } else {
            content.background(BrandTokens.accentPurple, in: shape)
        }
    }
}
