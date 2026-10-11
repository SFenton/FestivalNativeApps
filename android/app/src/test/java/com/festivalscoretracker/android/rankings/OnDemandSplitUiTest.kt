package com.festivalscoretracker.android.rankings

import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature
import androidx.window.testing.layout.FoldingFeature as TestFoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.ui.search.GlobalSearchTags
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Shared steps for the on-demand split journeys (#583, `split-panes` Android variant). */
abstract class OnDemandSplitHarness : LeaderboardsHarness() {
    protected val lead = "fst.leaderboards.card.Solo_Guitar"

    protected fun count(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    protected fun bounds(tag: String) = node(tag).fetchSemanticsNode().boundsInWindow

    protected fun systemBack() {
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        settle()
    }

    protected fun openLeadRankings() {
        launch("leaderboards")
        waitForTag(lead)
        scrollTo("fst.leaderboards", "$lead.view-all")
        click("$lead.view-all")
    }

    protected fun inPane(tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag("fst.split.trailing")), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class OnDemandSplitLandscapeUiTest : OnDemandSplitHarness() {
    /** Leaderboards → View All opens Full Rankings beside the overview, meeting at the midpoint. */
    @Test
    fun viewAllOpensBesideTheOverviewAndBackClosesThePaneFirst() {
        openLeadRankings()
        waitForTag("fst.split.trailing")
        waitForTag("fst.full-rankings.population")
        assertTrue("Full Rankings is in the trailing pane", inPane("fst.full-rankings.population"))
        // The overview stays visible in the leading pane.
        assertTrue(exists(lead))
        val leading = bounds("fst.split.leading")
        val trailing = bounds("fst.split.trailing")
        // Flat: the panes meet at the content's midpoint with no band (beside the drawer).
        assertEquals(leading.right, trailing.left, 1f)
        assertEquals(leading.width, trailing.width, 2f)
        // No divider line at default contrast.
        assertEquals(0, count("fst.split.hairline"))
        // The pane root closes with Close; global actions appear once (in the leading page).
        assertTrue(inPane("fst.split.close"))
        assertEquals(1, count(GlobalSearchTags.OPEN))
        assertEquals(1, count("fst.nav.profile"))

        // Back closes the trailing pane first and keeps the overview.
        systemBack()
        rule.waitUntil(10_000) { settle(100); !exists("fst.split.trailing") }
        assertTrue(exists(lead))
        assertFalse(rule.activity.isFinishing)
    }

    /** The pane's Close button closes the pane, like Back. */
    @Test
    fun closeButtonClosesThePane() {
        openLeadRankings()
        waitForTag("fst.split.close")
        rule.onNode(hasTestTag("fst.split.close") and hasAnyAncestor(hasTestTag("fst.split.trailing")), useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { settle(100); !exists("fst.split.trailing") }
        assertTrue(exists(lead))
    }

    /** A second View All replaces the pane's board instead of stacking a second split. */
    @Test
    fun anotherViewAllReplacesThePaneContent() {
        openLeadRankings()
        waitForText("Lead Leaderboards")
        val bass = "fst.leaderboards.card.Solo_Bass"
        rule.onNode(hasTestTag("fst.leaderboards") and hasAnyAncestor(hasTestTag("fst.split.leading"))).performScrollToNode(hasTestTag("$bass.view-all"))
        settle()
        node("$bass.view-all").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        waitForText("Bass Leaderboards")
        assertEquals(1, count("fst.split.trailing"))
        // One Back closes the pane: the replaced board is not left underneath.
        systemBack()
        rule.waitUntil(10_000) { settle(100); !exists("fst.split.trailing") }
        assertTrue(exists(lead))
    }

    /** Song Detail → View All opens the song's board beside it, without repeating the song header (#342 variant). */
    @Test
    fun songDetailOpensTheBoardBesideItWithoutTheSongHeader() {
        launch("songs")
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTagFirst("fst.songs.row.s-alpha").performClick()
        waitForTag("fst.song-detail.intensity")
        rule.onNode(hasTestTag("fst.song-detail.list")).performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        settle()
        node("fst.song-detail.view-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.split.trailing")
        waitForTag("fst.song-leaderboard.list")
        assertTrue(inPane("fst.song-leaderboard.list"))
        // Song Detail already shows the song: the pane board names the instrument instead.
        assertFalse(inPane("fst.song-detail.header"))
        // The board line (instrument switcher) leads the pane; the bar takes the instrument, not the song, once it scrolls away.
        assertTrue(inPane("fst.song-leaderboard.instrument"))
        assertTrue(
            rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.split.trailing")) and hasText("Alpha", substring = true), useUnmergedTree = true)
                .fetchSemanticsNodes().none { node -> node.config.contains(androidx.compose.ui.semantics.SemanticsProperties.Heading) },
        )
        systemBack()
        rule.waitUntil(10_000) { settle(100); !exists("fst.split.trailing") }
        assertTrue(exists("fst.song-detail.intensity"))
        // Then Back leaves Song Detail.
        systemBack()
        waitForTag("fst.songs.row.s-alpha")
        assertFalse(exists("fst.song-detail.intensity"))
    }

    private fun androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, *>.onNodeWithTagFirst(tag: String) = onAllNodesWithTag(tag)[0]
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w800dp-h1280dp-port-xhdpi")
class OnDemandSplitPortraitUiTest : OnDemandSplitHarness() {
    /** Portrait tablets stay single-pane, like the Duo in portrait: View All pushes full width. */
    @Test
    fun portraitPushesFullWidth() {
        openLeadRankings()
        waitForTag("fst.full-rankings.population")
        assertEquals(0, count("fst.split.trailing"))
        assertFalse(exists(lead))
        click("fst.nav.back")
        waitForTag(lead)
    }
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w790dp-h840dp-xhdpi")
class OnDemandSplitBookFoldUiTest : OnDemandSplitHarness() {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    private fun fold(state: FoldingFeature.State) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(TestFoldingFeature(rule.activity, state = state, orientation = FoldingFeature.Orientation.VERTICAL))),
        )
        settle()
    }

    /** Book posture splits at the fold even though the window is taller than wide. */
    @Test
    fun halfOpenFoldSplitsAtTheHinge() {
        launch("leaderboards")
        fold(FoldingFeature.State.HALF_OPENED)
        waitForTag(lead)
        scrollTo("fst.leaderboards", "$lead.view-all")
        click("$lead.view-all")
        waitForTag("fst.split.trailing")
        waitForTag("fst.full-rankings.population")
        val hinge = rule.activity.window.decorView.width / 2f
        assertTrue(bounds("fst.split.leading").right <= hinge + 1f)
        assertTrue(bounds("fst.split.trailing").left >= hinge - 1f)
        assertEquals(0, count("fst.split.hairline"))
    }

    /** Flat and taller than wide: single pane, like the Duo held upright. */
    @Test
    fun flatPortraitFoldStaysSinglePane() {
        launch("leaderboards")
        fold(FoldingFeature.State.FLAT)
        openFromOverview()
        waitForTag("fst.full-rankings.population")
        assertEquals(0, count("fst.split.trailing"))
    }

    private fun openFromOverview() {
        waitForTag(lead)
        scrollTo("fst.leaderboards", "$lead.view-all")
        click("$lead.view-all")
    }
}
