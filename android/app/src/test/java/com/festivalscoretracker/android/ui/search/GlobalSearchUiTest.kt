package com.festivalscoretracker.android.ui.search

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.search.ShellShortcut
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.shell.ShellShortcutBridge
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Shared launch/settle helpers for the search journeys. */
private class SearchHarness(val rule: AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>) {
    val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }
    val shortcuts = ShellShortcutBridge()

    fun launch(debug: DebugLaunch = DebugLaunch(stillBackground = true)) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug, shortcuts) }
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

    fun waitForGone(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    /** Every band-search request (must stay empty: the service's band search GET can write). */
    fun bandSearches() = transport.requests.filter { "/api/bands/search" in it.url }
}

/** Global search on a phone: action → full-screen search view. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class GlobalSearchUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { SearchHarness(rule) }

    @Test
    fun hintResultsScopesAndBandsExplanationWithoutBandSearch() {
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        assertEquals(1, rule.onAllNodesWithTag(GlobalSearchTags.OPEN).fetchSemanticsNodes().size)
        // Phone: search and page actions float over the bottom bar, not in the top app bar.
        val inToolbar = hasAnyAncestor(hasTestTag("fst.nav.floating-toolbar"))
        rule.onNode(hasTestTag(GlobalSearchTags.OPEN) and inToolbar).assertIsDisplayed()
        rule.onNode(hasTestTag("fst.songs.sort.open") and inToolbar).assertIsDisplayed()
        assertEquals(0, rule.onAllNodes(hasTestTag("fst.songs.sort.open") and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT))
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("a")
        h.settle(600)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT))
        assertTrue(h.transport.sent("/api/account/search").isEmpty())

        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("synthetic")
        h.waitForTag(GlobalSearchTags.RESULT_PLAYER)
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithTag(GlobalSearchTags.STATUS).assert(hasText("0 songs, 1 player"))
        rule.onNodeWithTag(GlobalSearchTags.STATUS).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion))
        assertEquals(1, h.transport.sent("/api/account/search").size)
        assertTrue(h.transport.sent("/api/account/search").single().url.contains("limit=10"))
        h.transport.sent("/api/account/search").single().headers.keys.forEach { key ->
            assertTrue(!key.equals("X-API-Key", true) && !key.lowercase().startsWith("x-fst-selected"))
        }

        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Songs)).assertIsDisplayed()

        // Scope segments fill the width equally (phone), no icon on Bands.
        val row = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        val widths = SearchScope.chips.map { rule.onNodeWithTag(GlobalSearchTags.scope(it)).fetchSemanticsNode().boundsInRoot.width }
        assertTrue("segments $widths", widths.max() - widths.min() < 2f)
        assertTrue(widths.sum() > row.width - 4f)
        // Scope toggles: Songs only, then back to all.
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsOn()
        assertEquals(0, rule.onAllNodesWithTag(GlobalSearchTags.section(SearchScope.Players)).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsOff()

        // Bands: explanation, no request, Band Rankings link.
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Bands)).performClick()
        h.waitForTag(GlobalSearchTags.BANDS_UNAVAILABLE)
        rule.onNodeWithText(GlobalSearchResults.BANDS_UNAVAILABLE).assertIsDisplayed()
        assertTrue(h.bandSearches().isEmpty())
        rule.onNodeWithTag(GlobalSearchTags.BANDS_RANKINGS).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        rule.waitUntil(10_000) { h.settle(100); rule.onAllNodesWithText("Duos Rankings").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(h.bandSearches().isEmpty())
    }

    @Test
    fun songResultPushesDetailOnCurrentSectionAndBackReturns() {
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.song-detail.intensity")
        rule.onNodeWithTag("fst.nav.back").performClick()
        h.waitForTag("fst.songs.row.s-alpha")
        // The query was not kept (web parity: nothing remembered after navigating).
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.HINT)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT))
        // Close button collapses.
        rule.onNodeWithTag(GlobalSearchTags.CLOSE).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
    }

    @Test
    fun playerResultOpensProfileAndSelectedPlayerOpensStatistics() {
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true))
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("synthetic")
        h.waitForTag(GlobalSearchTags.RESULT_PLAYER)
        rule.onNodeWithText("Selected player · Statistics").assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_PLAYER).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.statistics")
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsSelected()
    }

    @Test
    fun emptyPlayersOfferRetryAndClearButtonClears() {
        h.transport.on("/api/account/search") { """{"results":[]}""" }
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("zzzz")
        rule.waitUntil(10_000) { h.settle(100); rule.onAllNodes(hasText(GlobalSearchResults.NO_RESULTS)).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag(GlobalSearchTags.RETRY).performClick()
        rule.waitUntil(10_000) { h.settle(100); h.transport.sent("/api/account/search").size == 2 }
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Players)).performClick()
        h.waitForTag(GlobalSearchTags.RETRY)
        rule.onNodeWithText(GlobalSearchResults.NO_PLAYERS).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.CLEAR).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT))
    }

    @Test
    fun playersFreezeShowsScoresUpdatingWhileSongsStay() {
        h.transport.onRaw("/api/account/search") {
            HttpResult(503, "{}".toByteArray(), mapOf("Retry-After" to "60", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
        }
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag("fst.global-search.players-error")
        rule.onNodeWithText("Scores are updating").assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed()
    }

    @Test
    fun keyboardShortcutsAndDebugLaunchOpenSearch() {
        h.launch(DebugLaunch(stillBackground = true, searchQuery = "alpha", searchScope = SearchScope.Songs))
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsOn()
        rule.onNodeWithTag(GlobalSearchTags.CLOSE).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        rule.runOnIdle { assertTrue(h.shortcuts.dispatch(ShellShortcut.OpenSearch)) }
        h.waitForTag(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.CLOSE).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        // Ctrl+F with no page find registered falls back to global search.
        rule.runOnIdle { assertTrue(h.shortcuts.dispatch(ShellShortcut.FindInPage)) }
        h.waitForTag(GlobalSearchTags.SURFACE)
    }

    @Test
    fun searchActionExistsOnPushedPages() {
        h.launch(DebugLaunch(songQuery = "Beta Song", stillBackground = true))
        h.waitForTag("fst.song-detail.intensity")
        rule.onAllNodesWithTag(GlobalSearchTags.OPEN).onFirst().assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performSemanticsAction(SemanticsActions.OnClick)
        h.waitForTag(GlobalSearchTags.SURFACE)
    }
}

/** Global search on an expanded window: persistent bar → docked panel. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedGlobalSearchUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun searchActionOpensDockedPanel() {
        val h = SearchHarness(rule)
        h.launch(DebugLaunch(section = com.festivalscoretracker.android.core.nav.FestivalSection.Settings, stillBackground = true))
        h.waitForTag("fst.settings.list")
        // An icon action at every width (no persistent search field), in the top app bar here.
        rule.onNodeWithTag(GlobalSearchTags.OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Search")))
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.floating-toolbar").fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        h.waitForTag(GlobalSearchTags.RESULT_PLAYER)
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.song-detail.intensity")
        assertTrue(h.bandSearches().isEmpty())
    }

    @Test
    fun songsListPaneKeepsOneSearchEntry() {
        val h = SearchHarness(rule)
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        assertEquals(1, rule.onAllNodesWithTag(GlobalSearchTags.OPEN).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT))
    }
}

/** Global search on a medium window: rail, search action → docked panel. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w700dp-h1000dp-xhdpi")
class MediumGlobalSearchUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun railLayoutDocksSearchUnderTheAction() {
        val h = SearchHarness(rule)
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.rail").assertIsDisplayed()
        // Rail menu button: centred in the rail and on the top app bar's row.
        val menu = rule.onNodeWithTag("fst.nav.drawer").fetchSemanticsNode().boundsInRoot
        val rail = rule.onNodeWithTag("fst.nav.rail").fetchSemanticsNode().boundsInRoot
        val bar = rule.onNodeWithTag("fst.nav.top-bar").fetchSemanticsNode().boundsInRoot
        assertEquals(rail.center.x, menu.center.x, 1.5f)
        assertEquals(bar.center.y, menu.center.y, 1.5f)
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.floating-toolbar").fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Search")))
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.CLOSE).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        assertTrue(h.bandSearches().isEmpty())
    }
}
