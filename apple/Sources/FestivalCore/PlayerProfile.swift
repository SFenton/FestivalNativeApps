import Foundation

/// The service's single-instrument hex code, not a band or multi-chart combo.
enum PlayerInstrumentCode {
    /// Decode exactly one of the nine source-defined solo instrument bits.
    ///
    /// - Parameter hex: Canonical two- or three-digit hex combo from the wire.
    /// - Returns: Validated native solo chart.
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for a composite or unknown bit.
    static func instrument(for hex: String) throws -> Instrument {
        guard (2...3).contains(hex.count),
              let mask = Int(hex, radix: 16),
              mask > 0, mask.nonzeroBitCount == 1,
              mask.trailingZeroBitCount < Instrument.allCases.count,
              hex.lowercased() == String(format: "%02x", mask) else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        return Instrument.allCases[mask.trailingZeroBitCount]
    }
}

/// One changepoint in a precomputed valid score's filtered rank.
public struct PlayerRankTier: Decodable, Equatable, Sendable {
    public let leeway: Double
    public let rank: Int

    private enum CodingKeys: String, CodingKey {
        case leeway = "l", rank = "r"
    }

    /// Decode the source's compact leeway/rank pair.
    ///
    /// - Parameter decoder: One precomputed rank tier.
    /// - Throws: Wrong or absent wire fields.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        leeway = try fields.decode(Double.self, forKey: .leeway)
        rank = try fields.decode(Int.self, forKey: .rank)
    }

    /// Reject a corrupt threshold before filtering any visible score.
    ///
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for nonfinite or negative data.
    public func validate() throws {
        guard leeway.isFinite, rank >= 0 else {
            throw FestivalAPIError.invalidPlayerProfile
        }
    }
}

/// A historical valid score held separately from the current score.
public struct PlayerValidScoreVariant: Decodable, Equatable, Sendable {
    public let score: Int
    public let accuracy: Double?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let minLeeway: Double
    public let rankTiers: [PlayerRankTier]?

    private enum CodingKeys: String, CodingKey {
        case score = "sc", accuracy = "acc", isFullCombo = "fc"
        case stars = "st", minLeeway = "ml", rankTiers = "rt"
    }

    /// Preserve fallback rank tiers without applying Settings leeway prematurely.
    ///
    /// - Parameter decoder: One precomputed `vs` row.
    /// - Throws: Malformed or missing compact wire fields.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        score = try fields.decode(Int.self, forKey: .score)
        accuracy = try fields.decodeIfPresent(Double.self, forKey: .accuracy)
            .map { $0 * 1_000 }
        isFullCombo = try fields.decodeIfPresent(Bool.self, forKey: .isFullCombo)
        stars = try fields.decodeIfPresent(Int.self, forKey: .stars)
        minLeeway = try fields.decode(Double.self, forKey: .minLeeway)
        rankTiers = try fields.decodeIfPresent([PlayerRankTier].self, forKey: .rankTiers)
    }

    /// Validate every historical value before the profile is shown.
    ///
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for invalid fallback data.
    public func validate() throws {
        guard score >= 0, score <= Int(Int32.max), minLeeway.isFinite,
              accuracy.map({ $0.isFinite && (0...1_000_000).contains($0) }) ?? true,
              stars.map({ (0...6).contains($0) }) ?? true else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        for tier in rankTiers ?? [] {
            try tier.validate()
        }
    }
}

/// One validated compact-wire score; optional flags are never inferred from accuracy.
public struct PlayerScore: Decodable, Equatable, Sendable {
    public let songId: String
    public let instrument: Instrument
    public let score: Int
    public let accuracy: Double?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let season: Int?
    public let difficulty: Double?
    public let percentile: Double?
    public let rank: Int?
    public let totalEntries: Int?
    public let isValid: Bool?
    public let validScore: Int?
    public let validAccuracy: Double?
    public let validIsFullCombo: Bool?
    public let minLeeway: Double?
    public let validScores: [PlayerValidScoreVariant]?
    public let endTime: String?
    public let lastPlayedAt: String?
    public let validLastPlayedAt: String?

