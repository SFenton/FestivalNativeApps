package com.festivalscoretracker.android.suggestions

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.suggestions.PlayerProfileWire
import com.festivalscoretracker.android.data.suggestions.PlayerScoreWire
import com.festivalscoretracker.android.data.suggestions.SuggestionFilterStore
import com.festivalscoretracker.android.data.suggestions.SuggestionScoresRead
import com.festivalscoretracker.android.data.suggestions.suggestionRivals
import com.festivalscoretracker.android.data.suggestions.suggestionScores
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Suggestions reads (player scores, `/rivals/all`) and the filter store. */
class SuggestionDataTest {
    private fun api(transport: com.festivalscoretracker.android.testing.FakeTransport) = FestivalApi("https://festivalscoretracker.com", transport)

    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit) {
        try {
            block()
            fail("Expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    // region Player scores

    @Test
    fun scoresExpandAccuracyAndIndexEveryChartKeylessly() = runTest {
        val transport = SuggestionFixtures.transport()
        val read = api(transport).suggestionScores(Fixtures.ACCOUNT_A) as SuggestionScoresRead.Available
        assertEquals(7, read.observedPublicationId)
        assertEquals(SuggestionFixtures.SCORED, read.index.size)
        val lead = read.index.getValue("sg-0").getValue(Instrument.Lead)
        assertEquals(990_000.0, lead.accuracy!!, 0.0)
        assertEquals(6, lead.stars)
        assertEquals(true, lead.isFullCombo)
        assertEquals(198_000, lead.score)
        assertEquals(setOf(Instrument.Lead, Instrument.Bass, Instrument.Drums), read.index.getValue("sg-3").keys)
        val sent = transport.sent("/api/player/${Fixtures.ACCOUNT_A}").single()
        assertTrue(sent.headers.keys.none { it.lowercase().startsWith("x-fst-selected-") || it.equals("x-api-key", true) })
        assertEquals("GET", sent.method)
    }

    @Test
    fun syncingEnvelopeIsNotAnEmptyProfile() = runTest {
        val transport = SuggestionFixtures.transport().apply {
            on("/api/player/${Fixtures.ACCOUNT_A}", status = 202) {
                """{"accountId":"${Fixtures.ACCOUNT_A}","totalScores":0,"scores":[],"status":"syncing","notYetPublished":true}"""
            }
        }
        assertSame(SuggestionScoresRead.Syncing, api(transport).suggestionScores(Fixtures.ACCOUNT_A))
    }

    @Test
    fun corruptProfilesAreRejected() {
        fun wire(scores: String, total: Int = 1, account: String = Fixtures.ACCOUNT_A, extra: String = "") = FestivalApi.JSON.decodeFromString(
            PlayerProfileWire.serializer(), """{"accountId":"$account","totalScores":$total,"scores":[$scores]$extra}""",
        )
        val good = """{"si":"a","ins":"01","sc":1}"""
        assertTrue(PlayerScoreWire.toRead(wire(good), Fixtures.ACCOUNT_A.uppercase(), 200, 1) is SuggestionScoresRead.Available)
        val bad = listOf(
            { PlayerScoreWire.toRead(wire(good, account = Fixtures.ACCOUNT_B), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire(good, total = 2), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("$good,$good", total = 2), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("""{"si":"a","ins":"01","sc":1,"st":7}"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("""{"si":"a","ins":"01","sc":1,"acc":1000.5}"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("""{"si":"a","ins":"01","sc":-1}"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("""{"si":"","ins":"01","sc":1}"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire("""{"si":"a","ins":"01","sc":1,"rk":-1}"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire(good), Fixtures.ACCOUNT_A, 202, 1) },
            { PlayerScoreWire.toRead(wire("", total = 0, extra = ""","status":"syncing","notYetPublished":true"""), Fixtures.ACCOUNT_A, 200, 1) },
            { PlayerScoreWire.toRead(wire(good, extra = ""","notYetPublished":true"""), Fixtures.ACCOUNT_A, 200, 1) },
        )
        bad.forEachIndexed { i, attempt ->
            try {
                attempt()
                fail("case $i accepted")
            } catch (expected: FestivalApiException.InvalidResponse) {
                // Rejected as corrupt.
            }
        }
    }

    @Test
    fun instrumentCodesAreSingleCanonicalBits() {
        assertEquals(Instrument.Lead, PlayerScoreWire.instrument("01"))
        assertEquals(Instrument.Karaoke, PlayerScoreWire.instrument("40"))
        assertEquals(Instrument.ProDrums, PlayerScoreWire.instrument("100"))
        listOf("1", "03", "00", "200", "0x1", "001", "zz", "1000").forEach { code ->
            assertThrows<FestivalApiException.InvalidResponse> { PlayerScoreWire.instrument(code) }
        }
    }

    @Test
    fun invalidAccountsNeverReachTheWire() = runTest {
        val transport = SuggestionFixtures.transport()
        assertThrows<FestivalApiException.InvalidResource> { kotlinx.coroutines.runBlocking { api(transport).suggestionScores("bad/id") } }
        assertThrows<FestivalApiException.InvalidResource> { kotlinx.coroutines.runBlocking { api(transport).suggestionRivals("bad/id") } }
        assertTrue(transport.requests.none { it.url.contains("/api/player") })
    }

    // endregion

    // region Rivals

    @Test
    fun rivalsDecodeAndA404IsEmpty() = runTest {
        val transport = SuggestionFixtures.transport()
        val rivals = api(transport).suggestionRivals(Fixtures.ACCOUNT_A)
        assertEquals(listOf("rv-a"), rivals.combos.single().above.map { it.accountId })
        transport.onRaw("/api/player/${Fixtures.ACCOUNT_A}/rivals/all") { HttpResult(404, """{"error":"No rivals found."}""".toByteArray()) }
        assertTrue(api(transport).suggestionRivals(Fixtures.ACCOUNT_A).combos.isEmpty())
        transport.onRaw("/api/player/${Fixtures.ACCOUNT_A}/rivals/all") { HttpResult(500, ByteArray(0)) }
        assertThrows<FestivalApiException.HttpStatus> { kotlinx.coroutines.runBlocking { api(transport).suggestionRivals(Fixtures.ACCOUNT_A) } }
        assertTrue(transport.requests.all { runCatching { RequestGate.validateKeyless(it) }.isSuccess })
    }

    // endregion

    // region Filter store

    @Test
    fun filterStorePersistsOnlyNonDefaultFilters() = runTest {
        val prefs = InMemoryPreferences()
        val store = SuggestionFilterStore(prefs)
        assertEquals(SuggestionFilterSettings.DEFAULTS, store.filter.first())
        val filter = SuggestionFilterSettings.DEFAULTS.withGlobalType(SuggestionCategoryType.Stale, false)
        store.save(filter)
        assertEquals(filter, store.filter.first())
        val key = stringPreferencesKey(SuggestionFilterSettings.STORAGE_KEY)
        assertTrue(prefs.data.first()[key]!!.contains("stale"))
        store.save(SuggestionFilterSettings.DEFAULTS)
        assertNull(prefs.data.first()[key])
        assertFalse(store.filter.first().isActive)
    }

    // endregion
}
