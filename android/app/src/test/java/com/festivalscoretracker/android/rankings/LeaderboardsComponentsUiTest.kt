package com.festivalscoretracker.android.rankings

import android.os.Looper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.ui.leaderboards.CardGridRow
import com.festivalscoretracker.android.ui.leaderboards.HingeSplit
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardsScreen
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
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
