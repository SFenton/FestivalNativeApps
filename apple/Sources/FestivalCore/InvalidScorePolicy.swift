import Foundation

// MARK: - Population tiers

/// One chart's filtered population curve (web `PopulationTierData`, wire `{bc, t:[{l, t}]}`):
/// how many entries survive the invalid-score filter at each leeway.
public struct SongPopulationTiers: Decodable, Equatable, Hashable, Sendable {
    /// One changepoint: from `leeway` on, `total` entries are valid.
    public struct Tier: Decodable, Equatable, Hashable, Sendable {
        public let leeway: Double
        public let total: Int

        private enum CodingKeys: String, CodingKey {
            case leeway = "l", total = "t"
        }

        /// Create a changepoint.
        ///
        /// - Parameters:
        ///   - leeway: Leeway percentage where the total applies.
        ///   - total: Valid entries from that leeway on.
        public init(leeway: Double, total: Int) {
            self.leeway = leeway
            self.total = total
        }
    }

    /// Entries that are valid at every leeway (web `baseCount`).
    public let baseCount: Int
    /// Changepoints in ascending leeway order.
    public let tiers: [Tier]

    private enum CodingKeys: String, CodingKey {
        case baseCount = "bc", tiers = "t"
    }

    /// Create a curve.
    ///
    /// - Parameters:
    ///   - baseCount: Entries valid at every leeway.
    ///   - tiers: Ascending changepoints.
    public init(baseCount: Int, tiers: [Tier]) {
        self.baseCount = baseCount
        self.tiers = tiers
    }

    /// Decode and reject a corrupt curve (negative counts, nonfinite leeway).
    ///
    /// - Parameter decoder: One chart's compact `populationTiers` value.
    /// - Throws: Wrong types or invalid values.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        baseCount = try fields.decode(Int.self, forKey: .baseCount)
        tiers = try fields.decode([Tier].self, forKey: .tiers)
        guard baseCount >= 0,
              tiers.allSatisfy({ $0.leeway.isFinite && $0.total >= 0 }) else {
            throw FestivalAPIError.invalidCatalogue
        }
    }

    /// The filtered population at a leeway (web `getFilteredTotal`): the last
    /// changepoint at or under it, else the base count.
    ///
    /// - Parameter leeway: Settings leeway percentage.
    /// - Returns: Valid entries at that leeway.
    public func total(atLeeway leeway: Double) -> Int {
        tiers.last(where: { $0.leeway <= leeway })?.total ?? baseCount
    }
}

/// A song's population curves by service chart ID. Lenient: a malformed chart entry is
/// dropped (its fallback keeps the published total, as the web does without a curve)
/// rather than failing the whole catalogue.
public struct SongPopulationTierTable: Decodable, Equatable, Hashable, Sendable {
    public let byChart: [String: SongPopulationTiers]

    private struct ChartKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Create a table.
    ///
    /// - Parameter byChart: Curves keyed by `Instrument.rawValue`.
    public init(byChart: [String: SongPopulationTiers]) {
        self.byChart = byChart
    }

    /// Keep only well-formed chart curves.
    ///
    /// - Parameter decoder: The song's `populationTiers` object.
    public init(from decoder: any Decoder) throws {
        guard let fields = try? decoder.container(keyedBy: ChartKey.self) else {
            byChart = [:]
            return
        }
        var charts: [String: SongPopulationTiers] = [:]
        for key in fields.allKeys {
            if let curve = try? fields.decode(SongPopulationTiers.self, forKey: key) {
                charts[key.stringValue] = curve
            }
        }
        byChart = charts
    }

    /// One chart's curve.
    ///
    /// - Parameter instrument: Chart to look up.
    /// - Returns: The curve, or nil when the service sent none.
    public func tiers(for instrument: Instrument) -> SongPopulationTiers? {
        byChart[instrument.rawValue]
    }
}

// MARK: - Effective scores

/// Why a selected player's chart score was replaced, dropped or kept on Songs
/// (web `SongsPage` `InvalidReason`).
public enum InvalidScoreReason: String, Equatable, Hashable, Sendable {
    /// The raw score is invalid at the leeway; the next valid score is shown.
    case fallback
    /// The raw score is invalid and no valid score exists at the leeway; none is shown.
    case noFallback
    /// The raw score is invalid but kept because the chart's Over CHOpt Threshold
    /// filter is on.
    case overThreshold
}

