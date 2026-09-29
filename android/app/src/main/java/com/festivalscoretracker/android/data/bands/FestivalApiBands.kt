package com.festivalscoretracker.android.data.bands

import com.festivalscoretracker.android.core.bands.BandDetail
import com.festivalscoretracker.android.core.bands.BandProfileEnvelope
import com.festivalscoretracker.android.core.bands.BandRankHistoryResponse
import com.festivalscoretracker.android.core.bands.BandSongExtremesResponse
import com.festivalscoretracker.android.core.bands.BandText
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Band endpoints

/**
 * Allowlisted keyless band GETs (`.agents/platforms/service-safety.md`). Every
 * route here only `SELECT`s: `GetPlayerBandsList` degrades to an empty page
 * instead of rebuilding its projection, and Band Detail reads the rankings board
 * filtered by `teamKey` (`GetBandTeamRanking`). Band search, `/api/bands/{bandId}`
 * and the bare `/api/rankings/bands/{bandType}/{teamKey}` can write on a GET and
 * have no builder here.
 */
object BandEndpoints {
    /**
     * `GET /api/player/{accountId}/bands?group=&page=&pageSize=`.
     *
     * @param accountId Public account.
     * @param group Group filter.
     * @param page One-based page.
     * @param pageSize Rows, 1–100.
     * @return Endpoint.
     */
    fun playerBands(accountId: String, group: PlayerBandGroup, page: Int, pageSize: Int): ServiceEndpoint {
        if (!BandText.isValidMemberId(accountId) || page < 1 || pageSize !in 1..100) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(
            listOf("player", accountId, "bands"),
            listOf("group" to group.wireId, "page" to page.toString(), "pageSize" to pageSize.toString()),
        )
    }

    /**
     * `GET /api/rankings/bands/{bandType}?teamKey=&rankBy=adjusted&page=1&pageSize=1` (safe band lookup).
     *
     * @param bandType Band size.
     * @param teamKey Member-account roster key.
     * @return Endpoint.
     */
    fun bandProfile(bandType: BandType, teamKey: String): ServiceEndpoint {
        requireTeamKey(teamKey)
        return ServiceEndpoint.Feature(
            listOf("rankings", "bands", bandType.wireId),
            listOf("teamKey" to teamKey, "rankBy" to "adjusted", "page" to "1", "pageSize" to "1"),
        )
    }

    /**
     * `GET /api/rankings/bands/{bandType}/{teamKey}/history?days=`.
     *
     * @param bandType Band size.
     * @param teamKey Member-account roster key.
     * @param days Window, 1–3650.
     * @return Endpoint.
     */
    fun bandRankHistory(bandType: BandType, teamKey: String, days: Int): ServiceEndpoint {
        requireTeamKey(teamKey)
        if (days !in 1..3650) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(listOf("rankings", "bands", bandType.wireId, teamKey, "history"), listOf("days" to days.toString()))
    }

    /**
     * `GET /api/rankings/bands/{bandType}/{teamKey}/songs?limit=`.
     *
     * @param bandType Band size.
     * @param teamKey Member-account roster key.
     * @param limit Rows per list, 1–20.
     * @return Endpoint.
     */
    fun bandSongExtremes(bandType: BandType, teamKey: String, limit: Int): ServiceEndpoint {
        requireTeamKey(teamKey)
        if (limit !in 1..20) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(listOf("rankings", "bands", bandType.wireId, teamKey, "songs"), listOf("limit" to limit.toString()))
    }

    /**
     * `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=[&accountId=]`. With
     * `accountId` the service also returns that player's best band row as
     * `selectedPlayerEntry` (`GetSongBandLeaderboardEntryForAccount`, a pure `SELECT`).
     *
     * @param songId Catalogue song.
     * @param bandType Band size.
     * @param top Rows, 1–100.
     * @param offset Non-negative offset.
     * @param accountId Selected player, or null.
     * @return Endpoint.
     */
    fun songBandLeaderboard(songId: String, bandType: BandType, top: Int, offset: Int, accountId: String? = null): ServiceEndpoint {
        if (!ServiceEndpoint.isSafeSegment(songId) || top !in 1..100 || offset < 0) throw FestivalApiException.InvalidResource()
        if (accountId != null && !BandText.isValidMemberId(accountId)) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(
            listOf("leaderboard", songId, "bands", bandType.wireId),
            listOf("top" to top.toString(), "offset" to offset.toString()) + listOfNotNull(accountId?.let { "accountId" to it }),
        )
    }

