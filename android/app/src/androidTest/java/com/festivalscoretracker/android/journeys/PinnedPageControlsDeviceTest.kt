package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
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
import com.festivalscoretracker.android.testing.ShellHitTargets
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import com.festivalscoretracker.android.ui.songs.SONGS_SEARCH_PLACEHOLDER
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
 * back at the top goes to logcat `FST_A11Y`. While scrolled, every pinned control keeps its name,
 * role and state (the inline filter is editable text labelled by its placeholder, the tools are
 * buttons; Sort and Filter announce their state) and a separate 48 dp target (issue #418). The
 * `…AtDoubleFontScale` variants switch the same journeys to 200 % text: the inline filter grows
 * without clipping its placeholder and every pinned control stays on screen, pinned and usable.
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
    private val probe = ShellHitTargets(rule)
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
    private fun jumpsWithQuickLinks(placement: Placement, screen: String) {
        reveal("fst.quick-links.open", placement)
        h.tap("fst.quick-links.open")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.sheet") || h.exists("fst.quick-links.menu") }
        val surface = if (h.exists("fst.quick-links.sheet")) "fst.quick-links.sheet" else "fst.quick-links.menu"
        h.readingOrder(screen)
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

    /**
     * [tag] is one button whose spoken name includes [label] (and, when [stateful], announces a
     * state). Quick Links adds the sort and current section: "Year Quick Links, current section 1980s".
     *
     * @param tag Button test tag.
     * @param label Part of its spoken name.
     * @param stateful Whether it must carry a state description.
     * @param phase Phase for messages.
     */
    private fun assertButton(tag: String, label: String, phase: String, stateful: Boolean = false) {
        val config = rule.onNodeWithTag(tag).fetchSemanticsNode().config
        assertEquals("$tag is a button $phase", Role.Button, config.getOrNull(SemanticsProperties.Role))
        assertTrue("$tag is clickable $phase", SemanticsActions.OnClick in config)
        val name = config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString()
        assertTrue("$tag is named '$label' $phase, not '$name'", name.contains(label))
        if (stateful) assertTrue("$tag announces its state $phase", !config.getOrNull(SemanticsProperties.StateDescription).isNullOrBlank())
    }

    /** Songs' pinned inline filter is editable text TalkBack labels by its placeholder. */
    private fun assertSearchField(phase: String) {
        val config = rule.onNodeWithTag("fst.songs.search").fetchSemanticsNode().config
        assertTrue("the filter is editable text $phase", SemanticsProperties.EditableText in config)
        assertTrue("the filter accepts text $phase", SemanticsActions.SetText in config)
        assertTrue("the filter is labelled by its placeholder $phase", placeholderNodes().isNotEmpty())
    }

    private fun placeholderNodes() = rule.onAllNodes(
        hasText(SONGS_SEARCH_PLACEHOLDER) and hasAnyAncestor(hasTestTag("fst.songs.search")),
        useUnmergedTree = true,
    ).fetchSemanticsNodes()

    /** Every one of [tags] lies wholly inside the window's content, so it stays reachable. */
    private fun assertOnScreen(tags: List<String>, phase: String) {
        val window = rule.onRoot().fetchSemanticsNode().boundsInRoot
        tags.forEach { tag ->
            val box = bounds(tag)
            assertTrue(
                "$tag $box is on screen in $window $phase",
                box.left >= window.left - 1 && box.top >= window.top - 1 && box.right <= window.right + 1 && box.bottom <= window.bottom + 1,
            )
        }
    }

    /** Logs the font scale the journey runs at, for the `FST_A11Y` evidence. */
    private fun logScale(screen: String, scale: Float?) = Log.i(
        JourneyHarness.READING_ORDER_TAG,
        "$screen | font ${scale ?: rule.activity.resources.configuration.fontScale} | w${rule.activity.resources.configuration.screenWidthDp}dp",
    )

    // endregion

    // region Songs

    @Test
    fun songsControlsStayPinnedOpenWhileScrolledAndRestoreAtTheTop() = songsJourney("pinned-songs", largeText = false)

    @Test
    fun songsControlsStayPinnedAndReachableAtDoubleFontScale() = songsJourney("pinned-songs-font-2", largeText = true)

    /**
     * Songs (Year sort, 40 songs): records the pinned controls, scrolls, checks they kept their
     * bounds, names, roles, states and targets, opens each while scrolled, then scrolls back.
     *
     * @param screen Prefix for the logged reading orders.
     * @param largeText Switch to 200 % text once loaded (the inline filter must grow, unclipped).
     */
    private fun songsJourney(screen: String, largeText: Boolean) {
        h.enableAccessibilityChecks()
        val transport = SongsFixtures.scrollingCatalogueTransport().also { ProfileFixtures.register(it) }
        val prefs = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        var scale by mutableFloatStateOf(1f)
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport, prefs, fontScale = if (largeText) ({ scale }) else null)
        h.waitForTag("fst.songs.row.s-1")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.open") || h.exists("fst.nav.overflow") }
        if (largeText) {
            val field = bounds("fst.songs.search")
            scale = 2f
            rule.waitForIdle()
            val grew = runCatching { rule.waitUntil(5_000) { bounds("fst.songs.search").height > field.height } }.isSuccess
            assertTrue("the inline filter grows at 200 % text (${field.height} px at 100 %, ${bounds("fst.songs.search").height} px now)", grew)
            assertFilterTextFits("at 200 %")
        }
        logScale(screen, if (largeText) scale else null)
        val placement = placement("fst.songs.sort.open")
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        Log.i(JourneyHarness.READING_ORDER_TAG, "$screen | placement $placement")
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
        assertPinnedSongsControls(placement, anchors, "at the top")
        assertReads(h.readingOrder("$screen-top"), labels, "at the top")

        repeat(3) { swipe("fst.songs.list", down = true) }
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        assertSame(atTop, "while scrolled")
        assertPinnedSongsControls(placement, anchors, "while scrolled")
        if (largeText) assertFilterTextFits("at 200 % while scrolled")
        val scrolled = h.readingOrder("$screen-scrolled")
        assertReads(scrolled, labels, "while scrolled")
        if (placement == Placement.FloatingToolbar) assertToolbarReadBefore("fst.songs.list")

        opens("fst.songs.sort.open", "fst.songs.sort.form", "fst.songs.sort.done", placement, "$screen-sort")
        opens("fst.songs.filter.open", "fst.songs.filter.form", "fst.songs.filter.done", placement, "$screen-filter")
        jumpsWithQuickLinks(placement, "$screen-quick-links")
        opens("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close", Placement.TopBar, "$screen-global-search")
        assertSame(atTop, "after the tools")
        h.tap("fst.songs.search")
        rule.onNodeWithTag("fst.songs.search").assertIsFocused()
        Espresso.closeSoftKeyboard()
        rule.waitForIdle()

        scrollToTop("fst.songs.list") { h.exists("fst.songs.row.s-1") }
        rule.waitForIdle()
        assertSame(atTop, "back at the top")
        assertReads(h.readingOrder("$screen-restored"), labels, "back at the top")
        h.assertAccessible()
    }

    /**
     * Songs' pinned controls: the inline filter is labelled editable text, each tool (or ⋮) and
     * global search a named button (Sort and Filter with their state), every [anchors] target is
     * at least 48 dp without overlapping its neighbour, and all of them are on screen.
     */
    private fun assertPinnedSongsControls(placement: Placement, anchors: List<String>, phase: String) {
        assertSearchField(phase)
        if (placement == Placement.Overflow) {
            assertButton("fst.nav.overflow", "More actions", phase)
        } else {
            assertButton("fst.songs.sort.open", "Sort songs", phase, stateful = true)
            assertButton("fst.songs.filter.open", "Filter songs", phase, stateful = true)
            assertButton("fst.quick-links.open", "Quick Links", phase)
        }
        assertButton("fst.global-search.open", "Search", phase)
        probe.assertTargets(anchors)
        assertOnScreen(anchors, phase)
    }

    /** The inline filter's placeholder lies inside the field (it grew rather than clipping it). */
    private fun assertFilterTextFits(phase: String) {
        val field = bounds("fst.songs.search")
        val text = placeholderNodes().single().boundsInRoot
        assertTrue("placeholder $text fits vertically in the filter $field $phase", text.top >= field.top - 1 && text.bottom <= field.bottom + 1)
        assertTrue("placeholder $text starts inside the filter $field $phase", text.left >= field.left - 1 && text.left < field.right)
    }

    // endregion

    // region Suggestions

    /** Tag and top edge of the topmost Suggestions card on screen. */
    private fun firstCard(): Pair<String, Int> = rule.onAllNodes(
        SemanticsMatcher("suggestion card") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true },
    ).fetchSemanticsNodes().minBy { it.boundsInRoot.top }.let { it.config[SemanticsProperties.TestTag] to it.boundsInRoot.top.toInt() }

    @Test
    fun suggestionsFilterAndGlobalSearchStayPinnedOpenWhileScrolledAndRestoreAtTheTop() =
        suggestionsJourney("pinned-suggestions", largeText = false)

    @Test
    fun suggestionsFilterAndGlobalSearchStayPinnedAndReachableAtDoubleFontScale() =
        suggestionsJourney("pinned-suggestions-font-2", largeText = true)

    /**
     * Suggestions (seed 7): records Filter (or ⋮) and global search, scrolls the feed, checks they
     * kept their bounds, names, roles and targets, opens each while scrolled, then scrolls back.
     *
     * @param screen Prefix for the logged reading orders.
     * @param largeText Render at 200 % text.
     */
    private fun suggestionsJourney(screen: String, largeText: Boolean) {
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
            fontScale = if (largeText) ({ 2f }) else null,
        )
        h.waitForTag("fst.suggestions.list")
        rule.waitUntil(15_000) { h.exists("fst.suggestions.filter-button") || h.exists("fst.nav.overflow") }
        logScale(screen, if (largeText) 2f else null)
        val placement = placement("fst.suggestions.filter-button")
        Log.i(JourneyHarness.READING_ORDER_TAG, "$screen | placement $placement")
        if (rule.activity.resources.configuration.screenWidthDp < 600) assertEquals(Placement.FloatingToolbar, placement)
        val anchors = listOf(if (placement == Placement.Overflow) "fst.nav.overflow" else "fst.suggestions.filter-button", "fst.global-search.open")
        val labels = listOf(if (placement == Placement.Overflow) "More actions" else "Filter Suggestions", "Search")
        val atTop = anchors.associateWith(::bounds)
        rule.waitUntil(15_000) { runCatching { firstCard() }.isSuccess }
        val first = firstCard()
        assertPinnedSuggestionsControls(placement, anchors, "at the top")
        assertReads(h.readingOrder("$screen-top"), labels, "at the top")

        repeat(3) { swipe("fst.suggestions.list", down = true) }
        assertTrue("the first card scrolled away", firstCard() != first)
        assertSame(atTop, "while scrolled")
        assertPinnedSuggestionsControls(placement, anchors, "while scrolled")
        assertReads(h.readingOrder("$screen-scrolled"), labels, "while scrolled")
        if (placement == Placement.FloatingToolbar) assertToolbarReadBefore("fst.suggestions.list")
        opens("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done", placement, "$screen-filter")
        opens("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close", Placement.TopBar, "$screen-global-search")
        assertSame(atTop, "after the tools")

        scrollToTop("fst.suggestions.list") { firstCard() == first }
        assertSame(atTop, "back at the top")
        assertReads(h.readingOrder("$screen-restored"), labels, "back at the top")
        h.assertAccessible()
    }

    /** Filter (or ⋮) and global search are named buttons with separate 48 dp targets, on screen. */
    private fun assertPinnedSuggestionsControls(placement: Placement, anchors: List<String>, phase: String) {
        if (placement == Placement.Overflow) {
            assertButton("fst.nav.overflow", "More actions", phase)
        } else {
            assertButton("fst.suggestions.filter-button", "Filter Suggestions", phase)
        }
        assertButton("fst.global-search.open", "Search", phase)
        probe.assertTargets(anchors)
        assertOnScreen(anchors, phase)
    }

    // endregion
}