    private enum CodingKeys: String, CodingKey {
        case songId = "si", instrument = "ins", score = "sc", accuracy = "acc"
        case isFullCombo = "fc", stars = "st", season = "sn", difficulty = "dif"
        case percentile = "pct", rank = "rk", totalEntries = "te"
        case isValid, validScore, validAccuracy, validIsFullCombo
        case minLeeway = "ml", validScores = "vs", endTime = "et"
        case lastPlayedAt = "lp", validLastPlayedAt = "vlp"
    }

    /// Expand only the service's compact score keys and accuracy scale.
    ///
    /// - Parameter decoder: Actual precomputed or endpoint fallback wire row.
    /// - Throws: Invalid hex combo, wrong field type or missing score identifier.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        songId = try fields.decode(String.self, forKey: .songId)
        instrument = try PlayerInstrumentCode.instrument(
            for: fields.decode(String.self, forKey: .instrument)
        )
        score = try fields.decode(Int.self, forKey: .score)
        accuracy = try fields.decodeIfPresent(Double.self, forKey: .accuracy)
            .map { $0 * 1_000 }
        isFullCombo = try fields.decodeIfPresent(Bool.self, forKey: .isFullCombo)
        stars = try fields.decodeIfPresent(Int.self, forKey: .stars)
        season = try fields.decodeIfPresent(Int.self, forKey: .season)
        difficulty = try fields.decodeIfPresent(Double.self, forKey: .difficulty)
        let rawPercentile = try fields.decodeIfPresent(Double.self, forKey: .percentile)
        percentile = rawPercentile == -1 ? nil : rawPercentile
        rank = try fields.decodeIfPresent(Int.self, forKey: .rank)
        totalEntries = try fields.decodeIfPresent(Int.self, forKey: .totalEntries)
        isValid = try fields.decodeIfPresent(Bool.self, forKey: .isValid)
        validScore = try fields.decodeIfPresent(Int.self, forKey: .validScore)
        validAccuracy = try fields.decodeIfPresent(Double.self, forKey: .validAccuracy)
            .map { $0 * 1_000 }
        validIsFullCombo = try fields.decodeIfPresent(Bool.self, forKey: .validIsFullCombo)
        minLeeway = try fields.decodeIfPresent(Double.self, forKey: .minLeeway)
        validScores = try fields.decodeIfPresent(
            [PlayerValidScoreVariant].self, forKey: .validScores
        )
        endTime = try fields.decodeIfPresent(String.self, forKey: .endTime)
        lastPlayedAt = try fields.decodeIfPresent(String.self, forKey: .lastPlayedAt)
        validLastPlayedAt = try fields.decodeIfPresent(
            String.self, forKey: .validLastPlayedAt
        )
    }

    /// Reject corrupt score data before constructing Songs card indexes.
    ///
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for invalid metrics or identity.
    public func validate() throws {
        guard !songId.isEmpty, songId.count <= 200,
              !ProfileSearchText.containsUnsafeScalar(songId),
              score >= 0, score <= Int(Int32.max),
              rank.map({ $0 >= 0 }) ?? true,
              totalEntries.map({ $0 >= 0 }) ?? true,
              stars.map({ (0...6).contains($0) }) ?? true,
              season.map({ $0 >= 0 }) ?? true,
              validScore.map({ $0 >= 0 && $0 <= Int(Int32.max) }) ?? true,
              accuracy.map({ $0.isFinite && (0...1_000_000).contains($0) }) ?? true,
              validAccuracy.map({ $0.isFinite && (0...1_000_000).contains($0) }) ?? true,
              difficulty.map({ $0.isFinite && $0 >= 0 }) ?? true,
              minLeeway.map(\.isFinite) ?? true,
              percentile.map({ $0.isFinite && (0...100).contains($0) }) ?? true else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        for variant in validScores ?? [] {
            try variant.validate()
        }
    }
}

