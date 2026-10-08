package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.paths.PathCapability
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.paths.PathImageValidation
import com.festivalscoretracker.android.core.paths.SongPathData
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.shop.ShopSortChoice
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongGeneralFilter
import com.festivalscoretracker.android.core.songs.SongSortMode
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
        assertFalse(prefs.state.first().filterActive(hasPlayer = true, hideShop = false))
        val player = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead))
        val general = SongGeneralFilter(
            excludedDecades = setOf(1970, 2020), excludedDurations = setOf(0, 10), shopUnavailable = false, doubleBassUnsupported = false,
        )
        prefs.setFilters(SongFilter(Instrument.Bass, setOf(0, 7)), general, player)
        val saved = prefs.state.first()
        assertEquals(SongFilter(Instrument.Bass, setOf(0, 7)), saved.filter)
        assertEquals(general, saved.general)
        assertEquals(player, saved.playerFilter)
        assertTrue(saved.filterActive(hasPlayer = true, hideShop = false))
        prefs.resetForDeselect()
        // Deselection resets every filter, General included (web resetSongSettingsForDeselect, #359).
        assertEquals(SongsPreferencesState(), prefs.state.first())
        assertEquals(SongsPreferencesState(), prefs.state.first())
        prefs.setShopViewMode(ShopViewMode.List)
        assertEquals(ShopViewMode.List, prefs.state.first().shopViewMode)
        // Item Shop sort (#379) persists and survives a player deselect (it uses no scores).
        assertEquals(ShopSortChoice(), prefs.state.first().shopSort)
        prefs.setShopSort(ShopSortChoice(SongSortMode.Duration, ascending = false))
        assertEquals(ShopSortChoice(SongSortMode.Duration, false), prefs.state.first().shopSort)
        prefs.resetForDeselect()
        assertEquals(ShopSortChoice(SongSortMode.Duration, false), prefs.state.first().shopSort)
        prefs.setShopSort(ShopSortChoice())
        assertEquals(ShopSortChoice(), prefs.state.first().shopSort)
        prefs.setFilters(SongFilter(), SongGeneralFilter(), SongPlayerScoreFilter())
        assertEquals(SongFilter(), prefs.state.first().filter)
    }

    @Test
    fun filterIndicatorFollowsWebIsFilterActive() {
        val none = SongsPreferencesState()
        assertFalse(none.filterActive(hasPlayer = false, hideShop = false))
        // General filters count with or without a player; Item Shop only while shown.
        val year = SongsPreferencesState(general = SongGeneralFilter(excludedDecades = setOf(1990)))
        assertTrue(year.filterActive(hasPlayer = false, hideShop = false))
        assertTrue(year.filterActive(hasPlayer = true, hideShop = true))
        val shop = SongsPreferencesState(general = SongGeneralFilter(shopAvailable = false))
        assertTrue(shop.filterActive(hasPlayer = false, hideShop = false))
        assertFalse(shop.filterActive(hasPlayer = false, hideShop = true))
        // Instrument and score filters only with a player.
        val instrument = SongsPreferencesState(filter = SongFilter(Instrument.Lead))
        assertFalse(instrument.filterActive(hasPlayer = false, hideShop = false))
        assertTrue(instrument.filterActive(hasPlayer = true, hideShop = false))
        val score = SongsPreferencesState(playerFilter = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)))
        assertFalse(score.filterActive(hasPlayer = false, hideShop = false))
        assertTrue(score.filterActive(hasPlayer = true, hideShop = false))
        assertFalse(SongsPreferencesState(playerFilter = null).filterActive(hasPlayer = true, hideShop = false))
    }

    @Test
    fun filterStateDescriptionSpeaksWhatTheGoldTintShows() {
        val none = SongsPreferencesState()
        assertEquals("No filters", none.filterStateDescription(hasPlayer = false, hideShop = false))
        assertEquals("No filters", SongsPreferencesState(playerFilter = null).filterStateDescription(hasPlayer = true, hideShop = false))
        val general = SongsPreferencesState(
            general = SongGeneralFilter(
                excludedDecades = setOf(1990),
                excludedDurations = setOf(3),
                shopUnavailable = false,
                doubleBassUnsupported = false,
            ),
        )
        assertEquals("Filters on: Year, Duration, Item Shop, Double Bass", general.filterStateDescription(hasPlayer = false, hideShop = false))
        // Item Shop only while shown.
        assertEquals("Filters on: Year, Duration, Double Bass", general.filterStateDescription(hasPlayer = false, hideShop = true))
        val player = SongsPreferencesState(
            filter = SongFilter(Instrument.Lead),
            general = SongGeneralFilter(doubleBassSupported = false),
            playerFilter = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead), excludedStars = setOf(6)),
        )
        assertEquals("Filters on: Double Bass, Score & FC, Selected Instrument", player.filterStateDescription(hasPlayer = true, hideShop = false))
        // Without a player only General counts, like the gold tint.
        assertEquals("Filters on: Double Bass", player.filterStateDescription(hasPlayer = false, hideShop = false))
        // Spoken state and tint always agree.
        listOf(none, general, player, SongsPreferencesState(general = SongGeneralFilter(shopAvailable = false))).forEach { state ->
            listOf(true, false).forEach { hasPlayer ->
                listOf(true, false).forEach { hideShop ->
                    assertEquals(
                        state.filterActive(hasPlayer, hideShop),
                        state.filterStateDescription(hasPlayer, hideShop) != "No filters",
                    )
                }
            }
        }
    }

    @Test
    fun generalFiltersMigrateAndSanitize() {
        // Retired Shop toggles become "Available in Item Shop" only (web `migrateShopAvailability`).
        assertEquals(SongGeneralFilter(shopUnavailable = false), SongsPreferences.decodePublic("""{"inShop":true}""").second)
        assertEquals(SongGeneralFilter(shopUnavailable = false), SongsPreferences.decodePublic("""{"leavingTomorrow":true}""").second)
        assertEquals(SongGeneralFilter(), SongsPreferences.decodePublic("""{"inShop":false}""").second)
        // New keys win over the retired ones.
        assertEquals(SongGeneralFilter(shopAvailable = false), SongsPreferences.decodePublic("""{"inShop":true,"shopAvailable":false,"shopUnavailable":true}""").second)
        // Malformed decade/duration lists drop only that section.
        assertEquals(
            SongGeneralFilter(excludedDurations = setOf(2), doubleBassSupported = false),
            SongsPreferences.decodePublic("""{"excludedDecades":[1985],"excludedDurations":[2],"doubleBassSupported":false}""").second,
        )
        assertEquals(SongGeneralFilter(excludedDecades = setOf(1990)), SongsPreferences.decodePublic("""{"excludedDecades":[1990],"excludedDurations":[3,3]}""").second)
        assertEquals(SongGeneralFilter(), SongsPreferences.decodePublic("""{"excludedDurations":[11]}""").second)
        val general = SongGeneralFilter(setOf(1980), setOf(10), shopAvailable = false, doubleBassSupported = false)
        assertEquals(SongFilter() to general, SongsPreferences.decodePublic(SongsPreferences.encodePublic(SongFilter(), general)))
    }

    @Test
    fun corruptSavedStateIsExplicit() = runTest {
        val repository = SettingsRepository(InMemoryPreferences())
        val prefs = SongsPreferences(repository)
        repository.writeBlob(com.festivalscoretracker.android.core.settings.SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, "{broken")
        assertNull(prefs.state.first().playerFilter)
        assertEquals(SongFilter() to SongGeneralFilter(), SongsPreferences.decodePublic("{bad"))
        // Retired range keys are ignored; unknown or duplicate intensity keys drop the buckets but keep the instrument.
        assertEquals(SongFilter() to SongGeneralFilter(shopUnavailable = false), SongsPreferences.decodePublic("""{"minDifficulty":6,"maxDifficulty":2,"leavingTomorrow":true}"""))
        assertEquals(SongFilter(Instrument.Bass) to SongGeneralFilter(), SongsPreferences.decodePublic("""{"instrument":"Solo_Bass","excludedIntensities":[9]}"""))
        assertEquals(SongFilter(Instrument.Bass) to SongGeneralFilter(), SongsPreferences.decodePublic("""{"instrument":"Solo_Bass","excludedIntensities":[2,2]}"""))
        assertEquals(SongFilter(null, setOf(3)) to SongGeneralFilter(), SongsPreferences.decodePublic(SongsPreferences.encodePublic(SongFilter(null, setOf(3)), SongGeneralFilter())))
        assertNull(SongsPreferences.encodePublic(SongFilter(), SongGeneralFilter()))
    }

    @Test
    fun deselectionResetsFiltersLikeTheWeb() = runTest {
        val repository = SettingsRepository(InMemoryPreferences())
        val prefs = SongsPreferences(repository)
        prefs.setFilters(SongFilter(Instrument.Bass), SongGeneralFilter(shopUnavailable = false), SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)))
        repository.setSongSort(SongSortMode.Intensity, false)
        val players = MutableStateFlow<SelectedPlayer?>(null)
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        prefs.watchDeselection(scope, players)
        scope.advanceUntilIdle()
        assertTrue(prefs.state.first().playerFilter!!.isActive)
        players.value = SelectedPlayer("0123456789abcdef0123456789abcdef", "A")
        scope.advanceUntilIdle()
        // A player-to-player switch keeps everything (web shouldResetSongSettingsForProfileChange).
        players.value = SelectedPlayer("fedcba9876543210fedcba9876543210", "B")
        scope.advanceUntilIdle()
        assertTrue(prefs.state.first().playerFilter!!.isActive)
        assertEquals(SongSortMode.Intensity, repository.settings.first().songSort)
        players.value = null
        scope.advanceUntilIdle()
        // Deselect: default filters (General included) and a single-chart sort back to Title ascending.
        assertEquals(SongsPreferencesState(), prefs.state.first())
        assertEquals(SongSortMode.Title, repository.settings.first().songSort)
        assertTrue(repository.settings.first().songSortAscending)
        scope.cancel()
    }

    @Test
    fun deselectResetKeepsCatalogueSortsAndOnlyFiresWhenAProfileLeaves() = runTest {
        val a = SelectedPlayer("0123456789abcdef0123456789abcdef", "A")
        val b = SelectedPlayer("fedcba9876543210fedcba9876543210", "B")
        assertFalse(shouldResetSongsForProfileChange(null, null))
        assertFalse(shouldResetSongsForProfileChange(null, a))
        assertFalse(shouldResetSongsForProfileChange(a, b))
        assertFalse(shouldResetSongsForProfileChange(a, a))
        assertTrue(shouldResetSongsForProfileChange(a, null))

        val repository = SettingsRepository(InMemoryPreferences())
        val prefs = SongsPreferences(repository)
        repository.setSongSort(SongSortMode.Year, false)
        prefs.resetForDeselect()
        assertEquals(SongSortMode.Year, repository.settings.first().songSort)
        assertFalse(repository.settings.first().songSortAscending)
        listOf(SongSortMode.HasFC, SongSortMode.LastPlayed, SongSortMode.Score, SongSortMode.MaxScoreDiff).forEach { mode ->
            repository.setSongSort(mode, false)
            prefs.resetForDeselect()
            assertEquals(SongSortMode.Title, repository.settings.first().songSort)
        }
    }

    // endregion
}

private fun TestScope.cancel() = coroutineContext[kotlinx.coroutines.Job]?.cancel()
