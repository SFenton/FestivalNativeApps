import Foundation

// MARK: - Metrics

/// Sort metric for `/api/rankings/{instrument}`, mirroring the web client's
/// `RankingMetric` (`packages/core/src/api/serverTypes.ts:1137`).
public enum RankingMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case adjusted
    case weighted
    case fcrate
    case totalscore
    case maxscore

    public var id: String { rawValue }

    /// Present the same metric names as the web client's rank-by picker.
    public var label: String {
        switch self {
        case .adjusted: "Adjusted"
        case .weighted: "Weighted"
        case .fcrate: "FC Rate"
        case .totalscore: "Total Score"
        case .maxscore: "Max Score"
        }
    }

    /// Adjusted and weighted rank by a raw percentile rather than a plain value.
    public var isPercentile: Bool {
        self == .adjusted || self == .weighted
    }

    /// Bands have no max-score metric; fall back the same way the web client's
    /// `coerceBandRankingMetric` does when the shared instrument picker selects it.
    public var bandMetric: BandRankingMetric {
        BandRankingMetric(rawValue: rawValue) ?? .totalscore
    }
}

/// Sort metric for `/api/rankings/bands/{bandType}` — every `RankingMetric` case
/// except `.maxscore` (`packages/core/src/api/serverTypes.ts:1139`).
public enum BandRankingMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case adjusted
    case weighted
    case fcrate
    case totalscore

    public var id: String { rawValue }

    /// Reuse the shared account-metric label text.
    public var label: String { asRankingMetric.label }

    /// Widen back to the shared metric type for formatting helpers.
    public var asRankingMetric: RankingMetric {
        RankingMetric(rawValue: rawValue) ?? .totalscore
    }
}

// MARK: - Band type

/// The three ranked band sizes (`FortniteFestivalWeb/src/utils/bandTypes.ts`).
public enum BandType: String, CaseIterable, Codable, Sendable, Identifiable {
    case duets = "Band_Duets"
    case trios = "Band_Trios"
    case quad = "Band_Quad"

    public var id: String { rawValue }

    /// Present the same band-size names as the web client.
    public var label: String {
        switch self {
        case .duets: "Duos"
        case .trios: "Trios"
        case .quad: "Quads"
        }
    }
}

// MARK: - Per-instrument account rankings

/// One row of `/api/rankings/{instrument}`, matching `AccountRankingEntry`
/// (`packages/core/src/api/serverTypes.ts:1116`).
public struct AccountRankingEntry: Decodable, Sendable, Identifiable, Equatable {
    public let accountId: String
    public let displayName: String?
    public let songsPlayed: Int
    public let totalChartedSongs: Int
    public let coverage: Double
    public let rawSkillRating: Double
    public let adjustedSkillRating: Double
    public let adjustedSkillRank: Int
    public let weightedRating: Double
    public let weightedRank: Int
    public let fcRate: Double
    public let fcRateRank: Int
    public let totalScore: Int
    public let totalScoreRank: Int
    public let maxScorePercent: Double
    public let maxScorePercentRank: Int
    public let avgAccuracy: Double
    public let fullComboCount: Int
    public let avgStars: Double
    public let bestRank: Int
    public let avgRank: Double
    public let rawMaxScorePercent: Double?
    public let rawWeightedRating: Double?

    public var id: String { accountId }

    /// Rank column for the currently selected metric.
    ///
    /// - Parameter metric: Selected rank-by metric.
    /// - Returns: 1-based rank for that metric only.
    public func rank(for metric: RankingMetric) -> Int {
        switch metric {
        case .adjusted: adjustedSkillRank
        case .weighted: weightedRank
        case .fcrate: fcRateRank
        case .totalscore: totalScoreRank
        case .maxscore: maxScorePercentRank
        }
    }

    /// Raw value backing the displayed rating for the selected metric, mirroring
    /// the web client's `getRatingForMetric`.
    ///
    /// - Parameter metric: Selected rank-by metric.
    /// - Returns: Percentile fraction, score total or full-combo fraction.
    public func ratingValue(for metric: RankingMetric) -> Double {
        switch metric {
        case .adjusted: rawSkillRating
        case .weighted: rawWeightedRating ?? weightedRating
        case .fcrate: totalChartedSongs > 0 ? Double(fullComboCount) / Double(totalChartedSongs) : 0
        case .totalscore: Double(totalScore)
        case .maxscore: maxScorePercent
        }
    }

