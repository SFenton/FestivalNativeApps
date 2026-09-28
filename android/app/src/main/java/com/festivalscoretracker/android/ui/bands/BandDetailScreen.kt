package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandDetail
import com.festivalscoretracker.android.core.bands.BandDetailProjection
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandRankHistoryResponse
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandSongRow
import com.festivalscoretracker.android.core.bands.BandStat
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.BandDetailViewModel
import com.festivalscoretracker.android.presentation.bands.BandSongsState
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Screen

/**
 * `/bands/:bandId` (web `BandPage`): Members, Band Summary, Band Statistics (Rank
 * By), Band Rank History and Five Best / Five Worst Songs. Splits into two
 * independently scrolling panes on wide windows or around a vertical hinge.
 *
 * @param viewModel Detail logic.
 * @param routeName Name carried by the route (shown until the row loads).
 * @param artworkUrl Artwork resolver.
 * @param onNavigate Push a route.
 */
@Composable
fun BandDetailScreen(viewModel: BandDetailViewModel, routeName: String?, artworkUrl: (String?) -> String?, onNavigate: (AppRoute) -> Unit) {
    val detailState by viewModel.detail.collectAsStateWithLifecycle()
    val detail = (detailState as? LoadState.Loaded)?.value
    val title = detail?.let { BandMember.joinNames(it.displayMembers) } ?: routeName?.takeIf { it.isNotBlank() } ?: "Band"
    FestivalScreen(title = "Band", isRoot = false, modifier = Modifier.testTag("fst.band.screen")) { padding ->
        val type = viewModel.bandType
        when {
            type == null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                BandEmptyState(
                    "Band Not Available",
                    "Open this band from a player's band list, Band Rankings or a song's band leaderboard.",
                    "fst.band.unresolved",
                )
            }
            detailState is LoadState.Loading -> LoadingView("Loading band", Modifier.padding(padding))
            detailState is LoadState.Failed -> {
                val failed = detailState as LoadState.Failed
                ServiceStatusView(failed.issue, "Band not found", failed.countdown, viewModel::retry, Modifier.testTag("fst.band.error"), padding)
            }
            detail != null -> BandDetailContent(viewModel, detail, type, title, padding, artworkUrl, onNavigate)
        }
    }
}

@Composable
private fun BandDetailContent(
    viewModel: BandDetailViewModel,
    detail: BandDetail,
    type: BandType,
    title: String,
    padding: PaddingValues,
    artworkUrl: (String?) -> String?,
    onNavigate: (AppRoute) -> Unit,
) {
    val metric by viewModel.metric.collectAsStateWithLifecycle()
    val history by viewModel.history.collectAsStateWithLifecycle()
    val songs by viewModel.songs.collectAsStateWithLifecycle()
    val songsState = (songs as? LoadState.Loaded)?.value
    val bestSong = songsState?.let { state -> state.response.best.firstOrNull()?.let { state.songsById[it.songId] } }
    val summary = remember(detail, type) { BandDetailProjection.summary(detail, type) }
    val statistics = remember(detail, type, metric, bestSong) { BandDetailProjection.statistics(detail, type, metric, bestSong) }
    val density = LocalDensity.current
    var contentLeft by remember { mutableFloatStateOf(0f) }
    val leading: @Composable ColumnScope.() -> Unit = {
        BandPageHeader(title, "${type.label} · ${BandFormatting.appearances(detail.songsPlayed)}", "fst.band")
        MembersSection(detail.displayMembers, onNavigate)
        SectionHeader("Band Summary", Modifier.testTag("fst.band.summary-section"))
        StatGrid(summary, onNavigate)
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionHeader("Band Statistics", Modifier.weight(1f).testTag("fst.band.statistics-section"))
            RankByMenu(metric, viewModel::selectMetric)
        }
        StatGrid(statistics, onNavigate)
    }
    val trailing: @Composable ColumnScope.() -> Unit = {
        HistorySection(history, metric, viewModel::retryHistory)
        SongsSections(songs, title, artworkUrl, viewModel::retrySongs, onNavigate)
    }
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { contentLeft = it.positionInWindow().x },
    ) {
        val panes = rememberBandPaneLayout(maxWidth, with(density) { contentLeft.toDp() })
        val scrollPadding = Modifier.padding(start = 16.dp, end = 16.dp)
        val bottom = padding.calculateBottomPadding() + 24.dp
        if (panes.twoPane) {
            Row(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
                val leadingModifier = panes.leadingWidth?.let { Modifier.width(it) } ?: Modifier.weight(1f)
                Column(leadingModifier.fillMaxSize().verticalScroll(rememberScrollState()).then(scrollPadding).testTag("fst.band.pane.leading")) {
                    leading()
                    Spacer(Modifier.height(bottom))
                }
                Spacer(Modifier.width(panes.gap))
                Column(Modifier.weight(1f).fillMaxSize().verticalScroll(rememberScrollState()).then(scrollPadding).testTag("fst.band.pane.trailing")) {
                    trailing()
                    Spacer(Modifier.height(bottom))
                }
            }
        } else {
            BandReadableWidth {
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(top = padding.calculateTopPadding())
                        .then(scrollPadding)
                        .testTag("fst.band.content"),
                ) {
                    leading()
                    trailing()
                    Spacer(Modifier.height(bottom))
                }
            }
        }
    }
}

