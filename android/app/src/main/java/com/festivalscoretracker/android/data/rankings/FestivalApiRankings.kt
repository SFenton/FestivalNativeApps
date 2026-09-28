package com.festivalscoretracker.android.data.rankings

import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingsResponse
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRankingEnvelope
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankHistoryResponse
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rankings.RankingsResponse
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Endpoints

/**
 * Allowlisted keyless rankings GETs (`.agents/platforms/service-safety.md`), all pure
 * publication-pinned reads. Never the bare `/api/rankings/bands/{bandType}/{teamKey}`
 * route, which can rebuild band configurations on a GET.
 */
object RankingsEndpoints {
    /**
     * `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=`
     * (`FSTService/Api/RankingsEndpoints.cs:187`).
     *
     * @param instrument Chart.
     * @param rankBy Metric.
     * @param page One-based page.
     * @param pageSize Rows (10 for a card, 25 for a page).
     * @return Endpoint.
     */
    fun rankings(instrument: Instrument, rankBy: RankingMetric, page: Int, pageSize: Int): ServiceEndpoint {
        requirePaging(page, pageSize)
        return ServiceEndpoint.Feature(listOf("rankings", instrument.wireId), paging(rankBy.wireId, page, pageSize))
    }

    /**
     * `GET /api/rankings/{instrument}/{accountId}`: one account's own row
     * (`RankingsEndpoints.cs:272`, in-memory lookups only); 404 = not ranked.
     *
     * @param instrument Chart.
     * @param accountId Validated account ID.
     * @return Endpoint.
     */
    fun playerInstrumentRanking(instrument: Instrument, accountId: String): ServiceEndpoint {
        if (!ProfileSearchText.isValidAccountId(accountId)) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(listOf("rankings", instrument.wireId, accountId))
    }

    /**
     * `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=` (`RankingsEndpoints.cs:680`).
     *
     * @param bandType Band size.
     * @param rankBy Band metric.
     * @param page One-based page.
     * @param pageSize Rows.
     * @return Endpoint.
     */
    fun bandRankings(bandType: BandType, rankBy: BandRankingMetric, page: Int, pageSize: Int): ServiceEndpoint {
        requirePaging(page, pageSize)
        return ServiceEndpoint.Feature(listOf("rankings", "bands", bandType.wireId), paging(rankBy.wireId, page, pageSize))
    }

    /**
     * `GET /api/rankings/{instrument}/{accountId}/history?days=` (one `SELECT`,
     * `RankingsEndpoints.cs:392`); an unranked account is an empty `history`.
     *
     * @param instrument Chart.
     * @param accountId Validated account ID.
     * @param days Lookback, 1–365.
     * @return Endpoint.
     */
    fun rankHistory(instrument: Instrument, accountId: String, days: Int): ServiceEndpoint {
        if (!ProfileSearchText.isValidAccountId(accountId) || days !in 1..365) throw FestivalApiException.InvalidResource()
        return ServiceEndpoint.Feature(listOf("rankings", instrument.wireId, accountId, "history"), listOf("days" to days.toString()))
    }

    private fun paging(rankBy: String, page: Int, pageSize: Int) =
        listOf("rankBy" to rankBy, "page" to page.toString(), "pageSize" to pageSize.toString())

    private fun requirePaging(page: Int, pageSize: Int) {
        if (page < 1 || pageSize !in 1..RankingPaging.MAX_PAGE_SIZE) throw FestivalApiException.InvalidResource()
    }
}

// endregion

// region Payloads

/**
 * One account rankings page.
 *
 * @property rankings Validated rows.
 * @property publicationId Observed publication.
 */
data class RankingsPayload(val rankings: RankingsResponse, val publicationId: Int)

/**
 * One band rankings page.
 *
 * @property rankings Validated rows.
 * @property publicationId Observed publication.
 */
data class BandRankingsPayload(val rankings: BandRankingsResponse, val publicationId: Int)

// endregion

// region Reads

/**
 * Read one page of an instrument's account rankings.
 *
 * @param instrument Chart.
 * @param rankBy Metric.
 * @param page One-based page.
 * @param pageSize Rows per page.
 * @return Validated page.
 * @throws FestivalApiException for invalid input, service failures or a corrupt response.
 */
suspend fun FestivalApi.rankings(instrument: Instrument, rankBy: RankingMetric, page: Int, pageSize: Int = RankingPaging.PAGE_SIZE): RankingsPayload {
    val (body, publicationId) = readPinned(RankingsEndpoints.rankings(instrument, rankBy, page, pageSize))
    val response = decode(RankingsResponse.serializer(), body)
    response.validate(instrument)
    return RankingsPayload(response, publicationId)
}

/**
 * Read one page of a band size's rankings.
 *
 * @param bandType Band size.
 * @param rankBy Band metric.
 * @param page One-based page.
 * @param pageSize Rows per page.
 * @return Validated page.
 * @throws FestivalApiException for invalid input, service failures or a corrupt response.
 */
suspend fun FestivalApi.bandRankings(bandType: BandType, rankBy: BandRankingMetric, page: Int, pageSize: Int = RankingPaging.PAGE_SIZE): BandRankingsPayload {
    val (body, publicationId) = readPinned(RankingsEndpoints.bandRankings(bandType, rankBy, page, pageSize))
    val response = decode(BandRankingsResponse.serializer(), body)
    response.validate(bandType)
    return BandRankingsPayload(response, publicationId)
}

/**
 * Read one account's own row on an instrument board. HTTP 404 is an honest
 * "not ranked yet" ([PlayerRankingResult.Unranked]), never a failure.
 *
 * @param instrument Chart.
 * @param accountId Validated account ID.
 * @return The row or unranked.
 * @throws FestivalApiException for invalid input, other statuses or a corrupt response.
 */
suspend fun FestivalApi.playerInstrumentRanking(instrument: Instrument, accountId: String): PlayerRankingResult {
    val body = try {
        readPinned(RankingsEndpoints.playerInstrumentRanking(instrument, accountId)).first
    } catch (notFound: FestivalApiException.HttpStatus) {
        if (notFound.status == 404) return PlayerRankingResult.Unranked
        throw notFound
    }
    val entry = decode(AccountRankingEntry.serializer(), body)
    val envelope = decode(PlayerInstrumentRankingEnvelope.serializer(), body)
    val ranking = PlayerInstrumentRanking(entry, envelope.instrument, envelope.totalRankedAccounts)
    ranking.validate(instrument, accountId)
    return PlayerRankingResult.Ranked(ranking)
}

/**
 * Read one account's daily rank history on an instrument (every metric per day).
 *
 * @param instrument Chart.
 * @param accountId Validated account ID.
 * @param days Lookback.
 * @return Validated history (empty when unranked).
 * @throws FestivalApiException for invalid input, service failures or a corrupt response.
 */
suspend fun FestivalApi.rankHistory(instrument: Instrument, accountId: String, days: Int): RankHistoryResponse {
    val (body, _) = readPinned(RankingsEndpoints.rankHistory(instrument, accountId, days))
    return decode(RankHistoryResponse.serializer(), body).also { it.validate(instrument, accountId) }
}

// endregion
