package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.shell.BottomChromeSpacing
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #578 (`page-tools-and-nav-chrome` R7, `leaderboard-row` R5): pages end one standard
 * 16 dp gap above the bottom chrome actually shown, never above a band kept for an absent
 * floating toolbar or pinned row.
 *
 * - The song leaderboard without a profile or band has no page tools and no pinned row: its
 *   pager rests 16 dp above the bottom navigation bar, its rows end above the pager, and the
 *   pager buttons stay 48 dp targets that TalkBack reads after the rows.
 * - Full Rankings (pinned row and toolbar): the pager rests 16 dp above the toolbar.
 * - Leaderboards, Rival Detail and Rivalry (toolbar) end 16 dp above the toolbar; All Rivals (no
 *   tools) ends 16 dp above the bottom bar. Scrolled to the end, the last row clears the chrome.
 *
 * Each runs at 100 % and 200 % text; ATF checks every interaction. Fixtures only; `@DeviceCi`
 * runs it in the `android-device` job. Run with `device.py test
 * com.festivalscoretracker.android.journeys.BottomChromeSpacingAccessibilityJourneyTest --avd
 * FST_Phone`; measured gaps go to logcat `FST_A11Y`.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class BottomChromeSpacingAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    // region Boards

    @Test
    fun songLeaderboardPagerRestsOneGapAboveTheBottomBarWithoutAProfile() = songBoard(1f)

    @Test
    fun songLeaderboardPagerRestsOneGapAboveTheBottomBarWithoutAProfileAtDoubleText() = songBoard(2f)

    @Test
    fun fullRankingsPagerRestsOneGapAboveTheToolbar() = fullRankings(1f)

    @Test
    fun fullRankingsPagerRestsOneGapAboveTheToolbarAtDoubleText() = fullRankings(2f)

    /**
     * The song board with no selected profile: no toolbar, no pinned row, the pager one gap above
     * the bottom bar and the rows ending above it.
     */
    private fun songBoard(scale: Float) {
        val config = "song-leaderboard-no-profile ${scale}x"
        val prefix = "fst.song-leaderboard"
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("songLeaderboard:s-alpha:Solo_Guitar"), stillBackground = true),
            RankingsFixtures.install(FakeTransport.standard().apply(songs)),
            fontScale = { scale },
        )
        h.waitForTag("$prefix.page-next")
        h.awaitAccessibilityTree("$prefix.page-next")
        h.publishTalkBackTree()
        rule.waitForIdle()

        assertTrue("$config: a pinned row shows without a profile", !h.exists("$prefix.spotlight-footer"))
        assertTrue("$config: the toolbar shows without page tools", !toolbarShown())
        assertGap(config, "pager", bounds("$prefix.pager").bottom, chromeTop())
        listOf("first", "previous", "next", "last").map { "$prefix.page-$it" }.filter(h::exists).forEach { h.assertTouchTarget(config, it) }
        val order = h.readingOrder("bottom-chrome-$config".replace(' ', '-'), fresh = true)
        val pager = order.indexOfFirst { Regex("Page.1.of").containsMatchIn(it) }
        // A row reads as one stop ("#1, Synthetic Player 1, …").
        val row = order.indexOfFirst { it.contains("Synthetic Player") }
        assertTrue("$config: TalkBack misses the pager or rows: $order", pager >= 0 && row >= 0)
        assertTrue("$config: the pager is read before the rows: $order", row < pager)

        scrollToEnd("$prefix.list")
        assertLastRowClears(config, "$prefix.list", bounds("$prefix.bottom-bar").top)
        assertGap(config, "pager after scrolling", bounds("$prefix.pager").bottom, chromeTop())
        h.assertAccessible()
    }

    /** Full Rankings: pinned row and pager one gap above the floating toolbar. */
    private fun fullRankings(scale: Float) {
        val config = "full-rankings ${scale}x"
        val prefix = "fst.full-rankings"
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
            RankingsFixtures.install(FakeTransport.standard().apply(songs)),
            fontScale = { scale },
        )
        h.waitForTag("$prefix.spotlight-footer")
        h.waitForTag("$prefix.page-next")
        h.awaitAccessibilityTree("$prefix.page-next")
        rule.waitForIdle()

        assertTrue("$config: the toolbar is missing", toolbarShown())
        assertGap(config, "pager", bounds("$prefix.pager").bottom, chromeTop())
        scrollToEnd("$prefix.list")
        assertLastRowClears(config, "$prefix.list", bounds("$prefix.bottom-bar").top)
        h.assertAccessible()
    }

    // endregion

    // region Pages

    @Test
    fun leaderboardsEndOneGapAboveTheToolbar() = page(
        "leaderboards",
        DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
        RankingsFixtures.install(FakeTransport.standard().apply(songs)),
        list = "fst.leaderboards",
        toolbar = true,
    )

    @Test
    fun allRivalsEndOneGapAboveTheBottomBar() = rivals(1f, RivalRoutes.allRivals(RivalScopes.song(listOf(Instrument.Lead))), "fst.all-rivals.list", toolbar = false)

    @Test
    fun allRivalsEndOneGapAboveTheBottomBarAtDoubleText() = rivals(2f, RivalRoutes.allRivals(RivalScopes.song(listOf(Instrument.Lead))), "fst.all-rivals.list", toolbar = false)

    @Test
    fun rivalDetailEndsOneGapAboveTheToolbar() = rivals(1f, detail, "fst.rival-detail.grid", toolbar = true)

    @Test
    fun rivalDetailEndsOneGapAboveTheToolbarAtDoubleText() = rivals(2f, detail, "fst.rival-detail.grid", toolbar = true)

    @Test
    fun rivalryEndsOneGapAboveTheToolbar() = rivals(1f, RivalRoutes.rivalry(detail, "closest_battles", RIVAL_NAME), "fst.rivalry.list", toolbar = true)

    @Test
    fun rivalryEndsOneGapAboveTheToolbarAtDoubleText() = rivals(2f, RivalRoutes.rivalry(detail, "closest_battles", RIVAL_NAME), "fst.rivalry.list", toolbar = true)

    private val detail = RivalRoutes.detail(RivalsFixtures.RIVALS[0], RIVAL_NAME, RivalScopes.song(listOf(Instrument.Lead)))

    /** A Rivals page with long synthetic lists, so every page scrolls to an end. */
    private fun rivals(scale: Float, route: AppRoute, list: String, toolbar: Boolean) {
        val transport = RivalsFixtures.transport().apply(songs).apply {
            val many = (1..24).map { RivalsFixtures.rival("%032x".format(it + 0x1000), "Synthetic Rival $it", 90.0 - it) }
            on("/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Guitar") { RivalsFixtures.list("Solo_Guitar", many.take(12), many.drop(12)) }
            on("/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Guitar/${RivalsFixtures.RIVALS[0]}") {
                RivalsFixtures.detail(RivalsFixtures.RIVALS[0], deltas = (1..30).map { if (it % 2 == 0) it else -it }, name = RIVAL_NAME)
            }
        }
        page(list.substringAfter("fst.").substringBefore('.') + " ${scale}x", DebugLaunch(route = route, profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport, list, toolbar, scale)
    }

    /**
     * Launch [launch], scroll [list] to its end and check its last row ends one gap above the
     * chrome shown (the toolbar when [toolbar], else the bottom bar).
     */
    private fun page(config: String, launch: DebugLaunch, transport: FakeTransport, list: String, toolbar: Boolean, scale: Float = 1f) {
        h.enableAccessibilityChecks()
        h.launch(launch, transport, fontScale = { scale })
        h.waitForTag(list)
        if (toolbar) rule.waitUntil(15_000) { toolbarShown() }
        rule.waitForIdle()
        assertEquals("$config: toolbar shown", toolbar, toolbarShown())
        scrollToEnd(list)
        val end = assertLastRowClears(config, list, chromeTop())
        assertGap(config, "last row", end, chromeTop())
        h.assertAccessible()
    }

    // endregion

    // region Assertions

    /** Whether the floating toolbar draws (a page without tools leaves it zero-sized or absent). */
    // The pill's semantics keep the measured size; an empty toolbar collapses its outer layout to 0.
    private fun toolbarShown(): Boolean =
        rule.onAllNodes(hasTestTag(TOOLBAR), useUnmergedTree = true).fetchSemanticsNodes().any { it.layoutInfo.isPlaced && it.layoutInfo.height > 0 }

    /** Top of the chrome below the page: the toolbar while it draws, else the bottom navigation bar. */
    private fun chromeTop(): Float = if (toolbarShown()) bounds(TOOLBAR).top else bounds(BOTTOM_BAR).top

    /** [bottom] lies one standard gap above [chromeTop], within a dp. */
    private fun assertGap(config: String, what: String, bottom: Float, chromeTop: Float) {
        val gapDp = with(rule.density) { (chromeTop - bottom).toDp() }.value
        Log.i(JourneyHarness.READING_ORDER_TAG, "$config | $what ends ${"%.1f".format(gapDp)} dp above the chrome")
        assertEquals("$config: $what gap above the chrome (dp)", BottomChromeSpacing.GAP_DP.toFloat(), gapDp, 1f)
    }

    /**
     * Scrolled to the end, the lowest row of [list] ends at or above [limit].
     *
     * @return The lowest row's bottom.
     */
    private fun assertLastRowClears(config: String, list: String, limit: Float): Float {
        val viewport = bounds(list)
        val lowest = rule.onAllNodes(hasAnyAncestor(hasTestTag(list)), useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.boundsInRoot }
            .filter { it.height > 0f && it.bottom <= viewport.bottom + 1 }
            .maxOfOrNull { it.bottom }
        assertTrue("$config: no row of $list is on screen at the end", lowest != null)
        assertTrue("$config: the last row ends at $lowest px, under $limit px", lowest!! <= limit + 1)
        return lowest
    }

    // endregion

    // region Helpers

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    /** Swipes [list] up by touch until it stops scrolling. */
    private fun scrollToEnd(list: String) {
        var last = -1f
        repeat(MAX_SWIPES) {
            val now = rule.onNodeWithTag(list).fetchSemanticsNode().config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)?.value?.invoke() ?: 0f
            if (now == last) return
            last = now
            rule.onNodeWithTag(list).performTouchInput { swipeUp(startY = centerY + height / 6f, endY = centerY - height / 6f) }
            rule.waitForIdle()
        }
    }

    // endregion

    private companion object {
        const val TOOLBAR = "fst.nav.floating-toolbar"
        const val BOTTOM_BAR = "fst.nav.bar"
        const val RIVAL_NAME = "Synthetic Rival"
        const val MAX_SWIPES = 40
        val unused = 0.dp
    }
}
