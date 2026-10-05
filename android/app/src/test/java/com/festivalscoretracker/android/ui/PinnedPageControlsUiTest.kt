package com.festivalscoretracker.android.ui

import android.os.Looper
import android.view.accessibility.AccessibilityManager
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
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
import org.robolectric.annotation.GraphicsMode

// region Harness

/**
 * Whole-shell launcher for the issue #52/#160 pinning checks: Songs' Sort, Filter, Search and
 * Quick Links and Suggestions' Filter keep their place and still open while the list is scrolled,
 * and come back to the same place at the top.
 */
private class PinnedHarness(val rule: AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>) {
    /** Forty songs over forty years, so the Year sort has several Quick Links sections and the list scrolls. */
    val transport = SongsFixtures.scrollingCatalogueTransport()

    fun launchSongs(reduceMotion: Boolean = false, player: SelectedPlayer? = null) {
        val prefs = mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year")
        if (reduceMotion) prefs[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true
        if (player != null) ProfileFixtures.register(transport)
        launch(DebugLaunch(profile = player, stillBackground = true), transport, InMemoryPreferences(prefs))
        waitForTag("fst.songs.row.s-1")
        waitOrExplain("Quick Links or ⋮") { exists("fst.quick-links.open") || exists("fst.nav.overflow") }
    }

    fun launchSuggestions() {
        val debug = DebugLaunch(
            section = FestivalSection.Suggestions,
            profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
            stillBackground = true,
            suggestionsSeed = 7,
        )
        launch(debug, SuggestionFixtures.transport(), InMemoryPreferences())
        waitForTag("fst.suggestions.list")
        waitForTag("fst.suggestions.filter-button")
    }

    private fun launch(debug: DebugLaunch, transport: FakeTransport, prefs: InMemoryPreferences) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    fun waitForTag(tag: String) = waitOrExplain("$tag to appear") { exists(tag) }

    fun waitGone(tag: String) = waitOrExplain("$tag to close") { !exists(tag) }

    /** Waits for [condition], naming the `fst.` tags on screen when it times out. */
    private fun waitOrExplain(what: String, condition: () -> Boolean) {
        try {
            rule.waitUntil(20_000) { settle(100); condition() }
        } catch (timeout: ComposeTimeoutException) {
            val present = rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.TestTag), useUnmergedTree = true)
                .fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }
                .filter { it.startsWith("fst.") }.distinct().take(60)
            throw AssertionError("Timed out waiting for $what; present: $present", timeout)
        }
    }

    fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    fun scroll(list: String, down: Boolean, times: Int = 3) = repeat(times) {
        waitForTag(list)
        rule.onNodeWithTag(list).performTouchInput { if (down) swipeUp() else swipeDown() }
        settle()
    }

    /** Swipes [list] back up until [tag] is composed again (short windows need more swipes). */
    fun scrollBackTo(list: String, tag: String) {
        repeat(30) {
            if (exists(tag)) return
            scroll(list, down = false, times = 1)
        }
        waitForTag(tag)
    }

    /** Opens [button], waits for [sheet], then closes it with [close] and waits for it to go. */
    fun opensWhileScrolled(button: String, sheet: String, close: String) {
        click(button)
        waitForTag(sheet)
        click(close)
        waitGone(sheet)
    }

    /**
     * Opens Quick Links' medium/expanded menu while scrolled and jumps to its last section, which
     * keeps the list scrolled; the menu closes on the jump.
     */
    fun jumpsWithQuickLinksMenu(focusTop: () -> Unit = {}) {
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.menu")
        focusTop()
        val last = rule.onAllNodes(
            SemanticsMatcher("Quick Links item") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.quick-links.item.") == true },
        ).fetchSemanticsNodes().maxBy { it.boundsInRoot.top }.config[SemanticsProperties.TestTag]
        click(last)
        waitGone("fst.quick-links.menu")
        focusTop()
        assertTrue("the jump kept the list scrolled", !exists("fst.songs.row.s-1"))
    }

    /** Opens ⋮, then [button] inside its menu, waits for [sheet], closes it with [close]; the menu closes too (window focus is moved as on a device). */
    fun opensFromOverflowWhileScrolled(button: String, sheet: String, close: String, focusTop: () -> Unit) {
        click("fst.nav.overflow")
        waitForTag("fst.nav.overflow-menu")
        focusTop()
        assertTrue("$button in ⋮", within("fst.nav.overflow-menu", button))
        click(button)
        waitForTag(sheet)
        focusTop()
        click(close)
        waitGone(sheet)
        focusTop()
        waitGone("fst.nav.overflow-menu")
    }

    /** Tag and top edge of the topmost Suggestions card on screen. */
    fun firstCard(): Pair<String, Int> = rule.onAllNodes(
        SemanticsMatcher("suggestion card") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true },
    ).fetchSemanticsNodes().minBy { it.boundsInRoot.top }.let { it.config[SemanticsProperties.TestTag] to it.boundsInRoot.top.toInt() }

    fun within(ancestor: String, tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(ancestor))).fetchSemanticsNodes().isNotEmpty()

    fun assertSame(expected: Map<String, Rect>, phase: String) = expected.forEach { (tag, rect) ->
        val now = bounds(tag)
        listOf(rect.left to now.left, rect.top to now.top, rect.right to now.right, rect.bottom to now.bottom).forEach { (a, b) ->
            assertEquals("$tag $phase: $now vs $rect", a, b, 0.5f)
        }
    }
}

