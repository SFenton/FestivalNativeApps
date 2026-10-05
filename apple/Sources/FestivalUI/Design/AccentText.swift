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
