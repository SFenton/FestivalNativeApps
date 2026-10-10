package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
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
import com.festivalscoretracker.android.core.compete.CompeteScopes
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.ui.design.ViewAllLinkText
import com.festivalscoretracker.android.ui.design.viewAllSpokenName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #602 accessibility: a combo leaderboard card on Compete ("Lead + Bass + Drums + Tap
 * Vocals") offers the same View All link and View Full Leaderboards button as a single
 * instrument's card (`view-all-cta` R4): the link reads "View All: <combo>" right after the
 * card's heading, the button is one labelled 48 dp `Button` read once after the rows, and
 * both grow with 200% text. The button opens the combo's Full Rankings, whose title names the
 * combo and offers Rank By but no instrument picker; Back returns to the card. ATF runs on
 * every step. Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class CompeteComboBoardAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = CompeteFixtures.transport()
    private val player = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player")
    private val combo = CompeteScopes.resolve(Instrument.entries).first()
    private val card = "fst.compete.leaderboard-card.${combo.key}"
    private val viewFull = hasTestTag(VIEW_FULL).and(hasAnyAncestor(hasTestTag(card)))
    private val spokenViewFull = viewAllSpokenName(CompeteText.VIEW_FULL_LEADERBOARDS, combo.label)
    private val spokenSeeAll = ViewAllLinkText.spoken(combo.label)

    /** Compete as the user reaches it: the tab below 600 dp, the pushed route on wider windows. */
    private fun debug(): DebugLaunch {
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        return if (compact) {
            DebugLaunch(section = FestivalSection.Compete, profile = player, stillBackground = true)
        } else {
            DebugLaunch(route = CompeteRoute, profile = player, stillBackground = true)
        }
    }

    /** Scroll the grid until the combo card's View Full Leaderboards button is composed. */
    private fun scrollToViewFull() {
        rule.waitUntil(15_000) {
            runCatching { rule.onNodeWithTag(GRID).performScrollToNode(viewFull) }.isSuccess &&
                rule.onAllNodes(viewFull).fetchSemanticsNodes().isNotEmpty()
        }
        rule.waitForIdle()
    }

    /**
     * Assert the button's TalkBack contract and 48 dp target.
     *
     * @return The button's height in pixels.
     */
    private fun assertViewFullButton(): Float {
        val node = rule.onNode(viewFull)
        node.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(spokenViewFull)))
        val size = node.fetchSemanticsNode().size
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("View Full Leaderboards is $size px, under 48 dp", size.width >= min && size.height >= min)
        return size.height.toFloat()
    }

    /** At 100% and 200% text the combo card reads heading → View All → rows → View Full Leaderboards and opens its board. */
    @Test
    fun comboCardOffersViewAllAndOpensItsFullBoard() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(debug(), transport, fontScale = { scale })
        h.waitForTag(card)
        val heights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            rule.onNodeWithTag(GRID).performScrollToNode(hasTestTag(card))
            rule.waitForIdle()
            h.waitForTag(SEE_ALL + combo.key)
            rule.onNodeWithTag(SEE_ALL + combo.key)
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(spokenSeeAll)))
            h.assertTouchTarget("compete-combo-${fontScale}x", SEE_ALL + combo.key)
            val top = h.readingOrder("compete-combo-header-${fontScale}x", fresh = true)
            val heading = top.indexOf(combo.label)
            val link = top.indexOf(spokenSeeAll)
            assertTrue("TalkBack never reaches \"$spokenSeeAll\": $top", link >= 0)
            assertEquals("\"$spokenSeeAll\" is read more than once: $top", link, top.lastIndexOf(spokenSeeAll))
            assertTrue("The combo heading is not read right before its View All: $top", heading in 0 until link)

            scrollToViewFull()
            heights += assertViewFullButton()
            val order = h.readingOrder("compete-combo-button-${fontScale}x", fresh = true)
            val at = order.indexOf(spokenViewFull)
            assertTrue("TalkBack never reaches \"$spokenViewFull\": $order", at >= 0)
            assertEquals("\"$spokenViewFull\" is read more than once: $order", at, order.lastIndexOf(spokenViewFull))
            if (spokenSeeAll in order) assertTrue("View Full Leaderboards is read before the header link: $order", order.indexOf(spokenSeeAll) < at)
        }
        assertTrue("200% text did not grow View Full Leaderboards ($heights px)", heights[1] > heights[0])
        h.assertAccessible()

        scale = 1f
        rule.waitForIdle()
        scrollToViewFull()
        rule.onNode(viewFull).performSemanticsAction(SemanticsActions.OnClick)
        h.waitForTag(FULL_BOARD)
        h.waitForTag(TITLE_ICON + combo.key)
        h.awaitAccessibilityTree(present = FULL_BOARD, absent = card)
        val board = h.readingOrder("combo-full-rankings", fresh = true)
        assertTrue("The combo board's title does not name the combo: $board", board.any { "${combo.label} Leaderboards" in it })
        assertTrue("TalkBack still reads Compete behind the combo board: $board", spokenViewFull !in board)
        assertFalse("A combo board offers an instrument picker", h.exists(INSTRUMENT_MENU))
        h.assertAccessible()

        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
        h.waitForTag(card)
        h.awaitAccessibilityTree(present = card, absent = FULL_BOARD)
        assertTrue("Compete showed a loading placeholder on return", !h.exists("$card.loading") && !h.exists(PAGE_LOADING))
    }

    private companion object {
        const val GRID = "fst.compete.grid"
        const val VIEW_FULL = "fst.compete.view-full-leaderboards"
        const val SEE_ALL = "fst.compete.board.see-all."
        const val FULL_BOARD = "fst.full-rankings.pager"
        const val TITLE_ICON = "fst.full-rankings.title-icon."
        const val INSTRUMENT_MENU = "fst.full-rankings.instrument-menu"
        const val PAGE_LOADING = "fst.compete.loading"
    }
}