    /// The Bayesian-adjusted percentile value shown beside a "Top N%" pill.
    ///
    /// - Parameter metric: Selected rank-by metric.
    /// - Returns: `adjustedSkillRating`/`weightedRating` only for percentile metrics.
    public func bayesianValue(for metric: RankingMetric) -> Double? {
        switch metric {
        case .adjusted: adjustedSkillRating
        case .weighted: weightedRating
        default: nil
        }
    }

    /// Songs-played column, which counts full combos instead under FC Rate.
    ///
    /// - Parameter metric: Selected rank-by metric.
    /// - Returns: An "X / Y" label matching the web client's `getSongsLabel`.
    public func songsLabel(for metric: RankingMetric) -> String {
        metric == .fcrate
            ? "\(fullComboCount) / \(totalChartedSongs)"
            : "\(songsPlayed) / \(totalChartedSongs)"
    }
}

/// Response envelope for `/api/rankings/{instrument}`.
public struct RankingsResponse: Decodable, Sendable, Equatable {
    public let instrument: String
    public let rankBy: String
    public let page: Int
    public let pageSize: Int
    public let totalAccounts: Int
    public let entries: [AccountRankingEntry]

    /// Pages of `pageSize` rows, always at least one even for an empty board.
    public var pageCount: Int {
        let size = max(1, pageSize)
        return totalAccounts <= 0 ? 1 : (totalAccounts - 1) / size + 1
    }

    /// Reject a response for the wrong chart or with an impossible row count.
    ///
    /// - Parameter instrument: Requested solo chart.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on a mismatched or corrupt response.
    public func validate(instrument: Instrument) throws {
        guard self.instrument == instrument.rawValue, page > 0, pageSize > 0,
              totalAccounts >= 0, entries.count <= pageSize else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}

/// A rankings page together with its offline freshness, mirroring `LeaderboardPayload`.
public struct RankingsPayload: Sendable {
    public let page: Int
    public let rankings: RankingsResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Band rankings

/// One band member, as embedded in a `BandRankingEntry`'s `teamMembers`.
public struct BandTeamMember: Decodable, Sendable, Equatable {
    public let accountId: String
    public let displayName: String?
}

/// One row of `/api/rankings/bands/{bandType}`, matching `BandRankingEntry`
/// (`packages/core/src/api/serverTypes.ts:1147`).
public struct BandRankingEntry: Decodable, Sendable, Identifiable, Equatable {
    public let bandId: String
    public let teamKey: String
    public let teamMembers: [BandTeamMember]
    public let songsPlayed: Int
    public let totalChartedSongs: Int
    public let coverage: Double
    public let rawSkillRating: Double
    public let adjustedSkillRating: Double
    public let adjustedSkillRank: Int
    public let weightedRating: Double
    public let weightedRank: Int
    public let fcRate: Double
    public let fcRateRank: Int
    public let totalScore: Int
    public let totalScoreRank: Int
    public let avgAccuracy: Double
    public let fullComboCount: Int
    public let avgStars: Double
    public let bestRank: Int
    public let avgRank: Double
    public let rawWeightedRating: Double?

    public var id: String { teamKey }

    /// A readable roster label, joining members the same way the web client does.
    public var membersLabel: String {
        teamMembers
            .map { $0.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User" }
            .joined(separator: ", ")
    }

    /// Rank column for the currently selected metric.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: 1-based rank for that metric only.
    public func rank(for metric: BandRankingMetric) -> Int {
        switch metric {
        case .adjusted: adjustedSkillRank
        case .weighted: weightedRank
        case .fcrate: fcRateRank
        case .totalscore: totalScoreRank
        }
    }

    /// Raw value backing the displayed rating for the selected metric.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: Percentile fraction, score total or full-combo fraction.
    public func ratingValue(for metric: BandRankingMetric) -> Double {
        switch metric {
        case .adjusted: rawSkillRating
        case .weighted: rawWeightedRating ?? weightedRating
        case .fcrate: totalChartedSongs > 0 ? Double(fullComboCount) / Double(totalChartedSongs) : 0
        case .totalscore: Double(totalScore)
        }
    }

    /// The Bayesian-adjusted percentile value shown beside a "Top N%" pill.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: `adjustedSkillRating`/`weightedRating` only for percentile metrics.
    public func bayesianValue(for metric: BandRankingMetric) -> Double? {
        switch metric {
        case .adjusted: adjustedSkillRating
        case .weighted: weightedRating
        default: nil
        }
    }

    /// Songs-played column, which counts full combos instead under FC Rate.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: An "X / Y" label matching the web client's `getSongsLabel`.
    public func songsLabel(for metric: BandRankingMetric) -> String {
        metric == .fcrate
            ? "\(fullComboCount) / \(totalChartedSongs)"
            : "\(songsPlayed) / \(totalChartedSongs)"
    }
}

/// Response envelope for `/api/rankings/bands/{bandType}`.
public struct BandRankingsResponse: Decodable, Sendable, Equatable {
    public let bandType: String
    public let rankBy: String
    public let page: Int
    public let pageSize: Int
    public let totalTeams: Int
    public let entries: [BandRankingEntry]

