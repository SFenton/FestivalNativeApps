package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
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
        rule.onNodeWithTag("fst.songs.chip.Solo_Guitar.FullCombo", useUnmergedTree = true).assertExists()

        click("fst.songs.filter.open")
        settle()
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.score.instrument.Solo_Guitar.HasScores"))
        click("fst.songs.filter.score.instrument.Solo_Guitar.HasScores")
        click("fst.songs.filter.score.global.MissingFCs")
        click("fst.songs.filter.score.global.MissingFCs")
        click("fst.songs.filter.apply")
        rule.waitUntil(5_000) { settle(100); rule.onAllNodesWithTag("fst.songs.row.s-beta").fetchSemanticsNodes().isEmpty() }
        waitForTag("fst.songs.row.s-alpha")

        click("fst.songs.sort.open")
        settle()
        click("fst.songs.sort.shop")
        click("fst.songs.sort.apply")
        waitForTag("fst.songs.row.s-alpha")

        click("fst.songs.filter.open")
        settle()
        click("fst.songs.filter.reset")
        click("fst.songs.filter.cancel")
        settle()
        rule.onNodeWithText("Discard Changes?").assertIsDisplayed()
        click("fst.songs.filter.discard")
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
    fun songDetailShowsYourScoreShopPathsAndHistory() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_PeripheralVocals"))
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), prefs)
        waitForTag("fst.song-detail.list")
        waitForTag("fst.song-detail.shop", unmerged = true)
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.your-score.Solo_Guitar"))
        waitForTag("fst.song-detail.your-score.Solo_Guitar", unmerged = true)
        rule.onNodeWithText("Your score: 95,198 · 98.7% · FC · Top 5% · #42", substring = true, useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.history.Solo_Guitar"))
        rule.onNodeWithTag("fst.song-detail.your-rank.Solo_Guitar").assertExists()

        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.paths.open"))
        click("fst.song-detail.paths.open")
        waitForTag("fst.paths.karaoke-warning")
        click("fst.paths.warning.never")
        waitForTag("fst.paths.image")
        click("fst.paths.zoom-in")
        click("fst.paths.display.text")
        waitForTag("fst.paths.table")
        waitForTag("fst.paths.row.1")
        click("fst.paths.difficulty.hard")
        waitForTag("fst.paths.not-generated")
        click("fst.paths.close")
        settle()

        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.history.Solo_Guitar"))
        click("fst.song-detail.history.Solo_Guitar")
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
        waitForTag("fst.shop.details.s-alpha")
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.grid")
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
    fun hiddenShopShowsNotice() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true))
        launch(DebugLaunch(route = ShopRoute, stillBackground = true), prefs)
        waitForTag("fst.shop.hidden")
        rule.onNodeWithText("Go Back").performClick()
        settle()
    }
}
