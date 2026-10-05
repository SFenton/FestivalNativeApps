import SwiftUI
import FestivalDesign

/// Readable accent text on the app's dark surfaces.
///
/// `BrandTokens.accentBlue` is a fill and tint colour; as text on the row and tile cards
/// it rendered 3.8–4.2:1 on iPad (leaderboard ratings at 17 pt semibold, stat values),
/// below WCAG AA 4.5:1 for text that is not bold or 18 pt and up (HIG Accessibility
/// contrast table). This lighter blue of the same hue reads about 7:1 on those cards.
enum AccentText {
    /// Lighter accent blue for values and ratings drawn as text on dark surfaces.
    static let blue = Color(.sRGB, red: 0.38, green: 0.64, blue: 1.0, opacity: 1)
}

extension AccentText {
    /// Darker accent blue for the fill of a prominent button with a white label: the brand
    /// `accentBlue` fill measured 3.86:1 behind white 17 pt text ("Start New Mix", iPad
    /// audit 2026-10-05), below WCAG AA 4.5:1 (HIG Accessibility contrast table). This
    /// same-hue blue gives about 5.2:1.
    static let prominentFill = Color(.sRGB, red: 31.0 / 255, green: 108.0 / 255, blue: 203.0 / 255, opacity: 1)
}

extension View {
    /// A bordered prominent button on the readable accent fill (``AccentText/prominentFill``).
    /// Under Increase Contrast the app's root tint (primary text) is kept.
    ///
    /// - Returns: The styled button.
    func festivalProminentButton() -> some View {
        modifier(FestivalProminentButton())
    }
}

/// Implementation of ``SwiftUI/View/festivalProminentButton()``.
private struct FestivalProminentButton: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    func body(content: Content) -> some View {
        if contrast == .increased || moreContrast {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.borderedProminent).tint(AccentText.prominentFill)
        }
    }
}
