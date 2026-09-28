package com.festivalscoretracker.android.rankings

import androidx.datastore.preferences.core.mutablePreferencesOf
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.data.rankings.RankingsEndpoints
import com.festivalscoretracker.android.data.rankings.bandRankings
import com.festivalscoretracker.android.data.rankings.playerInstrumentRanking
import com.festivalscoretracker.android.data.rankings.rankings
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RankingsDataTest {
    private val transport = RankingsFixtures.install(FakeTransport.standard(), unranked = setOf("Solo_Bass"))
    private val api = FestivalApi("https://fixture.test", transport)
    private val base = "https://fixture.test".toHttpUrl()

    private suspend inline fun <reified T : Throwable> expect(block: () -> Unit) {
        try {
            block()
            fail("expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    // region Endpoints

    @Test
    fun endpointUrlsAreExactAndBounded() {
        assertEquals(
            "https://fixture.test/api/rankings/Solo_Guitar?rankBy=fcrate&page=2&pageSize=25",
            RankingsEndpoints.rankings(Instrument.Lead, RankingMetric.FcRate, 2, 25).url(base),
        )
        assertEquals(
            "https://fixture.test/api/rankings/bands/Band_Quad?rankBy=weighted&page=1&pageSize=10",
            RankingsEndpoints.bandRankings(BandType.Quad, BandRankingMetric.Weighted, 1, 10).url(base),
        )
        assertEquals(
            "https://fixture.test/api/rankings/Solo_PeripheralDrums/${RankingsFixtures.SELECTED}",
            RankingsEndpoints.playerInstrumentRanking(Instrument.ProDrums, RankingsFixtures.SELECTED).url(base),
        )
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.rankings(Instrument.Lead, RankingMetric.FcRate, 0, 25) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.rankings(Instrument.Lead, RankingMetric.FcRate, 1, 201) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.bandRankings(BandType.Duets, BandRankingMetric.Adjusted, 1, 0) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.playerInstrumentRanking(Instrument.Lead, "../x") }
        assertTrue(RankingsEndpoints.rankings(Instrument.Lead, RankingMetric.TotalScore, 1, 10).pinned)
    }

    // endregion

    // region Reads

    @Test
    fun rankingsDecodeAnonymousRowsAndStayKeyless() = runTest {
        val payload = api.rankings(Instrument.Lead, RankingMetric.TotalScore, 1, 10)
        assertEquals(7, payload.publicationId)
        assertEquals(10, payload.rankings.entries.size)
        assertEquals("", payload.rankings.entries[RankingsFixtures.ANONYMOUS_RANK - 1].accountId)
        val bands = api.bandRankings(BandType.Trios, BandRankingMetric.FcRate, 2, 25)
        assertEquals(5, bands.rankings.entries.size)
        transport.requests.forEach { request ->
            assertEquals("GET", request.method)
            assertTrue(request.headers.keys.none { it.equals("X-API-Key", true) || it.lowercase().startsWith("x-fst-selected-") })
        }
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
    }

    @Test
    fun ownRowReadMapsRankedUnrankedAndErrors() = runTest {
        val ranked = api.playerInstrumentRanking(Instrument.Lead, RankingsFixtures.SELECTED) as PlayerRankingResult.Ranked
        assertEquals(RankingsFixtures.SELECTED_RANK, ranked.ranking.entry.totalScoreRank)
        assertEquals(RankingsFixtures.TOTAL_ACCOUNTS, ranked.ranking.totalRankedAccounts)
        assertEquals(PlayerRankingResult.Unranked, api.playerInstrumentRanking(Instrument.Bass, RankingsFixtures.SELECTED))
        transport.onRaw("/api/rankings/Solo_Drums/${RankingsFixtures.SELECTED}") { HttpResult(500, ByteArray(0)) }
        expect<FestivalApiException.HttpStatus> { api.playerInstrumentRanking(Instrument.Drums, RankingsFixtures.SELECTED) }
        transport.on("/api/rankings/Solo_Vocals/${RankingsFixtures.SELECTED}") { RankingsFixtures.playerRanking(accountId = RankingsFixtures.accountId(1)) }
        expect<FestivalApiException.InvalidLeaderboard> { api.playerInstrumentRanking(Instrument.Vocals, RankingsFixtures.SELECTED) }
        transport.on("/api/rankings/Solo_PeripheralBass/${RankingsFixtures.SELECTED}") { "not json" }
        expect<FestivalApiException.InvalidResponse> { api.playerInstrumentRanking(Instrument.ProBass, RankingsFixtures.SELECTED) }
    }

    @Test
    fun mismatchedPagesAndFreezesAreErrors() = runTest {
        transport.on("/api/rankings/Solo_Guitar") { RankingsFixtures.rankings("Solo_Bass", "totalscore", 1, 10) }
        expect<FestivalApiException.InvalidLeaderboard> { api.rankings(Instrument.Lead, RankingMetric.TotalScore, 1, 10) }
        transport.on("/api/rankings/bands/Band_Duets") { RankingsFixtures.bandRankings("Band_Quad", "totalscore", 1, 10) }
        expect<FestivalApiException.InvalidLeaderboard> { api.bandRankings(BandType.Duets, BandRankingMetric.TotalScore, 1, 10) }
        transport.onRaw("/api/rankings/Solo_Bass") { HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "scrape")) }
        expect<FestivalApiException.PublicReadFrozen> { api.rankings(Instrument.Bass, RankingMetric.TotalScore, 1, 10) }
        RequestGate.validateKeyless(transport.requests.last())
    }

    // endregion

    // region Preferences

    @Test
    fun rankByPersistsUnderItsOwnKey() = runTest {
        val store = InMemoryPreferences()
        val preferences = LeaderboardPreferences(store)
        assertEquals(RankingMetric.TotalScore, preferences.rankBy.first())
        preferences.setRankBy(RankingMetric.Weighted)
        assertEquals(RankingMetric.Weighted, preferences.rankBy.first())
        assertEquals("weighted", store.current[LeaderboardPreferences.KEY_RANK_BY])
        val corrupt = LeaderboardPreferences(InMemoryPreferences(mutablePreferencesOf(LeaderboardPreferences.KEY_RANK_BY to "bogus")))
        assertEquals(RankingMetric.TotalScore, corrupt.rankBy.first())
        assertFalse(store.current.asMap().keys.any { it.name.startsWith("fst.settings") })
    }

    // endregion
}
