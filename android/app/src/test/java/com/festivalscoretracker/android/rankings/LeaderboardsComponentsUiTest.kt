package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.testing.RankingsFixtures
import android.os.Looper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.click
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.navigation.toRoute
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.ui.leaderboards.AnchoredRowCard
import com.festivalscoretracker.android.ui.leaderboards.CardGridRow
import com.festivalscoretracker.android.ui.leaderboards.HingeSplit
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardsScreen
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardLayout
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.leaderboards.SyncRouteArguments
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Card, spotlight and layout states rendered directly with scriptable reads. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w320dp-h700dp-xhdpi")
class LeaderboardsComponentsUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val fake = FakeReads()
    private val settings = MutableStateFlow<AppSettings?>(
        AppSettings(selectedPlayer = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), visibleInstruments = setOf(Instrument.Lead)),
    )
    private val rankBy = MutableStateFlow(RankingMetric.Weighted)

    private fun settle() {
        repeat(6) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.waitForIdle()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun text(value: String) = rule.onAllNodesWithText(value, substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun overview(): LeaderboardsViewModel {
        val viewModel = LeaderboardsViewModel(fake.reads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        rule.setContent { LeaderboardsScreen(viewModel, isRoot = true) }
        settle()
        return viewModel
    }

    @Test
    fun emptyBoardsAndFailedBandsRenderInline() {
        fake.accounts = 0
        fake.failBands = FestivalApiException.HttpStatus(500)
        overview()
        rule.waitUntil(5_000) { settle(); text("No ranked Lead players yet.") }
        assertTrue(text("Not yet ranked") || exists("fst.leaderboards.card.Solo_Guitar.spotlight"))
        rule.onNodeWithTag("fst.leaderboards").performSemanticsAction(SemanticsActions.ScrollToIndex) { it(3) }
        settle()
        rule.waitUntil(5_000) { settle(); exists("fst.service-status.inline") }
        assertTrue(text("Duos rankings unavailable") || text("Trios rankings unavailable") || text("Quads rankings unavailable"))
        fake.failBands = null
        fake.accounts = RankingsFixtures.TOTAL_ACCOUNTS
        val retry = rule.onAllNodesWithText("Retry")[0]
        val bounds = retry.fetchSemanticsNode().boundsInRoot
        assertTrue("Retry is ${bounds.width}px wide", bounds.width >= 48 * 2)
        retry.performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(5_000) { settle(); !exists("fst.service-status.inline") }
    }

    @Test
    fun spotlightLoadingFailureAndRetry() {
        fake.holdOwnRow = CompletableDeferred()
        val viewModel = overview()
        rule.waitUntil(5_000) { settle(); exists("fst.leaderboards.card.Solo_Guitar.spotlight.loading") }
        fake.failOwnRow = FestivalApiException.HttpStatus(500)
        fake.holdOwnRow!!.complete(Unit)
        rule.waitUntil(5_000) { settle(); text("Your rank is unavailable") }
        viewModel.retrySpotlight(Instrument.Lead)
        rule.waitUntil(5_000) { settle(); exists("fst.leaderboards.card.Solo_Guitar.spotlight") }
        // Weighted is a percentile metric: rows show "Top N%" plus the Bayesian value.
        assertTrue(text("Top "))
        viewModel.refresh()
        settle()
        rule.waitUntil(5_000) { settle(); !viewModel.refreshing.value }
    }

    @Test
    fun selectedPlayerInTheTopTenIsHighlightedInPlace() {
        val inTopTen = RankingsFixtures.accountId(5)
        settings.value = settings.value!!.copy(selectedPlayer = SelectedPlayer(inTopTen, "Synthetic Player 5"))
        overview()
        val row = "fst.rankings.row.$inTopTen"
        rule.waitUntil(5_000) { settle(); exists(row) }
        val config = rule.onAllNodesWithTag(row, useUnmergedTree = true)[0].fetchSemanticsNode().config
        assertTrue(config[SemanticsProperties.ContentDescription].single().startsWith("Your rank, #5. Synthetic Player 5."))
        assertEquals("Open your statistics", config[SemanticsActions.OnClick].label)
        // Highlighted in place: no pinned row or loading row below the top ten.
        val card = "fst.leaderboards.card.Solo_Guitar"
        assertTrue(!exists("$card.spotlight") && !exists("$card.spotlight.loading") && !exists("$card.spotlight.unranked"))
    }

    @Test
    fun rankHistoryCardDrawsTheChartAndSwitchesCharts() {
        settings.value = settings.value!!.copy(visibleInstruments = setOf(Instrument.Lead, Instrument.Bass))
        rankBy.value = RankingMetric.TotalScore
        val viewModel = LeaderboardsViewModel(fake.historyReads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        rule.setContent { LeaderboardsScreen(viewModel, isRoot = true) }
        rule.waitUntil(5_000) { settle(); text("Rank History") && exists("fst.leaderboards.rank-history.picker") }
        rule.waitUntil(5_000) { settle(); rule.onAllNodesWithContentDescription("Rank history chart", substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        assertTrue(text("Total Score"))
        // The window pages and swipes like the profile chart; tapping a bar shows its detail.
        rule.onNodeWithTag("fst.leaderboards.rank-history.back-page").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        rule.onNodeWithTag("fst.leaderboards.rank-history.forward-entry").performSemanticsAction(SemanticsActions.OnClick)
        rule.onNodeWithTag("fst.leaderboards.rank-history.plot").performTouchInput { click(centerLeft.copy(x = 4f)) }
        settle()
        assertTrue(exists("fst.leaderboards.rank-history.detail"))
        rule.onNodeWithTag("fst.leaderboards.rank-history.plot").performTouchInput { swipeRight() }
        settle()
        rule.onNodeWithTag("fst.leaderboards.rank-history.picker.Solo_Bass").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(5_000) { settle(); fake.count("history:Solo_Bass:") == 1 }
        // The header sits above (outside) its card.
        rule.onNodeWithTag("fst.leaderboards").performScrollToNode(hasTestTag("fst.leaderboards.card.Solo_Guitar"))
        settle()
        val header = rule.onAllNodesWithText("Lead", useUnmergedTree = true).fetchSemanticsNodes().first { it.boundsInRoot.height > 0 }.boundsInRoot
        val card = rule.onNodeWithTag("fst.leaderboards.card.Solo_Guitar").fetchSemanticsNode().boundsInRoot
        assertEquals(card.top, header.top, 60f)
    }

    @Test
    fun rankHistoryFailureAndEmptyStates() {
        fake.failHistory = FestivalApiException.HttpStatus(500)
        val viewModel = LeaderboardsViewModel(fake.historyReads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        rule.setContent { LeaderboardsScreen(viewModel, isRoot = true) }
        rule.waitUntil(5_000) { settle(); text("Rank history unavailable") }
        viewModel.retryHistory(Instrument.Lead)
        rule.waitUntil(5_000) { settle(); !text("Rank history unavailable") }
    }

    @Test
    fun starsUseTheArtworkAndReadAsOneElement() {
        var stars by mutableIntStateOf(6)
        rule.setContent { StarRating(stars, Modifier.testTag("fst.stars")) }
        settle()
        assertEquals(listOf("Gold stars"), rule.onNodeWithTag("fst.stars").fetchSemanticsNode().config[SemanticsProperties.ContentDescription])
        stars = 1
        settle()
        assertEquals(listOf("1 star"), rule.onNodeWithTag("fst.stars").fetchSemanticsNode().config[SemanticsProperties.ContentDescription])
        stars = 4
        settle()
        assertEquals(listOf("4 stars"), rule.onNodeWithTag("fst.stars").fetchSemanticsNode().config[SemanticsProperties.ContentDescription])
        stars = 0
        settle()
        assertTrue(!exists("fst.stars"))
    }

    @Test
    fun routeArgumentsFollowTheBoard() {
        val handle = SavedStateHandle(mapOf("instrument" to "Solo_Guitar", "rankBy" to "totalscore", "page" to 1))
        var page by mutableIntStateOf(1)
        rule.setContent { SyncRouteArguments(handle, "rankBy" to "fcrate", "page" to page) }
        settle()
        assertEquals(FullRankingsRoute("Solo_Guitar", "fcrate", 1), handle.toRoute<FullRankingsRoute>())
        page = 3
        settle()
        assertEquals(3, handle.toRoute<FullRankingsRoute>().page)
    }

    @Test
    fun narrowPagerDropsFirstAndLast() {
        var page = 2
        rule.setContent { RankingsPager(page, 5, "fst.test", { page = it }) }
        settle()
        assertTrue(exists("fst.test.page-previous"))
        assertTrue(!exists("fst.test.page-first") && !exists("fst.test.page-last"))
        rule.onNodeWithTag("fst.test.page-next").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(3, page)
    }

    @Test
    fun hingeBoardsKeepRowsAndThePagerOnOppositeSides() {
        rule.setContent {
            Box(Modifier.width(300.dp).height(400.dp)) {
                RankingsBoardLayout(
                    hinge = HingeSplit(140.dp, 160.dp),
                    measure = Modifier,
                    padding = PaddingValues(),
                    listState = rememberLazyListState(),
                    idPrefix = "fst.t",
                    controls = { Text("info") },
                    footer = { AnchoredRowCard { Text("mine") } },
                    pager = { RankingsPager(1, 3, "fst.t", {}) },
                ) { item { Box(Modifier.fillMaxWidth().height(20.dp).testTag("row")) } }
            }
        }
        settle()
        val density = rule.onNodeWithTag("row").fetchSemanticsNode().layoutInfo.density.density
        val row = rule.onNodeWithTag("row").fetchSemanticsNode().boundsInRoot
        val pane = rule.onNodeWithTag("fst.t.supporting-pane").fetchSemanticsNode().boundsInRoot
        val pager = rule.onNodeWithTag("fst.t.pager").fetchSemanticsNode().boundsInRoot
        assertTrue(row.right <= 140 * density)
        assertTrue(pane.left >= 160 * density)
        // The pager is anchored to the bottom of the far pane, below the page information.
        assertTrue(pager.bottom > pane.bottom - 80 * density)
        assertTrue(text("info") && text("mine"))
    }

    @Test
    fun hingeRowsKeepCardsOffTheFold() {
        rule.setContent {
            Box(Modifier.width(300.dp)) {
                CardGridRow(
                    cards = listOf({ Box(Modifier.fillMaxWidth().height(20.dp).testTag("left")) }, { Box(Modifier.fillMaxWidth().height(20.dp).testTag("right")) }),
                    columns = 2,
                    hinge = HingeSplit(140.dp, 160.dp),
                )
            }
        }
        settle()
        val left = rule.onNodeWithTag("left").fetchSemanticsNode().boundsInRoot
        val right = rule.onNodeWithTag("right").fetchSemanticsNode().boundsInRoot
        val density = rule.onNodeWithTag("left").fetchSemanticsNode().layoutInfo.density.density
        assertTrue(left.right <= 140 * density)
        assertTrue(right.left >= 160 * density)
    }
}
