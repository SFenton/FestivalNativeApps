import CoreGraphics
import SwiftUI
import FestivalCore

// MARK: - Wide-row profile panel

/// One scored chart's card in a wide Songs row's profile panel.
struct SongProfilePanelTile: Equatable, Identifiable {
    /// The chart this card describes.
    let chart: Instrument
    /// Visibility-filtered fields in the Settings Song row order.
    let fields: [SongMetadataField]

    var id: Instrument { chart }

    /// The card's single VoiceOver stop: chart name, then every field in order.
    var announcement: String {
        fields.isEmpty
            ? "\(chart.label), scored"
            : "\(chart.label): " + fields.map(\.announcement).joined(separator: ", ")
    }
}

/// Pure rules for the wide Songs row that puts the selected player's per-instrument
/// cards on the right half of the row (issue #340, decision A in
/// `.agents/controls/song-score-metadata/spec.md`).
///
/// The panel never decides score availability itself: callers pass the Songs
/// score-index gate (`FestivalSession.hasCurrentPlayerScores(forCatalogue:)`), and a
/// row without a current, publication-matched index keeps its plain loading/paused
/// content.
enum SongProfilePanelPolicy {
    /// Narrowest row card (outer width) that splits: the regular-width breakpoint
    /// (``DeviceLayout/regularColumnWidth``), so each half keeps about 290 pt.
    static let minimumRowWidth: CGFloat = DeviceLayout.regularColumnWidth
    /// Gap between the song half and the panel half.
    static let gap: CGFloat = 12
    /// Gap between instrument cards, horizontally and vertically.
    static let tileSpacing: CGFloat = 8
    /// A card's own width besides its pills: 8 pt padding each side, the 28 pt icon
    /// slot and its 8 pt gap.
    static let tileChrome: CGFloat = 16 + 28 + 8
    /// Gap between pills (``SongProfileMetadataPills``).
    static let pillSpacing: CGFloat = 10
    /// Fields an all-instruments card shows (when enabled in Settings); a single
    /// filtered chart shows every enabled field, like the one-chart Songs row.
    static let overviewKinds: Set<SongMetadataKind> = [.score, .accuracy, .percentile, .stars]

    /// How the panel lays out its cards.
    struct Arrangement: Equatable {
        /// Cards per line.
        let columns: Int
        /// All-instruments cards leave out the stars pill to save a line.
        let dropsStars: Bool
    }

    /// Typical width of one pill at the default text size (``SongMetadataFieldView``):
    /// a six-digit `title3` score, the fixed 66 pt percent pill, the 80 pt minimum
    /// percentile pill, five 23 pt mini stars.
    ///
    /// - Parameter kind: Field kind.
    /// - Returns: Estimated width in points.
    static func estimatedWidth(_ kind: SongMetadataKind) -> CGFloat {
        switch kind {
        case .score: 84
        case .accuracy: 66
        case .percentile: 80
        case .stars: 150
        case .season: 42
        case .intensity: 87
        case .difficulty: 32
        case .lastPlayed: 160
        }
    }

    /// Width a card needs to keep its pills on one line.
    ///
    /// - Parameters:
    ///   - kinds: The card's fields.
    ///   - scale: Dynamic Type scale relative to the default size.
    /// - Returns: Points.
    static func lineWidth(_ kinds: [SongMetadataKind], scale: CGFloat = 1) -> CGFloat {
        let pills = kinds.reduce(CGFloat.zero) { $0 + estimatedWidth($1) }
            + CGFloat(max(0, kinds.count - 1)) * pillSpacing
        return tileChrome + pills * max(1, scale)
    }

    /// Choose columns (and whether to drop stars) so cards fit on one line each with
    /// the fewest lines; stars stay when they cost no extra line. A card too wide even
    /// alone wraps its pills in one column.
    ///
    /// - Parameters:
    ///   - width: The panel half's width.
    ///   - tiles: The cards.
    ///   - overview: All-instruments cards (a single filtered chart never drops stars).
    ///   - scale: Dynamic Type scale relative to the default size.
    /// - Returns: The arrangement.
    static func arrangement(
        width: CGFloat, tiles: [SongProfilePanelTile], overview: Bool, scale: CGFloat = 1
    ) -> Arrangement {
        func columns(dropsStars: Bool) -> Int {
            let needed = tiles.map { tile in
                lineWidth(
                    tile.fields.map(\.id).filter { !dropsStars || $0 != .stars }, scale: scale
                )
            }.max() ?? tileChrome
            let fit = Int(((width + tileSpacing) / (needed + tileSpacing)).rounded(.down))
            return min(fit, max(1, tiles.count))
        }
        let full = columns(dropsStars: false)
        let hasStars = tiles.contains { $0.fields.contains { $0.id == .stars } }
        guard overview, hasStars else { return Arrangement(columns: max(1, full), dropsStars: false) }
        let compact = columns(dropsStars: true)
        func lines(_ columns: Int) -> Int {
            columns < 1 ? Int.max : (tiles.count + columns - 1) / columns
        }
        if full >= 1, lines(full) <= lines(compact) {
            return Arrangement(columns: full, dropsStars: false)
        }
        return Arrangement(columns: max(1, compact), dropsStars: true)
    }

