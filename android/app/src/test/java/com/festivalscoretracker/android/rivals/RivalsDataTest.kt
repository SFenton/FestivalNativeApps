package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalDetailRequest
import com.festivalscoretracker.android.core.rivals.RivalDetailResponse
import com.festivalscoretracker.android.core.rivals.RivalIdentity
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.data.rivals.isValidRivalScope
import com.festivalscoretracker.android.data.rivals.leaderboardRivalDetail
import com.festivalscoretracker.android.data.rivals.leaderboardRivals
import com.festivalscoretracker.android.data.rivals.rivalDetail
import com.festivalscoretracker.android.data.rivals.rivalsList
import com.festivalscoretracker.android.testing.FakeTransport
import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Rivals endpoint builders, status handling and the in-process read cache. */
class RivalsDataTest {
    private val player = RivalsFixtures.PLAYER
    private val rival = RivalsFixtures.RIVALS[0]

    private fun api(transport: FakeTransport) = FestivalApi("https://fixture.test", transport)

    private suspend inline fun <reified T : Throwable> assertThrowsSuspend(block: () -> Unit) {
        try {
            block()
            fail("expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    @Test
    fun listsAreKeylessGetsWithValidatedSegments() = runTest {
        val transport = RivalsFixtures.transport()
        val client = api(transport)
        val lead = client.rivalsList(player, "Solo_Guitar")
        assertEquals(2, lead.above.size)
        assertEquals(2, lead.below.size)
        assertEquals("03", client.rivalsList(player, "03").combo)
        val request = transport.sent("/api/player/$player/rivals/Solo_Guitar").single()
        assertEquals("GET", request.method)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected-") })
        val board = client.leaderboardRivals(player, Instrument.Lead, RivalRankMetric.TotalScore)
        assertEquals(42, board.userRank)
        assertTrue(transport.sent("/api/player/$player/leaderboard-rivals/Solo_Guitar").single().url.endsWith("?rankBy=totalscore"))
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.rivalsList("bad", "Solo_Guitar") }
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.rivalsList(player, "../x") }
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.leaderboardRivals("bad", Instrument.Lead, RivalRankMetric.TotalScore) }
        assertTrue(isValidRivalScope("pro_drums"))
        assertFalse(isValidRivalScope("recompute"))
    }

    @Test
    fun notFoundBecomesEmptyAndFreezeIsTyped() = runTest {
        val transport = FakeTransport.standard()
        val client = api(transport)
        assertTrue(client.rivalsList(player, "Solo_Bass").isEmpty)
        assertTrue(client.leaderboardRivals(player, Instrument.Bass, RivalRankMetric.Adjusted).isEmpty)
        assertTrue(client.rivalDetail(player, "Solo_Bass", rival).songs.isEmpty())
        assertTrue(client.leaderboardRivalDetail(player, Instrument.Bass, rival, RivalRankMetric.TotalScore).songs.isEmpty())
        transport.onRaw("/api/player/$player/rivals/Solo_Bass/$rival") {
            HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
        }
        assertThrowsSuspend<FestivalApiException.PublicReadFrozen> { client.rivalDetail(player, "Solo_Bass", rival) }
        transport.onRaw("/api/player/$player/rivals/Solo_Drums") { HttpResult(500, ByteArray(0)) }
        assertThrowsSuspend<FestivalApiException.HttpStatus> { client.rivalsList(player, "Solo_Drums") }
        transport.on("/api/player/$player/rivals/Solo_Vocals") { "not json" }
        assertThrowsSuspend<FestivalApiException.InvalidResponse> { client.rivalsList(player, "Solo_Vocals") }
    }

