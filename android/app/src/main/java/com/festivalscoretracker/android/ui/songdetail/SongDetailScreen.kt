package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Song detail

/**
 * Song Detail: header, Intensity for every charted instrument (even hidden ones),
 * then a lazily-loaded ten-row preview card per visible chart.
 *
 * @param viewModel Detail logic.
 * @param visibleInstruments Settings-visible charts.
 * @param artworkUrl Artwork resolver.
 * @param background Shared backdrop (receives this song's static cover).
 * @param embedded True inside a two-pane layout (no own top bar).
 * @param onOpenLeaderboard Open the full chart leaderboard.
 */
@Composable
fun SongDetailScreen(
    viewModel: SongDetailViewModel,
    visibleInstruments: Set<Instrument>,
    artworkUrl: (String?) -> String?,
    background: BackgroundController,
    embedded: Boolean,
    onOpenLeaderboard: (Song, Instrument) -> Unit,
) {
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val song = (songState as? LoadState.Loaded)?.value
    DisposableEffect(song?.albumArt) {
        val token = background.pushFocus(song?.albumArt)
        onDispose { background.popFocus(token) }
    }
    val body: @Composable (PaddingValues) -> Unit = { padding ->
        when (val state = songState) {
            LoadState.Loading -> LoadingView("Loading song", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(state.issue, "Song unavailable", state.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> SongDetailContent(state.value, viewModel, visibleInstruments, artworkUrl(state.value.albumArt), padding, onOpenLeaderboard)
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
    visibleInstruments: Set<Instrument>,
    artUrl: String?,
    padding: PaddingValues,
    onOpenLeaderboard: (Song, Instrument) -> Unit,
) {
    val charted = Instrument.entries.filter(song::supports)
    val cards = charted.filter { it in visibleInstruments }
    LazyColumn(
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize().testTag("fst.song-detail.list"),
    ) {
        item(key = "header") { SongHeader(song, artUrl) }
        item(key = "intensity-header") { SectionHeader("Intensity") }
        item(key = "intensity") { IntensityCard(song, charted) }
        items(cards, key = { it.wireId }) { instrument ->
            Column {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp)) {
                    InstrumentIcon(instrument, keyboard = song.usesKeyboardIcon, size = 28.dp, decorative = true)
                    Text(
                        instrument.label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.padding(start = 8.dp).semantics { heading() },
                    )
                }
                PreviewCard(song, instrument, viewModel, onOpenLeaderboard)
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
                Text(it, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textMuted)
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

@Composable
private fun PreviewCard(song: Song, instrument: Instrument, viewModel: SongDetailViewModel, onOpenLeaderboard: (Song, Instrument) -> Unit) {
    val state by viewModel.preview(song, instrument).collectAsStateWithLifecycle()
    GlassCard(Modifier.fillMaxWidth().testTag("fst.song-detail.preview.${instrument.wireId}")) {
        Column(Modifier.padding(vertical = 6.dp)) {
            when (val preview = state) {
                LoadState.Loading -> Box(Modifier.fillMaxWidth().heightIn(min = 96.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(28.dp))
                }
                is LoadState.Failed -> ServiceStatusInline(
                    preview.issue, "${instrument.label} scores unavailable", preview.countdown,
                    onRetry = { viewModel.retryPreview(instrument) },
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
                is LoadState.Loaded -> {
                    val entries = preview.value.leaderboard.entries
                    if (entries.isEmpty()) {
                        Text("No scores yet", color = BrandTokens.textSecondary, modifier = Modifier.padding(16.dp))
                    } else {
                        entries.forEach { ScoreRow(it) }
                        TextButton(
                            onClick = { onOpenLeaderboard(song, instrument) },
                            modifier = Modifier.padding(horizontal = 4.dp).heightIn(min = 48.dp).testTag("fst.song-detail.view-all.${instrument.wireId}"),
                        ) { Text("View Full Leaderboard") }
                    }
                }
            }
        }
    }
}

// endregion

// region Score row

/**
 * One leaderboard row: rank, name, accuracy (or FC) and score, read as one stop.
 *
 * @param entry Wire row.
 */
@Composable
fun ScoreRow(entry: LeaderboardEntry) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .padding(horizontal = 12.dp)
            .semantics(mergeDescendants = true) { },
    ) {
        Text("#${entry.rank}", style = MaterialTheme.typography.labelLarge, color = BrandTokens.textMuted, modifier = Modifier.width(56.dp))
        Text(
            entry.displayName ?: "Unknown player",
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
    }
}

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
