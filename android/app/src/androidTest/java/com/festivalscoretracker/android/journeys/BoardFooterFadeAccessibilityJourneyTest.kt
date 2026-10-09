package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PixelMap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardLayout
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs
import kotlin.math.ceil

/**
 * The board footer fade on a device, for accessibility (issue #329, backfill #473; `scroll-edge`
 * R3, R7). Every Android board that floats its "your rank" row and pager at the bottom (Song
 * Leaderboard, band song leaderboard, Full Rankings, Band Rankings: `RankingsBoardLayout`
 * `fadeAboveFooter`) fades its rows over a linear [ScrollEdgeFade.BOTTOM_DP] (40 dp) ramp ending at
 * the footer's top. On each board, at the device text size and at 200 %:
 * - a row the ramp dims is still a visible TalkBack stop (the ramp is drawing only), labelled
 *   wherever the list shows its content (a sliver peeking above the footer is clipped by the
 *   list, not the ramp), and is read before the pager;
 * - no row node reaches under the footer and the list's accessibility bounds end at its top, so
 *   covered rows leave touch and TalkBack (#104); beside a pager-only footer (Band Rankings) a
 *   row peeking less than 48 dp above the cut once reached 24 dp under it (#473);
 * - ATF passes (labels, 48 dp targets, contrast of what is drawn).
 *
 * With the real system settings on the same `RankingsBoardLayout` inside [FestivalTheme], rows
 * fade over a 40 dp linear ramp by default, and system High contrast text or Remove animations
 * (animator duration scale 0) switch it to a hard cut at the footer live and back (R7), with
 * nothing drawn beneath the footer in any mode.
 *
 * `@DeviceCi`: the `android-device` job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.BoardFooterFadeAccessibilityJourneyTest --avd …`).
 * Around a separating hinge the footer sits in the other pane with no fade, so the ramp checks
 * are skipped there.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class BoardFooterFadeAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Boards

    /**
     * One board that fades above its footer.
     *
     * @property route Debug route.
     * @property prefix `RankingsBoardLayout` id prefix.
     * @property rows Row test-tag prefix.
     * @property profile Selected player.
     * @property transport Fixture service.
     */
    private class Board(val route: String, val prefix: String, val rows: String, val profile: SelectedPlayer, val transport: () -> FakeTransport)

    private fun standard() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private val selected = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")

    private val songLeaderboard = Board("songLeaderboard:s-alpha:Solo_Guitar", "fst.song-leaderboard", "fst.song-leaderboard.row.", selected) {
        RankingsFixtures.install(
            standard().apply {
                on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
                    ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
                }
            },
        )
    }

    private val bandSongLeaderboard = Board(
        "songBandLeaderboard:s-alpha:Band_Duets",
        "fst.song-band-leaderboard",
        "fst.song-band-leaderboard.row.",
        SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player"),
    ) { BandFixtures.install(standard()) }

    private val fullRankings = Board("fullRankings:Solo_Guitar", "fst.full-rankings", "fst.rankings.row.", selected) { RankingsFixtures.install(standard()) }

    private val bandRankings = Board("bandRankings:Band_Duets", "fst.band-rankings", "fst.band-rankings.row.", selected) { RankingsFixtures.install(standard()) }

    // endregion

    // region Accessibility-tree helpers

    /** Visible accessibility nodes whose resource id matches [matches] (what TalkBack reaches). */
    private fun visible(matches: (String) -> Boolean): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName?.let(matches) == true && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    private fun screenBox(n: AccessibilityNodeInfo) = android.graphics.Rect().also(n::getBoundsInScreen)

    private fun isStop(n: AccessibilityNodeInfo) = n.isScreenReaderFocusable || n.isClickable || n.isLongClickable

    /** The node TalkBack focuses for a row: the row itself or its first focusable descendant. */
    private fun stop(row: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (isStop(row)) return row
        for (i in 0 until row.childCount) {
            val child = row.getChild(i)?.takeIf { it.isVisibleToUser } ?: continue
            stop(child)?.let { return it }
        }
        return null
    }

    /** What TalkBack speaks for [node], composed as [JourneyHarness.readingOrder] does. */
    private fun spoken(node: AccessibilityNodeInfo): String {
        fun own(n: AccessibilityNodeInfo) = listOfNotNull(n.contentDescription, n.text, n.stateDescription)
            .map { it.toString().trim() }.filter { it.isNotEmpty() }.distinct().joinToString(", ")
        fun descendants(n: AccessibilityNodeInfo): String = buildList {
            for (i in 0 until n.childCount) {
                val child = n.getChild(i) ?: continue
                if (!child.isVisibleToUser || isStop(child)) continue
                own(child).takeIf { it.isNotEmpty() }?.let(::add) ?: descendants(child).takeIf { it.isNotEmpty() }?.let(::add)
            }
        }.joinToString(", ")
        if (!node.contentDescription.isNullOrBlank()) return own(node)
        return listOfNotNull(node.text, descendants(node), node.stateDescription)
            .map { it.toString().trim() }.filter { it.isNotEmpty() }.distinct().joinToString(", ")
    }

    private fun hasTagPrefix(prefix: String) = SemanticsMatcher("test tag starts with $prefix") {
        it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true
    }

    // endregion

    // region Board journeys

    /** Song Leaderboard: rows dimmed by the ramp stay readable; covered rows leave TalkBack. */
    @Test
    fun songLeaderboardFadeKeepsDimmedRowsReadable() = journey("board-fade-song", songLeaderboard)

    /** Song Leaderboard at 200 % text. */
    @Test
    fun songLeaderboardFadeKeepsDimmedRowsReadableAtLargeText() = journey("board-fade-song-font-2", songLeaderboard, scale = 2f)

    /** Band song leaderboard: rows dimmed by the ramp stay readable; covered rows leave TalkBack. */
    @Test
    fun bandSongLeaderboardFadeKeepsDimmedRowsReadable() = journey("board-fade-band-song", bandSongLeaderboard)

    /** Band song leaderboard at 200 % text. */
    @Test
    fun bandSongLeaderboardFadeKeepsDimmedRowsReadableAtLargeText() = journey("board-fade-band-song-font-2", bandSongLeaderboard, scale = 2f)

    /** Full Rankings: rows dimmed by the ramp stay readable; covered rows leave TalkBack. */
    @Test
    fun fullRankingsFadeKeepsDimmedRowsReadable() = journey("board-fade-full-rankings", fullRankings)

    /** Full Rankings at 200 % text. */
    @Test
    fun fullRankingsFadeKeepsDimmedRowsReadableAtLargeText() = journey("board-fade-full-rankings-font-2", fullRankings, scale = 2f)

    /** Band Rankings: rows dimmed by the ramp stay readable; covered rows leave TalkBack. */
    @Test
    fun bandRankingsFadeKeepsDimmedRowsReadable() = journey("board-fade-band-rankings", bandRankings)

    /** Band Rankings at 200 % text. */
    @Test
    fun bandRankingsFadeKeepsDimmedRowsReadableAtLargeText() = journey("board-fade-band-rankings-font-2", bandRankings, scale = 2f)

    /**
     * Opens [board] at rest (page 1, rows running on under the footer, so the ramp is its full
     * 40 dp) and checks the fade region in the tree TalkBack reads; then scrolls so a row peeks
     * only [SLIVER_DP] above the footer (where a Pixel 6 rests on Song Leaderboard, #473) and
     * checks again, so every device covers that geometry.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param board The board.
     * @param scale Font scale, or null for the device's own.
     */
    private fun journey(screen: String, board: Board, scale: Float? = null) {
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute(board.route), profile = board.profile, stillBackground = true),
            board.transport(),
            fontScale = scale?.let { s -> { s } },
        )
        // Reading order follows TalkBack's traversal links and a fresh tree, not raw tree order.
        h.publishTalkBackTree()
        val bar = "${board.prefix}.bottom-bar"
        h.waitForTag(bar)
        h.waitForTag("${board.prefix}.pager")
        rule.waitUntil(15_000) { rule.onAllNodes(hasTagPrefix(board.rows), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        h.awaitAccessibilityTree(bar)
        rule.waitUntil(15_000) { visible { it.startsWith(board.rows) }.isNotEmpty() && visible { it == bar }.isNotEmpty() }
        h.assertNothingStraddles(bar, "${board.prefix}.pager")
        if (h.exists("${board.prefix}.supporting-pane")) {
            // Around a hinge the footer is in the other pane, beside the rows: nothing fades.
            h.assertAccessible()
            return
        }

        checkFade(screen, board, fresh = scale != null)
        peekSliver(board)
        checkFade("$screen-sliver", board, fresh = true, sliver = true)
        // Scroll back so the hide-on-scroll floating toolbar (always shown under TalkBack) slides
        // fully in again before ATF's findings are judged.
        rule.onNodeWithTag("${board.prefix}.list").performSemanticsAction(SemanticsActions.ScrollBy) {
            it(0f, -rule.activity.resources.displayMetrics.heightPixels.toFloat())
        }
        rule.waitForIdle()
        h.assertAccessible()
    }

    /**
     * Checks the fade region of the open [board] in the tree TalkBack reads.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param board The board.
     * @param fresh Drop UiAutomation's node cache before reading the order (after a change in place).
     * @param sliver Require a row peeking less than half its height above the footer.
     */
    private fun checkFade(screen: String, board: Board, fresh: Boolean, sliver: Boolean = false) {
        val bar = "${board.prefix}.bottom-bar"
        rule.waitForIdle()
        if (android.os.Build.VERSION.SDK_INT >= 34) InstrumentationRegistry.getInstrumentation().uiAutomation.clearCache()
        val footer = screenBox(visible { it == bar }.first())
        val ramp = ScrollEdgeFade.BOTTOM_DP * rule.activity.resources.displayMetrics.density
        assertEquals("$screen: board footer ramp (web board useScrollMask)", 40f, ScrollEdgeFade.BOTTOM_DP, 0f)

        // The list ends at the footer's top, so nothing beneath it is touchable or readable (#104, R7).
        val list = visible { it == "${board.prefix}.list" }
        assertTrue("$screen: board list not in the tree", list.isNotEmpty())
        list.forEach { assertTrue("$screen: list ${screenBox(it)} reaches under the footer $footer", screenBox(it).bottom <= footer.top + 1) }
        val rows = visible { it.startsWith(board.rows) }.filter { screenBox(it).let { b -> b.right > footer.left && b.left < footer.right } }
        rows.forEach { row ->
            assertTrue("$screen: ${row.viewIdResourceName} ${screenBox(row)} reaches under the footer $footer", screenBox(row).bottom <= footer.top + 1)
        }

        // Rows the 40 dp ramp dims are drawing-only changes: still visible TalkBack stops, and
        // labelled wherever the list shows their content. A row peeking only a sliver above the
        // footer is clipped by the list itself, not the ramp: its text children leave the tree
        // until TalkBack scrolls it in, as at any list edge (JourneyHarness treats ATF's matching
        // finding as a clipping artifact), so it must be a stop that composes a label. Rows tile,
        // so a sliver under 40 dp leaves a fully shown row ending inside the ramp, and one of
        // 40 dp or more shows at least the ramp's height: `shown` is never empty.
        val dimmed = rows.filter { screenBox(it).let { b -> b.bottom > footer.top - ramp && b.top < footer.top } }
        assertTrue("$screen: no row in the ${ScrollEdgeFade.BOTTOM_DP} dp ramp above $footer: ${rows.map(::screenBox)}", dimmed.isNotEmpty())
        dimmed.forEach { row -> assertTrue("$screen: dimmed ${row.viewIdResourceName} is not a TalkBack stop", stop(row) != null) }
        val (shown, slivers) = dimmed.partition { row ->
            val (height, full) = shownHeight(row.viewIdResourceName, bar)
            height >= minOf(full / 2f, ramp) - 1
        }
        assertTrue("$screen: no dimmed row shows its content: ${dimmed.map(::screenBox)}", shown.isNotEmpty())
        if (sliver) assertTrue("$screen: no row peeks a sliver above $footer: ${dimmed.map(::screenBox)}", slivers.isNotEmpty())
        slivers.forEach { row ->
            val label = hasAnyAncestor(hasTestTag(row.viewIdResourceName)) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Text)
            assertTrue("$screen: sliver ${row.viewIdResourceName} composes no label", rule.onAllNodes(label, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        }
        val stops = shown.map { stop(it)!! }
        stops.forEach { assertTrue("$screen: dimmed row ${it.viewIdResourceName} ${screenBox(it)} is unlabelled", spoken(it).isNotEmpty()) }

        // Reading order: the shown dimmed row nearest the footer is read before the pager.
        val order = h.readingOrder(screen, fresh = fresh)
        val nearest = spoken(stops.maxBy { screenBox(it).bottom })
        val row = order.indexOf(nearest)
        val pager = order.indexOfFirst { it.startsWith("Page 1 of ") }
        assertTrue("$screen: dimmed row \"$nearest\" not read in $order", row >= 0)
        assertTrue("$screen: page label not read in $order", pager >= 0)
        assertTrue("$screen: dimmed row read after the pager in $order", row < pager)
    }

    /** The row tagged [tag]'s height shown above the footer [bar], and its full height, in px (Compose layout). */
    private fun shownHeight(tag: String, bar: String): Pair<Float, Float> {
        val row = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first()
        val cut = rule.onAllNodesWithTag(bar, useUnmergedTree = true).fetchSemanticsNodes().first().positionInRoot.y
        val top = row.positionInRoot.y
        return (minOf(top + row.size.height, cut) - top) to row.size.height.toFloat()
    }

    /**
     * Scrolls [board]'s list so a row's top sits [SLIVER_DP] above the footer. The controls item
     * scrolls fully off first, so the list's top edge cuts only a row (tall enough for ATF's
     * clipping allowance), never a control menu.
     */
    private fun peekSliver(board: Board) {
        val bar = "${board.prefix}.bottom-bar"
        val sliver = SLIVER_DP * rule.density.density
        val rows = hasTagPrefix(board.rows) and !hasAnyAncestor(hasTestTag(bar))
        rule.onNodeWithTag("${board.prefix}.list").performScrollToIndex(1)
        repeat(4) {
            rule.waitForIdle()
            val cut = rule.onAllNodesWithTag(bar, useUnmergedTree = true).fetchSemanticsNodes().first().positionInRoot.y
            val want = cut - sliver
            val spans = rule.onAllNodes(rows, useUnmergedTree = true).fetchSemanticsNodes()
                .map { it.positionInRoot.y to it.positionInRoot.y + it.size.height }.sortedBy { it.first }
            if (spans.any { abs(it.first - want) < 1f }) return
            // The next row starts at or below the wanted top (just after the last composed row if none is).
            val next = spans.firstOrNull { it.first > want }?.first ?: spans.last().second
            rule.onNodeWithTag("${board.prefix}.list").performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, next - want) }
        }
        rule.waitForIdle()
    }

    // endregion

    // region System settings (R7) on the drawn ramp

    private var saved: Pair<String, String>? = null

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    private fun setHighContrastText(on: Boolean) = shell("settings put secure $HIGH_CONTRAST_TEXT ${if (on) 1 else 0}")

    private fun setAnimatorScale(scale: String) = shell("settings put global animator_duration_scale $scale")

    /** Save the system settings this region changes, then start from animations on, High contrast text off. */
    private fun useDefaultSettings() {
        saved = shell("settings get global animator_duration_scale") to shell("settings get secure $HIGH_CONTRAST_TEXT")
        setAnimatorScale("1")
        setHighContrastText(false)
    }

    @After
    fun restoreSettings() {
        val (scale, contrast) = saved ?: return
        shell(if (scale == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $scale")
        shell(if (contrast == "null") "settings delete secure $HIGH_CONTRAST_TEXT" else "settings put secure $HIGH_CONTRAST_TEXT $contrast")
    }

    /** A 400 × 800 dp board of red 40 dp rows on blue under a transparent 100 dp footer, in [FestivalTheme]. */
    private fun launchDrawnBoard() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.size(400.dp, 800.dp).background(Color.Blue).testTag(FRAME)) {
                    RankingsBoardLayout(
                        hinge = null,
                        measure = Modifier,
                        padding = PaddingValues(),
                        listState = rememberLazyListState(),
                        idPrefix = "fst.t",
                        controls = {},
                        footer = { Box(Modifier.fillMaxWidth().height(100.dp)) },
                        pager = {},
                        fadeAboveFooter = true,
                    ) {
                        items(100) { Box(Modifier.fillMaxWidth().height(40.dp).background(Color.Red)) }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    /** The frame's red channel down its centre, with the footer's top ([cut]) and the full ramp in px. */
    private inner class Shot(private val pixels: PixelMap, val cut: Int, val ramp: Float) {
        fun red(y: Int) = pixels[pixels.width / 2, y].red
        val band get() = ceil(cut - ramp).toInt() until cut
        val above get() = (cut - ramp - 200 * rule.density.density).toInt() until ceil(cut - ramp).toInt() - 1
        val below get() = cut + 1 until pixels.height

        /** Rows fade out over a 40 dp linear ramp ending at the cut; opaque above it, gone below. */
        fun isFade(): Boolean {
            val lit = band.filter { red(it) > 0.02f }
            return lit.size > ramp / 3 &&
                lit.all { abs(red(it) - (cut - (it + 0.5f)) / ramp) <= 0.05f } &&
                lit.any { red(it) in 0.3f..0.7f } &&
                red(cut - 1) < 0.1f &&
                above.all { red(it) > 0.95f || red(it) < 0.02f } && above.any { red(it) > 0.95f } &&
                below.none { red(it) > 0.05f }
        }

        /** R7: rows are opaque right up to the cut and gone below it. */
        fun isHardEdge(): Boolean =
            band.all { red(it) > 0.95f || red(it) < 0.02f } && band.any { red(it) > 0.95f } &&
                below.none { red(it) > 0.05f }

        fun describe() = "cut $cut px, ramp $ramp px, red over the ramp ${band.map { "%.2f".format(red(it)) }}"
    }

    private fun shot(): Shot {
        val frame = rule.onNodeWithTag(FRAME).fetchSemanticsNode().boundsInRoot
        val footer = rule.onNodeWithTag("fst.t.bottom-bar").fetchSemanticsNode().boundsInRoot
        return Shot(
            rule.onNodeWithTag(FRAME).captureToImage().toPixelMap(),
            cut = (footer.top - frame.top).toInt(),
            ramp = ScrollEdgeFade.BOTTOM_DP * rule.density.density,
        )
    }

    private fun awaitEdge(label: String, hard: Boolean) {
        runCatching { rule.waitUntil(5_000) { shot().let { if (hard) it.isHardEdge() else it.isFade() } } }
        val s = shot()
        assertTrue("$label: expected ${if (hard) "a hard edge" else "a 40 dp fade"}; ${s.describe()}", if (hard) s.isHardEdge() else s.isFade())
    }

    /** Default settings: rows fade over a 40 dp linear ramp into the footer and never show beneath it. */
    @Test
    fun rowsFadeOverFortyDpIntoTheFooter() {
        useDefaultSettings()
        launchDrawnBoard()
        awaitEdge("default", hard = false)
    }

    /** System High contrast text cuts the rows hard at the footer, live, and the ramp returns when it is off. */
    @Test
    fun highContrastTextCutsAtTheFooterLive() {
        useDefaultSettings()
        launchDrawnBoard()
        awaitEdge("before High contrast text", hard = false)
        setHighContrastText(true)
        awaitEdge("High contrast text on", hard = true)
        setHighContrastText(false)
        awaitEdge("High contrast text off", hard = false)
    }

    /** System Remove animations (animator duration scale 0) cuts the rows hard at the footer, live. */
    @Test
    fun removeAnimationsCutsAtTheFooterLive() {
        useDefaultSettings()
        launchDrawnBoard()
        awaitEdge("animations on", hard = false)
        setAnimatorScale("0")
        awaitEdge("Remove animations on", hard = true)
        setAnimatorScale("1")
        awaitEdge("animations back on", hard = false)
    }

    // endregion

    private companion object {
        const val FRAME = "board-fade-frame"
        const val HIGH_CONTRAST_TEXT = "high_text_contrast_enabled"

        /** How far a row peeks above the footer in the sliver pass, in dp. */
        const val SLIVER_DP = 8f
    }
}
