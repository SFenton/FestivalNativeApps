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
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.festivalscoretracker.android.ui.common.rememberRevealed
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
    val entries = current?.rankings?.entries.orEmpty()
    val revealed = rememberRevealed(board !is LoadState.Loading && current != null)

    LaunchedEffect(current) { listState.scrollToItem(0) }

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
            loadingOverlay = board is LoadState.Loading && current != null,
            controls = {
                current?.let {
                    Text(
                        RankingFormatting.population(it.rankings.totalTeams, "band"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.testTag("fst.band-rankings.population"),
                    )
                }
                if (failed != null) ServiceStatusInline(failed.issue, "Band rankings unavailable", failed.countdown, viewModel::retry)
            },
            footer = {},
            pager = { RankingsPager(page, current?.rankings?.pageCount ?: 1, "fst.band-rankings", viewModel::goTo) },
        ) {
            item(key = "rows") {
                GlassCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(8.dp)) {
                        when {
                            current == null -> RankingsSkeletonRows(10)
                            entries.isEmpty() -> Text("No ranked bands yet.", color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                            else -> CompositionLocalProvider(LocalRankingColumns provides rememberBandColumns(entries, metric)) { entries.forEachIndexed { index, entry ->
                                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
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
