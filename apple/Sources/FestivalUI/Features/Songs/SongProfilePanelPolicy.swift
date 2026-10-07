import CoreGraphics
import SwiftUI
import FestivalCore

// MARK: - Wide-row profile panel

/// One card in a wide Songs row's profile panel: a selected player's scored chart, or
/// the selected band's song score.
struct SongProfilePanelTile: Equatable, Identifiable {
    /// What a card describes.
    enum Subject: Equatable {
        /// A selected player's chart.
        case chart(Instrument)
        /// The selected band's score, named for VoiceOver.
        case band(BandType, name: String)
    }

    let subject: Subject
    /// Visibility-filtered fields in the Settings Song row order.
    let fields: [SongMetadataField]

    /// Stable within one row: the chart's wire key, or `band`.
    var id: String {
        switch subject {
        case let .chart(chart): chart.rawValue
        case .band: "band"
        }
    }

    /// The chart a player card describes; nil for a band card.
    var chart: Instrument? {
        if case let .chart(chart) = subject { chart } else { nil }
    }

    /// The card's spoken name.
    var label: String {
        switch subject {
        case let .chart(chart): chart.label
        case let .band(type, name): "\(name), \(type.label) band"
        }
    }

    /// The card's single VoiceOver stop: its name, then every field in order.
    var announcement: String {
        fields.isEmpty
            ? "\(label), scored"
            : "\(label): " + fields.map(\.announcement).joined(separator: ", ")
    }
}

/// Pure rules for the wide Songs row that puts the selected profile's score cards on
/// the right half of the row: a player's per-instrument cards or a band's score card
/// (issue #340; pattern `songs-profile-panel`, `.agents/patterns/songs-profile-panel.md`).
///
/// The panel never decides score availability itself: callers pass the Songs
/// score-index gate (`FestivalSession.hasCurrentPlayerScores(forCatalogue:)` or
/// `hasCurrentBandScores(forCatalogue:)`), and a row without a current,
/// publication-matched index keeps its plain loading/paused content.
enum SongProfilePanelPolicy {
    /// Narrowest row card (outer width) that may split: the regular-width breakpoint
    /// (``DeviceLayout/regularColumnWidth``). The one-line fit
    /// (``arrangement(width:tiles:overview:scale:)``) decides the rest: at default text
    /// size a compact score/accuracy/percentile card needs a 302 pt half, so in practice
    /// rows split from about 640 pt.
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
    /// Fields an all-instruments or band card shows (when enabled in Settings); a single
    /// filtered chart shows every enabled field, like the one-chart Songs row.
    static let overviewKinds: Set<SongMetadataKind> = [.score, .accuracy, .percentile, .stars]

    /// How the panel lays out its cards.
    struct Arrangement: Equatable {
        /// Cards per line.
        let columns: Int
        /// Compact cards leave out the stars pill to fit their line or save a line.
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

    /// Width of one field's pill: a score grows with its digits (a band's seven-digit
    /// score is wider than a player's six), about 12 pt a bold monospaced `title3`
    /// digit and 6 pt a group separator; other pills use their kind's estimate.
    ///
    /// - Parameter field: The field.
    /// - Returns: Estimated width in points.
    static func estimatedWidth(_ field: SongMetadataField) -> CGFloat {
        guard case let .score(value) = field else { return estimatedWidth(field.id) }
        let digits = String(abs(value)).count
        return CGFloat(digits) * 12 + CGFloat((digits - 1) / 3) * 6 + 6
    }

    /// Width a card needs to keep its pills on one line.
    ///
    /// - Parameters:
    ///   - fields: The card's fields.
    ///   - scale: Dynamic Type scale relative to the default size.
    /// - Returns: Points.
    static func lineWidth(_ fields: [SongMetadataField], scale: CGFloat = 1) -> CGFloat {
        let pills = fields.reduce(CGFloat.zero) { $0 + estimatedWidth($1) }
            + CGFloat(max(0, fields.count - 1)) * pillSpacing
        return tileChrome + pills * max(1, scale)
    }

