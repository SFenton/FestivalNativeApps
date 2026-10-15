package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import com.festivalscoretracker.android.ui.suggestions.SuggestionTokens
import kotlin.math.abs
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Suggestions on a real device (issue #112): ATF on the feed and the filter sheet, the
 * TalkBack reading order in logcat `FST_A11Y` and no card straddling a separating hinge
 * (`device.py test com.festivalscoretracker.android.journeys.SuggestionsAccessibilityJourneyTest --avd …`).
 * Issue #656: the "Climb Past {rival}" card reads only its title's rival and draws no badge
 * (`@DeviceCi`).
 */
@RunWith(AndroidJUnit4::class)
class SuggestionsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private fun launch() {
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
        )
        h.waitForTag("fst.suggestions.list")
    }

    @Test
    fun feedFilterAndReadingOrder() {
        h.enableAccessibilityChecks()
        launch()
        val order = h.readingOrder("suggestions")
        assertTrue("Filter missing from $order", order.any { it.startsWith("Filter Suggestions") })
        assertTrue("A card is missing from $order", order.any { it.contains("Synthetic Track") })
        // Filter-before-feed order is asserted on the semantics tree (SuggestionsUiTest) and with
        // real TalkBack (talkback_walk.py); this harness walk can split Compose's traversal chain.
        val cards = rule.onAllNodes(SemanticsMatcher("card") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true }, useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }.distinct()
        assertTrue("No cards", cards.isNotEmpty())
        h.assertNothingStraddles(*cards.toTypedArray())
        h.tap("fst.suggestions.filter-button")
        h.waitForTag("fst.suggestions.filter.done")
        h.readingOrder("suggestions-filter")
        h.tap("fst.suggestions.filter.done")
        h.waitGone("fst.suggestions.filter.done")
        h.assertAccessible()
    }

    /**
     * Issue #656: the seed-7 fixture's "Climb Past Rival rv-b" card (the fixture has two rivals,
     * rv-a and rv-b) lists only rv-b. TalkBack reads the heading, then each row naming rv-b and
     * never rv-a; no row has a separate badge stop or draws the rival-name badge, because the
     * title already names the rival. ATF runs on every step.
     */
    @DeviceCi
    @Test
    fun climbPastNamesOnlyItsRivalWithoutABadge() {
        h.enableAccessibilityChecks()
        launch()
        h.publishTalkBackTree()
        val list = "fst.suggestions.list"
        val card = "fst.suggestions.category.$CLIMB_PAST"
        val header = "fst.suggestions.header.$CLIMB_PAST"
        h.scrollTo(list, header)
        // Bring the heading near the top so its rows are on screen for the reading walk.
        val listTop = rule.onNodeWithTag(list).fetchSemanticsNode().boundsInRoot.top
        val headerTop = rule.onNodeWithTag(header).fetchSemanticsNode().boundsInRoot.top
        val viewport = rule.onNodeWithTag(list).fetchSemanticsNode().boundsInRoot.height
        rule.onNodeWithTag(list).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, headerTop - listTop - viewport / 4) }
        rule.waitForIdle()

        val rows = rule.onAllNodes(
            SemanticsMatcher("Climb Past row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.row.") == true } and
                hasAnyAncestor(hasTestTag(card)),
        ).fetchSemanticsNodes()
        assertTrue("Climb Past card has no rows", rows.isNotEmpty())
        rows.forEach { node ->
            val label = node.config[SemanticsProperties.ContentDescription].joinToString()
            assertTrue("Climb Past row does not name its rival: $label", label.endsWith(TITLE_RIVAL))
            assertFalse("Climb Past row names another rival: $label", label.contains(OTHER_RIVAL))
            val tag = node.config[SemanticsProperties.TestTag]
            val pixels = rule.onNode(hasTestTag(tag) and hasAnyAncestor(hasTestTag(card))).captureToImage().toPixelMap()
            assertFalse("rival-name badge drawn on $tag", (0 until pixels.width).any { x -> (0 until pixels.height).any { y -> near(pixels[x, y], SuggestionTokens.songRivalText) } })
        }

        val stops = h.readingStops("suggestions-climb-past", fresh = true)
        val heading = stops.indexOfFirst { it.isHeading && it.label.startsWith("Climb Past $TITLE_RIVAL") }
        assertTrue("Climb Past heading is not read: ${stops.map { it.label }}", heading >= 0)
        val after = stops.drop(heading + 1).takeWhile { !it.isHeading }
        val spokenRows = after.filter { it.isClickable && it.label.contains("Synthetic Track") }
        assertTrue("no Climb Past row is read after its heading: ${after.map { it.label }}", spokenRows.isNotEmpty())
        spokenRows.forEach {
            assertTrue("row read without its rival: ${it.label}", it.label.endsWith(TITLE_RIVAL))
            assertFalse("row read with another rival: ${it.label}", it.label.contains(OTHER_RIVAL))
        }
        assertTrue("a rival badge is a separate stop: ${after.map { it.label }}", after.none { it.label == TITLE_RIVAL || it.label == OTHER_RIVAL })
        h.assertAccessible()
    }

    private fun near(pixel: Color, target: Color, tolerance: Float = 14f / 255f) =
        abs(pixel.red - target.red) <= tolerance && abs(pixel.green - target.green) <= tolerance && abs(pixel.blue - target.blue) <= tolerance

    private companion object {
        const val CLIMB_PAST = "song_rival_pct_push"
        const val TITLE_RIVAL = "Rival rv-b"
        const val OTHER_RIVAL = "Rival rv-a"
    }
}
