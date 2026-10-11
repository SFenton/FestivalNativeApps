package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.design.ViewAllLinkText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #343 accessibility (backfill #479): on a half-open book fold, full-line titles,
 * subtitles and section headers in hinge-splitting grids keep to the leading pane through the
 * shared `FoldLane` (section-headers R9/R10) instead of running across the hinge. Covered here
 * on the real accessibility tree for the three page types #343 changed on Android:
 *
 * - Rival Detail's "You vs. Rival" heading and summary (the reported case) wrap before the
 *   hinge while the category cards split at it; TalkBack reads heading → summary → first
 *   category heading → its 48 dp "View All".
 * - Leaderboards' "Bands" heading and its 48 dp Band Rankings button end before the hinge;
 *   TalkBack reads Bands → Band Rankings → the Duos card.
 * - Compete's Leaderboards and Rivals group headings stay off the hinge and are read
 *   immediately before their first card's heading. (They're short wrap-width text, so this
 *   guards placement and order; the two cases above are the ones a missing lane fails.)
 *
 * Each page is checked at 100% and 200% text: headers stay headings, text grows and isn't
 * clipped, the reading order holds and ATF (labels, 48 dp targets, contrast) finds no errors.
 * At 200% the grids drop to one column by design (`rememberSingleColumn`), so the hinge checks
 * run at 100%. Fixtures only. `@DeviceCi` runs it on a phone in `android-device` (text size,
 * reading order, ATF; the hinge checks pass trivially); `@HalfOpenFoldJourney` runs it in
 * `android-fold` on a half-open Pixel 9 Pro Fold, where [JourneyHarness.requireHingeWhenAsked]
 * fails without a hinge. Locally: `device.py test
 * com.festivalscoretracker.android.journeys.FoldLaneAccessibilityJourneyTest --avd
 * FST_Book_Fold --posture half --runner-arg fstRequireHinge=true`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
