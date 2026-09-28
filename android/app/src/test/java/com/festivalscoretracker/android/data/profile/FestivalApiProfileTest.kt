package com.festivalscoretracker.android.data.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FestivalApiProfileTest {
    private val transport = FakeTransport.standard().also { ProfileFixtures.register(it) }
    private val api = FestivalApi("https://fixture.test", transport)

    private suspend inline fun <reified T : Throwable> expect(block: () -> Unit) {
        try {
            block()
            fail("expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    @Test
    fun profileReadCarriesHeaderProvenance() = runTest {
        val payload = api.playerProfile(Fixtures.ACCOUNT_A)
        assertEquals(PlayerProfileState.Available, payload.state)
        assertEquals(7, payload.publicationId)
        assertEquals(7, payload.observedPublicationId)
        assertTrue(payload.isSelectable(api.publicationChanges.value))
        assertEquals("Synthetic Player", payload.profile.displayName)
        val request = transport.sent("/api/player/${Fixtures.ACCOUNT_A}").single()
        RequestGate.validateKeyless(request)
        assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
    }

    @Test
    fun headerlessProfileIsPreviewOnly() = runTest {
        transport.on("/api/player/${Fixtures.ACCOUNT_B}") { ProfileFixtures.profile(Fixtures.ACCOUNT_B) }
        val payload = api.playerProfile(Fixtures.ACCOUNT_B)
        assertNull(payload.publicationId)
        assertEquals(false, payload.isSelectable(7))
    }

    @Test
    fun syncingAndMismatchedStatusAreHandled() = runTest {
        transport.on("/api/player/${Fixtures.ACCOUNT_B}", status = 202) { ProfileFixtures.syncing(Fixtures.ACCOUNT_B) }
        assertEquals(PlayerProfileState.Syncing, api.playerProfile(Fixtures.ACCOUNT_B).state)
        transport.on("/api/player/${Fixtures.ACCOUNT_B}", status = 200) { ProfileFixtures.syncing(Fixtures.ACCOUNT_B) }
        expect<FestivalApiException.InvalidResponse> { api.playerProfile(Fixtures.ACCOUNT_B) }
        transport.on("/api/player/${Fixtures.ACCOUNT_B}", status = 404) { "{}" }
        expect<FestivalApiException.HttpStatus> { api.playerProfile(Fixtures.ACCOUNT_B) }
        expect<FestivalApiException.InvalidResource> { api.playerProfile("bad id") }
    }

    @Test
    fun rankingReadMapsNotFoundToUnranked() = runTest {
        val ranked = api.playerInstrumentRanking(Instrument.Lead, Fixtures.ACCOUNT_A)
        assertEquals(8, ranked.ranking?.totalScoreRank)
        transport.on("/api/rankings/Solo_Bass/${Fixtures.ACCOUNT_A}", status = 404) { "{}" }
        assertNull(api.playerInstrumentRanking(Instrument.Bass, Fixtures.ACCOUNT_A).ranking)
        transport.on("/api/rankings/Solo_Drums/${Fixtures.ACCOUNT_A}", status = 500) { "{}" }
        expect<FestivalApiException.HttpStatus> { api.playerInstrumentRanking(Instrument.Drums, Fixtures.ACCOUNT_A) }
    }

    @Test
    fun rankHistoryReadValidates() = runTest {
        val history = api.playerRankHistory(Instrument.Lead, Fixtures.ACCOUNT_A)
        assertEquals(3, history.rankedChronological.size)
        assertTrue(transport.sent("/api/rankings/Solo_Guitar/${Fixtures.ACCOUNT_A}/history").single().url.endsWith("?days=30"))
        expect<FestivalApiException.InvalidResource> { api.playerRankHistory(Instrument.Lead, Fixtures.ACCOUNT_A, days = 0) }
        transport.on("/api/rankings/Solo_Bass/${Fixtures.ACCOUNT_A}/history") { ProfileFixtures.rankHistory(instrument = "Solo_Guitar") }
        expect<FestivalApiException.InvalidResponse> { api.playerRankHistory(Instrument.Bass, Fixtures.ACCOUNT_A) }
    }

    @Test
    fun historyReadDistinguishesUnregisteredAndSyncing() = runTest {
        val loaded = api.playerHistory(Fixtures.ACCOUNT_A, "s-alpha", Instrument.Lead)
        assertEquals(PlayerHistoryState.Available, loaded.state)
        assertEquals(2, loaded.entries("s-alpha", Instrument.Lead).size)
        val url = transport.sent("/api/player/${Fixtures.ACCOUNT_A}/history").single().url
        assertTrue(url, url.endsWith("?songId=s-alpha&instrument=Solo_Guitar"))
        transport.on("/api/player/${Fixtures.ACCOUNT_B}/history", status = 404) { "{}" }
        assertEquals(PlayerHistoryState.Unregistered, api.playerHistory(Fixtures.ACCOUNT_B, "s-alpha", Instrument.Lead).state)
        transport.on("/api/player/${Fixtures.ACCOUNT_B}/history", status = 202) {
            """{"accountId":"${Fixtures.ACCOUNT_B}","count":0,"history":[],"status":"syncing","notYetPublished":true}"""
        }
        assertEquals(PlayerHistoryState.Syncing, api.playerHistory(Fixtures.ACCOUNT_B, "s-alpha", Instrument.Lead).state)
        transport.on("/api/player/${Fixtures.ACCOUNT_B}/history", status = 500) { "{}" }
        expect<FestivalApiException.HttpStatus> { api.playerHistory(Fixtures.ACCOUNT_B, "s-alpha", Instrument.Lead) }
        expect<FestivalApiException.InvalidResource> { api.playerHistory(Fixtures.ACCOUNT_B, "a/b", Instrument.Lead) }
    }

    @Test
    fun cachedProfileKeepsItsProvenanceOn304() = runTest {
        transport.onRaw("/api/player/${Fixtures.ACCOUNT_B}") { request ->
            if (request.headers["If-None-Match"] == "W/\"p\"") {
                com.festivalscoretracker.android.data.HttpResult(304, ByteArray(0), mapOf("X-FST-Publication-Id" to "7"))
            } else {
                com.festivalscoretracker.android.data.HttpResult(
                    200,
                    ProfileFixtures.profile(Fixtures.ACCOUNT_B).toByteArray(),
                    mapOf("X-FST-Publication-Id" to "7", "ETag" to "W/\"p\""),
                )
            }
        }
        assertEquals(7, api.playerProfile(Fixtures.ACCOUNT_B).publicationId)
        assertEquals(7, api.playerProfile(Fixtures.ACCOUNT_B).publicationId)
        assertEquals(2, transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size)
    }
}