/// HTTP 200 public scores do not prove registration; 202 explicitly means syncing.
public enum PlayerProfileState: Sendable, Equatable {
    case available
    case syncing
}

/// Server's compact player-profile envelope, never a tracked or selected identity.
public struct PlayerProfileResponse: Decodable, Sendable, Equatable {
    static let wireByteLimit = 16_000_000

    public let accountId: String
    public let displayName: String?
    public let totalScores: Int
    public let scores: [PlayerScore]
    public let status: String?
    public let notYetPublished: Bool?

    private enum CodingKeys: String, CodingKey {
        case accountId, displayName, totalScores, scores, status, notYetPublished
    }

    private struct ScoreKey: Hashable {
        let songId: String
        let instrument: Instrument
    }

    /// Retain a nullable server name without mistaking outer spaces for identity.
    ///
    /// - Parameter decoder: Compact public profile or HTTP 202 syncing envelope.
    /// - Throws: Decoding errors or an unsafe reported display name.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try fields.decode(String.self, forKey: .accountId)
        let rawName = try fields.decodeIfPresent(String.self, forKey: .displayName)
        if let rawName, ProfileSearchText.containsUnsafeScalar(rawName) {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let trimmedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmedName?.isEmpty == true ? nil : trimmedName
        totalScores = try fields.decode(Int.self, forKey: .totalScores)
        scores = try fields.decode([PlayerScore].self, forKey: .scores)
        status = try fields.decodeIfPresent(String.self, forKey: .status)
        notYetPublished = try fields.decodeIfPresent(Bool.self, forKey: .notYetPublished)
    }

    /// Validate the requested account, all rows and a distinct syncing envelope.
    ///
    /// - Parameter requestedAccountId: Validated account ID from a search result.
    /// - Returns: Available public scores or explicitly syncing, never inferred registration.
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for corrupt or mixed-identity data.
    public func validate(requestedAccountId: String) throws -> PlayerProfileState {
        guard ProfileSearchText.isValidAccountId(requestedAccountId),
              ProfileSearchText.isValidAccountId(accountId),
              accountId.caseInsensitiveCompare(requestedAccountId) == .orderedSame,
              (0...20_000).contains(totalScores), totalScores == scores.count,
              displayName.map({
                  !$0.isEmpty && $0.count <= 200
              }) ?? true else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        if status == "syncing" {
            guard notYetPublished == true, scores.isEmpty else {
                throw FestivalAPIError.invalidPlayerProfile
            }
            return .syncing
        }
        guard status == nil, notYetPublished != true else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        var seen = Set<ScoreKey>()
        for row in scores {
            try row.validate()
            guard seen.insert(ScoreKey(songId: row.songId, instrument: row.instrument)).inserted
            else {
                throw FestivalAPIError.invalidPlayerProfile
            }
        }

        return .available
    }

