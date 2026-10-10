import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Tile model

/// One value/label tile in a player-page stat grid (web `StatBox`).
///
/// `id` is a stable key within its grid (for example `songs-played`), never a fresh
/// `UUID`: a new identity on every body pass made `ForEach` remove and re-insert every
/// tile whenever the page re-rendered, so tiles cross-faded mid-push and mid-scroll.
struct StatTile: Identifiable {
    /// Stable key within the grid; also the accessibility identifier suffix.
    let id: String
    let label: String
    let value: String
    var tint: Color?
    /// Draw five gold stars (`StarRating`, web `GoldStars`) instead of `value`.
    var goldStars = false
    /// Where a tap goes; nil for a plain, non-interactive tile.
    var link: PlayerStatLink?
    /// Still loading: the value is drawn as a redacted placeholder of the same size.
    var isPlaceholder = false
}

// MARK: - Grid

/// Stat tiles in an adaptive grid: two columns on iPhone, three or four as the page
/// widens (``StatGridColumns``). Every tile is its own material card (web `StatBox` in a
/// `frostedCard`); clickable tiles show an in-tile chevron.
///
/// A custom `Layout`, not a `LazyVGrid`: it reads the proposed width in the same layout
/// pass, so the first frame already has its final column count and row heights (no
/// resize while a push or fade-in is running), and every tile in a row gets that row's
/// height so chevrons and values line up.
struct PlayerStatGrid: View {
    let tiles: [StatTile]
    /// Accessibility identifier scope: `overview` or an instrument's raw value.
    let scope: String
    /// Accessibility identifier prefix: the Player profile's, or Band Detail's `fst.band.stat`.
    var identifierPrefix = PlayerStatTileView.playerIdentifierPrefix
    let onSelect: (PlayerStatLink) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    var body: some View {
        let minimumTileWidth = dynamicTypeSize.isAccessibilitySize
            ? StatGridColumns.accessibilityMinimumTileWidth : StatGridColumns.minimumTileWidth
        StatTileGridLayout(
            spacing: StatGridColumns.spacing,
            minimumTileWidth: minimumTileWidth,
            minimumColumns: dynamicTypeSize.isAccessibilitySize
                ? StatGridColumns.accessibilityMinimumColumns : StatGridColumns.minimumColumns,
            // A grid that spans an iPhone Duo book-pose fold (Global Statistics) puts a
            // gutter on it (pattern `hinge-columns`); tiles inside a half column never do.
            band: HingeColumns.band(
                span: span, fold: layout.splitHinge, gutter: StatGridColumns.spacing,
                minimumSide: max(CGFloat(minimumTileWidth), HingeColumns.minimumSide)
            )
        ) {
            ForEach(tiles) { tile in
                PlayerStatTileView(tile: tile, scope: scope, identifierPrefix: identifierPrefix, onSelect: onSelect)
            }
        }
        .measuresHorizontalSpan($span, fold: layout.splitHinge)
    }
}

/// Equal-width columns (``StatGridColumns/count(forWidth:minimumTileWidth:spacing:)``)
/// with each row as tall as its tallest tile; across an iPhone Duo book-pose fold, the
/// same count on each side with the centre gutter on the fold (``HingeColumns``).
struct StatTileGridLayout: Layout {
    var spacing: CGFloat = StatGridColumns.spacing
    /// Narrowest tile before a column is dropped (wider at accessibility sizes).
    var minimumTileWidth: Double = StatGridColumns.minimumTileWidth
    /// Fewest columns (one at accessibility sizes).
    var minimumColumns: Int = StatGridColumns.minimumColumns
    /// The fold's band across the grid, or nil; ignored unless it matches the width.
    var band: HingeBand?

    /// Every column's leading x and width for a width: hinge-aligned when ``band``
    /// matches it, otherwise ``metrics(for:)``'s equal columns.
    ///
    /// - Parameter width: Grid width; nil lays out at the two-column ideal.
    /// - Returns: One (x, width) per column.
    func columnFrames(for width: CGFloat?) -> [(x: CGFloat, width: CGFloat)] {
        if let band, let width, abs(band.width - width) < 0.5 {
            let spec = HingeColumns.spec(
                band: band, spacing: spacing, perSide: .fit(minimum: CGFloat(minimumTileWidth))
            )
            return zip(spec.offsets, spec.widths).map { (x: $0, width: $1) }
        }
        let (columns, tileWidth) = metrics(for: width)
        return (0 ..< columns).map { (x: CGFloat($0) * (tileWidth + spacing), width: tileWidth) }
    }

    /// Column count and tile width for a proposed width.
    ///
    /// - Parameter width: Proposed grid width; nil lays out at the two-column ideal.
    /// - Returns: Columns and the width of one tile.
    func metrics(for width: CGFloat?) -> (columns: Int, tileWidth: CGFloat) {
        let resolved = width ?? CGFloat(StatGridColumns.minimumTileWidth * 2) + spacing
        let columns = StatGridColumns.count(
            forWidth: Double(resolved), minimumTileWidth: minimumTileWidth, spacing: Double(spacing),
            minimumColumns: minimumColumns
        )
        let tileWidth = max(0, (resolved - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return (columns, tileWidth)
    }

    /// Height of every row, top to bottom.
    ///
    /// - Parameters:
    ///   - subviews: Tiles in display order.
    ///   - columns: Each column's frame.
    /// - Returns: One height per row.
    private func rowHeights(_ subviews: Subviews, columns: [(x: CGFloat, width: CGFloat)]) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns.count).map { start in
            zip(subviews[start ..< min(start + columns.count, subviews.count)], columns)
                .map { $0.sizeThatFits(ProposedViewSize(width: $1.width, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = columnFrames(for: proposal.width)
        let heights = rowHeights(subviews, columns: columns)
        let height = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        let width = proposal.width ?? columns.last.map { $0.x + $0.width } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columnFrames(for: bounds.width)
        let heights = rowHeights(subviews, columns: columns)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for (column, frame) in columns.enumerated() {
                let index = row * columns.count + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + frame.x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: frame.width, height: height)
                )
            }
            y += height + spacing
        }
    }
}

// MARK: - Tile

/// One tile: a button with a trailing chevron when it links somewhere, otherwise a
/// single static accessibility element.
struct PlayerStatTileView: View {
    /// The Player profile's tile identifier prefix.
    static let playerIdentifierPrefix = "fst.player.stat"

