package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.LeaderboardResponse
import com.festivalscoretracker.android.core.settings.ScoreLeeway
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.LeaderboardPayload
import com.festivalscoretracker.android.data.ServiceEndpoint
import java.util.Locale

// region Leeway leaderboard

/**
 * One leaderboard page, adding `leeway=` only while Filter Invalid Scores is on
 * (service-safety allowlist: `/api/leaderboard/{song}/{instrument}?top=&offset=[&leeway=]`).
 *
 * @receiver Shared client.
 * @param songId Song.
 * @param instrument Chart.
 * @param page One-based page.
 * @param top Rows per request.
 * @param leeway Invalid-score leeway percent, or null when filtering is off.
 * @return Validated page.
 */
suspend fun FestivalApi.leaderboardPage(songId: String, instrument: Instrument, page: Int, top: Int, leeway: Double?): LeaderboardPayload {
    if (leeway == null) return leaderboard(songId, instrument, page, top)
    if (page < 1 || top !in 1..LeaderboardPaging.PAGE_SIZE || page - 1 > Int.MAX_VALUE / top) throw FestivalApiException.InvalidResource()
    val endpoint = ServiceEndpoint.Feature(
        listOf("leaderboard", songId, instrument.wireId),
        listOf("top" to top.toString(), "offset" to ((page - 1) * top).toString(), "leeway" to leewayParameter(leeway)),
    )
    val (body, publicationId) = readPinned(endpoint)
    val response = decode(LeaderboardResponse.serializer(), body)
    response.validate(songId, instrument, top)
    return LeaderboardPayload(page, response, publicationId)
}

/**
 * Leeway as sent on the wire: clamped, one decimal, locale-independent.
 *
 * @param leeway Percent.
 * @return For example `1.0` or `-0.5`.
 */
internal fun leewayParameter(leeway: Double): String = String.format(Locale.ROOT, "%.1f", ScoreLeeway.clamp(leeway))

// endregion
