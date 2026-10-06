package com.festivalscoretracker.android.ui.search

import androidx.compose.runtime.CompositionLocalProvider
import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import com.festivalscoretracker.android.ui.common.fadeInRushOnScroll
import com.festivalscoretracker.android.ui.common.LocalFadeInWindow
import android.os.Build
import android.view.View
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExpandedDockedSearchBar
import androidx.compose.material3.ExpandedFullScreenSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SearchBarState
import androidx.compose.material3.SearchBarValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.PopupProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.search.GlobalPlayerResult
import com.festivalscoretracker.android.core.search.GlobalSearchLayout
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchAnchor
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.SearchPresentation
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.presentation.search.SearchEmptyState
import com.festivalscoretracker.android.presentation.search.SectionPhase
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.SearchChrome
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.launch

// region Test IDs

/** `fst.global-search.*` test tags (`.agents/controls/global-search/spec.md#test-ids`). */
object GlobalSearchTags {
    /** Shell Search action (icon or persistent bar; one per window). */
    const val OPEN = "fst.global-search.open"

    /** The open surface. */
    const val SURFACE = "fst.global-search.surface"

    /** Text field. */
    const val FIELD = "fst.global-search.field"

    /** Clear-text button. */
    const val CLEAR = "fst.global-search.clear"

    /** Close (back arrow) button. */
    const val CLOSE = "fst.global-search.close"

    /** Short-query hint. */
    const val HINT = "fst.global-search.hint"

    /** Centred title-and-subtitle empty state (all empty, Songs empty, Players empty). */
    const val EMPTY = "fst.global-search.empty"

    /** Polite result-count status. */
    const val STATUS = "fst.global-search.status"

    /** Whole-panel progress, centred in the results region under the scope chips. */
    const val LOADING = "fst.global-search.loading"

    /** Band explanation block. */
    const val BANDS_UNAVAILABLE = "fst.global-search.bands-unavailable"

    /** Band explanation's Band Rankings button. */
    const val BANDS_RANKINGS = "fst.global-search.bands-unavailable.rankings"

    /** Song result row. */
    const val RESULT_SONG = "fst.global-search.result.song"

    /** Player result row. */
    const val RESULT_PLAYER = "fst.global-search.result.player"

    /**
     * Scope chip tag.
     *
     * @param scope Chip scope.
     * @return Tag.
     */
    fun scope(scope: SearchScope) = "fst.global-search.scope.${scope.token}"

    /** Scope pill row. */
    const val SCOPES = "fst.global-search.scopes"

    /** Players failure status (no Retry). */
    const val PLAYERS_ERROR = "fst.global-search.players-error"
}

// endregion

// region Entry point

/**
 * The one Search entry: a magnifier action in the top app bar (medium and wider windows) or in
 * the floating toolbar (compact windows). No persistent search field at any width.
 *
 * @param chrome Shell search hooks.
 */
@Composable
fun GlobalSearchEntry(chrome: SearchChrome) {
    val holder = remember { BoundsHolder() }
    IconButton(
        onClick = { chrome.open(holder.bounds) },
        modifier = Modifier
            .testTag(GlobalSearchTags.OPEN)
            .onGloballyPositioned { coordinates ->
                val r = coordinates.boundsInWindow()
                PxRect(r.left.toInt(), r.top.toInt(), r.right.toInt(), r.bottom.toInt()).also {
                    holder.bounds = it
                    chrome.report(it)
                }
            },
    ) {
        Icon(Icons.Filled.Search, contentDescription = "Search")
    }
}

/** Non-snapshot bounds holder so layout reports never trigger recomposition. */
private class BoundsHolder {
    var bounds: PxRect? = null
}

// endregion

// region Host