private const val SONG_TOOLS = "fst.songs.sort.open|fst.songs.filter.open|fst.quick-links.open"

// endregion

// region Phone

/** Phone: the bottom floating toolbar stays put while Songs and Suggestions scroll (issues #52, #84, #160). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PhonePinnedPageControlsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    @Test
    fun songsToolsKeepTheirBoundsOpenWhileScrolledAndRestoreAtTheTop() {
        h.launchSongs()
        val tools = SONG_TOOLS.split('|')
        tools.forEach { assertTrue("$it in the toolbar", h.within("fst.nav.floating-toolbar", it)) }
        val atTop = tools.associateWith(h::bounds)
        val toolbarAtTop = h.bounds("fst.nav.floating-toolbar")
        val searchAtTop = h.bounds("fst.songs.search.open")

        h.scroll("fst.songs.list", down = true)
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        h.assertSame(atTop, "while scrolled")
        assertEquals(toolbarAtTop.bottom, h.bounds("fst.nav.floating-toolbar").bottom, 0.5f)
        assertTrue("search minimized", h.bounds("fst.songs.search.open").width < searchAtTop.width)
        h.opensWhileScrolled("fst.songs.sort.open", "fst.songs.sort.form", "fst.songs.sort.done")
        h.opensWhileScrolled("fst.songs.filter.open", "fst.songs.filter.form", "fst.songs.filter.done")
        h.opensWhileScrolled("fst.quick-links.open", "fst.quick-links.sheet", "fst.quick-links.close")
        h.assertSame(atTop, "after the sheets")

        h.scroll("fst.songs.list", down = false, times = 6)
        h.waitForTag("fst.songs.row.s-1")
        h.assertSame(atTop + mapOf("fst.nav.floating-toolbar" to toolbarAtTop, "fst.songs.search.open" to searchAtTop), "back at the top")
    }

    @Test
    fun suggestionsFilterAndSearchKeepTheirBoundsAndOpenWhileScrolled() {
        h.launchSuggestions()
        val tags = listOf("fst.suggestions.filter-button", "fst.global-search.open")
        val atTop = tags.associateWith(h::bounds)
        val firstCard = h.firstCard()

        h.scroll("fst.suggestions.list", down = true)
        assertTrue("the first card scrolled away", h.firstCard() != firstCard)
        h.assertSame(atTop, "while scrolled")
        h.opensWhileScrolled("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done")
        h.opensWhileScrolled("fst.global-search.open", "fst.global-search.surface", "fst.global-search.close")

        h.scroll("fst.suggestions.list", down = false, times = 8)
        h.assertSame(atTop, "back at the top")
        assertEquals(firstCard, h.firstCard())
    }
}

/**
 * Phone with reduced motion (the app's Reduce motion setting, which also follows the system
 * animator scale 0): the search pill swaps between field and icon in one frame instead of
 * animating its width (issue #160).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ReducedMotionPinnedToolbarUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    /** Distinct toolbar widths drawn frame by frame after a drag past the minimize threshold. */
    private fun widthsDuringMinimize(): Set<Int> {
        val widths = linkedSetOf(h.bounds("fst.nav.floating-toolbar").width.toInt())
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.songs.list").performTouchInput {
            down(center)
            moveBy(Offset(0f, -300f))
            up()
        }
        repeat(40) {
            rule.mainClock.advanceTimeByFrame()
            shadowOf(Looper.getMainLooper()).idle()
            widths += h.bounds("fst.nav.floating-toolbar").width.toInt()
        }
        rule.mainClock.autoAdvance = true
        return widths
    }

    @Test
    fun reducedMotionSwapsTheSearchPillWithoutIntermediateWidths() {
        h.launchSongs(reduceMotion = true)
        val widths = widthsDuringMinimize()
        assertEquals("expanded then minimized, nothing between: $widths", 2, widths.size)
    }

    @Test
    fun standardMotionAnimatesTheSearchPillWidth() {
        h.launchSongs()
        val widths = widthsDuringMinimize()
        assertTrue("animated through intermediate widths: $widths", widths.size > 2)
    }
}

