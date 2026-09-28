package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.BandsRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardsLayoutPolicy
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rankings.RankingSpotlightPlacement
import com.festivalscoretracker.android.core.rankings.RankingSpotlightSource
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Overview

/**
 * `/leaderboards`: top-ten cards per Settings-visible instrument, then Duos · Trios ·
 * Quads, with the Rank By action in the top bar. One column on compact widths, an
 * adaptive grid (≥ 340 dp cards, up to four columns) on medium/expanded widths, and
 * exactly two columns split around a separating vertical hinge.
 *
 * @param viewModel Overview logic.
 * @param isRoot Whether this is the Leaderboards tab root (else pushed, e.g. from Compete).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun LeaderboardsScreen(viewModel: LeaderboardsViewModel, isRoot: Boolean) {
    val metric by viewModel.metric.collectAsStateWithLifecycle()
    val instruments by viewModel.instruments.collectAsStateWithLifecycle()
    val selected by viewModel.selectedAccountId.collectAsStateWithLifecycle()
    val refreshing by viewModel.refreshing.collectAsStateWithLifecycle()
    val shell = LocalShellActions.current
    FestivalScreen(
        title = "Leaderboards",
        isRoot = isRoot,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        actions = { RankByAction(metric, viewModel::selectMetric) },
    ) { padding ->
        PullToRefreshBox(isRefreshing = refreshing, onRefresh = viewModel::refresh, modifier = Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            val (hinge, measure) = rememberHingeSplit()
            BoxWithConstraints(Modifier.fillMaxSize().then(measure)) {
                val columns = LeaderboardsLayoutPolicy.columns(maxWidth.value.toInt(), hinge != null)
                val gap = LeaderboardsLayoutPolicy.GAP_DP.dp
                val rowHinge = hinge?.let { HingeSplit(it.start - gap, it.end - gap) }
                val instrumentCards: List<@Composable () -> Unit> = instruments.map { instrument ->
                    { InstrumentCard(instrument, viewModel, metric, selected, shell.navigate) }
                }
                val bandCards: List<@Composable () -> Unit> = BandType.entries.map { bandType ->
                    { BandCard(bandType, viewModel, metric, selected, shell.navigate) }
                }
                LazyColumn(
                    contentPadding = PaddingValues(start = gap, end = gap, top = 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(gap),
                    modifier = Modifier.fillMaxSize().testTag("fst.leaderboards"),
                ) {
                    instrumentCards.chunked(columns).forEachIndexed { index, row ->
                        item(key = "instruments-$columns-$index") { CardGridRow(row, columns, rowHinge, gap) }
                    }
                    item(key = "bands-header") { BandsHeader { shell.navigate(BandsRoute) } }
                    bandCards.chunked(columns).forEachIndexed { index, row ->
                        item(key = "bands-$columns-$index") { CardGridRow(row, columns, rowHinge, gap) }
                    }
                }
            }
        }
    }
}

@Composable
private fun BandsHeader(onBrowse: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(
            "Bands",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        TextButton(onClick = onBrowse, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.leaderboards.bands-link")) {
            Text("Browse Bands", color = BrandTokens.accentBlue)
        }
    }
}

// endregion

// region Cards

/**
 * Card header: icon, Title Case heading and the metric subtitle.
 *
 * @param title Card title.
 * @param subtitle Metric label.
 * @param icon Leading icon.
 */
@Composable
private fun CardHeader(title: String, subtitle: String, icon: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 8.dp, top = 4.dp, bottom = 4.dp)) {
        icon()
        Column(Modifier.padding(start = 10.dp).semantics(mergeDescendants = true) { heading() }) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
            Text(subtitle, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textSecondary)
        }
    }
}

@Composable
private fun ViewAllButton(tag: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag)) {
        Text("View All", fontWeight = FontWeight.SemiBold, color = BrandTokens.accentBlue)
    }
}

/**
 * One instrument's top-ten card with the selected player's spotlight.
 *
 * @param instrument Chart.
 * @param viewModel Overview logic.
 * @param metric Rank By metric.
 * @param selected Selected player.
 * @param navigate Push a route.
 */
