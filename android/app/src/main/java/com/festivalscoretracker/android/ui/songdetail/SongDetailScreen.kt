package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.core.songs.SongDetailLayout
import com.festivalscoretracker.android.core.songs.SongHistoryChart
import com.festivalscoretracker.android.data.LeaderboardPayload
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoadGate
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.AccuracyPill
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.leaderboards.CardGridRow
import com.festivalscoretracker.android.ui.leaderboards.HingeSplit
import com.festivalscoretracker.android.ui.leaderboards.rememberHingeSplit
import com.festivalscoretracker.android.ui.shop.ShopDetailAction
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat

// region Extras

/**
 * Song Detail inputs beyond the song itself, computed by the route from shared
 * Shop, selected-profile and Settings state.
 *
 * @property visibleInstruments Settings-visible charts.
 * @property selectedAccountId Selected player, or null.
 * @property shopHighlight Effective Shop badge.
 * @property shopPulse Effective Shop pulse (Item Shop button breathe).
 * @property spotlight The selected player's effective row per chart (shown after the preview when outside the top ten).
 * @property shopUrl Validated official Shop URL for this song, or null.
 * @property shopError A Shop read failed (the offer can't be confirmed).
 * @property pathInstruments Path-capable charts; empty hides Paths.
 * @property historyLeeway Filter Invalid Scores leeway for the score history, or null when off.
 */
data class SongDetailExtras(
    val visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    val selectedAccountId: String? = null,
    val shopHighlight: ShopHighlight? = null,
    val shopPulse: ShopPulse? = null,
    val spotlight: Map<Instrument, LeaderboardEntry> = emptyMap(),
    val shopUrl: String? = null,
    val shopError: Boolean = false,
    val pathInstruments: List<Instrument> = emptyList(),
    val historyLeeway: Double? = null,
)

// endregion

// region Song detail

/**
 * Song Detail (web `SongDetailPage`): a spinner until the song, every visible chart's
 * ten-row preview and the selected player's score history have settled, then the page
 * fades in with the web's stagger (operator 6.41). The header (album art, title,
 * "artist · year · length") scrolls away with the page, and the top bar shows the title
 * once it has (6.40). Order: header, actions, Intensity, Score History (6.39),
 * instrument leaderboards (two columns on wide panes, split at a book-posture hinge,
 * 6.31), band leaderboards.
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
    val listState = rememberLazyListState()
    val headerGone by remember(listState) { derivedStateOf { listState.firstVisibleItemIndex > 0 } }
    val body: @Composable (PaddingValues) -> Unit = { padding ->
        when (val state = songState) {
            LoadState.Loading -> LoadingView("Loading song", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(state.issue, "Song unavailable", state.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> SongDetailGate(state.value, viewModel, extras, artworkUrl(state.value.albumArt), padding, onOpenPaths, embedded, listState)
        }
    }
    if (embedded) {
        val shell = LocalShellActions.current
        val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        body(PaddingValues(top = statusTop + 8.dp, bottom = shell.bottomPadding.calculateBottomPadding()))
    } else {
        // Paths lives in the dock (floating toolbar on phones, top bar elsewhere), like the web.
        FestivalScreen(
            title = if (headerGone && song != null) song.title else "",
            isRoot = false,
            scrolled = headerGone,
            actions = {
                if (song != null && extras.pathInstruments.isNotEmpty()) {
                    IconButton(onClick = { onOpenPaths(song) }, modifier = Modifier.testTag("fst.song-detail.paths.open")) {
                        Icon(Icons.Filled.Route, contentDescription = "View Paths")
                    }
                }
            },
            content = body,
        )
    }
}

/**
 * Starts every visible chart's preview and the score history together and shows the
 * shared load gate's spinner until all have settled (loaded or failed), like the web's
 * `allReady` gate, then fades the spinner and staggers the page in. Returning to a page
 * whose data is still cached shows it at once (no fade).
 */
