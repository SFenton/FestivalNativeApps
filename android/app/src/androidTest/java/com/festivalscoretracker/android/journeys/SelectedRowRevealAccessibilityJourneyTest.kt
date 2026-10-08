package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The selected-row reveal and the stagger rush it triggers (issue #323, load-transition R5/R6,
 * `leaderboard-row` R7; accessibility backfill #470) on a device, with ATF on every interaction.
 * Each board opens on the selected player's page with the reveal requested (web `navToPlayer` /
 * `navToBand`), so it waits for that row's own entrance, scrolls it above the pinned footer and
 * rushes the rows the scroll reaches:
 * - the selected row ends wholly on screen above the footer, as one 48 dp `Button` stop whose
 *   click names its destination ("Open your statistics" / "Open band"), and the pinned footer
 *   now opens the same destination instead of jumping;
 * - every row the reveal brought on screen is in TalkBack's tree once the rush settles: none is
 *   left transparent (Compose drops a fully transparent node from the tree) or skipped;
 * - TalkBack reads the rows in rank order with no gap, the selected row among them, then the
 *   pinned footer, then the pager.
 *
 * Runs on the solo song board (animations on, 200 % text and the in-app Reduce Motion setting,
 * whose reveal is instant with no fades), the song band board and Full Rankings. `@DeviceCi`:
 * the `android-device` job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.SelectedRowRevealAccessibilityJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class SelectedRowRevealAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private var savedAnimatorScale: String? = null

    /** The selected player's solo rank: deep on page 2, so the reveal has to scroll. */
    private val soloRank = 45

    /** The selected player's band rank: deep on page 2 of the band board. */
    private val bandRank = 47

    private val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
                ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", score = 100_000 - soloRank, rank = soloRank, total = 60)))
            }
            on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
                val offset = Regex("offset=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 0
                val board = Fixtures.leaderboard("s-alpha", rows = minOf(25, 60 - offset), total = 60, startRank = offset + 1)
                // Page 2's row `soloRank` (index 19) belongs to the selected player.
                val synthetic = "\"accountId\":\"${Fixtures.ACCOUNT_A.dropLast(2)}${10 + soloRank - 26}\",\"displayName\":\"Synthetic Player $soloRank\""
                if (offset == 25) board.replace(synthetic, "\"accountId\":\"${RankingsFixtures.SELECTED}\",\"displayName\":\"Selected Player\"") else board
            }
            on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
                val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
                val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
                BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, bandRank.takeIf { "accountId=${BandFixtures.PLAYER}" in request.url })
            }
        },
    )

    /**
     * One board whose reveal the journey checks.
     *
     * @property route Debug route opening the selected row's page with the reveal requested.
     * @property profile Selected player.
     * @property prefix Board id prefix (`.list`, `.bottom-bar`, `.spotlight-footer`, `.page-info`).
     * @property rowPrefix Row test-tag prefix.
     * @property selectedTag The selected row's test tag.
     * @property selectedRank The selected row's rank.
     * @property rowRank Extracts a row's rank from its spoken label.
     * @property footerRank Extracts the pinned footer's rank from its spoken label.
     * @property openLabel Click label of the selected row, and of the footer once the row is on screen.
     */
    private data class Board(
        val route: String,
        val profile: SelectedPlayer,
        val prefix: String,
        val rowPrefix: String,
        val selectedTag: String,
        val selectedRank: Int,
        val rowRank: Regex,
        val footerRank: Regex,
        val openLabel: String,
    )

    private val solo = Board(
        route = "songLeaderboard:s-alpha:Solo_Guitar:2:reveal",
        profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"),
        prefix = "fst.song-leaderboard",
        rowPrefix = "fst.song-leaderboard.row.",
        selectedTag = "fst.song-leaderboard.row.${RankingsFixtures.SELECTED}",
        selectedRank = soloRank,
        rowRank = Regex("^#(\\d+)\\b"),
        footerRank = Regex("^#(\\d+)\\b"),
        openLabel = SelectedRowLabels.OPEN_STATISTICS,
    )

    private val band = Board(
        route = "songBandLeaderboard:s-alpha:Band_Duets:2:reveal",
        profile = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player"),
        prefix = "fst.song-band-leaderboard",
        rowPrefix = "fst.song-band-leaderboard.row.",
        selectedTag = "fst.song-band-leaderboard.row.band-$bandRank:$bandRank",
        selectedRank = bandRank,
        rowRank = Regex("^(?:Your band, )?Rank (\\d+),"),
        footerRank = Regex("^#(\\d+)\\b"),
        openLabel = SelectedRowLabels.OPEN_BAND,
    )

    private val fullRankings = Board(
        route = "fullRankings:Solo_Guitar:2",
        profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"),
        prefix = "fst.full-rankings",
        rowPrefix = "fst.rankings.row.",
        selectedTag = "fst.rankings.row.${RankingsFixtures.SELECTED}",
        selectedRank = RankingsFixtures.SELECTED_RANK,
        rowRank = Regex("^(?:Your rank, )?#(\\d+)\\."),
        footerRank = Regex("^(?:Your rank, )?#(\\d+)\\."),
        openLabel = SelectedRowLabels.OPEN_STATISTICS,
    )

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(fd).bufferedReader().readText().trim()
        }

    /** Animations on (animator duration scale 1), so the fades and the reveal's wait run. */
    @Before
    fun animationsOn() {
        savedAnimatorScale = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale 1")
    }

    @After
    fun restoreAnimatorScale() {
        val saved = savedAnimatorScale
        shell(if (saved == null || saved == "null" || saved.isEmpty()) "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
    }

    private fun bounds(tag: String): Rect? = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()?.boundsInWindow

    /**
     * The part of the board's list a reader sees: below the top bar, and above the pinned footer
     * where the footer shares the row's column (around a hinge the footer sits in the other pane).
     *
     * @param board Board.
     * @param row A row's bounds.
     * @return True when [row] is wholly in that part.
     */
    private fun inView(board: Board, row: Rect): Boolean {
        val list = bounds("${board.prefix}.list") ?: return false
        val top = maxOf(list.top, bounds("fst.nav.top-bar")?.bottom ?: list.top)
        val footer = bounds("${board.prefix}.bottom-bar")
        val sharesColumn = footer != null && footer.left < row.right && footer.right > row.left
        val bottom = if (sharesColumn) minOf(list.bottom, footer!!.top) else list.bottom
        return row.top >= top - 1 && row.bottom <= bottom + 1 && row.width > 0f
    }

    /** Test tags of the board's rows that sit wholly in view (layout bounds: drawn or not). */
    private fun rowsInView(board: Board): Set<String> =
        rule.onAllNodes(
            SemanticsMatcher("row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(board.rowPrefix) == true },
            useUnmergedTree = true,
        ).fetchSemanticsNodes()
            .filter { inView(board, it.boundsInWindow) }
            .mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }
            .toSet()

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

    /** The click action's label of [node] or, for a wrapper, of its single clickable descendant. */
    private fun clickLabel(node: AccessibilityNodeInfo): String? {
        var clickable = node
        while (!clickable.isClickable && clickable.childCount == 1) clickable = clickable.getChild(0) ?: break
        return clickable.actionList.firstOrNull { it.id == AccessibilityNodeInfo.ACTION_CLICK }?.label?.toString()
    }

    /**
     * Every text under [tag] is laid out at [scale] and fits its box (names may shorten to keep
     * their columns, like the board rows).
     */
    private fun assertTextScaled(screen: String, tag: String, scale: Float) {
        val matcher = hasAnyAncestor(hasTestTag(tag)) and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult)
        val nodes = rule.onAllNodes(matcher, useUnmergedTree = true)
        val count = nodes.fetchSemanticsNodes().size
        assertTrue("$screen: no text under $tag", count > 0)
        for (i in 0 until count) {
            val layouts = mutableListOf<TextLayoutResult>()
            nodes[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            val text = layout.layoutInput.text.text
            assertEquals("$screen: \"$text\" laid out at ${scale}x text", scale, layout.layoutInput.density.fontScale, 0.01f)
            val lines = 0 until layout.lineCount
            assertFalse("$screen: \"$text\" is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
            assertFalse("$screen: \"$text\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
        }
    }

    // endregion

    // region Journeys

    /** Solo song board, animations on: the reveal waits for the row's entrance, then rushes the rest. */
    @Test
    fun soloRevealLeavesTheRowAndEveryReachedRowReadable() = journey("reveal-solo", solo)

    /** Solo song board at 200 % text: the taller selected row still lands whole above the taller footer. */
    @Test
    fun soloRevealAtLargeTextKeepsTheRowWholeAndReadable() = journey("reveal-solo-font-2", solo, scale = 2f)

    /** Solo song board under the in-app Reduce Motion setting: an instant reveal with no fades (R6). */
    @Test
    fun soloRevealUnderReduceMotionLeavesEveryRowReadable() = journey(
        "reveal-solo-reduce-motion",
        solo,
        preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true)),
    )

    /** Song band board (web `navToBand`): the band card reveal and its rush. */
    @Test
    fun bandRevealLeavesTheBandAndEveryReachedBandReadable() = journey("reveal-band", band)

    /** Full Rankings on the selected player's page: the same reveal and rush. */
    @Test
    fun fullRankingsRevealLeavesTheRowAndEveryReachedRowReadable() = journey("reveal-full-rankings", fullRankings)

    /**
     * Open [board] on the selected row's page with the reveal requested, wait for it to settle,
     * then check the row, the rows its scroll reached, the reading order and ATF.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param board Board.
     * @param scale Font scale to render at, or null for the device's own.
     * @param preferences Settings store (accessibility modes).
     */
    private fun journey(screen: String, board: Board, scale: Float? = null, preferences: MemoryPreferences = MemoryPreferences()) {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(board.route), profile = board.profile, stillBackground = true)
        h.launch(debug, transport, preferences, fontScale = scale?.let { s -> { s } })
        h.publishTalkBackTree()
        h.waitForTag(board.selectedTag)
        h.waitForTag("${board.prefix}.spotlight-footer")

        // The reveal lands the selected row wholly on screen above the pinned footer (R7).
        try {
            rule.waitUntil(20_000) { bounds(board.selectedTag)?.let { inView(board, it) } == true }
        } catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
            throw AssertionError("$screen: the reveal left ${board.selectedTag} at ${bounds(board.selectedTag)} out of view", timeout)
        }
        rule.waitForIdle()
        h.awaitAccessibilityTree(present = board.selectedTag)

        // Every row the reveal brought on screen is in TalkBack's tree once the rush settles (R5):
        // none stays transparent (out of the tree) or pops in unread.
        val expected = rowsInView(board)
        assertTrue("$screen: no rows in view after the reveal", expected.size >= 3)
        val readable = runCatching {
            rule.waitUntil(10_000) { visibleNodes(board.rowPrefix).mapNotNull { it.viewIdResourceName }.toSet().containsAll(expected) }
        }
        assertTrue(
            "$screen: rows in view but not readable after the reveal: " +
                (expected - visibleNodes(board.rowPrefix).mapNotNull { it.viewIdResourceName }.toSet()),
            readable.isSuccess,
        )

        // The selected row: one 48 dp button stop naming its destination.
        val row = visibleNodes(board.selectedTag).first { it.viewIdResourceName == board.selectedTag }
        assertEquals("$screen: selected row action", board.openLabel, clickLabel(row))
        val role = rule.onAllNodes(hasTestTag(board.selectedTag)).fetchSemanticsNodes().first().config.getOrNull(SemanticsProperties.Role)
        assertEquals("$screen: selected row role", Role.Button, role)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val box = screenBox(row)
        assertTrue("$screen: selected row ${box.width()}×${box.height()} px is under 48 dp", box.width() >= min && box.height() >= min)

        // With the row on screen, the pinned footer opens the same destination instead of jumping (R7).
        val footer = visibleNodes("${board.prefix}.spotlight-footer").first()
        assertEquals("$screen: footer action once the row is on screen", board.openLabel, clickLabel(footer))

        if (scale != null) {
            assertTextScaled(screen, board.selectedTag, scale)
            assertTextScaled(screen, "${board.prefix}.spotlight-footer", scale)
        }

        // Reading order: the rows in rank order with no gap (the selected one among them), then the
        // pinned footer, then the pager.
        val order = h.readingOrder(screen, fresh = true)
        val footerAt = order.indexOfLast { board.footerRank.find(it)?.groupValues?.get(1)?.toInt() == board.selectedRank }
        assertTrue("$screen: pinned footer not read in $order", footerAt >= 0)
        val ranks = order.take(footerAt).mapNotNull { board.rowRank.find(it)?.groupValues?.get(1)?.toInt() }
        assertTrue("$screen: selected row #${board.selectedRank} not read before the footer in $order", board.selectedRank in ranks)
        assertTrue("$screen: fewer rows read (${ranks.size}) than in view (${expected.size}) in $order", ranks.size >= expected.size)
        assertEquals("$screen: rows not read in rank order without a gap: $ranks", (ranks.first()..ranks.last()).toList(), ranks)
        val pager = order.indexOfFirst { it.startsWith("Page 2 of 3") }
        assertTrue("$screen: pager not read after the pinned footer in $order", pager > footerAt)
        h.assertAccessible()
    }

    // endregion
}
