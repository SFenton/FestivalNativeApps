import Foundation
import FestivalCore

// MARK: - Bands reads

extension FestivalSession {
    /// Load a page of a player's bands under the same observed publication as
    /// every other tab.
    ///
    /// - Parameters:
    ///   - accountId: Public Epic account ID whose bands to list.
    ///   - group: Segmented-control filter (all/duos/trios/quads).
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page.
    /// - Returns: Validated band rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func playerBands(
        accountId: String, group: PlayerBandGroup, page: Int, pageSize: Int = 25
    ) async throws -> PlayerBandListPayload {
        let payload = try await client().playerBands(
            accountId: accountId, group: group, page: page, pageSize: pageSize
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load one band's public ranking row by its `bandType`/`teamKey`.
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter.
    /// - Returns: The team's full ranking row and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func bandProfile(
        bandType: BandType, teamKey: String, combo: String? = nil
    ) async throws -> BandDetailPayload {
        let payload = try await client().bandProfile(bandType: bandType, teamKey: teamKey, combo: combo)
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load a band's recent daily rank history.
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter.
    ///   - days: History window, 1 to 3650 days.
    /// - Returns: Validated history rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func bandRankHistory(
        bandType: BandType, teamKey: String, combo: String? = nil, days: Int = 30
    ) async throws -> BandRankHistoryPayload {
        let payload = try await client().bandRankHistory(
            bandType: bandType, teamKey: teamKey, combo: combo, days: days
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load a band's best- and worst-performing songs.
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter.
    ///   - limit: Rows per extreme, 1 to 20.
    /// - Returns: Validated best/worst rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func bandSongExtremes(
        bandType: BandType, teamKey: String, combo: String? = nil, limit: Int = 5
    ) async throws -> BandSongExtremesPayload {
        let payload = try await client().bandSongExtremes(
            bandType: bandType, teamKey: teamKey, combo: combo, limit: limit
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load a page of a song's band leaderboard for one band size.
    ///
    /// - Parameters:
    ///   - songId: Catalog identifier for the requested song.
    ///   - bandType: Band size to rank.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page.
    ///   - combo: Optional instrument-combo filter.
    /// - Returns: Validated band score rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func songBandLeaderboard(
        songId: String, bandType: BandType, page: Int, pageSize: Int = 25, combo: String? = nil
    ) async throws -> SongBandLeaderboardPayload {
        let payload = try await client().songBandLeaderboard(
            songId: songId, bandType: bandType, page: page, pageSize: pageSize, combo: combo
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }
}
