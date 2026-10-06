package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Pinned page controls on a real device (issues #52, #160): Songs' Search, Quick Links, Sort and
 * Filter and Suggestions' Filter and global search keep their bounds while the primary list is
 * scrolled by touch, open while scrolled, and are where they were once the list is back at the
 * top. ATF runs on every interaction; TalkBack's reading order at the top, while scrolled and
 * back at the top goes to logcat `FST_A11Y`.
 *
 * The journey follows the window's placement of the page tools: the compact floating toolbar
 * (`FST_Phone`), the top app bar (`FST_Tablet`) or ⋮ on a narrow list pane (`FST_Book_Fold
 * --posture half`, `FST_Passport_Fold --posture unfolded`), whose menu must close after each tool's
 * sheet or menu closes. Run with
 * `device.py test com.festivalscoretracker.android.journeys.PinnedPageControlsDeviceTest --avd …`.
 */
@RunWith(AndroidJUnit4::class)
class PinnedPageControlsDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    // region Helpers

    /** Where the window put the page tools. */
    private enum class Placement { FloatingToolbar, TopBar, Overflow }

    private fun placement(tool: String): Placement = when {
        h.exists("fst.nav.overflow") && !h.exists(tool) -> Placement.Overflow
        within("fst.nav.floating-toolbar", tool) -> Placement.FloatingToolbar
        else -> Placement.TopBar
    }

    private fun within(ancestor: String, tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(ancestor))).fetchSemanticsNodes().isNotEmpty()

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    private fun assertSame(expected: Map<String, Rect>, phase: String) = expected.forEach { (tag, rect) ->
        val now = bounds(tag)
        listOf(rect.left to now.left, rect.top to now.top, rect.right to now.right, rect.bottom to now.bottom).forEach { (a, b) ->
            assertEquals("$tag $phase: $now vs $rect", a, b, 1f)
        }
    }

    /** Swipes [list] by touch: up (content scrolls down) or down. */
    private fun swipe(list: String, down: Boolean) {
        h.waitForTag(list)
        rule.onNodeWithTag(list).performTouchInput { if (down) swipeUp() else swipeDown() }
        rule.waitForIdle()
    }

    /** Swipes back up until [atTop] holds. */
    private fun scrollToTop(list: String, atTop: () -> Boolean) {
        repeat(20) {
            if (atTop()) return
            swipe(list, down = false)
        }
        assertTrue("$list never got back to the top", atTop())
    }

    /** Opens ⋮ when the page tools sit behind it, so [tool] can be activated. */
    private fun reveal(tool: String, placement: Placement) {
        if (placement != Placement.Overflow) return
        h.tap("fst.nav.overflow")
        h.waitForTag("fst.nav.overflow-menu")
        assertTrue("$tool in ⋮", within("fst.nav.overflow-menu", tool))
    }

    /** After a tool's sheet or menu closed, ⋮'s menu closes too (issue #160). */
    private fun overflowClosed(placement: Placement) {
        if (placement == Placement.Overflow) h.waitGone("fst.nav.overflow-menu")
    }

    /** Opens [tool] (through ⋮ when needed), reads the opened [surface], closes it with [close]. */
    private fun opens(tool: String, surface: String, close: String, placement: Placement, screen: String) {
        reveal(tool, placement)
        h.tap(tool)
        h.waitForTag(surface)
        h.readingOrder(screen)
        h.tap(close)
        h.waitGone(surface)
        overflowClosed(placement)
    }

    /** Opens Quick Links (sheet on compact widths, menu wider) and jumps to its last section. */
    private fun jumpsWithQuickLinks(placement: Placement) {
        reveal("fst.quick-links.open", placement)
        h.tap("fst.quick-links.open")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.sheet") || h.exists("fst.quick-links.menu") }
        val surface = if (h.exists("fst.quick-links.sheet")) "fst.quick-links.sheet" else "fst.quick-links.menu"
        h.readingOrder("pinned-songs-quick-links")
        val items = rule.onAllNodes(
            SemanticsMatcher("Quick Links item") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.quick-links.item.") == true },
            useUnmergedTree = true,
        ).fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }.distinct()
        assertTrue("Quick Links lists the Year sections: $items", items.size > 1)
        h.tap(items.last())
        h.waitGone(surface)
        overflowClosed(placement)
        assertTrue("the jump kept the list scrolled", !h.exists("fst.songs.row.s-1"))
    }

    /** Index of the first label containing [label]. */
    private fun List<String>.at(label: String) = indexOfFirst { it.contains(label) }

    /** Traversal index of [tag]'s node (0 when unset). */
    private fun traversalIndex(tag: String) =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.TraversalIndex) ?: 0f

    /**
     * `actionsReadFirst` (issues #112, #160): TalkBack reads top bar (−2) → floating toolbar (−1)
     * → [list] (0). This harness walk can split Compose's traversal chain, so the order is read
     * from the semantics TalkBack consumes; real TalkBack is walked with `talkback_walk.py`.
     */
    private fun assertToolbarReadBefore(list: String) {
        assertEquals(-2f, traversalIndex("fst.nav.top-bar"))
        assertEquals(-1f, traversalIndex("fst.nav.floating-toolbar"))
        assertEquals(0f, traversalIndex(list))
    }

    /** The reading order still reaches every control in [labels]. */
    private fun assertReads(order: List<String>, labels: List<String>, phase: String) =
        labels.forEach { assertTrue("$it is read $phase: $order", order.at(it) >= 0) }

    // endregion

    // region Songs

    @Test
    fun songsControlsStayPinnedOpenWhileScrolledAndRestoreAtTheTop() {
        h.enableAccessibilityChecks()
        val transport = SongsFixtures.scrollingCatalogueTransport().also { ProfileFixtures.register(it) }
        val prefs = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport, prefs)
        h.waitForTag("fst.songs.row.s-1")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.open") || h.exists("fst.nav.overflow") }
        val placement = placement("fst.songs.sort.open")
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        Log.i(JourneyHarness.READING_ORDER_TAG, "pinned-songs | placement $placement")
        if (compact) assertEquals("compact windows pin the tools in the floating toolbar", Placement.FloatingToolbar, placement)

        val tools = listOf("fst.songs.sort.open", "fst.songs.filter.open", "fst.quick-links.open")
        val anchors = when (placement) {
            // The list filter is pinned inline above the list at every width (issue #309).
            Placement.FloatingToolbar, Placement.TopBar -> tools + "fst.songs.search"
            Placement.Overflow -> listOf("fst.nav.overflow", "fst.songs.search")
        } + "fst.global-search.open"
        val labels = when (placement) {
            Placement.Overflow -> listOf("More actions")
            else -> listOf("Sort songs", "Filter songs", "Quick Links")
        } + "Search"
        val atTop = anchors.associateWith(::bounds)
        assertReads(h.readingOrder("pinned-songs-top"), labels, "at the top")

        repeat(3) { swipe("fst.songs.list", down = true) }
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        assertSame(atTop, "while scrolled")
        val scrolled = h.readingOrder("pinned-songs-scrolled")
        assertReads(scrolled, labels, "while scrolled")
        if (placement == Placement.FloatingToolbar) assertToolbarReadBefore("fst.songs.list")

        opens("fst.songs.sort.open", "fst.songs.sort.form", "fst.songs.sort.done", placement, "pinned-songs-sort")
        opens("fst.songs.filter.open", "fst.songs.filter.form", "fst.songs.filter.done", placement, "pinned-songs-filter")
        jumpsWithQuickLinks(placement)
        opens("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close", Placement.TopBar, "pinned-songs-global-search")
        assertSame(atTop, "after the tools")
        h.tap("fst.songs.search")
        rule.onNodeWithTag("fst.songs.search").assertIsFocused()
        Espresso.closeSoftKeyboard()
        rule.waitForIdle()

        scrollToTop("fst.songs.list") { h.exists("fst.songs.row.s-1") }
        rule.waitForIdle()
        assertSame(atTop, "back at the top")
        assertReads(h.readingOrder("pinned-songs-restored"), labels, "back at the top")
        h.assertAccessible()
    }

    // endregion

    // region Suggestions

    /** Tag and top edge of the topmost Suggestions card on screen. */
    private fun firstCard(): Pair<String, Int> = rule.onAllNodes(
        SemanticsMatcher("suggestion card") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true },
    ).fetchSemanticsNodes().minBy { it.boundsInRoot.top }.let { it.config[SemanticsProperties.TestTag] to it.boundsInRoot.top.toInt() }

    @Test
    fun suggestionsFilterAndGlobalSearchStayPinnedOpenWhileScrolledAndRestoreAtTheTop() {
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
        )
        h.waitForTag("fst.suggestions.list")
        rule.waitUntil(15_000) { h.exists("fst.suggestions.filter-button") || h.exists("fst.nav.overflow") }
        val placement = placement("fst.suggestions.filter-button")
        Log.i(JourneyHarness.READING_ORDER_TAG, "pinned-suggestions | placement $placement")
        if (rule.activity.resources.configuration.screenWidthDp < 600) assertEquals(Placement.FloatingToolbar, placement)
        val anchors = listOf(if (placement == Placement.Overflow) "fst.nav.overflow" else "fst.suggestions.filter-button", "fst.global-search.open")
        val labels = listOf(if (placement == Placement.Overflow) "More actions" else "Filter Suggestions", "Search")
        val atTop = anchors.associateWith(::bounds)
        rule.waitUntil(15_000) { runCatching { firstCard() }.isSuccess }
        val first = firstCard()
        assertReads(h.readingOrder("pinned-suggestions-top"), labels, "at the top")

        repeat(3) { swipe("fst.suggestions.list", down = true) }
        assertTrue("the first card scrolled away", firstCard() != first)
        assertSame(atTop, "while scrolled")
        assertReads(h.readingOrder("pinned-suggestions-scrolled"), labels, "while scrolled")
        if (placement == Placement.FloatingToolbar) assertToolbarReadBefore("fst.suggestions.list")
        opens("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done", placement, "pinned-suggestions-filter")
        opens("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close", Placement.TopBar, "pinned-suggestions-global-search")
        assertSame(atTop, "after the tools")

        scrollToTop("fst.suggestions.list") { firstCard() == first }
        assertSame(atTop, "back at the top")
        assertReads(h.readingOrder("pinned-suggestions-restored"), labels, "back at the top")
        h.assertAccessible()
    }

    // endregion
}
