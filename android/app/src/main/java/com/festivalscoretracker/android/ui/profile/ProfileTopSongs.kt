package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.profile.PlayerSongPlacement
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.PlayerTopSongs
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Top songs

/**
 * "Top Songs Per Instrument" heading (web `top-heading`).
 *
 * @param displayName Player name.
 */
@Composable
internal fun TopSongsHeading(displayName: String) {
    Column(Modifier.fillMaxWidth().testTag("fst.player.top-songs")) {
        SectionHeader("Top Songs Per Instrument")
        Text(
            "$displayName's highest and lowest-ranked competitive songs per instrument, sorted by percentile.",
            style = MaterialTheme.typography.bodySmall,
            color = BrandTokens.textSecondary,
            modifier = Modifier.padding(horizontal = 4.dp),
        )
    }
}

/**
 * One chart's top five (and, with more than five ranked songs, bottom five) songs
 * (web `buildTopSongsItems`); rows open Song Detail.
 *
 * @param top Placements.
 * @param displayName Player name.
 * @param state Page state (decides whether rows are interactive).
 * @param onAction Row tap.
 */
@Composable
internal fun TopSongsCard(top: PlayerTopSongs, displayName: String, state: PlayerProfileUiState, onAction: (PlayerTileAction) -> Unit) {
    val instrument = top.instrument
    GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            InstrumentHeading(instrument, "fst.player.top-songs.${instrument.wireId}")
            if (top.isEmpty) {
                Text(
                    "No scores yet",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.padding(top = 12.dp).testTag("fst.player.top-songs-empty.${instrument.wireId}"),
                )
                Text(
                    "Play some songs on ${instrument.label} to see your stats appear here.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = BrandTokens.textSecondary,
                )
                return@Column
            }
            SongList("Top Five Songs", "$displayName's top ranked competitive songs on ${instrument.label}, sorted by percentile.", top.top, "top", state, onAction)
            if (top.bottom.isNotEmpty()) {
                SongList("Bottom Five Songs", "$displayName's lowest-ranked competitive songs on ${instrument.label}, sorted by percentile.", top.bottom, "bottom", state, onAction)
            }
        }
    }
}

@Composable
private fun SongList(
    title: String,
    description: String,
    rows: List<PlayerSongPlacement>,
    kind: String,
    state: PlayerProfileUiState,
    onAction: (PlayerTileAction) -> Unit,
) {
    SubHeader(title)
    Text(description, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(bottom = 8.dp))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            val action = PlayerTileAction.OpenSong(row.songId, row.instrument).takeIf(state::canRun)
            SongRow(row, action?.let { { onAction(it) } }, Modifier.testTag("fst.player.$kind-song.${row.instrument.wireId}.${row.songId}"))
        }
    }
}

@Composable
private fun SongRow(row: PlayerSongPlacement, onClick: (() -> Unit)?, modifier: Modifier) {
    val color = BrandTokens.surfaceSubtle.copy(alpha = 0.7f)
    val shape = RoundedCornerShape(10.dp)
    val semantics = Modifier.clearAndSetSemantics {
        contentDescription = row.announcement
        if (onClick != null) {
            role = Role.Button
            onClick(label = "Open song") { onClick(); true }
        }
    }
    val content: @Composable () -> Unit = {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = row.artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
            )
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(row.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (row.subtitle.isNotEmpty()) {
                    Text(row.subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Surface(color = BrandTokens.surfaceMuted, shape = RoundedCornerShape(50)) {
                Text(
                    row.bucket,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (row.isTopFive) BrandTokens.gold else BrandTokens.textPrimary,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
        }
    }
    if (onClick == null) {
        Surface(color = color, shape = shape, modifier = modifier.fillMaxWidth().then(semantics), content = content)
    } else {
        Surface(onClick = onClick, color = color, shape = shape, modifier = modifier.fillMaxWidth().heightIn(min = 56.dp).then(semantics), content = content)
    }
}

// endregion
