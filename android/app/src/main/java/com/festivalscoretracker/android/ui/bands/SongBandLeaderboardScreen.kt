package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.SongBandLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Screen

/**
 * `/songs/:songId/bands/:bandType`: song header, in-place band-size switcher,
 * 25-row pages of band scores. Rows open Band Detail with the type and team key.
 *
 * @param viewModel Board logic.
 * @param artworkUrl Artwork resolver.
 * @param background Shared backdrop (static song cover while visible).
 * @param onNavigate Push a route.
 */
@Composable
fun SongBandLeaderboardScreen(
    viewModel: SongBandLeaderboardViewModel,
    artworkUrl: (String?) -> String?,
    background: BackgroundController,
    onNavigate: (AppRoute) -> Unit,
) {
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val type by viewModel.bandType.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val song = (songState as? LoadState.Loaded)?.value
    DisposableEffect(song?.albumArt) {
        val token = background.pushFocus(song?.albumArt)
        onDispose { background.popFocus(token) }
    }
    // A page or band-size change reloads, so its rows fade in again (web stagger).
    val revealed = rememberRevealed(board is LoadState.Loaded)
    FestivalScreen(title = "${type.label} Leaderboard", isRoot = false, modifier = Modifier.testTag("fst.song-band-leaderboard.screen")) { padding ->
        BandReadableWidth {
            LazyColumn(
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize().testTag("fst.song-band-leaderboard.list"),
            ) {
                item(key = "header") { SongHeader(song, board, type, artworkUrl, onNavigate) }
                item(key = "sizes") {
                    BandSegmentedControl(
                        options = BandType.entries,
                        selected = type,
                        label = { it.label },
                        tag = { "fst.song-band-leaderboard.band-type.${it.wireId}" },
                        onSelect = viewModel::selectBandType,
                        modifier = Modifier.padding(vertical = 4.dp).testTag("fst.song-band-leaderboard.band-type-menu"),
                    )
                }
                when (val state = board) {
                    LoadState.Loading -> item(key = "loading") { LoadingView("Loading band scores", Modifier.heightIn(min = 240.dp)) }
                    is LoadState.Failed -> item(key = "error") {
                        ServiceStatusView(
                            state.issue,
                            "Band scores unavailable",
                            state.countdown,
                            viewModel::retry,
                            Modifier.height(360.dp).testTag("fst.song-band-leaderboard.error"),
                        )
                    }
                    is LoadState.Loaded -> {
                        val response = state.value
                        if (response.entries.isEmpty()) {
                            item(key = "empty") {
                                BandEmptyState(
                                    "No band scores found",
                                    "No ${type.label} scores have been recorded for this song yet.",
                                    "fst.song-band-leaderboard.empty",
                                )
                            }
                        }
                        itemsIndexed(response.entries, key = { _, entry -> entry.key }) { index, entry ->
                            Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                                BandScoreRow(entry, song) { onNavigate(BandRoute(entry.bandId.ifEmpty { entry.teamKey }, entry.membersLabel, entry.bandType, entry.teamKey)) }
                            }
                        }
                        item(key = "pager") { BandPager(page, response.pageCount(BandPaging.PAGE_SIZE), "fst.song-band-leaderboard", viewModel::goTo) }
                    }
                }
            }
        }
    }
}

@Composable
private fun SongHeader(
    song: Song?,
    board: LoadState<SongBandLeaderboardResponse>,
    type: BandType,
    artworkUrl: (String?) -> String?,
    onNavigate: (AppRoute) -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AsyncImage(
            model = artworkUrl(song?.albumArt),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(72.dp).clip(RoundedCornerShape(10.dp)).background(BrandTokens.surfaceMuted),
        )
        Column(Modifier.weight(1f)) {
            if (song != null) {
                BandTextLink(song.title, "fst.song-band-leaderboard.song") { onNavigate(SongDetailRoute(song.songId)) }
                val details = listOfNotNull(song.artist.ifEmpty { null }, song.year?.toString()).joinToString(" · ")
                if (details.isNotEmpty()) Text(details, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
            val total = (board as? LoadState.Loaded)?.value?.population
            if (total != null) {
                Text(
                    "${type.label} · ${BandFormatting.count(total.toLong())} ${if (total == 1) "entry" else "entries"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.song-band-leaderboard.subtitle"),
                )
            }
        }
    }
}

// endregion

// region Row

/**
 * One band score: rank, members with instruments and per-member scores, team
 * score, FC badge, accuracy and stars. The whole card opens Band Detail.
 *
 * @param entry Wire row.
 * @param song Song, for keyboard-variant icons.
 * @param onClick Open action.
 */
@Composable
private fun BandScoreRow(entry: SongBandLeaderboardEntry, song: Song?, onClick: () -> Unit) {
    val keyboard = song?.sig == "Keyboard"
    val accuracy = entry.accuracy?.let { if (it > 0) ScoreFormatting.accuracy(it) + "%" else null }
    val announcement = buildString {
        append("Rank ${entry.rank}, ${entry.membersLabel}, ${BandFormatting.count(entry.score)}")
        if (entry.isFullCombo == true) append(", full combo")
        accuracy?.let { append(", $it accuracy") }
        entry.stars?.takeIf { it > 0 }?.let { append(", $it stars") }
    }
    GlassCard(
        Modifier
            .fillMaxWidth()
            .testTag("fst.song-band-leaderboard.row.${entry.key}")
            .semantics(mergeDescendants = true) { contentDescription = announcement },
        onClick = onClick,
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                BandFormatting.rank(entry.rank),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.widthIn(min = 44.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                BandMember.distinct(entry.members).forEach { member ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        member.chartedInstruments.forEach { InstrumentIcon(it, keyboard = keyboard, size = 18.dp, decorative = true) }
                        FestivalMarqueeText(
                            member.resolvedName,
                            style = MaterialTheme.typography.bodyMedium,
                            color = BrandTokens.textPrimary,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        member.score?.let { Text(BandFormatting.count(it), style = MaterialTheme.typography.bodySmall, color = BrandTokens.textMuted) }
                    }
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(BandFormatting.count(entry.score), fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (entry.isFullCombo == true) {
                        Text(
                            "FC",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = BrandTokens.gold,
                            modifier = Modifier
                                .border(BorderStroke(1.dp, BrandTokens.gold), RoundedCornerShape(50))
                                .padding(horizontal = 6.dp, vertical = 1.dp),
                        )
                    }
                    accuracy?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textSecondary) }
                    entry.stars?.takeIf { it > 0 }?.let { Text("★ $it", style = MaterialTheme.typography.labelSmall, color = BrandTokens.gold) }
                }
            }
        }
    }
}

// endregion
