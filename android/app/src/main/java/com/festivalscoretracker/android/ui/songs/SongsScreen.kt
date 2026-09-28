package com.festivalscoretracker.android.ui.songs

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.songs.SongFilterDraft
import com.festivalscoretracker.android.core.songs.SongListHeader
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongsUiState
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// region Songs screen

/**
 * The Songs catalogue: search, draft Sort/Filter sheets, pause notices,
 * Shop-bucket headers, a right-edge section index and glass rows with Shop
 * accents and selected-player chips or metadata.
 *
 * @param viewModel Songs logic.
 * @param artworkUrl Artwork resolver.
 * @param onApplySort Persist a sort.
 * @param onApplyFilter Persist a filter draft.
 * @param onClearFilters Clear every filter (also repairs a corrupt saved filter).
 * @param onSongClick Open a song (push on phones, select on two-pane layouts).
 * @param selectedSongId Highlighted song in two-pane layouts.
 * @param visibleInstruments Settings-visible charts (Filter choices).
 * @param modifier Modifier.
 */
@Composable
fun SongsScreen(
    viewModel: SongsViewModel,
    artworkUrl: (String?) -> String?,
    onApplySort: (SongSortMode, Boolean) -> Unit,
    onApplyFilter: (SongFilterDraft) -> Unit,
    onClearFilters: () -> Unit,
    onSongClick: (Song) -> Unit,
    selectedSongId: String? = null,
    visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    modifier: Modifier = Modifier,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val search by viewModel.searchInput.collectAsStateWithLifecycle()
    var showSort by rememberSaveable { mutableStateOf(false) }
    var showFilter by rememberSaveable { mutableStateOf(false) }
    FestivalScreen(
        title = "Songs",
        isRoot = true,
        modifier = modifier,
        actions = {
            IconButton(onClick = { showSort = true }, modifier = Modifier.testTag("fst.songs.sort.open")) {
                Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort songs", tint = if (state.sortChanged) BrandTokens.gold else BrandTokens.textPrimary)
            }
            if (state.hasPlayer) {
                IconButton(onClick = { showFilter = true }, modifier = Modifier.testTag("fst.songs.filter.open")) {
                    Icon(
                        Icons.Filled.FilterList,
                        contentDescription = "Filter songs",
                        tint = if (state.prefs.anyFilterActive) BrandTokens.gold else BrandTokens.textPrimary,
                    )
                }
            }
        },
    ) { padding ->
        when (val catalog = state.catalog) {
            LoadState.Loading -> LoadingView("Loading songs", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(catalog.issue, "Songs unavailable", catalog.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> PullToRefreshBox(
                isRefreshing = catalog.refreshing,
                onRefresh = viewModel::refresh,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (state.invalidSavedFilter) {
                    InvalidFilterView(onClearFilters, padding)
                } else {
                    FirstPaintGate(state, artworkUrl) {
                        SongList(state, search, viewModel::onSearchChange, artworkUrl, onSongClick, selectedSongId, padding)
                    }
                }
            }
        }
    }
    if (showSort) {
        SortSheet(state.sort, state.ascending, state.hideShop, onApply = onApplySort, onDismiss = { showSort = false })
    }
    if (showFilter) {
        val prefs = state.prefs
        FilterSheet(
            initial = SongFilterDraft.from(prefs.filter, prefs.shopFilter, prefs.playerFilter, visibleInstruments),
            hasPlayer = state.hasPlayer,
            hideShop = state.hideShop,
            onApply = onApplyFilter,
            onDismiss = { showFilter = false },
        )
    }
}

/**
 * Bounded first-paint gate: the first reveal waits (≤ 900 ms) for the first rows'
 * artwork to decode, then fades in (instant under reduced motion). Later updates
 * never re-block.
 *
 * @param state Songs state.
 * @param artworkUrl Artwork resolver.
 * @param content List.
 */
@Composable
private fun FirstPaintGate(state: SongsUiState, artworkUrl: (String?) -> String?, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val still = LocalFestivalAccessibility.current.reduceMotion
    var revealed by rememberSaveable { mutableStateOf(false) }
    val hasRows = state.rows.isNotEmpty() || state.totalSongs == 0 || state.catalog !is LoadState.Loaded
    LaunchedEffect(hasRows) {
        if (revealed || !hasRows) return@LaunchedEffect
        val loader = SingletonImageLoader.get(context)
        val urls = state.rows.take(FIRST_PAINT_ROWS).mapNotNull { artworkUrl(it.song.albumArt) }
        withTimeoutOrNull(FIRST_PAINT_BUDGET_MS) {
            urls.map { url -> async { loader.execute(ImageRequest.Builder(context).data(url).build()) } }.awaitAll()
        }
        revealed = true
    }
    val alpha by animateFloatAsState(if (revealed) 1f else 0f, animationSpec = tween(if (still) 0 else 250), label = "firstPaint")
    Box(Modifier.fillMaxSize().alpha(alpha).testTag(if (revealed) "fst.songs.revealed" else "fst.songs.priming")) { content() }
}

/** Rows whose artwork the first reveal waits for. */
private const val FIRST_PAINT_ROWS = 12

/** Upper bound on the first-paint wait. */
private const val FIRST_PAINT_BUDGET_MS = 900L

@Composable
private fun InvalidFilterView(onReset: () -> Unit, padding: PaddingValues) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp).testTag("fst.songs.filter-invalid"),
    ) {
        Text("Saved filters can't be read", style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary, textAlign = TextAlign.Center)
        Text(
            "Your saved player score filters are damaged. Reset them to show songs again.",
            color = BrandTokens.textSecondary,
            textAlign = TextAlign.Center,
        )
        Button(onClick = onReset, modifier = Modifier.testTag("fst.songs.filter-reset-invalid")) { Text("Reset Filters") }
    }
}

