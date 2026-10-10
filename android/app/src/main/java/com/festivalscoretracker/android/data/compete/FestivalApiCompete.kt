package com.festivalscoretracker.android.data.compete

import com.festivalscoretracker.android.core.compete.ComboRankingEntry
import com.festivalscoretracker.android.core.compete.ComboRankingsResponse
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint
import com.festivalscoretracker.android.data.rankings.RankingsPayload
import kotlinx.serialization.Serializable

// region Combo rankings reads

/*
 * Combo rankings (`FSTService/Api/RankingsEndpoints.cs:528-613`): both handlers only
 * `SELECT` from `combo_leaderboard`/`combo_stats`/account names and memoize an
 * instrument DB handle for the charted-song total — pure reads under the
 * allowlisted `/api/rankings/…` family (verified 2026-09-28). Publication-bound like
 * the other rankings reads. Cross-group combos answer 404 and are never requested.
 */

private fun comboQuery(comboId: String, rankBy: RankingMetric): List<Pair<String, String>> {
    val mask = RivalCombo.instrumentsFor(comboId)?.let(RivalCombo::mask)
    if (mask == null || !RivalCombo.isWithinGroup(mask)) throw FestivalApiException.InvalidResource()
    return listOf("combo" to comboId, "rankBy" to rankBy.wireId)
}

/**
 * `GET /api/rankings/combo?combo=&rankBy=&page=&pageSize=`.
 *
 * @param comboId Within-group hex combo ID.
 * @param rankBy Metric.
 * @param page One-based page.
 * @param pageSize Rows.
 * @return Validated page.
 */
suspend fun FestivalApi.comboRankings(comboId: String, rankBy: RankingMetric, page: Int, pageSize: Int): ComboRankingsResponse =
    comboRankingsPinned(comboId, rankBy, page, pageSize).first

/**
 * The combo board in the shared account-rankings shape, for Full Rankings' combo mode
 * (web `FullRankingsPage` `?combo=`, #602). A 404 is an honest empty board.
 *
 * @param comboId Within-group hex combo ID.
 * @param rankBy Metric.
 * @param page One-based page.
 * @param pageSize Rows.
 * @return Validated page; [RankingsPayload.publicationId] is 0 for a 404.
 */
suspend fun FestivalApi.comboRankingsPage(comboId: String, rankBy: RankingMetric, page: Int, pageSize: Int): RankingsPayload {
    val (response, publicationId) = comboRankingsPinned(comboId, rankBy, page, pageSize)
    return RankingsPayload(response.asRankingsResponse(rankBy), publicationId)
}

private suspend fun FestivalApi.comboRankingsPinned(comboId: String, rankBy: RankingMetric, page: Int, pageSize: Int): Pair<ComboRankingsResponse, Int> {
    if (page < 1 || pageSize !in 1..RankingPaging.MAX_PAGE_SIZE) throw FestivalApiException.InvalidResource()
    val query = comboQuery(comboId, rankBy) + listOf("page" to page.toString(), "pageSize" to pageSize.toString())
    val (body, publicationId) = try {
        readPinned(ServiceEndpoint.Feature(listOf("rankings", "combo"), query))
    } catch (notFound: FestivalApiException.HttpStatus) {
        // 404 = no board for this combo yet: an honest empty board ("No scores yet"), not an outage.
        if (notFound.status == 404) return ComboRankingsResponse(comboId = comboId, rankBy = rankBy.wireId, page = page, pageSize = pageSize) to 0
        throw notFound
    }
    return decode(ComboRankingsResponse.serializer(), body).also { it.validate(comboId) } to publicationId
}

/**
 * `GET /api/rankings/combo/{accountId}?combo=&rankBy=`: one account's combo row;
 * HTTP 404 means not ranked in this combo.
 *
 * @param accountId Validated account ID.
 * @param comboId Within-group hex combo ID.
 * @param rankBy Metric.
 * @return The row, or null when unranked.
 */
suspend fun FestivalApi.playerComboRanking(accountId: String, comboId: String, rankBy: RankingMetric): ComboRankingEntry? {
    if (!ProfileSearchText.isValidAccountId(accountId)) throw FestivalApiException.InvalidResource()
    val body = try {
        readPinned(ServiceEndpoint.Feature(listOf("rankings", "combo", accountId), comboQuery(comboId, rankBy))).first
    } catch (notFound: FestivalApiException.HttpStatus) {
        if (notFound.status == 404) return null
        throw notFound
    }
    val entry = decode(ComboRankingEntry.serializer(), body)
    if (!entry.accountId.equals(accountId, ignoreCase = true) || entry.rank < 1) throw FestivalApiException.InvalidResponse()
    return entry
}

/**
 * [playerComboRanking] as the Full Rankings own-row result: the row in the shared shape
 * with the combo's population, or [PlayerRankingResult.Unranked] on 404.
 *
 * @param accountId Validated account ID.
 * @param comboId Within-group hex combo ID.
 * @param rankBy Metric (a combo row carries only this metric's rank).
 * @return The row or unranked.
 */
suspend fun FestivalApi.playerComboRankingResult(accountId: String, comboId: String, rankBy: RankingMetric): PlayerRankingResult {
    if (!ProfileSearchText.isValidAccountId(accountId)) throw FestivalApiException.InvalidResource()
    val body = try {
        readPinned(ServiceEndpoint.Feature(listOf("rankings", "combo", accountId), comboQuery(comboId, rankBy))).first
    } catch (notFound: FestivalApiException.HttpStatus) {
        if (notFound.status == 404) return PlayerRankingResult.Unranked
        throw notFound
    }
    val entry = decode(ComboRankingEntry.serializer(), body)
    val envelope = decode(PlayerComboRankingEnvelope.serializer(), body)
    if (!entry.accountId.equals(accountId, ignoreCase = true) || entry.rank < 1 || envelope.totalAccounts < 0) throw FestivalApiException.InvalidResponse()
    return PlayerRankingResult.Ranked(PlayerInstrumentRanking(entry.asAccountEntry(rankBy), envelope.comboId, envelope.totalAccounts))
}

/** Envelope-only fields of `GET /api/rankings/combo/{accountId}` (web `{ comboId, rankBy, totalAccounts }`). */
@Serializable
private data class PlayerComboRankingEnvelope(val comboId: String = "", val totalAccounts: Int = 0)

// endregion