@HalfOpenFoldJourney
class FoldLaneAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Helpers

    private fun node(tag: String): SemanticsNode = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first()

    private fun text(node: SemanticsNode): String = node.config.getOrNull(SemanticsProperties.Text).orEmpty().joinToString("") { it.text }

    private fun bounds(tag: String): Rect = node(tag).boundsInWindow

    private fun isHeadingNode(node: SemanticsNode) = node.config.contains(SemanticsProperties.Heading)

    /** The first separating vertical hinge, or null on phones and flat folds. */
    private fun hinge(): Rect? = h.hinges().firstOrNull()

    /**
     * Assert [tag] is one labelled Button at least 48 dp in both directions.
     *
     * @param tag Test tag.
     * @param name What the node is, for messages.
     */
    private fun assertButtonTarget(tag: String, name: String) {
        val button = node(tag)
        assertEquals("$name is not a Button", Role.Button, button.config.getOrNull(SemanticsProperties.Role))
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$name is ${button.size} px, under 48 dp", button.size.width >= min && button.size.height >= min)
    }

    /**
     * Assert [tag] (and every text under it) ends before the hinge's leading edge.
     *
     * @param hinge Hinge bounds in window pixels.
     * @param tags Test tags.
     */
    private fun assertLeadingPane(hinge: Rect, vararg tags: String) {
        tags.forEach { tag ->
            val box = bounds(tag)
            assertTrue("$tag [${box.left}, ${box.right}] runs past the hinge at ${hinge.left}", box.right <= hinge.left + 1f)
        }
    }

    /**
     * No text in [tag] (the node itself or its descendants) is cut off: each line fits the
     * node's width, the paragraph its height, and nothing is ellipsized.
     *
     * @param tag Test tag of the region.
     * @param state Configuration, for messages.
     * @return Line count and first-line height (px) per text, in tree order. Line height,
     *   unlike box height, grows with text size even when a wider single column unwraps it.
     */
    private fun assertNoClippedText(tag: String, state: String): List<Pair<Int, Float>> {
        val texts = rule.onAllNodes(
            (hasTestTag(tag) or hasAnyAncestor(hasTestTag(tag))) and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult),
            useUnmergedTree = true,
        )
        val lines = mutableListOf<Pair<Int, Float>>()
        texts.fetchSemanticsNodes().indices.forEach { i ->
            val layouts = mutableListOf<TextLayoutResult>()
            texts[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val label = text(texts[i].fetchSemanticsNode())
            layouts.forEach { layout ->
                val range = 0 until layout.lineCount
                assertFalse("$state: \"$label\" is wider than its box", range.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
                assertFalse("$state: \"$label\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
                assertFalse("$state: \"$label\" is ellipsized", range.any { layout.isLineEllipsized(it) })
                lines += layout.lineCount to (layout.getLineBottom(0) - layout.getLineTop(0))
            }
        }
        assertTrue("$state: no text under $tag", lines.isNotEmpty())
        return lines
    }

    /**
     * Assert [heading] is read once, directly before [next] (decorative icons in between are
     * hidden from TalkBack), so a header is never read after or apart from what it introduces.
     *
     * @param order Reading order.
     * @param heading Heading label.
     * @param next The stop that must follow it.
     * @param config Configuration, for messages.
     */
    private fun assertReadDirectlyBefore(order: List<String>, heading: String, next: String, config: String) {
        val at = order.indexOf(next)
        assertTrue("$config: TalkBack never reaches \"$next\": $order", at >= 0)
        assertEquals("$config: \"$heading\" is not read directly before \"$next\": $order", heading, order.getOrNull(at - 1))
    }

    // endregion

    // region Rival Detail

    /**
     * The reported #343 case: Rival Detail's "Synthetic Player vs. Synthetic Rival" heading and
     * its summary wrap inside the leading pane while the category cards split at the hinge.
     */
    @Test
    fun rivalDetailHeaderStaysInTheLeadingPaneAndReadsFirst() {
        var scale by mutableFloatStateOf(1f)
        val player = SelectedPlayer(RivalsFixtures.PLAYER, PLAYER_NAME)
        val rival = RivalsFixtures.RIVALS[1]
        val transport = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        h.enableAccessibilityChecks()
        val route = RivalRoutes.detail(rival, RIVAL_NAME, RivalScopes.song(listOf(Instrument.Lead)))
        h.launch(DebugLaunch(route = route, profile = player, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag(RIVAL_TITLE)
        h.requireHingeWhenAsked()
        h.publishTalkBackTree()
        val closest = RivalCategorization.title("closest_battles")
        val spokenViewAll = ViewAllLinkText.spoken(closest)
        val titleHeights = mutableListOf<Float>()
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "text ${(s * 100).toInt()}%"
            h.waitForTag(RIVAL_SEE_ALL)
            h.awaitAccessibilityTree(present = RIVAL_SEE_ALL)
            val title = node(RIVAL_TITLE)
            assertEquals("$PLAYER_NAME vs. $RIVAL_NAME", text(title))
            assertTrue("$config: the Rival Detail header is not a heading", isHeadingNode(title))
            assertButtonTarget(RIVAL_SEE_ALL, "$config: View All: $closest")
            val lines = assertNoClippedText(RIVAL_TITLE, "$config title")
            assertNoClippedText(RIVAL_SUMMARY, "$config summary")
            titleHeights += lines.first().second

            val fold = hinge()
            if (s == 1f && fold != null) {
                val categories = rule.onAllNodes(categoryMatcher(), useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInWindow }
                assertTrue(
                    "$config: the category cards don't split at the hinge ${fold.left}..${fold.right}: $categories",
                    categories.any { it.right <= fold.left } && categories.any { it.left >= fold.right },
                )
                // Without FoldLane the full-line header spans both panes and this title crosses the fold.
                assertLeadingPane(fold, RIVAL_TITLE, RIVAL_SUMMARY)
                assertTrue("$config: the title should wrap in the leading pane (lines $lines)", lines.first().first > 1)
            }
            h.assertNothingStraddles(RIVAL_SEE_ALL)

            val order = h.readingOrder("rival-detail-fold-$config", fresh = true)
            val iTitle = order.indexOf(text(title))
            val iSummary = order.indexOf(text(node(RIVAL_SUMMARY)))
            val iClosest = order.indexOf(closest)
            val iViewAll = order.indexOf(spokenViewAll)
            assertTrue("$config: TalkBack misses the header, summary, $closest or its View All: $order", listOf(iTitle, iSummary, iClosest, iViewAll).all { it >= 0 })
            assertTrue("$config: Rival Detail's header is not read first: $order", iTitle < iSummary && iSummary < iClosest && iClosest < iViewAll)
        }
        assertTrue("200% text did not grow the header lines ($titleHeights px)", titleHeights[1] > titleHeights[0])
        h.assertAccessible()
    }

    private fun categoryMatcher() = SemanticsMatcher("rival detail category card") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.rival-detail.category.") == true
    }

    // endregion

    // region Leaderboards

    /** Section-headers R10: the Leaderboards "Bands" header and Band Rankings stay left of the hinge. */
    @Test
    fun leaderboardsBandsHeaderStaysInTheLeadingPaneAndReadsBeforeTheBands() {
        var scale by mutableFloatStateOf(1f)
        val transport = RankingsFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        )
        val selected = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = selected, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag(LEADERBOARDS)
        h.requireHingeWhenAsked()
        h.publishTalkBackTree()
        val duos = BandType.entries.first()
        val headerHeights = mutableListOf<Float>()
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "text ${(s * 100).toInt()}%"
            // Scrolling a lazy list to an item puts it at the top, with the Duos card below it.
            rule.waitUntil(15_000) {
                runCatching { rule.onNodeWithTag(LEADERBOARDS).performScrollToNode(hasTestTag(BANDS_HEADER)) }.isSuccess && h.exists(BANDS_HEADER)
            }
            rule.waitForIdle()
            h.awaitAccessibilityTree(present = BANDS_LINK)
            val heading = rule.onAllNodes(isHeading() and hasAnyAncestor(hasTestTag(BANDS_HEADER)), useUnmergedTree = true).fetchSemanticsNodes()
            assertEquals("$config: the Bands header has no single heading", listOf("Bands"), heading.map(::text))
            assertButtonTarget(BANDS_LINK, "$config: Band Rankings")
            headerHeights += assertNoClippedText(BANDS_HEADER, config).first().second

            val fold = hinge()
            if (s == 1f && fold != null) {
                // Without FoldLane the header row fills the line and its button sits across the fold.
                assertLeadingPane(fold, BANDS_HEADER, BANDS_LINK)
                if (h.exists("$BAND_CARD.${BandType.entries[1].wireId}")) {
                    val leading = bounds("$BAND_CARD.${duos.wireId}")
                    val trailing = bounds("$BAND_CARD.${BandType.entries[1].wireId}")
                    assertTrue("$config: band cards don't split at the hinge ($leading | $trailing)", leading.right <= fold.left && trailing.left >= fold.right)
                }
            }

            val order = h.readingOrder("leaderboards-bands-fold-$config", fresh = true)
            assertReadDirectlyBefore(order, "Bands", "Band Rankings", config)
            val iDuos = order.indexOf(duos.label)
            if (iDuos >= 0) assertTrue("$config: ${duos.label} is read before the Bands header: $order", iDuos > order.indexOf("Band Rankings"))
        }
        assertTrue("200% text did not grow the Bands header lines ($headerHeights px)", headerHeights[1] > headerHeights[0])
        h.assertAccessible()
    }

    // endregion

    // region Compete

    /** Compete's group headings stay off the hinge and introduce their first card. */
    @Test
    fun competeGroupHeadingsStayOffTheHingeAndIntroduceTheirCards() {
        var scale by mutableFloatStateOf(1f)
        val player = SelectedPlayer(CompeteFixtures.PLAYER, PLAYER_NAME)
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        val debug = if (compact) {
            DebugLaunch(section = FestivalSection.Compete, profile = player, stillBackground = true)
        } else {
            DebugLaunch(route = CompeteRoute, profile = player, stillBackground = true)
        }
        h.enableAccessibilityChecks()
        h.launch(debug, CompeteFixtures.transport(), fontScale = { scale })
        h.waitForTag(COMPETE_BOARDS)
        h.requireHingeWhenAsked()
        h.publishTalkBackTree()
        val groups = listOf(
            Triple(COMPETE_BOARDS, CompeteText.LEADERBOARDS, "fst.compete.leaderboard-card."),
            Triple(COMPETE_RIVALS, CompeteText.RIVALS, "fst.compete.rivals-card."),
        )
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "text ${(s * 100).toInt()}%"
            groups.forEach { (tag, title, cardPrefix) ->
                rule.waitUntil(15_000) {
                    runCatching { rule.onNodeWithTag(COMPETE_GRID).performScrollToNode(hasTestTag(tag)) }.isSuccess && h.exists(tag)
                }
                rule.waitForIdle()
                h.awaitAccessibilityTree(present = tag)
                val heading = node(tag)
                assertEquals(title, text(heading))
                assertTrue("$config: \"$title\" is not a heading", isHeadingNode(heading))
                assertNoClippedText(tag, "$config $title")
                hinge()?.takeIf { s == 1f }?.let { fold -> assertLeadingPane(fold, tag) }
                h.assertNothingStraddles(tag)

                // The first card after the heading: its own heading must be read right after the group's.
                val firstCard = rule.onAllNodes(cardMatcher(cardPrefix), useUnmergedTree = true).fetchSemanticsNodes()
                    .minByOrNull { it.boundsInWindow.top * 10_000 + it.boundsInWindow.left }
                assertTrue("$config: no card under \"$title\"", firstCard != null)
                val cardTag = firstCard!!.config[SemanticsProperties.TestTag]
                val cardHeading = rule.onAllNodes(isHeading() and hasAnyAncestor(hasTestTag(cardTag)), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()
                val order = h.readingOrder("compete-$title-fold-$config", fresh = true)
                if (cardHeading != null && text(cardHeading) in order) {
                    assertReadDirectlyBefore(order, title, text(cardHeading), config)
                } else {
                    assertTrue("$config: TalkBack never reaches \"$title\": $order", title in order)
                }
            }
        }
        h.assertAccessible()
    }

    private fun cardMatcher(prefix: String) = SemanticsMatcher("compete card $prefix") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true
    }

    // endregion

    private companion object {
        const val PLAYER_NAME = "Synthetic Player"

        /** `RivalsFixtures.detail`'s rival name. */
        const val RIVAL_NAME = "Synthetic Rival"
        const val RIVAL_TITLE = "fst.rival-detail.title"
        const val RIVAL_SUMMARY = "fst.rival-detail.summary"
        const val RIVAL_SEE_ALL = "fst.rival-detail.see-all.closest_battles"
        const val LEADERBOARDS = "fst.leaderboards"
        const val BANDS_HEADER = "fst.leaderboards.bands-header"
        const val BANDS_LINK = "fst.leaderboards.bands-link"
        const val BAND_CARD = "fst.leaderboards.band-card"
        const val COMPETE_GRID = "fst.compete.grid"
        const val COMPETE_BOARDS = "fst.compete.section.leaderboards"
        const val COMPETE_RIVALS = "fst.compete.section.rivals"
    }
}
