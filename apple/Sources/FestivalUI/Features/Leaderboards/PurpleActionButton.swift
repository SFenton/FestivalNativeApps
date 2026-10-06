import SwiftUI
import FestivalDesign

// MARK: - Purple action link

/// The shared "View All …" push below a card of preview rows (view-all-cta R1–R4):
/// a `NavigationLink` drawing ``PurpleActionLabel`` with the row button style, so
/// consumers set only the label, destination, spoken name and test ID (#321).
struct PurpleActionLink: View {
    /// Visible Title Case label, e.g. "View All" or "View All Rivals".
    let title: String
    /// Full list to push.
    let route: AppRoute
    /// Per-card `…view-all` accessibility identifier.
    let identifier: String
    /// Card or list the button opens, spoken after the label ("View All, Closest
    /// Battles"; WCAG 2.5.3 label in name). `nil` speaks the label alone.
    var card: String? = nil

    var body: some View {
        NavigationLink(value: route) {
            PurpleActionLabel(title: title)
        }
        .festivalRowButtonStyle()
        .accessibilityLabel(card.map { "\(title), \($0)" } ?? title)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Purple action surface

/// The one purple "View Full Leaderboard" / "View All …" button look used everywhere
/// (operator batch 6.29): full-width, 44 pt, white semibold text on the accent-purple
/// material card (issue #291), and an opaque purple fill under Reduce Transparency, the
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

/// Accent-purple material card for ``PurpleActionLabel``.
///
/// The shared card's `ultraThinMaterial` and rim (``FestivalCardModifier``) under an
/// accent-purple tint instead of tinted interactive Liquid Glass (HIG Materials: "Use
/// Liquid Glass effects sparingly on custom controls"). Press feedback comes from the
/// enclosing button's style (`.plain` dims the label while pressed).
struct PurpleActionSurface: ViewModifier {
    static let cornerRadius: CGFloat = 12
    /// Accent purple over the dark material: white text stays above 4.5:1 even if the
    /// material passed a pure white backdrop through (about 4.8:1).
    static let tint = BrandTokens.accentPurple.opacity(0.9)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.accentPurple, in: shape)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(Self.tint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(RowCardStyle.rim, lineWidth: 1))
        } else {
            content.background(BrandTokens.accentPurple, in: shape)
        }
    }
}
