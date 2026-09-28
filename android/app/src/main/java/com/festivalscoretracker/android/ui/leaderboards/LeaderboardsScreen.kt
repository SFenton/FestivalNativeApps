package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.BandsRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
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
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat

// region Overview

/**
 * `/leaderboards`: the selected player's rank history, top-ten cards per
 * Settings-visible instrument, then Duos · Trios · Quads. Each card's icon, title and
 * metric sit above the card, like the web. Rank By and Quick Links are screen
 * actions (floating toolbar on compact windows, top app bar otherwise; Quick Links
 * open a sheet on compact and a menu on wider windows). One column on compact widths,
 * an adaptive grid (≥ 340 dp cards, up to four columns) on medium/expanded widths,
 * and exactly two columns split around a separating vertical hinge.
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
    val ready by viewModel.ready.collectAsStateWithLifecycle()
    val shell = LocalShellActions.current
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val windowWidthDp = with(density) { currentWindowSize().width.toDp().value.toInt() }
    val folded = currentWindowAdaptiveInfo().windowPosture.hingeList.any { it.isSeparating && it.isVertical }
    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = LeaderboardsLayoutPolicy.columns(maxWidth.value.toInt(), folded)
        val layout = remember(ready, instruments, selected, columns) {
            if (ready) OverviewLayout(instruments, showHistory = selected != null && instruments.isNotEmpty(), columns) else null
        }
        val quickLinks = rememberQuickLinks(listState, QUICK_LINKS_TITLE, layout?.sections.orEmpty()) { id -> layout?.indexOf(id) }
        FestivalScreen(
            title = "Leaderboards",
            isRoot = isRoot,
            scrolled = scrolled,
            modifier = Modifier.semantics { testTagsAsResourceId = true },
            actions = {
                QuickLinksAction(quickLinks, windowWidthDp)
                RankByAction(metric, viewModel::selectMetric)
            },
        ) { padding ->
            PullToRefreshBox(isRefreshing = refreshing, onRefresh = viewModel::refresh, modifier = Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
                // Until settings arrive the instrument list is empty; composing the band cards
                // first would anchor the list on them once instrument rows are inserted above.
                if (layout == null) return@PullToRefreshBox
                OverviewList(viewModel, layout, metric, selected, listState, padding, shell.navigate)
            }
        }
    }
}

/** Quick Links title (web `rankings.quickLinks.title`). */
private const val QUICK_LINKS_TITLE = "Leaderboards Quick Links"

/**
 * The overview's list items and Quick Links sections (web `quickLinkItems`): Rank
 * History (with a selected player), each instrument, then each band size.
 *
 * @property instruments Visible charts.
 * @property showHistory Whether the rank-history card leads the list.
 * @property columns Grid columns.
 */
private class OverviewLayout(val instruments: List<Instrument>, val showHistory: Boolean, val columns: Int) {
    private val historyItems = if (showHistory) 1 else 0
    private val instrumentRows = (instruments.size + columns - 1) / columns

    /** Quick Links sections in page order. */
    val sections: List<QuickLinkSection> =
        (if (showHistory) listOf(QuickLinkSection(HISTORY_ID, "Rank History Graph", icon = "chart")) else emptyList()) +
            instruments.map { QuickLinkSection("instrument:${it.wireId}", it.label, instrument = it) } +
            BandType.entries.map { QuickLinkSection("band:${it.wireId}", it.label, icon = "people") }

    /**
     * List item index of a section.
     *
     * @param id Section ID.
     * @return Index, or null for an unknown section.
     */
    fun indexOf(id: String): Int? {
        if (id == HISTORY_ID) return if (showHistory) 0 else null
        val instrument = instruments.indexOfFirst { "instrument:${it.wireId}" == id }
        if (instrument >= 0) return historyItems + instrument / columns
        val band = BandType.entries.indexOfFirst { "band:${it.wireId}" == id }
        if (band >= 0) return historyItems + instrumentRows + 1 + band / columns
        return null
    }

    companion object {
        const val HISTORY_ID = "rank-history"
    }
}

