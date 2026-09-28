import SwiftUI

// MARK: - Star image

/// A single star in first-run demos (full-combo marker), drawn with the shared
/// `StarRating` so demos use the web's own `star_white`/`star_gold` artwork, never an SF Symbol.
struct FirstRunStar: View {
    /// Gold for full combo; white for a regular star.
    let gold: Bool
    /// Rendered edge length in points (before Dynamic Type scaling).
    var size: CGFloat = 14

    /// Asset name for a star kind (delegates to `StarRating`).
    ///
    /// - Parameter gold: Gold versus white star.
    /// - Returns: Image set name in the FestivalUI bundle.
    static func assetName(gold: Bool) -> String {
        StarRating.assetName(gold: gold)
    }

    var body: some View {
        StarRating(stars: 1, gold: gold, size: size)
            .accessibilityHidden(true)
    }
}

/// A row of stars in demos: six or more show five gold stars, like the web's `MiniStars`.
struct FirstRunStarRow: View {
    let count: Int
    var size: CGFloat = 12

    var body: some View {
        StarRating(stars: count, size: size)
    }
}
