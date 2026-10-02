package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rankings.RankingSpotlightPlacement
import com.festivalscoretracker.android.core.rankings.RankingSpotlightSource
import com.festivalscoretracker.android.data.rankings.RankingsPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.FullRankingsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadSwap
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Full rankings

/**
 * `/leaderboards/all`: one instrument's paginated rankings. The instrument and
 * Rank By pickers are top-app-bar actions next to search; the selected player is
 * highlighted in place or pinned above the bottom-anchored pager, with "Your Page"
 * to jump to their page (native addition; the web footer only links to the profile).
 *
 * @param viewModel Board logic.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun FullRankingsScreen(viewModel: FullRankingsViewModel) {
    val instrument by viewModel.instrument.collectAsStateWithLifecycle()
    val metric by viewModel.metric.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val selected by viewModel.selectedAccountId.collectAsStateWithLifecycle()
    val visible by viewModel.visibleInstruments.collectAsStateWithLifecycle()
    val spotlight by viewModel.spotlight.collectAsStateWithLifecycle()
    val navigate = LocalShellActions.current.navigate
    val listState = rememberLazyListState()
    val current by viewModel.displayed.collectAsStateWithLifecycle()
    val totalPages = current?.rankings?.pageCount ?: 1
    // Reloads (chart, Rank By, page) fade the rows out, show the spinner and stagger the new
    // page in, like the web's PaginatedLeaderboard (issue #71).
    val swap = rememberLoadSwap(board, board !is LoadState.Loading, key = Triple(instrument, metric, page))
    val shown = swap.shown
    val shownPage = (shown as? LoadState.Loaded)?.value
    val entries = shownPage?.rankings?.entries.orEmpty()
    val revealsSelected = entries.any { RankingSpotlight.isSelected(selected, it.accountId) }

    // A new page starts at the top, unless it holds the selected row (revealed instead).
    LaunchedEffect(swap.showsSpinner) {
        if (swap.showsSpinner) listState.scrollToItem(0)
    }
    LaunchedEffect(shownPage) {
        if (!revealsSelected) listState.scrollToItem(0)
    }

    FestivalScreen(
        title = "${instrument.label} Leaderboards",
        isRoot = false,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        actions = {
            InstrumentAction(instrument, Instrument.entries.filter { it in visible || it == instrument }, viewModel::selectInstrument, "fst.full-rankings.instrument-menu")
            RankByAction(metric, viewModel::selectMetric)
        },
    ) { padding ->
        val failed = board as? LoadState.Failed
        if (failed != null && current == null) {
            ServiceStatusView(failed.issue, "Rankings unavailable", failed.countdown, viewModel::retry, contentPadding = padding)
            return@FestivalScreen
        }
        val pinned = ((spotlight as? LoadState.Loaded)?.value as? PlayerRankingResult.Ranked)?.ranking?.entry
        CompositionLocalProvider(LocalRankingColumns provides rememberAccountColumns(entries + listOfNotNull(pinned), metric)) {
        RankingsBoardScaffold(
            padding = padding,
            listState = listState,
            idPrefix = "fst.full-rankings",
            controls = { FullRankingsControls(current) },
            footer = { FullRankingsFooter(instrument, metric, selected, entries, spotlight, shownPage != null, viewModel, navigate) },
            pager = { RankingsPager(page, totalPages, "fst.full-rankings", viewModel::goTo) },
        ) {
            when {
                swap.showsSpinner -> loadSwapSpinnerItem(swap, "Loading rankings", "fst.full-rankings.loading")
                shown is LoadState.Failed -> item(key = "failed") {
                    Box(swap.contentModifier) { ServiceStatusInline(shown.issue, "Rankings unavailable", shown.countdown, viewModel::retry) }
                }
                else -> rankingRows(swap, entries, metric, selected, navigate)
            }
        }
        }
    }
}

/**
 * Page information above the rows: the population (web "868,901 ranked players"; the
 * pickers themselves are screen actions).
 *
 * @param current Shown page, or null while the first page loads.
 */
@Composable
private fun FullRankingsControls(current: RankingsPayload?) {
    if (current == null) return
    Text(
        RankingFormatting.population(current.rankings.totalAccounts, "player"),
        style = MaterialTheme.typography.bodyMedium,
        color = BrandTokens.textPrimary,
        modifier = Modifier.testTag("fst.full-rankings.population"),
    )
}

/**
 * Row items for one page of account rankings, faded out and staggered in by the load swap.
 *
 * @param swap Load swap for the page.
 * @param entries Page rows.
 * @param metric Selected metric.
 * @param selected Selected player.
 * @param navigate Push a route.
 */
private fun LazyListScope.rankingRows(
    swap: LoadSwap<*>,
    entries: List<AccountRankingEntry>,
    metric: RankingMetric,
    selected: String?,
    navigate: (AppRoute) -> Unit,
) {
    item(key = "rows") {
        GlassCard(Modifier.fillMaxWidth().then(swap.contentModifier)) {
            Column(Modifier.padding(8.dp)) {
                when {
                    entries.isEmpty() -> Text("No ranked players yet.", color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                    else -> entries.forEachIndexed { index, entry ->
                        Box(Modifier.festivalFadeIn(swap.revealed, fadeInStagger(index))) {
                            if (index > 0) RowSeparator(Modifier.align(Alignment.TopCenter))
                            AccountRankingRow(
                                entry = entry,
                                metric = metric,
                                isSelected = RankingSpotlight.isSelected(selected, entry.accountId),
                                route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selected),
                                onOpen = navigate,
                                reveal = true,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.FullRankingsFooter(
    instrument: Instrument,
    metric: RankingMetric,
    selected: String?,
    entries: List<AccountRankingEntry>,
    spotlight: LoadState<PlayerRankingResult>,
    pageLoaded: Boolean,
    viewModel: FullRankingsViewModel,
    navigate: (AppRoute) -> Unit,
) {
    if (selected == null || !pageLoaded) return
    if (spotlight is LoadState.Failed) {
        AnchoredRowCard { ServiceStatusInline(spotlight.issue, "Your rank is unavailable", spotlight.countdown, viewModel::retrySpotlight) }
        return
    }
    val source = when (val value = (spotlight as? LoadState.Loaded)?.value) {
        is PlayerRankingResult.Ranked -> RankingSpotlightSource.Available(value.ranking.entry)
        PlayerRankingResult.Unranked -> RankingSpotlightSource.Unranked
        null -> RankingSpotlightSource.NotLoaded
    }
    when (val placement = RankingSpotlight.placement(selected, entries, source)) {
        RankingSpotlightPlacement.None, RankingSpotlightPlacement.Inline -> Unit
        RankingSpotlightPlacement.Pending -> AnchoredRowCard { SpotlightLoadingRow("fst.full-rankings.spotlight-footer.loading") }
        RankingSpotlightPlacement.Unranked -> AnchoredRowCard { SpotlightUnrankedRow("Not yet ranked on ${instrument.label}.", "fst.full-rankings.spotlight-footer.unranked") }
        // Web fixed player footer: the full-width row (opening the profile) in the page's
        // columns, so it lines up with the rows above (operator batch 7, 7.9).
        is RankingSpotlightPlacement.Footer -> AnchoredRowCard {
            AccountRankingRow(
                entry = placement.entry,
                metric = metric,
                isSelected = true,
                route = RankingNavigation.playerRoute(placement.entry.accountId, placement.entry.displayName, selected),
                onOpen = navigate,
                tag = "fst.full-rankings.spotlight-footer",
            )
        }
    }
}

// endregion
