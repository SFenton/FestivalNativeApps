import Foundation

// MARK: - Combo rankings wire types

/// One row of `/api/rankings/combo` (web `ComboRankingEntry`): a single rank for the
/// requested metric plus the account's combined values across the combo's instruments.
///
/// Live-probed 2026-10-10 (`combo=03`, `rankBy=totalscore`): `totalChartedSongs` is the sum
/// of the combo's charts (1466 for Lead + Bass) and `fcRate` is `fullComboCount /
/// songsPlayed`.
public struct ComboRankingEntry: Decodable, Sendable, Equatable {
    public let rank: Int
    public let accountId: String
    public let displayName: String?
    public let adjustedRating: Double
    public let weightedRating: Double
    public let fcRate: Double
    public let totalScore: Int
    public let maxScorePercent: Double
    public let songsPlayed: Int
    public let totalChartedSongs: Int
    public let fullComboCount: Int
}

/// Response envelope for `/api/rankings/combo?combo=&rankBy=&page=&pageSize=`.
public struct ComboRankingsResponse: Decodable, Sendable, Equatable {
    public let comboId: String
    public let rankBy: String
    public let page: Int
    public let pageSize: Int
    public let totalAccounts: Int
    public let entries: [ComboRankingEntry]

    /// Reject a response for another combo or with an impossible row count.
    ///
    /// - Parameter combo: Requested combo.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on a mismatched or corrupt response.
    public func validate(combo: RankingCombo) throws {
        guard comboId.caseInsensitiveCompare(combo.comboId) == .orderedSame, page > 0, pageSize > 0,
              totalAccounts >= 0, entries.count <= pageSize else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }

    /// The page as a ``RankingsResponse`` of ``AccountRankingEntry`` rows ranked by
    /// `metric`, so combo boards reuse the one ranking row (pattern `leaderboard-row`).
    ///
    /// - Parameter metric: The metric the page was read for.
    /// - Returns: The same page; `instrument` carries the combo id.
    public func rankings(metric: RankingMetric) -> RankingsResponse {
        RankingsResponse(
            instrument: comboId, rankBy: rankBy, page: page, pageSize: pageSize,
            totalAccounts: totalAccounts, entries: entries.map { AccountRankingEntry(combo: $0, metric: metric) }
        )
    }
}

/// One account's own row on a combo board (`/api/rankings/combo/{accountId}?combo=&rankBy=`).
public struct PlayerComboRanking: Decodable, Sendable, Equatable {
    public let entry: ComboRankingEntry
    public let comboId: String
    public let totalAccounts: Int

    private enum CodingKeys: String, CodingKey {
        case comboId, totalAccounts
    }

    /// Decode the flat single-account envelope, reusing ``ComboRankingEntry``'s fields.
    ///
    /// - Parameter decoder: Raw `/api/rankings/combo/{accountId}` response.
    /// - Throws: Missing or mistyped wire fields.
    public init(from decoder: any Decoder) throws {
        entry = try ComboRankingEntry(from: decoder)
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        comboId = try fields.decode(String.self, forKey: .comboId)
        totalAccounts = try fields.decode(Int.self, forKey: .totalAccounts)
    }
}

// MARK: - Mapping onto the instrument row

extension AccountRankingEntry {
    /// A combo row drawn by the instrument ranking row: every metric's rank is the combo
    /// board's one rank, and each value maps as the web's `FullRankingsPage`
    /// `getDisplayRating` does (Adjusted → `adjustedRating`, FC Rate → `fcRate`, …).
    ///
    /// Under FC Rate the songs column reads full combos over songs played (web
    /// `getDisplaySongsLabel` for combos), so ``songsLabel(for:)`` and
    /// ``ratingValue(for:)`` both divide by songs played there.
    ///
    /// - Parameters:
    ///   - combo: The combo board's row.
    ///   - metric: The metric the board was read for.
    public init(combo: ComboRankingEntry, metric: RankingMetric) {
        accountId = combo.accountId
        displayName = combo.displayName
        songsPlayed = combo.songsPlayed
        totalChartedSongs = metric == .fcrate ? combo.songsPlayed : combo.totalChartedSongs
        coverage = combo.totalChartedSongs > 0 ? Double(combo.songsPlayed) / Double(combo.totalChartedSongs) : 0
        rawSkillRating = combo.adjustedRating
        adjustedSkillRating = combo.adjustedRating
        adjustedSkillRank = combo.rank
        weightedRating = combo.weightedRating
        weightedRank = combo.rank
        fcRate = combo.fcRate
        fcRateRank = combo.rank
        totalScore = combo.totalScore
        totalScoreRank = combo.rank
        maxScorePercent = combo.maxScorePercent
        maxScorePercentRank = combo.rank
        avgAccuracy = 0
        fullComboCount = combo.fullComboCount
        avgStars = 0
        bestRank = 0
        avgRank = 0
        rawMaxScorePercent = nil
        rawWeightedRating = nil
    }
}

