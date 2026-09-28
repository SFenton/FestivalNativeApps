import Foundation

/// A score row in the service's solo chart response.
public struct LeaderboardEntry: Decodable, Sendable, Identifiable, Equatable {
    public let accountId: String
    public let displayName: String?
    public let score: Int
    public let rank: Int
    public let localRank: Int?
    public let accuracy: Double?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let season: Int?
    public let difficulty: Double?

    public var id: String { accountId }

    /// Build a synthetic row from already-loaded data — e.g. the selected
    /// player's own score index (`FestivalSession.selectedPlayerScores`) — for a
    /// spotlight footer that needs no extra network read. `Decodable`'s
    /// synthesized `init(from:)` suppresses the automatic memberwise
    /// initializer, so this is declared explicitly.
    ///
    /// - Parameters:
    ///   - accountId: Selected player's public account key.
    ///   - displayName: Selected player's display name.
    ///   - score: Score value to show.
    ///   - rank: 1-based rank on this song/instrument's board.
    ///   - localRank: Rank within only the locally-visible entries, if known.
    ///   - accuracy: Accuracy fraction, if known.
    ///   - isFullCombo: Full-combo flag, if known.
    ///   - stars: Star rating, if known.
    ///   - season: Season number, if known.
    ///   - difficulty: Difficulty tier, if known.
    public init(
        accountId: String, displayName: String?, score: Int, rank: Int,
        localRank: Int? = nil, accuracy: Double?, isFullCombo: Bool?, stars: Int?,
        season: Int?, difficulty: Double?
    ) {
        self.accountId = accountId
        self.displayName = displayName
        self.score = score
        self.rank = rank
        self.localRank = localRank
        self.accuracy = accuracy
        self.isFullCombo = isFullCombo
        self.stars = stars
        self.season = season
        self.difficulty = difficulty
    }
}

/// Pagination metadata comes from local entries, not from the current rows.
public struct LeaderboardResponse: Decodable, Sendable, Equatable {
    public let songId: String
    public let instrument: String
    public let showLeaderboardEntryTotals: Bool?
    public let count: Int
    public let totalEntries: Int
    public let localEntries: Int?
    public let entries: [LeaderboardEntry]

    /// Compute at least one page using the service's local/total fallback.
    ///
    /// - Returns: Number of 25-row pages, even when the current response is empty.
    public var pageCount: Int {
        let total = max(0, localEntries ?? totalEntries)
        return total == 0 ? 1 : (total - 1) / 25 + 1
    }

    /// Reject mismatched request data and invalid counts before the UI renders rows.
    ///
    /// - Parameters:
    ///   - songId: Requested catalog song.
    ///   - instrument: Requested solo chart.
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on a corrupt wire response.
    public func validate(songId: String, instrument: Instrument) throws {
        guard self.songId == songId,
              self.instrument == instrument.rawValue,
              count == entries.count, count >= 0,
              totalEntries >= 0,
              localEntries.map({ $0 >= 0 }) ?? true else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}

/// A page's response and its offline freshness are independent of the URL state.
public struct LeaderboardPayload: Sendable {
    public let page: Int
    public let leaderboard: LeaderboardResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

/// Pure navigation rules shared between deep links, cached pages and pagination.
public enum LeaderboardPaging {
    /// Prefer an explicit link over last-viewed page state.
    ///
    /// - Parameters:
    ///   - explicitPage: Incoming deep-link page, if valid.
    ///   - cachedPage: Last in-process page for this chart.
    /// - Returns: One-based page to request.
    public static func initial(explicitPage: Int?, cachedPage: Int?) -> Int {
        if let explicitPage, explicitPage > 0 { return explicitPage }
        if let cachedPage, cachedPage > 0 { return cachedPage }
        return 1
    }

    /// Correct a stale bookmark after local entry totals are known.
    ///
    /// - Parameters:
    ///   - requested: One-based page requested by the user.
    ///   - totalPages: Current response's maximum valid page.
    /// - Returns: A one-based page inside the available range.
    public static func corrected(requested: Int, totalPages: Int) -> Int {
        min(max(1, requested), max(1, totalPages))
    }

    /// Map a 1-based rank to the page that contains it, mirroring the web client's
    /// `getLeaderboardPageForRank` (`rankingHelpers.ts:48-51`). Used to jump a
    /// paginated board straight to the selected player's own page.
    ///
    /// - Parameters:
    ///   - rank: 1-based rank, e.g. from `AccountRankingEntry.rank(for:)`.
    ///   - pageSize: Rows per page for this board.
    /// - Returns: A 1-based page number; falls back to 1 for a non-positive input.
    public static func page(forRank rank: Int, pageSize: Int) -> Int {
        guard rank > 0, pageSize > 0 else { return 1 }
        return (rank - 1) / pageSize + 1
    }
}

extension FestivalAPI {
    /// Request one 25-row chart page under the current publication.
    ///
    /// - Parameters:
    ///   - songId: Song identifier from the catalog.
    ///   - instrument: Solo chart identifier.
    ///   - page: One-based page number.
    ///   - top: Rows per request; ten for a Detail preview or 25 for a full page.
    ///   - leeway: Optional percentage from an enabled invalid-score filter.
    /// - Returns: Validated leaderboard rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func leaderboard(
        songId: String, instrument: Instrument, page: Int,
        top: Int = 25, leeway: Double? = nil
    ) async throws -> LeaderboardPayload {
        guard (1...25).contains(top), page > 0, page - 1 <= Int.max / top else {
            throw FestivalAPIError.invalidResource
        }
        let resource = PublicEndpoint.leaderboard(
            songId: songId, instrument: instrument.rawValue,
            top: top, offset: (page - 1) * top, leeway: leeway
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(LeaderboardResponse.self, from: payload.data)
        try response.validate(songId: songId, instrument: instrument)
        guard response.count <= top else {
            throw FestivalAPIError.invalidLeaderboard
        }
        try await rememberUnverified(payload, for: resource)
        return LeaderboardPayload(
            page: page, leaderboard: response,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }
}
