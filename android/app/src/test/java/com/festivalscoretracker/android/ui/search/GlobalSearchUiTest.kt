package com.festivalscoretracker.android.ui.search

import com.festivalscoretracker.android.core.nav.FestivalSection
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.onNodeWithContentDescription
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
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
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.semantics.Role
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

    /** Every band-search request (a keyless pure read since FortniteFestivalLeaderboardScraper#170). */
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
    fun hintResultsScopesAndBandResultsOpenTheBandPage() {
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        assertEquals(1, rule.onAllNodesWithTag(GlobalSearchTags.OPEN).fetchSemanticsNodes().size)
        // Phone: page actions float over the bottom bar; search stays in the top app bar.
        val inToolbar = hasAnyAncestor(hasTestTag("fst.nav.floating-toolbar"))
        rule.onNode(hasTestTag(GlobalSearchTags.OPEN) and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).assertIsDisplayed()
        rule.onNode(hasTestTag("fst.songs.sort.open") and inToolbar).assertIsDisplayed()
        assertEquals(0, rule.onAllNodes(hasTestTag("fst.songs.sort.open") and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_ALL))
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("a")
        h.settle(600)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_ALL))
        assertTrue(h.transport.sent("/api/account/search").isEmpty())

        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("synthetic")
        h.waitForTag(GlobalSearchTags.RESULT_PLAYER)
        // Issue #348: in All each shown category has its web-order title; "synthetic" matches no
        // songs, so only Players and Bands are titled (empty categories are omitted, like the web).
        val headings = SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and hasAnyAncestor(hasTestTag(GlobalSearchTags.SURFACE))
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)).assert(hasText("Players"))
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Songs)).assertDoesNotExist()
        // Counts are announced (polite live region) but never drawn as text (operator batch 6).
        rule.onNodeWithTag(GlobalSearchTags.STATUS).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("0 songs, 1 player, 2 bands")))
        rule.onNodeWithTag(GlobalSearchTags.STATUS).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion))
        assertEquals(0, rule.onAllNodesWithText("0 songs, 1 player, 2 bands").fetchSemanticsNodes().size)
        assertEquals(1, h.transport.sent("/api/account/search").size)
        assertTrue(h.transport.sent("/api/account/search").single().url.contains("limit=10"))
        h.transport.sent("/api/account/search").single().headers.keys.forEach { key ->
            assertTrue(!key.equals("X-API-Key", true) && !key.lowercase().startsWith("x-fst-selected"))
        }

        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Songs)).assert(hasText("Songs"))

        // Scope pills: equal shares of the row (two 8 dp gaps), pill-shaped and at least 48 dp to touch.
        val row = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        val chips = SearchScope.chips.map { rule.onNodeWithTag(GlobalSearchTags.scope(it)).fetchSemanticsNode() }
        val widths = chips.map { it.boundsInRoot.width }
        assertTrue("pills $widths", widths.max() - widths.min() < 2f)
        assertTrue("pills $widths in ${row.width}", widths.sum() > row.width - 16 * 3f - 4f)
        chips.forEach { assertTrue(it.touchBoundsInRoot.height >= 48 * 3f - 1f) }
        // Scope toggles: Songs only, then back to all.
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsNotSelected()
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsSelected()
        assertEquals(0, rule.onAllNodesWithTag(GlobalSearchTags.RESULT_PLAYER).fetchSemanticsNodes().size)
        // Issue #299: a single scope has no section title; its chip already names it.
        assertEquals(0, rule.onAllNodes(headings).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsNotSelected()

        // Bands: the same settled query already searched bands (web useUnifiedSearch); the chip
        // only filters, so no new request. Malformed and repeated rows were dropped.
        val bandRequests = h.bandSearches().size
        assertTrue(bandRequests >= 2)
        h.bandSearches().forEach { request ->
            assertTrue(request.url, request.url.contains("page=1&pageSize=10"))
            request.headers.keys.forEach { key -> assertTrue(!key.equals("X-API-Key", true) && !key.lowercase().startsWith("x-fst-selected")) }
        }
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Bands)).performClick()
        h.waitForTag(GlobalSearchTags.RESULT_BAND)
        assertEquals(2, rule.onAllNodesWithTag(GlobalSearchTags.RESULT_BAND).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag(GlobalSearchTags.RESULT_SONG).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag(GlobalSearchTags.RESULT_PLAYER).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithText("Band search isn't available", substring = true).fetchSemanticsNodes().size)
        // The player-bands card: member names, size and appearances as one "Open band" button.
        rule.onAllNodesWithTag(GlobalSearchTags.RESULT_BAND).onFirst()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Synthetic Lead + Synthetic Bass, Duos, 12 appearances")))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        assertEquals(bandRequests, h.bandSearches().size)
        rule.onAllNodesWithTag(GlobalSearchTags.RESULT_BAND).onFirst().performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.band.screen")
    }

    @Test
    fun bandsEmptyAndFailureFollowThePlayersRules() {
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Bands)).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_BANDS))
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("zzzz")
        rule.waitUntil(10_000) { h.settle(100); rule.onAllNodesWithText(GlobalSearchResults.EMPTY_BANDS_TITLE).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText(GlobalSearchResults.EMPTY_BANDS_SUBTITLE).assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithText("Retry").fetchSemanticsNodes().size)
        // A failure is not "No bands found": it shows the service status line, still without Retry.
        h.transport.on("/api/bands/search", status = 500) { "{}" }
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performImeAction()
        h.waitForTag(GlobalSearchTags.BANDS_ERROR)
        assertEquals(0, rule.onAllNodesWithText(GlobalSearchResults.EMPTY_BANDS_TITLE).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithText("Retry").fetchSemanticsNodes().size)
        assertEquals(2, h.bandSearches().size)
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
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_ALL))
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
    fun emptyResultsHaveNoRetrySearchKeyRunsAgainAndClearButtonClears() {
        h.transport.on("/api/account/search") { """{"results":[]}""" }
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("zzzz")
        rule.waitUntil(10_000) { h.settle(100); rule.onAllNodes(hasText(GlobalSearchResults.EMPTY_ALL_TITLE)).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_SUBTITLE).assertIsDisplayed()
        // Issue #299: no Retry button; the keyboard Search action runs the same text again.
        assertEquals(0, rule.onAllNodesWithText("Retry").fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performImeAction()
        rule.waitUntil(10_000) { h.settle(100); h.transport.sent("/api/account/search").size == 2 }
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Players)).performClick()
        rule.waitUntil(10_000) { h.settle(100); rule.onAllNodesWithText(GlobalSearchResults.EMPTY_PLAYERS_TITLE).fetchSemanticsNodes().isNotEmpty() }
        assertEquals(0, rule.onAllNodesWithText("Retry").fetchSemanticsNodes().size)
        rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.CLEAR).performClick()
        h.settle()
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_PLAYERS))
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
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true, searchQuery = "alpha", searchScope = SearchScope.Songs))
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsSelected()
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
    fun findInPageFocusesTheSongsFilter() {
        h.launch()
        h.waitForTag("fst.songs.search")
        rule.onNodeWithTag("fst.songs.list").performScrollToIndex(2)
        h.settle()
        rule.runOnIdle { assertTrue(h.shortcuts.dispatch(ShellShortcut.FindInPage)) }
        h.settle()
        // Ctrl+F focuses the inline filter pinned above the list, on phones too (issue #309).
        rule.onNodeWithTag("fst.songs.search").assertIsFocused()
        assertTrue(rule.onAllNodesWithTag(GlobalSearchTags.SURFACE).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun songsFilterIsPinnedInlineWhileSortAndFilterStayInTheBottomToolbar() {
        // Issue #309 (option C): on a phone the Songs filter is pinned inline above the list (web
        // SongsToolbar, Apple's Filter Songs field), global search stays in the top app bar, and
        // the pinned floating toolbar holds only the page tools. Issue #52: nothing scrolls away.
        val songs = (1..40).joinToString(",") { i ->
            """{"songId":"s-$i","title":"${'A' + (i - 1) / 2} Song ${"%02d".format(i)}","artist":"${'A' + (i - 1) / 2} Band $i","year":2020,"durationSeconds":120,"difficulty":{"guitar":1}}"""
        }
        h.transport.on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"count":40,"currentSeason":15,"songs":[$songs]}""" }
        h.launch()
        h.waitForTag("fst.songs.row.s-1")
        val inToolbar = hasAnyAncestor(hasTestTag("fst.nav.floating-toolbar"))
        val inTopBar = hasAnyAncestor(hasTestTag("fst.nav.top-bar"))
        fun bounds(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
        val dp48 = 48 * 3f // xxhdpi
        // One filter field, inline: not in the toolbar or the top app bar, and no toolbar search entry.
        rule.onNodeWithTag("fst.songs.search").assertIsDisplayed()
        assertEquals(0, rule.onAllNodes(hasTestTag("fst.songs.search") and inToolbar).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodes(hasTestTag("fst.songs.search") and inTopBar).fetchSemanticsNodes().size)
        assertTrue(rule.onAllNodesWithTag("fst.songs.search.open").fetchSemanticsNodes().isEmpty())
        // Global search stays a top app bar action.
        rule.onNode(hasTestTag(GlobalSearchTags.OPEN) and inTopBar).assertIsDisplayed()
        val fieldAtTop = bounds("fst.songs.search")
        val toolbarAtTop = bounds("fst.nav.floating-toolbar")
        assertTrue(fieldAtTop.height >= dp48 - 1f)
        assertTrue("field above the rows", fieldAtTop.bottom <= bounds("fst.songs.row.s-1").top + 1f)
        assertTrue("field below the top app bar", fieldAtTop.top >= bounds("fst.nav.top-bar").bottom - 1f)
        // The toolbar floats at the bottom of the page, below the list's first rows.
        assertTrue(toolbarAtTop.top > bounds("fst.songs.row.s-1").bottom)

        repeat(3) {
            rule.onNodeWithTag("fst.songs.list").performTouchInput { swipeUp() }
            h.settle()
        }
        assertTrue(rule.onAllNodesWithTag("fst.songs.row.s-1").fetchSemanticsNodes().isEmpty())
        // Pinned, not merely present: the field and the toolbar keep their bounds while scrolled.
        assertEquals(fieldAtTop, bounds("fst.songs.search"))
        assertEquals(toolbarAtTop, bounds("fst.nav.floating-toolbar"))
        rule.onNode(hasTestTag("fst.songs.sort.open") and inToolbar).assertIsDisplayed()
        rule.onNode(hasTestTag("fst.songs.filter.open") and inToolbar).assertIsDisplayed()
        assertEquals(0, rule.onAllNodes(hasTestTag("fst.songs.filter.open") and inTopBar).fetchSemanticsNodes().size)

        // Typing filters the list; the page tools stay in the toolbar.
        rule.onNodeWithTag("fst.songs.search").performClick()
        rule.onNodeWithTag("fst.songs.search").assertIsFocused()
        rule.onNodeWithTag("fst.songs.search").performTextInput("Song 40")
        h.waitForTag("fst.songs.row.s-40")
        rule.onNode(hasTestTag("fst.songs.sort.open") and inToolbar).assertIsDisplayed()
        // The keyboard's Search key dismisses it and keeps the query.
        rule.onNodeWithTag("fst.songs.search").performImeAction()
        h.settle()
        rule.onNodeWithTag("fst.songs.search").assertIsNotFocused()
        rule.onNodeWithTag("fst.songs.row.s-40").assertIsDisplayed()
        // Clear empties the query.
        rule.onNodeWithContentDescription("Clear search").performClick()
        h.waitForTag("fst.songs.row.s-39")
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

/** Global search on a phone at font scale 2.0: the full-screen field grows instead of clipping. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
class LargeFontGlobalSearchUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun fullScreenFieldFitsTheScaledLine() {
        val h = SearchHarness(rule)
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        val field = rule.onNodeWithTag(GlobalSearchTags.FIELD).fetchSemanticsNode().boundsInRoot.height
        val needed = with(rule.density) { (24.sp.toPx() + 32.dp.toPx()) }
        assertTrue("font scale ${rule.density.fontScale}", rule.density.fontScale > 1.5f)
        assertTrue("field $field px < line + padding $needed px", field >= needed - 1f)
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
        // An icon action at every width (no persistent search field), in the top app bar, never
        // the floating toolbar that holds page tools at every width (#576).
        rule.onNodeWithTag(GlobalSearchTags.OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Search")))
        rule.onNode(hasTestTag(GlobalSearchTags.OPEN) and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).assertIsDisplayed()
        assertEquals(0, rule.onAllNodes(hasTestTag(GlobalSearchTags.OPEN) and hasAnyAncestor(hasTestTag("fst.nav.floating-toolbar"))).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        h.settle(800)
        val hintHeight = rule.onNodeWithTag(GlobalSearchTags.SURFACE).fetchSemanticsNode().boundsInRoot.height
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        h.waitForTag(GlobalSearchTags.RESULT_PLAYER)
        // The docked panel has one fixed height: it does not shrink or grow as the query settles.
        assertEquals(hintHeight, rule.onNodeWithTag(GlobalSearchTags.SURFACE).fetchSemanticsNode().boundsInRoot.height, 1f)
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.song-detail.intensity")
        assertTrue(h.bandSearches().isNotEmpty())
    }

    @Test
    fun songsListPaneKeepsOneSearchEntry() {
        val h = SearchHarness(rule)
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        assertEquals(1, rule.onAllNodesWithTag(GlobalSearchTags.OPEN).fetchSemanticsNodes().size)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(GlobalSearchResults.ENTER_QUERY_HINT_ALL))
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
        // Page tools float in the toolbar beside the rail too (#576); search stays in the top app bar.
        rule.onNode(hasTestTag("fst.songs.sort.open") and hasAnyAncestor(hasTestTag("fst.nav.floating-toolbar"))).assertIsDisplayed()
        rule.onNode(hasTestTag(GlobalSearchTags.OPEN) and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Search")))
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.CLOSE).performClick()
        h.waitForGone(GlobalSearchTags.SURFACE)
        assertTrue(h.bandSearches().isNotEmpty())
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun dockedEscapeClearsFirstAndBackClosesThePanel() {
        val h = SearchHarness(rule)
        h.launch()
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.FIELD)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        // The popup no longer swallows Escape: the field clears its text and the panel stays.
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performKeyInput { pressKey(Key.Escape) }
        h.waitForTag(GlobalSearchTags.HINT)
        rule.onNodeWithTag(GlobalSearchTags.SURFACE).assertIsDisplayed()
        // Back reaching the panel (keyboard already down) closes it.
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performKeyInput { pressKey(Key.Back) }
        h.waitForGone(GlobalSearchTags.SURFACE)
        rule.onNodeWithTag(GlobalSearchTags.OPEN).performClick()
        h.waitForTag(GlobalSearchTags.HINT)
    }
}