/// One song's selected-player scores after the invalid-score filter.
public struct SongEffectiveScores: Equatable, Sendable {
    /// Scores to show, sort and filter by; a dropped chart has no entry.
    public let scores: [Instrument: PlayerScore]
    /// Charts whose raw score was invalid, and what happened to it.
    public let reasons: [Instrument: InvalidScoreReason]

    /// Create a result.
    ///
    /// - Parameters:
    ///   - scores: Effective scores by chart.
    ///   - reasons: Invalid charts and their outcome.
    public init(scores: [Instrument: PlayerScore], reasons: [Instrument: InvalidScoreReason] = [:]) {
        self.scores = scores
        self.reasons = reasons
    }
}

/// Settings › **Filter Invalid Scores** applied to the selected player's own scores
/// (web `SongsPage.effectiveScores` and `useScoreFilter.filterPlayerScores`): a score
/// above the chart's CHOpt ceiling at the leeway is replaced by the best valid score the
/// service precomputed (`vs`, or the legacy `validScore*` fields) or dropped, with a
/// filtered rank (`rt`) and population (`populationTiers`).
public enum InvalidScorePolicy {
    /// Whether a score is above the chart's CHOpt ceiling at a leeway (web
    /// `isScoreValid`, unrounded: `score <= maxScore × (1 + leeway / 100)`).
    ///
    /// - Parameters:
    ///   - score: The score.
    ///   - maxScore: The chart's CHOpt maximum, or nil when unknown.
    ///   - leeway: Settings leeway percentage.
    /// - Returns: True only above a known, positive maximum's ceiling.
    public static func exceedsThreshold(score: Int, maxScore: Int?, leeway: Double) -> Bool {
        guard let maxScore, maxScore > 0 else { return false }
        return Double(score) > Double(maxScore) * (1 + leeway / 100)
    }

    /// Whether a raw score is invalid at a leeway: its precomputed `minLeeway` when the
    /// service sent one, else the CHOpt ceiling.
    ///
    /// - Parameters:
    ///   - score: Raw published score.
    ///   - song: Its catalogue song (CHOpt maxima).
    ///   - leeway: Settings leeway percentage.
    /// - Returns: True when the filter rejects it.
    public static func isInvalid(_ score: PlayerScore, song: Song?, leeway: Double) -> Bool {
        if let minLeeway = score.minLeeway { return minLeeway > leeway }
        return exceedsThreshold(
            score: score.score, maxScore: song?.maxScore(for: score.instrument), leeway: leeway
        )
    }

    /// The filtered rank of a fallback (web `getFilteredRank`): the last rank tier at or
    /// under the leeway.
    ///
    /// - Parameters:
    ///   - tiers: Ascending rank changepoints.
    ///   - leeway: Settings leeway percentage.
    /// - Returns: The rank, or nil without a qualifying tier.
    public static func rank(in tiers: [PlayerRankTier]?, leeway: Double) -> Int? {
        tiers?.last(where: { $0.leeway <= leeway })?.rank
    }

    /// The first precomputed fallback valid at the leeway, substituted into the score.
    ///
    /// - Parameters:
    ///   - score: Raw invalid score with a non-empty `validScores`.
    ///   - song: Its catalogue song (population curve).
    ///   - leeway: Settings leeway percentage.
    /// - Returns: The substituted score, or nil when no variant qualifies.
    static func variantFallback(_ score: PlayerScore, song: Song?, leeway: Double) -> PlayerScore? {
        guard let variant = score.validScores?.first(where: { $0.minLeeway <= leeway }) else {
            return nil
        }
        let total = song?.populationTiers?.tiers(for: score.instrument)?.total(atLeeway: leeway)
        return PlayerScore(
            substituting: score, score: variant.score,
            accuracy: variant.accuracy ?? score.accuracy,
            isFullCombo: variant.isFullCombo ?? score.isFullCombo,
            stars: variant.stars ?? score.stars,
            rank: rank(in: variant.rankTiers, leeway: leeway) ?? score.rank,
            totalEntries: total ?? score.totalEntries
        )
    }

