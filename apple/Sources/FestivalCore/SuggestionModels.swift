import Foundation

// MARK: - Suggestion category type

/// Broad family a generated `SuggestionCategory` belongs to, used only for the
/// Suggestions filter sheet (web `SuggestionTypeId`). Rival- and band-driven
/// families are not ported in this wave (no rival/band data source yet).
public enum SuggestionCategoryType: String, CaseIterable, Codable, Sendable, Identifiable {
    case nearFC
    case starProgress
    case unplayed
    case varietyPack
    case artistEssentials
    case artistDiscover
    case sameName
    case almostElite
    case percentilePush
    case stale
    case pctImprove

    public var id: String { rawValue }

    /// Title Case label for the filter sheet's "General" section.
    public var label: String {
        switch self {
        case .nearFC: "Near FC"
        case .starProgress: "Star Progress"
        case .unplayed: "Unplayed"
        case .varietyPack: "Variety Pack"
        case .artistEssentials: "Artist Essentials"
        case .artistDiscover: "Artist Discover"
        case .sameName: "Same Name"
        case .almostElite: "Almost Elite"
        case .percentilePush: "Percentile Push"
        case .stale: "Stale Songs"
        case .pctImprove: "Percentile Improve"
        }
    }

    /// One-line explanation shown under the filter row's label.
    public var filterDescription: String {
        switch self {
        case .nearFC: "Songs you're close to full-comboing."
        case .starProgress: "Push five-star runs to gold, or gain more stars."
        case .unplayed: "Songs you haven't played yet."
        case .varietyPack: "A mix of songs from different artists."
        case .artistEssentials: "A selection of songs by a single artist."
        case .artistDiscover: "Unplayed songs from a single artist."
        case .sameName: "Different tracks that share the same title."
        case .almostElite: "Top 5% — one good run could crack the top 1%."
        case .percentilePush: "Close to the next percentile bracket."
        case .stale: "Songs you haven't played in a while."
        case .pctImprove: "Songs with room for percentile improvement."
        }
    }
}

// MARK: - Suggested song

/// One song shown inside a `SuggestionCategory`, annotated with the score fields
/// relevant to that category (web `SuggestionSongItem`, minus rival cross-pollination).
public struct SuggestionSongItem: Identifiable, Equatable, Sendable {
    public let song: Song
    /// Chart this suggestion is about, when the category mixes instruments; nil for a
    /// single-instrument category (the instrument is already implied by its title).
    public let instrument: Instrument?
    public let stars: Int?
    /// Accuracy as a 0–100 percent (already descaled from the wire's expanded form).
    public let percent: Double?
    public let fullCombo: Bool?
    public var percentileDisplay: String?

    public var id: String { instrument.map { "\(song.songId)|\($0.rawValue)" } ?? song.songId }

    /// Build one annotated suggestion row.
    ///
    /// - Parameters:
    ///   - song: Catalogue row being suggested.
    ///   - instrument: Chart the annotation is about, or nil when instrument-agnostic.
    ///   - stars: Current star count for that chart, if scored.
    ///   - percent: Current accuracy percent (0–100), if scored.
    ///   - fullCombo: Whether the current score is a full combo.
    ///   - percentileDisplay: Precomputed "Top N%" label, if a rank is known.
    public init(
        song: Song, instrument: Instrument? = nil, stars: Int? = nil, percent: Double? = nil,
        fullCombo: Bool? = nil, percentileDisplay: String? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.stars = stars
        self.percent = percent
        self.fullCombo = fullCombo
        self.percentileDisplay = percentileDisplay
    }
}

// MARK: - Suggestion category

/// One titled group of suggested songs (web `SuggestionCategory` + the generator's key).
public struct SuggestionCategory: Identifiable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let description: String
    public let type: SuggestionCategoryType
    /// The single chart this category is about, or nil when it mixes instruments
    /// (each song then carries its own `SuggestionSongItem.instrument`).
    public let instrument: Instrument?
    public let songs: [SuggestionSongItem]

    public var id: String { key }

    /// Build one category. Called only by `SuggestionGenerator` and category filtering.
    public init(
        key: String, title: String, description: String, type: SuggestionCategoryType,
        instrument: Instrument?, songs: [SuggestionSongItem]
    ) {
        self.key = key
        self.title = title
        self.description = description
        self.type = type
        self.instrument = instrument
        self.songs = songs
    }
}

// MARK: - Season fallback

/// Season used by "stale" categories when the catalogue hasn't reported one.
public enum SuggestionSeason {
    /// Fall back to the highest season observed in the player's own scores.
    ///
    /// - Parameters:
    ///   - currentSeason: Catalogue-reported season, if any.
    ///   - scores: Selected player's validated score index.
    /// - Returns: A season of at least 0; 0 disables season-gated ("stale") categories.
    public static func effective(
        currentSeason: Int?, scores: [String: [Instrument: PlayerScore]]
    ) -> Int {
        if let currentSeason, currentSeason > 0 { return currentSeason }
        var highest = 0
        for perInstrument in scores.values {
            for score in perInstrument.values where (score.season ?? 0) > highest {
                highest = score.season ?? 0
            }
        }
        return highest
    }
}
