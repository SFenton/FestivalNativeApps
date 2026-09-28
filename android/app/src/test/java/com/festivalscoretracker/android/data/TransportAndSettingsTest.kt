package com.festivalscoretracker.android.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.mutablePreferencesOf
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.testing.Fixtures
import java.io.File
import java.io.IOException
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class TransportAndSettingsTest {
    private lateinit var server: MockWebServer
    private lateinit var dir: File

    @Before
    fun setUp() {
        server = MockWebServer().apply { start(java.net.InetAddress.getByName("127.0.0.1"), 0) }
        dir = Files.createTempDirectory("fst-settings").toFile()
    }

    @After
    fun tearDown() {
        server.shutdown()
        dir.deleteRecursively()
    }

    // region OkHttp transport

    @Test
    fun okHttpTransportSendsHeadersAndReturnsStatusBodyAndHeaders() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(503).setHeader("Retry-After", "30").setBody("frozen"))
        val transport = OkHttpTransport()
        val result = transport.send(RequestGate.makeRequest(server.url("/api/songs").toString(), mapOf("If-None-Match" to "e1")))
        assertEquals(503, result.status)
        assertEquals("30", result.header("retry-after"))
        assertEquals("frozen", String(result.body))
        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("no-cache", recorded.getHeader("Cache-Control"))
        assertEquals("e1", recorded.getHeader("If-None-Match"))
        assertNull(recorded.getHeader("X-API-Key"))
    }

    @Test
    fun okHttpTransportSurfacesConnectivityFailures() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
        try {
            OkHttpTransport().send(RequestGate.makeRequest(server.url("/api/songs").toString()))
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun liveClientUsesThirtySecondTimeoutsAndNoCache() {
        val client = OkHttpTransport.defaultClient()
        assertEquals(30_000, client.readTimeoutMillis)
        assertEquals(30_000, client.connectTimeoutMillis)
        assertNull(client.cache)
    }

    @Test
    fun endToEndThroughMockServer() = runBlocking {
        server.enqueue(MockResponse().setBody(Fixtures.publication()))
        server.enqueue(MockResponse().setBody(Fixtures.songsJson).setHeader("X-FST-Publication-Id", "7"))
        val api = FestivalApi("http://127.0.0.1:${server.port}", OkHttpTransport())
        assertEquals(3, api.catalog().catalog.songs.size)
    }

    // endregion

    // region Settings

    private fun repository(scope: CoroutineScope) = SettingsRepository(
        PreferenceDataStoreFactory.create(scope = scope, produceFile = { File(dir, "fst_settings.preferences_pb") }),
    )

    /**
     * One real on-disk write, then a fresh DataStore instance (a cold start) reads it back.
     * Further setters are covered with an in-memory store: DataStore replaces its file by
     * rename, which the Windows JVM refuses when the target exists (Android is unaffected).
     */
    @Test
    fun selectedProfilePersistsAcrossColdStarts() = runBlocking {
        val first = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val repo = repository(first)
        assertEquals(Instrument.entries.toSet(), repo.settings.first().visibleInstruments)
        repo.setSelectedPlayer(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        first.coroutineContext[Job]!!.cancelAndJoin()

        val second = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val reloaded = repository(second).settings.first()
        assertEquals(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), reloaded.selectedPlayer)
        assertEquals(SongSortMode.Title, reloaded.songSort)
        assertTrue(reloaded.songSortAscending)
        second.coroutineContext[Job]!!.cancelAndJoin()
    }

    @Test
    fun settersRoundTripAndInvalidStoredProfileIsIgnored() = runBlocking {
        val repo = SettingsRepository(com.festivalscoretracker.android.presentation.InMemoryPreferences())
        repo.setSelectedPlayer(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        repo.setInstrumentVisible(Instrument.Karaoke, false)
        repo.setInstrumentVisible(Instrument.Karaoke, true)
        repo.setInstrumentVisible(Instrument.Bass, false)
        repo.setSongSort(SongSortMode.Year, false)
        repo.setIncreaseContrast(true)
        repo.setReduceMotion(true)
        val stored = repo.settings.first()
        assertEquals("Synthetic Player", stored.selectedPlayer?.displayName)
        assertFalse(Instrument.Bass in stored.visibleInstruments)
        assertTrue(Instrument.Karaoke in stored.visibleInstruments)
        assertEquals(SongSortMode.Year, stored.songSort)
        assertFalse(stored.songSortAscending)
        assertTrue(stored.increaseContrast && stored.reduceMotion)
        repo.setSelectedPlayer(null)
        assertNull(repo.settings.first().selectedPlayer)
        val corrupt = mutablePreferencesOf(
            SettingsRepository.KEY_ACCOUNT_ID to "not-an-id",
            SettingsRepository.KEY_DISPLAY_NAME to "Name",
        )
        assertNull(SettingsRepository.decode(corrupt).selectedPlayer)
        val partial = mutablePreferencesOf(SettingsRepository.KEY_ACCOUNT_ID to Fixtures.ACCOUNT_A)
        assertNull(SettingsRepository.decode(partial).selectedPlayer)
    }

    // endregion
}
