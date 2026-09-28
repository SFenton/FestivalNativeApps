package com.festivalscoretracker.android.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExpandedDockedSearchBar
import androidx.compose.material3.ExpandedFullScreenSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MultiChoiceSegmentedButtonRow
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SearchBarState
import androidx.compose.material3.SearchBarValue
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.search.GlobalPlayerResult
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchAnchor
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.SearchPresentation
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.presentation.search.SectionPhase
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

    /** Short-query / empty / error message. */
    const val HINT = "fst.global-search.hint"

    /** Polite result-count status. */
    const val STATUS = "fst.global-search.status"

    /** Whole-panel progress before the first rows. */
    const val LOADING = "fst.global-search.loading"

    /** Players inline progress. */
    const val PLAYERS_LOADING = "fst.global-search.players-loading"

    /** Retry (players empty / all empty). */
    const val RETRY = "fst.global-search.retry"

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

    /** Segmented scope row. */
    const val SCOPES = "fst.global-search.scopes"

    /**
     * Section heading tag.
     *
     * @param scope Section scope.
     * @return Tag.
     */
    fun section(scope: SearchScope) = "fst.global-search.section.${scope.token}"
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
    val content: @Composable () -> Unit = {
        GlobalSearchContent(
            ui = ui,
            artworkUrl = artworkUrl,
            onToggleScope = viewModel::toggleScope,
            onRetry = viewModel::retry,
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
                modifier = surfaceModifier
                    .width(anchor.anchor.width.toDp())
                    .then(anchor.maxPanelHeight?.let { Modifier.heightIn(max = it.toDp()) } ?: Modifier),
            ) { content() }
        }
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
        // IME Search runs the text now and only closes the keyboard (web: Enter opens nothing).
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
 * Chips, status, and grouped results for the expanded surface.
 *
 * @param ui Current state.
 * @param artworkUrl Artwork resolver.
 * @param onToggleScope Toggle a scope chip.
 * @param onRetry Retry the query.
 * @param onOpen Open a result.
 * @param onBandRankings Open Band Rankings.
 */
@Composable
fun GlobalSearchContent(
    ui: GlobalSearchUiState,
    artworkUrl: (String?) -> String?,
    onToggleScope: (SearchScope) -> Unit,
    onRetry: () -> Unit,
    onOpen: (SearchDestination) -> Unit,
    onBandRankings: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        // Scope toggles go above results (the IME covers the bottom): a full-width M3 segmented
        // row with equal segments. Multi-choice segments give toggle semantics like the web's
        // `aria-pressed` chips; tapping the pressed one returns to All, so at most one is on.
        MultiChoiceSegmentedButtonRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag(GlobalSearchTags.SCOPES),
        ) {
            SearchScope.chips.forEachIndexed { index, chip ->
                SegmentedButton(
                    checked = ui.scope == chip,
                    onCheckedChange = { onToggleScope(chip) },
                    shape = SegmentedButtonDefaults.itemShape(index, SearchScope.chips.size),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = BrandTokens.accentPurple.copy(alpha = 0.45f),
                        activeContentColor = BrandTokens.textPrimary,
                        inactiveContainerColor = Color.Transparent,
                        inactiveContentColor = BrandTokens.textSecondary,
                        activeBorderColor = BrandTokens.glassBorder,
                        inactiveBorderColor = BrandTokens.glassBorder,
                    ),
                    label = { Text(chip.title, maxLines = 1) },
                    modifier = Modifier.weight(1f).testTag(GlobalSearchTags.scope(chip)),
                )
            }
        }
        val announcement = ui.announcement
        if (announcement != null && !ui.isBandsScope && !ui.isShortQuery) {
            Text(
                announcement,
                style = MaterialTheme.typography.labelMedium,
                color = BrandTokens.textMuted,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .testTag(GlobalSearchTags.STATUS)
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
        when {
            ui.isBandsScope -> BandsUnavailable(onBandRankings)
            ui.hint != null -> CenteredMessage(ui.hint!!, retry = if (ui.canRetryAll) onRetry else null)
            ui.isBusy && !ui.showSongsSection && !ui.showPlayersSection -> Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(32.dp).testTag(GlobalSearchTags.LOADING).semantics { contentDescription = "Searching" })
            }
            else -> Results(ui, artworkUrl, onRetry, onOpen)
        }
    }
}

