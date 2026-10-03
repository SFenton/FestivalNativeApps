package com.festivalscoretracker.android.data.rivals

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.core.rivals.RivalDetailResponse
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Rivals reads

/*
 * Keyless public Rivals reads (`FSTService/Api/RivalsEndpoints.cs`,
 * `LeaderboardRivalsEndpoints.cs`), allowlisted as pure reads in
 * `.agents/platforms/service-safety.md`. They are unpinned: Rivals data is not part
 * of the catalogue publication contract. `POST …/rivals/recompute` has no builder.
 * Rival detail's `allowLiveFallback=true` is allowlisted (the fallback only reads)
 * and is sent only for a detail opened from Find Rival (web `RivalsPage.tsx:263`).
 */

/** Sorts accepted by the rival detail endpoints. */
val RIVAL_DETAIL_SORTS = setOf("closest", "they_lead", "you_lead")

/**
 * Whether a string is a rivals scope segment: a chart wire ID, a hex combo or `pro_drums`.
 *
 * @param scope Candidate.
 * @return True when it may be sent.
 */
fun isValidRivalScope(scope: String): Boolean = Instrument.fromWireId(scope) != null || RivalCombo.isValidToken(scope)

private fun requireAccount(vararg ids: String) {
    if (!ids.all(ProfileSearchText::isValidAccountId)) throw FestivalApiException.InvalidResource()
}

/**
 * One unpinned Rivals GET (Rivals data is outside the catalogue publication contract).
 *
 * @param segments Path segments after `/api/`.
 * @param query Query parameters.
 * @return Body bytes.
 */
private suspend fun FestivalApi.rivalsRead(segments: List<String>, query: List<Pair<String, String>> = emptyList()): ByteArray =
    readUnpinned(ServiceEndpoint.Feature(segments, query, pinned = false))

private suspend fun <T> emptyOn404(empty: () -> T, read: suspend () -> T): T =
    try {
        read()
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status == 404) empty() else throw error
    }

/**
 * `GET /api/player/{accountId}/rivals/{scope}`; HTTP 404 "no rivals" becomes an empty list.
 *
 * @param accountId Selected player.
 * @param scope Chart wire ID, hex combo ID or `pro_drums`.
 * @return Validated list.
 */
suspend fun FestivalApi.rivalsList(accountId: String, scope: String): RivalsListResponse {
    requireAccount(accountId)
    if (!isValidRivalScope(scope)) throw FestivalApiException.InvalidResource()
    return emptyOn404({ RivalsListResponse.empty(scope) }) {
        decode(RivalsListResponse.serializer(), rivalsRead(listOf("player", accountId, "rivals", scope))).validated()
    }
}

/**
 * `GET /api/player/{accountId}/leaderboard-rivals/{instrument}?rankBy=`; 404 becomes empty.
 *
 * @param accountId Selected player.
 * @param instrument Chart.
 * @param rankBy Metric.
 * @return Validated neighbours.
 */
suspend fun FestivalApi.leaderboardRivals(accountId: String, instrument: Instrument, rankBy: RivalRankMetric): LeaderboardRivalsListResponse {
    requireAccount(accountId)
    return emptyOn404({ LeaderboardRivalsListResponse.empty(instrument) }) {
        decode(
            LeaderboardRivalsListResponse.serializer(),
            rivalsRead(listOf("player", accountId, "leaderboard-rivals", instrument.wireId), listOf("rankBy" to rankBy.wireId)),
        ).validated()
    }
}

/**
 * `GET /api/player/{accountId}/rivals/{scope}/{rivalId}?limit=0&sort=[&allowLiveFallback=true]`
 * (web `api.getRivalDetail`); 404 "not precomputed" becomes an empty detail.
 *
 * @param accountId Selected player.
 * @param scope Chart wire ID, hex combo ID or `pro_drums`.
 * @param rivalId Rival.
 * @param sort `closest`, `they_lead` or `you_lead`.
 * @param allowLiveFallback Compute untracked comparisons live (Find Rival only).
 * @return Validated detail.
 */
suspend fun FestivalApi.rivalDetail(
    accountId: String,
    scope: String,
    rivalId: String,
    sort: String = "closest",
    allowLiveFallback: Boolean = false,
): RivalDetailResponse {
    requireAccount(accountId, rivalId)
    if (!isValidRivalScope(scope) || sort !in RIVAL_DETAIL_SORTS) throw FestivalApiException.InvalidResource()
    val query = buildList {
        add("limit" to "0")
        add("sort" to sort)
        if (allowLiveFallback) add("allowLiveFallback" to "true")
    }
    return emptyOn404({ RivalDetailResponse.empty(rivalId) }) {
        decode(RivalDetailResponse.serializer(), rivalsRead(listOf("player", accountId, "rivals", scope, rivalId), query)).validated(rivalId)
    }
}

/**
 * `GET /api/player/{accountId}/leaderboard-rivals/{instrument}/{rivalId}?rankBy=&sort=`; 404 becomes empty.
 *
 * @param accountId Selected player.
 * @param instrument Chart.
 * @param rivalId Rival.
 * @param rankBy Metric.
 * @param sort `closest`, `they_lead` or `you_lead`.
 * @return Validated detail.
 */
suspend fun FestivalApi.leaderboardRivalDetail(
    accountId: String,
    instrument: Instrument,
    rivalId: String,
    rankBy: RivalRankMetric,
    sort: String = "closest",
): RivalDetailResponse {
    requireAccount(accountId, rivalId)
    if (sort !in RIVAL_DETAIL_SORTS) throw FestivalApiException.InvalidResource()
    return emptyOn404({ RivalDetailResponse.empty(rivalId) }) {
        decode(
            RivalDetailResponse.serializer(),
            rivalsRead(
                listOf("player", accountId, "leaderboard-rivals", instrument.wireId, rivalId),
                listOf("rankBy" to rankBy.wireId, "sort" to sort),
            ),
        ).validated(rivalId)
    }
}

/**
 * `GET /api/player/{accountId}/rivals/all`, unpinned like the other Rivals reads (Suggestions
 * reads the same endpoint pinned); 404 becomes empty. Rival Detail uses it as the freeze
 * fallback ([com.festivalscoretracker.android.core.rivals.RivalsAllDetail]). The live body is
 * ~8.9 MB uncompressed (2026-10).
 *
 * @param accountId Selected player.
 * @return Every combo's rivals with samples.
 * @throws FestivalApiException.InvalidResponse when the echoed account differs.
 */
suspend fun FestivalApi.rivalsAll(accountId: String): RivalsAllResponse {
    requireAccount(accountId)
    val all = emptyOn404({ RivalsAllResponse.empty(accountId) }) {
        decode(RivalsAllResponse.serializer(), rivalsRead(listOf("player", accountId, "rivals", "all")))
    }
    if (!all.accountId.equals(accountId, ignoreCase = true)) throw FestivalApiException.InvalidResponse()
    return all
}

// endregion