@Composable
private fun SongDetailGate(
    song: Song,
    viewModel: SongDetailViewModel,
    extras: SongDetailExtras,
    artUrl: String?,
    padding: PaddingValues,
    onOpenPaths: (Song) -> Unit,
    embedded: Boolean,
    listState: androidx.compose.foundation.lazy.LazyListState,
) {
    val charts = remember(song, extras.visibleInstruments) { Instrument.entries.filter { song.supports(it) && it in extras.visibleInstruments } }
    val flows = remember(song, charts) { viewModel.startPreviews(song, charts) }
    val previews = charts.mapIndexed { index, chart -> key(chart) { flows[index].collectAsStateWithLifecycle() } }
    val historyFlow = remember(song, extras.selectedAccountId) { extras.selectedAccountId?.let { viewModel.history(song, it) } }
    val history: State<LoadState<PlayerHistoryPayload>>? = historyFlow?.collectAsStateWithLifecycle()
    val ready = SongDetailLayout.ready(previews.map { it.value == LoadState.Loading }, history?.let { it.value == LoadState.Loading })
    FestivalLoadGate(ready, Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()), label = "Loading song") {
        SongDetailContent(song, viewModel, extras, artUrl, PaddingValues(bottom = padding.calculateBottomPadding()), onOpenPaths, embedded, listState, charts, previews.map { it.value }, history?.value, revealed)
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
    embedded: Boolean,
    listState: androidx.compose.foundation.lazy.LazyListState,
    cards: List<Instrument>,
    previews: List<LoadState<LeaderboardPayload>>,
    history: LoadState<PlayerHistoryPayload>?,
    revealed: Boolean,
) {
    val navigate = LocalShellActions.current.navigate
    val charted = Instrument.entries.filter(song::supports)
    val historyRows = remember(history, extras.historyLeeway, song) {
        val payload = (history as? LoadState.Loaded)?.value?.takeIf { it.state == PlayerHistoryState.Available }
        payload?.let { SongHistoryChart.valid(it.response.history, song, extras.historyLeeway) }.orEmpty()
    }
    val showHistory = SongHistoryChart.available(SongHistoryChart.counts(historyRows), extras.visibleInstruments).isNotEmpty()
    val (hinge, hingeModifier) = rememberHingeSplit()
    BoxWithConstraints(Modifier.fillMaxSize().then(hingeModifier)) {
        val rowHinge = hinge?.let { HingeSplit(it.start - PAGE_GUTTER, it.end - PAGE_GUTTER) }
        val columns = SongDetailLayout.columns((maxWidth - PAGE_GUTTER * 2).value, cards.size, rowHinge != null)
        val rows = cards.chunked(columns)
        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = PAGE_GUTTER, end = PAGE_GUTTER, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.song-detail.list"),
        ) {
            // Web order: header, actions, intensity, score history, instrument leaderboards, band leaderboards.
            item(key = "header") { Box(Modifier.festivalFadeIn(revealed)) { SongHeader(song, artUrl) } }
            item(key = "actions") { HeaderActions(song, extras, onOpenPaths, showPaths = embedded) }
            item(key = "intensity") {
                Column(Modifier.festivalFadeIn(revealed, fadeInStagger(1))) {
                    SectionHeader("Intensity")
                    IntensityCard(song, charted)
                }
            }
            if (showHistory) {
                item(key = "history") {
                    SongHistoryCard(
                        entries = historyRows,
                        visible = extras.visibleInstruments,
                        keyboard = song.usesKeyboardIcon,
                        initialInstrument = null,
                        onViewAll = { chart -> navigate(PlayerHistoryRoute(song.songId, chart.wireId)) },
                        modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(2)),
                    )
                }
            }
            itemsIndexed(rows, key = { _, row -> row.joinToString { it.wireId } }) { rowIndex, row ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(3 + rowIndex))) {
                    CardGridRow(
                        cards = row.map { instrument ->
                            {
                                val state = previews[cards.indexOf(instrument)]
                                InstrumentCard(song, instrument, state, viewModel, extras, navigate)
                            }
                        },
                        columns = columns,
                        hinge = rowHinge,
                    )
                }
            }
            item(key = "bands") { Box(Modifier.festivalFadeIn(revealed, fadeInStagger(3 + rows.size))) { BandLinks(song, navigate) } }
        }
    }
}