    /// Pages of `pageSize' rows, always at least one even for an empty board.
    public var pageCount: Int {
        let size = max(1, pageSize)
        return totalTeams <= 0 ? 1 : (totalTeams - 1) / size + 1
    }

    /// Reject a response for the wrong band size or with an impossible row count.
    ///
    /// - Parameter bandType: Requested band size.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on a mismatched or corrupt response.
    public func validate(bandType: BandType) throws {
        guard self.bandType == bandType.rawValue, page > 0, pageSize > 0,
              totalTeams >= 0, entries.count <= pageSize else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}

/// A band rankings page together with its offline freshness.
public struct BandRankingsPayload: Sendable {
    public let page: Int
    public let rankings: BandRankingsResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Display formatting

/// Pure, testable value formatting shared by every rankings surface, mirroring
/// `rankingHelpers.ts` (`formatRating`, `formatRankingValueDisplay`,
/// `formatBayesianRatingDisplay`).
public enum RankingFormatting {
    /// Format a metric's primary rating value the way the web client's cards do.
    ///
    /// - Parameters:
    ///   - value: Raw value from `ratingValue(for:)`.
    ///   - metric: Selected rank-by metric.
    /// - Returns: A percentile ("Top 3%"), percentage ("97.3%") or grouped integer.
    public static func rating(_ value: Double, metric: RankingMetric) -> String {
        switch metric {
        case .adjusted, .weighted: percentile(value)
        case .fcrate, .maxscore: percentage(value)
        case .totalscore: wholeNumber(value)
        }
    }

    /// Format a raw 0-1 percentile as "Top N%", matching `formatPercentileTopExact`.
    ///
    /// - Parameter rawPercentile: Fraction where 0 is the very best rank.
    /// - Returns: "Top 0.03%" below one percent, otherwise a whole "Top N%".
    public static func percentile(_ rawPercentile: Double) -> String {
        guard rawPercentile.isFinite else { return "N/A" }
        let topPercent = min(max(rawPercentile * 100, 0.01), 100)
        if topPercent < 1 {
            return "Top \(topPercent.formatted(.number.precision(.fractionLength(2))))%"
        }
        return "Top \(topPercent.formatted(.number.precision(.fractionLength(0))))%"
    }

    /// Format a raw 0-1 fraction as a one-decimal percentage, matching `formatRating`.
    ///
    /// - Parameter fraction: FC Rate or Max Score fraction.
    /// - Returns: A string such as "97.3%".
    public static func percentage(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "N/A" }
        return "\((fraction * 100).formatted(.number.precision(.fractionLength(1))))%"
    }

    /// Format a whole score total with locale grouping, matching `toLocaleString`.
    ///
    /// - Parameter value: Total score, already summed by the service.
    /// - Returns: A grouped integer string such as "12,345,678".
    public static func wholeNumber(_ value: Double) -> String {
        guard value.isFinite else { return "N/A" }
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    /// Format the Bayesian-adjusted raw rating shown beside a percentile pill,
    /// matching `formatRatingValue`.
    ///
    /// - Parameter value: Raw adjusted/weighted rating.
    /// - Returns: A trimmed decimal with 1 to 4 fraction digits depending on magnitude.
    public static func bayesian(_ value: Double) -> String {
        guard value.isFinite else { return "N/A" }
        let magnitude = abs(value)
        if magnitude < 0.1 {
            var text = String(format: "%.4f", value)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text += "0" }
            return text
        }
        if magnitude < 1 { return String(format: "%.2f", value) }
        return String(format: "%.1f", value)
    }
}
