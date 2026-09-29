import Foundation

// MARK: - Stars and percentile buckets

/// The web Songs filter's star buckets (`FilterModal.tsx` `StarsToggles`): 6 is gold
/// (five gold stars), 5…1 are white stars and 0 is "No Score".
public enum SongStarsBucket {
    /// Every bucket key, in the web's display order (gold first, No Score last).
    public static let keys: [Int] = [6, 5, 4, 3, 2, 1, 0]

    /// The bucket a selected-player score falls in (web `score?.stars ?? 0`).
    ///
    /// - Parameter score: The selected player's score on the Songs instrument, or nil.
    /// - Returns: The raw star count, 0 without a score.
    public static func key(for score: PlayerScore?) -> Int {
        score?.stars ?? 0
    }

    /// Spoken and visible filter label for a bucket.
    ///
    /// - Parameter key: One of ``keys``.
    /// - Returns: "No Score", "5 gold stars", "1 star", …
    public static func label(_ key: Int) -> String {
        switch key {
        case 0: "No Score"
        case 6: "5 gold stars"
        case 1: "1 star"
        default: "\(key) stars"
        }
    }
}

/// The web Songs filter's percentile buckets (`FilterModal.tsx` `PercentileToggles`,
/// `useFilteredSongs.ts`): Top 1%…Top 100%, and 0 for "No Score" (no score, or no
/// published rank).
public enum SongPercentileBucket {
    /// Thresholds, best first (`PERCENTILE_THRESHOLDS`).
    public static let thresholds: [Int] = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100]
    /// Every bucket key in the web's display order ("No Score" first).
    public static let keys: [Int] = [0] + thresholds

    /// The bucket a selected-player score falls in: the first threshold at or above
    /// `rank / totalEntries × 100` (capped at 100), or 0 without a positive rank and field.
    ///
    /// - Parameter score: The selected player's score on the Songs instrument, or nil.
    /// - Returns: A threshold from ``thresholds``, or 0.
    public static func key(for score: PlayerScore?) -> Int {
        guard let fraction = rankFraction(score) else { return 0 }
        let percentile = min(fraction * 100, 100)
        return thresholds.first { percentile <= Double($0) } ?? 100
    }

    /// `rank / totalEntries` for a ranked score (web `compareByMode('percentile')`).
    ///
    /// - Parameter score: A selected-player score, or nil.
    /// - Returns: The fraction, or nil without a positive rank and field size.
    static func rankFraction(_ score: PlayerScore?) -> Double? {
        guard let rank = score?.rank, let total = score?.totalEntries, rank > 0, total > 0 else {
            return nil
        }
        return Double(rank) / Double(total)
    }

    /// Visible filter label for a bucket.
    ///
    /// - Parameter key: One of ``keys``.
    /// - Returns: "No Score" or "Top 5%".
    public static func label(_ key: Int) -> String {
        key == 0 ? "No Score" : "Top \(key)%"
    }
}

/// The web Songs filter's season buckets (`SeasonToggles`): the seasons the selected
/// player has scores in, plus 0 for "No Score".
public enum SongSeasonBucket {
    /// Largest season key accepted from saved preferences.
    public static let maximumSeason = 999

    /// The bucket a selected-player score falls in (web `score?.season ?? 0`).
    ///
    /// - Parameter score: The selected player's score on the Songs instrument, or nil.
    /// - Returns: The season, 0 without a score or season.
    public static func key(for score: PlayerScore?) -> Int {
        score?.season ?? 0
    }

    /// Keys to offer: the seasons present in the player's scores, ascending, then 0.
    ///
    /// - Parameter scores: The selected player's score index.
    /// - Returns: Distinct positive seasons followed by 0 (web `[...availableSeasons, 0]`).
    public static func keys(in scores: [String: [Instrument: PlayerScore]]) -> [Int] {
        let seasons = Set(scores.values.flatMap { $0.values.compactMap(\.season) }.filter { $0 > 0 })
        return seasons.sorted() + [0]
    }

    /// Visible filter label.
    ///
    /// - Parameter key: A season or 0.
    /// - Returns: "No Score" or "Season 5".
    public static func label(_ key: Int) -> String {
        key == 0 ? "No Score" : "Season \(key)"
    }
}

/// The web Songs filter's intensity buckets (`DifficultyToggles`): the chart's 0–6
/// intensity shown as 1–7 bars, and 0 for an uncharted instrument.
public enum SongIntensityBucket {
    /// Every key in the web's display order.
    public static let keys: [Int] = [1, 2, 3, 4, 5, 6, 7, 0]

    /// The bucket for a song on one chart (web `trunc(diff) + 1`, clamped to 1…7).
    ///
    /// - Parameters:
    ///   - song: Catalogue song.
    ///   - instrument: The Songs instrument.
    /// - Returns: 1…7, or 0 when the chart has no intensity.
    public static func key(for song: Song, instrument: Instrument) -> Int {
        guard let value = song.difficulty?.chartedValue(for: instrument) else { return 0 }
        return min(7, max(1, Int(value.rounded(.towardZero)) + 1))
    }

