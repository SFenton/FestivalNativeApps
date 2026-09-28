package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.profile.PlayerScoreSortMode
import com.festivalscoretracker.android.presentation.profile.HistoryPhase
import com.festivalscoretracker.android.presentation.profile.PlayerHistoryViewModel
import com.festivalscoretracker.android.presentation.profile.ScoreHistoryRow
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Screen

/**
 * `/songs/:songId/:instrument/history`: the selected player's score changes, with
 * the web's sort modes (in memory only) and a score-over-time chart.
 *
 * @param viewModel Page model.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerHistoryScreen(viewModel: PlayerHistoryViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var sorting by rememberSaveable { mutableStateOf(false) }
    val sortLabel = "Sort by ${state.sortMode.label}, ${if (state.ascending) "ascending" else "descending"}"
    FestivalScreen(
        title = "Score History",
        isRoot = false,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("fst.history"),
        actions = {
            if (state.phase == HistoryPhase.Loaded) {
                IconButton(onClick = { sorting = true }, modifier = Modifier.testTag("fst.history.sort.open").semantics { contentDescription = sortLabel }) {
                    Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null)
                }
            }
        },
    ) { padding ->
        // Rows fade in (staggered) on the frame after the history loads (web FadeIn).
        val revealed = rememberRevealed(state.phase == HistoryPhase.Loaded)
        when (val phase = state.phase) {
            HistoryPhase.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            is HistoryPhase.Failed -> ServiceStatusView(phase.issue, "History unavailable", phase.countdown, viewModel::retry, contentPadding = padding)
            HistoryPhase.NoPlayer -> HistoryMessage("No Player Selected", "Select a player profile to see score history.", padding)
            HistoryPhase.Unregistered -> HistoryMessage("History Unavailable", "Score history is only available for registered users.", padding)
            HistoryPhase.Syncing -> HistoryMessage("Still Syncing", "This player's score history is still being prepared. Try again shortly.", padding, viewModel::retry)
            HistoryPhase.Empty -> HistoryMessage("No History Yet", "No score history for ${viewModel.instrument.label} on this song.", padding)
            HistoryPhase.Loaded -> {
                val direction = LocalLayoutDirection.current
                LazyColumn(
                    contentPadding = PaddingValues(
                        start = padding.calculateStartPadding(direction) + 16.dp,
                        end = padding.calculateEndPadding(direction) + 16.dp,
                        top = padding.calculateTopPadding() + 8.dp,
                        bottom = padding.calculateBottomPadding() + 24.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxSize().wrapContentWidth(Alignment.CenterHorizontally).widthIn(max = MAX_LIST_WIDTH).testTag("fst.history.rows"),
                ) {
                    item(key = "subtitle") {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.festivalFadeIn(revealed).testTag("fst.history.subtitle")) {
                            InstrumentIcon(viewModel.instrument, keyboard = state.keyboard, size = 28.dp, decorative = true)
                            Text(
                                listOfNotNull(state.songTitle, viewModel.instrument.label).joinToString(" · "),
                                style = MaterialTheme.typography.titleMedium,
                                color = BrandTokens.textPrimary,
                                modifier = Modifier.padding(start = 12.dp),
                            )
                        }
                    }
                    state.chart?.let { chart ->
                        item(key = "chart") {
                            GlassCard(Modifier.fillMaxWidth().festivalFadeIn(revealed, fadeInStagger(1))) {
                                Column(Modifier.padding(16.dp)) {
                                    Text("Score Over Time", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
                                    ScoreHistoryChart(chart, Modifier.padding(top = 12.dp))
                                }
                            }
                        }
                    }
                    itemsIndexed(state.rows, key = { index, row -> "${row.entry.dateKey}:$index" }) { index, row ->
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 2))) { HistoryRow(row) }
                    }
                }
            }
        }
    }
    if (sorting) {
        ModalBottomSheet(onDismissRequest = { sorting = false }, containerColor = BrandTokens.cardBackground, modifier = Modifier.testTag("fst.history.sort")) {
            SortSheet(
                mode = state.sortMode,
                ascending = state.ascending,
                onMode = viewModel::sortBy,
                onAscending = viewModel::setAscending,
                onReset = viewModel::resetSort,
            )
        }
    }
}

// endregion

// region Rows

/** Readable list width on tablets and unfolded windows. */
private val MAX_LIST_WIDTH = 840.dp

