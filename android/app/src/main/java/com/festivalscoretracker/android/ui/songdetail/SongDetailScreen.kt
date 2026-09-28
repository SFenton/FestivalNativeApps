package com.festivalscoretracker.android.ui.songdetail

import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.rememberRevealed
import androidx.compose.foundation.lazy.itemsIndexed
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import com.festivalscoretracker.android.data.LeaderboardPayload
import java.text.NumberFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.presentation.songs.ChartScoreSummary
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.shop.ShopDetailAction
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Extras

/**
 * Song Detail inputs beyond the song itself, computed by the route from shared
 * Shop, selected-profile and Settings state.
 *
 * @property visibleInstruments Settings-visible charts.
 * @property selectedAccountId Selected player, or null.
 * @property summaries Per-chart "Your score" lines (empty without a player).
 * @property shopHighlight Effective Shop badge.
 * @property shopPulse Effective Shop pulse (Item Shop button breathe).
 * @property spotlight The selected player's effective row per chart (shown after the preview when outside the top ten).
 * @property shopUrl Validated official Shop URL for this song, or null.
 * @property shopError A Shop read failed (the offer can't be confirmed).
 * @property pathInstruments Path-capable charts; empty hides Paths.
 */
data class SongDetailExtras(
    val visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    val selectedAccountId: String? = null,
    val summaries: Map<Instrument, ChartScoreSummary> = emptyMap(),
    val shopHighlight: ShopHighlight? = null,
    val shopPulse: ShopPulse? = null,
    val spotlight: Map<Instrument, LeaderboardEntry> = emptyMap(),
    val shopUrl: String? = null,
    val shopError: Boolean = false,
    val pathInstruments: List<Instrument> = emptyList(),
)

// endregion

// region Song detail

/**
 * Song Detail: header (art, title, Shop badge/action, Paths), Intensity for every
 * charted instrument (even hidden ones), band leaderboard links, then a lazily
 * loaded ten-row preview per visible chart with the selected player's summary,
 * highlighted row, off-preview rank link and score-history link.
 *
 * @param viewModel Detail logic.
 * @param extras Shop, player and Settings inputs.
 * @param artworkUrl Artwork resolver.
 * @param background Shared backdrop (receives this song's static cover).
 * @param embedded True inside a two-pane layout (no own top bar).
 * @param onOpenPaths Open the CHOpt Paths sheet.
 */
@Composable
fun SongDetailScreen(
    viewModel: SongDetailViewModel,
    extras: SongDetailExtras,
    artworkUrl: (String?) -> String?,
    background: BackgroundController,
    embedded: Boolean,
    onOpenPaths: (Song) -> Unit,
) {
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val song = (songState as? LoadState.Loaded)?.value
    DisposableEffect(song?.albumArt) {
        val token = background.pushFocus(song?.albumArt)
        onDispose { background.popFocus(token) }
    }
    val revealed = rememberRevealed(songState is LoadState.Loaded)
    val body: @Composable (PaddingValues) -> Unit = { padding ->
        when (val state = songState) {
            LoadState.Loading -> LoadingView("Loading song", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(state.issue, "Song unavailable", state.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> SongDetailContent(state.value, viewModel, extras, artworkUrl(state.value.albumArt), padding, onOpenPaths, revealed)
        }
    }
    if (embedded) {
        val shell = LocalShellActions.current
        val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        body(PaddingValues(top = statusTop + 8.dp, bottom = shell.bottomPadding.calculateBottomPadding()))
    } else {
        FestivalScreen(title = song?.title ?: "Song", isRoot = false, content = body)
    }
}

@Composable
private fun SongDetailContent(
    song: Song,
    viewModel: SongDetailViewModel,
    extras: SongDetailExtras,
    artUrl: String?,
    padding: PaddingValues,
    onOpenPaths: (Song) -> Unit,
    revealed: Boolean,
) {
    val navigate = LocalShellActions.current.navigate
    val charted = Instrument.entries.filter(song::supports)
    val cards = charted.filter { it in extras.visibleInstruments }
    LazyColumn(
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize().testTag("fst.song-detail.list"),
    ) {
        item(key = "header") { Box(Modifier.festivalFadeIn(revealed)) { SongHeader(song, artUrl) } }
        item(key = "actions") { HeaderActions(song, extras, onOpenPaths) }
        item(key = "intensity-header") { SectionHeader("Intensity") }
        item(key = "intensity") { IntensityCard(song, charted) }
        item(key = "bands") { BandLinks(song, navigate) }
        itemsIndexed(cards, key = { _, chart -> chart.wireId }) { index, instrument ->
            val state by viewModel.preview(song, instrument).collectAsStateWithLifecycle()
            Column(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1))) {
                CardHeader(song, instrument, (state as? LoadState.Loaded)?.value?.leaderboard?.let { board -> if (board.entries.isEmpty()) 0 else board.totalEntries })
                PreviewCard(song, instrument, state, viewModel, extras, navigate)
            }
        }
    }
}