// endregion

// region Members and stats

@Composable
private fun MembersSection(members: List<BandMember>, onNavigate: (AppRoute) -> Unit) {
    SectionHeader("Members", Modifier.testTag("fst.band.members-section"))
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = maxOf(1, (maxWidth / 260.dp).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BandMember.distinct(members).chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { member ->
                        val route = if (member.isLinkable) PlayerRoute(member.accountId, member.displayName?.takeIf { it.isNotBlank() }) else null
                        GlassCard(
                            Modifier
                                .weight(1f)
                                .heightIn(min = 56.dp)
                                .testTag("fst.band.member.${member.accountId.ifEmpty { "unknown" }}")
                                .semantics(mergeDescendants = true) { contentDescription = memberAnnouncement(member) },
                            onClick = route?.let { { onNavigate(it) } },
                        ) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    member.resolvedName,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (route != null) BrandTokens.textPrimary else BrandTokens.textSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                                member.chartedInstruments.forEach { InstrumentIcon(it, size = 28.dp, decorative = true) }
                            }
                        }
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun StatGrid(stats: List<BandStat>, onNavigate: (AppRoute) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = maxOf(2, (maxWidth / 150.dp).toInt()).coerceAtMost(4)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            stats.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { stat ->
                        GlassCard(
                            Modifier
                                .weight(1f)
                                .heightIn(min = 72.dp)
                                .testTag("fst.band.stat.${stat.id}")
                                .semantics(mergeDescendants = true) { contentDescription = "${stat.label}, ${stat.value}" },
                            onClick = stat.route?.let { { onNavigate(it) } },
                        ) {
                            Column(Modifier.padding(12.dp)) {
                                Text(stat.label, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(
                                    stat.value,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = if (stat.route != null) BrandTokens.accentBlue else BrandTokens.textPrimary,
                                    maxLines = 1,
                                )
                            }
                        }
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun RankByMenu(metric: BandRankingMetric, onSelect: (BandRankingMetric) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(
            onClick = { open = true },
            modifier = Modifier
                .heightIn(min = 48.dp)
                .testTag("fst.band.rank-by")
                .semantics { contentDescription = "Rank by ${metric.label}" },
        ) {
            Text(metric.label, maxLines = 1)
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            BandRankingMetric.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.label) },
                    onClick = {
                        onSelect(option)
                        open = false
                    },
                    modifier = Modifier.testTag("fst.band.rank-by.${option.wireId}"),
                )
            }
        }
    }
}

// endregion

// region Rank history