    /// Choose columns (and whether to drop stars) so every card keeps its pills on one
    /// line with the fewest lines; stars stay when they cost no extra line.
    ///
    /// Compact cards (all instruments, or a band) must fit one line even alone: when
    /// one doesn't, even without stars, there is no arrangement and the row stays
    /// plain. A single filtered chart's card shows every enabled field, so it takes the
    /// whole half and wraps its pills like the one-chart Songs row.
    ///
    /// - Parameters:
    ///   - width: The panel half's width.
    ///   - tiles: The cards.
    ///   - overview: Compact cards (false only for one filtered chart).
    ///   - scale: Dynamic Type scale relative to the default size.
    /// - Returns: The arrangement, or nil when compact cards cannot fit one line.
    static func arrangement(
        width: CGFloat, tiles: [SongProfilePanelTile], overview: Bool, scale: CGFloat = 1
    ) -> Arrangement? {
        guard overview else { return Arrangement(columns: 1, dropsStars: false) }
        func columns(dropsStars: Bool) -> Int {
            let needed = tiles.map { tile in
                lineWidth(tile.fields.filter { !dropsStars || $0.id != .stars }, scale: scale)
            }.max() ?? tileChrome
            let fit = Int(((width + tileSpacing) / (needed + tileSpacing)).rounded(.down))
            return min(fit, max(1, tiles.count))
        }
        let full = columns(dropsStars: false)
        let hasStars = tiles.contains { $0.fields.contains { $0.id == .stars } }
        guard hasStars else { return full >= 1 ? Arrangement(columns: full, dropsStars: false) : nil }
        let compact = columns(dropsStars: true)
        guard compact >= 1 else { return nil }
        func lines(_ columns: Int) -> Int {
            columns < 1 ? Int.max : (tiles.count + columns - 1) / columns
        }
        if full >= 1, lines(full) <= lines(compact) {
            return Arrangement(columns: full, dropsStars: false)
        }
        return Arrangement(columns: compact, dropsStars: true)
    }

    /// Whether a row may split at all.
    ///
    /// - Parameters:
    ///   - allowed: The shell opted in (``SwiftUI/EnvironmentValues/songRowsAllowProfilePanel``).
    ///   - hasSelectedProfile: A player or band is selected.
    ///   - scoresCurrent: That profile's score index is available and matches the
    ///     displayed Songs publication (never a paused, loading or failed index).
    ///   - filterInvalidScores: The unsupported invalid-score substitution is requested
    ///     for a player (band scores have no substitution; callers pass false).
    ///   - accessibilitySize: Accessibility Dynamic Type sizes keep the stacked row.
    ///   - shopRow: The row is an Item Shop offer.
    ///   - rowWidth: The row card's outer width in points (0 before layout).
    /// - Returns: True when the split layout may replace the plain row.
    static func allows(
        allowed: Bool, hasSelectedProfile: Bool, scoresCurrent: Bool,
        filterInvalidScores: Bool, accessibilitySize: Bool, shopRow: Bool,
        rowWidth: CGFloat
    ) -> Bool {
        allowed && hasSelectedProfile && scoresCurrent && !filterInvalidScores
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
                subject: .chart(chart), fields: SongProfileCardPolicy.reordered(fields, by: order)
            )
        }
    }

    /// The selected band's one compact card for a song.
    ///
    /// - Parameters:
    ///   - band: The selected band.
    ///   - entry: This song's row from the verified band index, if the band scored it.
    ///   - currentSeason: Current season for the season pill.
    ///   - visibility: Saved score-field switches.
    ///   - order: Settings' saved Song row field order.
    /// - Returns: One card for a positive score; empty otherwise, so the row stays plain.
    /// - Throws: The typed projection's invalid-accuracy error (the row falls back).
    static func bandTiles(
        band: SelectedBandIdentity, entry: BandSongPerformanceEntry?, currentSeason: Int?,
        visibility: SongMetadataVisibility, order: [MetadataField]
    ) throws -> [SongProfilePanelTile] {
        guard let entry, entry.score > 0 else { return [] }
        let fields = try SongProfileCardPolicy.bandFields(
            for: entry, currentSeason: currentSeason, visibility: visibility
        ).filter { overviewKinds.contains($0.id) }
        return [SongProfilePanelTile(
            subject: .band(band.bandType, name: band.displayName),
            fields: SongProfileCardPolicy.reordered(fields, by: order)
        )]
    }

    /// Songs grid columns: one song per row while a profile's cards can fill the right
    /// half, else the landscape grid (``SongGridPolicy/columns(layout:)``).
    ///
    /// - Parameters:
    ///   - layout: The page's device layout.
    ///   - hasSelectedProfile: A player or band is selected.
    ///   - filterInvalidScores: A player's panels never show while this is requested.
    /// - Returns: 1 or 2.
    static func gridColumns(
        layout: DeviceLayout, hasSelectedProfile: Bool, filterInvalidScores: Bool
    ) -> Int {
        hasSelectedProfile && !filterInvalidScores ? 1 : SongGridPolicy.columns(layout: layout)
    }
}

extension EnvironmentValues {
    /// Whether Songs rows may split into song | selected profile's score cards when
    /// wide enough (``SongProfilePanelPolicy``); set by Songs on iPad, the iPhone
    /// Duo inner display and the Mac.
    @Entry var songRowsAllowProfilePanel = false
}
