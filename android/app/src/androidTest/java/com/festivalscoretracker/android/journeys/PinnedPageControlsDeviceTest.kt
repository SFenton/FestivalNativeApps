package com.festivalscoretracker.android.journeys

import android.content.pm.ActivityInfo
import android.content.res.Configuration
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
import androidx.compose.ui.test.performScrollToIndex
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
 * Pinned page controls on a real device (issues #52, #160, #418): Songs' Search, Quick Links,
 * Sort and Filter and Suggestions' Filter and global search keep their bounds while the primary
 * list is scrolled by touch, open while scrolled, and are where they were once the list is back
 * at the top. ATF runs on every interaction.
 *
 * TalkBack's linear order is asserted at the top, while scrolled and back at the top: the
 * harness walks the tree Compose publishes to TalkBack ([JourneyHarness.publishTalkBackTree],
 * with its traversal links and a fresh tree after each scroll) and every pinned control must be
 * read in the placement's order, each before any list item. While scrolled every pinned control
 * keeps its name, role and state (the inline filter is editable text labelled by its placeholder,
 * the tools are buttons; Sort and Filter speak their state, Suggestions' Filter "No filters" ⇄
 * "Filters on: Instruments" as the journey switches an instrument off and resets) and a separate
 * 48 dp target. The `…AtDoubleFontScale` variants repeat the journeys at 200 % text: the inline
 * filter grows without clipping its placeholder and every pinned control stays on screen.
 *
 * The page tools float in the shell's toolbar at every window size (issue #576): portrait and
 * landscape phones, `FST_Tablet` and `FST_Book_Fold --posture half`, where the toolbar stays on
 * screen inside the list pane. The `…InLandscape` variants turn the phone, so the `android-device`
 * CI job (`@DeviceCi`, one portrait phone emulator) covers both orientations. Reading orders go to logcat
 * `FST_A11Y`. Run with
 * `device.py test com.festivalscoretracker.android.journeys.PinnedPageControlsDeviceTest --avd …`.
 */
@DeviceCi
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

    /** Turns the phone to landscape before [JourneyHarness.launch] (ignored where the system ignores it). */
    private fun landscape(screen: String) {
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        val turned = runCatching {
            rule.waitUntil(10_000) { rule.activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE }
        }.isSuccess
        rule.waitForIdle()
        Log.i(JourneyHarness.READING_ORDER_TAG, "$screen | landscape $turned")
    }

    /** Swipes [list] by touch: up (content scrolls down) or down. */
    private fun swipe(list: String, down: Boolean) {
        h.waitForTag(list)
        rule.onNodeWithTag(list).performTouchInput { if (down) swipeUp() else swipeDown() }
        rule.waitForIdle()
    }

    /** Swipes back up until [atTop] holds; a viewport about one row high (landscape phone) then scrolls to the start. */
    private fun scrollToTop(list: String, atTop: () -> Boolean) {
        repeat(20) {
            if (atTop()) return
            swipe(list, down = false)
        }
        if (!atTop()) {
            Log.i(JourneyHarness.READING_ORDER_TAG, "$list | scrolling to the start after 20 swipes")
            rule.onNodeWithTag(list).performScrollToIndex(0)
            rule.waitForIdle()
        }
        assertTrue("$list never got back to the top", atTop())
    }

    /** Scroll offset [list] reports to accessibility services (0 at the top). */
    private fun scrollOffset(list: String): Float =
        rule.onNodeWithTag(list).fetchSemanticsNode().config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)?.value?.invoke() ?: 0f

    /** Opens ⋮ when the page tools sit behind it, so [tool] can be activated. */
    private fun reveal(tool: String, placement: Placement) {
        if (placement != Placement.Overflow) return
        h.tap("fst.nav.overflow")
        h.waitForTag("fst.nav.overflow-menu")
        assertTrue("$tool in ⋮", within("fst.nav.overflow-menu", tool))
    }

    /** Closes ⋮'s menu without choosing a tool. */
    private fun dismissOverflow(placement: Placement) {
        if (placement != Placement.Overflow) return
        Espresso.pressBack()
        h.waitGone("fst.nav.overflow-menu")
    }

    /** After a tool's sheet or menu closed, ⋮'s menu closes too (issue #160). */
    private fun overflowClosed(placement: Placement) {
        if (placement == Placement.Overflow) h.waitGone("fst.nav.overflow-menu")
    }

    /** Opens [tool] (through ⋮ when needed), reads the opened [surface], closes it with [close]. */
    private fun opens(tool: String, surface: String, close: String, placement: Placement, screen: String, inside: () -> Unit = {}) {
        reveal(tool, placement)
        h.tap(tool)
        h.waitForTag(surface)
        h.readingOrder(screen)
        inside()
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

    /** Traversal index of [tag]'s node (0 when unset). */
    private fun traversalIndex(tag: String) =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.TraversalIndex) ?: 0f

    /**
     * Supporting check for `actionsReadFirst` (issues #112, #160): the semantics behind the walk
     * put the top bar (−2) before the floating toolbar (−1) before [list] (0).
     */
    private fun assertToolbarReadBefore(list: String) {
        assertEquals(-2f, traversalIndex("fst.nav.top-bar"))
        assertEquals(-1f, traversalIndex("fst.nav.floating-toolbar"))
        assertEquals(0f, traversalIndex(list))
    }

    /** One stop TalkBack must reach, recognised by its spoken label. */
    private class Stop(val name: String, val matches: (String) -> Boolean)

    private val globalSearch = Stop("global search") { it == "Search" }
    private val profile = Stop("profile") { it.startsWith("Profile") }
    private val more = Stop("⋮") { it == "More actions" }
    private val quickLinks = Stop("Quick Links") { it.contains("Quick Links") }
    private val sortSongs = Stop("Sort songs") { it.startsWith("Sort songs") }
    private val filterSongs = Stop("Filter songs") { it.startsWith("Filter songs") }
    private val inlineFilter = Stop("inline filter") { it.startsWith(SONGS_SEARCH_PLACEHOLDER) }
    private val filterSuggestions = Stop("Filter Suggestions") { it.startsWith("Filter Suggestions") }

    /**
     * TalkBack reads [stops] in this order, and every list item ([isContent]) after the last one.
     *
     * @param order Labels from [JourneyHarness.readingOrder].
     * @param stops Controls in their expected order.
     * @param isContent Recognises a list item's label, or null when no list is in the window.
     * @param phase Phase for messages.
     */
    private fun assertReadInOrder(order: List<String>, stops: List<Stop>, isContent: ((String) -> Boolean)?, phase: String) {
        val at = stops.map { stop -> stop to order.indexOfFirst(stop.matches) }
        at.forEach { (stop, i) -> assertTrue("${stop.name} is read $phase: $order", i >= 0) }
        at.zipWithNext().forEach { (a, b) ->
            assertTrue("${a.first.name} (#${a.second}) is read before ${b.first.name} (#${b.second}) $phase: $order", a.second < b.second)
        }
        if (isContent == null) return
        val content = order.indices.filter { isContent(order[it]) }
        assertTrue("list items are read $phase: $order", content.isNotEmpty())
        assertTrue(
            "every list item is read after ${at.last().first.name} (#${at.last().second}) $phase, the first is #${content.first()}: $order",
            content.first() > at.last().second,
        )
    }

    /**
     * [tag] is one button whose spoken name includes [label] and, when [state] is set, whose
     * state is exactly [state] (or any state when [stateful]). Quick Links adds the sort and
     * current section: "Year Quick Links, current section 1980s".
     */
    private fun assertButton(tag: String, label: String, phase: String, stateful: Boolean = false, state: String? = null) {
        val config = rule.onNodeWithTag(tag).fetchSemanticsNode().config
        assertEquals("$tag is a button $phase", Role.Button, config.getOrNull(SemanticsProperties.Role))
        assertTrue("$tag is clickable $phase", SemanticsActions.OnClick in config)
        val name = config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString()
        assertTrue("$tag is named '$label' $phase, not '$name'", name.contains(label))
        val spoken = config.getOrNull(SemanticsProperties.StateDescription)
        if (stateful) assertTrue("$tag announces its state $phase", !spoken.isNullOrBlank())
        if (state != null) assertEquals("$tag announces its state $phase", state, spoken)
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

    /** Logs the font scale and width the journey runs at, for the `FST_A11Y` evidence. */
    private fun logScale(screen: String, scale: Float?) = Log.i(
        JourneyHarness.READING_ORDER_TAG,
        "$screen | font ${scale ?: rule.activity.resources.configuration.fontScale} | w${rule.activity.resources.configuration.screenWidthDp}dp",
    )

    /**
     * Placement checks every journey shares: every window floats the tools (issue #576), and the
     * toolbar lies wholly on screen.
     */
    private fun assertPlacement(placement: Placement, screen: String) {
        Log.i(JourneyHarness.READING_ORDER_TAG, "$screen | placement $placement")
        assertEquals("every window pins the tools in the floating toolbar", Placement.FloatingToolbar, placement)
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        val toolbar = bounds("fst.nav.floating-toolbar")
        assertTrue("toolbar $toolbar is on screen ($root)", toolbar.left >= root.left && toolbar.right <= root.right && toolbar.bottom <= root.bottom)
    }

    // endregion

    // region Songs

    @Test
    fun songsControlsStayPinnedOpenWhileScrolledAndRestoreAtTheTop() = songsJourney("pinned-songs", largeText = false)

    @Test
    fun songsControlsStayPinnedAndReachableAtDoubleFontScale() = songsJourney("pinned-songs-font-2", largeText = true)

    @Test
    fun songsControlsStayPinnedInLandscape() = songsJourney("pinned-songs-land", largeText = false, turn = true)

    @Test
    fun songsControlsStayPinnedInLandscapeAtDoubleFontScale() = songsJourney("pinned-songs-land-font-2", largeText = true, turn = true)

    /** A Songs row's spoken label ("A Song 01, Band 1 · 1981 · …"). */
    private val songRow: (String) -> Boolean = { Regex("""^\p{Lu} Song \d+,""").containsMatchIn(it) }

    /**
     * TalkBack's order for Songs' pinned controls: the shell's top-bar actions, then the floating
     * toolbar's tools (read first, issue #160); in the top app bar the bar's visual order (page
     * tools, then global search and profile); with ⋮, ⋮ in the tools' place. The inline filter
     * follows, then the list.
     */
    private fun songsStops(placement: Placement) = when (placement) {
        Placement.FloatingToolbar -> listOf(globalSearch, profile, quickLinks, sortSongs, filterSongs)
        Placement.TopBar -> listOf(quickLinks, sortSongs, filterSongs, globalSearch, profile)
        Placement.Overflow -> listOf(more, globalSearch, profile)
    } + inlineFilter

    /**
     * Songs (Year sort, 40 songs): records the pinned controls, scrolls, checks they kept their
     * bounds, names, roles, states, targets and reading order, opens each while scrolled, then
     * scrolls back.
     *
     * @param screen Prefix for the logged reading orders.
     * @param largeText Switch to 200 % text once loaded (the inline filter must grow, unclipped).
     * @param turn Run in landscape.
     */
    private fun songsJourney(screen: String, largeText: Boolean, turn: Boolean = false) {
        if (turn) landscape(screen)
        h.enableAccessibilityChecks()
        val transport = SongsFixtures.scrollingCatalogueTransport().also { ProfileFixtures.register(it) }
        val prefs = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        var scale by mutableFloatStateOf(1f)
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport, prefs, fontScale = if (largeText) ({ scale }) else null)
        h.waitForTag("fst.songs.row.s-1")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.open") || h.exists("fst.nav.overflow") }
        h.publishTalkBackTree()
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
        assertPlacement(placement, screen)

        val tools = listOf("fst.songs.sort.open", "fst.songs.filter.open", "fst.quick-links.open")
        val anchors = when (placement) {
            // The list filter is pinned inline above the list at every width (issue #309).
            Placement.FloatingToolbar, Placement.TopBar -> tools + "fst.songs.search"
            Placement.Overflow -> listOf("fst.nav.overflow", "fst.songs.search")
        } + "fst.global-search.open"
        val stops = songsStops(placement)
        val atTop = anchors.associateWith(::bounds)
        assertPinnedSongsControls(placement, anchors, "at the top", screen)
        assertReadInOrder(h.readingOrder("$screen-top"), stops, songRow, "at the top")

        repeat(3) { swipe("fst.songs.list", down = true) }
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        assertSame(atTop, "while scrolled")
        assertPinnedSongsControls(placement, anchors, "while scrolled", screen)
        if (largeText) assertFilterTextFits("at 200 % while scrolled")
        assertReadInOrder(h.readingOrder("$screen-scrolled"), stops, songRow, "while scrolled")
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
        assertReadInOrder(h.readingOrder("$screen-restored"), stops, songRow, "back at the top")
        h.assertAccessible()
    }

    /**
     * Songs' pinned controls: the inline filter is labelled editable text, each tool (or ⋮) and
     * global search a named button (Sort and Filter with their state), every [anchors] target is
     * at least 48 dp without overlapping its neighbour, and all of them are on screen. Behind ⋮,
     * the menu reads Quick Links, Sort and Filter in that order, each a named button.
     */
    private fun assertPinnedSongsControls(placement: Placement, anchors: List<String>, phase: String, screen: String) {
        assertSearchField(phase)
        if (placement == Placement.Overflow) {
            assertButton("fst.nav.overflow", "More actions", phase)
            reveal("fst.songs.sort.open", placement)
            assertSongsTools(phase)
            assertReadInOrder(h.readingOrder("$screen-overflow-menu"), listOf(quickLinks, sortSongs, filterSongs), null, "in ⋮ $phase")
            dismissOverflow(placement)
        } else {
            assertSongsTools(phase)
        }
        assertButton("fst.global-search.open", "Search", phase)
        probe.assertTargets(anchors)
        assertOnScreen(anchors, phase)
    }

    private fun assertSongsTools(phase: String) {
        assertButton("fst.songs.sort.open", "Sort songs", phase, stateful = true)
        assertButton("fst.songs.filter.open", "Filter songs", phase, stateful = true)
        assertButton("fst.quick-links.open", "Quick Links", phase)
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

    @Test
    fun suggestionsFilterAndGlobalSearchStayPinnedInLandscape() =
        suggestionsJourney("pinned-suggestions-land", largeText = false, turn = true)

    @Test
    fun suggestionsFilterAndGlobalSearchStayPinnedInLandscapeAtDoubleFontScale() =
        suggestionsJourney("pinned-suggestions-land-font-2", largeText = true, turn = true)

    /** A Suggestions song row's spoken label (fixture tracks are "Synthetic Track …"). */
    private val suggestionRow: (String) -> Boolean = { it.contains("Synthetic Track") }

    /** TalkBack's order for Suggestions' pinned controls (as [songsStops], Filter as the tool). */
    private fun suggestionsStops(placement: Placement) = when (placement) {
        Placement.FloatingToolbar -> listOf(globalSearch, profile, filterSuggestions)
        Placement.TopBar -> listOf(filterSuggestions, globalSearch, profile)
        Placement.Overflow -> listOf(more, globalSearch, profile)
    }

    /**
     * Suggestions (seed 7): records Filter (or ⋮) and global search, scrolls the feed, checks they
     * kept their bounds, names, roles, targets, reading order and Filter's "No filters" state.
     * While scrolled it switches an instrument off in the Filter sheet, then checks the
     * "Filters on: Instruments" state at the top and scrolled, resets it, opens global search
     * and scrolls back.
     *
     * @param screen Prefix for the logged reading orders.
     * @param largeText Render at 200 % text.
     * @param turn Run in landscape.
     */
    private fun suggestionsJourney(screen: String, largeText: Boolean, turn: Boolean = false) {
        if (turn) landscape(screen)
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
            fontScale = if (largeText) ({ 2f }) else null,
        )
        h.waitForTag("fst.suggestions.list")
        rule.waitUntil(15_000) { h.exists("fst.suggestions.filter-button") || h.exists("fst.nav.overflow") }
        h.publishTalkBackTree()
        logScale(screen, if (largeText) 2f else null)
        val placement = placement("fst.suggestions.filter-button")
        assertPlacement(placement, screen)
        val anchors = listOf(if (placement == Placement.Overflow) "fst.nav.overflow" else "fst.suggestions.filter-button", "fst.global-search.open")
        val stops = suggestionsStops(placement)
        val list = "fst.suggestions.list"
        val atTop = anchors.associateWith(::bounds)
        rule.waitUntil(15_000) { runCatching { firstCard() }.isSuccess }
        val first = firstCard()
        val inactive = "No filters"
        val active = "Filters on: Instruments"
        assertPinnedSuggestionsControls(placement, anchors, inactive, "at the top")
        assertSuggestionsOrder(h.readingOrder("$screen-top"), placement, stops, inactive, "at the top")

        repeat(3) { swipe(list, down = true) }
        assertTrue("the first card scrolled away", firstCard() != first)
        assertSame(atTop, "while scrolled")
        assertPinnedSuggestionsControls(placement, anchors, inactive, "while scrolled")
        assertSuggestionsOrder(h.readingOrder("$screen-scrolled"), placement, stops, inactive, "while scrolled")
        if (placement == Placement.FloatingToolbar) assertToolbarReadBefore(list)

        // Switch the first instrument off while scrolled: the filter applies live.
        opens("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done", placement, "$screen-filter") {
            val instrument = rule.onAllNodes(
                SemanticsMatcher("instrument switch") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.filter.instrument.") == true },
                useUnmergedTree = true,
            ).fetchSemanticsNodes().first().config[SemanticsProperties.TestTag]
            h.tap(instrument)
        }
        assertSame(atTop, "with a filter on")
        scrollToTop(list) { scrollOffset(list) == 0f }
        rule.waitUntil(15_000) { runCatching { firstCard() }.isSuccess }
        assertPinnedSuggestionsControls(placement, anchors, active, "at the top with a filter on")
        assertSuggestionsOrder(h.readingOrder("$screen-filtered-top"), placement, stops, active, "at the top with a filter on")
        repeat(3) { swipe(list, down = true) }
        assertTrue("the filtered feed scrolled", scrollOffset(list) > 0f)
        assertSame(atTop, "while scrolled with a filter on")
        assertPinnedSuggestionsControls(placement, anchors, active, "while scrolled with a filter on")
        assertSuggestionsOrder(h.readingOrder("$screen-filtered-scrolled"), placement, stops, active, "while scrolled with a filter on")

        opens("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done", placement, "$screen-filter-reset") {
            h.scrollTo("fst.suggestions.filter.form", "fst.suggestions.filter.reset")
            h.tap("fst.suggestions.filter.reset")
        }
        assertPinnedSuggestionsControls(placement, anchors, inactive, "after Reset")
        opens("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close", Placement.TopBar, "$screen-global-search")
        assertSame(atTop, "after the tools")

        scrollToTop(list) { scrollOffset(list) == 0f }
        assertSame(atTop, "back at the top")
        assertSuggestionsOrder(h.readingOrder("$screen-restored"), placement, stops, inactive, "back at the top")
        h.assertAccessible()
    }

    /** [stops] in order before the feed; where Filter is in the window, TalkBack reads its [state] with it. */
    private fun assertSuggestionsOrder(order: List<String>, placement: Placement, stops: List<Stop>, state: String, phase: String) {
        assertReadInOrder(order, stops, suggestionRow, phase)
        if (placement != Placement.Overflow) {
            assertTrue("Filter is read as 'Filter Suggestions, $state' $phase: $order", "Filter Suggestions, $state" in order)
        }
    }

    /**
     * Filter (or ⋮) and global search are named buttons with separate 48 dp targets, on screen,
     * and Filter (in ⋮'s menu when it is there) speaks [state].
     */
    private fun assertPinnedSuggestionsControls(placement: Placement, anchors: List<String>, state: String, phase: String) {
        if (placement == Placement.Overflow) {
            assertButton("fst.nav.overflow", "More actions", phase)
            reveal("fst.suggestions.filter-button", placement)
            assertButton("fst.suggestions.filter-button", "Filter Suggestions", phase, state = state)
            dismissOverflow(placement)
        } else {
            assertButton("fst.suggestions.filter-button", "Filter Suggestions", phase, state = state)
        }
        assertButton("fst.global-search.open", "Search", phase)
        probe.assertTargets(anchors)
        assertOnScreen(anchors, phase)
    }

    // endregion
}
