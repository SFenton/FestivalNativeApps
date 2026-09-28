package com.festivalscoretracker.android.data.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.profile.PlayerHistoryResponse
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Profile endpoints

/**
 * Player-profile reads (`.agents/platforms/service-safety.md` allowlist). All are
 * keyless pure GETs; the player-stats GET (it can store tiers) is never called.
 */
internal object ProfileEndpoints {
    /**
     * `GET /api/player/{accountId}` (compact public scores; 202 = syncing).
     *
     * @param accountId Validated account.
     * @return Endpoint.
     */
    fun player(accountId: String) = ServiceEndpoint.Feature(listOf("player", account(accountId)), acceptsSyncing = true)

    /**
     * `GET /api/rankings/{instrument}/{accountId}` (single-account row; 404 = unranked;
     * in-memory lookups only, `FSTService/Api/RankingsEndpoints.cs:272-327`).
     *
     * @param instrument Chart.
     * @param accountId Validated account.
     * @return Endpoint.
     */
    fun instrumentRanking(instrument: Instrument, accountId: String) =
        ServiceEndpoint.Feature(listOf("rankings", instrument.wireId, account(accountId)))

    /**
     * `GET /api/rankings/{instrument}/{accountId}/history?days=` (one `SELECT`).
     *
     * @param instrument Chart.
     * @param accountId Validated account.
     * @param days Lookback, 1–365.
     * @return Endpoint.
     */
    fun rankHistory(instrument: Instrument, accountId: String, days: Int): ServiceEndpoint.Feature {
        if (days !in 1..365) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(
            listOf("rankings", instrument.wireId, account(accountId), "history"),
            listOf("days" to days.toString()),
        )
    }

    /**
     * `GET /api/player/{accountId}/history?songId=&instrument=` (precomputed published cache).
     *
     * @param accountId Validated account.
     * @param songId Song.
     * @param instrument Chart.
     * @return Endpoint.
     */
    fun history(accountId: String, songId: String, instrument: Instrument): ServiceEndpoint.Feature {
        if (!ServiceEndpoint.isSafeSegment(songId)) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(
            listOf("player", account(accountId), "history"),
            listOf("songId" to songId, "instrument" to instrument.wireId),
            acceptsSyncing = true,
        )
    }

    private fun account(accountId: String): String =
        if (ProfileSearchText.isValidAccountId(accountId)) accountId else throw FestivalApiException.InvalidResource()
}

// endregion

// region Profile reads

/**
 * Read a player's public compact scores. Keyless: never a selected-profile header
 * or tracking call. The result carries the header-verified publication so only a
 * current, proven read can back a Select.
 *
 * @param accountId Validated account ID.
 * @return Validated profile, its state and provenance.
 * @throws FestivalApiException for an invalid ID, transport, status (404 as [FestivalApiException.HttpStatus]) or corrupt data.
 */
suspend fun FestivalApi.playerProfile(accountId: String): PlayerProfilePayload {
    val read = readPinnedResponse(ProfileEndpoints.player(accountId))
    val profile = decode(PlayerProfileResponse.serializer(), read.body).normalized()
    val state = profile.validate(accountId)
    if ((state == PlayerProfileState.Syncing) != (read.status == 202)) throw FestivalApiException.InvalidResponse()
    return PlayerProfilePayload(profile, state, read.responsePublicationId, read.observedPublicationId)
}

/**
 * Read one account's row on a per-instrument rankings board (never player-stats).
 *
 * @param instrument Chart.
 * @param accountId Validated account ID.
 * @return The row, or an unranked payload for HTTP 404.
 */
suspend fun FestivalApi.playerInstrumentRanking(instrument: Instrument, accountId: String): PlayerInstrumentRankingPayload =
    try {
        val (body, _) = readPinned(ProfileEndpoints.instrumentRanking(instrument, accountId))
        val ranking = decode(PlayerInstrumentRanking.serializer(), body)
        ranking.validate(instrument, accountId)
        PlayerInstrumentRankingPayload(ranking)
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status != 404) throw error
        PlayerInstrumentRankingPayload(null)
    }

/**
 * Read one account's daily rank history (empty, not 404, when unranked).
 *
 * @param instrument Chart.
 * @param accountId Validated account ID.
 * @param days Lookback, 1–365 (the web uses 30).
 * @return Validated history.
 */
suspend fun FestivalApi.playerRankHistory(instrument: Instrument, accountId: String, days: Int = 30): PlayerRankHistory {
    val (body, _) = readPinned(ProfileEndpoints.rankHistory(instrument, accountId, days))
    return decode(PlayerRankHistory.serializer(), body).also { it.validate(instrument, accountId) }
}

/**
 * Read a player's score-change history for one song and chart.
 *
 * @param accountId Validated account ID.
 * @param songId Song.
 * @param instrument Chart.
 * @return Rows, or an explicit syncing (202) / unregistered (404) state.
 */
suspend fun FestivalApi.playerHistory(accountId: String, songId: String, instrument: Instrument): PlayerHistoryPayload =
    try {
        val read = readPinnedResponse(ProfileEndpoints.history(accountId, songId, instrument))
        val response = decode(PlayerHistoryResponse.serializer(), read.body)
        response.validate(accountId)
        PlayerHistoryPayload(response, if (read.status == 202) PlayerHistoryState.Syncing else PlayerHistoryState.Available)
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status != 404) throw error
        PlayerHistoryPayload(PlayerHistoryResponse(accountId = accountId), PlayerHistoryState.Unregistered)
    }

// endregion
