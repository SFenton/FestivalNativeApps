package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.ui.design.viewAllSpokenName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #82 accessibility (backfill #435): Compete → View Full Leaderboards → Back. Returning
 * must leave TalkBack exactly where the page was: the same stops in the same order, the Lead
 * card in place and no loading placeholder, at 100% and 200% text, and also when a newer
 * publication refreshed Compete in place while the full board was open (#82's Android change).
 * The card's View Full Leaderboards button is one labelled 48 dp `Button` read after its rows.
 * ATF runs on every step. Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class CompeteReturnAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = CompeteFixtures.transport()
    private val player = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player")
    private val viewFull = hasTestTag(VIEW_FULL).and(hasAnyAncestor(hasTestTag(LEAD_CARD)))
    private val spokenViewFull = viewAllSpokenName(CompeteText.VIEW_FULL_LEADERBOARDS, Instrument.Lead.label)

    /** Compete as the user reaches it: the tab below 600 dp, the pushed route on wider windows. */
    private fun debug(): DebugLaunch {
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        return if (compact) {
            DebugLaunch(section = FestivalSection.Compete, profile = player, stillBackground = true)
        } else {
            DebugLaunch(route = CompeteRoute, profile = player, stillBackground = true)
        }
    }

    /** Scroll the grid until the Lead card's View Full Leaderboards button is composed. */
    private fun scrollToViewFull() {
        rule.waitUntil(15_000) {
            runCatching { rule.onNodeWithTag(GRID).performScrollToNode(viewFull) }.isSuccess &&
                rule.onAllNodes(viewFull).fetchSemanticsNodes().isNotEmpty()
        }
        rule.waitForIdle()
    }

    private fun leadCardBounds(): Rect = rule.onNodeWithTag(LEAD_CARD).fetchSemanticsNode().boundsInRoot

    /**
     * The reading order without the floating toolbar's Quick Links. Without a screen reader the
     * toolbar hides while the grid scrolls and the shell shows it again on every navigation
     * (`FestivalApp` `toolbarScroll.reset()`); under TalkBack it never hides, so it is not part of
     * what Back must keep.
     *
     * @param order Reading order.
     * @return The page's own stops.
     */
    private fun pageOrder(order: List<String>): List<String> = order.filterNot { it.startsWith(QUICK_LINKS) }

    /**
     * After Back the floating toolbar is shown again and read after the page content.
     *
     * @param order Reading order after Back.
     */
    private fun assertToolbarReadAfterPage(order: List<String>) {
        val toolbar = order.indexOfFirst { it.startsWith(QUICK_LINKS) }
        assertTrue("Quick Links is not read after Compete's content once Back shows it again: $order", toolbar > order.indexOf(spokenViewFull))
    }

    /**
     * Assert the button's TalkBack contract and size, and that the page reads it once, after
     * the Lead heading and the card's rows.
     *
     * @param order Reading order of the current window.
     * @param headingShown Whether the Lead heading must be on screen (and so read) too.
     * @return The button's height in pixels.
     */
    private fun assertViewFullButton(order: List<String>, headingShown: Boolean = true): Float {
        val node = rule.onNode(viewFull)
        node.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(spokenViewFull)))
        val size = node.fetchSemanticsNode().size
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("View Full Leaderboards is $size px, under 48 dp", size.width >= min && size.height >= min)
        val at = order.indexOf(spokenViewFull)
        assertTrue("TalkBack never reaches \"$spokenViewFull\": $order", at >= 0)
        assertEquals("\"$spokenViewFull\" is read more than once: $order", at, order.lastIndexOf(spokenViewFull))
        val heading = order.indexOfFirst { it == Instrument.Lead.label }
        // At 200% text the card is taller than the viewport, so its heading can be scrolled off.
        if (headingShown || heading >= 0) assertTrue("The Lead heading is not read before its button: $order", heading in 0 until at)
        return size.height.toFloat()
    }

    /**
     * Open the Lead full board, check Compete is not read behind it, go Back and return the
     * reading order once the accessibility tree shows Compete again.
     *
     * @param screen Reading-order log name.
     * @param whileAway Runs once the full board is up (for example, a publication change).
     * @return Compete's reading order after Back.
     */
    private fun openFullBoardAndReturn(screen: String, whileAway: () -> Unit = {}): List<String> {
        rule.onNode(viewFull).performSemanticsAction(SemanticsActions.OnClick)
        h.waitForTag(FULL_BOARD)
        h.awaitAccessibilityTree(present = FULL_BOARD, absent = LEAD_CARD)
        whileAway()
        val away = h.readingOrder("$screen-full-board", fresh = true)
        assertTrue("TalkBack still reads Compete behind the full board: $away", spokenViewFull !in away)
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
        h.waitForTag(LEAD_CARD)
        h.awaitAccessibilityTree(present = LEAD_CARD, absent = FULL_BOARD)
        assertTrue("Compete showed a loading placeholder on return", !h.exists("$LEAD_CARD.loading") && !h.exists(PAGE_LOADING))
        return h.readingOrder("$screen-returned", fresh = true)
    }

    /** At 100% and 200% text, Back from the full board restores Compete's stops, order and layout. */
    @Test
    fun returnKeepsReadingOrderAndLayoutAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(debug(), transport, fontScale = { scale })
        h.waitForTag(LEAD_CARD)
        val heights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            scrollToViewFull()
            val screen = "compete-return-${fontScale}x"
            val before = h.readingOrder(screen, fresh = true)
            heights += assertViewFullButton(before, headingShown = fontScale == 1f)
            val bounds = leadCardBounds()
            val after = openFullBoardAndReturn(screen)
            assertEquals("TalkBack reads Compete differently after Back at ${fontScale}x", pageOrder(before), pageOrder(after))
            assertToolbarReadAfterPage(after)
            assertEquals("The Lead card moved after Back at ${fontScale}x", bounds, leadCardBounds())
            assertViewFullButton(after, headingShown = fontScale == 1f)
        }
        assertTrue("200% text did not grow View Full Leaderboards ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /**
     * A newer publication seen on the full board refreshes Compete in place behind it (#82):
     * Back still shows the loaded cards with no placeholder, read in the same order.
     */
    @Test
    fun publicationRefreshWhileAwayKeepsReadingOrder() {
        h.enableAccessibilityChecks()
        h.launch(debug(), transport)
        h.waitForTag(LEAD_CARD)
        scrollToViewFull()
        val before = h.readingOrder("compete-publication", fresh = true)
        assertViewFullButton(before)
        val bounds = leadCardBounds()
        fun comboReads() = transport.requests.count { "/api/rankings/combo" in it.url }
        val combosBefore = comboReads()
        // The full board's read adopts publication 8; Compete, kept on the back stack, re-reads its boards in place.
        transport.publish(8)
        val after = openFullBoardAndReturn("compete-publication") {
            rule.waitUntil(15_000) { comboReads() > combosBefore }
            rule.waitForIdle()
        }
        assertTrue("Compete never refreshed for publication 8", comboReads() > combosBefore)
        assertEquals("TalkBack reads Compete differently after an in-place refresh", pageOrder(before), pageOrder(after))
        assertToolbarReadAfterPage(after)
        assertEquals("The Lead card moved after an in-place refresh", bounds, leadCardBounds())
        assertViewFullButton(after)
        h.assertAccessible()
    }

    private companion object {
        const val GRID = "fst.compete.grid"
        const val LEAD_CARD = "fst.compete.leaderboard-card.Solo_Guitar"
        const val VIEW_FULL = "fst.compete.view-full-leaderboards"
        const val FULL_BOARD = "fst.full-rankings.pager"
        const val PAGE_LOADING = "fst.compete.loading"

        /** The floating toolbar's Quick Links button label (`CompeteScreen` `rememberQuickLinks`). */
        const val QUICK_LINKS = "Quick Links"
    }
}