/** Phone with TalkBack on: the toolbar never hides and search never minimizes while scrolled (issue #160). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ScreenReaderPinnedToolbarUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    @Test
    fun searchStaysAFullFieldWhileScrolledUnderTalkBack() {
        shadowOf(rule.activity.getSystemService(AccessibilityManager::class.java)).setTouchExplorationEnabled(true)
        h.launchSongs()
        val atTop = (SONG_TOOLS.split('|') + listOf("fst.songs.search.open", "fst.nav.floating-toolbar")).associateWith(h::bounds)
        h.scroll("fst.songs.list", down = true)
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        h.assertSame(atTop, "while scrolled with TalkBack")
    }

    /** Traversal index of [tag]'s node (0 when unset). */
    private fun traversalIndex(tag: String) =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.TraversalIndex) ?: 0f

    @Test
    fun songsToolbarIsReadAfterTheTopBarAndBeforeTheRows() {
        // Issue #160: read after ~700 rows (the shell default), TalkBack swipes never reached
        // Search, Quick Links, Sort or Filter. Top bar (-2) → toolbar (-1) → rows (0).
        shadowOf(rule.activity.getSystemService(AccessibilityManager::class.java)).setTouchExplorationEnabled(true)
        h.launchSongs()
        assertEquals(-2f, traversalIndex("fst.nav.top-bar"))
        assertEquals(-1f, traversalIndex("fst.nav.floating-toolbar"))
        (SONG_TOOLS.split('|') + "fst.songs.search.open").forEach { assertTrue("$it in the toolbar", h.within("fst.nav.floating-toolbar", it)) }
        assertEquals(0f, traversalIndex("fst.songs.list"))
    }
}

// endregion

// region Medium and expanded

