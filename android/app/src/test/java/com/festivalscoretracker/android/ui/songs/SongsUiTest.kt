package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
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
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Songs, Song Detail, Paths and Item Shop against synthetic fixtures on Robolectric. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":2,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z"},
          {"si":"s-beta","ins":"02","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000}
        ]}
    """.trimIndent()

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { profileJson }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, SongsFixtures.png(), mapOf("X-FST-Publication-Id" to "7")) }
        on("/api/player/${Fixtures.ACCOUNT_A}/history") { ProfileFixtures.history() }
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

    private fun waitForTag(tag: String, unmerged: Boolean = false) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    @Test
    fun selectedPlayerRowsShowChipsShopAccentsAndFilter() {
        launch(DebugLaunch(profile = player, stillBackground = true))
        waitForTag("fst.songs.row.s-alpha")
        waitForTag("fst.songs.instrument-status.s-alpha", unmerged = true)
        waitForTag("fst.songs.shop-badge.s-alpha", unmerged = true)
        val chips = rule.onNodeWithTag("fst.songs.instrument-status.s-alpha", useUnmergedTree = true).fetchSemanticsNode().config[SongChipStatuses]
        assertTrue(chips.toString(), "Solo_Guitar.FullCombo" in chips)

        click("fst.songs.filter.open")
        settle()
        // Web structure: collapsed Global / per-instrument groups (6.32).
        click("fst.songs.filter.global")
        settle()
        click("fst.songs.filter.score.global.MissingFCs")
        click("fst.songs.filter.score.global.MissingFCs")
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.score.chart.Solo_Guitar"))
        click("fst.songs.filter.score.chart.Solo_Guitar")
        settle()
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.score.instrument.Solo_Guitar.HasScores"))
        click("fst.songs.filter.score.instrument.Solo_Guitar.HasScores")
        click("fst.songs.filter.done")
        rule.waitUntil(5_000) { settle(100); rule.onAllNodesWithTag("fst.songs.row.s-beta").fetchSemanticsNodes().isEmpty() }
        waitForTag("fst.songs.row.s-alpha")

        click("fst.songs.sort.open")
        settle()
        click("fst.songs.sort.shop")
        click("fst.songs.sort.done")
        waitForTag("fst.songs.row.s-alpha")

        click("fst.songs.filter.open")
        settle()
        // Changes apply live: Reset restores every row immediately, Done just closes.
        click("fst.songs.filter.reset")
        waitForTag("fst.songs.row.s-beta")
        click("fst.songs.filter.done")
        settle()
    }

    @Test
    fun anonymousFilterOffersOnlyGeneralFilters() {
        val transport = transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
                Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null")
                    .replace("\"sig\":\"Guitar\"", "\"sig\":\"Guitar\",\"doubleBassSupported\":true")
                    .replace("\"sig\":\"Keyboard\"", "\"sig\":\"Keyboard\",\"doubleBassSupported\":false")
            }
        }
        launch(DebugLaunch(stillBackground = true), transport = transport)
        waitForTag("fst.songs.row.s-gamma")
        click("fst.songs.filter.open")
        waitForTag("fst.songs.filter.general")
        // No profile: only General (web 6415d3e3); score and Selected Instrument filters are hidden.
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.score-sections").fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.instrument", useUnmergedTree = true).fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.songs.filter.shop").assertExists()
        // Double Bass Support only: the unsupported song and the unknown one (null) drop.
        click("fst.songs.filter.double-bass")
        settle()
        click("fst.songs.filter.double-bass.unsupported")
        rule.waitUntil(5_000) {
            settle(100)
            rule.onAllNodesWithTag("fst.songs.row.s-beta").fetchSemanticsNodes().isEmpty() &&
                rule.onAllNodesWithTag("fst.songs.row.s-gamma").fetchSemanticsNodes().isEmpty()
        }
        waitForTag("fst.songs.row.s-alpha")
        // Year: catalogue decades with web labels; hiding the 2020s leaves nothing.
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.year"))
        click("fst.songs.filter.year")
        settle()
        rule.onNodeWithText("2010s").assertExists()
        click("fst.songs.filter.year.2020")
        waitForTag("fst.songs.empty")
        click("fst.songs.filter.year.select-all")
        waitForTag("fst.songs.row.s-alpha")
        // Duration buckets: 0-9 minutes (no song reaches 10).
        click("fst.songs.filter.duration")
        settle()
        rule.onNodeWithText("Under 1 Minute").assertExists()
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.duration.10").fetchSemanticsNodes().size)
        click("fst.songs.filter.duration.clear-all")
        waitForTag("fst.songs.empty")
        click("fst.songs.filter.reset")
        waitForTag("fst.songs.row.s-beta")
        click("fst.songs.filter.done")
        settle()
    }

    @Test
    fun metadataPillsWhenIconsAreOff() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.SHOW_INSTRUMENT_ICONS) to false))
        launch(DebugLaunch(profile = player, stillBackground = true), prefs)
        waitForTag("fst.songs.metadata.score.s-alpha", unmerged = true)
        waitForTag("fst.songs.metadata.s-alpha", unmerged = true)
        rule.onNodeWithTag("fst.songs.score-state.s-gamma", useUnmergedTree = true).assertExists()
    }

    @Test
    fun corruptSavedFilterBlocksUntilReset() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS) to "{broken"))
        launch(DebugLaunch(profile = player, stillBackground = true), prefs)
        waitForTag("fst.songs.filter-invalid")
        click("fst.songs.filter-reset-invalid")
        waitForTag("fst.songs.row.s-alpha")
    }

    @Test
    fun songDetailShowsSpotlightShopPathsAndHistory() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_PeripheralVocals"))
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), prefs)
        waitForTag("fst.song-detail.list")
        waitForTag("fst.song-detail.shop", unmerged = true)
        // Score history on the song page (6.39): chart plus the best scores, best first.
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.history"))
        waitForTag("fst.song-detail.history.chart")
        rule.onNodeWithTag("fst.song-detail.history.top.0").assertExists()
        rule.onNodeWithTag("fst.song-detail.history.top.1").assertExists()
        assertEquals(0, rule.onAllNodesWithTag("fst.song-detail.history.view-all").fetchSemanticsNodes().size)
        // No "Your score" line (6.38): the selected player's row follows the top ten instead.
        assertEquals(0, rule.onAllNodesWithText("Your score", substring = true, useUnmergedTree = true).fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        rule.onNodeWithTag("fst.song-detail.your-rank.Solo_Guitar").assertExists()

        click("fst.song-detail.paths.open")
        waitForTag("fst.paths.karaoke-warning")
        click("fst.paths.warning.never")
        waitForTag("fst.paths.image")
        click("fst.paths.zoom-in")
        click("fst.paths.display.open")
        waitForTag("fst.paths.display.text")
        click("fst.paths.display.text")
        waitForTag("fst.paths.table")
        waitForTag("fst.paths.row.1")
        // Web table: fret pills and the Overdrive bar, no path summary or max score (6.27).
        assertEquals(0, rule.onAllNodesWithText("Max score", substring = true, useUnmergedTree = true).fetchSemanticsNodes().size)
        assertTrue(rule.onNodeWithTag("fst.paths.row.1").fetchSemanticsNode().config.toString().contains("Activation 1"))
        assertTrue(rule.onNodeWithTag("fst.paths.status", useUnmergedTree = true).fetchSemanticsNode().config.toString().contains("Expert path loaded"))
        click("fst.paths.difficulty.open")
        waitForTag("fst.paths.difficulty.hard")
        click("fst.paths.difficulty.hard")
        waitForTag("fst.paths.not-generated")
        // TalkBack: the polite live region announced loading, then what loaded (issue #70).
        rule.onNodeWithTag("fst.paths.status", useUnmergedTree = true)
            .assertContentDescriptionEquals("No Hard path has been generated for ${Instrument.Lead.label} yet.")
        click("fst.paths.instrument.open")
        waitForTag("fst.paths.instrument.Solo_Guitar")
        click("fst.paths.instrument.Solo_Guitar")
        click("fst.paths.close")
        settle()

    }

    @Test
    fun songDetailToolbarHidesBehindTheBottomBarEdge() {
        // Issue #102: hidden on scroll, the floating toolbar slid under the 96%-opaque bottom bar
        // and ghosted through it; the content-area clip now cuts it off at the bar's top edge.
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        waitForTag("fst.song-detail.paths.open")
        val barTop = rule.onNodeWithTag("fst.nav.tab.songs").fetchSemanticsNode().boundsInRoot.top
        val shown = rule.onNodeWithTag("fst.nav.floating-toolbar").fetchSemanticsNode().boundsInRoot
        assertTrue("shown $shown above bar $barTop", shown.height > 0f && shown.bottom <= barTop)
        repeat(3) {
            rule.onNodeWithTag("fst.song-detail.list").performTouchInput { swipeUp() }
            settle()
        }
        val hidden = rule.onNodeWithTag("fst.nav.floating-toolbar").fetchSemanticsNode().boundsInRoot
        assertTrue("hidden toolbar still visible: $hidden", hidden.height < 1f)
        // Scrolling back brings it back above the bar.
        rule.onNodeWithTag("fst.song-detail.list").performTouchInput { swipeDown() }
        settle()
        assertTrue(rule.onNodeWithTag("fst.nav.floating-toolbar").fetchSemanticsNode().boundsInRoot.height > 0f)
    }

    @Test
    fun songDetailHistoryViewAllOpensTheHistoryPage() {
        val rows = (1..6).joinToString(",") { day ->
            """{"songId":"s-alpha","instrument":"Solo_Guitar","newScore":${700000 + day},"newRank":9,"accuracy":990000,"isFullCombo":false,"season":40,"changedAt":"2024-01-0${day}T00:00:00Z"}"""
        }
        val transport = transport().apply {
            on("/api/player/${Fixtures.ACCOUNT_A}/history") { """{"accountId":"${Fixtures.ACCOUNT_A}","count":6,"history":[$rows]}""" }
        }
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), transport = transport)
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.history.view-all"))
        click("fst.song-detail.history.view-all")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.song-detail.list").fetchSemanticsNodes().isEmpty() }
    }

    @Test
    fun shopListOnPhone() {
        launch(DebugLaunch(route = ShopRoute, stillBackground = true))
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-beta")
        rule.onNodeWithTag("fst.shop.badge.new.s-beta", useUnmergedTree = true).assertExists()
        click("fst.shop.song.s-alpha")
        waitForTag("fst.song-detail.list")
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun shopGridToggleOnExpanded() {
        launch(DebugLaunch(route = ShopRoute, stillBackground = true))
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.grid")
        // Web ShopCard: the card opens the official Shop; Song Details is a long press / custom action.
        waitForTag("fst.shop.song.s-alpha")
        rule.onNodeWithTag("fst.shop.song.s-alpha").performTouchInput { longClick() }
        waitForTag("fst.song-detail.list")
    }

    @Test
    fun shopEmptyAndCatalogueFailureStayDistinct() {
        val broken = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"count":0,"songs":[]}""" }
            on("/api/songs", status = 500) { "{}" }
        }
        launch(DebugLaunch(route = ShopRoute, stillBackground = true), transport = broken)
        waitForTag("fst.shop.empty")
        waitForTag("fst.shop.song-details-error")
        rule.onNodeWithText("Retry").performClick()
        settle()
    }

    @Test
    fun shopFailureAndHiddenStates() {
        val failing = transport().apply { on("/api/shop", status = 500) { "{}" } }
        launch(DebugLaunch(route = ShopRoute, stillBackground = true), transport = failing)
        waitForTag("fst.shop.error")
    }

    @Test
    fun shopFilterSheetFiltersListAndKeepsStateWhenReopened() {
        launch(DebugLaunch(route = ShopRoute, stillBackground = true))
        waitForTag("fst.shop.song.s-alpha")
        click("fst.shop.filter.open")
        waitForTag("fst.shop.filter.new")
        click("fst.shop.filter.new")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.shop.song.s-alpha").fetchSemanticsNodes().isEmpty() }
        assertTrue(rule.onAllNodesWithTag("fst.shop.song.s-x").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.shop.song.s-beta").assertExists()
        click("fst.shop.filter.done")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.shop.filter.new").fetchSemanticsNodes().isEmpty() }
        click("fst.shop.filter.open")
        waitForTag("fst.shop.filter.new")
        rule.onNodeWithTag("fst.shop.filter.new").assertIsOn()
        rule.onNodeWithTag("fst.shop.filter.available").assertIsOff()
        click("fst.shop.filter.available")
        waitForTag("fst.shop.song.s-x")
        click("fst.shop.filter.reset")
        waitForTag("fst.shop.song.s-alpha")
        rule.onNodeWithTag("fst.shop.filter.new").assertIsOff()
    }

    @Test
    fun shopFilterWithNoMatchesOffersReset() {
        val plain = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) {
                """{"count":1,"songs":[{"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/alpha"}]}"""
            }
        }
        launch(DebugLaunch(route = ShopRoute, stillBackground = true), transport = plain)
        waitForTag("fst.shop.song.s-alpha")
        click("fst.shop.filter.open")
        waitForTag("fst.shop.filter.leaving")
        click("fst.shop.filter.leaving")
        click("fst.shop.filter.done")
        waitForTag("fst.shop.filter.empty")
        assertTrue(rule.onAllNodesWithTag("fst.shop.empty").fetchSemanticsNodes().isEmpty())
        click("fst.shop.filter.empty-reset")
        waitForTag("fst.shop.song.s-alpha")
    }

    @Test
    fun hiddenShopShowsNotice() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true))
        launch(DebugLaunch(route = ShopRoute, stillBackground = true), prefs)
        waitForTag("fst.shop.hidden")
        rule.onNodeWithText("Go Back").performClick()
        settle()
    }
}
