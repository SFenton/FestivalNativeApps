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
    static let blue = Color(.sRGB, red: blueRGB.red, green: blueRGB.green, blue: blueRGB.blue, opacity: 1)

    /// ``blue`` as components, shared with the UIKit port's `UKAccentText`.
    static let blueRGB = (red: 0.38, green: 0.64, blue: 1.0)
}

extension AccentText {
    /// Darker accent blue for the fill of any prominent button with a white label: the brand
    /// `accentBlue` fill measured 3.86:1 behind white 17 pt text ("Start New Mix", iPad
    /// audit 2026-10-05), below WCAG AA 4.5:1 (HIG Accessibility contrast table). This
    /// same-hue blue gives about 5.2:1.
    static let prominentFill = Color(
        .sRGB, red: prominentFillRGB.red, green: prominentFillRGB.green, blue: prominentFillRGB.blue, opacity: 1
    )

    /// ``prominentFill`` as components, shared with the UIKit port.
    static let prominentFillRGB = (red: 31.0 / 255, green: 108.0 / 255, blue: 203.0 / 255)
}

extension View {
    /// A bordered prominent button on the readable accent fill (``AccentText/prominentFill``).
    /// Under Increase Contrast (system or the app's More Contrast) it takes the app's
    /// increased-contrast tint, primary white, with a dark label (``FestivalProminentButtonColors``).
    ///
    /// - Returns: The styled button.
    func festivalProminentButton() -> some View {
        modifier(FestivalProminentButton())
    }
}

/// Fill and label of ``SwiftUI/View/festivalProminentButton()``.
///
/// `.borderedProminent` keeps a white label whatever its tint, so the white increased-contrast
/// tint alone painted a blank white capsule (issue #477: "Choose Profile" unreadable under
/// Increase Contrast). Each fill is paired with its label; HIG Color: "Supply … an
/// increased-contrast option for each" custom colour.
struct FestivalProminentButtonColors: Equatable {
    /// The button's tint (its fill).
    let fill: Color
    /// The label's colour on that fill.
    let label: Color

    /// The colours for the current contrast setting.
    ///
    /// - Parameter increasedContrast: System Increase Contrast or the app's More Contrast.
    init(increasedContrast: Bool) {
        if increasedContrast {
            // The root tint under Increase Contrast, with the page's dark background as label
            // (about 18:1).
            fill = BrandTokens.textPrimary
            label = BrandTokens.appBackground
        } else {
            // White on the readable accent blue (about 5.2:1).
            fill = AccentText.prominentFill
            label = BrandTokens.textPrimary
        }
    }
}

/// Implementation of ``SwiftUI/View/festivalProminentButton()``.
private struct FestivalProminentButton: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    func body(content: Content) -> some View {
        let colors = FestivalProminentButtonColors(increasedContrast: contrast == .increased || moreContrast)
        content.buttonStyle(.borderedProminent)
            .tint(colors.fill)
            .foregroundStyle(colors.label)
    }
}