/** Page side margin (M3 compact margin). */
private val PAGE_GUTTER = 16.dp

/**
 * The song header (web `SongInfoHeader`; operator 6.40: like iOS it scrolls away with
 * the page): album art, title and "artist · year · length", marqueeing when they
 * overflow. One heading stop.
 */
@Composable
internal fun SongHeader(song: Song, artUrl: String?, artSize: Dp = HEADER_ART) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
            .testTag("fst.song-detail.header"),
    ) {
        AsyncImage(
            model = artUrl,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(artSize).clip(RoundedCornerShape(12.dp)).background(BrandTokens.surfaceMuted),
        )
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { heading() }) {
            FestivalMarqueeText(song.title, style = MaterialTheme.typography.headlineSmall, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold)
            FestivalMarqueeText(song.subtitle, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textSecondary)
        }
    }
}

/** Header album art side. */
private val HEADER_ART = 88.dp

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HeaderActions(song: Song, extras: SongDetailExtras, onOpenPaths: (Song) -> Unit, showPaths: Boolean) {
    val hasShop = extras.shopUrl != null
    val paths = showPaths && extras.pathInstruments.isNotEmpty()
    if (!paths && !hasShop && !extras.shopError) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (paths) {
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

/**
 * Intensity for every charted instrument in two columns (web icon grid; operator 6.31:
 * two columns on unfolded/tablet widths too): icon + meter on compact panes, icon,
 * label and meter on wider ones. Each cell is one TalkBack stop naming the instrument
 * and its level.
 */
@Composable
private fun IntensityCard(song: Song, charted: List<Instrument>) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.song-detail.intensity")) {
        BoxWithConstraints(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            val labelled = maxWidth >= INTENSITY_LABEL_MIN_WIDTH
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                charted.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                        row.forEach { instrument ->
                            val raw = song.difficulty?.chartedValue(instrument) ?: Double.NaN
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier
                                    .weight(1f)
                                    .testTag("fst.song-detail.intensity.${instrument.wireId}")
                                    .clearAndSetSemantics { contentDescription = "${instrument.label}, ${DifficultyMeterSpec.accessibilityLabel(raw, raw = true)}" },
                            ) {
                                InstrumentIcon(instrument, keyboard = song.usesKeyboardIcon, size = 28.dp, decorative = true)
                                if (labelled) {
                                    Text(instrument.label, color = BrandTokens.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = 10.dp))
                                    DifficultyMeter(raw)
                                } else {
                                    // Web cell: icon, 12 px gap, meter, left-aligned in its column.
                                    DifficultyMeter(raw, Modifier.padding(start = 12.dp))
                                    Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** Card widths from which intensity cells carry the instrument name. */
private val INTENSITY_LABEL_MIN_WIDTH = 480.dp

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

// endregion

// region Instrument card

/**
 * One chart's card (web `InstrumentCard`): the instrument header above it, then the
 * top ten with separators (operator 6.5), the selected player's row highlighted and
 * bold in place or appended after a separator when outside the top ten (no separate
 * "Your score" line, 6.38), and the shared purple "View full leaderboard" (6.29).
 */
@Composable
private fun InstrumentCard(
    song: Song,
    instrument: Instrument,
    state: LoadState<LeaderboardPayload>,
    viewModel: SongDetailViewModel,
    extras: SongDetailExtras,
    navigate: (AppRoute) -> Unit,
) {
    val board = (state as? LoadState.Loaded)?.value?.leaderboard
    Column {
        CardHeader(song, instrument, board?.let { if (it.entries.isEmpty()) 0 else it.totalEntries })
        GlassCard(Modifier.fillMaxWidth().testTag("fst.song-detail.preview.${instrument.wireId}")) {
            Column(Modifier.padding(vertical = 4.dp)) {
                when (state) {
                    LoadState.Loading -> Box(Modifier.fillMaxWidth().heightIn(min = 96.dp), contentAlignment = Alignment.Center) {
                        FestivalLoading(null, size = 28.dp)
                    }
                    is LoadState.Failed -> ServiceStatusInline(
                        state.issue, "${instrument.label} scores unavailable", state.countdown,
                        onRetry = { viewModel.retryPreview(instrument) },
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                    is LoadState.Loaded -> {
                        val entries = state.value.leaderboard.entries
                        val mine = extras.spotlight[instrument]?.takeIf { row ->
                            row.rank > LeaderboardPaging.PREVIEW_SIZE && entries.none { RankingSpotlight.isSelected(row.accountId, it.accountId) }
                        }
                        if (entries.isEmpty() && mine == null) {
                            EmptyChart(instrument)
                        } else {
                            val rankWidth = rememberRankWidth(entries.map { it.rank } + listOfNotNull(mine?.rank))
                            entries.forEachIndexed { index, entry ->
                                if (index > 0) RowSeparator()
                                PreviewRow(
                                    entry = entry,
                                    isSelected = RankingSpotlight.isSelected(extras.selectedAccountId, entry.accountId),
                                    route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, extras.selectedAccountId),
                                    instrument = instrument,
                                    rankWidth = rankWidth,
                                    onOpen = navigate,
                                )
                            }
                            // The selected player outside the top ten follows (web spotlight footer); it opens their page.
                            mine?.let { row ->
                                RowSeparator()
                                Box(Modifier.testTag("fst.song-detail.your-rank.${instrument.wireId}")) {
                                    PreviewRow(
                                        entry = row,
                                        isSelected = true,
                                        route = SongLeaderboardRoute(song.songId, instrument.wireId, LeaderboardPaging.pageForRank(row.rank)),
                                        instrument = instrument,
                                        rankWidth = rankWidth,
                                        onOpen = navigate,
                                    )
                                }
                            }
                            if (entries.isNotEmpty()) {
                                ViewFullLeaderboardButton(
                                    onClick = { navigate(SongLeaderboardRoute(song.songId, instrument.wireId)) },
                                    testTag = "fst.song-detail.view-all.${instrument.wireId}",
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A hairline between rows of a multi-entry card (operator 6.5). */
@Composable
internal fun RowSeparator() {
    HorizontalDivider(color = BrandTokens.glassBorder, modifier = Modifier.padding(horizontal = 12.dp))
}

/** Web `InstrumentEmptyState` (`songDetail.noScores` + subtitle). */
@Composable
private fun EmptyChart(instrument: Instrument) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 20.dp).testTag("fst.song-detail.empty.${instrument.wireId}"),
    ) {
        Text("No scores recorded yet.", color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(
            "When scores are submitted for ${instrument.label}, they will show up here on the next leaderboard update.",
            style = MaterialTheme.typography.bodySmall,
            color = BrandTokens.textSecondary,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * The instrument header above its card (web `InstrumentCard` header): icon, name
 * and the chart's total entries once the preview loads (nothing for an empty chart,
 * whose card shows the empty state).
 */
@Composable
private fun CardHeader(song: Song, instrument: Instrument, totalEntries: Int?) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp).semantics(mergeDescendants = true) { heading() }) {
        InstrumentIcon(instrument, keyboard = song.usesKeyboardIcon, size = 32.dp, decorative = true)
        Column(Modifier.padding(start = 10.dp)) {
            Text(instrument.label, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
            // An empty chart's card already says "No scores recorded yet." (web empty state).
            totalEntries?.takeIf { it > 0 }?.let {
                Text(
                    "${NumberFormat.getIntegerInstance().format(it)} total entries",
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.song-detail.total.${instrument.wireId}"),
                )
            }
        }
    }
}

@Composable
private fun PreviewRow(entry: LeaderboardEntry, isSelected: Boolean, route: AppRoute?, instrument: Instrument, rankWidth: Dp, onOpen: (AppRoute) -> Unit) {
    var modifier = Modifier.fillMaxWidth().selectedRowHighlight(isSelected)
    modifier = if (route != null) {
        modifier.clickable(role = Role.Button, onClickLabel = "Open profile") { onOpen(route) }
    } else {
        modifier.semantics { stateDescription = "Profile unavailable" }
    }
    Box(modifier.testTag("fst.song-detail.preview-row.${instrument.wireId}.${entry.accountId.ifEmpty { "rank-${entry.rank}" }}")) {
        ScoreRow(entry, isSelected = isSelected, rankWidth = rankWidth, navigable = route != null)
    }
}

// endregion

// region Score row

/**
 * Row inset plus the selected player's treatment (web `playerEntryRow`: purple
 * highlight with a purple border). Every row gets the same 4 dp inset so the selected
 * row's columns line up with the others (7.9) and separators stay visible.
 *
 * @param selected Whether this is the selected player's row.
 * @return Modifier.
 */
internal fun Modifier.selectedRowHighlight(selected: Boolean): Modifier {
    val shape = RoundedCornerShape(10.dp)
    val inset = padding(horizontal = 4.dp).clip(shape)
    return if (selected) inset.background(PurpleHighlight).border(1.dp, PurpleHighlightBorder, shape) else inset
}

/**
 * Rank column width for a card: the widest "#rank" plus breathing room (web
 * `computeRankWidth`), so short ranks don't push names right.
 *
 * @param ranks Ranks shown in the card.
 * @return Width.
 */
@Composable
internal fun rememberRankWidth(ranks: List<Int>): Dp {
    val measurer = rememberTextMeasurer()
    val style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold)
    val density = LocalDensity.current
    val widest = ranks.maxOrNull() ?: 1
    return remember(widest, style, density) {
        with(density) { measurer.measure("#${NumberFormat.getIntegerInstance().format(widest)}", style).size.width.toDp() + 12.dp }
    }
}

/**
 * One leaderboard row, the unified design shared with the rankings boards (7.7): rank,
 * name, score, the web accuracy pill (gold italic outline for an FC, 7.11) and an
 * in-card chevron on navigable rows (7.3; other rows keep the slot so columns align).
 * The selected player's texts are bold (web `LeaderboardEntry` `isPlayer`, 6.42).
 * Anonymous rows (no account) read "Unknown User". Read as one stop.
 *
 * @param entry Wire row.
 * @param showStars Show the star images after the score (wide rows, web `QUERY_SHOW_STARS`).
 * @param isSelected The selected player's row (bold).
 * @param rankWidth Rank column width (defaults to a four-digit rank).
 * @param navigable Draw the chevron.
 */
@Composable
fun ScoreRow(entry: LeaderboardEntry, showStars: Boolean = false, isSelected: Boolean = false, rankWidth: Dp = DEFAULT_RANK_WIDTH, navigable: Boolean = false) {
    val weight = if (isSelected) FontWeight.Bold else FontWeight.Normal
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .padding(horizontal = 8.dp)
            .semantics(mergeDescendants = true) { },
    ) {
        Text("#${NumberFormat.getIntegerInstance().format(entry.rank)}", style = MaterialTheme.typography.labelLarge, fontWeight = weight, color = BrandTokens.textPrimary, modifier = Modifier.width(rankWidth))
        Text(
            entry.displayName?.takeIf { it.isNotBlank() && entry.accountId.isNotEmpty() } ?: "Unknown User",
            color = BrandTokens.textPrimary,
            fontWeight = weight,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Text(
            ScoreFormatting.score(entry.score),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.SemiBold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(horizontal = 10.dp),
        )
        if (entry.accuracy != null) AccuracyPill(entry.accuracy, entry.isFullCombo == true) else Spacer(Modifier.width(56.dp))
        if (showStars) {
            Box(Modifier.padding(start = 10.dp).width(STAR_COLUMN_DP.dp), contentAlignment = Alignment.CenterEnd) {
                StarRating(entry.stars ?: 0, Modifier.testTag("fst.stars"), size = 20.dp)
            }
        }
        if (navigable) RowChevron(Modifier.padding(start = 4.dp)) else Spacer(Modifier.width(24.dp))
    }
}

/** Rank column when the caller doesn't measure (fits "#9,999"). */
private val DEFAULT_RANK_WIDTH = 52.dp

/** Width reserved for the stars column so scores stay aligned (web `StarSize.rowWidth`). */
private const val STAR_COLUMN_DP = 116

// endregion
