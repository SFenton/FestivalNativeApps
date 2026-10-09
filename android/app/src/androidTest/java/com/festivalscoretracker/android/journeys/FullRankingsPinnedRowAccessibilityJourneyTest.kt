package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The full instrument leaderboard's pinned "your rank" row on a device (issue #318, accessibility
 * backfill #466; `leaderboard-row` R7). The selected player's row stays pinned directly above the
 * pager on every page, their own included, and TalkBack reads it as one button:
 * - off the player's page (page 1) it reads "Your rank, #40. …", acts as "Jump to your position",
 *   and is read after the rows and before the pager;
 * - activating it shows the player's page (page 2), where the row is still pinned, now acts as
 *   "Open your statistics", and is read after the inline highlighted row and before the pager;
 * - it and every pager button are at least 48 dp, inside the window and above/beside the pager,
 *   never straddling a hinge;
 * - at 200 % text the pinned row grows, isn't clipped and still sits above an on-screen pager.
 *
 * ATF runs on every interaction. `@DeviceCi`: the `android-device` job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.FullRankingsPinnedRowAccessibilityJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class FullRankingsPinnedRowAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val prefix = "fst.full-rankings"
    private val footer = "$prefix.spotlight-footer"
    private val pinnedLabel = "Your rank, #${RankingsFixtures.SELECTED_RANK}. "
    private val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    // region Helpers

    /** Visible accessibility nodes whose resource id is exactly [tag] (what TalkBack reaches). */
    private fun visible(tag: String): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName == tag && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    private fun screenBox(n: AccessibilityNodeInfo) = android.graphics.Rect().also(n::getBoundsInScreen)

    private fun minPx() = with(rule.density) { 48.dp.toPx() } - 1

    /** TalkBack's click action label on the pinned row. */
    private fun pinnedAction(): String? =
        visible(footer).firstOrNull()?.actionList?.firstOrNull { it.id == AccessibilityNodeInfo.ACTION_CLICK }?.label?.toString()

    /**
     * The pinned row is one readable, unclipped 48 dp button named for the player's rank, with
     * [action] as its click label, sitting directly above the pager in the same column.
     */
    private fun assertPinnedRow(screen: String, action: String) {
        rule.waitUntil(10_000) { pinnedAction() == action }
        val semantics = rule.onAllNodes(hasTestTag(footer), useUnmergedTree = true).fetchSemanticsNodes().single()
        val description = semantics.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString().orEmpty()
        assertTrue("$screen: pinned row reads \"$description\"", description.startsWith("${pinnedLabel}Synthetic Player ${RankingsFixtures.SELECTED_RANK}."))
        assertEquals("$screen: pinned row role", Role.Button, semantics.config.getOrNull(SemanticsProperties.Role))
        val node = visible(footer).single()
        assertTrue("$screen: pinned row is not clickable for TalkBack", node.isClickable && node.isEnabled)
        val box = screenBox(node)
        assertTrue("$screen: pinned row $box under 48 dp", box.height() >= minPx() && box.width() >= minPx())
        // Not clipped: TalkBack's bounds are the row's whole laid-out size.
        assertEquals("$screen: pinned row clipped", semantics.size.height.toFloat(), box.height().toFloat(), 2f)
        val pager = screenBox(visible("$prefix.pager").single())
        val window = rule.activity.window.decorView.let { v -> IntArray(2).also(v::getLocationOnScreen).let { android.graphics.Rect(it[0], it[1], it[0] + v.width, it[1] + v.height) } }
        assertTrue("$screen: pager $pager leaves the window $window", window.contains(pager))
        if (box.right > pager.left && box.left < pager.right) {
            assertTrue("$screen: pinned row $box is not above the pager $pager", box.bottom <= pager.top + 1)
        }
        h.assertNothingStraddles(footer, "$prefix.pager", "$prefix.page-next")
    }

    /** Each shown pager button is a labelled 48 dp button inside the window. */
    private fun assertPagerTargets(screen: String) {
        val width = rule.activity.window.decorView.width
        mapOf("first" to "First page", "previous" to "Previous page", "next" to "Next page", "last" to "Last page").forEach { (id, label) ->
            val node = rule.onAllNodes(hasTestTag("$prefix.page-$id"), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull() ?: return@forEach
            assertEquals("$screen: $id label", label, node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
            assertEquals("$screen: $id role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            val box = node.boundsInWindow
            assertTrue("$screen: $id $box under 48 dp", box.width >= minPx() && box.height >= minPx())
            assertTrue("$screen: $id $box leaves the window", box.left >= 0f && box.right <= width + 1)
        }
    }

    /**
     * Reading order: the rows (from [firstRow]), then the pinned row, then the pager's page label.
     *
     * @return The reading order.
     */
    private fun assertReadingOrder(screen: String, firstRow: String, page: String): List<String> {
        val order = h.readingOrder(screen, fresh = true)
        val row = order.indexOfFirst { it.contains(firstRow) }
        val pinned = order.indexOfLast { it.startsWith(pinnedLabel) }
        val pager = order.indexOfFirst { it.startsWith(page) }
        assertTrue("$screen: $firstRow not read in $order", row >= 0)
        assertTrue("$screen: pinned row not read in $order", pinned >= 0)
        assertTrue("$screen: $page not read in $order", pager >= 0)
        assertTrue("$screen: rows not read before the pinned row in $order", row < pinned)
        assertTrue("$screen: pinned row not read before the pager in $order", pinned < pager)
        return order
    }

    // endregion

    // region Journeys

    /** Device text size: the pinned row on another page and on the player's own page. */
    @Test
    fun pinnedRowReadsAsOneButtonAboveThePagerOnEveryPage() = journey("full-rankings-pinned")

    /** 200 % text: the pinned row grows unclipped and stays above an on-screen pager on both pages. */
    @Test
    fun largeTextKeepsThePinnedRowReadableAboveThePager() = journey("full-rankings-pinned-font-2", large = true)

    /**
     * Page 1 (row elsewhere: jump), activate the pinned row, page 2 (row on screen: still pinned, opens Statistics).
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param large Switch to 200 % text after measuring the pinned row at 100 %.
     */
    private fun journey(screen: String, large: Boolean = false) {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(
                route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"),
                profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"),
                stillBackground = true,
            ),
            transport,
            fontScale = { scale },
        )
        h.waitForTag(footer)
        h.waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
        h.awaitAccessibilityTree(footer)
        if (large) {
            val before = visible(footer).single().let(::screenBox).height()
            scale = 2f
            rule.waitForIdle()
            rule.waitUntil(10_000) { visible(footer).singleOrNull()?.let(::screenBox)?.height()?.let { it > before * 1.3f } == true }
        }

        // Page 1: the player's row (#40) is on page 2, so the pinned row jumps there.
        assertPinnedRow(screen, SelectedRowLabels.JUMP_TO_PLAYER)
        assertPagerTargets(screen)
        assertReadingOrder(screen, "Synthetic Player 1.", "Page 1 of 3")

        // Issue #318: on the player's own page the row stays pinned above the pager and opens Statistics.
        h.tap(footer)
        rule.waitUntil(15_000) { rule.onAllNodes(hasContentDescription("Page 2 of 3"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        h.waitForTag("fst.rankings.row.${RankingsFixtures.SELECTED}")
        h.waitForTag(footer)
        h.awaitAccessibilityTree(footer)
        assertPinnedRow("$screen-own-page", SelectedRowLabels.OPEN_STATISTICS)
        assertPagerTargets("$screen-own-page")
        val order = assertReadingOrder("$screen-own-page", "Synthetic Player ", "Page 2 of 3")
        // When the revealed inline row is on screen too, it is read before its pinned copy.
        val reads = order.indices.filter { order[it].startsWith(pinnedLabel) }
        assertTrue("$screen-own-page: pinned row read ${reads.size} times in $order", reads.size in 1..2)
        h.assertAccessible()
    }

    // endregion
}
