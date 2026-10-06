package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import com.festivalscoretracker.android.ui.leaderboards.LocalRankingColumns
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.BandRankingsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Band rankings

/**
 * `/leaderboards/bands/:bandType`: one band size's paginated rankings with band-size
 * and band Rank By top-bar actions (no Max Score). Rows open Band Detail with the row's
 * `bandType`/`teamKey`, never the side-effecting `/api/bands/{bandId}` read; rows
 * containing the selected player are highlighted. No selected-band pinned row
 * (Android has no selected-band identity).
 *
 * @param viewModel Board logic.
 * @param selectedAccountId Selected player, for the membership highlight.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun BandRankingsScreen(viewModel: BandRankingsViewModel, selectedAccountId: String?) {
    val bandType by viewModel.bandType.collectAsStateWithLifecycle()
    val storedMetric by viewModel.metric.collectAsStateWithLifecycle()
    val metric = storedMetric ?: BandRankingMetric.DEFAULT
    val page by viewModel.page.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val current by viewModel.displayed.collectAsStateWithLifecycle()
    val navigate = LocalShellActions.current.navigate
    val listState = rememberLazyListState()
    // Band size, Rank By and page reloads fade the rows out, show the spinner and stagger
    // the new page in, like the web's PaginatedLeaderboard (issue #71).
    val swap = rememberLoadSwap(board, board !is LoadState.Loading, key = Triple(bandType, metric, page))
    val shown = swap.shown
    val shownPage = (shown as? LoadState.Loaded)?.value
    val entries = shownPage?.rankings?.entries.orEmpty()

    LaunchedEffect(swap.showsSpinner, shownPage) { listState.scrollToItem(0) }

    FestivalScreen(
        title = "${bandType.label} Leaderboards",
        isRoot = false,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        actions = {
            TopBarChoiceAction("Band Size", BandType.entries, bandType, BandType::label, viewModel::selectBandType, "fst.band-rankings.band-type-menu", icon = { BandGlyph() }, leading = { BandGlyph() })
            TopBarChoiceAction(
                "Rank By",
                BandRankingMetric.entries,
                metric,
                BandRankingMetric::label,
                viewModel::selectMetric,
                "fst.band-rankings.rank-by-menu",
                icon = { Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null) },
            )
        },
    ) { padding ->
        val failed = board as? LoadState.Failed
        if (failed != null && current == null) {
            ServiceStatusView(failed.issue, "Band rankings unavailable", failed.countdown, viewModel::retry, contentPadding = padding)
            return@FestivalScreen
        }
        RankingsBoardScaffold(
            padding = padding,
            listState = listState,
            idPrefix = "fst.band-rankings",
            controls = {
                current?.let {
                    Text(
                        RankingFormatting.population(it.rankings.totalTeams, "band"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.testTag("fst.band-rankings.population"),
                    )
                }
            },
            footer = {},
            pager = { RankingsPager(page, current?.rankings?.pageCount ?: 1, "fst.band-rankings", viewModel::goTo) },
            // Rows fade out above the floating pager and leave touch/TalkBack beneath it (issue #116).
            fadeAboveFooter = true,
        ) {
            if (swap.showsSpinner) {
                loadSwapSpinnerItem(swap, "Loading band rankings", "fst.band-rankings.loading")
            } else if (shown is LoadState.Failed) {
                item(key = "failed") {
                    Box(swap.contentModifier) { ServiceStatusInline(shown.issue, "Band rankings unavailable", shown.countdown, viewModel::retry) }
                }
            } else item(key = "rows") {
                GlassCard(Modifier.fillMaxWidth().then(swap.contentModifier)) {
                    // Rows fill this column; below the roster's minimum width they stack (issue #116).
                    var rowWidth by rememberRankingRowWidth()
                    val density = LocalDensity.current
                    Column(Modifier.padding(8.dp).onSizeChanged { rowWidth = with(density) { it.width.toDp().value } }) {
                        when {
                            entries.isEmpty() -> Text("No ranked bands yet.", color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                            else -> CompositionLocalProvider(LocalRankingColumns provides rememberBandColumns(entries, metric, stackBelow = rowWidth)) { entries.forEachIndexed { index, entry ->
                                Box(Modifier.festivalFadeIn(swap.revealed, fadeInStagger(index))) {
                                    if (index > 0) RowSeparator(Modifier.align(Alignment.TopCenter))
                                    BandRankingRow(entry, metric, entry.includes(selectedAccountId), RankingNavigation.bandRoute(entry, bandType), navigate)
                                }
                            } }
                        }
                    }
                }
            }
        }
    }
}

// endregion
