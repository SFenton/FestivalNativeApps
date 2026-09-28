import SwiftUI
import FestivalDesign

// MARK: - Star rating

/// A row of the web app's own star images (`public/star_white.png` and
/// `public/star_gold.png`, bundled as `star_white` / `star_gold` in
/// `Resources/Stars.xcassets`).
///
/// Ports the semantics of the web's `components/songs/metadata/MiniStars.tsx` and
/// `GoldStars.tsx`: the service's top score (six stars) is drawn as **five gold stars**,
/// anything else as that many white stars (at least one). Use this everywhere a star
/// count is shown instead of SF Symbol `star` / `star.fill`, so the app keeps the
/// game's recognizable star artwork.
///
/// The row is one accessibility element labelled like the web's `common.starCount` /
/// `common.goldStarCount` strings ("3 stars", "5 gold stars").
public struct StarRating: View {
    // MARK: - Style

    /// Visual treatment, matching the two web components.
    public enum Style: Sendable {
        /// Plain star images in a tight row: the web's `GoldStars` and the inline
        /// rows in the Filter sheet and Suggestion cards (default 14 pt, 2 pt gap).
        case inline
        /// The web's `MiniStars`: each star centered in a 24 pt circle (20 pt star,
        /// 3 pt gap) that gets a 1.5 pt gold outline when the row is gold.
        case mini
    }

    private let count: Int
    private let isGold: Bool
    private let style: Style
    private let baseSize: CGFloat?
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    /// Create a star row.
    ///
    /// - Parameters:
    ///   - stars: Raw service star count. `6` (or more) means gold stars; `0...5` draws
    ///     that many white stars, clamped to at least one like the web's `MiniStars`.
    ///   - gold: Force the gold treatment even when `stars` is below six (for example a
    ///     "gold stars" statistic or an average of exactly six).
    ///   - style: `.inline` (plain images) or `.mini` (web `MiniStars` circles).
    ///   - size: Star image edge in points before Dynamic Type scaling; defaults to
    ///     14 pt for `.inline` and 20 pt for `.mini`.
    public init(stars: Int, gold: Bool = false, style: Style = .inline, size: CGFloat? = nil) {
        let display = Self.display(stars: stars, gold: gold)
        self.count = display.count
        self.isGold = display.gold
        self.style = style
        self.baseSize = size
    }

    public var body: some View {
        let starEdge = (baseSize ?? defaultSize) * scale
        HStack(spacing: spacing * scale) {
            ForEach(0..<count, id: \.self) { _ in
                star(edge: starEdge)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(count: count, gold: isGold))
    }

    // MARK: - Layout

    private var defaultSize: CGFloat {
        switch style {
        case .inline: 14
        case .mini: 20
        }
    }

    private var spacing: CGFloat {
        switch style {
        case .inline: 2
        case .mini: 3
        }
    }

    /// One star, wrapped in the `MiniStars` circle when that style is chosen.
    ///
    /// - Parameter edge: Scaled star image edge in points.
    /// - Returns: The star image view.
    @ViewBuilder
    private func star(edge: CGFloat) -> some View {
        let image = Image(Self.assetName(gold: isGold), bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: edge, height: edge)
        switch style {
        case .inline:
            image
        case .mini:
            // Web: 24 px circle around a 20 px star; keep that 1.2 ratio at any size.
            let circle = edge * 1.2
            image
                .frame(width: circle, height: circle)
                .overlay(
                    Circle().strokeBorder(isGold ? BrandTokens.gold : .clear, lineWidth: 1.5)
                )
                .clipShape(Circle())
        }
    }

    // MARK: - Semantics

    /// Resolve how many stars to draw and whether they are gold.
    ///
    /// - Parameters:
    ///   - stars: Raw service star count (`6` = gold).
    ///   - gold: Force the gold treatment.
    /// - Returns: Stars to draw (1...5) and whether to use the gold image.
    nonisolated static func display(stars: Int, gold: Bool) -> (count: Int, gold: Bool) {
        if gold || stars >= 6 { return (5, true) }
        return (max(1, stars), false)
    }

    /// Bundled asset for one star.
    ///
    /// - Parameter gold: Whether the gold image is wanted.
    /// - Returns: `star_gold` or `star_white` inside `Resources/Stars.xcassets`.
    nonisolated static func assetName(gold: Bool) -> String {
        gold ? "star_gold" : "star_white"
    }

    /// VoiceOver label matching the web's `common.starCount` / `common.goldStarCount`.
    ///
    /// - Parameters:
    ///   - count: Stars drawn.
    ///   - gold: Whether they are gold.
    /// - Returns: For example "1 star", "4 stars" or "5 gold stars".
    nonisolated static func accessibilityLabel(count: Int, gold: Bool) -> String {
        let noun = count == 1 ? "star" : "stars"
        return gold ? "\(count) gold \(noun)" : "\(count) \(noun)"
    }
}
