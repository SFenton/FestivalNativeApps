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
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The solo song leaderboard on a device (issues #93, #190, #443): before any scroll the top bar
 * carries no title, and takes the song title once the in-page header has scrolled under it;
 * the pinned score and pager float at the bottom while rows beneath them leave the
 * accessibility tree (no visible row node overlaps the footer); TalkBack reads header → rows →
 * pinned score → pager; the pinned row is one 48 dp "Jump to your position" button and every
 * pager button is a labelled 48 dp button; and a page change keeps the pinned score and pager in
 * place while only the rows show the spinner. The same journey runs at 200 % text (the header,
 * pinned row and page label lay out at that scale without clipping, and the pager stays on
 * screen) and with Reduce Transparency, whose hard edge (scroll-edge R7) must still cut rows at
 * the footer. ATF runs throughout and nothing straddles a hinge. `@DeviceCi`: the `android-device`
 * job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.SongLeaderboardJourneyTest --avd …`).
 */
@DeviceCi
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

    /** Each shown pager button is a labelled button at least 48 dp square, inside the window. */
    private fun assertPagerTargets(screen: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val width = rule.activity.window.decorView.width
        mapOf("first" to "First page", "previous" to "Previous page", "next" to "Next page", "last" to "Last page").forEach { (id, label) ->
            val tag = "$prefix.page-$id"
            val node = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull() ?: return@forEach
            assertEquals("$screen: $tag label", label, node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
            assertEquals("$screen: $tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            val box = node.boundsInWindow
            assertTrue("$screen: $tag $box under 48 dp", box.width >= min && box.height >= min)
            assertTrue("$screen: $tag $box leaves the window", box.left >= 0f && box.right <= width + 1)
        }
    }

    /**
     * Every text node matching [matcher] is laid out at [scale] and fits its box: no line wider
     * than the box and no paragraph taller than it; no ellipsis unless [allowEllipsis] (score-row
     * names may shorten to keep their columns, like the board rows).
     */
    private fun assertTextScaled(screen: String, matcher: SemanticsMatcher, scale: Float, allowEllipsis: Boolean = false) {
        val nodes = rule.onAllNodes(matcher and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
        val count = nodes.fetchSemanticsNodes().size
        assertTrue("$screen: no text matches $matcher", count > 0)
        for (i in 0 until count) {
            val layouts = mutableListOf<TextLayoutResult>()
            nodes[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            val text = layout.layoutInput.text.text
            assertEquals("$screen: \"$text\" laid out at ${scale}x text", scale, layout.layoutInput.density.fontScale, 0.01f)
            val lines = 0 until layout.lineCount
            assertFalse("$screen: \"$text\" is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
            assertFalse("$screen: \"$text\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
            if (!allowEllipsis) assertFalse("$screen: \"$text\" is ellipsized", lines.any(layout::isLineEllipsized))
        }
    }

    // endregion

    // region Journeys

    /** Device text size, effects on: the fade above the footer (issue #93). */
    @Test
    fun titleWaitsForScrollFooterFloatsAndPagingKeepsThePager() = journey("song-leaderboard")

    /** 200 % text: the header, pinned score and pager grow, stay unclipped and reachable (#443). */
    @Test
    fun largeTextKeepsTheHeaderPinnedScoreAndPagerReadableAndReachable() = journey("song-leaderboard-font-2", scale = 2f)

    /** Reduce Transparency: the hard edge still hides rows under the footer from sight and TalkBack (#443). */
    @Test
    fun reduceTransparencyStillCutsRowsAtTheFooter() = journey(
        "song-leaderboard-reduce-transparency",
        preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_TRANSPARENCY) to true)),
    )

    /**
     * The board journey: title, reading order, targets, the footer cut, then a held page change.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param scale Font scale to render at, or null for the device's own.
     * @param preferences Settings store (accessibility modes).
     */
    private fun journey(screen: String, scale: Float? = null, preferences: MemoryPreferences = MemoryPreferences()) {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(
            route = DebugLaunch.parseRoute("songLeaderboard:s-alpha:Solo_Guitar"),
            profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"),
            stillBackground = true,
        )
        h.launch(debug, transport, preferences, fontScale = scale?.let { s -> { s } })
        h.waitForTag(footer)
        h.waitForTag("$prefix.row.${Fixtures.ACCOUNT_A.dropLast(2)}10")
        h.awaitAccessibilityTree(footer)

        // Before any scroll the in-page header carries the title; the bar is empty.
        assertTrue("song header missing", rule.onAllNodes(hasText("Alpha Tune"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        assertTrue("the bar shows the title before any scroll", !barShows("Alpha Tune"))
        if (scale != null) {
            assertTextScaled(screen, hasText("Alpha Tune") and !hasAnyAncestor(hasTestTag("fst.nav.title")), scale)
            assertTextScaled(screen, hasAnyAncestor(hasTestTag(footer)), scale, allowEllipsis = true)
            assertTextScaled(screen, hasTestTag("$prefix.page-info"), scale)
        }
        assertPagerTargets(screen)

        // Reading order: header → rows → pinned score → pager (spec accessibility order). Around a
        // separating hinge (only without TalkBack: rememberSingleColumn drops the split under it) the
        // rows pane reads first, then the supporting pane's header → pinned score → pager.
        val order = h.readingOrder(screen)
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
        assertPagerTargets("$screen-page-2")
        h.assertAccessible()
    }

    // endregion
}
