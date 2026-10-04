package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.search.GlobalSearchTags
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #141: the Global Search control on a real device/emulator against synthetic fixtures
 * (`device.py test com.festivalscoretracker.android.journeys.GlobalSearchDeviceTest --avd
 * FST_Phone`, and `--avd FST_Book_Fold --posture half` / `--avd FST_Tablet` for the docked
 * panel). Accessibility Test Framework checks run on every interaction, each state logs its
 * TalkBack reading order, every target is at least 48 dp, nothing straddles a separating
 * hinge, the empty state stays above the keyboard and no band search or selected-profile
 * header is ever sent. `device.py test` runs with animator scale 0 (reduced motion).
 */
@RunWith(AndroidJUnit4::class)
class GlobalSearchDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    /** Touch bounds (including Material's minimum interactive padding) of every [tags] node are at least 48 dp. */
    private fun assertTargets(vararg tags: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        tags.forEach { tag ->
            val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot
            assertTrue("$tag touch target is ${bounds.width} x ${bounds.height} px", bounds.width >= min && bounds.height >= min)
        }
    }

    private fun before(order: List<String>, first: String, second: String) {
        val a = order.indexOfFirst { it.contains(first) }
        val b = order.indexOfFirst { it.contains(second) }
        assertTrue("'$first' before '$second' in $order", a >= 0 && b > a)
    }

    /** Every request was keyless, sent no selected-profile header and never hit band search. */
    private fun assertSafeRequests() {
        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
        assertTrue(transport.requests.none { "/api/bands/search" in it.url })
    }

    private fun open() {
        h.launch(DebugLaunch(stillBackground = true), transport)
        h.waitForTag("fst.songs.row.s-alpha")
        h.tap(GlobalSearchTags.OPEN)
        h.waitForTag(GlobalSearchTags.HINT)
    }

    @Test
    fun hintResultsScopesAndBandsAreAccessibleAndClearOfTheFold() {
        h.enableAccessibilityChecks()
        open()
        before(h.readingOrder("global-search-hint"), "Songs", "Enter at least two characters")
        assertTargets(GlobalSearchTags.CLOSE, *SearchScope.chips.map(GlobalSearchTags::scope).toTypedArray())
        h.assertNothingStraddles(GlobalSearchTags.SURFACE)

        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        val results = h.readingOrder("global-search-results")
        before(results, "Songs", "Alpha")
        assertTargets(GlobalSearchTags.CLEAR, GlobalSearchTags.RESULT_SONG)
        h.assertNothingStraddles(GlobalSearchTags.SURFACE, GlobalSearchTags.RESULT_SONG)

        h.tap(GlobalSearchTags.scope(SearchScope.Songs))
        rule.onNodeWithTag(GlobalSearchTags.scope(SearchScope.Songs)).assertIsSelected()
        h.awaitAccessibilityTree(GlobalSearchTags.RESULT_SONG, absent = GlobalSearchTags.RESULT_PLAYER)
        before(h.readingOrder("global-search-scoped"), "Songs, Selected", "Alpha")

        h.tap(GlobalSearchTags.scope(SearchScope.Bands))
        h.waitForTag(GlobalSearchTags.BANDS_UNAVAILABLE)
        h.awaitAccessibilityTree(GlobalSearchTags.BANDS_UNAVAILABLE, absent = GlobalSearchTags.RESULT_SONG)
        before(h.readingOrder("global-search-bands"), "Bands, Selected", "Band Rankings")
        assertTargets(GlobalSearchTags.BANDS_RANKINGS)

        assertSafeRequests()
        h.assertAccessible()
    }

    @Test
    fun emptyStateStaysWholeAboveTheKeyboard() {
        transport.on("/api/account/search") { """{"results":[]}""" }
        h.enableAccessibilityChecks()
        open()
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("zzzz")
        h.waitForTag(GlobalSearchTags.EMPTY)
        // Let the keyboard finish showing so its inset is final.
        Thread.sleep(1_500)
        rule.waitForIdle()
        h.awaitAccessibilityTree(GlobalSearchTags.EMPTY)
        before(h.readingOrder("global-search-empty"), GlobalSearchResults.EMPTY_ALL_TITLE, GlobalSearchResults.EMPTY_ALL_SUBTITLE)
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_SUBTITLE).assertIsDisplayed()

        // Issue #141: the docked panel counted the keyboard twice and pushed the empty state under it.
        val decor = rule.activity.window.decorView
        val imeBottom = ViewCompat.getRootWindowInsets(decor)?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        val location = IntArray(2).also(decor::getLocationOnScreen)
        val keyboardTop = location[1] + decor.height - imeBottom
        val subtitle = rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_SUBTITLE).fetchSemanticsNode()
        val surface = rule.onNodeWithTag(GlobalSearchTags.SURFACE).fetchSemanticsNode()
        val subtitleBottom = subtitle.positionOnScreen.y + subtitle.size.height
        assertTrue("Empty state ends at $subtitleBottom, keyboard starts at $keyboardTop", subtitleBottom <= keyboardTop + 1)
        assertTrue("Empty state ends at $subtitleBottom, panel at ${surface.positionOnScreen.y + surface.size.height}", subtitleBottom <= surface.positionOnScreen.y + surface.size.height + 1)
        assertSafeRequests()
        h.assertAccessible()
    }

    @Test
    fun playersFreezeKeepsSongsAndReadsTheStatus() {
        transport.onRaw("/api/account/search") {
            HttpResult(503, "{}".toByteArray(), mapOf("Retry-After" to "60", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
        }
        h.enableAccessibilityChecks()
        open()
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextInput("alpha")
        h.waitForTag("fst.global-search.players-error")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        before(h.readingOrder("global-search-error"), "Alpha", "Scores are updating")
        assertSafeRequests()
        h.assertAccessible()
    }

    @Test
    fun songResultNavigatesAndClosesTheSearch() {
        h.enableAccessibilityChecks()
        open()
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("beta")
        h.waitForTag(GlobalSearchTags.RESULT_SONG)
        h.tap(GlobalSearchTags.RESULT_SONG)
        h.waitGone(GlobalSearchTags.SURFACE)
        h.waitForTag("fst.song-detail.intensity")
        h.readingOrder("global-search-navigated")
        assertSafeRequests()
        h.assertAccessible()
    }
}