@Composable
private fun SongList(
    state: SongsUiState,
    search: String,
    onSearchChange: (String) -> Unit,
    artworkUrl: (String?) -> String?,
    onSongClick: (Song) -> Unit,
    selectedSongId: String?,
    padding: PaddingValues,
) {
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val headersByIndex = remember(state.headers) { state.headers.associateBy { it.firstIndex } }
    val leading = 1 + state.notices.size
    val showIndex = state.sections.size > 1
    // Scroll back to the top only when the sort or filters reshape the list (not on returning to it).
    val shape = "${state.effectiveSort}:${state.ascending}:${state.prefs.hashCode()}"
    var lastShape by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(shape) {
        if (lastShape != null && lastShape != shape) listState.scrollToItem(0)
        lastShape = shape
    }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(
                start = 16.dp,
                end = if (showIndex) 28.dp else 16.dp,
                top = padding.calculateTopPadding(),
                bottom = padding.calculateBottomPadding() + 16.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.songs.list"),
        ) {
            item(key = "search", contentType = "search") { SearchField(search, onSearchChange) }
            state.notices.forEachIndexed { index, notice ->
                item(key = "notice-$index", contentType = "notice") { Notice(notice, index) }
            }
            if (state.rows.isEmpty()) {
                item(key = "empty", contentType = "empty") {
                    Text(
                        state.emptyMessage,
                        color = BrandTokens.textPrimary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(32.dp).testTag("fst.songs.empty"),
                    )
                }
            }
            itemsIndexed(state.rows, key = { _, row -> row.song.songId }, contentType = { _, _ -> "song" }) { index, row ->
                Column {
                    headersByIndex[index]?.let { ShopHeader(it) }
                    SongRow(row, artworkUrl(row.song.albumArt), selected = row.song.songId == selectedSongId) { onSongClick(row.song) }
                }
            }
        }
        AnimatedVisibility(
            visible = showIndex,
            enter = fadeIn() + slideInHorizontally { it },
            exit = fadeOut() + slideOutHorizontally { it },
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(top = padding.calculateTopPadding() + 56.dp, bottom = padding.calculateBottomPadding() + 8.dp)
                .fillMaxHeight(),
        ) {
            SectionIndexScrubber(
                sections = state.sections,
                current = currentSection(listState, state.sections, leading),
                onJump = { section -> scope.launch { listState.scrollToItem(section.firstIndex + leading) } },
            )
        }
    }
}

