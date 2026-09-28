package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardScaffold
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.leaderboards.RankingsSkeletonRows
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Song leaderboard

/**
 * Full 25-row song leaderboard (`/songs/:songId/:instrument`) with the shared
 * rankings pager. Rows open the player's profile (Statistics for the selected
 * player, web `LeaderboardPage.tsx`); rows without a usable account ID are shown
 * but not interactive. The selected player's row is highlighted in place.
 *
 * @param viewModel Leaderboard logic.
 * @param selectedAccountId Selected player, or null.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SongLeaderboardScreen(viewModel: SongLeaderboardViewModel, selectedAccountId: String? = null) {
    val song by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val navigate = LocalShellActions.current.navigate
    val listState = rememberLazyListState()
    val title = (song as? LoadState.Loaded)?.value?.title ?: "Leaderboard"
    val loaded = (board as? LoadState.Loaded)?.value?.leaderboard

    LaunchedEffect(page) { listState.scrollToItem(0) }

    FestivalScreen(title = title, isRoot = false, modifier = Modifier.semantics { testTagsAsResourceId = true }) { padding ->
        val failed = board as? LoadState.Failed
        if (failed != null) {
            ServiceStatusView(failed.issue, "Leaderboard unavailable", failed.countdown, viewModel::retry, contentPadding = padding)
            return@FestivalScreen
        }
        RankingsBoardScaffold(
            padding = padding,
            listState = listState,
            idPrefix = "fst.song-leaderboard",
            loadingOverlay = false,
            controls = {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp).testTag("fst.song-leaderboard.instrument")) {
                    InstrumentIcon(viewModel.instrument, size = 32.dp, decorative = true)
                    Text(
                        viewModel.instrument.label,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.padding(start = 10.dp),
                    )
                }
            },
            footer = {},
            pager = { RankingsPager(page, loaded?.pageCount() ?: page, "fst.song-leaderboard", viewModel::goTo) },
        ) {
            item(key = "rows") {
                GlassCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(vertical = 6.dp)) {
                        when {
                            loaded == null -> RankingsSkeletonRows(10)
                            loaded.entries.isEmpty() -> Text("No scores yet", color = BrandTokens.textSecondary, modifier = Modifier.padding(16.dp))
                            else -> loaded.entries.forEach { entry ->
                                SongLeaderboardRow(
                                    entry = entry,
                                    isSelected = RankingSpotlight.isSelected(selectedAccountId, entry.accountId),
                                    route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selectedAccountId),
                                    onOpen = navigate,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * One score row, interactive when it has a usable account.
 *
 * @param entry Score row.
 * @param isSelected Selected player's row (accent treatment).
 * @param route Destination or null.
 * @param onOpen Navigation callback.
 */
@Composable
private fun SongLeaderboardRow(entry: LeaderboardEntry, isSelected: Boolean, route: AppRoute?, onOpen: (AppRoute) -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    var modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp).clip(shape)
    if (isSelected) modifier = modifier.background(BrandTokens.accentPurple.copy(alpha = 0.18f)).border(BorderStroke(1.dp, BrandTokens.accentPurple), shape)
    modifier = if (route != null) {
        modifier.clickable(role = Role.Button, onClickLabel = "Open profile") { onOpen(route) }
    } else {
        modifier.semantics { stateDescription = "Profile unavailable" }
    }
    Box(modifier.testTag("fst.song-leaderboard.row.${entry.accountId.ifEmpty { "rank-${entry.rank}" }}")) {
        ScoreRow(entry)
    }
}

// endregion