@Composable
private fun HistoryRow(row: ScoreHistoryRow) {
    val border = if (row.isHighScore) BorderStroke(1.dp, BrandTokens.gold) else BorderStroke(1.dp, BrandTokens.glassBorder)
    Surface(
        color = if (row.isHighScore) BrandTokens.accentPurple.copy(alpha = 0.25f) else BrandTokens.surfaceFrosted,
        shape = RoundedCornerShape(12.dp),
        border = border,
        modifier = Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = row.announcement },
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    row.score,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (row.isHighScore) BrandTokens.gold else BrandTokens.textPrimary,
                    modifier = Modifier.weight(1f),
                )
                StarRating(row.stars, Modifier.testTag("fst.history.stars"))
            }
            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    listOfNotNull(row.date, row.season).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.weight(1f),
                )
                row.accuracy?.let { accuracy ->
                    val tint = row.entry.accuracy?.let { ScoreFormatting.accuracyTint(it) }
                    Pill(accuracy, tint?.let { androidx.compose.ui.graphics.Color(0xFF000000 or it.toLong()).copy(alpha = 0.25f) } ?: BrandTokens.surfaceMuted)
                }
                if (row.isFullCombo) Pill("FC", BrandTokens.gold.copy(alpha = 0.25f))
            }
        }
    }
}

@Composable
private fun Pill(text: String, color: androidx.compose.ui.graphics.Color) {
    Surface(color = color, shape = RoundedCornerShape(50), modifier = Modifier.padding(start = 6.dp)) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
    }
}

@Composable
private fun HistoryMessage(title: String, body: String, padding: PaddingValues, onRetry: (() -> Unit)? = null) {
    Column(
        Modifier.fillMaxSize().padding(padding).padding(24.dp).testTag("fst.history.message"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text(body, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        if (onRetry != null) Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp).testTag("fst.history.retry")) { Text("Retry") }
    }
}

// endregion

// region Sort sheet

/**
 * Sort Scores sheet (web `PlayerScoreSortModal`): changes apply immediately, the
 * Material pattern for a lightweight sort sheet; Reset restores Score, descending.
 */
@Composable
private fun SortSheet(
    mode: PlayerScoreSortMode,
    ascending: Boolean,
    onMode: (PlayerScoreSortMode) -> Unit,
    onAscending: (Boolean) -> Unit,
    onReset: () -> Unit,
) {
    Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).widthIn(max = 560.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Sort Scores", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f).semantics { heading() })
            TextButton(onClick = onReset, modifier = Modifier.testTag("fst.history.sort.reset")) { Text("Reset") }
        }
        Column(Modifier.selectableGroup().padding(top = 8.dp)) {
            PlayerScoreSortMode.entries.forEach { option ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .selectable(selected = option == mode, role = Role.RadioButton) { onMode(option) }
                        .testTag("fst.history.sort.mode.${option.name.lowercase()}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(selected = option == mode, onClick = null)
                    Text(option.label, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = 16.dp)) {
            listOf(true to "Ascending", false to "Descending").forEachIndexed { index, (value, label) ->
                SegmentedButton(
                    selected = ascending == value,
                    onClick = { onAscending(value) },
                    shape = SegmentedButtonDefaults.itemShape(index, 2),
                    modifier = Modifier.testTag("fst.history.sort.direction.${label.lowercase()}"),
                ) { Text(label) }
            }
        }
    }
}

// endregion