    /// The legacy `validScore*` fallback substituted into the score.
    ///
    /// - Parameter score: Raw invalid score with a `validScore`.
    /// - Returns: The substituted score, or nil without one.
    static func legacyFallback(_ score: PlayerScore) -> PlayerScore? {
        guard let valid = score.validScore else { return nil }
        return PlayerScore(
            substituting: score, score: valid,
            accuracy: score.validAccuracy ?? score.accuracy,
            isFullCombo: score.validIsFullCombo ?? score.isFullCombo,
            stars: score.validStars ?? score.stars,
            rank: score.validRank ?? 0,
            totalEntries: score.validTotalEntries ?? score.totalEntries
        )
    }

    /// One song's effective scores on Songs (web `SongsPage.effectiveScores`).
    ///
    /// - Parameters:
    ///   - scores: The song's raw scores by chart.
    ///   - song: Its catalogue song, or nil when not in the catalogue.
    ///   - leeway: Settings leeway percentage.
    ///   - overThreshold: Charts whose Over CHOpt Threshold filter is on: an invalid
    ///     raw score is kept and marked rather than replaced.
    /// - Returns: Effective scores and the invalid charts' reasons.
    public static func resolve(
        _ scores: [Instrument: PlayerScore], song: Song?, leeway: Double,
        overThreshold: Set<Instrument> = []
    ) -> SongEffectiveScores {
        var effective: [Instrument: PlayerScore] = [:]
        var reasons: [Instrument: InvalidScoreReason] = [:]
        for (chart, score) in scores {
            guard isInvalid(score, song: song, leeway: leeway) else {
                effective[chart] = score
                continue
            }
            if overThreshold.contains(chart) {
                effective[chart] = score
                reasons[chart] = .overThreshold
            } else if let variants = score.validScores, !variants.isEmpty {
                if let fallback = variantFallback(score, song: song, leeway: leeway) {
                    effective[chart] = fallback
                    reasons[chart] = .fallback
                } else {
                    reasons[chart] = .noFallback
                }
            } else if let fallback = legacyFallback(score) {
                effective[chart] = fallback
                reasons[chart] = .fallback
            } else {
                reasons[chart] = .noFallback
            }
        }
        return SongEffectiveScores(scores: effective, reasons: reasons)
    }

    /// The whole selected-player index on Songs.
    ///
    /// - Parameters:
    ///   - index: Raw scores by song ID and chart.
    ///   - songsById: Catalogue songs by ID.
    ///   - leeway: Settings leeway percentage.
    ///   - overThreshold: Charts whose Over CHOpt Threshold filter is on.
    /// - Returns: Effective scores by song (songs left with none are omitted).
    public static func resolve(
        index: [String: [Instrument: PlayerScore]], songsById: [String: Song], leeway: Double,
        overThreshold: Set<Instrument> = []
    ) -> [String: [Instrument: PlayerScore]] {
        var result: [String: [Instrument: PlayerScore]] = [:]
        result.reserveCapacity(index.count)
        for (songId, scores) in index {
            let resolved = resolve(
                scores, song: songsById[songId], leeway: leeway, overThreshold: overThreshold
            ).scores
            if !resolved.isEmpty { result[songId] = resolved }
        }
        return result
    }

    /// One score as Song Detail shows it (web `useScoreFilter.filterPlayerScores`): a
    /// score with a precomputed `minLeeway` uses only `validScores`; one without uses
    /// the CHOpt ceiling and the legacy `validScore*` fallback.
    ///
    /// - Parameters:
    ///   - score: Raw published score.
    ///   - song: Its catalogue song.
    ///   - leeway: Settings leeway percentage.
    /// - Returns: The effective score, or nil when it is dropped.
    public static func filtered(_ score: PlayerScore, song: Song?, leeway: Double) -> PlayerScore? {
        if let minLeeway = score.minLeeway {
            if minLeeway <= leeway { return score }
            return variantFallback(score, song: song, leeway: leeway)
        }
        guard exceedsThreshold(
            score: score.score, maxScore: song?.maxScore(for: score.instrument), leeway: leeway
        ) else { return score }
        return legacyFallback(score)
    }

    /// A song's scores as Song Detail shows them.
    ///
    /// - Parameters:
    ///   - scores: The song's raw scores by chart.
    ///   - song: Its catalogue song.
    ///   - leeway: Settings leeway percentage, or nil when the filter is off.
    /// - Returns: The raw scores without a leeway, else the filtered ones.
    public static func filtered(
        _ scores: [Instrument: PlayerScore], song: Song?, leeway: Double?
    ) -> [Instrument: PlayerScore] {
        guard let leeway else { return scores }
        return scores.compactMapValues { filtered($0, song: song, leeway: leeway) }
    }
}

