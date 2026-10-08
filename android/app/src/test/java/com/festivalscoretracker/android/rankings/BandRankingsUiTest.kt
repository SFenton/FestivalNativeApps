package com.festivalscoretracker.android.rankings

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.testing.EmptyRegionAssertions.assertFillsAndCentres
import com.festivalscoretracker.android.testing.EmptyRegionAssertions.boundsOf
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// region Phone

/**
 * Band Rankings page states the issue #116 validation found uncovered: rows beneath the floating
 * pager, the full-page and inline failures with Retry, and the empty board.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class BandRankingsUiTest : LeaderboardsHarness() {
    private val path = "/api/rankings/bands/Band_Duets"

    private fun row(rank: Int) = "fst.band-rankings.row.${RankingsFixtures.accountId(1000 + rank)}:${RankingsFixtures.accountId(2000 + rank)}"

    /** Serves Band_Duets pages, failing while [fail] says so. */
    private fun serve(fail: () -> Boolean = { false }, body: (page: Int) -> String = { RankingsFixtures.bandRankings("Band_Duets", "totalscore", it, 25) }) {
        transport.onRaw(path) { request ->
            val page = Regex("[?&]page=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 1
            if (fail()) HttpResult(500, ByteArray(0)) else HttpResult(200, body(page).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
        }
    }

    @Test
    fun rowsBeneathTheFloatingPagerLeaveTouchAndTalkBack() {
        launch("bandRankings:Band_Duets")
        waitForTag(row(1))
        waitForDescription("Page 1 of 2")
        val list = node("fst.band-rankings.list").fetchSemanticsNode().boundsInRoot
        val footer = node("fst.band-rankings.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue("the list $list ends at the pager's top $footer", list.bottom <= footer.top + 1f)
        node(row(1)).assertIsDisplayed()
        // The 25th row lies far below the pager on a phone: hidden, not reachable behind it.
        node(row(25)).assertIsNotDisplayed()
    }

    @Test
    fun fullFailureRetriesIntoTheBoard() {
        var fail = true
        serve(fail = { fail })
        launch("bandRankings:Band_Duets")
        waitForText("Band rankings unavailable")
        assertFalse(exists("fst.band-rankings.list"))
        assertFalse(exists("fst.band-rankings.population"))
        fail = false
        click("fst.service-status.retry")
        waitForTag(row(1))
        waitForText("30 ranked bands")
    }

    @Test
    fun failedPageKeepsTheBoardAndRetriesInline() {
        var fail = false
        serve(fail = { fail })
        launch("bandRankings:Band_Duets")
        waitForTag(row(1))
        fail = true
        click("fst.band-rankings.page-next")
        waitForTag("fst.service-status.inline")
        // The page information and pager stay; the rows give way to the inline failure.
        assertTrue(exists("fst.band-rankings.population"))
        assertTrue(exists("fst.band-rankings.pager"))
        assertFalse(exists(row(1)))
        fail = false
        rule.onAllNodesWithText("Retry", useUnmergedTree = true)[0].performClick()
        settle()
        waitForTag(row(26))
        waitForDescription("Page 2 of 2")
    }

    @Test
    fun emptyBoardSaysSo() {
        serve(body = { page -> """{"bandType":"Band_Duets","rankBy":"totalscore","page":$page,"pageSize":25,"totalTeams":0,"entries":[]}""" })
        launch("bandRankings:Band_Duets")
        waitForText("No ranked bands yet.")
        waitForText("0 ranked bands")
        assertTrue(node("fst.band-rankings.page-next").fetchSemanticsNode().config.contains(SemanticsProperties.Disabled))
        assertEmptyFillsTheBoard()
    }

    /** Issue #377: on a tall tablet window the empty board still centres between the population and the pager. */
    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun emptyBoardCentresOnATallWindow() {
        serve(body = { page -> """{"bandType":"Band_Duets","rankBy":"totalscore","page":$page,"pageSize":25,"totalTeams":0,"entries":[]}""" })
        launch("bandRankings:Band_Duets")
        waitForText("No ranked bands yet.")
        waitForText("0 ranked bands")
        assertEmptyFillsTheBoard()
    }

    /** The empty state fills the rows' region between the population line and the floating pager (12 dp item gaps), text centred. */
    private fun assertEmptyFillsTheBoard() {
        settle()
        rule.assertFillsAndCentres(
            "fst.band-rankings.empty",
            above = rule.boundsOf("fst.band-rankings.population"),
            gapAbove = 12f,
            belowTop = rule.boundsOf("fst.band-rankings.bottom-bar").top,
            gapBelow = 12f,
            firstText = "No ranked bands yet.",
            lastText = "No ranked bands yet.",
            density = rule.density.density,
        )
    }
}

// endregion

// region Row layout

/**
 * Band Rankings row layout by pane width, measured with real text: one line where the roster
 * keeps its minimum width; stacked in a pane too narrow for that (a half-opened book fold's list
 * pane is about 260 dp, and the fixtures' 10-digit totals already leave a 411 dp phone row too
 * little), so the roster keeps its width instead of collapsing to nothing (issue #116).
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BandRankingsRowLayoutUiTest : LeaderboardsHarness() {
    private val first = "fst.band-rankings.row.${RankingsFixtures.accountId(1001)}:${RankingsFixtures.accountId(2001)}"

    private fun firstRowHeight(): Float {
        launch("bandRankings:Band_Duets")
        waitForTag(first)
        settle()
        return node(first).fetchSemanticsNode().boundsInRoot.height / rule.density.density
    }

    @Test
    @Config(qualifiers = "w600dp-h960dp-xxhdpi")
    fun mediumPaneRowsStayOnOneLine() {
        val height = firstRowHeight()
        assertTrue("one-line row is $height dp tall", height < 60f)
    }

    @Test
    @Config(qualifiers = "w300dp-h891dp-xxhdpi")
    fun narrowPaneRowsStackRatherThanHideTheRoster() {
        val height = firstRowHeight()
        assertTrue("stacked row is $height dp tall", height > 70f)
        // Stacking keeps the pager clear and every row inside the list.
        val list = node("fst.band-rankings.list").fetchSemanticsNode().boundsInRoot
        val footer = node("fst.band-rankings.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue(list.bottom <= footer.top + 1f)
        val row = node(first).fetchSemanticsNode().boundsInRoot
        assertTrue("row $row stays inside the list $list", row.left >= list.left && row.right <= list.right)
    }
}

// endregion

// region Large text

/** Band Rankings at font scale 2.0 on a phone: stacked rows, still clear of the floating pager. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
class BandRankingsLargeTextUiTest : LeaderboardsHarness() {
    @Test
    fun stackedRowsKeepFullNamesAndClearThePager() {
        launch("bandRankings:Band_Duets")
        val first = "fst.band-rankings.row.${RankingsFixtures.accountId(1001)}:${RankingsFixtures.accountId(2001)}"
        waitForTag(first)
        waitForText("Member 1A + Unknown User")
        val list = node("fst.band-rankings.list").fetchSemanticsNode().boundsInRoot
        val footer = node("fst.band-rankings.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue(list.bottom <= footer.top + 1f)
        val row = node(first).fetchSemanticsNode().boundsInRoot
        assertTrue("row $row stays inside the list $list", row.left >= list.left && row.right <= list.right)
    }
}

// endregion
