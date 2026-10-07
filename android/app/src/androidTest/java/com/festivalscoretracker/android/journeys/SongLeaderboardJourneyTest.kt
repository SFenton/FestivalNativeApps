package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The solo song leaderboard on a device (issues #93, #190): before any scroll the top bar
 * carries no title, and takes the song title once the in-page header has scrolled under it;
 * the pinned score and pager float at the bottom while rows beneath them leave the
 * accessibility tree (no visible row node overlaps the footer); TalkBack reads header → rows →
 * pinned score → pager; the pinned row is one 48 dp "Jump to your position" button; and a
 * page change keeps the pinned score and pager in place while only the rows show the spinner. ATF runs
 * throughout and nothing straddles a hinge
 * (`device.py test com.festivalscoretracker.android.journeys.SongLeaderboardJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SongLeaderboardJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val prefix = "fst.song-leaderboard"
    private val footer = "$prefix.spotlight-footer"
    private val nextPage = CompletableDeferred<Unit>()
    private val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
                ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
            }
            // Hold page 2 open so the loading state can be inspected.
            beforeRespond = { request ->
                if (request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && request.url.contains("offset=25")) nextPage.await()
            }
        },
    )

    // region Helpers

    private fun bounds(tag: String): Rect = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    /** Whether the top bar shows [title] (the marquee may tag a wrapper around its text). */
    private fun barShows(title: String): Boolean {
        val bar = hasTestTag("fst.nav.title")
        return rule.onAllNodes(hasText(title) and (bar or hasAnyAncestor(bar)), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

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

    // endregion

    @Test
    fun titleWaitsForScrollFooterFloatsAndPagingKeepsThePager() {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(
            route = DebugLaunch.parseRoute("songLeaderboard:s-alpha:Solo_Guitar"),
            profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"),
            stillBackground = true,
        )
        h.launch(debug, transport)
        h.waitForTag(footer)
        h.waitForTag("$prefix.row.${Fixtures.ACCOUNT_A.dropLast(2)}10")
        h.awaitAccessibilityTree(footer)

        // Before any scroll the in-page header carries the title; the bar is empty.
        assertTrue("song header missing", rule.onAllNodes(hasText("Alpha Tune"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        assertTrue("the bar shows the title before any scroll", !barShows("Alpha Tune"))

        // Reading order: header → rows → pinned score → pager (spec accessibility order). Around a
        // separating hinge (only without TalkBack: rememberSingleColumn drops the split under it) the
        // rows pane reads first, then the supporting pane's header → pinned score → pager.
        val order = h.readingOrder("song-leaderboard")
        fun at(label: String) = order.indexOfFirst { it.contains(label) }.also { assertTrue("$label not read in $order", it >= 0) }
        val firstRow = at("Synthetic Player 1,")
        val header = at("Alpha Tune")
        val pinned = at("#30,")
        val pager = at("Page 1 of 3")
        val split = h.exists("$prefix.supporting-pane")
        if (split) {
            assertTrue("supporting pane before the rows in $order", firstRow < header)
            assertTrue("header after the pinned score in $order", header < pinned)
        } else {
            assertTrue("header after the first row in $order", header < firstRow)
            assertTrue("pinned score before a row in $order", firstRow < pinned)
        }
        assertTrue("pager before the pinned score in $order", pinned < pager)

        // The pinned row is one 48 dp button that jumps to the player's page.
        val pinnedNode = visibleNodes(footer).first()
        var clickable = pinnedNode
        while (!clickable.isClickable && clickable.childCount == 1) clickable = clickable.getChild(0) ?: break
        assertEquals("Jump to your position", clickable.actionList.firstOrNull { it.id == AccessibilityNodeInfo.ACTION_CLICK }?.label?.toString())
        val minPx = 48 * rule.activity.resources.displayMetrics.density - 1
        assertTrue("pinned row under 48 dp", screenBox(clickable).height() >= minPx)

        // Scrolled: the bar takes the title, and no row the footer covers stays readable or touchable.
        // Around a hinge the header lives in the supporting pane (the list holds only the rows) and
        // never scrolls away, so the bar stays empty there.
        if (split) {
            assertTrue("the bar shows the title beside the supporting pane", !barShows("Alpha Tune"))
        } else {
            rule.onNode(hasTestTag("$prefix.list")).performScrollToIndex(1)
            rule.waitForIdle()
            // A window tall enough to show the whole board cannot scroll the header away.
            if (runCatching { rule.waitUntil(5_000) { !h.exists("$prefix.instrument") } }.isSuccess) {
                rule.waitUntil(10_000) { barShows("Alpha Tune") }
            }
        }
        val footerBox = screenBox(visibleNodes("$prefix.bottom-bar").first())
        val rows = visibleNodes("$prefix.row.")
        assertTrue("no rows visible after scrolling", rows.isNotEmpty())
        // Around a hinge the footer sits in the other pane; only rows in its column are checked.
        rows.filter { screenBox(it).right > footerBox.left && screenBox(it).left < footerBox.right }.forEach { row ->
            assertTrue("${row.viewIdResourceName} reaches under the footer (${screenBox(row).bottom} > ${footerBox.top})", screenBox(row).bottom <= footerBox.top + 1)
        }
        h.assertNothingStraddles(footer, "$prefix.pager", "$prefix.page-next")

        // Paging: the pinned score and pager stay put, readable and usable, while only the rows swap
        // to the spinner (#93; #190 owner decision B, like the web footer).
        val pagerBefore = bounds("$prefix.pager")
        val footerBefore = bounds(footer)
        h.tap("$prefix.page-next")
        h.waitForTag("$prefix.loading")
        assertTrue("pager left while loading", h.exists("$prefix.pager"))
        assertEquals("pager moved while loading", pagerBefore, bounds("$prefix.pager"))
        assertEquals("pinned score moved while loading", footerBefore, bounds(footer))
        assertTrue("pinned score left TalkBack while loading", visibleNodes(footer).isNotEmpty())
        nextPage.complete(Unit)
        rule.waitUntil(15_000) { rule.onAllNodes(hasContentDescription("Page 2 of 3"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        h.waitGone("$prefix.loading")
        h.waitForTag(footer)
        assertEquals("pager moved after paging", pagerBefore, bounds("$prefix.pager"))
        assertEquals("pinned score moved after paging", footerBefore, bounds(footer))
        h.assertAccessible()
    }
}