/** Medium window (rail): Songs' pinned search field and top-bar tools stay put while scrolled (issue #160). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w700dp-h1000dp-xhdpi")
class MediumPinnedPageControlsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    @Test
    fun songsSearchFieldAndTopBarToolsStayPinned() = songsStayPinned(h)

    @Test
    fun suggestionsFilterStaysInTheTopBar() = suggestionsStayPinned(h)
}

/** Expanded window (list-detail): the same pinning in the Songs list pane and on Suggestions (issue #160). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedPinnedPageControlsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    @Test
    fun songsSearchFieldAndTopBarToolsStayPinned() = songsStayPinned(h)

    @Test
    fun suggestionsFilterStaysInTheTopBar() = suggestionsStayPinned(h)
}

/**
 * Narrow list pane (phone landscape, list-detail): the page tools sit behind ⋮ (issue #101). ⋮,
 * the pinned search field and global search stay put while scrolled; Sort, Filter and Quick Links
 * open from ⋮ while scrolled and ⋮'s menu closes after each (issue #160). Native graphics, so the
 * title measures real text and the tools really overflow.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w923dp-h411dp-land-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class OverflowPinnedPageControlsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { PinnedHarness(rule) }

    @Test
    fun songsOverflowSearchAndGlobalSearchStayPinnedAndToolsOpenFromOverflow() {
        h.launchSongs(player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val present = listOf("fst.nav.overflow", "fst.songs.sort.open", "fst.quick-links.open", "fst.nav.floating-toolbar").filter(h::exists)
        assertTrue("page tools behind ⋮: present $present, top bar ${h.bounds("fst.nav.top-bar")}", h.exists("fst.nav.overflow") && !h.exists("fst.songs.sort.open"))
        val atTop = listOf("fst.nav.overflow", "fst.songs.search", "fst.global-search.open").associateWith(h::bounds)
        h.scroll("fst.songs.list", down = true)
        assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
        h.assertSame(atTop, "while scrolled")
        val focus = { rule.focusTopWindow() }
        h.opensFromOverflowWhileScrolled("fst.songs.sort.open", "fst.songs.sort.form", "fst.songs.sort.done", focus)
        h.opensFromOverflowWhileScrolled("fst.songs.filter.open", "fst.songs.filter.form", "fst.songs.filter.done", focus)
        h.click("fst.nav.overflow")
        h.waitForTag("fst.nav.overflow-menu")
        focus()
        h.jumpsWithQuickLinksMenu(focus)
        h.waitGone("fst.nav.overflow-menu")
        h.assertSame(atTop, "after the tools")
        h.scrollBackTo("fst.songs.list", "fst.songs.row.s-1")
        h.assertSame(atTop, "back at the top")
    }
}

private fun songsStayPinned(h: PinnedHarness) {
    h.launchSongs()
    assertTrue("no floating toolbar on wider windows", !h.exists("fst.nav.floating-toolbar"))
    val tools = SONG_TOOLS.split('|')
    tools.forEach { assertTrue("$it in the top app bar", h.within("fst.nav.top-bar", it)) }
    val atTop = (tools + "fst.songs.search").associateWith(h::bounds)
    h.scroll("fst.songs.list", down = true)
    assertTrue("scrolled away from the first row", !h.exists("fst.songs.row.s-1"))
    h.assertSame(atTop, "while scrolled")
    h.opensWhileScrolled("fst.songs.sort.open", "fst.songs.sort.form", "fst.songs.sort.done")
    h.opensWhileScrolled("fst.songs.filter.open", "fst.songs.filter.form", "fst.songs.filter.done")
    h.jumpsWithQuickLinksMenu()
    h.assertSame(atTop, "after Quick Links")
    h.scrollBackTo("fst.songs.list", "fst.songs.row.s-1")
    h.assertSame(atTop, "back at the top")
}

private fun suggestionsStayPinned(h: PinnedHarness) {
    h.launchSuggestions()
    assertTrue("Filter in the top app bar", h.within("fst.nav.top-bar", "fst.suggestions.filter-button"))
    val atTop = listOf("fst.suggestions.filter-button", "fst.global-search.open").associateWith(h::bounds)
    val firstCard = h.firstCard()
    h.scroll("fst.suggestions.list", down = true)
    assertTrue("the first card scrolled away", h.firstCard() != firstCard)
    h.assertSame(atTop, "while scrolled")
    h.opensWhileScrolled("fst.suggestions.filter-button", "fst.suggestions.filter.form", "fst.suggestions.filter.done")
    h.scroll("fst.suggestions.list", down = false, times = 8)
    h.assertSame(atTop, "back at the top")
    assertEquals(firstCard, h.firstCard())
}

// endregion
