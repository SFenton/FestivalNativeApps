package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.profile.PlayerHistoryResponse
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Song score history

/**
 * `GET /api/player/{accountId}/history?songId=` without `instrument` (web
 * `playerHistoryQueryOptions(accountId, songId)`): every chart's score changes for one
 * song, for the Song Detail score-history card. Same allowlisted, keyless pure read as
 * the per-chart history page ([service safety](.agents/platforms/service-safety.md)).
 *
 * @param accountId Validated account.
 * @param songId Song.
 * @return Endpoint.
 * @throws FestivalApiException.InvalidResource for an invalid account or song ID.
 */
internal fun songHistoryEndpoint(accountId: String, songId: String): ServiceEndpoint.Feature {
    if (!ProfileSearchText.isValidAccountId(accountId) || !ServiceEndpoint.isSafeSegment(songId)) throw FestivalApiException.InvalidResource()
    return ServiceEndpoint.Feature(listOf("player", accountId, "history"), listOf("songId" to songId), acceptsSyncing = true)
}

/**
 * Read a player's score changes on every chart of one song.
 *
 * @receiver Shared client.
 * @param accountId Validated account ID.
 * @param songId Song.
 * @return Rows for this song only, or an explicit syncing (202) / unregistered (404) state.
 */
suspend fun FestivalApi.songScoreHistory(accountId: String, songId: String): PlayerHistoryPayload =
    try {
        val read = readPinnedResponse(songHistoryEndpoint(accountId, songId))
        val response = decode(PlayerHistoryResponse.serializer(), read.body)
        response.validate(accountId)
        val rows = response.history.filter { it.songId == songId }
        PlayerHistoryPayload(response.copy(history = rows, count = rows.size), if (read.status == 202) PlayerHistoryState.Syncing else PlayerHistoryState.Available)
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status != 404) throw error
        PlayerHistoryPayload(PlayerHistoryResponse(accountId = accountId), PlayerHistoryState.Unregistered)
    }

// endregion
