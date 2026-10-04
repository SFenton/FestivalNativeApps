package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongGeneralFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.songs.SongsPreferences
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
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
 * Songs Filter control (`fst.songs.filter`) reachable states from
 * `.agents/controls/songs-filter/spec.md` (issue #126), against synthetic fixtures.
 * Fixtures: s-alpha has a Lead FC, s-beta a Bass score, s-gamma no score; the Shop
 * lists s-alpha and s-beta, so s-gamma is the only "Not Available in Item Shop" song.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsFilterStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":2,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z"},
          {"si":"s-beta","ins":"02","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000}
        ]}
    """.trimIndent()

    private val shopOnly = SongGeneralFilter(shopUnavailable = false)

    // region Harness

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { profileJson }
    }

    private fun seeded(
        general: SongGeneralFilter = SongGeneralFilter(),
        player: SongPlayerScoreFilter = SongPlayerScoreFilter(),
        prefs: InMemoryPreferences = InMemoryPreferences(),
    ): InMemoryPreferences = prefs.also {
        runBlocking { SongsPreferences(SettingsRepository(it)).setFilters(SongFilter(), general, player) }
    }

    private fun launch(debug: DebugLaunch, prefs: InMemoryPreferences = InMemoryPreferences(), transport: FakeTransport = transport()) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun exists(tag: String, unmerged: Boolean = false) =
        rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String, unmerged: Boolean = false) = rule.waitUntil(10_000) { settle(100); exists(tag, unmerged) }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); !exists(tag) }

    private fun waitForText(text: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithText(text, substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun scrollTo(tag: String) = rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag(tag))

    private fun openFilter() {
        click("fst.songs.filter.open")
        waitForTag("fst.songs.filter.form")
    }

    private fun saved() = runBlocking { SongsPreferences(SettingsRepository(currentPrefs!!)).state.first() }

    private var currentPrefs: InMemoryPreferences? = null

    // endregion

    // region Player score and FC toggles

    /** `player-loaded`, `score`, `full-combo`: per-chart Score/FC toggles filter rows live. */
    @Test
    fun chartScoreAndFullComboTogglesFilterRows() {
        launch(DebugLaunch(profile = player, stillBackground = true))
        waitForTag("fst.songs.row.s-gamma")
        openFilter()
        waitForTag("fst.songs.filter.score-sections")
        scrollTo("fst.songs.filter.score.chart.Solo_Guitar")
        click("fst.songs.filter.score.chart.Solo_Guitar")
        settle()
        scrollTo("fst.songs.filter.score.instrument.Solo_Guitar.HasFCs")
        click("fst.songs.filter.score.instrument.Solo_Guitar.HasFCs")
        waitGone("fst.songs.row.s-beta")
        waitGone("fst.songs.row.s-gamma")
        assertTrue(exists("fst.songs.row.s-alpha"))
        rule.onNodeWithTag("fst.songs.filter.score.instrument.Solo_Guitar.HasFCs").assertIsOn()
        // Swap to Missing Lead FCs: the FC song leaves, the others return.
        click("fst.songs.filter.score.instrument.Solo_Guitar.HasFCs")
        click("fst.songs.filter.score.instrument.Solo_Guitar.MissingFCs")
        waitGone("fst.songs.row.s-alpha")
        waitForTag("fst.songs.row.s-beta")
        // Missing Lead Scores composes with it (AND): s-beta has no Lead score either.
        click("fst.songs.filter.score.instrument.Solo_Guitar.MissingScores")
        settle()
        assertTrue(exists("fst.songs.row.s-beta"))
        click("fst.songs.filter.done")
        waitGone("fst.songs.filter.form")
        assertFalse(exists("fst.songs.row.s-alpha"))
    }

    /** Global toggles turn the same check on for every visible chart. */
    @Test
    fun globalToggleTurnsOnEveryVisibleChart() {
        currentPrefs = InMemoryPreferences()
        launch(DebugLaunch(profile = player, stillBackground = true), currentPrefs!!)
        waitForTag("fst.songs.row.s-gamma")
        openFilter()
        scrollTo("fst.songs.filter.global")
        click("fst.songs.filter.global")
        settle()
        click("fst.songs.filter.score.global.HasScores")
        // Has scores on any visible instrument: s-gamma (no scores) leaves.
        waitGone("fst.songs.row.s-gamma")
        rule.onNodeWithTag("fst.songs.filter.score.global.HasScores").assertIsOn()
        val filter = saved().playerFilter!!
        assertTrue(filter.isActive)
        assertTrue(Instrument.Lead in filter.hasScores && Instrument.Bass in filter.hasScores)
    }

    // endregion

    // region Selected Instrument Filters

    /** `instrument`, `season`, `percentile`, `stars`, `intensity`: the selector reveals the bucket groups. */
    @Test
    fun instrumentSelectionRevealsBucketGroups() {
        launch(DebugLaunch(profile = player, stillBackground = true))
        waitForTag("fst.songs.row.s-gamma")
        openFilter()
        scrollTo("fst.songs.filter.instrument")
        assertFalse(exists("fst.songs.filter.stars"))
        // Phone width shows the compact cycler; wider sheets show every chart.
        if (exists("fst.songs.filter.instrument.preview", unmerged = true)) {
            rule.onNodeWithTag("fst.songs.filter.instrument.preview", useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        } else {
            rule.onNodeWithTag("fst.songs.filter.instrument.Solo_Guitar", useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        }
        waitForTag("fst.songs.filter.stars")
        listOf("season", "percentile", "stars", "intensity").forEach { group ->
            scrollTo("fst.songs.filter.$group")
            rule.onNodeWithTag("fst.songs.filter.$group").assertExists()
        }
        // Season keys come from the player's scores (9 and 15).
        scrollTo("fst.songs.filter.season")
        click("fst.songs.filter.season")
        settle()
        scrollTo("fst.songs.filter.season.15")
        rule.onNodeWithTag("fst.songs.filter.season.15").assertIsOn()
        // Stars: one bucket off, Clear All, then Select All.
        scrollTo("fst.songs.filter.stars")
        click("fst.songs.filter.stars")
        settle()
        scrollTo("fst.songs.filter.stars.6")
        click("fst.songs.filter.stars.6")
        settle()
        rule.onNodeWithTag("fst.songs.filter.stars.6").assertIsOff()
        rule.onNodeWithTag("fst.songs.filter.stars.5").assertIsOn()
        scrollTo("fst.songs.filter.stars.clear-all")
        click("fst.songs.filter.stars.clear-all")
        settle()
        rule.onNodeWithTag("fst.songs.filter.stars.5").assertIsOff()
        click("fst.songs.filter.stars.select-all")
        settle()
        rule.onNodeWithTag("fst.songs.filter.stars.6").assertIsOn()
        // Percentile and Song Intensity groups expand with their own bulk actions.
        scrollTo("fst.songs.filter.percentile")
        click("fst.songs.filter.percentile")
        settle()
        scrollTo("fst.songs.filter.percentile.clear-all")
        click("fst.songs.filter.percentile.clear-all")
        settle()
        rule.onNodeWithTag("fst.songs.filter.percentile.0").assertIsOff()
        scrollTo("fst.songs.filter.intensity")
        click("fst.songs.filter.intensity")
        settle()
        scrollTo("fst.songs.filter.intensity.clear-all")
        click("fst.songs.filter.intensity.clear-all")
        settle()
        rule.onNodeWithTag("fst.songs.filter.intensity.1").assertIsOff()
        // Reset restores every bucket and collapses back to no instrument.
        click("fst.songs.filter.reset")
        waitGone("fst.songs.filter.stars")
    }

    // endregion

    // region Item Shop availability

    /** `shop-draft`, `applied`: Available-only hides songs not in the Shop and is saved. */
    @Test
    fun shopAvailabilityAppliesLiveAndIsSaved() {
        currentPrefs = InMemoryPreferences()
        launch(DebugLaunch(profile = player, stillBackground = true), currentPrefs!!)
        waitForTag("fst.songs.row.s-gamma")
        openFilter()
        scrollTo("fst.songs.filter.shop")
        click("fst.songs.filter.shop")
        settle()
        rule.onNodeWithTag("fst.songs.filter.shop-available").assertIsOn()
        rule.onNodeWithTag("fst.songs.filter.shop-unavailable").assertIsOn()
        click("fst.songs.filter.shop-unavailable")
        waitGone("fst.songs.row.s-gamma")
        assertTrue(exists("fst.songs.row.s-alpha"))
        assertEquals(shopOnly, saved().general)
        click("fst.songs.filter.done")
        waitGone("fst.songs.filter.form")
        // Reopening seeds the sheet from the saved choice (group expanded, toggle off).
        openFilter()
        scrollTo("fst.songs.filter.shop-unavailable")
        rule.onNodeWithTag("fst.songs.filter.shop-unavailable").assertIsOff()
    }

    /** `relaunch-persisted`: a saved Available-only filter applies on launch and seeds the sheet. */
    @Test
    fun savedShopFilterAppliesOnRelaunch() {
        launch(DebugLaunch(profile = player, stillBackground = true), seeded(shopOnly))
        waitForTag("fst.songs.row.s-alpha")
        assertFalse(exists("fst.songs.row.s-gamma"))
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.notice.0").fetchSemanticsNodes().size)
        openFilter()
        scrollTo("fst.songs.filter.shop-unavailable")
        rule.onNodeWithTag("fst.songs.filter.shop-available").assertIsOn()
        rule.onNodeWithTag("fst.songs.filter.shop-unavailable").assertIsOff()
        click("fst.songs.filter.reset")
        waitForTag("fst.songs.row.s-gamma")
    }

    /** `leaving-draft`: retired In Shop / Leaving Tomorrow keys migrate to Available only. */
    @Test
    fun retiredLeavingTomorrowKeyMigratesToAvailable() {
        val prefs = InMemoryPreferences(
            mutablePreferencesOf(androidx.datastore.preferences.core.stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"leavingTomorrow":true}"""),
        )
        launch(DebugLaunch(profile = player, stillBackground = true), prefs)
        waitForTag("fst.songs.row.s-alpha")
        assertFalse(exists("fst.songs.row.s-gamma"))
        openFilter()
        scrollTo("fst.songs.filter.shop-unavailable")
        rule.onNodeWithTag("fst.songs.filter.shop-available").assertIsOn()
        rule.onNodeWithTag("fst.songs.filter.shop-unavailable").assertIsOff()
    }

    /** `shop-hidden-paused`, `shop-sort-badges-suppressed`: hidden Shop pauses the saved choice. */
    @Test
    fun hiddenShopPausesSavedShopFilter() {
        val prefs = seeded(shopOnly, prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true)))
        launch(DebugLaunch(profile = player, stillBackground = true), prefs)
        waitForTag("fst.songs.row.s-gamma")
        waitForText("Item Shop filters paused while the Item Shop is hidden")
        assertFalse(exists("fst.songs.shop-badge.s-alpha", unmerged = true))
        openFilter()
        // The Item Shop group is withdrawn; the saved choice stays until Reset.
        assertFalse(exists("fst.songs.filter.shop"))
        rule.onNodeWithTag("fst.songs.filter.general").assertExists()
    }

    /** `shop-unavailable-paused`: a failed Shop read pauses the filter instead of hiding rows. */
    @Test
    fun failedShopReadPausesShopFilter() {
        val failing = transport().apply { on("/api/shop", status = 500) { "{}" } }
        launch(DebugLaunch(profile = player, stillBackground = true), seeded(shopOnly), failing)
        waitForTag("fst.songs.row.s-gamma")
        waitForText("Item Shop filters paused until Item Shop data loads")
        assertTrue(exists("fst.songs.row.s-alpha"))
    }

    /** `shop-validated-empty`: a matching, empty Shop feed is a real result, not a pause. */
    @Test
    fun emptyMatchingShopFeedShowsEmptyResult() {
        val empty = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"count":0,"songs":[]}""" }
        }
        launch(DebugLaunch(profile = player, stillBackground = true), seeded(shopOnly), empty)
        waitForTag("fst.songs.empty")
        assertFalse(exists("fst.songs.notice.0"))
        assertFalse(exists("fst.songs.row.s-alpha"))
    }

    /** `publication-mismatch-paused`: Shop data from another publication never filters or badges rows. */
    @Test
    fun shopFromAnotherPublicationPausesFilterAndBadges() {
        val newer = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "8")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        }
        launch(DebugLaunch(profile = player, stillBackground = true), seeded(shopOnly), newer)
        waitForTag("fst.songs.row.s-gamma")
        // The repository withholds a feed from another publication (the exact "update together"
        // copy is SongsViewModelTest.shopSortAndHighlightsNeedSamePublication); rows stay unfiltered.
        waitForText("Item Shop filters paused until")
        assertFalse(exists("fst.songs.shop-badge.s-alpha", unmerged = true))
    }

    // endregion

    // region Player availability and deselection

    /** `player-unavailable`: score checks pause (rows stay) when the player's scores fail to load. */
    @Test
    fun unavailableScoresPauseScoreFilters() {
        val failing = transport().apply { on("/api/player/${Fixtures.ACCOUNT_A}", status = 500) { "{}" } }
        val prefs = seeded(player = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead)))
        launch(DebugLaunch(profile = player, stillBackground = true), prefs, failing)
        waitForTag("fst.songs.row.s-gamma")
        waitForText("Player score filters paused")
        assertTrue(exists("fst.songs.row.s-beta"))
    }

    /** `deselected-paused`: deselecting clears score checks and keeps public General choices. */
    @Test
    fun deselectionClearsScoreChecksAndKeepsGeneral() {
        currentPrefs = seeded(shopOnly, SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead)))
        launch(DebugLaunch(profile = player, opensProfileSheet = true, stillBackground = true), currentPrefs!!)
        waitForTag("fst.profile.deselect")
        click("fst.profile.deselect")
        waitForTag("fst.profile.deselect-confirm.ok")
        click("fst.profile.deselect-confirm.ok")
        rule.waitUntil(10_000) { settle(100); saved().playerFilter?.isActive == false }
        assertEquals(shopOnly, saved().general)
        waitForTag("fst.songs.row.s-beta")
        assertFalse(exists("fst.songs.row.s-gamma"))
        openFilter()
        assertFalse(exists("fst.songs.filter.score-sections"))
        rule.onNodeWithTag("fst.songs.filter.shop").assertExists()
    }

    // endregion
}

/** Compact-height (landscape phone) Filter layout: Reset moves into the header (issue #126). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-xxhdpi")
class SongsFilterCompactHeightUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun resetSitsInTheHeaderBesideClose() {
        val debug = DebugLaunch(stillBackground = true)
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.onAllNodesWithTag("fst.songs.filter.open").fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithTag("fst.songs.filter.open").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.onAllNodesWithTag("fst.songs.filter.reset").fetchSemanticsNodes().isNotEmpty()
        }
        val reset = rule.onNodeWithTag("fst.songs.filter.reset").fetchSemanticsNode().boundsInRoot
        val close = rule.onNodeWithTag("fst.songs.filter.done").fetchSemanticsNode().boundsInRoot
        val form = rule.onNodeWithTag("fst.songs.filter.form").fetchSemanticsNode().boundsInRoot
        // Same header row as Close, above the scrolling form.
        assertTrue("reset $reset vs form $form", reset.bottom <= form.top + 1f)
        assertTrue("reset $reset vs close $close", reset.top < close.bottom && close.top < reset.bottom)
    }
}