    let tile: StatTile
    let scope: String
    var identifierPrefix = playerIdentifierPrefix
    let onSelect: (PlayerStatLink) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Side padding that clears the chevron at every text size: a fixed 22 pt let the
    /// AX5 chevron (footnote, ≈ 2.5×) sit on "2 (66.6%)" (iPad audit capture, Lane A11Y3).
    @ScaledMetric(relativeTo: .footnote) private var chevronInset: CGFloat = 22

    private var identifier: String { "\(identifierPrefix).\(scope).\(tile.id)" }

    var body: some View {
        if let link = tile.link {
            Button {
                onSelect(link)
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(StatTileButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.label)
            .accessibilityValue(spokenValue)
            .accessibilityHint(Self.hint(for: link))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
        } else {
            content(showsChevron: false)
                .modifier(StatTileSurface(isPressed: false))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.label)
                .accessibilityValue(spokenValue)
                .accessibilityIdentifier(identifier)
        }
    }

    /// Lines a tile value may take: one, or two at accessibility text sizes.
    ///
    /// - Parameter size: The environment's Dynamic Type size.
    /// - Returns: The value's line limit.
    static func valueLineLimit(_ size: DynamicTypeSize) -> Int { size.isAccessibilitySize ? 2 : 1 }

    /// How far a tile value may shrink to fit: further at accessibility sizes, where a
    /// two-column grid in a 375 pt window still cut "(66.6%)" at AX5 after wrapping.
    ///
    /// - Parameter size: The environment's Dynamic Type size.
    /// - Returns: The minimum scale factor.
    static func valueMinimumScale(_ size: DynamicTypeSize) -> CGFloat { size.isAccessibilitySize ? 0.5 : 0.6 }

    private var spokenValue: String {
        if tile.isPlaceholder { return "Loading" }
        return tile.goldStars ? "5 gold stars" : tile.value
    }

    /// Value over an uppercase caption, centred; a chevron rides the trailing edge.
    ///
    /// Horizontal padding is symmetric (the chevron's inset on both sides) so the
    /// centred text stays centred whether or not the tile links somewhere.
    @ViewBuilder
    private func content(showsChevron: Bool) -> some View {
        VStack(spacing: 2) {
            Group {
                if tile.goldStars {
                    StarRating(stars: 6, gold: true, size: 16)
                        .frame(minHeight: 28)
                } else {
                    Text(tile.value)
                        .font(.title3.bold())
                        .monospacedDigit()
                        .foregroundStyle(tile.tint ?? AccentText.blue)
                        // One line, shrinking to fit; at accessibility sizes the value may
                        // also wrap ("2 (66.6%)" truncated to "2 (66…" in an iPad tile at
                        // AX5: HIG Typography "Keep text truncation to a minimum").
                        .lineLimit(Self.valueLineLimit(dynamicTypeSize))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(Self.valueMinimumScale(dynamicTypeSize))
                        .redacted(reason: tile.isPlaceholder ? .placeholder : [])
                }
            }
            Text(tile.label)
                .font(.caption2)
                .foregroundStyle(FestivalText.primary)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, chevronInset)
        .overlay(alignment: .trailing) {
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: StatTileSurface.cornerRadius))
    }

    /// VoiceOver hint naming where a tile goes.
    ///
    /// - Parameter link: The tile's link.
    /// - Returns: A short hint sentence.
    static func hint(for link: PlayerStatLink) -> String {
        switch link {
        case .songs: "Shows these songs in Songs"
        case .songDetail: "Opens the song"
        case .fullRankings: "Opens the full rankings"
        case .bandRankings: "Opens the band rankings"
        case .bandSongDetail: "Opens the song"
        }
    }
}

/// Each tile is its own material card, like the web's one `frostedCard` per `StatBox`
/// (operator batch 6: no big card around the grid). Pressed, a 4% white wash (web
/// `clickablePressed`).
struct StatTileSurface: ViewModifier {
    static let cornerRadius: CGFloat = 14
    let isPressed: Bool
    /// First-run demos: the tile's breathing glow tint, else nil.
    @Environment(\.statTileGlow) private var glow

    func body(content: Content) -> some View {
        let surface = content
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isPressed ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
            .festivalCard(cornerRadius: Self.cornerRadius)
        if let glow {
            surface.firstRunPulse(glow, shape: .roundedRect(cornerRadius: Self.cornerRadius))
        } else {
            surface
        }
    }
}

extension EnvironmentValues {
    /// A first-run demo's glow tint for every stat tile inside (nil on real pages).
    @Entry var statTileGlow: Color?
}

/// Web `StatBox` press feedback: a slight scale-down and a brighter fill.
struct StatTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(StatTileSurface(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
