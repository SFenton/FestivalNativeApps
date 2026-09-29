package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.paths.PathCapability
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.paths.PathImageValidation
import com.festivalscoretracker.android.core.paths.SongPathData
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongShopFilter
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.paths.pathData
import com.festivalscoretracker.android.data.paths.pathEndpoint
import com.festivalscoretracker.android.data.paths.pathImage
import com.festivalscoretracker.android.data.shop.shop
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.SongsFixtures
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SongsDataTest {
    private fun transport() = FakeTransport.standard().apply {
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, SongsFixtures.png(), mapOf("X-FST-Publication-Id" to "7")) }
    }

    // region Shop

    @Test
    fun shopReadIsKeylessPinnedAndValidated() = runTest {
        val transport = transport()
        val api = FestivalApi("https://fixture.test", transport)
        val shop = api.shop()
        assertEquals(3, shop.shop.count)
        assertEquals(7, shop.publicationId)
        assertEquals(7, shop.observedPublicationId)
        assertTrue(shop.offersById.getValue("s-alpha").leavingTomorrow)
        transport.requests.forEach(RequestGate::validateKeyless)
        transport.on("/api/shop") { """{"count":1,"songs":[{"songId":"x","title":"T","artist":"A","shopUrl":"https://evil.example/x"}]}""" }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { kotlinx.coroutines.runBlocking { api.shop() } }
        transport.onRaw("/api/shop") { HttpResult(200, ByteArray(4_000_001)) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { kotlinx.coroutines.runBlocking { api.shop() } }
    }

    // endregion

    // region Paths

    @Test
    fun pathEndpointsValidateAndEncode() {
        val base = "https://fixture.test".toHttpUrl()
        assertEquals(
            "https://fixture.test/api/paths/s-a/Solo_Bass/hard/data?generationId=g%201",
            pathEndpoint("s-a", Instrument.Bass, PathDifficulty.Hard, text = true, generationId = "g 1").url(base),
        )
        assertEquals("https://fixture.test/api/paths/s-a/Solo_Bass/easy", pathEndpoint("s-a", Instrument.Bass, PathDifficulty.Easy, false, null).url(base))
        assertThrows(FestivalApiException.InvalidResource::class.java) { pathEndpoint("s", Instrument.Karaoke, PathDifficulty.Easy, false, null) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { pathEndpoint("s", Instrument.Lead, PathDifficulty.Easy, false, "") }
        assertThrows(FestivalApiException.InvalidResource::class.java) { pathEndpoint("s", Instrument.Lead, PathDifficulty.Easy, false, "x".repeat(201)) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { pathEndpoint("a/b", Instrument.Lead, PathDifficulty.Easy, false, null).url(base) }
    }

    @Test
    fun pathDataAndImageReads() = runTest {
        val transport = transport()
        val api = FestivalApi("https://fixture.test", transport)
        val data = api.pathData("s-alpha", Instrument.Lead, PathDifficulty.Expert)
        assertEquals(123456L, data.path.totalScore)
        assertEquals(3, data.rows.size)
        assertEquals(7, data.publicationId)
        val image = api.pathImage("s-alpha", Instrument.Lead, PathDifficulty.Expert)
        assertEquals(100 to 200, image.width to image.height)
        transport.requests.forEach(RequestGate::validateKeyless)
        // Wrong difficulty in the body is rejected.
        transport.on("/api/paths/s-alpha/Solo_Guitar/hard/data") { SongsFixtures.pathJson }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { kotlinx.coroutines.runBlocking { api.pathData("s-alpha", Instrument.Lead, PathDifficulty.Hard) } }
        // A 404 (not generated) surfaces as an HTTP status.
        assertThrows(FestivalApiException.HttpStatus::class.java) { kotlinx.coroutines.runBlocking { api.pathImage("s-beta", Instrument.Lead, PathDifficulty.Expert) } }
    }

    @Test
    fun pathRowsResolveAnchorsAndFormat() {
        val path = FestivalApi.JSON.decodeFromString(SongPathData.serializer(), SongsFixtures.pathJson)
        path.validate(PathDifficulty.Expert)
        val rows = path.activationRows()
        val first = rows[0]
        assertEquals(1, first.number)
        assertEquals(listOf("green", "red", "open"), first.frets)
        assertEquals("01:05:432", first.timeText)
        assertEquals("50%", first.odText)
        assertEquals("45,000", first.scoreText(Locale.US))
        assertEquals("10.01", first.beatText(Locale.US))
        assertEquals("green, red, open", first.fretsText)
        val second = rows[1]
        assertEquals(listOf("yellow"), second.frets)
        assertEquals("25%", second.odText)
        assertEquals("90,000", second.scoreText(Locale.US))
        val third = rows[2]
        assertEquals("No anchor", third.fretsText)
        assertEquals("Unavailable", third.odText)
        assertEquals("Unavailable", third.scoreText(Locale.US))
        assertEquals("02:00:000", third.timeText)
    }

    @Test
    fun pathValidationRejectsBadData() {
        val good = FestivalApi.JSON.decodeFromString(SongPathData.serializer(), SongsFixtures.pathJson)
        fun invalid(path: SongPathData) = assertThrows(FestivalApiException.InvalidResponse::class.java) { path.validate(PathDifficulty.Expert) }
        invalid(good.copy(schemaVersion = 3))
        invalid(good.copy(totalScore = 0))
        invalid(good.copy(songName = ""))
        invalid(good.copy(activations = listOf(good.activations[0].copy(endBeat = 1.0))))
        invalid(good.copy(activations = listOf(good.activations[0].copy(odAtActivation = 2.0))))
        invalid(good.copy(activations = listOf(good.activations[0].copy(activationSeconds = -1.0))))
        invalid(good.copy(activations = listOf(good.activations[0].copy(instruction = "x".repeat(501)))))
        invalid(good.copy(notes = listOf(good.notes[0].copy(frets = mapOf("purple" to 0.0)))))
        invalid(good.copy(notes = listOf(good.notes[0].copy(beat = Double.NaN))))
        good.copy(schemaVersion = null).validate(PathDifficulty.Expert)
    }

    @Test
    fun pathImageHeaderIsBounded() {
        assertEquals(100 to 200, PathImageValidation.dimensions(SongsFixtures.png()))
        listOf(
            ByteArray(10),
            SongsFixtures.png().also { it[1] = 0 },
            SongsFixtures.png().also { it[12] = 0 },
            SongsFixtures.png(width = 0),
            SongsFixtures.png(width = 9_000),
            SongsFixtures.png(height = 30_001),
            SongsFixtures.png(width = 8_000, height = 4_000),
        ).forEach { bytes -> assertThrows(FestivalApiException.InvalidResponse::class.java) { PathImageValidation.dimensions(bytes) } }
    }

    @Test
    fun pathCapabilityRules() {
        assertFalse(PathCapability.hasPaths(Instrument.Karaoke))
        assertEquals(
            listOf(Instrument.Lead, Instrument.Drums),
            PathCapability.menuInstruments(setOf(Instrument.Drums, Instrument.Lead, Instrument.Karaoke, Instrument.Bass)) { it != Instrument.Bass },
        )
        assertTrue(PathCapability.showsKaraokeWarning(setOf(Instrument.Karaoke), dismissed = false))
        assertFalse(PathCapability.showsKaraokeWarning(setOf(Instrument.Karaoke), dismissed = true))
        assertFalse(PathCapability.showsKaraokeWarning(setOf(Instrument.Lead), dismissed = false))
    }

    // endregion

    // region Preferences

    @Test
    fun preferencesRoundTripAndClear() = runTest {
        val prefs = SongsPreferences(SettingsRepository(InMemoryPreferences()))
        assertEquals(SongsPreferencesState(), prefs.state.first())
        assertFalse(prefs.state.first().anyFilterActive)
        val player = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead))
        prefs.setFilters(SongFilter(Instrument.Bass, setOf(0, 7)), SongShopFilter(inShop = true), player)
        val saved = prefs.state.first()
        assertEquals(SongFilter(Instrument.Bass, setOf(0, 7)), saved.filter)
        assertEquals(SongShopFilter(inShop = true), saved.shopFilter)
        assertEquals(player, saved.playerFilter)
        assertTrue(saved.anyFilterActive)
        prefs.clearPlayerFilter()
        assertEquals(SongPlayerScoreFilter(), prefs.state.first().playerFilter)
        assertTrue(prefs.state.first().shopFilter.inShop)
        prefs.clearFilters()
        assertEquals(SongsPreferencesState(), prefs.state.first())
        prefs.setShopViewMode(ShopViewMode.List)
        assertEquals(ShopViewMode.List, prefs.state.first().shopViewMode)
        prefs.setFilters(SongFilter(), SongShopFilter(), SongPlayerScoreFilter())
        assertEquals(SongFilter(), prefs.state.first().filter)
    }

    @Test
    fun corruptSavedStateIsExplicit() = runTest {
        val repository = SettingsRepository(InMemoryPreferences())
        val prefs = SongsPreferences(repository)
        repository.writeBlob(com.festivalscoretracker.android.core.settings.SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, "{broken")
        assertNull(prefs.state.first().playerFilter)
        assertEquals(SongFilter() to SongShopFilter(), SongsPreferences.decodePublic("{bad"))
        // Retired range keys are ignored; unknown or duplicate intensity keys drop the buckets but keep the instrument.
        assertEquals(SongFilter() to SongShopFilter(leavingTomorrow = true), SongsPreferences.decodePublic("""{"minDifficulty":6,"maxDifficulty":2,"leavingTomorrow":true}"""))
        assertEquals(SongFilter(Instrument.Bass) to SongShopFilter(), SongsPreferences.decodePublic("""{"instrument":"Solo_Bass","excludedIntensities":[9]}"""))
        assertEquals(SongFilter(Instrument.Bass) to SongShopFilter(), SongsPreferences.decodePublic("""{"instrument":"Solo_Bass","excludedIntensities":[2,2]}"""))
        assertEquals(SongFilter(null, setOf(3)) to SongShopFilter(), SongsPreferences.decodePublic(SongsPreferences.encodePublic(SongFilter(null, setOf(3)), SongShopFilter())))
        assertNull(SongsPreferences.encodePublic(SongFilter(), SongShopFilter()))
    }

    @Test
    fun deselectionClearsOnlyPlayerPredicates() = runTest {
        val repository = SettingsRepository(InMemoryPreferences())
        val prefs = SongsPreferences(repository)
        prefs.setFilters(SongFilter(), SongShopFilter(inShop = true), SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)))
        val players = MutableStateFlow<SelectedPlayer?>(null)
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        prefs.watchDeselection(scope, players)
        scope.advanceUntilIdle()
        assertTrue(prefs.state.first().playerFilter!!.isActive)
        players.value = SelectedPlayer("0123456789abcdef0123456789abcdef", "A")
        scope.advanceUntilIdle()
        players.value = SelectedPlayer("fedcba9876543210fedcba9876543210", "B")
        scope.advanceUntilIdle()
        assertTrue(prefs.state.first().playerFilter!!.isActive)
        players.value = null
        scope.advanceUntilIdle()
        assertFalse(prefs.state.first().playerFilter!!.isActive)
        assertTrue(prefs.state.first().shopFilter.inShop)
        scope.cancel()
    }

    // endregion
}

private fun TestScope.cancel() = coroutineContext[kotlinx.coroutines.Job]?.cancel()
