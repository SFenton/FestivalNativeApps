package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.presentation.profile.PlayerIdentityAction
import com.festivalscoretracker.android.presentation.profile.PlayerInstrumentSection
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.presentation.profile.PlayerProfileViewModel
import com.festivalscoretracker.android.presentation.profile.PlayerStatTile
import com.festivalscoretracker.android.presentation.profile.ProfilePhase
import com.festivalscoretracker.android.presentation.profile.RankHistoryLoad
import com.festivalscoretracker.android.presentation.profile.RankLoad
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Screens

/**
 * `/player/:accountId`, pushed on the current tab.
 *
 * @param viewModel Page model for the viewed account.
 */
@Composable
fun PlayerProfileScreen(viewModel: PlayerProfileViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    FestivalScreen(title = state.displayName.ifEmpty { "Player" }, isRoot = false, modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("fst.player")) { padding ->
        PlayerProfileContent(viewModel, padding)
    }
}

/**
 * The Statistics tab root: the selected player's profile ("This Is Me").
 *
 * @param viewModel Page model following the selection.
 * @param isRoot Whether shown as the tab root (else pushed from the drawer or Compete).
 */
@Composable
fun StatisticsScreen(viewModel: PlayerProfileViewModel, isRoot: Boolean = true) {
    FestivalScreen(title = "Statistics", isRoot = isRoot, modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("fst.statistics")) { padding ->
        PlayerProfileContent(viewModel, padding)
    }
}

// endregion

// region Content

/**
 * The shared player-profile body: header with identity actions, Overview, one card
 * per Settings-visible chart (stats, global rank, rank history, percentiles) and
 * the Bands link. Select/Switch/Deselect never navigate away.
 *
 * @param viewModel Page model.
 * @param padding Scaffold padding.
 */
@Composable
fun PlayerProfileContent(viewModel: PlayerProfileViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    when (val phase = state.phase) {
        ProfilePhase.NoAccount -> Message(
            "No Profile Selected",
            "Select a player profile to see statistics.",
            padding,
            Modifier.testTag("fst.player.no-profile"),
        )
        ProfilePhase.Loading -> Box(Modifier.fillMaxSize().padding(padding).testTag("fst.player.loading"), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        ProfilePhase.Syncing -> Message(
            "Still Syncing",
            "${state.displayName}'s public scores are still syncing. Try again shortly.",
            padding,
            Modifier.testTag("fst.player.syncing"),
            onRetry = viewModel::retry,
        )
        is ProfilePhase.Failed -> ServiceStatusView(phase.issue, "Profile unavailable", phase.countdown, viewModel::retry, contentPadding = padding)
        ProfilePhase.Loaded -> LoadedProfile(viewModel, state, padding)
    }
}

@Composable
private fun LoadedProfile(viewModel: PlayerProfileViewModel, state: PlayerProfileUiState, padding: PaddingValues) {
    val shell = LocalShellActions.current
    val ranks by viewModel.ranks.collectAsStateWithLifecycle()
    val histories by viewModel.rankHistories.collectAsStateWithLifecycle()
    var confirm by rememberSaveable { mutableStateOf<PlayerIdentityAction?>(null) }
    val direction = LocalLayoutDirection.current
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 340.dp),
        contentPadding = PaddingValues(
            start = padding.calculateStartPadding(direction) + 16.dp,
            end = padding.calculateEndPadding(direction) + 16.dp,
            top = padding.calculateTopPadding() + 8.dp,
            bottom = padding.calculateBottomPadding() + 24.dp,
        ),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize().testTag("fst.player.available"),
    ) {
        fullWidth("header") {
            Header(state, onSelect = {
                if (state.identity == PlayerIdentityAction.Switch) confirm = PlayerIdentityAction.Switch else viewModel.select()
            }, onDeselect = { confirm = PlayerIdentityAction.Deselect })
        }
        fullWidth("overview") {
            Column(Modifier.testTag("fst.player.overview")) {
                SectionHeader("Overview")
                TileFlow(state.overview)
            }
        }
        items(state.instruments, key = { it.instrument.wireId }) { section ->
            LaunchedEffect(section.instrument, section.hasScores) { viewModel.ensureInstrument(section.instrument) }
            InstrumentCard(
                section = section,
                rank = ranks[section.instrument],
                history = histories[section.instrument],
                onRetryRank = { viewModel.retryRank(section.instrument) },
                onRetryHistory = { viewModel.retryRankHistory(section.instrument) },
            )
        }
        fullWidth("bands") {
            GlassCard(
                onClick = { shell.navigate(PlayerBandsRoute(state.accountId, state.displayName)) },
                modifier = Modifier.fillMaxWidth().testTag("fst.player.bands-link"),
            ) {
                Row(Modifier.padding(16.dp).heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Groups, contentDescription = null, tint = BrandTokens.textPrimary)
                    Text(
                        "View ${state.displayName}'s Bands",
                        style = MaterialTheme.typography.titleSmall,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.padding(start = 12.dp),
                    )
                }
            }
        }
    }
    when (confirm) {
        PlayerIdentityAction.Switch -> ConfirmDialog(
            title = "Switch Profile?",
            text = "Scores and profile-dependent pages will update to ${state.displayName}.",
            confirmLabel = "Switch",
            tag = "fst.player.switch-confirm",
            onConfirm = { confirm = null; viewModel.select() },
            onDismiss = { confirm = null },
        )
        PlayerIdentityAction.Deselect -> ConfirmDialog(
            title = "Deselect Profile?",
            text = "Scores and profile-only content will be hidden; app Settings stay saved.",
            confirmLabel = "Deselect",
            tag = "fst.player.deselect-confirm",
            onConfirm = { confirm = null; viewModel.deselect() },
            onDismiss = { confirm = null },
        )
        else -> Unit
    }
}

