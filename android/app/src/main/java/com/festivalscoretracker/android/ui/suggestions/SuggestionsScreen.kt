package com.festivalscoretracker.android.ui.suggestions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.readingGroup
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsPhase
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsUiState
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.flow.distinctUntilChanged
import com.festivalscoretracker.android.ui.common.rememberMeasuredPx

// region Screen

/**
 * Suggestions (`/suggestions`): generated category cards for the selected player,
 * loaded incrementally as the list nears its end, with a persisted filter sheet.
 *
 * @param viewModel Page model.
 * @param isRoot Tab root (drawer + avatar) or pushed (back).
 * @param artworkUrl Resolves artwork references.
 * @param onSong Open Song Detail for a song ID.
 */
@Composable
fun SuggestionsScreen(viewModel: SuggestionsViewModel, isRoot: Boolean, artworkUrl: (String?) -> String?, onSong: (String) -> Unit) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val actions = remember(viewModel) {
        SuggestionsActions(viewModel::retry, viewModel::loadMore, viewModel::startNewMix, viewModel::applyFilter)
    }
    SuggestionsScreenContent(state, isRoot, artworkUrl, onSong, actions)
}

/**
 * User intents the stateless screen raises.
 *
 * @property retry Retry after a failure or while syncing.
 * @property loadMore Generate the next batch.
 * @property startNewMix Start a fresh mix after the cap.
 * @property applyFilter Apply and persist a filter.
 */
@Immutable
internal data class SuggestionsActions(
    val retry: () -> Unit = {},
    val loadMore: () -> Unit = {},
    val startNewMix: () -> Unit = {},
    val applyFilter: (SuggestionFilterSettings) -> Unit = {},
)

/**
 * Stateless Suggestions screen: chrome, the phase's content and the filter sheet.
 *
 * @param state Screen state.
 * @param isRoot Tab root or pushed.
 * @param artworkUrl Resolves artwork references.
 * @param onSong Open Song Detail.
 * @param actions User intents.
 */
@Composable
internal fun SuggestionsScreenContent(
    state: SuggestionsUiState,
    isRoot: Boolean,
    artworkUrl: (String?) -> String?,
    onSong: (String) -> Unit,
    actions: SuggestionsActions,
) {
    var showFilter by rememberSaveable { mutableStateOf(false) }
    FestivalScreen(
        title = "Suggestions",
        isRoot = isRoot,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        // Filter stays reachable while the cards scroll (issue #52), and TalkBack reaches it before
        // the endless feed rather than after it (issue #112).
        pinActions = true,
        actionsReadFirst = true,
        actions = {
            if (state.phase != SuggestionsPhase.NoPlayer) {
                val active = state.filter.isActive
                IconButton(
                    onClick = { showFilter = true },
                    modifier = Modifier
                        .testTag("fst.suggestions.filter-button")
                        .semantics { contentDescription = if (active) "Filter Suggestions, filters on" else "Filter Suggestions" },
                ) {
                    Icon(Icons.Outlined.FilterList, contentDescription = null, tint = if (active) BrandTokens.gold else BrandTokens.textPrimary)
                }
            }
        },
    ) { padding ->
        SuggestionsContent(state, padding, actions, artworkUrl, onSong)
    }
    if (showFilter) {
        SuggestionsFilterSheet(
            filter = state.filter,
            instruments = state.visibleInstruments,
            onChange = actions.applyFilter,
            onDismiss = { showFilter = false },
        )
    }
}

@Composable
private fun SuggestionsContent(
    state: SuggestionsUiState,
    padding: PaddingValues,
    actions: SuggestionsActions,
    artworkUrl: (String?) -> String?,
    onSong: (String) -> Unit,
) {
    val shell = LocalShellActions.current
    when (state.phase) {
        SuggestionsPhase.NoPlayer -> Message(
            "No suggestions available.",
            "Select a player profile to get personalized suggestions.",
            padding,
            "fst.suggestions.choose-profile",
            "Choose Profile",
            shell.openProfile,
        )
        SuggestionsPhase.Loading -> LoadingView("Loading suggestions", Modifier.padding(padding).testTag("fst.suggestions.loading"))
        SuggestionsPhase.Syncing -> ServiceStatusView(
            ServiceIssue.Syncing, "Suggestions unavailable", null, actions.retry,
            Modifier.testTag("fst.suggestions.syncing"), padding,
        )
        SuggestionsPhase.Failed -> ServiceStatusView(
            state.issue ?: ServiceIssue.Other("Something went wrong. Try again."), "Suggestions unavailable", state.countdown, actions.retry,
            Modifier.testTag("fst.suggestions.error"), padding,
        )
        SuggestionsPhase.Empty -> if (state.filteredOut) {
            Message(
                "No suggestions available.",
                "Try changing your filters to see more suggestions.",
                padding,
                "fst.suggestions.reset-filters",
                "Reset Filters",
            ) { actions.applyFilter(SuggestionFilterSettings.DEFAULTS) }
        } else {
            Message("No suggestions available.", "Play some songs first!", padding)
        }
        SuggestionsPhase.Loaded -> SuggestionsGrid(state, padding, actions, artworkUrl, onSong)
    }
}