// MARK: - Combo reads

extension FestivalAPI {
    /// Request one page of a public combo rankings board.
    ///
    /// `GET /api/rankings/combo?combo=&rankBy=&page=&pageSize=` is a pure, keyless read
    /// (`FSTService/Api/RankingsEndpoints.cs:528`).
    ///
    /// - Parameters:
    ///   - combo: The within-group combo being ranked.
    ///   - rankBy: Sort metric.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; five for a Compete preview or 25 for a full page.
    /// - Returns: The page as instrument-shaped rows with offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func comboRankings(
        combo: RankingCombo, rankBy: RankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> RankingsPayload {
        guard page > 0, (1...200).contains(pageSize) else {
            throw FestivalAPIError.invalidResource
        }
        let resource = PublicEndpoint.comboRankings(
            comboId: combo.comboId, rankBy: rankBy.rawValue, page: page, pageSize: pageSize
        )
        let payload = try await read(resource)
        let response: ComboRankingsResponse
        do {
            response = try JSONDecoder().decode(ComboRankingsResponse.self, from: payload.data)
        } catch is DecodingError {
            throw FestivalAPIError.invalidLeaderboard
        }
        try response.validate(combo: combo)
        try await rememberUnverified(payload, for: resource)
        return RankingsPayload(
            page: page, rankings: response.rankings(metric: rankBy),
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Read one account's own row on a combo board.
    ///
    /// `GET /api/rankings/combo/{accountId}?combo=&rankBy=` is a pure, keyless read
    /// (`FSTService/Api/RankingsEndpoints.cs:587`); its 404 means the account has no rank
    /// on this combo.
    ///
    /// - Parameters:
    ///   - combo: The within-group combo.
    ///   - accountId: Validated public account key.
    ///   - rankBy: The metric the board is ranked by.
    /// - Returns: The row as an instrument-shaped ranking, or an explicit unranked state.
    /// - Throws: Invalid parameters, transport failures or malformed wire responses;
    ///   never for an account with no rank on this combo (see `state`).
    public func playerComboRanking(
        combo: RankingCombo, accountId: String, rankBy: RankingMetric
    ) async throws -> PlayerInstrumentRankingPayload {
        guard ProfileSearchText.isValidAccountId(accountId) else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let resource = PublicEndpoint.playerComboRanking(
            comboId: combo.comboId, accountId: accountId, rankBy: rankBy.rawValue
        )
        do {
            let payload = try await read(resource)
            let ranking = try JSONDecoder().decode(PlayerComboRanking.self, from: payload.data)
            guard ranking.comboId.caseInsensitiveCompare(combo.comboId) == .orderedSame,
                  ranking.entry.accountId.caseInsensitiveCompare(accountId) == .orderedSame,
                  ranking.totalAccounts >= 0 else {
                throw FestivalAPIError.invalidLeaderboard
            }
            return PlayerInstrumentRankingPayload(
                ranking: PlayerInstrumentRanking(
                    entry: AccountRankingEntry(combo: ranking.entry, metric: rankBy),
                    instrument: ranking.comboId, totalRankedAccounts: ranking.totalAccounts
                ),
                state: .available,
                publicationId: payload.publicationId,
                observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
            )
        } catch FestivalAPIError.httpStatus(404) {
            let current = try await publication()
            return PlayerInstrumentRankingPayload(
                ranking: nil, state: .unranked, publicationId: nil,
                observedPublicationId: current.publicationId, isStale: false
            )
        } catch is DecodingError {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}