@Composable
private fun SongHeader(song: Song, artUrl: String?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(top = 8.dp)) {
        AsyncImage(
            model = artUrl,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(112.dp).clip(RoundedCornerShape(12.dp)).background(BrandTokens.surfaceMuted),
        )
        Column(Modifier.weight(1f)) {
            Text(song.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
            Text(song.subtitle, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textSecondary)
            song.album?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HeaderActions(song: Song, extras: SongDetailExtras, onOpenPaths: (Song) -> Unit) {
    val hasShop = extras.shopUrl != null
    if (extras.pathInstruments.isEmpty() && !hasShop && !extras.shopError) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (extras.pathInstruments.isNotEmpty()) {
                FilledTonalButton(onClick = { onOpenPaths(song) }, modifier = Modifier.testTag("fst.song-detail.paths.open")) {
                    Icon(Icons.Filled.Route, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text("Paths", modifier = Modifier.padding(start = 6.dp))
                }
            }
            extras.shopUrl?.let { ShopDetailAction(extras.shopHighlight, it, song.songId, extras.shopPulse) }
        }
        if (extras.shopError) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("fst.song-detail.shop-error")) {
                Icon(Icons.Filled.Warning, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(16.dp))
                Text("Item Shop availability couldn't be checked", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(start = 6.dp))
            }
        }
    }
}

@Composable
private fun IntensityCard(song: Song, charted: List<Instrument>) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.song-detail.intensity")) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            charted.forEach { instrument ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.semantics(mergeDescendants = true) { }) {
                    InstrumentIcon(instrument, keyboard = song.usesKeyboardIcon, size = 28.dp)
                    Text(instrument.label, color = BrandTokens.textSecondary, modifier = Modifier.weight(1f).padding(start = 10.dp))
                    DifficultyMeter(song.difficulty?.chartedValue(instrument) ?: Double.NaN)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BandLinks(song: Song, navigate: (AppRoute) -> Unit) {
    Column {
        SectionHeader("Band Leaderboards")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.song-detail.bands")) {
            BandType.entries.forEach { type ->
                AssistChip(
                    onClick = { navigate(SongBandLeaderboardRoute(song.songId, type.wireId)) },
                    label = { Text(type.label) },
                    leadingIcon = { Icon(Icons.Filled.Groups, contentDescription = null, modifier = Modifier.size(AssistChipDefaults.IconSize)) },
                    modifier = Modifier.testTag("fst.song-detail.band.${type.wireId}"),
                )
            }
        }
    }
}

/**
 * The instrument header above its card (web `InstrumentCard` header): icon, name
 * and the chart's total entries once the preview loads, or "No scores recorded yet"
 * (web `songDetail.noScores`) when the chart has none (the card then has no View all).
 */
@Composable
private fun CardHeader(song: Song, instrument: Instrument, totalEntries: Int?) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp).semantics(mergeDescendants = true) { heading() }) {
        InstrumentIcon(instrument, keyboard = song.usesKeyboardIcon, size = 32.dp, decorative = true)
        Column(Modifier.padding(start = 10.dp)) {
            Text(instrument.label, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
            totalEntries?.let {
                Text(
                    if (it <= 0) "No scores recorded yet" else "${NumberFormat.getIntegerInstance().format(it)} total entries",
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.song-detail.total.${instrument.wireId}"),
                )
            }
        }
    }
}

