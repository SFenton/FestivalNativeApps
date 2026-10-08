package com.festivalscoretracker.android.settings

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.ResetPolicy
import com.festivalscoretracker.android.core.settings.ScoreLeeway
import com.festivalscoretracker.android.core.settings.SettingsCodec
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.RetiredSettingsMigration
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsModelTest {
    // region Model

    @Test
    fun defaultsMatchWeb() {
        val s = AppSettings()
        assertTrue(s.showInstrumentIcons)
        assertFalse(s.enableVisualOrder)
        assertEquals(
            listOf("score", "percentage", "percentile", "stars", "seasonachieved", "intensity", "difficulty", "lastplayed"),
            s.songRowVisualOrder.map { it.token },
        )
        assertEquals(listOf("note", "beat", "time", "od", "score"), s.pathColumnOrder.map { it.token })
        assertEquals(PathDisplayMode.Image, s.pathDefaultView)
        assertEquals(1.0, s.leeway, 0.0)
        assertEquals(MetadataField.entries.toSet(), s.visibleMetadata)
        assertTrue(s.shopHighlightEnabled)
        assertEquals(8, MetadataField.toggleOrder.size)
        assertEquals("last-played", MetadataField.LastPlayed.tag)
        assertEquals("season", MetadataField.Season.tag)
    }

    @Test
    fun lastVisibleInstrumentCannotBeHidden() {
        var s = AppSettings(visibleInstruments = setOf(Instrument.Bass, Instrument.Lead))
        s = s.withInstrumentVisible(Instrument.Lead, false)
        assertEquals(setOf(Instrument.Bass), s.visibleInstruments)
        assertTrue(s.isLastVisible(Instrument.Bass))
        assertFalse(s.isLastVisible(Instrument.Lead))
        assertSame(s, s.withInstrumentVisible(Instrument.Bass, false))
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), s.withInstrumentVisible(Instrument.Lead, true).orderedVisibleInstruments)
        assertEquals(Instrument.entries.toSet(), AppSettings(visibleInstruments = emptySet()).sanitized().visibleInstruments)
    }

    @Test
    fun metadataAllMayBeOffAndOrderFollowsVisualOrderToggle() {
        var s = AppSettings()
        MetadataField.entries.forEach { s = s.withMetadataVisible(it, false) }
        assertTrue(s.visibleMetadata.isEmpty())
        assertTrue(s.orderedVisibleMetadata.isEmpty())
        s = AppSettings(songRowVisualOrder = listOf(MetadataField.LastPlayed) + MetadataField.entries.dropLast(1))
            .withMetadataVisible(MetadataField.Score, false)
        assertEquals(MetadataField.Percentage, s.orderedVisibleMetadata.first())
        assertEquals(MetadataField.LastPlayed, s.copy(enableVisualOrder = true).orderedVisibleMetadata.first())
    }

    @Test
    fun shopHighlightAndSanitize() {
        assertFalse(AppSettings(hideShop = true).shopHighlightEnabled)
        assertFalse(AppSettings(disableShopHighlighting = true).shopHighlightEnabled)
        val sanitized = AppSettings(experimentalRanks = true, leeway = 9.0).sanitized()
        assertFalse(sanitized.experimentalRanks)
        assertEquals(5.0, sanitized.leeway, 0.0)
    }

    @Test
    fun resetKeepsProfileAndSongsSort() {
        val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        val changed = AppSettings(
            selectedPlayer = player, songSort = SongSortMode.Year, songSortAscending = false,
            hideShop = true, leeway = -2.0, visibleInstruments = setOf(Instrument.Bass), reduceMotion = true,
        )
        assertEquals(AppSettings(selectedPlayer = player, songSort = SongSortMode.Year, songSortAscending = false), changed.resetAppSettings())
    }

    // endregion

    // region Codecs

    @Test
    fun orderCodecRepairsCorruptLists() {
        assertEquals(PathColumnKey.entries, SettingsOrder.decode(null, PathColumnKey.entries, PathColumnKey::fromToken))
        assertEquals(
            listOf(PathColumnKey.Score, PathColumnKey.Note, PathColumnKey.Beat, PathColumnKey.Time, PathColumnKey.Od),
            SettingsOrder.decode("score,bogus,score, note", PathColumnKey.entries, PathColumnKey::fromToken),
        )
        assertEquals("note,beat", SettingsOrder.encode(listOf(PathColumnKey.Note, PathColumnKey.Beat)) { it.token })
        val order = listOf(1, 2, 3)
        assertEquals(listOf(2, 1, 3), SettingsOrder.move(order, 0, 1))
        assertEquals(listOf(1, 3, 2), SettingsOrder.move(order, 2, -1))
        assertEquals(listOf(3, 1, 2), SettingsOrder.move(order, 2, -2))
        assertSame(order, SettingsOrder.move(order, 0, -1))
        assertSame(order, SettingsOrder.move(order, 5, 1))
        assertNull(MetadataField.fromToken("nope"))
        assertEquals(PathDisplayMode.Image, PathDisplayMode.fromToken("x"))
        assertEquals(PathDisplayMode.Text, PathDisplayMode.fromToken("text"))
    }

    @Test
    fun metadataCodec() {
        assertEquals(MetadataField.entries.toSet(), SettingsCodec.decodeMetadata(null))
        assertTrue(SettingsCodec.decodeMetadata("").isEmpty())
        val some = setOf(MetadataField.Season, MetadataField.Score)
        assertEquals("score,seasonachieved", SettingsCodec.encodeMetadata(some))
        assertEquals(some, SettingsCodec.decodeMetadata("seasonachieved, score, junk"))
    }

    @Test
    fun leewayRules() {
        assertEquals(1.0, ScoreLeeway.clamp(Double.NaN), 0.0)
        assertEquals(-5.0, ScoreLeeway.clamp(-7.0), 0.0)
        assertEquals(0.3, ScoreLeeway.clamp(0.25), 0.0)
        assertEquals(-0.3, ScoreLeeway.clamp(-0.25), 0.0)
        assertEquals("+1.0%", ScoreLeeway.format(1.0))
        assertEquals("-0.5%", ScoreLeeway.format(-0.5))
        assertEquals("0.0%", ScoreLeeway.format(0.0))
        assertEquals(101_000, ScoreLeeway.maxEffectiveScore(1.0))
        assertEquals(95_000, ScoreLeeway.maxEffectiveScore(-5.0))
        assertTrue(ScoreLeeway.description(1.0).contains("max score of 100k and 1% leeway will allow the app to accept scores up to 101,000"))
        assertTrue(ScoreLeeway.description(1.5).contains("1.5% leeway") && ScoreLeeway.description(1.5).contains("101,500"))
    }

    // endregion

    // region Repository and registry

    @Test
    fun everyFieldRoundTripsAndResetRestoresAppSettingsOnly() = runBlocking {
        val store = InMemoryPreferences()
        val repo = SettingsRepository(store)
        val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        repo.setSelectedPlayer(player)
        repo.setSongSort(SongSortMode.Artist, false)
        val changed = AppSettings(
            visibleInstruments = setOf(Instrument.Drums),
            increaseContrast = true, reduceMotion = true, reduceTransparency = true, disableAnimatedArtwork = true,
            showInstrumentIcons = false, enableVisualOrder = true,
            songRowVisualOrder = MetadataField.entries.reversed(), pathColumnOrder = PathColumnKey.entries.reversed(),
            pathDefaultView = PathDisplayMode.Text, pathUnavailableWarningDismissed = true,
            filterInvalidScores = true, leeway = -1.2, hideShop = true, disableShopHighlighting = true,
            visibleMetadata = setOf(MetadataField.Stars),
        )
        repo.update { changed }
        repo.writeBlob(SettingsRegistry.FIRST_RUN_SEEN, "{}")
        val stored = repo.settings.first()
        assertEquals(changed.copy(selectedPlayer = player, songSort = SongSortMode.Artist, songSortAscending = false), stored)

        // Every key written is registered.
        store.current.asMap().keys.forEach { assertTrue(it.name, SettingsRegistry.isRegistered(it.name)) }

        repo.resetAppSettings()
        assertEquals(AppSettings(selectedPlayer = player, songSort = SongSortMode.Artist, songSortAscending = false), repo.settings.first())
        assertEquals("{}", repo.readBlob(SettingsRegistry.FIRST_RUN_SEEN))
        repo.writeBlob(SettingsRegistry.FIRST_RUN_SEEN, null)
        assertNull(repo.readBlob(SettingsRegistry.FIRST_RUN_SEEN))
    }

    @Test
    fun blobAccessRequiresRegistration(): Unit = runBlocking {
        val repo = SettingsRepository(InMemoryPreferences())
        try {
            repo.readBlob("fst.unregistered")
            throw AssertionError("expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {
        }
        assertThrows(IllegalArgumentException::class.java) { runBlocking { repo.writeBlob("fst.unregistered", "x") } }
        Unit
    }

    @Test
    fun corruptStoredValuesDecodeSafely() {
        val prefs = mutablePreferencesOf(
            stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "",
            stringPreferencesKey(SettingsRegistry.SONG_ROW_VISUAL_ORDER) to "junk,stars",
            doublePreferencesKey(SettingsRegistry.LEEWAY) to 42.0,
            stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW) to "video",
        )
        val decoded = SettingsRepository.decode(prefs)
        assertEquals(Instrument.entries.toSet(), decoded.visibleInstruments)
        assertEquals(MetadataField.Stars, decoded.songRowVisualOrder.first())
        assertEquals(8, decoded.songRowVisualOrder.size)
        assertEquals(5.0, decoded.leeway, 0.0)
        assertEquals(PathDisplayMode.Image, decoded.pathDefaultView)
    }

    @Test
    fun registryIsUniqueAndPoliciesAreSane() {
        val keys = SettingsRegistry.entries.map { it.key }
        assertEquals(keys.size, keys.toSet().size)
        assertFalse(SettingsRegistry.ACCOUNT_ID in SettingsRegistry.appSettingKeys)
        assertFalse(SettingsRegistry.FIRST_RUN_SEEN in SettingsRegistry.appSettingKeys)
        assertTrue(SettingsRegistry.LEEWAY in SettingsRegistry.appSettingKeys)
        assertEquals(ResetPolicy.Kept, SettingsRegistry.entries.first { it.key == SettingsRegistry.SONG_SORT }.policy)
        // Retired keys are never registered again (#374).
        SettingsRegistry.retiredKeys.forEach { assertFalse(it, SettingsRegistry.isRegistered(it)) }
    }

    @Test
    fun retiredTapDiagnosticsKeysAreDeletedAndOthersKept() = runBlocking {
        val prefs = mutablePreferencesOf(
            booleanPreferencesKey("fst.settings.tapDiagnostics") to true,
            booleanPreferencesKey("fst.settings.tapTelemetry") to true,
            booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true,
        )
        assertTrue(RetiredSettingsMigration.shouldMigrate(prefs))
        val migrated = RetiredSettingsMigration.migrate(prefs)
        assertEquals(setOf(SettingsRegistry.HIDE_SHOP), migrated.asMap().keys.map { it.name }.toSet())
        assertFalse(RetiredSettingsMigration.shouldMigrate(migrated))
        assertFalse(RetiredSettingsMigration.shouldMigrate(mutablePreferencesOf()))
        RetiredSettingsMigration.cleanUp()
    }

    // endregion
}