    /// Visible filter label.
    ///
    /// - Parameter key: One of ``keys``.
    /// - Returns: "No Score" or "Intensity 3 of 7".
    public static func label(_ key: Int) -> String {
        key == 0 ? "No Score" : "Intensity \(key) of 7"
    }
}

/// The four web bucket filters that read one Songs instrument.
public enum SongBucketKind: String, CaseIterable, Sendable, Identifiable {
    case season
    case percentile
    case stars
    case intensity

    public var id: String { rawValue }

    /// Whether a key can be saved for this filter.
    ///
    /// - Parameter key: Candidate bucket key.
    /// - Returns: True for a known star/percentile/intensity key or a season 0…999.
    public func accepts(_ key: Int) -> Bool {
        switch self {
        case .season: (0...SongSeasonBucket.maximumSeason).contains(key)
        case .percentile: SongPercentileBucket.keys.contains(key)
        case .stars: SongStarsBucket.keys.contains(key)
        case .intensity: SongIntensityBucket.keys.contains(key)
        }
    }

    /// Whether the check reads the selected player's scores (intensity reads the song).
    public var needsScores: Bool { self != .intensity }
}

// MARK: - Player-mode sorting

/// The web's `compareByMode` for the ported selected-player sorts.
enum SongScoreSortKey {
    /// Compare two songs' selected-player scores; a song without a score sorts after
    /// one with a score in ascending order (and, reversed, before it in descending
    /// order, like the web's `cmp * dir`).
    ///
    /// - Parameters:
    ///   - left: First song's score on the Songs instrument.
    ///   - right: Second song's score.
    ///   - mode: Score, Percentile or Stars.
    /// - Returns: The primary order; ties fall back to title in the caller.
    static func compare(_ left: PlayerScore?, _ right: PlayerScore?, mode: SongSortMode) -> ComparisonResult {
        switch (left, right) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (left?, right?):
            switch mode {
            case .score:
                return compare(Double(left.score), Double(right.score))
            case .stars:
                return compare(Double(left.stars ?? 0), Double(right.stars ?? 0))
            case .percentile:
                // Unranked is +∞ on the web; two unranked scores tie.
                let lhs = SongPercentileBucket.rankFraction(left) ?? .infinity
                let rhs = SongPercentileBucket.rankFraction(right) ?? .infinity
                return compare(lhs, rhs)
            default:
                return .orderedSame
            }
        }
    }

    private static func compare(_ left: Double, _ right: Double) -> ComparisonResult {
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}

// MARK: - Player-mode sections

/// A nonempty run of rows sorted by a player mode, grouped like the web's quick links.
public struct SongScoreSection: Identifiable, Sendable {
    /// Bucket key: "no-score", "no-rank", a score floor, a percentile or a star count.
    public let key: String
    /// Header and quick-link title (web labels: "1.2M+", "5%", "5★", "No Score").
    public let label: String
    /// VoiceOver label ("5 stars" rather than "5 black star").
    public let spokenLabel: String
    public internal(set) var songs: [Song]

    public var id: String { key }

    /// The web's bucket for one score.
    ///
    /// - Parameters:
    ///   - score: Selected-player score on the Songs instrument.
    ///   - mode: Score, Percentile or Stars.
    /// - Returns: Key, visible label and spoken label.
    static func bucket(for score: PlayerScore?, mode: SongSortMode) -> (key: String, label: String, spoken: String) {
        switch mode {
        case .score:
            guard let value = score?.score, value > 0 else { return ("no-score", "No Score", "No Score") }
            let step = value >= 1_000_000 ? 100_000 : 50_000
            let floor = (value / step) * step
            let text = "\(compactNumber(floor))+"
            return (String(floor), text, text)
        case .percentile:
            let key = SongPercentileBucket.key(for: score)
            guard key > 0 else { return ("no-rank", "No Rank", "No Rank") }
            return (String(key), "\(key)%", "Top \(key)%")
        case .stars:
            guard let stars = score?.stars, stars > 0 else { return ("no-score", "No Score", "No Score") }
            let spoken = stars >= 6 ? "Gold stars" : (stars == 1 ? "1 star" : "\(stars) stars")
            return (String(stars), "\(stars)★", spoken)
        default:
            return ("none", "", "")
        }
    }

    /// The web's `formatCompactNumber`: 1.2M, 950k.
    ///
    /// - Parameter value: A non-negative score floor.
    /// - Returns: Compact text.
    static func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return millions == millions.rounded()
                ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        if value >= 1_000 {
            return "\(Int((Double(value) / 1_000).rounded()))k"
        }
        return "\(value)"
    }
}