/**
 * Shell-level host for the expanded surface: an invisible anchor at [anchor] that the
 * Material search bar grows from, then `ExpandedFullScreenSearchBar` (compact) or
 * `ExpandedDockedSearchBar` (medium and wider) driven by [viewModel].
 *
 * @param viewModel Global search engine.
 * @param searchState Material search bar state (expanded flag mirrors the view model).
 * @param presentation Current presentation.
 * @param anchor Where the surface sits (window px) and the docked height cap.
 * @param artworkUrl Artwork resolver.
 * @param onOpen Navigate to a result's destination (after collapsing).
 * @param onBandRankings Open Band Rankings from the Bands explanation.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun GlobalSearchHost(
    viewModel: GlobalSearchViewModel,
    searchState: SearchBarState,
    presentation: SearchPresentation,
    anchor: SearchAnchor,
    artworkUrl: (String?) -> String?,
    onOpen: (SearchDestination) -> Unit,
    onBandRankings: () -> Unit,
) {
    val ui by viewModel.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current


    // The view model owns "open"; the Material state follows it, and a collapse the
    // Material bar makes on its own (back, scrim, Escape) closes the view model.
    LaunchedEffect(ui.expanded) {
        if (ui.expanded) searchState.animateToExpanded() else searchState.animateToCollapsed()
    }
    LaunchedEffect(searchState) {
        var seenExpanded = false
        snapshotFlow { searchState.currentValue }.collect { value ->
            if (value == SearchBarValue.Expanded) {
                seenExpanded = true
            } else if (seenExpanded) {
                seenExpanded = false
                viewModel.close()
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        with(density) {
            Box(
                Modifier
                    .offset { IntOffset(anchor.anchor.left, anchor.anchor.top) }
                    .size(anchor.anchor.width.coerceAtLeast(1).toDp(), anchor.anchor.height.coerceAtLeast(1).toDp())
                    .onGloballyPositioned { searchState.collapsedCoords = it },
            )
        }
    }

    val collapseThen: (() -> Unit) -> Unit = { action ->
        scope.launch {
            searchState.animateToCollapsed()
            viewModel.close()
            action()
        }
    }
    val colors = SearchBarDefaults.colors(containerColor = BrandTokens.cardBackground, dividerColor = BrandTokens.glassBorder)
    val inputField = @Composable {
        SearchField(
            ui = ui,
            viewModel = viewModel,
            expanded = searchState.targetValue == SearchBarValue.Expanded,
            colors = colors.inputFieldColors,
            onCollapse = { collapseThen {} },
        )
    }
    val dockedHeightPx = anchor.maxPanelHeight

    val content: @Composable () -> Unit = {
        GlobalSearchContent(
            ui = ui,
            artworkUrl = artworkUrl,
            onToggleScope = viewModel::toggleScope,
            onOpen = { destination -> collapseThen { onOpen(destination) } },
            onBandRankings = { collapseThen(onBandRankings) },
        )
    }
    // The expanded bar lives in its own dialog/popup window, so it re-enables resource-id tags there.
    val surfaceModifier = Modifier.testTag(GlobalSearchTags.SURFACE).semantics { isTraversalGroup = true; testTagsAsResourceId = true }
    when (presentation) {
        SearchPresentation.FullScreen -> ExpandedFullScreenSearchBar(
            state = searchState,
            inputField = inputField,
            colors = colors,
            modifier = surfaceModifier,
        ) { content() }
        SearchPresentation.Docked -> with(density) {
            ExpandedDockedSearchBar(
                state = searchState,
                inputField = inputField,
                colors = colors,
                // The popup's own Back/Escape handling is off: its overlay-priority Back callback
                // closed the panel together with the keyboard, and it swallowed Escape before the
                // field could clear the text. DockedPanelBack closes it once the keyboard is down.
                properties = PopupProperties(focusable = true, clippingEnabled = false, dismissOnBackPress = false),
                // A fixed height: the panel never shrinks or grows as results, progress and
                // hints replace each other while typing. Material pads the surface by the part
                // the keyboard covers (imePadding inside this modifier), so content needs no
                // inset of its own; adding one clipped the empty state twice over.
                modifier = surfaceModifier
                    .width(anchor.anchor.width.toDp())
                    .then(dockedHeightPx?.let { Modifier.height(it.toDp()) } ?: Modifier)
                    // Before API 33 (and on hardware keys the system still delivers), Back arrives
                    // as a key event once the keyboard has handled its own.
                    .onKeyEvent { event ->
                        if (event.key != Key.Back) return@onKeyEvent false
                        if (event.type == KeyEventType.KeyUp) collapseThen {}
                        true
                    },
            ) {
                DockedPanelBack { collapseThen {} }
                content()
            }
        }
    }
}

/**
 * Back for the docked panel's popup window on API 33+, at default priority so the keyboard's
 * own Back callback (registered when it shows, so newer) hides the keyboard first and the next
 * Back closes the panel.
 *
 * @param onBack Close the panel.
 */