/** Centered title, subtitle and optional action (web `EmptyState`). */
@Composable
private fun Message(title: String, subtitle: String, padding: PaddingValues, tag: String? = null, action: String? = null, onAction: () -> Unit = {}) {
    Column(
        Modifier.fillMaxSize().padding(padding).padding(24.dp).testTag("fst.suggestions.no-results"),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
        Text(subtitle, color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
        if (action != null && tag != null) {
            FilledTonalButton(onClick = onAction, modifier = Modifier.heightIn(min = 48.dp).testTag(tag)) { Text(action) }
        }
    }
}

// endregion

// region Grid

/**
 * Two unequal columns split around a separating hinge (book fold half-open), so no
 * card straddles the fold.
 *
 * @property firstPx Width of the column before the hinge.
 */
@Immutable
internal data class HingeSplitCells(val firstPx: Int) : StaggeredGridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): IntArray {
        val usable = availableSize - spacing
        val first = firstPx.coerceIn(0, usable)
        return intArrayOf(first, usable - first)
    }
}

/**
 * Card columns for the current window: split at a separating vertical hinge,
 * otherwise as many ≥ [MIN_COLUMN] columns as fit.
 */
private data class GridColumns(val cells: StaggeredGridCells, val gap: Dp, val narrow: Boolean)

@Composable
private fun SuggestionsGrid(
    state: SuggestionsUiState,
    padding: PaddingValues,
    actions: SuggestionsActions,
    artworkUrl: (String?) -> String?,
    onSong: (String) -> Unit,
) {
    val gridState = rememberLazyStaggeredGridState()
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    var gridLeft by rememberMeasuredPx(0f)
    val cardCount = state.cards.size

    LaunchedEffect(state.mixId) { if (gridState.firstVisibleItemIndex > 0) gridState.scrollToItem(0) }
    // Web `getCardDelay`: each newly generated batch fades in, staggered from its first card;
    // cards already revealed (or scrolled back into view) show at once.
    var revealedCount by remember(state.mixId) { mutableIntStateOf(0) }
    var batchStart by remember(state.mixId) { mutableIntStateOf(0) }
    LaunchedEffect(state.mixId, cardCount) {
        if (cardCount > revealedCount) {
            batchStart = revealedCount
            withFrameNanos {}
        }
        revealedCount = cardCount
    }
    LaunchedEffect(gridState, cardCount, state.hasMore) {
        if (!state.hasMore) return@LaunchedEffect
        snapshotFlow { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1 }
            .distinctUntilChanged()
            .collect { last -> if (last >= cardCount - LOAD_TRIGGER_FROM_END) actions.loadMore() }
    }

    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { gridLeft = it.positionInWindow().x }) {
        val side = 16.dp
        val start = padding.calculateStartPadding(direction) + side
        val end = padding.calculateEndPadding(direction) + side
        val available = maxWidth - start - end
        val columns = with(density) {
            val hingeStart = hinge?.let { it.bounds.left.toDp() - gridLeft.toDp() - start }
            val hingeWidth = hinge?.let { (it.bounds.right - it.bounds.left).toDp() } ?: 0.dp
            if (hingeStart != null && hingeStart > MIN_HALF && hingeStart < available - MIN_HALF) {
                val gap = maxOf(hingeWidth, side)
                val first = hingeStart - (gap - hingeWidth) / 2
                GridColumns(HingeSplitCells(first.roundToPx()), gap, first < NARROW)
            } else {
                val count = maxOf(1, ((available + side) / (MIN_COLUMN + side)).toInt())
                GridColumns(StaggeredGridCells.Fixed(count), side, (available - side * (count - 1)) / count < NARROW)
            }
        }
        LazyVerticalStaggeredGrid(
            columns = columns.cells,
            state = gridState,
            contentPadding = PaddingValues(start = start, end = end, top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
            horizontalArrangement = Arrangement.spacedBy(columns.gap),
            verticalItemSpacing = 24.dp,
            modifier = Modifier.fillMaxSize().testTag("fst.suggestions.list"),
        ) {
            itemsIndexed(state.cards, key = { _, card -> card.id }, contentType = { _, _ -> "card" }) { index, card ->
                Box(Modifier.readingGroup()) {
                    SuggestionCardView(
                        card,
                        columns.narrow,
                        artworkUrl,
                        onSong,
                        Modifier.festivalFadeIn(index < revealedCount, fadeInStagger(index - batchStart)),
                    )
                }
            }
            if (state.hasMore) {
                item(key = "more", contentType = "more", span = StaggeredGridItemSpan.FullLine) {
                    Box(Modifier.fillMaxWidth().padding(16.dp).testTag("fst.suggestions.loading-more"), contentAlignment = Alignment.Center) {
                        FestivalLoading("Loading more suggestions")
                    }
                }
            }
            if (state.reachedLimit) {
                item(key = "limit", contentType = "limit", span = StaggeredGridItemSpan.FullLine) {
                    Column(
                        Modifier.fillMaxWidth().padding(16.dp).testTag("fst.suggestions.mix-limit"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("You've reached 1,000 suggestions in this mix.", color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
                        FilledTonalButton(onClick = actions.startNewMix, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.suggestions.start-new-mix")) {
                            Text("Start a New Mix")
                        }
                    }
                }
            }
        }
    }
}

/** Load the next batch once the third-from-last card is visible (web sentinel). */
private const val LOAD_TRIGGER_FROM_END = 3

/** Narrowest comfortable card column. */
private val MIN_COLUMN = 400.dp

/** Below this card width, row metadata moves to a second line (web `useIsNarrow`). */
private val NARROW = 420.dp

/** Smallest half worth splitting around a hinge. */
private val MIN_HALF = 240.dp

// endregion
