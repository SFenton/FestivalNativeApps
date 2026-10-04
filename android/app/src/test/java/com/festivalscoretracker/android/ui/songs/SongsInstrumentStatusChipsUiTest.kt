package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongRowProjector
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Every reachable `fst.songs.instrument-status.*` state (#134) on synthetic fixtures: chips
 * only for an explicitly selected player's matching 200 scores with icons on and no
 * single-chart filter, each status in service order, and the row's one spoken summary.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsInstrumentStatusChipsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val pin = mapOf("X-FST-Publication-Id" to "7")

    /**
     * Alpha (every chart charted): Lead FC, Bass scored, Drums a zero-score "FC", Pro Lead a
     * zero score, the rest unplayed. Beta (`Keyboard`, Lead/Bass only): Lead scored.
     */
    private val mixedScores = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":5,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000},
          {"si":"s-alpha","ins":"02","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000},
          {"si":"s-alpha","ins":"04","sc":0,"fc":true,"te":1000},
          {"si":"s-alpha","ins":"10","sc":0,"fc":false,"te":1000},
          {"si":"s-beta","ins":"01","sc":1234,"acc":400,"fc":false,"st":1,"sn":9,"dif":0,"rk":950,"te":1000}
        ]}
    """.trimIndent()

    private val alphaStatuses = listOf(
        "Solo_Guitar.FullCombo", "Solo_Bass.Scored", "Solo_Drums.InconsistentFullCombo", "Solo_Vocals.NoScore",
        "Solo_PeripheralGuitar.NoScore", "Solo_PeripheralBass.NoScore", "Solo_PeripheralVocals.NoScore",
        "Solo_PeripheralCymbals.NoScore", "Solo_PeripheralDrums.NoScore",
    )

    private val betaStatuses = listOf(
        "Solo_Guitar.Scored", "Solo_Bass.NoScore", "Solo_Drums.Unavailable", "Solo_Vocals.Unavailable",
        "Solo_PeripheralGuitar.Unavailable", "Solo_PeripheralBass.Unavailable", "Solo_PeripheralVocals.Unavailable",
        "Solo_PeripheralCymbals.Unavailable", "Solo_PeripheralDrums.Unavailable",
    )

    private fun transport(profile: String = mixedScores, profileStatus: Int = 200) = FakeTransport.standard().apply {
        on("/api/songs", headers = pin) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = pin) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        onRaw("/api/player/${Fixtures.ACCOUNT_A}") { HttpResult(profileStatus, profile.toByteArray(), pin) }
    }

    private fun launch(prefs: Preferences = mutablePreferencesOf(), transport: FakeTransport = transport(), profile: SelectedPlayer? = player, song: String? = null) {
        val debug = DebugLaunch(profile = profile, songQuery = song, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences(prefs.toMutablePreferences()))
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(100); exists(tag) }

    private fun chips(songId: String): List<String> =
        rule.onNodeWithTag("fst.songs.instrument-status.$songId", useUnmergedTree = true).fetchSemanticsNode().config[SongChipStatuses]

    private fun description(songId: String): String =
        rule.onNodeWithTag("fst.songs.row.$songId").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    private fun noChips() = listOf("s-alpha", "s-beta", "s-gamma").forEach { assertFalse(it, exists("fst.songs.instrument-status.$it")) }

    // region Score source states

    @Test
    fun anonymousRowsShowNoChipsOrScoreState() {
        launch(profile = null)
        waitForTag("fst.songs.row.s-gamma")
        noChips()
        assertFalse(exists("fst.songs.score-state.s-alpha"))
    }

    @Test
    fun loadingRowsSayLoadingScoresInsteadOfChips() {
        val song = Fixtures.song("s-load", "Loading Song")
        val row = SongRowProjector(AppSettings(), SongFilter(), 15, null, SongScoreSource.LOADING).project(song)
        rule.setContent { MaterialTheme { SongRow(row, artUrl = null) {} } }
        settle()
        assertTrue(row.chips.isEmpty())
        assertFalse(exists("fst.songs.instrument-status.s-load"))
        assertTrue(exists("fst.songs.score-state.s-load"))
        assertTrue(description("s-load"), description("s-load").endsWith("Loading scores"))
    }

    @Test
    fun syncingPlayerShowsScoresSyncingNotChips() {
        launch(transport = transport(profile = ProfileFixtures.syncing(Fixtures.ACCOUNT_A), profileStatus = 202))
        waitForTag("fst.songs.score-state.s-alpha")
        noChips()
        assertTrue(description("s-alpha"), description("s-alpha").contains("Scores syncing"))
    }

    @Test
    fun failedScoreReadShowsScoresUnavailableNotChips() {
        launch(transport = transport(profile = "{}", profileStatus = 500))
        waitForTag("fst.songs.score-state.s-alpha")
        noChips()
        assertTrue(description("s-alpha").contains("Scores unavailable"))
    }

    @Test
    fun availableEmptyIndexIsNoScoreOnChartedPartsNotAMissingState() {
        launch(transport = transport(profile = """{"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":0,"scores":[]}"""))
        waitForTag("fst.songs.instrument-status.s-gamma")
        assertTrue(chips("s-alpha").all { it.endsWith(".NoScore") })
        val gamma = chips("s-gamma")
        assertEquals(listOf("Solo_Drums.NoScore"), gamma.filterNot { it.endsWith(".Unavailable") })
        assertEquals(8, gamma.count { it.endsWith(".Unavailable") })
        assertFalse(exists("fst.songs.score-state.s-alpha"))
    }

    // endregion

    // region Status derivation and announcement

    @Test
    fun eachStatusFollowsTheChartAndScoreInServiceOrder() {
        launch()
        waitForTag("fst.songs.instrument-status.s-beta")
        // full-combo, scored, inconsistent-zero-fc, no-score (unplayed and zero score).
        assertEquals(alphaStatuses, chips("s-alpha"))
        // not-charted and keyboard-variant: Beta is a Keyboard song with only Lead and Bass charts.
        assertEquals(betaStatuses, chips("s-beta"))
        assertEquals(Instrument.entries.map { it.wireId }, chips("s-alpha").map { it.substringBefore('.') })
    }

    @Test
    fun screenReaderHearsOneRowSummaryWithEveryChartStatusInOrder() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        val spoken = description("s-alpha")
        val expected = listOf(
            "Lead, full combo", "Bass, scored", "Drums, score missing despite a reported full combo", "Tap Vocals, no score",
            "Pro Lead, no score", "Pro Bass, no score", "Karaoke, no score", "Pro Drums + Cymbals, no score", "Pro Drums, no score",
        )
        var from = 0
        expected.forEach { phrase ->
            val at = spoken.indexOf(phrase, from)
            assertTrue("$phrase in $spoken", at >= 0)
            from = at + phrase.length
        }
        assertTrue(description("s-beta").contains("Tap Vocals, not charted"))
        // The chips themselves are not separate TalkBack stops: the merged row is the only node.
        val merged = rule.onAllNodesWithTag("fst.songs.instrument-status.s-alpha").fetchSemanticsNodes()
        assertTrue(merged.isEmpty())
    }

    // endregion

    // region Settings and filters

    @Test
    fun hiddenInstrumentsDropTheirChips() {
        launch(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Drums"))
        waitForTag("fst.songs.instrument-status.s-alpha")
        assertEquals(listOf("Solo_Guitar.FullCombo", "Solo_Drums.InconsistentFullCombo"), chips("s-alpha"))
        assertFalse(description("s-alpha").contains("Bass"))
    }

    @Test
    fun singleChartFilterSwapsChipsForThatChartsMetadata() {
        launch(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar"}"""))
        waitForTag("fst.songs.metadata.score.s-alpha")
        noChips()
    }

    @Test
    fun iconsOffShowsMetadataNotChips() {
        launch(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.SHOW_INSTRUMENT_ICONS) to false))
        waitForTag("fst.songs.metadata.score.s-alpha")
        noChips()
    }

    @Test
    fun filterInvalidScoresKeepsChipsOnEffectiveScoresWithTheWarning() {
        // Lead is invalid at the default +1% leeway (minimum 2%); its fallback is a non-FC score.
        // Bass is invalid with no fallback, so it has no valid score at all.
        val profile = """
            {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":2,"scores":[
              {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,
               "ml":2.0,"vs":[{"sc":80000,"acc":950,"fc":false,"st":5,"ml":0.5,"rt":[{"l":0,"r":60}]}]},
              {"si":"s-alpha","ins":"02","sc":5000,"acc":500,"fc":true,"st":2,"sn":9,"dif":1,"rk":900,"te":1000,"ml":50.0,"vs":[]}
            ]}
        """.trimIndent()
        launch(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true), transport(profile))
        waitForTag("fst.songs.invalid-score.s-alpha")
        val statuses = chips("s-alpha")
        assertEquals("Solo_Guitar.Scored", statuses[0])
        assertEquals("Solo_Bass.NoScore", statuses[1])
        assertTrue(description("s-alpha").contains("Filtered score"))
    }

    @Test
    fun filterInvalidScoresOffShowsTheRawFullCombo() {
        val profile = """
            {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":1,"scores":[
              {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,
               "ml":2.0,"vs":[{"sc":80000,"acc":950,"fc":false,"st":5,"ml":0.5,"rt":[{"l":0,"r":60}]}]}
            ]}
        """.trimIndent()
        launch(transport = transport(profile))
        waitForTag("fst.songs.instrument-status.s-alpha")
        assertEquals("Solo_Guitar.FullCombo", chips("s-alpha")[0])
        assertFalse(exists("fst.songs.invalid-score.s-alpha"))
    }

    @Test
    fun increaseContrastKeepsEveryChip() {
        launch(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.INCREASE_CONTRAST) to true))
        waitForTag("fst.songs.instrument-status.s-beta")
        assertEquals(alphaStatuses, chips("s-alpha"))
        assertEquals(betaStatuses, chips("s-beta"))
    }

    // endregion

    // region Layout

    @Test
    fun phoneWidthFitsNineChipsInOneRow() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).assertHeightIsEqualTo(34.dp)
    }

    @Test
    @Config(qualifiers = "w320dp-h640dp-xhdpi")
    fun compactWidthWrapsNineChipsIntoBalancedRows() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        // 5 + 4: two 34 dp rows and one 4 dp gap.
        rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).assertHeightIsEqualTo(72.dp)
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largestTextKeepsChipSizeAndEveryStatus() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        assertEquals(alphaStatuses, chips("s-alpha"))
        val node = rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).fetchSemanticsNode()
        val row = rule.onNodeWithTag("fst.songs.row.s-alpha").fetchSemanticsNode()
        assertTrue("chips inside the card", node.boundsInRoot.left >= row.boundsInRoot.left && node.boundsInRoot.right <= row.boundsInRoot.right)
        assertEquals(1, rule.onAllNodesWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).fetchSemanticsNodes().size)
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
    fun twoPaneSelectedRowBalancesChipsInTheListColumn() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        rule.onNodeWithTag("fst.songs.row.s-alpha").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            settle(100)
            rule.onNodeWithTag("fst.songs.row.s-alpha").fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.Selected) { null } == true
        }
        // The selected (purple) row keeps every chip; its rings lighten to clear 3:1 (SongChipContrastTest).
        // The two-pane list column is narrower than nine chips, so they balance 5 + 4.
        rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).assertHeightIsEqualTo(72.dp)
        assertEquals(alphaStatuses, chips("s-alpha"))
    }

    @Test
    @Config(qualifiers = "w700dp-h900dp-xhdpi")
    fun wideSinglePaneCardKeepsNineChipsInOneRow() {
        launch()
        waitForTag("fst.songs.instrument-status.s-alpha")
        val node = rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).fetchSemanticsNode()
        val density = rule.activity.resources.displayMetrics.density
        assertEquals("width ${node.size.width / density}", 34f, node.size.height / density, 0.5f)
    }

    // endregion
}