// MARK: - Invalid-score indicator

/// The Songs row's invalid-score indicator and its "Filtered Score" alert (web
/// `InvalidScoreIcon`, strings `songs.invalidScore*`).
public struct InvalidScoreWarning: Equatable, Sendable {
    /// Alert title (web `songs.invalidScoreTitle`).
    public static let title = "Filtered Score"
    /// The indicator's spoken name (web `songs.invalidScoreAriaLabel`).
    public static let accessibilityLabel = "Invalid score indicator"
    /// The alert's action that opens Settings (web `songs.goToSettings`).
    public static let settingsAction = "Settings"

    /// Every described chart kept its raw score above the CHOpt ceiling (gold warning
    /// glyph); otherwise a score was replaced or dropped (red alert glyph).
    public let isOverThreshold: Bool
    /// Charts the alert describes, in Settings order.
    public let charts: [Instrument]
    /// Alert body.
    public let message: String

    /// The row's warning, or nil when the row shows no indicator (web `SongRow`
    /// `hasInvalid`): nothing invalid, or a Songs instrument whose chart is valid.
    ///
    /// - Parameters:
    ///   - songTitle: The song's title.
    ///   - reasons: Invalid charts and their outcome (``SongEffectiveScores/reasons``).
    ///   - instrumentFilter: The Songs instrument, or nil for every instrument (chips).
    ///   - visibleInstruments: Settings-visible charts; hidden charts are not described.
    /// - Returns: The indicator's tone and alert message.
    public static func make(
        songTitle: String, reasons: [Instrument: InvalidScoreReason],
        instrumentFilter: Instrument?, visibleInstruments: Set<Instrument>
    ) -> InvalidScoreWarning? {
        let entries: [(chart: Instrument, reason: InvalidScoreReason)]
        if let instrumentFilter {
            guard let reason = reasons[instrumentFilter] else { return nil }
            entries = [(instrumentFilter, reason)]
        } else {
            entries = Instrument.allCases.compactMap { chart in
                guard visibleInstruments.contains(chart), let reason = reasons[chart] else { return nil }
                return (chart, reason)
            }
        }
        guard !entries.isEmpty else { return nil }
        let names = joinedNames(entries.map(\.chart.label))
        let allOver = entries.allSatisfy { $0.reason == .overThreshold }
        let charts = entries.map(\.chart)
        if allOver {
            return InvalidScoreWarning(
                isOverThreshold: true, charts: charts,
                message: "\(songTitle) has a score on \(names) that exceeds the CHOpt maximum. "
                    + "This is the highest unfiltered invalid score."
            )
        }
        let header = "\(songTitle) has an invalid, filtered-out score on \(names)."
        let chipsView = instrumentFilter == nil
        var details: [String] = []
        let fallbacks = entries.filter { $0.reason == .fallback }
        if !fallbacks.isEmpty {
            if !chipsView {
                details.append("We are showing the next valid score here.")
            } else if fallbacks.count == 1 {
                details.append("The \(fallbacks[0].chart.label) chip reflects the next valid score.")
            } else {
                details.append("The chips for these instruments reflect the next valid score.")
            }
        }
        for entry in entries where entry.reason != .fallback {
            let name = entry.chart.label
            details.append(
                entry.reason == .overThreshold
                    ? "The \(name) score shown exceeds the CHOpt maximum."
                    : "Because there is no valid other score for \(name), the \(name) icon chip is red here."
            )
        }
        let footer = entries.count > 1
            ? "To see the absolute highest scores you've achieved, toggle off 'Filter Invalid Scores' in App Settings."
            : "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings."
        let hint = instrumentFilter.map {
            "You can also temporarily filter to '\($0.label) Over CHOpt Threshold' in the Filter modal."
        } ?? "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal "
            + "when viewing scores for a specific instrument."
        return InvalidScoreWarning(
            isOverThreshold: false, charts: charts,
            message: "\(header) \(details.joined(separator: " "))\n\n\(footer) \(hint)"
        )
    }

    /// "A", "A and B" or "A, B, and C" (web `instNames`).
    ///
    /// - Parameter names: Chart names in order.
    /// - Returns: The joined list.
    static func joinedNames(_ names: [String]) -> String {
        guard names.count > 2 else { return names.joined(separator: " and ") }
        return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
    }
}