/**
 * Section containing the first visible row.
 *
 * @param listState List state.
 * @param sections Sections.
 * @param leading Non-row items before the first row.
 * @return Current section, or null.
 */
@Composable
private fun currentSection(listState: LazyListState, sections: List<SongSection>, leading: Int): SongSection? {
    val current by remember(sections, leading) {
        derivedStateOf {
            val row = (listState.firstVisibleItemIndex - leading).coerceAtLeast(0)
            sections.lastOrNull { it.firstIndex <= row }
        }
    }
    return current
}

@Composable
private fun ShopHeader(header: SongListHeader) {
    SectionHeader(header.label, Modifier.testTag("fst.songs.shop-section.${header.id.substringAfter("shop-").substringBeforeLast('-')}"))
}

@Composable
private fun Notice(text: String, index: Int) {
    GlassCard(Modifier.fillMaxWidth().padding(bottom = 4.dp).testTag("fst.songs.notice.$index")) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(12.dp)) {
            Icon(Icons.Filled.Info, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(20.dp))
            Text(text, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp))
        }
    }
}

@Composable
private fun SearchField(value: String, onChange: (String) -> Unit) {
    TextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        placeholder = { Text("Search songs or artists") },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onChange("") }) { Icon(Icons.Filled.Clear, contentDescription = "Clear search") }
            }
        },
        shape = RoundedCornerShape(28.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = BrandTokens.surfaceFrosted,
            unfocusedContainerColor = BrandTokens.surfaceFrosted,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = BrandTokens.textPrimary,
            unfocusedTextColor = BrandTokens.textPrimary,
        ),
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).testTag("fst.songs.search"),
    )
}

// endregion

// region Section index

/**
 * Contacts-style right-edge index: tap or drag to jump. Labels are sampled when
 * there are more sections than fit, while drag positions still reach every
 * section. One accessibility element whose state names the current section, with
 * next/previous actions equivalent to dragging one section.
 *
 * @param sections Sections in list order.
 * @param current Section at the top of the list.
 * @param onJump Scroll to a section.
 * @param modifier Modifier.
 */
@Composable
fun SectionIndexScrubber(sections: List<SongSection>, current: SongSection?, onJump: (SongSection) -> Unit, modifier: Modifier = Modifier) {
    var active by remember { mutableStateOf<String?>(null) }
    val position = current?.id ?: 0
    BoxWithConstraints(
        modifier
            .width(24.dp)
            .testTag("fst.songs.section-index")
            .clearAndSetSemantics {
                contentDescription = "Section index"
                stateDescription = current?.label ?: sections.firstOrNull()?.label.orEmpty()
                customActions = listOf(
                    CustomAccessibilityAction("Next section") {
                        sections.getOrNull(position + 1)?.let(onJump) != null
                    },
                    CustomAccessibilityAction("Previous section") {
                        sections.getOrNull(position - 1)?.let(onJump) != null
                    },
                )
            },
    ) {
        val maxLabels = (maxHeight.value / 20f).toInt().coerceAtLeast(2)
        val stride = (sections.size + maxLabels - 1) / maxLabels
        val heightPx = constraints.maxHeight.toFloat()
        fun jumpTo(y: Float) {
            val index = ((y / heightPx) * sections.size).toInt().coerceIn(0, sections.lastIndex)
            val section = sections[index]
            active = section.label
            onJump(section)
        }
        Column(
            verticalArrangement = Arrangement.SpaceEvenly,
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .background(if (active != null) BrandTokens.surfaceFrosted else Color.Transparent, RoundedCornerShape(12.dp))
                .pointerInput(sections) { detectTapGestures(onPress = { jumpTo(it.y); tryAwaitRelease(); active = null }) }
                .pointerInput(sections) {
                    detectVerticalDragGestures(onDragEnd = { active = null }, onDragCancel = { active = null }) { change, _ -> jumpTo(change.position.y) }
                },
        ) {
            sections.filterIndexed { index, _ -> index % stride == 0 }.forEach { section ->
                Text(
                    section.label.take(4),
                    fontSize = if (section.label.length > 2) 8.sp else 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (section.label == active) BrandTokens.gold else BrandTokens.textSecondary,
                )
            }
        }
    }
}

// endregion