    @Test
    fun detailQueriesAndLiveFallbackOnlyWhenAsked() = runTest {
        val transport = RivalsFixtures.transport()
        val client = api(transport)
        val detail = client.rivalDetail(player, "Solo_Guitar", rival)
        assertEquals("Synthetic Rival", detail.rival.displayName)
        assertEquals(8, detail.songs.size)
        client.rivalDetail(player, "Solo_Guitar", rival, sort = "you_lead", allowLiveFallback = true)
        val urls = transport.sent("/api/player/$player/rivals/Solo_Guitar/$rival").map { it.url.substringAfter('?') }
        assertEquals(listOf("limit=0&sort=closest", "limit=0&sort=you_lead&allowLiveFallback=true"), urls)
        client.leaderboardRivalDetail(player, Instrument.Lead, rival, RivalRankMetric.TotalScore)
        assertEquals("rankBy=totalscore&sort=closest", transport.sent("/api/player/$player/leaderboard-rivals/Solo_Guitar/$rival").single().url.substringAfter('?'))
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.rivalDetail(player, "Solo_Guitar", rival, sort = "random") }
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.rivalDetail(player, "Solo_Guitar", "bad") }
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.leaderboardRivalDetail(player, Instrument.Lead, rival, RivalRankMetric.TotalScore, sort = "x") }
        transport.on("/api/player/$player/rivals/Solo_Guitar/$rival") { RivalsFixtures.detail(RivalsFixtures.RIVALS[1]) }
        assertThrowsSuspend<FestivalApiException.InvalidResponse> { client.rivalDetail(player, "Solo_Guitar", rival) }
        assertTrue(transport.requests.all { it.method == "GET" })
    }

    @Test
    fun repositoryCachesSuccessesOnly() = runTest {
        var now = 0L
        var calls = 0
        var fail = true
        val repository = RivalsRepository(
            lists = { _, scope -> calls++; if (fail && scope == "Solo_Bass") throw IOException("offline") else RivalsListResponse.empty(scope) },
            leaderboardLists = { _, instrument, _ -> calls++; LeaderboardRivalsListResponse.empty(instrument) },
            details = { _, _, id, _ -> RivalDetailResponse.empty(id) },
            leaderboardDetails = { _, _, id, _ -> RivalDetailResponse.empty(id) },
            clock = { now },
        )
        repository.list(player, "Solo_Guitar")
        repository.list(player, "Solo_Guitar")
        assertEquals(1, calls)
        repository.list(player, "Solo_Guitar", refresh = true)
        assertEquals(2, calls)
        now += RivalsRepository.TTL_MILLIS
        repository.list(player, "Solo_Guitar")
        assertEquals(3, calls)
        assertThrowsSuspend<IOException> { repository.list(player, "Solo_Bass") }
        fail = false
        repository.list(player, "Solo_Bass")
        assertEquals(5, calls)
        repository.leaderboardList(player, Instrument.Lead, RivalRankMetric.TotalScore)
        repository.leaderboardList(player, Instrument.Lead, RivalRankMetric.TotalScore)
        assertEquals(6, calls)
        repository.clear()
        repository.leaderboardList(player, Instrument.Lead, RivalRankMetric.TotalScore)
        assertEquals(7, calls)
        repeat(RivalsRepository.MAX_ENTRIES + 5) { repository.list(player, "s$it") }
    }

    @Test
    fun repositoryMergesScopesAndToleratesPartialFailure() = runTest {
        val live = mutableListOf<Boolean>()
        val repository = RivalsRepository(
            lists = { _, scope -> RivalsListResponse.empty(scope) },
            leaderboardLists = { _, instrument, _ -> LeaderboardRivalsListResponse.empty(instrument) },
            details = { _, scope, id, allow ->
                live += allow
                when (scope) {
                    "bad" -> throw IOException("offline")
                    else -> RivalDetailResponse(RivalIdentity(id, "Named"), songs = listOf(com.festivalscoretracker.android.core.rivals.RivalSongComparison("song-$scope", instrument = "Solo_Guitar")))
                }
            },
            leaderboardDetails = { _, _, id, _ -> RivalDetailResponse(RivalIdentity(id, "Board")) },
        )
        val merged = repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar", "bad", "Solo_Bass")), allowLiveFallback = true)
        assertEquals(listOf("song-Solo_Guitar", "song-Solo_Bass"), merged.songs.map { it.songId })
        assertEquals("Solo_Guitar,bad,Solo_Bass", merged.combo)
        assertTrue(live.all { it })
        val single = repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Drums")))
        assertEquals("Solo_Guitar", single.songs.single().instrument)
        assertEquals("Board", repository.detail(player, rival, RivalDetailRequest.Leaderboard(Instrument.Lead, RivalRankMetric.TotalScore)).rival.displayName)
        assertThrowsSuspend<IOException> { repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("bad"))) }
    }

    @Test
    fun repositoryOverTheRealClient() = runTest {
        val transport = RivalsFixtures.transport()
        val repository = RivalsRepository(api(transport))
        assertEquals(2, repository.list(player, "Solo_Guitar").above.size)
        assertEquals(42, repository.leaderboardList(player, Instrument.Lead, RivalRankMetric.TotalScore).userRank)
        assertEquals(10, repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar", "Solo_Bass"))).songs.size)
        assertEquals(1, repository.detail(player, rival, RivalDetailRequest.Leaderboard(Instrument.Lead, RivalRankMetric.TotalScore)).songs.size)
    }
}
