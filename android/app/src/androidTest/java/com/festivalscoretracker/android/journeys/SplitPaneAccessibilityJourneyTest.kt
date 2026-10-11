package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
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
 * Issue #583 accessibility: Android's on-demand split (owner-approved `split-panes` variant, the
 * iPhone Duo's policy). Leaderboards → View All opens Full Rankings in a trailing pane:
 *
 * - **Half open (book posture):** the panes meet at the fold, nothing straddles it, and no
 *   divider is drawn. TalkBack reads the whole Leaderboards page before the pane, whose first
 *   stop is its Close button: a labelled 48 dp button. System Back closes the pane first and
 *   keeps the overview.
 * - **Flat:** the split applies only when the window is landscape and regular (the Duo's
 *   condition); a taller-than-wide inner screen pushes Full Rankings full width.
 * - **200% text:** a pane narrower than 360 text-scaled dp does not split, so an open pane
 *   becomes an ordinary full-width page in place (no lost state), and Back still returns to the
 *   overview.
 *
 * ATF (labels, 48 dp targets, contrast) finds no errors in any state. Postures are synthetic
 * vertical folds at the window centre ([WindowLayoutInfoPublisherRule]). Fixtures only.
 * Locally: `device.py test com.festivalscoretracker.android.journeys.SplitPaneAccessibilityJourneyTest
 * --avd FST_Book_Fold --posture half --runner-arg fstRequireHinge=true`.
 */
@RunWith(AndroidJUnit4::class)
@HalfOpenFoldJourney
class SplitPaneAccessibilityJourneyTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val transport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    // region Helpers

    private fun bounds(tag: String): Rect = rule.onAllNodesWithTagUnmerged(tag).first().boundsInWindow

    private fun androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, *>.onAllNodesWithTagUnmerged(tag: String): List<SemanticsNode> =
        onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes()

    private fun inPane(tag: String): Boolean =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(TRAILING)), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** The synthetic fold's x in window pixels. */
    private fun foldX(): Float = rule.activity.window.decorView.width / 2f

    private fun publish(state: State) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))),
        )
        rule.waitForIdle()
    }

    private fun openLeadRankings() {
        h.scrollTo(OVERVIEW, VIEW_ALL)
        h.tap(VIEW_ALL)
        h.waitForTag(POPULATION)
    }

    private fun systemBack() {
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
    }

    private fun indexOf(order: List<String>, label: String): Int = order.indexOfFirst { it == label || it.startsWith("$label, ") }

    /**
     * Assert no node with any of [tags] crosses the synthetic fold at [fold].
     *
     * @param fold The fold's x in window pixels.
     * @param tags Test tags.
     */
    private fun assertNothingStraddles(fold: Float, vararg tags: String) {
        tags.forEach { tag ->
            rule.onAllNodesWithTagUnmerged(tag).forEach { node ->
                val box = node.boundsInWindow
                assertTrue("$tag straddles the fold at $fold: $box", box.right <= fold + 1f || box.left >= fold - 1f)
            }
        }
    }

    /** Whether the flat window allows a split: landscape and at least 600 dp wide (the Duo's condition). */
    private fun flatSplits(): Boolean = rule.activity.resources.configuration.let { it.screenWidthDp > it.screenHeightDp && it.screenWidthDp >= 600 }

    // endregion

    @Test
    fun splitPaneStaysAccessibleHalfOpenFlatAndAtLargeText() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = LeaderboardsRoute, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag(LEAD)
        h.publishTalkBackTree()

        // Half open: the pane opens beside the overview at the fold.
        publish(State.HALF_OPENED)
        openLeadRankings()
        val fold = foldX()
        val twoPane = h.exists(TRAILING)
        val wide = rule.activity.resources.configuration.screenWidthDp >= 600
        // The publisher rule doesn't replay the synthetic fold to a new collector, so the fold job
        // (fstRequireHinge=true) demands the unfolded inner display instead of JourneyHarness.hinges().
        if (InstrumentationRegistry.getArguments().getString(JourneyHarness.REQUIRE_HINGE_ARG) == "true") {
            assertTrue("the fold job needs the unfolded inner display (≥ 600 dp)", wide)
        }
        if (wide) assertTrue("half open: View All did not open beside the overview", twoPane)
        if (twoPane) {
            assertTrue("half open: Full Rankings is not in the trailing pane", inPane(POPULATION))
            assertTrue("half open: the overview left the screen", h.exists(LEAD))
            assertTrue("half open: the leading pane ${bounds(LEADING)} runs past the fold $fold", bounds(LEADING).right <= fold + 1f)
            assertTrue("half open: the trailing pane ${bounds(TRAILING)} starts before the fold $fold", bounds(TRAILING).left >= fold - 1f)
            assertFalse("half open: a divider is drawn at the fold", h.exists(HAIRLINE))
            assertNothingStraddles(fold, CLOSE, LEAD, POPULATION)

            // Close: a labelled 48 dp button, first in the pane, read after the whole overview.
            assertEquals("Close role", Role.Button, rule.onAllNodes(hasTestTag(CLOSE)).fetchSemanticsNodes().first().config.getOrNull(SemanticsProperties.Role))
            h.awaitAccessibilityTree(present = CLOSE)
            h.assertTouchTarget("split-half-open", CLOSE)
            val order = h.readingOrder("split-half-open", fresh = true)
            val overview = indexOf(order, "Leaderboards")
            val closeAt = indexOf(order, "Close")
            assertTrue("half open: TalkBack never reaches the overview title or Close: $order", overview >= 0 && closeAt >= 0)
            assertTrue("half open: the pane is read before the overview's title: $order", overview < closeAt)
            assertTrue("half open: an overview card is read after the pane's Close: $order", order.drop(closeAt).none { it.startsWith("View All Rankings") })
            assertEquals("half open: global search shows twice", 1, rule.onAllNodesWithTagUnmerged(SEARCH).size)

            // Back closes the pane first and keeps the overview.
            systemBack()
            h.waitGone(TRAILING)
            assertTrue("Back left the overview", h.exists(LEAD))
            assertFalse(rule.activity.isFinishing)
        } else {
            systemBack()
            h.waitForTag(LEAD)
        }

        // Flat: the Duo's condition (landscape, regular) decides; a taller-than-wide screen pushes.
        publish(State.FLAT)
        openLeadRankings()
        assertEquals("flat: split shown ≠ the window's condition", flatSplits(), h.exists(TRAILING))
        systemBack()
        rule.waitUntil(15_000) { h.exists(LEAD) && !h.exists(TRAILING) }

        // 200% text, half open: an open pane becomes a full-width page in place.
        publish(State.HALF_OPENED)
        openLeadRankings()
        scale = 2f
        rule.waitUntil(15_000) { !h.exists(TRAILING) && h.exists(POPULATION) }
        rule.waitForIdle()
        assertFalse("200%: the overview stayed beside a page too narrow to split", h.exists(LEAD))
        h.awaitAccessibilityTree(present = POPULATION)
        systemBack()
        h.waitForTag(LEAD)
        h.assertAccessible()
    }

    private companion object {
        const val LEAD = "fst.leaderboards.card.Solo_Guitar"
        const val VIEW_ALL = "$LEAD.view-all"
        const val OVERVIEW = "fst.leaderboards"
        const val POPULATION = "fst.full-rankings.population"
        const val LEADING = "fst.split.leading"
        const val TRAILING = "fst.split.trailing"
        const val HAIRLINE = "fst.split.hairline"
        const val CLOSE = "fst.split.close"
        const val SEARCH = "fst.global-search.open"
    }
}