@Composable
private fun DockedPanelBack(onBack: () -> Unit) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val view = LocalView.current
    val latest by rememberUpdatedState(onBack)
    DisposableEffect(view) {
        val registration = DockedBackApi33.register(view) { latest() }
        onDispose { registration?.invoke() }
    }
}

/** API 33 window back-callback registration, kept apart for class verification on older releases. */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private object DockedBackApi33 {
    /**
     * Registers [onBack] on [view]'s window dispatcher at default priority.
     *
     * @return Unregister action, or null when the view has no window dispatcher yet.
     */
    fun register(view: View, onBack: () -> Unit): (() -> Unit)? {
        val dispatcher = view.findOnBackInvokedDispatcher() ?: return null
        val callback = OnBackInvokedCallback { onBack() }
        dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
        return { dispatcher.unregisterOnBackInvokedCallback(callback) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchField(
    ui: GlobalSearchUiState,
    viewModel: GlobalSearchViewModel,
    expanded: Boolean,
    colors: TextFieldColors,
    onCollapse: () -> Unit,
) {
    SearchBarDefaults.InputField(
        query = ui.query,
        onQueryChange = viewModel::onQueryChange,
        // IME Search runs the text now and only closes the keyboard (web: Enter opens nothing); on a
        // failed or empty players result it runs it again (issue #299: there is no Retry button).
        onSearch = { viewModel.submit() },
        expanded = expanded,
        onExpandedChange = { if (!it) onCollapse() },
        placeholder = { Text(GlobalSearchResults.PLACEHOLDER, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = {
            IconButton(onClick = onCollapse, modifier = Modifier.testTag(GlobalSearchTags.CLOSE)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close search")
            }
        },
        trailingIcon = if (ui.query.isNotEmpty()) {
            {
                IconButton(onClick = viewModel::clearQuery, modifier = Modifier.testTag(GlobalSearchTags.CLEAR)) {
                    Icon(Icons.Filled.Close, contentDescription = "Clear search")
                }
            }
        } else {
            null
        },
        colors = colors,
        modifier = Modifier
            // Fill the docked panel (Material measures the field loosely, at its 360 dp minimum).
            .fillMaxWidth()
            .testTag(GlobalSearchTags.FIELD)
            .semantics { contentDescription = GlobalSearchResults.FIELD_NAME }
            // Escape clears the text first, then collapses (adaptive quality Keyboard_Exit).
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown || event.key != Key.Escape) return@onPreviewKeyEvent false
                if (ui.query.isNotEmpty()) viewModel.clearQuery() else onCollapse()
                true
            },
    )
}

// endregion

// region Content

/**
 * Chips, status and results for the expanded surface. Results carry no section titles: the scope
 * chips already name the scope (issue #299).
 *
 * @param ui Current state.
 * @param artworkUrl Artwork resolver.
 * @param onToggleScope Toggle a scope chip.
 * @param onOpen Open a result.
 * @param onBandRankings Open Band Rankings.
 */
@Composable
fun GlobalSearchContent(
    ui: GlobalSearchUiState,
    artworkUrl: (String?) -> String?,
    onToggleScope: (SearchScope) -> Unit,
    onOpen: (SearchDestination) -> Unit,
    onBandRankings: () -> Unit,
) {
    // Fills the surface: every state (hint, progress, results) shares one full-height region,
    // so nothing resizes while typing.
    Column(Modifier.fillMaxSize()) {
        ScopePills(ui.scope, onToggleScope)
        // Result counts are spoken, not shown (operator batch 6): an undrawn polite live region.
        val announcement = ui.announcement
        if (announcement != null && !ui.isBandsScope && !ui.isShortQuery) {
            Box(
                Modifier
                    .size(1.dp)
                    .testTag(GlobalSearchTags.STATUS)
                    .semantics {
                        contentDescription = announcement
                        liveRegion = LiveRegionMode.Polite
                    },
            )
        }
        Box(Modifier.fillMaxWidth().weight(1f)) {
            when {
                ui.hint != null -> CenteredMessage(ui.hint!!)
                ui.isBandsScope -> BandsUnavailable(onBandRankings)
                ui.emptyState != null -> EmptyResults(ui.emptyState!!)
                // The one spinner, centred in the region between the scope chips and the bottom
                // edge (the docked surface already sits above the keyboard), like the web panel
                // spinner (issue #299).
                ui.isBusy -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    FestivalLoading("Searching", Modifier.testTag(GlobalSearchTags.LOADING), size = 36.dp)
                }
                else -> Results(ui, artworkUrl, onOpen)
            }
        }
    }
}

/**
 * Songs / Players / Bands scope toggles as M3 filter chips with pill ends (web `aria-pressed`
 * pills). Tapping the selected chip returns to All, so at most one is selected; each chip is
 * an equal share of the row and at least 48 dp tall to touch. When large text makes a label
 * wider than its share, the row scrolls horizontally with natural-width chips instead of
 * clipping the label ([GlobalSearchLayout.scopeChipsFitEqually]).
 *
 * @param selected Current scope.
 * @param onToggle Toggle a chip.
 */
@Composable
private fun ScopePills(selected: SearchScope, onToggle: (SearchScope) -> Unit) {
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelLarge
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val rowWidthPx = constraints.maxWidth
        val equal = remember(rowWidthPx, labelStyle, density) {
            val widths = SearchScope.chips.map { measurer.measure(it.title, labelStyle, maxLines = 1).size.width.toFloat() }
            GlobalSearchLayout.scopeChipsFitEqually(widths, rowWidthPx, density.density)
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(GlobalSearchLayout.CHIP_GAP_DP.dp),
            modifier = Modifier
                .fillMaxWidth()
                .then(if (equal) Modifier else Modifier.horizontalScroll(rememberScrollState()))
                .padding(horizontal = GlobalSearchLayout.CHIP_ROW_PADDING_DP.dp, vertical = 4.dp)
                .selectableGroup()
                .testTag(GlobalSearchTags.SCOPES),
        ) {
            SearchScope.chips.forEach { chip ->
                val isSelected = selected == chip
                FilterChip(
                    selected = isSelected,
                    onClick = { onToggle(chip) },
                    label = {
                        Text(
                            chip.title,
                            maxLines = 1,
                            textAlign = TextAlign.Center,
                            modifier = if (equal) Modifier.fillMaxWidth() else Modifier,
                        )
                    },
                    shape = CircleShape,
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.Transparent,
                        labelColor = BrandTokens.textSecondary,
                        selectedContainerColor = BrandTokens.accentPurple.copy(alpha = 0.45f),
                        selectedLabelColor = BrandTokens.textPrimary,
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = isSelected,
                        borderColor = BrandTokens.glassBorder,
                        selectedBorderColor = BrandTokens.accentPurple,
                    ),
                    modifier = (if (equal) Modifier.weight(1f) else Modifier)
                        .heightIn(min = 40.dp)
                        .testTag(GlobalSearchTags.scope(chip)),
                )
            }
        }
    }
}

