package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.ProfileRow
import com.festivalscoretracker.android.core.profile.ProfileSections
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.presentation.profile.PlayerIdentityAction
import com.festivalscoretracker.android.presentation.profile.PlayerInstrumentSection
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.presentation.profile.PlayerProfileViewModel
import com.festivalscoretracker.android.presentation.profile.PlayerStatTile
import com.festivalscoretracker.android.presentation.profile.ProfileActionResult
import com.festivalscoretracker.android.presentation.profile.ProfilePhase
import com.festivalscoretracker.android.presentation.profile.RankHistoryLoad
import com.festivalscoretracker.android.presentation.profile.RankLoad
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.launch

// region Screens

/**
 * `/player/:accountId`, pushed on the current tab.
 *
 * @param viewModel Page model for the viewed account.
 */
@Composable
fun PlayerProfileScreen(viewModel: PlayerProfileViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    ProfileScaffold(viewModel, title = state.displayName.ifEmpty { "Player" }, isRoot = false, tag = "fst.player")
}

/**
 * The Statistics tab root: the selected player's profile.
 *
 * @param viewModel Page model following the selection.
 * @param isRoot Whether shown as the tab root (else pushed from the drawer or Compete).
 */
@Composable
fun StatisticsScreen(viewModel: PlayerProfileViewModel, isRoot: Boolean = true) {
    ProfileScaffold(viewModel, title = "Statistics", isRoot = isRoot, tag = "fst.statistics")
}

/**
 * Top bar, Quick Links (top-bar entry: menu on medium+ windows, sheet on compact; formerly a trailing pane on wide pages without a
 * fold) and the profile body.
 */
@Composable
private fun ProfileScaffold(viewModel: PlayerProfileViewModel, title: String, isRoot: Boolean, tag: String) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val gridState = rememberLazyStaggeredGridState()
    val loaded = state.phase == ProfilePhase.Loaded
    val visible = state.instruments.map { it.instrument }
    val rows = remember(visible, loaded) { if (loaded) ProfileSections.rows(visible) else emptyList() }
    val sections = remember(visible, loaded, state.displayName) { if (loaded) ProfileSections.quickLinks(visible, state.displayName) else emptyList() }
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", sections) { id ->
        rows.indexOfFirst { it.key == ProfileSections.rowKey(id) }.takeIf { it >= 0 }
    }
    val density = LocalDensity.current
    val windowWidthDp = with(density) { currentWindowSize().width.toDp().value.toInt() }
    val scrolled by remember(gridState) { derivedStateOf { gridState.canScrollBackward } }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        FestivalScreen(
            title = title,
            isRoot = isRoot,
            scrolled = scrolled,
            actions = { QuickLinksAction(quickLinks, windowWidthDp) },
            modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag(tag),
        ) { padding ->
            Box(Modifier.fillMaxSize()) { PlayerProfileContent(viewModel, padding, gridState, rows) }
        }
    }
}

// endregion

// region Content

/**
 * The shared player-profile body: header with identity actions, Overview, one card
 * per Settings-visible chart (stats, global rank, rank history, percentiles), top and
 * bottom five songs per chart and the Bands link. Select/Switch/Deselect never
 * navigate away; stat tiles and song rows do (web `withProfileSwitch`).
 *
 * @param viewModel Page model.
 * @param padding Scaffold padding.
 * @param gridState Grid state shared with Quick Links.
 * @param rows Rows in page order.
 */
@Composable
fun PlayerProfileContent(viewModel: PlayerProfileViewModel, padding: PaddingValues, gridState: LazyStaggeredGridState, rows: List<ProfileRow>) {
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
        ProfilePhase.Loaded -> LoadedProfile(viewModel, state, padding, gridState, rows)
    }
}