@Composable
private fun InstrumentCard(instrument: Instrument, viewModel: LeaderboardsViewModel, metric: RankingMetric, selected: String?, navigate: (AppRoute) -> Unit) {
    val state by viewModel.card(instrument).collectAsStateWithLifecycle()
    val tag = "fst.leaderboards.card.${instrument.wireId}"
    GlassCard(Modifier.fillMaxWidth().testTag(tag)) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            CardHeader(instrument.label, metric.label) { InstrumentIcon(instrument, size = 28.dp, decorative = true) }
            when (val current = state) {
                LoadState.Loading -> RankingsSkeletonRows(5)
                is LoadState.Failed -> ServiceStatusInline(current.issue, "${instrument.label} rankings unavailable", current.countdown, { viewModel.retryCard(instrument) }, Modifier.padding(horizontal = 8.dp))
                is LoadState.Loaded -> {
                    val entries = current.value.rankings.entries
                    if (entries.isEmpty()) {
                        Text("No ranked ${instrument.label} players yet.", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(8.dp))
                    }
                    entries.forEach { entry ->
                        AccountRankingRow(
                            entry = entry,
                            metric = metric,
                            isSelected = RankingSpotlight.isSelected(selected, entry.accountId),
                            route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selected),
                            onOpen = navigate,
                        )
                    }
                    CardSpotlight(instrument, viewModel, metric, selected, entries, navigate, tag)
                    if (entries.isNotEmpty()) {
                        ViewAllButton("$tag.view-all") { navigate(FullRankingsRoute(instrument.wireId, metric.wireId)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun CardSpotlight(
    instrument: Instrument,
    viewModel: LeaderboardsViewModel,
    metric: RankingMetric,
    selected: String?,
    entries: List<AccountRankingEntry>,
    navigate: (AppRoute) -> Unit,
    tag: String,
) {
    if (selected == null || entries.any { RankingSpotlight.isSelected(selected, it.accountId) }) return
    val state by viewModel.spotlight(instrument).collectAsStateWithLifecycle()
    val failed = state as? LoadState.Failed
    if (failed != null) {
        ServiceStatusInline(failed.issue, "Your rank is unavailable", failed.countdown, { viewModel.retrySpotlight(instrument) }, Modifier.padding(horizontal = 8.dp))
        return
    }
    val source = when (val value = (state as? LoadState.Loaded)?.value) {
        is PlayerRankingResult.Ranked -> RankingSpotlightSource.Available(value.ranking.entry)
        PlayerRankingResult.Unranked -> RankingSpotlightSource.Unranked
        null -> RankingSpotlightSource.NotLoaded
    }
    when (val placement = RankingSpotlight.placement(selected, entries, source)) {
        RankingSpotlightPlacement.None, RankingSpotlightPlacement.Inline -> Unit
        RankingSpotlightPlacement.Pending -> SpotlightLoadingRow("$tag.spotlight.loading")
        RankingSpotlightPlacement.Unranked -> SpotlightUnrankedRow("Not yet ranked on ${instrument.label}.", "$tag.spotlight.unranked")
        is RankingSpotlightPlacement.Footer -> AccountRankingRow(
            entry = placement.entry,
            metric = metric,
            isSelected = true,
            route = RankingNavigation.playerRoute(placement.entry.accountId, placement.entry.displayName, selected),
            onOpen = navigate,
            tag = "$tag.spotlight",
        )
    }
}

/**
 * One band size's top-ten card; rows containing the selected player are highlighted.
 *
 * @param bandType Band size.
 * @param viewModel Overview logic.
 * @param metric Rank By metric (narrowed for bands).
 * @param selected Selected player.
 * @param navigate Push a route.
 */
@Composable
private fun BandCard(bandType: BandType, viewModel: LeaderboardsViewModel, metric: RankingMetric, selected: String?, navigate: (AppRoute) -> Unit) {
    val state by viewModel.bandCard(bandType).collectAsStateWithLifecycle()
    val bandMetric = metric.bandMetric
    val tag = "fst.leaderboards.band-card.${bandType.wireId}"
    GlassCard(Modifier.fillMaxWidth().testTag(tag)) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            CardHeader(bandType.label, bandMetric.label) { BandGlyph() }
            when (val current = state) {
                LoadState.Loading -> RankingsSkeletonRows(5)
                is LoadState.Failed -> ServiceStatusInline(current.issue, "${bandType.label} rankings unavailable", current.countdown, { viewModel.retryBand(bandType) }, Modifier.padding(horizontal = 8.dp))
                is LoadState.Loaded -> {
                    val entries = current.value.rankings.entries
                    if (entries.isEmpty()) {
                        Text("No ranked ${bandType.label.lowercase()} yet.", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(8.dp))
                    }
                    entries.forEach { entry ->
                        BandRankingRow(entry, bandMetric, entry.includes(selected), RankingNavigation.bandRoute(entry, bandType), navigate)
                    }
                    if (entries.isNotEmpty()) {
                        ViewAllButton("$tag.view-all") { navigate(BandRankingsRoute(bandType.wireId)) }
                    }
                }
            }
        }
    }
}

// endregion
