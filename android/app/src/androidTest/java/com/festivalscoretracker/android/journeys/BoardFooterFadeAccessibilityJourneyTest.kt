package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of the board footer fade that issue #308 consolidated (test backfill, issue #462),
 * on the boards with **no** selected player, where only the pager floats above the rows
 * (scroll-edge R9: the fade is the same with or without a pinned row). `bottomChromeEdgeFade` is
 * drawing only, and `clipAboveFooter` ends the list at the pager's top in every mode (R7, issues
 * #104, #306), so these journeys pin what TalkBack gets: mid-scroll and at the list end no row the
 * pager covers stays in the accessibility tree (Compose widens a clickable row's bounds 24 dp past
 * the cut, so the footer band occludes the rows beneath it, issue #462), the last row is fully
 * readable above the pager,
 * rows are read before the pager, and every pager button is a labelled 48 dp button beside a
 * polite "Page 1 of n" label. Each board runs with default settings, one per in-app hard-edge
 * setting (Increase Contrast, Reduce Transparency, Reduce Motion: no ramp, the cut stays) and at
 * 200 % text. ATF runs throughout. The solo song board with a pinned player row is
 * [SongLeaderboardJourneyTest] (#443); the Songs pinned titles are
 * [SongsBucketHeaderAccessibilityJourneyTest]. Fixture-only;
 * `device.py test com.festivalscoretracker.android.journeys.BoardFooterFadeAccessibilityJourneyTest --avd FST_Phone`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class BoardFooterFadeAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /**
     * One board with a floating pager.
     *
     * @property route Debug route.
     * @property prefix Board test-tag prefix.
     * @property rowPrefix Row test-tag prefix.
     * @property lastRow Tag of page 1's last row.
     * @property rowLabel Text every row's spoken label contains.
     * @property pages Page count.
     */
    private data class Board(val route: String, val prefix: String, val rowPrefix: String, val lastRow: String, val rowLabel: String, val pages: Int)

    private val fullRankings = Board(
        route = "fullRankings:Solo_Guitar",
        prefix = "fst.full-rankings",
        rowPrefix = "fst.rankings.row.",
        lastRow = "fst.rankings.row.${RankingsFixtures.accountId(25)}",
        rowLabel = "Synthetic Player",
        pages = 3,
    )

    private val bandRankings = Board(
        route = "bandRankings:Band_Duets",
        prefix = "fst.band-rankings",
        rowPrefix = "fst.band-rankings.row.",
        lastRow = "fst.band-rankings.row.${RankingsFixtures.accountId(1025)}:${RankingsFixtures.accountId(2025)}",
        rowLabel = "Member",
        pages = 2,
    )

    private val songBandBoard = Board(
        route = "songBandLeaderboard:s-alpha:Band_Duets",
        prefix = "fst.song-band-leaderboard",
        rowPrefix = "fst.song-band-leaderboard.row.",
        lastRow = "fst.song-band-leaderboard.row.band-25:25",
        rowLabel = "Synthetic Lead",
        pages = 2,
    )

    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    /** The board's fixtures: band song boards need [BandFixtures], whose band lookup would shadow Band Rankings. */
    private fun transport(board: Board): FakeTransport =
        if (board == songBandBoard) BandFixtures.install(FakeTransport.standard().apply(songs)) else RankingsFixtures.install(FakeTransport.standard().apply(songs))

    // region Helpers

    /** Visible accessibility nodes whose resource id starts with [prefix]. */
    private fun visibleNodes(prefix: String): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName?.startsWith(prefix) == true && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    private fun screenBox(n: AccessibilityNodeInfo) = android.graphics.Rect().also(n::getBoundsInScreen)

    private fun isRow(board: Board) = SemanticsMatcher("${board.rowPrefix}*") {
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith(board.rowPrefix)
    }

    /**
     * Launch [board] with no selected player.
     *
     * @param setting In-app hard-edge setting to turn on, or null.
     * @param scale Font scale, or null for the device's.
     */
    private fun launch(board: Board, setting: String? = null, scale: Float? = null) {
        val preferences = mutablePreferencesOf()
        if (setting != null) preferences[booleanPreferencesKey(setting)] = true
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute(board.route), stillBackground = true), transport(board), MemoryPreferences(preferences), scale?.let { s -> { s } })
        h.waitForTag("${board.prefix}.pager")
        rule.waitUntil(15_000) { rule.onAllNodes(isRow(board), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        h.awaitAccessibilityTree("${board.prefix}.page-info")
    }

    /**
     * Each shown pager button is a labelled button at least 48 dp square, and the page label is a
     * polite live region reading "Page 1 of n" whose text, at [scale], is laid out unclipped.
     */
    private fun assertPager(screen: String, board: Board, scale: Float?) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        mapOf("first" to "First page", "previous" to "Previous page", "next" to "Next page", "last" to "Last page").forEach { (id, label) ->
            val tag = "${board.prefix}.page-$id"
            val node = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull() ?: return@forEach
            assertEquals("$screen: $tag label", label, node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
            assertEquals("$screen: $tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            val box = node.boundsInWindow
            assertTrue("$screen: $tag $box under 48 dp", box.width >= min && box.height >= min)
        }
        val info = rule.onAllNodes(hasTestTag("${board.prefix}.page-info"), useUnmergedTree = true).fetchSemanticsNodes().single()
        assertEquals("$screen: page label", "Page 1 of ${board.pages}", info.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
        assertEquals("$screen: page label is a polite live region", LiveRegionMode.Polite, info.config.getOrNull(SemanticsProperties.LiveRegion))
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onAllNodes(hasTestTag("${board.prefix}.page-info"), useUnmergedTree = true)[0].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.single()
        if (scale != null) assertEquals("$screen: page label laid out at ${scale}x", scale, layout.layoutInput.density.fontScale, 0.01f)
        // `hasVisualOverflow` compares the box with the paragraph's constraint width, so check the
        // laid-out lines like SongLeaderboardJourneyTest does.
        val lines = 0 until layout.lineCount
        assertFalse("$screen: page label is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
        assertFalse("$screen: page label is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
        assertFalse("$screen: page label is ellipsized", lines.any(layout::isLineEllipsized))
    }

    /**
     * No row the floating pager covers stays readable or touchable: every visible row node ends
     * at or above the bottom bar's top. With [atEnd], the last row is in the tree, fully above it.
     *
     * @return The bottom bar's top in screen px.
     */
    private fun assertNoRowUnderThePager(screen: String, board: Board, atEnd: Boolean): Int {
        val bar = visibleNodes("${board.prefix}.bottom-bar").firstOrNull { it.viewIdResourceName == "${board.prefix}.bottom-bar" }
        assertTrue("$screen: the bottom bar is readable", bar != null)
        val top = screenBox(bar!!).top
        val rows = visibleNodes(board.rowPrefix).filter { it.viewIdResourceName?.startsWith(board.rowPrefix) == true }
        assertTrue("$screen: rows are readable", rows.isNotEmpty())
        rows.forEach { row ->
            assertTrue(
                "$screen: ${row.viewIdResourceName} reaches under the pager (${screenBox(row).bottom} > $top); " +
                    "rows ${rows.map { "${it.viewIdResourceName?.substringAfterLast('.')} ${screenBox(it)}" }}",
                screenBox(row).bottom <= top + 1,
            )
        }
        if (atEnd) {
            val last = rows.firstOrNull { it.viewIdResourceName == board.lastRow }
            assertTrue("$screen: the last row ${board.lastRow} is readable at the list end", last != null)
            val box = screenBox(last!!)
            val full = rule.onAllNodes(hasTestTag(board.lastRow), useUnmergedTree = true).fetchSemanticsNodes().first().size.height
            assertTrue("$screen: the last row is cut (${box.height()} of $full px)", box.height() >= full - 1)
        }
        return top
    }

    /** TalkBack reads the shown rows before the pager, and the pager's page label once. */
    private fun assertRowsReadBeforeThePager(screen: String, board: Board) {
        val order = h.readingOrder(screen, fresh = true)
        val lastRow = order.indexOfLast { it.contains(board.rowLabel) }
        val pager = order.indexOfFirst { it.startsWith("Page 1 of ${board.pages}") }
        assertTrue("$screen: no row read in $order", lastRow >= 0)
        assertTrue("$screen: the page label is not read in $order", pager >= 0)
        assertTrue("$screen: a row is read after the pager in $order", lastRow < pager)
        assertEquals("$screen: the page label is read once in $order", 1, order.count { it.startsWith("Page 1 of ") })
    }

    /**
     * The journey: pager targets at rest, then mid-scroll and at the list end the cut, the last
     * row and the reading order; ATF on every interaction.
     *
     * @param screen Reading-order log name.
     * @param board Board.
     * @param setting In-app hard-edge setting, or null.
     * @param scale Font scale, or null.
     */
    private fun journey(screen: String, board: Board, setting: String? = null, scale: Float? = null) {
        h.enableAccessibilityChecks()
        launch(board, setting, scale)
        assertTrue("$screen: no pinned player row without a selected player", !h.exists("${board.prefix}.spotlight-footer"))
        assertPager(screen, board, scale)

        // Full and Band Rankings hold their rows in one card item, so scroll by distance, not index.
        val list = rule.onNodeWithTag("${board.prefix}.list")
        list.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, with(rule.density) { MID_SCROLL.toPx() }) }
        rule.waitForIdle()
        assertNoRowUnderThePager("$screen-mid", board, atEnd = false)
        assertRowsReadBeforeThePager("$screen-mid", board)

        list.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, 1_000_000f) }
        rule.waitForIdle()
        assertNoRowUnderThePager("$screen-end", board, atEnd = true)
        assertRowsReadBeforeThePager("$screen-end", board)
        assertPager("$screen-end", board, scale)
        h.assertAccessible()
    }

    // endregion

    // region Journeys

    /** Full Rankings, default settings. */
    @Test
    fun fullRankingsEndsAtThePager() = journey("full-rankings-footer", fullRankings)

    /** Band Rankings, default settings. */
    @Test
    fun bandRankingsEndsAtThePager() = journey("band-rankings-footer", bandRankings)

    /** The band song board, default settings. */
    @Test
    fun songBandBoardEndsAtThePager() = journey("song-band-footer", songBandBoard)

    /** Increase Contrast drops the ramp; the cut at the pager stays (R7). */
    @Test
    fun increaseContrastStillEndsFullRankingsAtThePager() =
        journey("full-rankings-footer-contrast", fullRankings, setting = SettingsRegistry.INCREASE_CONTRAST)

    /** Reduce Transparency drops the ramp; the cut at the pager stays (R7). */
    @Test
    fun reduceTransparencyStillEndsBandRankingsAtThePager() =
        journey("band-rankings-footer-transparency", bandRankings, setting = SettingsRegistry.REDUCE_TRANSPARENCY)

    /** Reduce Motion drops the ramp; the cut at the pager stays (R7). */
    @Test
    fun reduceMotionStillEndsTheSongBandBoardAtThePager() =
        journey("song-band-footer-motion", songBandBoard, setting = SettingsRegistry.REDUCE_MOTION)

    /** 200 % text: the pager grows unclipped, stays 48 dp, and rows still end above it. */
    @Test
    fun largeTextKeepsTheCutAndPagerOnBandRankings() = journey("band-rankings-footer-font-2", bandRankings, scale = 2f)

    // endregion

    private companion object {
        /** Mid-list scroll: past the header, well short of page 1's end. */
        val MID_SCROLL = 400.dp
    }
}