@Composable
private fun Results(ui: GlobalSearchUiState, artworkUrl: (String?) -> String?, onRetry: () -> Unit, onOpen: (SearchDestination) -> Unit) {
    // Web SearchModal restaggers once per content signature: hide for a frame when the result
    // set changes, then fade rows in (web fadeInUp, 125 ms stagger).
    val signature = remember(ui.songs, ui.players) { ui.songs.map { it.songId } to ui.players.map { it.accountId } }
    var settled by remember { mutableStateOf<Any?>(null) }
    LaunchedEffect(signature) { settled = signature }
    val revealed = rememberRevealed(settled == signature)
    val playersOffset = if (ui.showSongsSection) ui.songs.size + 1 else 0
    LazyColumn(Modifier.fillMaxWidth().testTag("fst.global-search.results")) {
        if (ui.showSongsSection) {
            item(key = "h-songs") {
                Box(Modifier.festivalFadeIn(revealed)) { SectionTitle("Songs", GlobalSearchTags.section(SearchScope.Songs)) }
            }
            if (ui.songsPhase == SectionPhase.Failed) {
                item(key = "songs-failed") { InlineMessage(GlobalSearchResults.SONGS_FAILED) }
            }
            itemsIndexed(ui.songs, key = { _, song -> "s-${song.songId}" }) { index, song ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1))) {
                    SongResultRow(song, artworkUrl(song.albumArt)) { onOpen(song.destination) }
                }
            }
        }
        if (ui.showPlayersSection) {
            item(key = "h-players") {
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(playersOffset))) { SectionTitle("Players", GlobalSearchTags.section(SearchScope.Players)) }
            }
            when (ui.playersPhase) {
                SectionPhase.Loading -> item(key = "players-loading") {
                    LinearProgressIndicator(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp)
                            .testTag(GlobalSearchTags.PLAYERS_LOADING)
                            .semantics { contentDescription = "Searching players"; liveRegion = LiveRegionMode.Polite },
                    )
                }
                SectionPhase.Failed -> item(key = "players-failed") {
                    ServiceStatusInline(
                        issue = ui.playersIssue ?: return@item,
                        fallbackTitle = GlobalSearchResults.PLAYERS_UNAVAILABLE,
                        countdown = ui.playersCountdown,
                        onRetry = onRetry,
                        modifier = Modifier.padding(horizontal = 16.dp).testTag("fst.global-search.players-error"),
                    )
                }
                SectionPhase.Empty -> item(key = "players-empty") {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                        Text(GlobalSearchResults.NO_PLAYERS, color = BrandTokens.textSecondary, modifier = Modifier.weight(1f).testTag(GlobalSearchTags.HINT))
                        TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).testTag(GlobalSearchTags.RETRY)) { Text("Retry") }
                    }
                }
                else -> Unit
            }
            itemsIndexed(ui.players, key = { _, player -> "p-${player.accountId}" }) { index, player ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(playersOffset + index + 1))) {
                    PlayerResultRow(player) { onOpen(player.destination) }
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, tag: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier
            .fillMaxWidth()
            .background(BrandTokens.cardBackground)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .testTag(tag)
            .semantics { heading() },
    )
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
private fun CenteredMessage(text: String, retry: (() -> Unit)?) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 32.dp),
    ) {
        Text(text, color = BrandTokens.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.testTag(GlobalSearchTags.HINT))
        if (retry != null) {
            FilledTonalButton(onClick = retry, modifier = Modifier.heightIn(min = 48.dp).testTag(GlobalSearchTags.RETRY)) { Text("Retry") }
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