    private fun requireTeamKey(teamKey: String) {
        if (!BandText.isValidTeamKey(teamKey)) throw FestivalApiException.InvalidResource()
    }
}

// endregion

// region Band reads

/**
 * Read one page of a player's bands.
 *
 * @param accountId Public account.
 * @param group Group filter.
 * @param page One-based page.
 * @param pageSize Rows per page.
 * @return Validated page.
 */
suspend fun FestivalApi.playerBands(accountId: String, group: PlayerBandGroup, page: Int, pageSize: Int): PlayerBandListResponse {
    val (body, _) = readPinned(BandEndpoints.playerBands(accountId, group, page, pageSize))
    return decode(PlayerBandListResponse.serializer(), body).also { it.validate(accountId, pageSize) }
}

/**
 * Read one band's ranking row by the type and team key its originating row carried.
 *
 * @param bandType Band size.
 * @param teamKey Member-account roster key.
 * @return The team's row.
 * @throws FestivalApiException.HttpStatus 404 when the team is unranked.
 */
suspend fun FestivalApi.bandProfile(bandType: BandType, teamKey: String): BandDetail {
    val (body, _) = readPinned(BandEndpoints.bandProfile(bandType, teamKey))
    val envelope = decode(BandProfileEnvelope.serializer(), body)
    if (envelope.bandType != bandType.wireId) throw FestivalApiException.InvalidResponse()
    val detail = envelope.selectedBandEntry ?: throw FestivalApiException.HttpStatus(404)
    if (detail.teamKey != teamKey) throw FestivalApiException.InvalidResponse()
    return detail
}

/**
 * Read a band's daily rank history.
 *
 * @param bandType Band size.
 * @param teamKey Member-account roster key.
 * @param days Window.
 * @return Validated history.
 */
suspend fun FestivalApi.bandRankHistory(bandType: BandType, teamKey: String, days: Int): BandRankHistoryResponse {
    val (body, _) = readPinned(BandEndpoints.bandRankHistory(bandType, teamKey, days))
    val history = decode(BandRankHistoryResponse.serializer(), body)
    if (history.bandType != bandType.wireId || history.teamKey != teamKey) throw FestivalApiException.InvalidResponse()
    return history
}

/**
 * Read a band's best and worst songs (503 until the band-song projection is published).
 *
 * @param bandType Band size.
 * @param teamKey Member-account roster key.
 * @param limit Rows per list.
 * @return Validated lists.
 */
suspend fun FestivalApi.bandSongExtremes(bandType: BandType, teamKey: String, limit: Int): BandSongExtremesResponse {
    val (body, _) = readPinned(BandEndpoints.bandSongExtremes(bandType, teamKey, limit))
    val songs = decode(BandSongExtremesResponse.serializer(), body)
    if (songs.bandType != bandType.wireId || songs.teamKey != teamKey || songs.best.size > limit || songs.worst.size > limit) {
        throw FestivalApiException.InvalidResponse()
    }
    return songs
}

/**
 * Read one page of a song's band leaderboard.
 *
 * @param songId Catalogue song.
 * @param bandType Band size.
 * @param page One-based page.
 * @param top Rows per page.
 * @param accountId Selected player for `selectedPlayerEntry`, or null.
 * @return Validated rows.
 */
suspend fun FestivalApi.songBandLeaderboard(songId: String, bandType: BandType, page: Int, top: Int, accountId: String? = null): SongBandLeaderboardResponse {
    if (page < 1 || top < 1 || page - 1 > Int.MAX_VALUE / top) throw FestivalApiException.InvalidResource()
    val (body, _) = readPinned(BandEndpoints.songBandLeaderboard(songId, bandType, top, (page - 1) * top, accountId))
    return decode(SongBandLeaderboardResponse.serializer(), body).also { it.validate(songId, bandType, top) }
}

// endregion