@Composable
private fun OverviewList(
    viewModel: LeaderboardsViewModel,
    layout: OverviewLayout,
    metric: RankingMetric,
    selected: String?,
    listState: LazyListState,
    padding: PaddingValues,
    navigate: (AppRoute) -> Unit,
) {
    val (hinge, measure) = rememberHingeSplit()
    val columns = layout.columns
    val gap = LeaderboardsLayoutPolicy.GAP_DP.dp
    val rowHinge = hinge?.let { HingeSplit(it.start - gap, it.end - gap) }
    val instrumentCards: List<@Composable () -> Unit> = layout.instruments.map { instrument ->
        { InstrumentCard(instrument, viewModel, metric, selected, navigate) }
    }
    val bandCards: List<@Composable () -> Unit> = BandType.entries.map { bandType ->
        { BandCard(bandType, viewModel, metric, selected, navigate) }
    }
    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(start = gap, end = gap, top = 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        modifier = Modifier.fillMaxSize().then(measure).testTag("fst.leaderboards"),
    ) {
        if (layout.showHistory && selected != null) {
            item(key = OverviewLayout.HISTORY_ID) {
                val history: List<@Composable () -> Unit> = listOf({ RankHistoryCard(viewModel, layout.instruments, metric, selected) })
                // The chart takes the leading side of a hinge; elsewhere it spans the row.
                if (rowHinge != null) CardGridRow(history, 2, rowHinge, gap) else history[0]()
            }
        }
        instrumentCards.chunked(columns).forEachIndexed { index, row ->
            item(key = "instruments-$columns-$index") { CardGridRow(row, columns, rowHinge, gap) }
        }
        item(key = "bands-header") { BandsHeader { navigate(BandsRoute) } }
        bandCards.chunked(columns).forEachIndexed { index, row ->
            item(key = "bands-$columns-$index") { CardGridRow(row, columns, rowHinge, gap) }
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
 * Card header shown above (outside) the card, like the web's `InstrumentHeader`:
 * the instrument icon (none for band sizes) and the Title Case name; the Rank By
 * metric is not repeated here (operator 2026-09-28).
 *
 * @param title Card title.
 * @param icon Leading icon, or null.
 */
@Composable
private fun CardHeader(title: String, icon: (@Composable () -> Unit)? = null) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.heightIn(min = 40.dp).padding(start = 4.dp, bottom = 8.dp),
    ) {
        icon?.invoke()
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
    }
}

/**
 * "View all rankings (N)" (web `rankings.viewAllRankingsWithCount`) as the card's
 * purple filled button, below the top ten (and the selected player's row).
 *
 * @param label Button text.
 * @param tag Test tag.
 * @param onClick Open the full board.
 */
@Composable
private fun ViewAllButton(label: String, tag: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentPurple, contentColor = BrandTokens.textPrimary),
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp).heightIn(min = 48.dp).testTag(tag),
    ) {
        Text(label, fontWeight = FontWeight.SemiBold)
    }
}

/**
 * View-all label with the population when known.
 *
 * @param noun "rankings" or "band rankings".
 * @param total Population, 0 when unknown.
 * @return Label.
 */
internal fun viewAllLabel(noun: String, total: Int): String =
    if (total > 0) "View all $noun (${NumberFormat.getIntegerInstance().format(total)})" else "View all $noun"

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
    val revealed = rememberRevealed(state is LoadState.Loaded)
    Column(Modifier.fillMaxWidth().testTag(tag)) {
        CardHeader(instrument.label) { InstrumentIcon(instrument, size = 40.dp, decorative = true) }
        GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            when (val current = state) {
                LoadState.Loading -> RankingsSkeletonRows(5)
                is LoadState.Failed -> ServiceStatusInline(current.issue, "${instrument.label} rankings unavailable", current.countdown, { viewModel.retryCard(instrument) }, Modifier.padding(horizontal = 8.dp))
                is LoadState.Loaded -> {
                    val entries = current.value.rankings.entries
                    if (entries.isEmpty()) {
                        Text("No ranked ${instrument.label} players yet.", style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                    }
                    entries.forEachIndexed { index, entry ->
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                            AccountRankingRow(
                                entry = entry,
                                metric = metric,
                                isSelected = RankingSpotlight.isSelected(selected, entry.accountId),
                                route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selected),
                                onOpen = navigate,
                            )
                        }
                    }
                    Column(Modifier.festivalFadeIn(revealed, fadeInStagger(entries.size))) {
                        CardSpotlight(instrument, viewModel, metric, selected, entries, navigate, tag)
                        if (entries.isNotEmpty()) {
                            ViewAllButton(viewAllLabel("rankings", current.value.rankings.totalAccounts), "$tag.view-all") {
                                navigate(FullRankingsRoute(instrument.wireId, metric.wireId))
                            }
                        }
                    }
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
    val revealed = rememberRevealed(state is LoadState.Loaded)
    Column(Modifier.fillMaxWidth().testTag(tag)) {
        CardHeader(bandType.label)
        GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            when (val current = state) {
                LoadState.Loading -> RankingsSkeletonRows(5)
                is LoadState.Failed -> ServiceStatusInline(current.issue, "${bandType.label} rankings unavailable", current.countdown, { viewModel.retryBand(bandType) }, Modifier.padding(horizontal = 8.dp))
                is LoadState.Loaded -> {
                    val entries = current.value.rankings.entries
                    if (entries.isEmpty()) {
                        Text("No ranked ${bandType.label.lowercase()} yet.", style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                    }
                    entries.forEachIndexed { index, entry ->
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                            BandRankingRow(entry, bandMetric, entry.includes(selected), RankingNavigation.bandRoute(entry, bandType), navigate)
                        }
                    }
                    if (entries.isNotEmpty()) {
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(entries.size))) {
                            ViewAllButton(viewAllLabel("band rankings", current.value.rankings.totalTeams), "$tag.view-all") {
                                navigate(BandRankingsRoute(bandType.wireId))
                            }
                        }
                    }
                }
            }
        }
        }
    }
}

// endregion
