package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rankings.RankingSpotlightPlacement
import com.festivalscoretracker.android.core.rankings.RankingSpotlightSource
import com.festivalscoretracker.android.core.rankings.SelectedRowAction
import com.festivalscoretracker.android.core.rankings.SelectedRowSubject
import com.festivalscoretracker.android.core.rankings.label
import com.festivalscoretracker.android.data.rankings.RankingsPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.FullRankingsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadSwap
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Full rankings

/**
 * `/leaderboards/all`: one instrument's paginated rankings. The instrument and
 * Rank By pickers are top-app-bar actions; the selected player is highlighted in place
 * and always pinned above the bottom-anchored pager (issue #318), and rows fade out above that footer
 * instead of scrolling visibly behind it (issue #115).
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
    // The requested page's rows are on screen (not the previous page fading out or the spinner).
    val pageShown = swap.phase == LoadSwapPhase.ContentIn && board is LoadState.Loaded && swap.shown === board
    // Inner width of the rows card, so narrow panes (beside a hinge) keep names readable (issue #115).
    var rowWidth by rememberRankingRowWidth()

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
        // The board's chart before its title, like the song leaderboard header (issue #294).
        titleIcon = { size -> InstrumentIcon(instrument, size = size, decorative = true, modifier = Modifier.testTag("fst.full-rankings.title-icon.${instrument.wireId}")) },
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
        CompositionLocalProvider(LocalRankingColumns provides rememberAccountColumns(entries + listOfNotNull(pinned), metric, keepNameMinimumIn = rowWidth)) {
        // Wide windows centre a capped board (web/Windows ~1100), so names stay near their scores.
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = MAX_BOARD_WIDTH_DP.dp).fillMaxSize()) {
        RankingsBoardScaffold(
            padding = padding,
            listState = listState,
            idPrefix = "fst.full-rankings",
            controls = { FullRankingsControls(current) },
            footer = { FullRankingsFooter(instrument, metric, selected, entries, spotlight, shownPage != null, page, pageShown, viewModel, navigate) },
            pager = { RankingsPager(page, totalPages, "fst.full-rankings", viewModel::goTo) },
            fadeAboveFooter = true,
        ) {
            when {
                swap.showsSpinner -> loadSwapSpinnerItem(swap, "Loading rankings", "fst.full-rankings.loading")
                shown is LoadState.Failed -> item(key = "failed") {
                    Box(swap.contentModifier) { ServiceStatusInline(shown.issue, "Rankings unavailable", shown.countdown, viewModel::retry) }
                }
                else -> rankingRows(swap, entries, metric, selected, navigate) { rowWidth = it }
            }
        }
        }
        }
        }
    }
}

/** Widest the board grows (web page container / Windows list, about 1100), centred beyond it (issue #115). */
private const val MAX_BOARD_WIDTH_DP = 1100

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
 * @param onRowWidth Receives the rows' width in dp (the card's inner width) after layout.
 */
private fun LazyListScope.rankingRows(
    swap: LoadSwap<*>,
    entries: List<AccountRankingEntry>,
    metric: RankingMetric,
    selected: String?,
    navigate: (AppRoute) -> Unit,
    onRowWidth: (Float) -> Unit,
) {
    item(key = "rows") {
        val density = LocalDensity.current
        GlassCard(Modifier.fillMaxWidth().then(swap.contentModifier)) {
            Column(Modifier.padding(8.dp).onSizeChanged { onRowWidth(with(density) { it.width.toDp().value }) }) {
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
                                revealDelayMillis = fadeInStagger(index),
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
    page: Int,
    pageShown: Boolean,
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
    // Pinned on every page, the player's own included, like the song boards (issue #318).
    when (val placement = RankingSpotlight.pinnedPlacement(selected, entries, source)) {
        RankingSpotlightPlacement.None, RankingSpotlightPlacement.Inline -> Unit
        RankingSpotlightPlacement.Pending -> AnchoredRowCard { SpotlightLoadingRow("fst.full-rankings.spotlight-footer.loading") }
        RankingSpotlightPlacement.Unranked -> AnchoredRowCard { SpotlightUnrankedRow("Not yet ranked on ${instrument.label}.", "fst.full-rankings.spotlight-footer.unranked") }
        // Web fixed player footer: the full-width row in the page's columns, so it lines up
        // with the rows above (operator batch 7, 7.9). `leaderboard-row` R7: it jumps to the
        // player's page while their row is elsewhere and opens Statistics once it is on screen;
        // while a page loads, the rank decides.
        is RankingSpotlightPlacement.Footer -> AnchoredRowCard {
            val rank = placement.entry.rank(metric)
            val visible = if (pageShown) entries.any { RankingSpotlight.isSelected(selected, it.accountId) } else rank > 0 && LeaderboardPaging.pageForRank(rank, RankingPaging.PAGE_SIZE) == page
            val action = SelectedRowAction.footer(rank, visible, page, RankingPaging.PAGE_SIZE)
            AccountRankingRow(
                entry = placement.entry,
                metric = metric,
                isSelected = true,
                route = RankingNavigation.playerRoute(placement.entry.accountId, placement.entry.displayName, selected),
                onOpen = { route -> if (action is SelectedRowAction.Jump) viewModel.goTo(action.page) else navigate(route) },
                tag = "fst.full-rankings.spotlight-footer",
                clickLabel = action.label(SelectedRowSubject.Player),
            )
        }
    }
}

// endregion