    /// Whether a row may split at all.
    ///
    /// - Parameters:
    ///   - allowed: The shell opted in (``SwiftUI/EnvironmentValues/songRowsAllowProfilePanel``).
    ///   - hasSelectedPlayer: A player is selected.
    ///   - scoresCurrent: The score index is available and matches the displayed Songs
    ///     publication (never a paused, loading or failed index).
    ///   - filterInvalidScores: The unsupported invalid-score substitution is requested.
    ///   - accessibilitySize: Accessibility Dynamic Type sizes keep the stacked row.
    ///   - shopRow: The row is an Item Shop offer.
    ///   - rowWidth: The row card's outer width in points (0 before layout).
    /// - Returns: True when the split layout may replace the plain row.
    static func allows(
        allowed: Bool, hasSelectedPlayer: Bool, scoresCurrent: Bool,
        filterInvalidScores: Bool, accessibilitySize: Bool, shopRow: Bool,
        rowWidth: CGFloat
    ) -> Bool {
        allowed && hasSelectedPlayer && scoresCurrent && !filterInvalidScores
            && !accessibilitySize && !shopRow && rowWidth >= minimumRowWidth
    }

    /// Width of each half of a split row's content.
    ///
    /// - Parameter contentWidth: Row width inside the card's padding.
    /// - Returns: Half the content after the gap.
    static func halfWidth(contentWidth: CGFloat) -> CGFloat {
        max(0, (contentWidth - gap) / 2)
    }

    /// The scored charts' cards, in the chips' stable instrument order.
    ///
    /// - Parameters:
    ///   - song: Current catalogue song (chart support and Intensity).
    ///   - scores: This song's verified selected-player index.
    ///   - instrumentFilter: Songs' explicit chart filter, or nil for all visible charts.
    ///   - visibleInstruments: Charts enabled in Settings.
    ///   - currentSeason: Current season for the season pill.
    ///   - visibility: Saved score-field switches.
    ///   - order: Settings' saved Song row field order.
    /// - Returns: One card per supported chart with a positive score; empty when the
    ///   song has none, so the row stays plain.
    /// - Throws: The typed projection's invalid-accuracy error (the row falls back).
    static func tiles(
        song: Song, scores: [Instrument: PlayerScore], instrumentFilter: Instrument?,
        visibleInstruments: Set<Instrument>, currentSeason: Int?,
        visibility: SongMetadataVisibility, order: [MetadataField]
    ) throws -> [SongProfilePanelTile] {
        let charts = instrumentFilter.map { [$0] }
            ?? Instrument.allCases.filter(visibleInstruments.contains)
        return try charts.compactMap { chart in
            guard song.supports(chart), let score = scores[chart], score.score > 0 else { return nil }
            var fields = try SongProfileCardPolicy.fields(
                for: score, chart: chart, song: song,
                currentSeason: currentSeason, visibility: visibility
            )
            if instrumentFilter == nil {
                fields = fields.filter { overviewKinds.contains($0.id) }
            }
            return SongProfilePanelTile(
                chart: chart, fields: SongProfileCardPolicy.reordered(fields, by: order)
            )
        }
    }

    /// Songs grid columns: one song per row while a player's cards can fill the right
    /// half, else the landscape grid (``SongGridPolicy/columns(layout:)``).
    ///
    /// - Parameters:
    ///   - layout: The page's device layout.
    ///   - hasSelectedPlayer: A player is selected.
    ///   - filterInvalidScores: Panels never show while this is requested.
    /// - Returns: 1 or 2.
    static func gridColumns(
        layout: DeviceLayout, hasSelectedPlayer: Bool, filterInvalidScores: Bool
    ) -> Int {
        hasSelectedPlayer && !filterInvalidScores ? 1 : SongGridPolicy.columns(layout: layout)
    }
}

extension EnvironmentValues {
    /// Whether Songs rows may split into song | selected player's instrument cards
    /// when wide enough (``SongProfilePanelPolicy``); set by Songs on iPad, the iPhone
    /// Duo inner display and the Mac.
    @Entry var songRowsAllowProfilePanel = false
}
