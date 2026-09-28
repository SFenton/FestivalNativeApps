package com.festivalscoretracker.android.data.compete

import com.festivalscoretracker.android.core.compete.ComboRankingEntry
import com.festivalscoretracker.android.core.compete.ComboRankingsResponse
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

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
suspend fun FestivalApi.comboRankings(comboId: String, rankBy: RankingMetric, page: Int, pageSize: Int): ComboRankingsResponse {
    if (page < 1 || pageSize !in 1..RankingPaging.MAX_PAGE_SIZE) throw FestivalApiException.InvalidResource()
    val query = comboQuery(comboId, rankBy) + listOf("page" to page.toString(), "pageSize" to pageSize.toString())
    val (body, _) = readPinned(ServiceEndpoint.Feature(listOf("rankings", "combo"), query))
    return decode(ComboRankingsResponse.serializer(), body).also { it.validate(comboId) }
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

// endregion