@Composable
private fun LoadedProfile(viewModel: PlayerProfileViewModel, state: PlayerProfileUiState, padding: PaddingValues, gridState: LazyStaggeredGridState, rows: List<ProfileRow>) {
    val shell = LocalShellActions.current
    val ranks by viewModel.ranks.collectAsStateWithLifecycle()
    val histories by viewModel.rankHistories.collectAsStateWithLifecycle()
    val bands by viewModel.bands.collectAsStateWithLifecycle()
    var confirm by rememberSaveable { mutableStateOf<PlayerIdentityAction?>(null) }
    var pendingAction by remember { mutableStateOf<PlayerTileAction?>(null) }
    val scope = rememberCoroutineScope()
    val runAction: (PlayerTileAction, Boolean) -> Unit = { action, confirmed ->
        scope.launch {
            when (val result = viewModel.run(action, confirmed)) {
                is ProfileActionResult.Navigate -> shell.navigate(result.route)
                ProfileActionResult.ConfirmSwitch -> pendingAction = action
                ProfileActionResult.Unavailable -> Unit
            }
        }
    }
    val onAction: (PlayerTileAction) -> Unit = { runAction(it, false) }
    val direction = LocalLayoutDirection.current
    ProfileGrid(
        state = gridState,
        contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
        modifier = Modifier.padding(start = padding.calculateStartPadding(direction) + 16.dp, end = padding.calculateEndPadding(direction) + 16.dp),
    ) { split ->
        rows.forEach { row ->
            val span = if (row.fullWidth && !split) StaggeredGridItemSpan.FullLine else StaggeredGridItemSpan.SingleLane
            item(key = row.key, span = span) {
                Box(Modifier.festivalFadeIn(isLoaded = true)) {
                when (row) {
                    ProfileRow.Header -> Header(state, onSelect = {
                        if (state.identity == PlayerIdentityAction.Switch) confirm = PlayerIdentityAction.Switch else viewModel.select()
                    }, onDeselect = { confirm = PlayerIdentityAction.Deselect })
                    ProfileRow.Overview -> Column(Modifier.testTag("fst.player.overview")) {
                        SectionHeader("Overview")
                        TileFlow(state.overview, "overview", state, onAction)
                    }
                    is ProfileRow.InstrumentStats -> state.instruments.firstOrNull { it.instrument == row.instrument }?.let { section ->
                        LaunchedEffect(section.instrument, section.hasScores) { viewModel.ensureInstrument(section.instrument) }
                        InstrumentCard(
                            section = section,
                            rank = ranks[section.instrument],
                            history = histories[section.instrument],
                            state = state,
                            onAction = onAction,
                            onRetryRank = { viewModel.retryRank(section.instrument) },
                            onRetryHistory = { viewModel.retryRankHistory(section.instrument) },
                        )
                    }
                    ProfileRow.TopSongsHeading -> TopSongsHeading(state.displayName)
                    is ProfileRow.TopSongs -> state.topSongs.firstOrNull { it.instrument == row.instrument }?.let { top ->
                        TopSongsCard(top, state.displayName, state, onAction)
                    }
                    ProfileRow.Bands -> {
                        LaunchedEffect(state.accountId) { viewModel.ensureBands() }
                        ProfileBandsSection(state, bands, onRetry = viewModel::retryBands, onNavigate = shell.navigate)
                    }
                }
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
    pendingAction?.let { action ->
        // Web `ConfirmAlert` "Switch to {name}": a tile needs this player selected first.
        ConfirmDialog(
            title = "Switch to ${state.displayName}?",
            text = "In order to see ${state.displayName}'s scores, you will have to set them as your selected profile. Would you like to continue?",
            confirmLabel = "Switch",
            tag = "fst.player.action-switch-confirm",
            onConfirm = { pendingAction = null; runAction(action, true) },
            onDismiss = { pendingAction = null },
        )
    }
}

// endregion

// region Header

@Composable
private fun Header(state: PlayerProfileUiState, onSelect: () -> Unit, onDeselect: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.player.header")) {
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
                    Icon(Icons.Outlined.Info, contentDescription = null, tint = BrandTokens.textPrimary, modifier = Modifier.size(18.dp))
                    Text(notice, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 8.dp))
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
    state: PlayerProfileUiState,
    onAction: (PlayerTileAction) -> Unit,
    onRetryRank: () -> Unit,
    onRetryHistory: () -> Unit,
) {
    val instrument = section.instrument
    Column(Modifier.fillMaxWidth()) {
        // Web: the instrument header sits above its cards, never inside them.
        InstrumentHeading(instrument, "fst.player.instrument.${instrument.wireId}")
        GlassCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                if (!section.hasScores) {
                    Text(
                        "No ${instrument.label} scores recorded yet.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.testTag("fst.player.instrument-empty.${instrument.wireId}"),
                    )
                    return@Column
                }
                TileFlow(section.stats, instrument.wireId, state, onAction)
                SubHeader("Global Rank")
                GlobalRank(instrument, rank, state, onAction, onRetryRank)
                when (history) {
                    is RankHistoryLoad.Loaded -> history.chart?.let { chart ->
                        SubHeader("Rank History")
                        RankHistoryChart(chart, Modifier.festivalFadeIn(isLoaded = true).testTag("fst.player.rank-history.${instrument.wireId}"))
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
}

@Composable
internal fun InstrumentHeading(instrument: Instrument, tag: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 4.dp, bottom = 8.dp).testTag(tag)) {
        InstrumentIcon(instrument, size = 32.dp, decorative = true)
        Text(
            instrument.label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(start = 12.dp).semantics { heading() },
        )
    }
}

@Composable
private fun GlobalRank(instrument: Instrument, rank: RankLoad?, state: PlayerProfileUiState, onAction: (PlayerTileAction) -> Unit, onRetry: () -> Unit) {
    val tag = "fst.player.global-rank.${instrument.wireId}"
    when (rank) {
        null, RankLoad.Loading -> CircularProgressIndicator(Modifier.size(24.dp).testTag("$tag.loading"))
        RankLoad.Unranked -> Text(
            "Not yet ranked globally on ${instrument.label}.",
            style = MaterialTheme.typography.bodyMedium,
            color = BrandTokens.textPrimary,
            modifier = Modifier.testTag("$tag.unranked"),
        )
        is RankLoad.Available -> Box(Modifier.festivalFadeIn(isLoaded = true).testTag("$tag.available")) { TileFlow(rank.tiles, "rank.${instrument.wireId}", state, onAction) }
        is RankLoad.Failed -> Box(Modifier.testTag("$tag.error")) { ServiceStatusInline(rank.issue, "Global rank unavailable", null, onRetry) }
    }
}

@Composable
internal fun SubHeader(text: String, first: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.padding(top = if (first) 0.dp else 20.dp, bottom = 8.dp).semantics { heading() },
    )
}

// endregion

// region Tiles and messages

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TileFlow(tiles: List<PlayerStatTile>, scope: String, state: PlayerProfileUiState, onAction: (PlayerTileAction) -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        tiles.forEach { tile ->
            val action = tile.action?.takeIf(state::canRun)
            StatTile(
                tile,
                onClick = action?.let { { onAction(it) } },
                modifier = Modifier.widthIn(min = 104.dp).weight(1f).testTag("fst.player.tile.$scope.${tileSlug(tile.label)}"),
            )
        }
    }
}

/** "Songs Played" → `songs-played`. */
internal fun tileSlug(label: String): String = label.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')

/** TalkBack action label for a tile. */
internal fun actionLabel(action: PlayerTileAction): String = when (action) {
    is PlayerTileAction.FilterSongs -> "Show in Songs"
    is PlayerTileAction.OpenSong -> "Open song"
    is PlayerTileAction.OpenRankings -> "Open rankings"
}

@Composable
private fun StatTile(tile: PlayerStatTile, onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    val content: @Composable () -> Unit = {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            val stars = tile.stars
            if (stars != null) {
                StarRating(stars, Modifier.heightIn(min = 24.dp), size = 18.dp)
            } else {
                Text(
                    tile.value,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (tile.gold) BrandTokens.gold else BrandTokens.textPrimary,
                    maxLines = 2,
                )
            }
            Text(tile.label, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textPrimary, maxLines = 1)
        }
    }
    val color = BrandTokens.surfaceSubtle.copy(alpha = 0.7f)
    val shape = RoundedCornerShape(10.dp)
    if (onClick == null) {
        Surface(color = color, shape = shape, modifier = modifier.clearAndSetSemantics { contentDescription = tile.announcement }, content = content)
    } else {
        val label = tile.action?.let(::actionLabel)
        Surface(
            onClick = onClick,
            color = color,
            shape = shape,
            modifier = modifier.heightIn(min = 48.dp).clearAndSetSemantics {
                contentDescription = tile.announcement
                role = Role.Button
                onClick(label = label) { onClick(); true }
            },
            content = content,
        )
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
        Text(body, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        if (onRetry != null) {
            Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp).testTag("fst.player.retry")) { Text("Retry") }
        }
    }
}

// endregion
