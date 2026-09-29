package com.festivalscoretracker.android.bands

import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.bands.BandEndpoints
import com.festivalscoretracker.android.data.bands.bandProfile
import com.festivalscoretracker.android.data.bands.bandRankHistory
import com.festivalscoretracker.android.data.bands.bandSongExtremes
import com.festivalscoretracker.android.data.bands.playerBands
import com.festivalscoretracker.android.data.bands.songBandLeaderboard
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class BandsApiTest {
    private val base = "https://fixture.test".toHttpUrl()
    private val transport = BandFixtures.install(FakeTransport.standard())
    private val api = FestivalApi("https://fixture.test", transport)

    private suspend inline fun <reified T : Throwable> expect(noinline block: suspend () -> Unit): T {
        try {
            block()
        } catch (error: Throwable) {
            if (error is T) return error
            throw error
        }
        fail("expected ${T::class.simpleName}")
        throw IllegalStateException()
    }

    @Test
    fun endpointUrls() {
        assertEquals(
            "https://fixture.test/api/player/${Fixtures.ACCOUNT_A}/bands?group=trios&page=2&pageSize=25",
            BandEndpoints.playerBands(Fixtures.ACCOUNT_A, PlayerBandGroup.Trios, 2, 25).url(base),
        )
        assertEquals(
            "https://fixture.test/api/rankings/bands/Band_Duets?teamKey=a%3Ab&rankBy=adjusted&page=1&pageSize=1",
            BandEndpoints.bandProfile(BandType.Duets, "a:b").url(base),
        )
        assertEquals("https://fixture.test/api/rankings/bands/Band_Quad/a:b/history?days=30", BandEndpoints.bandRankHistory(BandType.Quad, "a:b", 30).url(base))
        assertEquals("https://fixture.test/api/rankings/bands/Band_Trios/a/songs?limit=5", BandEndpoints.bandSongExtremes(BandType.Trios, "a", 5).url(base))
        assertEquals("https://fixture.test/api/leaderboard/s-1/bands/Band_Duets?top=25&offset=50", BandEndpoints.songBandLeaderboard("s-1", BandType.Duets, 25, 50).url(base))
        assertEquals(
            "https://fixture.test/api/leaderboard/s-1/bands/Band_Duets?top=10&offset=0&accountId=${Fixtures.ACCOUNT_A}",
            BandEndpoints.songBandLeaderboard("s-1", BandType.Duets, 10, 0, Fixtures.ACCOUNT_A).url(base),
        )
    }

    @Test
    fun endpointValidation() {
        listOf(
            { BandEndpoints.playerBands("bad/id", PlayerBandGroup.All, 1, 25) },
            { BandEndpoints.playerBands(Fixtures.ACCOUNT_A, PlayerBandGroup.All, 0, 25) },
            { BandEndpoints.playerBands(Fixtures.ACCOUNT_A, PlayerBandGroup.All, 1, 101) },
            { BandEndpoints.bandProfile(BandType.Duets, "../x") },
            { BandEndpoints.bandRankHistory(BandType.Duets, "a", 0) },
            { BandEndpoints.bandRankHistory(BandType.Duets, "a", 3651) },
            { BandEndpoints.bandRankHistory(BandType.Duets, "", 30) },
            { BandEndpoints.bandSongExtremes(BandType.Duets, "a", 21) },
            { BandEndpoints.bandSongExtremes(BandType.Duets, "a:b:c:d:e", 5) },
            { BandEndpoints.songBandLeaderboard("..", BandType.Duets, 25, 0) },
            { BandEndpoints.songBandLeaderboard("s", BandType.Duets, 0, 0) },
            { BandEndpoints.songBandLeaderboard("s", BandType.Duets, 25, -1) },
            { BandEndpoints.songBandLeaderboard("s", BandType.Duets, 25, 0, "bad/id") },
        ).forEach { assertThrows(FestivalApiException.InvalidResource::class.java) { it() } }
    }

    @Test
    fun readsDecodeAndValidate() = runTest {
        val page = api.playerBands(BandFixtures.PLAYER, PlayerBandGroup.All, 2, 25)
        assertEquals(30, page.totalCount)
        assertEquals(5, page.entries.size)
        val detail = api.bandProfile(BandType.Duets, BandFixtures.DUO_KEY)
        assertEquals(BandFixtures.DUO_ID, detail.bandId)
        val history = api.bandRankHistory(BandType.Duets, BandFixtures.DUO_KEY, 30)
        assertEquals(4, history.history.size)
        val songs = api.bandSongExtremes(BandType.Duets, BandFixtures.DUO_KEY, 5)
        assertEquals("s-alpha", songs.best.single().songId)
        val board = api.songBandLeaderboard("s-alpha", BandType.Trios, 2, 25)
        assertEquals(26, board.entries.first().rank)
        assertNull(board.selectedPlayerEntry)
        // With the selected player: their band row comes back; outside the page it's appended.
        val duos = api.songBandLeaderboard("s-alpha", BandType.Duets, 1, 10, BandFixtures.PLAYER)
        assertEquals(12, duos.selectedOutsidePage?.rank)
        val trios = api.songBandLeaderboard("s-alpha", BandType.Trios, 1, 10, BandFixtures.PLAYER)
        assertEquals(2, trios.selectedPlayerEntry?.rank)
        assertNull(trios.selectedOutsidePage)
        assertTrue(trios.entries[1].sameBand(trios.selectedPlayerEntry!!))
        assertFalse(trios.entries[0].sameBand(trios.selectedPlayerEntry!!))
        assertTrue(trios.entries[0].copy(bandId = "").sameBand(trios.entries[0].copy(bandId = "")))
        // Every band read went through the keyless gate, GET only, and never touched a blocked route.
        transport.requests.forEach { RequestGate.validateKeyless(it) }
        val paths = transport.requests.map { it.url.substringAfter("fixture.test").substringBefore('?') }
        assertTrue(paths.none { it.startsWith("/api/bands/") })
        assertTrue(paths.none { Regex("^/api/rankings/bands/[^/]+/[^/]+$").matches(it) })
        assertTrue(paths.none { "/sync-status" in it || it.startsWith("/api/bands/search") })
    }

    @Test
    fun unrankedTeamIs404AndMismatchesAreInvalid() = runTest {
        val unknown = "${Fixtures.ACCOUNT_B}:${Fixtures.ACCOUNT_A}"
        assertEquals(404, expect<FestivalApiException.HttpStatus> { api.bandProfile(BandType.Duets, unknown) }.status)
        transport.on("/api/rankings/bands/Band_Trios") { BandFixtures.bandProfile(bandType = "Band_Duets") }
        expect<FestivalApiException.InvalidResponse> { api.bandProfile(BandType.Trios, BandFixtures.DUO_KEY) }
        transport.on("/api/rankings/bands/Band_Quad") { BandFixtures.bandProfile(bandType = "Band_Quad", teamKey = "other") }
        expect<FestivalApiException.InvalidResponse> { api.bandProfile(BandType.Quad, BandFixtures.DUO_KEY) }
        transport.on("/api/rankings/bands/Band_Trios/a/history") { BandFixtures.history() }
        expect<FestivalApiException.InvalidResponse> { api.bandRankHistory(BandType.Trios, "a", 30) }
        transport.on("/api/rankings/bands/Band_Trios/a/songs") { BandFixtures.songs }
        expect<FestivalApiException.InvalidResponse> { api.bandSongExtremes(BandType.Trios, "a", 5) }
        transport.on("/api/player/${Fixtures.ACCOUNT_B}/bands") { BandFixtures.playerBands(3, 1, 25) }
        expect<FestivalApiException.InvalidResponse> { api.playerBands(Fixtures.ACCOUNT_B, PlayerBandGroup.All, 1, 25) }
        transport.on("/api/player/${Fixtures.ACCOUNT_B}/bands") { "not json" }
        expect<FestivalApiException.InvalidResponse> { api.playerBands(Fixtures.ACCOUNT_B, PlayerBandGroup.All, 1, 25) }
        expect<FestivalApiException.InvalidResource> { api.songBandLeaderboard("s-alpha", BandType.Duets, 0, 25) }
        expect<FestivalApiException.InvalidResource> { api.songBandLeaderboard("s-alpha", BandType.Duets, Int.MAX_VALUE, 25) }
    }

    @Test
    fun songsProjectionFreezeIsAServiceIssue() = runTest {
        transport.onRaw("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/songs") {
            com.festivalscoretracker.android.data.HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30"))
        }
        expect<FestivalApiException.Unavailable> { api.bandSongExtremes(BandType.Duets, BandFixtures.DUO_KEY, 5) }
        transport.on("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/songs") {
            BandFixtures.songs.replace("\"worst\":[", "\"worst\":[" + List(6) { """{"songId":"x$it"},""" }.joinToString(""))
        }
        expect<FestivalApiException.InvalidResponse> { api.bandSongExtremes(BandType.Duets, BandFixtures.DUO_KEY, 5) }
    }
}
