package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Song leaderboard

/**
 * Full 25-row song leaderboard (`/songs/:songId/:instrument`) with paging.
 *
 * @param viewModel Leaderboard logic.
 */
@Composable
fun SongLeaderboardScreen(viewModel: SongLeaderboardViewModel) {
    val song by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val title = (song as? LoadState.Loaded)?.value?.title ?: "Leaderboard"
    FestivalScreen(title = title, isRoot = false) { padding ->
        when (val state = board) {
            LoadState.Loading -> LoadingView("Loading leaderboard", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(state.issue, "Leaderboard unavailable", state.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> {
                val response = state.value.leaderboard
                val pages = response.pageCount()
                LazyColumn(
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxSize().testTag("fst.song-leaderboard.list"),
                ) {
                    item(key = "header") {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
                            InstrumentIcon(viewModel.instrument, size = 32.dp, decorative = true)
                            Text(
                                viewModel.instrument.label,
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                color = BrandTokens.textPrimary,
                                modifier = Modifier.padding(start = 10.dp),
                            )
                        }
                    }
                    item(key = "rows") {
                        GlassCard(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(vertical = 6.dp)) {
                                if (response.entries.isEmpty()) {
                                    Text("No scores yet", color = BrandTokens.textSecondary, modifier = Modifier.padding(16.dp))
                                }
                                response.entries.forEach { ScoreRow(it) }
                            }
                        }
                    }
                    item(key = "pager") {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                            modifier = Modifier.fillMaxWidth().testTag("fst.song-leaderboard.pager"),
                        ) {
                            IconButton(onClick = { viewModel.goTo(page - 1) }, enabled = page > 1) {
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous page")
                            }
                            Text("Page $page of $pages", color = BrandTokens.textPrimary)
                            IconButton(onClick = { viewModel.goTo(page + 1) }, enabled = page < pages) {
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next page")
                            }
                        }
                    }
                }
            }
        }
    }
}

// endregion
