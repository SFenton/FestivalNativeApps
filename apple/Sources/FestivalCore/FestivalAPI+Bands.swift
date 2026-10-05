import Foundation

// MARK: - Bands reads

extension FestivalAPI {
    /// Request one page of a player's bands, optionally filtered to one group.
    ///
    /// `GET /api/player/{accountId}/bands?group=&page=&pageSize=` is a pure read:
    /// `GlobalLeaderboardPersistence.GetPlayerBandsList` degrades to an empty page
    /// when the band-search projection is missing rather than rebuilding anything
    /// (`GlobalLeaderboardPersistence.cs:3873-3896`).
    ///
    /// - Parameters:
    ///   - accountId: Public Epic account ID whose bands to list.
    ///   - group: Segmented-control filter (all/duos/trios/quads).
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page.
    /// - Returns: Validated band rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func playerBands(
        accountId: String, group: PlayerBandGroup, page: Int, pageSize: Int = 25
    ) async throws -> PlayerBandListPayload {
        let resource = PublicEndpoint.playerBands(
            accountId: accountId, group: group.rawValue, page: page, pageSize: pageSize
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(PlayerBandListResponse.self, from: payload.data)
        guard response.accountId == accountId else {
            throw FestivalAPIError.invalidBandProfile
        }
        return PlayerBandListPayload(
            page: page, list: response,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Look up one band's public ranking row by the `bandType`/`teamKey` that a
    /// rankings, player-bands or song-band-leaderboard row already carries.
    ///
    /// This calls `GET /api/rankings/bands/{bandType}?teamKey=&page=1&pageSize=1`,
    /// the same pure-read board `bandRankings` uses — never `/api/bands/{bandId}`.
    /// See `BandDetail`'s documentation for why that endpoint is unsafe to call.
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter (only ever populates
    ///     `configurations` for `Band_Duets`).
    /// - Returns: The team's full ranking row and explicit offline freshness.
    /// - Throws: `FestivalAPIError.invalidBandProfile` when the team is unknown,
    ///   or invalid parameters, service or decoding failures.
    public func bandProfile(
        bandType: BandType, teamKey: String, combo: String? = nil
    ) async throws -> BandDetailPayload {
        guard !teamKey.isEmpty else { throw FestivalAPIError.invalidBandProfile }
        let resource = PublicEndpoint.bandProfile(
            bandType: bandType.rawValue, teamKey: teamKey, combo: combo
        )
        let payload = try await read(resource)
        let envelope = try JSONDecoder().decode(BandProfileEnvelope.self, from: payload.data)
        guard envelope.bandType == bandType.rawValue, let detail = envelope.selectedBandEntry else {
            throw FestivalAPIError.invalidBandProfile
        }
        return BandDetailPayload(
            detail: detail, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Request a band's recent daily rank history.
    ///
    /// `GET /api/rankings/bands/{bandType}/{teamKey}/history?days=` is a pure read
    /// (`MetaDatabase.GetBandRankHistory`/`GetBandRankHistoryStatus`, only `SELECT`s).
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter.
    ///   - days: History window, 1 to 3650 days.
    /// - Returns: Validated history rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func bandRankHistory(
        bandType: BandType, teamKey: String, combo: String? = nil, days: Int = 30
    ) async throws -> BandRankHistoryPayload {
        let resource = PublicEndpoint.bandRankHistory(
            bandType: bandType.rawValue, teamKey: teamKey, combo: combo, days: days
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(BandRankHistoryResponse.self, from: payload.data)
        guard response.bandType == bandType.rawValue, response.teamKey == teamKey else {
            throw FestivalAPIError.invalidBandProfile
        }
        return BandRankHistoryPayload(
            response: response, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Request a band's best- and worst-performing songs.
    ///
    /// `GET /api/rankings/bands/{bandType}/{teamKey}/songs?limit=` is a pure read
    /// (`MetaDatabase.GetBandSongPerformanceExtremes`, only `SELECT`s); it can 503
    /// when the published band-song projection is not yet promoted, surfaced here
    /// as `FestivalAPIError.unavailable`.
    ///
    /// - Parameters:
    ///   - bandType: Band size the team belongs to.
    ///   - teamKey: Stable member-account-id roster key.
    ///   - combo: Optional instrument-combo filter.
    ///   - limit: Rows per extreme, 1 to 20.
    /// - Returns: Validated best/worst rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func bandSongExtremes(
        bandType: BandType, teamKey: String, combo: String? = nil, limit: Int = 5
    ) async throws -> BandSongExtremesPayload {
        let resource = PublicEndpoint.bandSongExtremes(
            bandType: bandType.rawValue, teamKey: teamKey, combo: combo, limit: limit
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(BandSongExtremesResponse.self, from: payload.data)
        guard response.bandType == bandType.rawValue, response.teamKey == teamKey else {
            throw FestivalAPIError.invalidBandProfile
        }
        return BandSongExtremesPayload(
            response: response, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Request one page of a song's band leaderboard for one band size.
    ///
    /// `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=` is a pure read
    /// (`MetaDatabase.GetSongBandLeaderboard`, only `SELECT`s).
    ///
    /// - Parameters:
    ///   - songId: Catalog identifier for the requested song.
    ///   - bandType: Band size to rank.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; 25 matches the Solo chart's page size.
    ///   - combo: Optional instrument-combo filter.
    ///   - accountId: Selected player, sent only as the `accountId` query so the service
    ///     returns that player's best band row (`selectedPlayerEntry`, a pure `SELECT`
    ///     in `MetaDatabase.GetSongBandLeaderboardEntryForAccount`); never as a
    ///     selected-profile header.
    /// - Returns: Validated band score rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func songBandLeaderboard(
        songId: String, bandType: BandType, page: Int, pageSize: Int = 25, combo: String? = nil,
        accountId: String? = nil
    ) async throws -> SongBandLeaderboardPayload {
        guard page > 0, page - 1 <= Int.max / max(1, pageSize) else {
            throw FestivalAPIError.invalidResource
        }
        let resource = PublicEndpoint.songBandLeaderboard(
            songId: songId, bandType: bandType.rawValue, top: pageSize,
            offset: (page - 1) * pageSize, combo: combo, accountId: accountId
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: payload.data)
        try response.validate(songId: songId, bandType: bandType)
        return SongBandLeaderboardPayload(
            page: page, leaderboard: response,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Read Song Detail's band previews: every band size's top rows in one request.
    ///
    /// - Parameters:
    ///   - songId: Song shown on Song Detail.
    ///   - accountId: Selected player, sent only as the `accountId` query so the service
    ///     can return that player's best band row; never as a selected-profile header.
    ///   - top: Rows per band size (1...50); the web previews use 10.
    /// - Returns: The previews with their publication provenance.
    /// - Throws: `FestivalAPIError` for invalid input, transport or a corrupt response.
    public func songBandLeaderboards(
        songId: String, accountId: String?, top: Int = 10
    ) async throws -> SongBandLeaderboardsPayload {
        let payload = try await read(
            PublicEndpoint.songBandLeaderboards(songId: songId, top: top, accountId: accountId)
        )
        let response = try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: payload.data)
        try response.validate(songId: songId)
        return SongBandLeaderboardsPayload(
            response: response, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }
}