@Composable
private fun Results(ui: GlobalSearchUiState, artworkUrl: (String?) -> String?, onOpen: (SearchDestination) -> Unit) {
    // Web SearchModal restaggers once per content signature: hide for a frame when the result
    // set changes, then fade rows in (web fadeInUp, 125 ms stagger).
    val signature = remember(ui.songs, ui.players) { ui.songs.map { it.songId } to ui.players.map { it.accountId } }
    var settled by remember { mutableStateOf<Any?>(null) }
    LaunchedEffect(signature) { settled = signature }
    // The results' own fade window (web SearchModal `useStaggerRush`): scrolling the results
    // mid-entrance fades the rest in together (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    CompositionLocalProvider(LocalFadeInWindow provides fadeIn) {
        ResultsList(ui, rememberRevealed(settled == signature), Modifier.fadeInRushOnScroll(fadeIn), artworkUrl, onOpen)
    }
}

/**
 * The results list, inside the results' fade window.
 *
 * @param ui Search state.
 * @param revealed Whether the current result set may show ([rememberRevealed]).
 * @param modifier Modifier for the list.
 * @param artworkUrl Artwork URL resolver.
 * @param onOpen Opens a result.
 */
@Composable
private fun ResultsList(
    ui: GlobalSearchUiState,
    revealed: Boolean,
    modifier: Modifier,
    artworkUrl: (String?) -> String?,
    onOpen: (SearchDestination) -> Unit,
) {
    val playersOffset = if (ui.showSongsSection) ui.songs.size else 0
    // A new scope or query starts at the top: a kept state would pin the previously first
    // visible key (the first player after Players → All) and hide the songs above it.
    val listState = remember(ui.scope, ui.settledQuery) { LazyListState() }
    LazyColumn(modifier.fillMaxSize().testTag("fst.global-search.results"), state = listState) {
        if (ui.showSongsSection) {
            if (ui.songsPhase == SectionPhase.Failed) {
                item(key = "songs-failed") { InlineMessage(GlobalSearchResults.SONGS_FAILED) }
            }
            itemsIndexed(ui.songs, key = { _, song -> "s-${song.songId}" }) { index, song ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                    SongResultRow(song, artworkUrl(song.albumArt)) { onOpen(song.destination) }
                }
            }
        }
        if (ui.showPlayersSection) {
            if (ui.playersPhase == SectionPhase.Failed) {
                item(key = "players-failed") {
                    ServiceStatusInline(
                        issue = ui.playersIssue ?: return@item,
                        fallbackTitle = GlobalSearchResults.PLAYERS_UNAVAILABLE,
                        countdown = ui.playersCountdown,
                        onRetry = null,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag(GlobalSearchTags.PLAYERS_ERROR),
                    )
                }
            }
            itemsIndexed(ui.players, key = { _, player -> "p-${player.accountId}" }) { index, player ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(playersOffset + index))) {
                    PlayerResultRow(player) { onOpen(player.destination) }
                }
            }
        }
    }
}