private fun LazyGridScope.fullWidth(key: String, content: @Composable () -> Unit) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }) { content() }
}

// endregion

// region Header

@Composable
private fun Header(state: PlayerProfileUiState, onSelect: () -> Unit, onDeselect: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(56.dp).background(BrandTokens.accentPurple, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        SelectedPlayer(state.accountId, state.displayName).initials,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                    )
                }
                Column(Modifier.padding(start = 16.dp).weight(1f)) {
                    Text(
                        state.displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.testTag("fst.player.name").semantics { heading() },
                    )
                    Text(state.subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.testTag("fst.player.subtitle"))
                }
            }
            when (state.identity) {
                PlayerIdentityAction.Select, PlayerIdentityAction.Switch -> Button(
                    onClick = onSelect,
                    modifier = Modifier.padding(top = 12.dp).heightIn(min = 48.dp).testTag("fst.player.select"),
                ) { Text(state.selectLabel) }
                PlayerIdentityAction.Deselect -> OutlinedButton(
                    onClick = onDeselect,
                    modifier = Modifier.padding(top = 12.dp).heightIn(min = 48.dp).testTag("fst.player.deselect"),
                ) { Text("Deselect Profile") }
                else -> Unit
            }
            state.identityNotice?.let { notice ->
                Row(Modifier.padding(top = 12.dp).testTag("fst.player.identity-notice"), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Info, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.size(18.dp))
                    Text(notice, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, modifier = Modifier.padding(start = 8.dp))
                }
            }
            state.actionError?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp).testTag("fst.player.action-error"))
            }
        }
    }
}

@Composable
private fun ConfirmDialog(title: String, text: String, confirmLabel: String, tag: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = onConfirm, modifier = Modifier.testTag("$tag.ok")) { Text(confirmLabel) } },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.testTag("$tag.cancel")) { Text("Cancel") } },
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.testTag(tag),
    )
}

// endregion

// region Instrument card

@Composable
private fun InstrumentCard(
    section: PlayerInstrumentSection,
    rank: RankLoad?,
    history: RankHistoryLoad?,
    onRetryRank: () -> Unit,
    onRetryHistory: () -> Unit,
) {
    val instrument = section.instrument
    GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("fst.player.instrument.${instrument.wireId}")) {
                InstrumentIcon(instrument, size = 32.dp, decorative = true)
                Text(
                    instrument.label,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.padding(start = 12.dp).semantics { heading() },
                )
            }
            if (!section.hasScores) {
                Text(
                    "No ${instrument.label} scores recorded yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.padding(top = 12.dp).testTag("fst.player.instrument-empty.${instrument.wireId}"),
                )
                return@Column
            }
            Spacer(Modifier.size(12.dp))
            TileFlow(section.stats)
            SubHeader("Global Rank")
            GlobalRank(instrument, rank, onRetryRank)
            when (history) {
                is RankHistoryLoad.Loaded -> history.chart?.let { chart ->
                    SubHeader("Rank History")
                    RankHistoryChart(chart, Modifier.testTag("fst.player.rank-history.${instrument.wireId}"))
                }
                is RankHistoryLoad.Failed -> {
                    SubHeader("Rank History")
                    ServiceStatusInline(history.issue, "Rank history unavailable", null, onRetryHistory)
                }
                else -> Unit
            }
            if (section.percentiles.isNotEmpty()) {
                SubHeader("Percentiles")
                PercentileBars(section.percentiles, Modifier.testTag("fst.player.percentiles.${instrument.wireId}"))
            }
        }
    }
}

@Composable
private fun GlobalRank(instrument: Instrument, rank: RankLoad?, onRetry: () -> Unit) {
    val tag = "fst.player.global-rank.${instrument.wireId}"
    when (rank) {
        null, RankLoad.Loading -> CircularProgressIndicator(Modifier.size(24.dp).testTag("$tag.loading"))
        RankLoad.Unranked -> Text(
            "Not yet ranked globally on ${instrument.label}.",
            style = MaterialTheme.typography.bodyMedium,
            color = BrandTokens.textSecondary,
            modifier = Modifier.testTag("$tag.unranked"),
        )
        is RankLoad.Available -> Box(Modifier.testTag("$tag.available")) { TileFlow(rank.tiles) }
        is RankLoad.Failed -> Box(Modifier.testTag("$tag.error")) { ServiceStatusInline(rank.issue, "Global rank unavailable", null, onRetry) }
    }
}

@Composable
private fun SubHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.padding(top = 20.dp, bottom = 8.dp).semantics { heading() },
    )
}

// endregion

// region Tiles and messages

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TileFlow(tiles: List<PlayerStatTile>) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        tiles.forEach { tile -> StatTile(tile, Modifier.widthIn(min = 104.dp).weight(1f)) }
    }
}

@Composable
private fun StatTile(tile: PlayerStatTile, modifier: Modifier = Modifier) {
    Surface(
        color = BrandTokens.surfaceSubtle.copy(alpha = 0.7f),
        shape = RoundedCornerShape(10.dp),
        modifier = modifier.clearAndSetSemantics { contentDescription = tile.announcement },
    ) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            Text(
                tile.value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = if (tile.gold) BrandTokens.gold else BrandTokens.textPrimary,
                maxLines = 2,
            )
            Text(tile.label, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted, maxLines = 1)
        }
    }
}

@Composable
private fun Message(title: String, body: String, padding: PaddingValues, modifier: Modifier, onRetry: (() -> Unit)? = null) {
    Column(
        modifier.fillMaxSize().padding(padding).padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text(body, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        if (onRetry != null) {
            Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp).testTag("fst.player.retry")) { Text("Retry") }
        }
    }
}

// endregion
