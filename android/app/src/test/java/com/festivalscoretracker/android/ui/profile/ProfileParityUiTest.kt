package com.festivalscoretracker.android.ui.profile

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Shared launch/wait helpers for profile parity journeys. */
internal class ProfileJourney(private val rule: androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, ComponentActivity>) {
    val store = InMemoryPreferences()
    val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        ProfileFixtures.register(this, Fixtures.ACCOUNT_B)
    }
    lateinit var container: AppContainer

    fun launch(debug: DebugLaunch) {
        container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    fun waitGone(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    fun scrollTo(tag: String) {
        waitForTag("fst.player.available")
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag(tag))
        settle()
    }

    fun tap(tag: String) {
        waitForTag(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }
}

/** Quick Links, top songs and tap-to-filter tiles on a phone. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ProfileParityUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val journey = ProfileJourney(rule)

    @Test
    fun quickLinksJumpToTopSongsAndBands() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        journey.waitForTag("fst.player.select")
        journey.tap("fst.quick-links.open")
        journey.waitForTag("fst.quick-links.sheet")
        listOf("global", "instrument:Solo_Guitar", "instrument:Solo_Bass", "top-songs", "bands").forEach {
            journey.waitForTag("fst.quick-links.item.$it")
        }
        journey.tap("fst.quick-links.item.top-songs")
        journey.waitGone("fst.quick-links.sheet")
        journey.waitForTag("fst.player.top-songs")
        rule.onNodeWithText("Top Songs Per Instrument").assertIsDisplayed()
        journey.waitForTag("fst.player.top-songs.Solo_Guitar")
        journey.tap("fst.quick-links.open")
        journey.tap("fst.quick-links.item.bands")
        journey.waitForTag("fst.player.bands-link")
        rule.onNodeWithTag("fst.player.bands-link").assertIsDisplayed()
    }

    @Test
    fun topSongsListRankedSongsAndEmptyCharts() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        journey.scrollTo("fst.player.top-song.Solo_Guitar.s-alpha")
        rule.onNodeWithTag("fst.player.top-song.Solo_Guitar.s-alpha").assert(hasContentDescription("Alpha Tune, Band One · 2021, Top 1%"))
        journey.scrollTo("fst.player.top-songs-empty.Solo_Drums")
        rule.onNodeWithText("Play some songs on Drums to see your stats appear here.").assertIsDisplayed()
        // Rows open Song Detail after selecting the viewed player (nothing was selected).
        journey.scrollTo("fst.player.top-song.Solo_Guitar.s-beta")
        journey.tap("fst.player.top-song.Solo_Guitar.s-beta")
        journey.waitForTag("fst.song-detail.list")
        assertEquals(Fixtures.ACCOUNT_A, runBlocking { journey.container.settings.settings.first() }.selectedPlayer?.accountId)
    }

    @Test
    fun instrumentTileFiltersSongs() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        journey.scrollTo("fst.player.tile.Solo_Bass.songs-played")
        journey.tap("fst.player.tile.Solo_Bass.songs-played")
        journey.waitForTag("fst.songs.list")
        val saved = runBlocking { journey.container.songsPreferences.state.first() }
        assertEquals(SongFilter(Instrument.Bass), saved.filter)
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Bass)), saved.playerFilter)
        // Only the song with a Bass score stays.
        journey.waitForTag("fst.songs.row.s-alpha")
        journey.waitGone("fst.songs.row.s-beta")
        journey.waitForTag("fst.nav.tab.statistics")
    }

    @Test
    fun switchIsConfirmedBeforeATileNavigates() {
        journey.launch(
            DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_B, "Other"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true),
        )
        journey.waitForTag("fst.player.select")
        journey.tap("fst.player.tile.overview.songs-played")
        journey.waitForTag("fst.player.action-switch-confirm")
        rule.onNodeWithText("Switch to Synthetic Player?").assertIsDisplayed()
        journey.tap("fst.player.action-switch-confirm.cancel")
        journey.waitGone("fst.player.action-switch-confirm")
        // Cancel keeps the other player selected and stays here.
        rule.onNodeWithText("Switch to This Profile").assertIsDisplayed()
        journey.tap("fst.player.tile.overview.best-rank")
        journey.tap("fst.player.action-switch-confirm.ok")
        journey.waitForTag("fst.song-detail.list")
    }

    @Test
    fun globalRankTileOpensFullRankings() {
        journey.launch(
            DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true),
        )
        journey.waitForTag("fst.player.deselect")
        journey.scrollTo("fst.player.tile.rank.Solo_Guitar.global-rank")
        journey.tap("fst.player.tile.rank.Solo_Guitar.global-rank")
        rule.waitUntil(10_000) {
            journey.settle(100)
            rule.onAllNodesWithTag("fst.player.available").fetchSemanticsNodes().isEmpty()
        }
        rule.onNodeWithText("Lead Rankings").assertIsDisplayed()
    }

    @Test
    fun pausedSelectionLeavesSongsTilesFlat() {
        journey.transport.on("/api/player/${Fixtures.ACCOUNT_B}") { ProfileFixtures.profile(Fixtures.ACCOUNT_B) }
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B), stillBackground = true))
        journey.waitForTag("fst.player.identity-notice")
        // Songs filters need the selection, so those tiles are flat; Best Rank still opens the song.
        rule.onNodeWithTag("fst.player.tile.overview.songs-played").assert(SemanticsMatcher.keyNotDefined(SemanticsActions.OnClick))
        journey.tap("fst.player.tile.overview.best-rank")
        journey.waitForTag("fst.song-detail.list")
    }
}

/** Charts draw with native graphics so the Canvas code runs. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ProfileChartsDrawTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val journey = ProfileJourney(rule)

    /** Draw the window into a bitmap (runs every Canvas lambda on screen); true when something was painted. */
    private fun draw(): Boolean {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return (0 until bitmap.height step 16).any { y -> (0 until bitmap.width step 16).any { x -> bitmap.getPixel(x, y) != 0 } }
    }

    @Test
    fun rankHistoryAndPercentileChartsDraw() {
        journey.launch(
            DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true),
        )
        journey.scrollTo("fst.player.rank-history.Solo_Guitar")
        journey.waitForTag("fst.player.rank-history.Solo_Guitar")
        assertTrue(draw())
        journey.scrollTo("fst.player.percentiles.Solo_Guitar")
        assertTrue(draw())
    }
}

/** Expanded window: Quick Links become the persistent trailing pane. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-mdpi")
class ProfileParityExpandedUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val journey = ProfileJourney(rule)

    @Test
    fun quickLinksPaneJumpsWithoutClosing() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        journey.waitForTag("fst.quick-links.pane")
        assertTrue(rule.onAllNodesWithTag("fst.quick-links.open").fetchSemanticsNodes().isEmpty())
        journey.tap("fst.quick-links.item.top-songs")
        journey.waitForTag("fst.player.top-songs")
        journey.waitForTag("fst.quick-links.pane")
    }
}