@Composable
private fun SongResultRow(song: GlobalSongResult, artUrl: String?, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = song.accessibleName }
            .testTag(GlobalSearchTags.RESULT_SONG)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        AsyncImage(
            model = artUrl,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted),
        )
        Column(Modifier.weight(1f)) {
            FestivalMarqueeText(song.title, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textPrimary)
            FestivalMarqueeText(song.artist, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        }
    }
}

@Composable
private fun PlayerResultRow(player: GlobalPlayerResult, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = player.accessibleName }
            .testTag(GlobalSearchTags.RESULT_PLAYER)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Box(Modifier.size(40.dp).background(BrandTokens.accentPurple, CircleShape), contentAlignment = Alignment.Center) {
            Text(monogram(player.displayName), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        }
        Column(Modifier.weight(1f)) {
            FestivalMarqueeText(player.displayName, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textPrimary)
            Text(player.subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        }
    }
}

/**
 * One-letter avatar monogram.
 *
 * @param name Display name.
 * @return Uppercase first letter or digit, else `?`.
 */
internal fun monogram(name: String): String = name.firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: "?"

@Composable
private fun InlineMessage(text: String) {
    Text(text, color = BrandTokens.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}

@Composable
private fun CenteredMessage(text: String) {
    // Web: the hint ("Enter at least two characters…") is plain white text centred in the
    // results area, with no container.
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 32.dp),
    ) {
        Text(text, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.testTag(GlobalSearchTags.HINT))
    }
}

/**
 * The app's shared title-and-subtitle empty state, centred horizontally and vertically in the
 * results area above the keyboard (issue #99), with no Retry (issue #299). It scrolls instead of
 * clipping when large text outgrows a short window.
 *
 * @param empty Title and subtitle.
 */
@Composable
private fun EmptyResults(empty: SearchEmptyState) {
    BoxWithConstraints(Modifier.fillMaxSize().testTag(GlobalSearchTags.EMPTY)) {
        val viewport = maxHeight
        Box(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = viewport), contentAlignment = Alignment.Center) {
            FestivalEmptyState(title = empty.title, subtitle = empty.subtitle, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun BandsUnavailable(onBandRankings: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .background(BrandTokens.surfaceSubtle, RoundedCornerShape(12.dp))
            .padding(16.dp)
            .testTag(GlobalSearchTags.BANDS_UNAVAILABLE),
    ) {
        Text("Band search unavailable", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text(GlobalSearchResults.BANDS_UNAVAILABLE, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        TextButton(onClick = onBandRankings, modifier = Modifier.heightIn(min = 48.dp).testTag(GlobalSearchTags.BANDS_RANKINGS)) { Text("Band Rankings") }
    }
}

// endregion