@Composable
private fun PreviewCard(
    song: Song,
    instrument: Instrument,
    state: LoadState<LeaderboardPayload>,
    viewModel: SongDetailViewModel,
    extras: SongDetailExtras,
    navigate: (AppRoute) -> Unit,
) {
    val summary = extras.summaries[instrument]
    val rowsRevealed = rememberRevealed(state is LoadState.Loaded)
    GlassCard(Modifier.fillMaxWidth().testTag("fst.song-detail.preview.${instrument.wireId}")) {
        Column(Modifier.padding(vertical = 6.dp)) {
            summary?.let { YourScore(it, instrument) }
            when (val preview = state) {
                LoadState.Loading -> Box(Modifier.fillMaxWidth().heightIn(min = 96.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(28.dp))
                }
                is LoadState.Failed -> ServiceStatusInline(
                    preview.issue, "${instrument.label} scores unavailable", preview.countdown,
                    onRetry = { viewModel.retryPreview(instrument) },
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
                is LoadState.Loaded -> Column(Modifier.festivalFadeIn(rowsRevealed)) {
                    val entries = preview.value.leaderboard.entries
                    if (entries.isEmpty()) {
                        Text("No scores yet", color = BrandTokens.textSecondary, modifier = Modifier.padding(16.dp))
                    } else {
                        entries.forEach { entry ->
                            PreviewRow(
                                entry = entry,
                                isSelected = RankingSpotlight.isSelected(extras.selectedAccountId, entry.accountId),
                                route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, extras.selectedAccountId),
                                instrument = instrument,
                                onOpen = navigate,
                            )
                        }
                        // The selected player outside the top ten is row eleven (web spotlight footer); it opens their page.
                        extras.spotlight[instrument]
                            ?.takeIf { mine -> mine.rank > LeaderboardPaging.PREVIEW_SIZE && entries.none { RankingSpotlight.isSelected(mine.accountId, it.accountId) } }
                            ?.let { mine ->
                                HorizontalDivider(color = BrandTokens.glassBorder, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                                Box(Modifier.testTag("fst.song-detail.your-rank.${instrument.wireId}")) {
                                    PreviewRow(
                                        entry = mine,
                                        isSelected = true,
                                        route = SongLeaderboardRoute(song.songId, instrument.wireId, LeaderboardPaging.pageForRank(mine.rank)),
                                        instrument = instrument,
                                        onOpen = navigate,
                                    )
                                }
                            }
                        FilledTonalButton(
                            onClick = { navigate(SongLeaderboardRoute(song.songId, instrument.wireId)) },
                            colors = ButtonDefaults.filledTonalButtonColors(containerColor = BrandTokens.accentPurple, contentColor = BrandTokens.textPrimary),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 8.dp)
                                .heightIn(min = 48.dp)
                                .testTag("fst.song-detail.view-all.${instrument.wireId}"),
                        ) { Text("View full leaderboard") }
                    }
                }
            }
            if (extras.selectedAccountId != null) {
                TextButton(
                    onClick = { navigate(PlayerHistoryRoute(song.songId, instrument.wireId)) },
                    modifier = Modifier.padding(horizontal = 4.dp).heightIn(min = 48.dp).testTag("fst.song-detail.history.${instrument.wireId}"),
                ) {
                    Icon(Icons.AutoMirrored.Filled.ShowChart, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text("View ${instrument.label} Score History", modifier = Modifier.padding(start = 6.dp))
                }
            }
        }
    }
}

/** The selected player's gold summary line (their row outside the top ten follows the preview). */
@Composable
private fun YourScore(summary: ChartScoreSummary, instrument: Instrument) {
    Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp).testTag("fst.song-detail.your-score.${instrument.wireId}")) {
        Text(
            summary.text,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (summary.scored) FontWeight.SemiBold else FontWeight.Normal,
            color = if (summary.scored) BrandTokens.gold else BrandTokens.textSecondary,
        )
    }
}

@Composable
private fun PreviewRow(entry: LeaderboardEntry, isSelected: Boolean, route: AppRoute?, instrument: Instrument, onOpen: (AppRoute) -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    var modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp).clip(shape)
    if (isSelected) modifier = modifier.background(BrandTokens.accentPurple.copy(alpha = 0.18f)).border(BorderStroke(1.dp, BrandTokens.accentPurple), shape)
    modifier = if (route != null) {
        modifier.clickable(role = Role.Button, onClickLabel = "Open profile") { onOpen(route) }
    } else {
        modifier.semantics { stateDescription = "Profile unavailable" }
    }
    Box(modifier.testTag("fst.song-detail.preview-row.${instrument.wireId}.${entry.accountId.ifEmpty { "rank-${entry.rank}" }}")) {
        ScoreRow(entry)
    }
}

// endregion

// region Score row

/**
 * One leaderboard row: rank, name, accuracy (or FC) and score, read as one stop.
 * Anonymous rows (no account) read "Unknown User".
 *
 * @param entry Wire row.
 * @param showStars Show the star images after the score (wide rows, web `QUERY_SHOW_STARS`).
 */
@Composable
fun ScoreRow(entry: LeaderboardEntry, showStars: Boolean = false) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .padding(horizontal = 12.dp)
            .semantics(mergeDescendants = true) { },
    ) {
        Text("#${entry.rank}", style = MaterialTheme.typography.labelLarge, color = BrandTokens.textPrimary, modifier = Modifier.width(56.dp))
        Text(
            entry.displayName?.takeIf { it.isNotBlank() && entry.accountId.isNotEmpty() } ?: "Unknown User",
            color = BrandTokens.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        AccuracyBadge(entry)
        Text(
            ScoreFormatting.score(entry.score),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(start = 10.dp),
        )
        if (showStars) {
            Box(Modifier.padding(start = 10.dp).width(STAR_COLUMN_DP.dp), contentAlignment = Alignment.CenterEnd) {
                StarRating(entry.stars ?: 0, Modifier.testTag("fst.stars"), size = 20.dp)
            }
        }
    }
}

/** Width reserved for the stars column so scores stay aligned (web `StarSize.rowWidth`). */
private const val STAR_COLUMN_DP = 116

@Composable
private fun AccuracyBadge(entry: LeaderboardEntry) {
    val accuracy = entry.accuracy ?: return
    val fullCombo = entry.isFullCombo == true
    val tint = ScoreFormatting.accuracyTint(accuracy)
    val background = when {
        fullCombo -> BrandTokens.gold.copy(alpha = 0.25f)
        tint != null -> Color(0xFF000000 or tint.toLong()).copy(alpha = 0.25f)
        else -> Color.Transparent
    }
    Text(
        if (fullCombo) "FC ${ScoreFormatting.accuracy(accuracy)}%" else "${ScoreFormatting.accuracy(accuracy)}%",
        style = MaterialTheme.typography.labelMedium,
        color = if (fullCombo) BrandTokens.gold else BrandTokens.textPrimary,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(background)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

// endregion
