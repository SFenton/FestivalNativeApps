package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.common.formatCountdown
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

/**
 * Whole-shell Compose tests on Robolectric against synthetic fixtures (no network:
 * fixture songs carry no artwork, and every read goes through [FakeTransport]).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShellUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun launch(debug: DebugLaunch = DebugLaunch(stillBackground = true), transport: FakeTransport = this.transport) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun anonymousPhoneShowsCatalogueAndAnonymousTabs() {
        launch()
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.bar").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.settings").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.tab.statistics").fetchSemanticsNodes().size)
        // General filters need no profile (web), so Filter is always offered.
        rule.onNodeWithTag("fst.songs.filter.open").assertIsDisplayed()
        rule.onNodeWithContentDescription("Choose profile").assertIsDisplayed()
    }

    @Test
    fun systemBackClosesTheOpenDrawerInsteadOfLeaving() {
        launch()
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.drawer").performClick()
        waitForTag("fst.nav.drawer-sheet")
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.nav.drawer-sheet").fetchSemanticsNodes().none { node -> node.layoutInfo.isPlaced && node.boundsInRoot.right > 0f } }
        // Still in the app, on Songs.
        assertTrue(!rule.activity.isFinishing)
        rule.onNodeWithTag("fst.songs.row.s-alpha").assertIsDisplayed()
    }

    @Test
    fun searchSortAndSectionIndex() {
        launch()
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.songs.section-index").assertIsDisplayed()
        rule.onNodeWithTag("fst.songs.search").performTextInput("beta")
        rule.waitUntil(5_000) { settle(100); rule.onAllNodesWithTag("fst.songs.row.s-alpha").fetchSemanticsNodes().isEmpty() }
        rule.onNodeWithTag("fst.songs.row.s-beta").assertIsDisplayed()
        rule.onNodeWithContentDescription("Clear search").performClick()
        settle(600)
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.songs.search").performTextInput("zzzz")
        waitForTag("fst.songs.empty")
        rule.onNodeWithContentDescription("Clear search").performClick()
        settle(600)
        rule.onNodeWithTag("fst.songs.sort.open").performClick()
        settle()
        rule.onNodeWithText("Sort Songs").assertIsDisplayed()
        rule.onNodeWithTag("fst.songs.sort.artist").performClick()
        rule.onNodeWithText("Descending").performClick()
        rule.onNodeWithTag("fst.songs.sort.done").performClick()
        settle()
    }

    @Test
    fun songDetailPreviewAndFullLeaderboard() {
        launch()
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.songs.row.s-alpha").performClick()
        waitForTag("fst.song-detail.intensity")
        rule.onNodeWithText("Intensity").assertIsDisplayed()
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        waitForTag("fst.song-detail.view-all.Solo_Guitar")
        rule.onNodeWithTag("fst.song-detail.view-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-leaderboard.list")
        rule.waitUntil(5_000) { settle(100); rule.onAllNodes(hasContentDescription("Page 1 of 3")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.song-leaderboard.page-info").assertIsDisplayed()
        rule.onNodeWithContentDescription("Next page").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        rule.waitUntil(5_000) { settle(100); rule.onAllNodes(hasContentDescription("Page 2 of 3")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.nav.back").performClick()
        waitForTag("fst.song-detail.intensity")
        rule.onNodeWithTag("fst.nav.back").performClick()
        waitForTag("fst.songs.row.s-alpha")
    }

    @Test
    fun selectedPlayerTabsFilterAndPlaceholders() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.tab.suggestions").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.compete").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsDisplayed()
        // The top-bar avatar (the closed drawer's profile row carries the same label).
        rule.onNodeWithTag("fst.nav.profile").assertIsDisplayed().assert(hasContentDescription("Profile: Synthetic Player"))
        rule.onNodeWithTag("fst.songs.filter.open").performClick()
        settle()
        // Phone sheet: the Instrument Selector is compact; ‹ previews Pro Drums, the centre commits it.
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.instrument.previous"))
        rule.onNodeWithTag("fst.songs.filter.instrument.previous").performClick()
        rule.onNodeWithTag("fst.songs.filter.instrument.preview").performClick()
        rule.onNodeWithTag("fst.songs.filter.done").performClick()
        settle()
        rule.onNodeWithTag("fst.nav.tab.statistics").performClick()
        waitForTag("fst.statistics")
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        waitForTag("fst.songs.list")
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        settle()
    }

    @Test
    fun settingsTogglesAndDrawerNavigation() {
        launch(DebugLaunch(section = com.festivalscoretracker.android.core.nav.FestivalSection.Settings, stillBackground = true))
        waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.instrument.Solo_Bass"))
        rule.onNodeWithTag("fst.settings.instrument.Solo_Bass").performSemanticsAction(SemanticsActions.OnClick)
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.motion"))
        rule.onNodeWithTag("fst.settings.contrast").performSemanticsAction(SemanticsActions.OnClick)
        rule.onNodeWithTag("fst.settings.motion").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        rule.onNodeWithTag("fst.nav.drawer").performClick()
        waitForTag("fst.nav.drawer.shop")
        rule.onNodeWithTag("fst.nav.drawer.shop").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-alpha")
        rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).assertExists()
    }

    @Test
    fun scrapeFreezeShowsCountdownAndRetryNowRecovers() {
        var frozen = true
        val freezing = FakeTransport.standard().apply {
            onRaw("/api/songs") {
                if (frozen) {
                    com.festivalscoretracker.android.data.HttpResult(503, "{}".toByteArray(), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
                } else {
                    com.festivalscoretracker.android.data.HttpResult(200, Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null").toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
                }
            }
        }
        launch(transport = freezing)
        waitForTag("fst.service-status.countdown")
        rule.onNodeWithText("Scores are updating").assertIsDisplayed()
        frozen = false
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        waitForTag("fst.songs.row.s-alpha")
        assertEquals("0:30", formatCountdown(30))
        assertEquals("5:00", formatCountdown(300))
    }

    @Test
    fun songOpenedByDebugTitleAndMissingSongShowsNotFound() {
        launch(DebugLaunch(songQuery = "Beta Song", stillBackground = true))
        waitForTag("fst.song-detail.intensity")
        // The song header names it; the top bar takes the title once the header scrolls away.
        assertEquals(1, rule.onAllNodes(hasText("Beta Song")).fetchSemanticsNodes().size)
    }
}

/** Expanded window: permanent drawer and Songs list-detail. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedShellUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun expandedWindowUsesPermanentDrawerAndTwoPanes() {
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.songs.row.s-gamma").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.nav.drawer-sheet").assertIsDisplayed()
        // Two populated columns before any pick: the first row fills the detail pane (never
        // an empty "Select a song" pane).
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.song-detail.intensity").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.songs.detail-pane").assertIsDisplayed()
        assertTrue(rule.onAllNodesWithTag("fst.songs.detail-placeholder").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.songs.row.s-gamma").performClick()
        rule.waitUntil(10_000) {
            settle()
            rule.onNodeWithTag("fst.songs.row.s-gamma").fetchSemanticsNode().config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Selected) == true
        }
        rule.onNodeWithTag("fst.songs.detail-pane").assertIsDisplayed()
        rule.onNodeWithTag("fst.songs.row.s-gamma").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.settings.list").fetchSemanticsNodes().isNotEmpty() }
    }
}