@Composable
private fun HistorySection(state: LoadState<BandRankHistoryResponse>, metric: BandRankingMetric, onRetry: () -> Unit) {
    SectionHeader("Band Rank History", Modifier.testTag("fst.band.history-section"))
    val note = (state as? LoadState.Loaded)?.value?.let(BandDetailProjection::historyNote)
    Text(
        "Any-combo ranking progression over the past ${BandDetailProjection.HISTORY_DAYS} days." + (note?.let { " $it" } ?: ""),
        style = MaterialTheme.typography.bodySmall,
        color = BrandTokens.textSecondary,
        modifier = Modifier.padding(bottom = 8.dp),
    )
    when (state) {
        LoadState.Loading -> SectionProgress("Loading rank history")
        is LoadState.Failed -> ServiceStatusInline(state.issue, "Rank history unavailable", state.countdown, onRetry)
        is LoadState.Loaded -> {
            val ranked = remember(state.value, metric) { BandDetailProjection.ranked(state.value.history, metric) }
            if (ranked.isEmpty()) {
                Text("No band rank history yet.", color = BrandTokens.textSecondary, modifier = Modifier.padding(vertical = 8.dp).testTag("fst.band.history-empty"))
                return
            }
            val points = remember(ranked, metric) { BandDetailProjection.points(ranked, metric) }
            val rows = remember(ranked, metric) { BandDetailProjection.recentRows(ranked, metric) }
            GlassCard(Modifier.fillMaxWidth()) {
                RankHistoryChart(points.map { Offset(it.x, it.y) }, ranked.first().rank(metric), ranked.last().rank(metric), ranked.size)
                Column(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
                    rows.forEach { row ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 40.dp)
                                .testTag("fst.band.history-row.${row.date}")
                                .semantics(mergeDescendants = true) { contentDescription = "${row.dateText}, rank ${row.rankText}, ${row.valueText}" },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(row.dateText, color = BrandTokens.textSecondary, modifier = Modifier.weight(1f))
                            Text(row.rankText, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                            Text(row.valueText, color = BrandTokens.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Static rank line (best rank at the top); drawn only when its inputs change.
 *
 * @param points Normalized vertices, oldest first.
 * @param firstRank Oldest rank.
 * @param lastRank Newest rank.
 * @param count Snapshot count.
 */
@Composable
private fun RankHistoryChart(points: List<Offset>, firstRank: Int, lastRank: Int, count: Int) {
    val line = BrandTokens.accentBlue
    val description = "Rank history chart: ${BandFormatting.rank(firstRank)} to ${BandFormatting.rank(lastRank)} over $count snapshots"
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(140.dp)
            .padding(16.dp)
            .testTag("fst.band.history-chart")
            .semantics { contentDescription = description },
    ) {
        val mapped = points.map { Offset(it.x * size.width, it.y * size.height) }
        if (mapped.size > 1) {
            val path = Path().apply {
                moveTo(mapped[0].x, mapped[0].y)
                mapped.drop(1).forEach { lineTo(it.x, it.y) }
            }
            drawPath(path, line, style = Stroke(width = 3.dp.toPx()))
        }
        mapped.forEach { drawCircle(line, radius = 4.dp.toPx(), center = it) }
    }
}

// endregion

// region Songs

@Composable
private fun SongsSections(
    state: LoadState<BandSongsState>,
    title: String,
    artworkUrl: (String?) -> String?,
    onRetry: () -> Unit,
    onNavigate: (AppRoute) -> Unit,
) {
    SectionHeader("Five Best Songs", Modifier.testTag("fst.band.songs-section"))
    when (state) {
        LoadState.Loading -> SectionProgress("Loading band songs")
        is LoadState.Failed -> ServiceStatusInline(state.issue, "Band songs unavailable", state.countdown, onRetry)
        is LoadState.Loaded -> {
            val best = state.value.response.best.map { BandSongRow(it, state.value.songsById[it.songId]) }
            val worst = state.value.response.worst.map { BandSongRow(it, state.value.songsById[it.songId]) }
            SongList(best, "$title's highest-ranked band songs, sorted by percentile.", "fst.band.best-songs", artworkUrl, onNavigate)
            SectionHeader("Five Worst Songs")
            SongList(worst, "$title's lowest-ranked band songs, sorted by percentile.", "fst.band.worst-songs", artworkUrl, onNavigate)
        }
    }
}

@Composable
private fun SongList(rows: List<BandSongRow>, description: String, tag: String, artworkUrl: (String?) -> String?, onNavigate: (AppRoute) -> Unit) {
    Text(description, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(bottom = 8.dp))
    if (rows.isEmpty()) {
        Text("No band songs yet.", color = BrandTokens.textSecondary, modifier = Modifier.padding(vertical = 8.dp))
        return
    }
    Column(Modifier.testTag(tag), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            val rankText = "${BandFormatting.rank(row.performance.rank)} of ${BandFormatting.count(row.performance.totalEntries.toLong())}"
            val percentile = BandFormatting.percentile(row.performance.percentile)
            GlassCard(
                Modifier
                    .fillMaxWidth()
                    .testTag("fst.band.song-row.${row.performance.songId}")
                    .semantics(mergeDescendants = true) { contentDescription = "${row.title}, $percentile, rank $rankText" },
                onClick = row.route?.let { { onNavigate(it) } },
            ) {
                Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AsyncImage(
                        model = artworkUrl(row.song?.albumArt),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(40.dp).clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(row.title, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (row.subtitle.isNotEmpty()) {
                            Text(row.subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Pill(percentile)
                        Text(rankText, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionProgress(label: String) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.Center) {
        CircularProgressIndicator(Modifier.semantics { contentDescription = label })
    }
}

// endregion
