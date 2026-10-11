package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #577 (`page-tools-and-nav-chrome` R7): on every page the shell's floating toolbar, and
 * the Quick Links button in it, stays on screen while the page scrolls by touch. Songs and
 * Suggestions are covered by [PinnedPageControlsDeviceTest]; this journey covers the other
 * pages the owner reported or that share the toolbar: Statistics (the selected player's
 * profile), Song Details, Leaderboards, Compete and Settings.
 *
 * On each page, at the top and after three touch swipes:
 * - the toolbar keeps its bounds, wholly on screen and above the bottom navigation bar;
 * - Quick Links is one `Button` named "Quick Links, current section …" with a 48 dp target, and
 *   TalkBack reads it (the tree TalkBack gets, [JourneyHarness.publishTalkBackTree]);
 * - scrolled to the end, the last content row ends above the toolbar (the band every page
 *   reserves for it is covered by it, never left empty or overlapped).
 *
 * Statistics also runs at 200 % text. ATF checks every interaction. Fixtures only; `@DeviceCi`
 * runs it in the `android-device` job. Run with `device.py test
 * com.festivalscoretracker.android.journeys.FloatingToolbarStaysOnScreenAccessibilityJourneyTest
 * --avd FST_Phone`; reading orders go to logcat `FST_A11Y`.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class FloatingToolbarStaysOnScreenAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    // region Tests

    @Test
    fun statisticsQuickLinksStayOnScreenWhileScrolled() = statistics(1f)

    @Test
    fun statisticsQuickLinksStayOnScreenWhileScrolledAtDoubleText() = statistics(2f)

    @Test
    fun songDetailToolsStayOnScreenWhileScrolled() = journey(
        screen = "song-detail",
        launch = DebugLaunch(profile = PLAYER, songQuery = "s-alpha", stillBackground = true),
        transport = FakeTransport.standard().apply(songs),
        list = "fst.song-detail.list",
    )

    @Test
    fun leaderboardsQuickLinksStayOnScreenWhileScrolled() = journey(
        screen = "leaderboards",
        launch = DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
        transport = RankingsFixtures.install(FakeTransport.standard().apply(songs)),
        list = "fst.leaderboards",
    )

    @Test
    fun competeQuickLinksStayOnScreenWhileScrolled() = journey(
        screen = "compete",
        launch = DebugLaunch(route = DebugLaunch.parseRoute("compete"), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true),
        transport = RivalsFixtures.transport().apply(songs).also { RankingsFixtures.install(it) },
        list = "fst.compete.grid",
    )

    @Test
    fun settingsQuickLinksStayOnScreenWhileScrolled() = journey(
        screen = "settings",
        launch = DebugLaunch(section = FestivalSection.Settings, stillBackground = true),
        transport = FakeTransport.standard(),
        list = "fst.settings.list",
    )

    private fun statistics(scale: Float) = journey(
        screen = "statistics",
        launch = DebugLaunch(section = FestivalSection.Statistics, profile = PLAYER, stillBackground = true),
        transport = FakeTransport.standard().apply(songs).also { ProfileFixtures.register(it) },
        list = "fst.player.available",
        scale = scale,
    )

    // endregion

    // region Journey

    /**
     * Launch [launch], then check the toolbar at the top, while scrolled and at the end of [list].
     *
     * @param screen Prefix for logged reading orders and messages.
     * @param launch Page to open.
     * @param transport Fixture transport.
     * @param list The page's scrolling container.
     * @param scale Font scale.
     */
    private fun journey(screen: String, launch: DebugLaunch, transport: FakeTransport, list: String, scale: Float = 1f) {
        val config = "$screen ${scale}x"
        h.enableAccessibilityChecks()
        h.launch(launch, transport, fontScale = { scale })
        h.waitForTag(list)
        h.waitForTag(QUICK_LINKS)
        h.publishTalkBackTree()
        rule.waitForIdle()

        val atTop = bounds(TOOLBAR)
        assertToolbar(config, "at the top", atTop)
        assertQuickLinks(config, "at the top")

        repeat(3) { swipe(list) }
        val offset = scrollOffset(list)
        Log.i(JourneyHarness.READING_ORDER_TAG, "$config | scrolled to $offset px")
        assertTrue("$config: the page did not scroll", offset > 0f)
        assertSameRect("$config: the toolbar moved while the page scrolled", atTop, bounds(TOOLBAR))
        assertToolbar(config, "while scrolled", bounds(TOOLBAR))
        assertQuickLinks(config, "while scrolled")

        scrollToEnd(list)
        assertSameRect("$config: the toolbar moved at the end of the page", atTop, bounds(TOOLBAR))
        assertLastRowClearsToolbar(config, list)
        h.assertAccessible()
    }

    // endregion

    // region Assertions

    /** The toolbar lies wholly on screen and, on compact windows, above the bottom bar. */
    private fun assertToolbar(config: String, phase: String, toolbar: Rect) {
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("$config: toolbar $toolbar has no size $phase", toolbar.width > 0f && toolbar.height > 0f)
        assertTrue(
            "$config: toolbar $toolbar is off screen ($root) $phase",
            toolbar.left >= root.left - 1 && toolbar.right <= root.right + 1 && toolbar.top >= root.top - 1 && toolbar.bottom <= root.bottom + 1,
        )
        if (h.exists(BOTTOM_BAR)) {
            val bar = bounds(BOTTOM_BAR)
            assertTrue("$config: toolbar $toolbar overlaps the bottom bar $bar $phase", toolbar.bottom <= bar.top + 1)
        }
    }

    /** Quick Links is a named 48 dp button that TalkBack reads. */
    private fun assertQuickLinks(config: String, phase: String) {
        val node = rule.onNodeWithTag(QUICK_LINKS).fetchSemanticsNode()
        assertEquals("$config: Quick Links is a button $phase", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
        assertTrue("$config: Quick Links is clickable $phase", SemanticsActions.OnClick in node.config)
        val name = node.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString(" ")
        assertTrue("$config: Quick Links is named '$name' $phase", name.contains(QUICK_LINKS_LABEL))
        h.assertTouchTarget("$config $phase", QUICK_LINKS)
        val order = h.readingOrder("toolbar-$config-$phase".replace(' ', '-'), fresh = true)
        assertTrue("$config: TalkBack does not read Quick Links $phase: $order", order.any { it.contains(QUICK_LINKS_LABEL) })
    }

    /** Scrolled to the end, no row of [list] reaches under the toolbar. */
    private fun assertLastRowClearsToolbar(config: String, list: String) {
        val toolbar = bounds(TOOLBAR)
        val viewport = bounds(list)
        val lowest = rule.onAllNodes(hasAnyAncestor(hasTestTag(list)), useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.boundsInRoot }
            .filter { it.height > 0f && it.bottom <= viewport.bottom + 1 }
            .maxOfOrNull { it.bottom }
        Log.i(JourneyHarness.READING_ORDER_TAG, "$config | end: lowest row $lowest | toolbar $toolbar")
        assertTrue("$config: no row of $list is on screen at the end", lowest != null)
        assertTrue("$config: the last row ends at $lowest px, under the toolbar's top ${toolbar.top} px", lowest!! <= toolbar.top + 1)
    }

    // endregion

    // region Helpers

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    /** Asserts [now] matches [expected] within a pixel. */
    private fun assertSameRect(message: String, expected: Rect, now: Rect) =
        listOf(expected.left to now.left, expected.top to now.top, expected.right to now.right, expected.bottom to now.bottom).forEach { (a, b) ->
            assertEquals("$message: $now vs $expected", a, b, 1f)
        }

    /**
     * Swipes [list] up by touch (its content scrolls toward the end), in the middle third so
     * the gesture starts on content rather than on the toolbar floating over its bottom.
     */
    private fun swipe(list: String) {
        rule.onNodeWithTag(list).performTouchInput { swipeUp(startY = centerY + height / 6f, endY = centerY - height / 6f) }
        rule.waitForIdle()
    }

    /** Swipes until [list] stops scrolling. */
    private fun scrollToEnd(list: String) {
        var last = -1f
        repeat(MAX_SWIPES) {
            val now = scrollOffset(list)
            if (now == last) return
            last = now
            swipe(list)
        }
    }

    /** Scroll offset [list] reports to accessibility services (0 at the top). */
    private fun scrollOffset(list: String): Float =
        rule.onNodeWithTag(list).fetchSemanticsNode().config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)?.value?.invoke() ?: 0f

    // endregion

    private companion object {
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        const val TOOLBAR = "fst.nav.floating-toolbar"
        const val BOTTOM_BAR = "fst.nav.bar"
        const val QUICK_LINKS = "fst.quick-links.open"
        const val QUICK_LINKS_LABEL = "Quick Links"
        const val MAX_SWIPES = 40
    }
}
