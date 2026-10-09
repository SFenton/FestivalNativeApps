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
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The full song band leaderboard (Duos/Trios/Quads) on a device, for the selected player's
 * pinned band (issues #306, #461): the band pinned above the pager is one labelled 48 dp
 * button whose TalkBack action names where it leads ("Jump to your band's position" while its
 * row is on another page, "Open band" once it is on screen, `leaderboard-row` R7); TalkBack
 * reads header → band size → rows → pinned band → pager; rows that scroll under the pinned
 * band leave the accessibility tree (scroll-edge); after the jump the band's own row reads
 * "Your band" and sits clear of the footer; every pager button is a labelled 48 dp button.
 * The same journey runs at 200 % text (the header, pinned band and page label grow without
 * clipping and the pager stays on screen), with Reduce Transparency and with Reduce Motion,
 * whose hard edge (scroll-edge R7) must still cut rows at the footer; under Reduce Motion the
 * jump also reveals the band's row at once (load-transition R6). ATF runs throughout and nothing
 * straddles a hinge. `@DeviceCi`: the `android-device` job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.SongBandLeaderboardJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class SongBandLeaderboardJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val prefix = "fst.song-band-leaderboard"
    private val footer = "$prefix.spotlight-footer"
    private val selectedRank = 40
    private val selectedRow = "$prefix.row.band-$selectedRank:$selectedRank"
    private val selectedPageFirstRow = "$prefix.row.band-26:26"
    private val held = CopyOnWriteArrayList<Pair<(String) -> Boolean, CompletableDeferred<Unit>>>()
    private val transport: FakeTransport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            beforeRespond = { request -> held.firstOrNull { (matches, _) -> matches(request.url) }?.second?.await() }
        },
    ).apply {
        // 60 Duos bands, the selected player's at #40 on page 2, so the pinned band starts as a jump.
        on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, selectedRank.takeIf { "accountId=${BandFixtures.PLAYER}" in request.url })
        }
    }

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

    private fun bounds(tag: String): Rect = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    private val minTarget get() = with(rule.density) { 48.dp.toPx() } - 1

    /**
     * The pinned band is one button (role, 48 dp, inside the window) whose click action TalkBack
     * announces as [label], both in Compose semantics and in the published accessibility node.
     */
    private fun assertPinnedBand(screen: String, label: String) {
        val node = rule.onAllNodes(hasTestTag(footer), useUnmergedTree = true).fetchSemanticsNodes().single()
        assertEquals("$screen: pinned band role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
        assertEquals("$screen: pinned band action", label, node.config.getOrNull(SemanticsActions.OnClick)?.label)
        val box = node.boundsInWindow
        assertTrue("$screen: pinned band $box under 48 dp", box.height >= minTarget)
        assertTrue("$screen: pinned band $box leaves the window", box.left >= 0f && box.right <= rule.activity.window.decorView.width + 1)
        rule.waitUntil(10_000) {
            visibleNodes(footer).any { n -> n.actionList.any { it.id == AccessibilityNodeInfo.ACTION_CLICK && it.label?.toString() == label } }
        }
    }

    /** Each shown pager button is a labelled button at least 48 dp square, inside the window. */
    private fun assertPagerTargets(screen: String) {
        val width = rule.activity.window.decorView.width
        mapOf("first" to "First page", "previous" to "Previous page", "next" to "Next page", "last" to "Last page").forEach { (id, label) ->
            val tag = "$prefix.page-$id"
            val node = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull() ?: return@forEach
            assertEquals("$screen: $tag label", label, node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
            assertEquals("$screen: $tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            val box = node.boundsInWindow
            assertTrue("$screen: $tag $box under 48 dp", box.width >= minTarget && box.height >= minTarget)
            assertTrue("$screen: $tag $box leaves the window", box.left >= 0f && box.right <= width + 1)
        }
    }

    /**
     * Every text node matching [matcher] is laid out at [scale] and fits its box: no line wider
     * than the box and no paragraph taller than it; no ellipsis unless [allowEllipsis].
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

    /** No visible row in the footer's column reaches under the pinned band and pager. */
    private fun assertRowsClearOfFooter(screen: String) {
        val footerBox = screenBox(visibleNodes("$prefix.bottom-bar").first())
        val rows = visibleNodes("$prefix.row.")
        assertTrue("$screen: no rows visible", rows.isNotEmpty())
        rows.filter { screenBox(it).right > footerBox.left && screenBox(it).left < footerBox.right }.forEach { row ->
            assertTrue("$screen: ${row.viewIdResourceName} reaches under the footer (${screenBox(row).bottom} > ${footerBox.top})", screenBox(row).bottom <= footerBox.top + 1)
        }
    }

    /** The selected band's page-2 read: held until [assertInstantReveal] releases it on a paused clock. */
    private fun isSelectedPage(url: String) = "/bands/Band_Duets" in url && Regex("[?&]offset=25(&|$)").containsMatchIn(url)

    /**
     * Reduce Motion (load-transition R6, `leaderboard-row` R7): the pinned band's jump reveals its
     * row without animation. With page 2's read held and the frame clock paused, the row must sit
     * clear of the footer within [REVEAL_FRAMES] frames of its page showing, then not move for a
     * second. The animated reveal waits for the row's staggered entrance (about 1.9 s) and then
     * scrolls, so it fails both checks.
     */
    private fun assertInstantReveal(screen: String) {
        val page = CompletableDeferred<Unit>().also { held += ::isSelectedPage to it }
        h.tap(footer)
        rule.waitUntil(10_000) { transport.requests.any { isSelectedPage(it.url) } }
        rule.mainClock.autoAdvance = false
        try {
            page.complete(Unit)
            val deadline = System.currentTimeMillis() + 15_000
            while (!h.exists(selectedPageFirstRow)) {
                assertTrue("$screen: page 2 never showed", System.currentTimeMillis() < deadline)
                rule.mainClock.advanceTimeByFrame()
                Thread.sleep(16)
            }
            repeat(REVEAL_FRAMES) { rule.mainClock.advanceTimeByFrame() }
            assertTrue("$screen: the band's row isn't composed $REVEAL_FRAMES frames after its page showed", h.exists(selectedRow))
            val row = bounds(selectedRow)
            assertTrue("$screen: row $row not revealed clear of the footer ${bounds(footer)} within $REVEAL_FRAMES frames", row.bottom <= bounds("$prefix.bottom-bar").top + 1)
            rule.mainClock.advanceTimeBy(1_000)
            assertEquals("$screen: the reveal kept animating", row, bounds(selectedRow))
        } finally {
            rule.mainClock.autoAdvance = true
        }
    }

    // endregion

    // region Journeys

    /** Device text size, effects on. */
    @Test
    fun pinnedBandIsALabelledButtonReadAfterTheRowsAndJumpsToItsRow() = journey("song-band-leaderboard")

    /** 200 % text: the header, pinned band and pager grow, stay unclipped and reachable. */
    @Test
    fun largeTextKeepsThePinnedBandAndPagerReadableAndReachable() = journey("song-band-leaderboard-font-2", scale = 2f)

    /** Reduce Transparency: the hard edge still hides rows under the pinned band from sight and TalkBack. */
    @Test
    fun reduceTransparencyStillCutsRowsAtThePinnedBand() = journey(
        "song-band-leaderboard-reduce-transparency",
        preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_TRANSPARENCY) to true)),
    )

    /**
     * Reduce Motion: the hard edge (scroll-edge R7) still hides rows under the pinned band, the
     * pinned band keeps its action, state and TalkBack place, and its jump reveals the band's row
     * at once (load-transition R6).
     */
    @Test
    fun reduceMotionCutsRowsAtThePinnedBandAndRevealsItsRowAtOnce() = journey(
        "song-band-leaderboard-reduce-motion",
        preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true)),
        instantReveal = true,
    )

    /**
     * The board journey: text scale, targets, reading order and the footer cut on page 1, then
     * the pinned band's jump to its own row on page 2.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param scale Font scale to render at, or null for the device's own.
     * @param preferences Settings store (accessibility modes).
     * @param instantReveal Also require the jump's reveal to land without animation (Reduce Motion).
     */
    private fun journey(screen: String, scale: Float? = null, preferences: MemoryPreferences = MemoryPreferences(), instantReveal: Boolean = false) {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(
            route = DebugLaunch.parseRoute("songBandLeaderboard:s-alpha:Band_Duets"),
            profile = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player"),
            stillBackground = true,
        )
        h.launch(debug, transport, preferences, fontScale = scale?.let { s -> { s } })
        h.waitForTag(footer)
        h.waitForTag("$prefix.row.band-1:1")
        h.awaitAccessibilityTree(footer)
        // Read with the allowlisted `accountId=` query only, never selected-profile headers.
        assertTrue(transport.requests.none { request -> request.headers.keys.any { it.startsWith("X-FST-Selected", ignoreCase = true) } })

        if (scale != null) {
            assertTextScaled(screen, hasText("Alpha Tune") and !hasAnyAncestor(hasTestTag("fst.nav.title")), scale)
            assertTextScaled(screen, hasAnyAncestor(hasTestTag(footer)), scale, allowEllipsis = true)
            assertTextScaled(screen, hasTestTag("$prefix.page-info"), scale)
        }
        assertPagerTargets(screen)
        // Its row is on page 2: the pinned band jumps there.
        assertPinnedBand(screen, SelectedRowLabels.JUMP_TO_BAND)

        // Reading order: header → band size → rows → pinned band → pager (spec accessibility order).
        val order = h.readingOrder(screen)
        fun at(label: String) = order.indexOfFirst { it.contains(label) }.also { assertTrue("$label not read in $order", it >= 0) }
        val header = at("Alpha Tune")
        val size = at("Duos")
        val firstRow = at("Rank 1,")
        val pinned = at("#$selectedRank,")
        val pager = at("Page 1 of 3")
        assertTrue("header before the band size in $order", header < size)
        assertTrue("pinned band after the header in $order", header < pinned)
        if (!h.exists("$prefix.controls-pane")) {
            assertTrue("band size before the first row in $order", size < firstRow)
            assertTrue("pinned band after the rows in $order", firstRow < pinned)
        }
        assertTrue("pager after the pinned band in $order", pinned < pager)
        assertFalse("the pinned band is announced as a row in $order", order.any { it.contains("Your band") })

        // Scrolled: rows under the pinned band leave sight and TalkBack. The page's rows are one
        // card item after the controls (owner #543, `leaderboard-row` R10), like the solo board's.
        if (!h.exists("$prefix.controls-pane")) {
            rule.onNode(hasTestTag("$prefix.list")).performScrollToIndex(1)
            rule.waitForIdle()
        }
        assertRowsClearOfFooter(screen)
        h.assertNothingStraddles(footer, "$prefix.pager", "$prefix.page-next")

        // Jump: page 2 shows the band's own row, revealed clear of the footer; the pinned band now opens it.
        val footerBefore = bounds(footer)
        if (instantReveal) assertInstantReveal(screen) else h.tap(footer)
        h.waitForTag(selectedRow)
        h.awaitAccessibilityTree(selectedRow)
        rule.waitUntil(15_000) {
            val row = visibleNodes(selectedRow).firstOrNull() ?: return@waitUntil false
            val bar = visibleNodes("$prefix.bottom-bar").firstOrNull() ?: return@waitUntil false
            screenBox(row).bottom <= screenBox(bar).top + 1
        }
        assertPinnedBand("$screen-page-2", SelectedRowLabels.OPEN_BAND)
        assertEquals("pinned band moved after the jump", footerBefore, bounds(footer))
        val revealed = h.readingOrder("$screen-page-2")
        val ownRow = revealed.indexOfFirst { it.contains("Your band, Rank $selectedRank,") }
        assertTrue("the band's row doesn't read \"Your band\" in $revealed", ownRow >= 0)
        val pinnedAgain = revealed.indexOfFirst { it.contains("#$selectedRank,") }
        assertTrue("its row before the pinned band in $revealed", h.exists("$prefix.controls-pane") || ownRow < pinnedAgain)
        assertRowsClearOfFooter("$screen-page-2")
        assertPagerTargets("$screen-page-2")
        h.assertAccessible()
    }

    // endregion

    private companion object {
        /** Frames (about 167 ms) the Reduce Motion reveal may take after the page shows: a few layout passes, no animation. */
        const val REVEAL_FRAMES = 10
    }
}