    /// Build one lookup per validated profile, not a linear scan for every visible row.
    ///
    /// - Parameter requestedAccountId: Account that must own every indexed score.
    /// - Returns: Song and solo-instrument keys mapped to their original score rows.
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` for an unvalidated or syncing response.
    public func scoreIndex(
        requestedAccountId: String
    ) throws -> [String: [Instrument: PlayerScore]] {
        guard try validate(requestedAccountId: requestedAccountId) == .available else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        var index: [String: [Instrument: PlayerScore]] = [:]
        for row in scores {
            index[row.songId, default: [:]][row.instrument] = row
        }
        return index
    }
}

/// One validated profile read with independent publication and syncing state.
public struct PlayerProfilePayload: Sendable {
    public let profile: PlayerProfileResponse
    public let state: PlayerProfileState
    public let publicationId: Int?
    public let observedPublicationId: Int
}

// MARK: - Client-side aggregation

/// One row contributing to an overall or per-instrument aggregate.
private struct AggregatedRow {
    let songId: String
    let instrument: Instrument
    let isFullCombo: Bool
    let stars: Int
    let accuracy: Double?
    let rank: Int?
}

/// Player-page summary computed only from the compact `scores` array, mirroring the
/// source's `computeOverallStats` without a call to the forbidden player-stats GET.
public struct PlayerOverallStats: Equatable, Sendable {
    public let songsPlayed: Int
    public let fullComboCount: Int
    public let fullComboPercent: Double
    public let goldStarCount: Int
    public let averageAccuracy: Double?
    public let bestRank: Int?
    public let bestRankSongId: String?
    public let bestRankInstrument: Instrument?
}

/// Per-instrument summary computed only from the compact `scores` array, mirroring
/// the source's `computeInstrumentStats` without a call to the forbidden stats GET.
public struct PlayerInstrumentStats: Equatable, Sendable {
    public let instrument: Instrument
    public let songsPlayed: Int
    public let fullComboCount: Int
    public let fullComboPercent: Double
    public let goldStarCount: Int
    public let fiveStarCount: Int
    public let averageAccuracy: Double?
    public let bestRank: Int?
    public let bestRankSongId: String?
}

/// Shared arithmetic for both the overall and the per-instrument summary.
private func aggregate(_ rows: [AggregatedRow]) -> (
    fullComboCount: Int, fullComboPercent: Double, goldStarCount: Int,
    fiveStarCount: Int, averageAccuracy: Double?,
    bestRank: Int?, bestRankSongId: String?, bestRankInstrument: Instrument?
) {
    let fullComboCount = rows.filter(\.isFullCombo).count
    let fullComboPercent = rows.isEmpty ? 0
        : (Double(fullComboCount) / Double(rows.count) * 1_000).rounded(.down) / 10
    let goldStarCount = rows.filter { $0.stars >= 6 }.count
    let fiveStarCount = rows.filter { $0.stars == 5 }.count
    let accuracies = rows.compactMap(\.accuracy).filter { $0 > 0 }
    let averageAccuracy = accuracies.isEmpty ? nil
        : accuracies.reduce(0, +) / Double(accuracies.count)
    let ranked = rows.filter { ($0.rank ?? 0) > 0 }
    let bestRank = ranked.map { $0.rank! }.min()
    let bestRankRow = bestRank.flatMap { best in ranked.first { $0.rank == best } }
    return (
        fullComboCount, fullComboPercent, goldStarCount, fiveStarCount, averageAccuracy,
        bestRank, bestRankRow?.songId, bestRankRow?.instrument
    )
}

extension PlayerProfileResponse {
    /// Aggregate every visible-instrument score into one player-page summary.
    ///
    /// - Parameter visibleInstruments: Settings-visible solo charts.
    /// - Returns: Zeroed totals for a profile with no visible-instrument scores.
    public func overallStats(visibleInstruments: Set<Instrument>) -> PlayerOverallStats {
        let rows = scores.filter { visibleInstruments.contains($0.instrument) }.map {
            AggregatedRow(
                songId: $0.songId, instrument: $0.instrument,
                isFullCombo: $0.isFullCombo == true, stars: $0.stars ?? 0,
                accuracy: $0.accuracy, rank: $0.rank
            )
        }
        let totals = aggregate(rows)
        return PlayerOverallStats(
            songsPlayed: Set(rows.map(\.songId)).count,
            fullComboCount: totals.fullComboCount, fullComboPercent: totals.fullComboPercent,
            goldStarCount: totals.goldStarCount, averageAccuracy: totals.averageAccuracy,
            bestRank: totals.bestRank, bestRankSongId: totals.bestRankSongId,
            bestRankInstrument: totals.bestRankInstrument
        )
    }

    /// Aggregate only one instrument's scores into its player-page summary.
    ///
    /// - Parameter instrument: Solo chart to summarize.
    /// - Returns: Zeroed totals when this instrument has no recorded scores.
    public func instrumentStats(_ instrument: Instrument) -> PlayerInstrumentStats {
        let rows = scores.filter { $0.instrument == instrument }.map {
            AggregatedRow(
                songId: $0.songId, instrument: $0.instrument,
                isFullCombo: $0.isFullCombo == true, stars: $0.stars ?? 0,
                accuracy: $0.accuracy, rank: $0.rank
            )
        }
        let totals = aggregate(rows)
        return PlayerInstrumentStats(
            instrument: instrument, songsPlayed: rows.count,
            fullComboCount: totals.fullComboCount, fullComboPercent: totals.fullComboPercent,
            goldStarCount: totals.goldStarCount, fiveStarCount: totals.fiveStarCount,
            averageAccuracy: totals.averageAccuracy,
            bestRank: totals.bestRank, bestRankSongId: totals.bestRankSongId
        )
    }
}

// MARK: - Percentile distribution

/// Songs whose leaderboard placement falls in one "Top N%" band, for the per-instrument
/// percentile chart (the web's percentile table, `PlayerPercentileTable.tsx`).
public struct PlayerPercentileBucket: Equatable, Sendable, Identifiable {
    /// Upper bound of the band: the song placed within the top `topPercent`%.
    public let topPercent: Int
    /// Number of the player's songs in `(previous threshold, topPercent]`.
    public let count: Int

    public var id: Int { topPercent }
}

extension PlayerProfileResponse {
    /// Band upper bounds, matching the web's `pctThresholds` (`playerStats.ts:69`).
    public static let percentileThresholds = [
        1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100,
    ]

    /// Distribution of one instrument's placements, computed like the web's
    /// `computeInstrumentStats` (`pages/player/helpers/playerStats.ts:54-79`): each
    /// score with a rank and a field size contributes `rank / totalEntries`, counted
    /// in the first band whose upper bound it does not exceed. Empty bands are
    /// omitted, as on the web.
    ///
    /// - Parameter instrument: Solo chart to summarize.
    /// - Returns: Non-empty bands, best (smallest) first.
    public func percentileBuckets(_ instrument: Instrument) -> [PlayerPercentileBucket] {
        let fractions: [Double] = scores.compactMap { score in
            guard score.instrument == instrument, let rank = score.rank, rank > 0,
                  let entries = score.totalEntries, entries > 0 else { return nil }
            return Double(rank) / Double(entries) * 100
        }
        var previous = 0
        var buckets: [PlayerPercentileBucket] = []
        for threshold in Self.percentileThresholds {
            let lower = Double(previous)
            let upper = Double(threshold)
            let count = fractions.filter { $0 > lower && $0 <= upper }.count
            if count > 0 { buckets.append(PlayerPercentileBucket(topPercent: threshold, count: count)) }
            previous = threshold
        }
        return buckets
    }
}

extension FestivalAPI {
    /// Fetch public compact scores without selected-profile or registration headers.
    ///
    /// - Parameter accountId: Validated account key from a separate search result.
    /// - Returns: Publication provenance and explicit 202 or available-empty state.
    /// - Throws: HTTP, publication, cancellation or invalid compact-wire errors.
    public func playerProfile(accountId: String) async throws -> PlayerProfilePayload {
        guard ProfileSearchText.isValidAccountId(accountId) else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let payload = try await read(.player(accountId: accountId))
        try Task.checkCancellation()
        guard !payload.isStale,
              payload.data.count <= PlayerProfileResponse.wireByteLimit else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        do {
            let profile = try JSONDecoder().decode(
                PlayerProfileResponse.self, from: payload.data
            )
            let state = try profile.validate(requestedAccountId: accountId)
            guard (state == .syncing && payload.httpStatus == 202)
                || (state == .available && payload.httpStatus == 200) else {
                throw FestivalAPIError.invalidPlayerProfile
            }
            try Task.checkCancellation()
            return PlayerProfilePayload(
                profile: profile, state: state,
                publicationId: payload.publicationId,
                observedPublicationId: payload.observedPublicationId
            )
        } catch is DecodingError {
            throw FestivalAPIError.invalidPlayerProfile
        }
    }
}
