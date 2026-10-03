package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.core.rivals.RivalDetailRequest
import com.festivalscoretracker.android.core.rivals.RivalDetailResponse
import com.festivalscoretracker.android.core.rivals.RivalIdentity
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalsAllDetail
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.suggestions.RivalsAllCombo
import com.festivalscoretracker.android.core.suggestions.RivalsAllEntry
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import com.festivalscoretracker.android.core.suggestions.RivalsAllSample
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.data.rivals.rivalsAll
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.RivalsFixtures
import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Issue #95: rival detail rebuilt from `rivals/all` while the service refuses uncached detail during a freeze. */
class RivalsAllDetailTest {
    private val player = RivalsFixtures.PLAYER
    private val rival = RivalsFixtures.RIVALS[0]

    private suspend inline fun <reified T : Throwable> assertThrowsSuspend(block: () -> Unit) {
        try {
            block()
            fail("expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    private fun entry(id: String, name: String?, vararg samples: RivalsAllSample) =
        RivalsAllEntry(id, name, "above", samples.size, 0, 0, 1.0, samples = samples.toList())

    /** Songs: 0 song-a, 1 song-b, 2 song-c. Rival samples split over two combo entries like the live payload. */
    private fun all(): RivalsAllResponse = RivalsAllResponse(
        accountId = player,
        songs = listOf("song-a", "song-b", "song-c"),
        combos = listOf(
            RivalsAllCombo(
                "01",
                above = listOf(
                    entry(
                        rival.uppercase(), " All Name ",
                        RivalsAllSample(0, "Solo_Guitar", 5, 3, 1000, 1100),
                        RivalsAllSample(1, "Solo_Guitar", 2, 10, 2000, 1500),
                        RivalsAllSample(9, "Solo_Guitar", 1, 1),
                        RivalsAllSample(2, "Solo_Guitar", -1, 4),
                        RivalsAllSample(2, "Bogus_Chart", 1, 4),
                    ),
                ),
                below = listOf(entry(RivalsFixtures.RIVALS[1], "Other", RivalsAllSample(0, "Solo_Guitar", 1, 2))),
            ),
            RivalsAllCombo(
                "03",
                above = listOf(
                    entry(
                        rival, null,
                        RivalsAllSample(0, "Solo_Guitar", 5, 3, 1000, 1100),
                        RivalsAllSample(2, "Solo_Bass", 4, 5, 900, null),
                        RivalsAllSample(2, "Solo_PeripheralDrums", 4, 5),
                    ),
                ),
            ),
        ),
    )

    @Test
    fun buildsTheScopedClosestFirstDetail() {
        val detail = RivalsAllDetail.build(all(), rival, listOf(Instrument.Lead, Instrument.Bass), "03")!!
        assertEquals("All Name", detail.rival.displayName)
        assertEquals(rival, detail.rival.accountId)
        assertEquals(RivalsAllDetail.SOURCE, detail.source)
        assertEquals("03", detail.combo)
        assertEquals("closest", detail.sort)
        // Deduplicated per song+chart, invalid indices/ranks/charts dropped, stable |delta| order.
        assertEquals(listOf("song-c" to "Solo_Bass", "song-a" to "Solo_Guitar", "song-b" to "Solo_Guitar"), detail.songs.map { it.songId to it.instrument })
        assertEquals(listOf(1, -2, 8), detail.songs.map { it.rankDelta })
        assertEquals(3, detail.totalSongs)
        val first = detail.songs[1]
        assertEquals(listOf(5, 3), listOf(first.userRank, first.rivalRank))
        assertEquals(1000L to 1100L, first.userScore to first.rivalScore)
        assertNull(first.title)
        assertNull(detail.songs[0].rivalScore)

        assertEquals(listOf("song-c"), RivalsAllDetail.build(all(), rival, listOf(Instrument.Bass), "Solo_Bass")!!.songs.map { it.songId })
        assertNull(RivalsAllDetail.build(all(), rival, listOf(Instrument.Vocals), "Solo_Vocals"))
        assertNull(RivalsAllDetail.build(all(), RivalsFixtures.RIVALS[3], listOf(Instrument.Lead), "Solo_Guitar"))
        assertNull(RivalsAllDetail.build(RivalsAllResponse.empty(player), rival, listOf(Instrument.Lead), "Solo_Guitar"))
    }

    @Test
    fun onlyChartAndComboScopesCanBeRebuilt() {
        assertEquals(listOf(Instrument.Bass), RivalsAllDetail.instrumentsFor("Solo_Bass"))
        assertEquals(RivalCombo.instrumentsFor("03"), RivalsAllDetail.instrumentsFor("03"))
        assertNull(RivalsAllDetail.instrumentsFor(RivalCombo.PRO_DRUMS_TOKEN))
        assertNull(RivalsAllDetail.instrumentsFor("nonsense"))
    }

    private fun repository(details: suspend (String) -> RivalDetailResponse, all: suspend (String) -> RivalsAllResponse) = RivalsRepository(
        lists = { _, scope -> RivalsListResponse.empty(scope) },
        leaderboardLists = { _, instrument, _ -> LeaderboardRivalsListResponse.empty(instrument) },
        details = { _, scope, _, _ -> details(scope) },
        leaderboardDetails = { _, _, id, _ -> RivalDetailResponse.empty(id) },
        all = all,
    )

    @Test
    fun aFrozenDetailIsRebuiltFromRivalsAll() = runTest {
        var allReads = 0
        val repository = repository({ throw FestivalApiException.PublicReadFrozen("post-process", null) }) { allReads++; all() }
        val single = repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar")))
        assertEquals(listOf("song-a", "song-b"), single.songs.map { it.songId })
        assertEquals("Solo_Guitar", single.combo)
        val merged = repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar", "Solo_Bass")))
        assertEquals(3, merged.songs.size)
        assertEquals("All Name", merged.rival.displayName)
        assertEquals(1, allReads) // one cached rivals/all read serves every scope
        // Pro Drums family and a rival missing from rivals/all keep the freeze (the page's retry state).
        assertThrowsSuspend<FestivalApiException.PublicReadFrozen> { repository.detail(player, rival, RivalDetailRequest.Scopes(listOf(RivalCombo.PRO_DRUMS_TOKEN))) }
        assertThrowsSuspend<FestivalApiException.PublicReadFrozen> {
            repository.detail(player, RivalsFixtures.RIVALS[3], RivalDetailRequest.Scopes(listOf("Solo_Guitar")))
        }
    }

    @Test
    fun onlyFrozenScopesAreFilledAndOtherFailuresStand() = runTest {
        val repository = repository({ scope ->
            when (scope) {
                "Solo_Bass" -> throw FestivalApiException.HttpStatus(503)
                "Solo_Drums" -> throw IOException("offline")
                else -> RivalDetailResponse(RivalIdentity(rival, "Named"), songs = listOf(RivalSongComparison("song-x", instrument = "Solo_Guitar", rankDelta = 2)))
            }
        }) { all() }
        val partial = repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar", "Solo_Bass")))
        assertEquals(listOf("song-x" to "Solo_Guitar", "song-c" to "Solo_Bass"), partial.songs.map { it.songId to it.instrument })
        assertThrowsSuspend<IOException> { repository.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Drums"))) }

        val allFails = repository({ throw FestivalApiException.Unavailable(null) }) { throw FestivalApiException.Unavailable(null) }
        assertThrowsSuspend<FestivalApiException.Unavailable> { allFails.detail(player, rival, RivalDetailRequest.Scopes(listOf("Solo_Guitar"))) }
    }

    @Test
    fun rivalsAllIsAnUnpinnedKeylessGet() = runTest {
        val transport = FakeTransport.standard()
        val client = FestivalApi("https://fixture.test", transport)
        assertTrue(client.rivalsAll(player).combos.isEmpty()) // 404
        transport.on("/api/player/$player/rivals/all") {
            """{"accountId":"$player","songs":["song-a"],"combos":[{"combo":"01","above":[{"accountId":"$rival","displayName":"R","direction":"above",""" +
                """"sharedSongCount":1,"aheadCount":0,"behindCount":1,"rivalScore":1.5,"samples":[{"s":0,"i":"Solo_Guitar","ur":2,"rr":1,"us":5,"rs":6}]}],"below":[]}]}"""
        }
        val all = client.rivalsAll(player)
        assertEquals("song-a", all.songId(all.combos.single().above.single().samples.single()))
        val request = transport.sent("/api/player/$player/rivals/all").last()
        assertEquals("GET", request.method)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected-") })
        transport.on("/api/player/$player/rivals/all") { """{"accountId":"$rival","combos":[]}""" }
        assertThrowsSuspend<FestivalApiException.InvalidResponse> { client.rivalsAll(player) }
        transport.onRaw("/api/player/$player/rivals/all") { HttpResult(503, ByteArray(0), mapOf("X-FST-Public-Read-Freeze-Reason" to "scrape")) }
        assertThrowsSuspend<FestivalApiException.PublicReadFrozen> { client.rivalsAll(player) }
        assertThrowsSuspend<FestivalApiException.InvalidResource> { client.rivalsAll("bad id") }
    }
}
