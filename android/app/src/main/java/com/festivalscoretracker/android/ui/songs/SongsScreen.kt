package com.festivalscoretracker.android.ui.songs

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.launch

// region Songs screen

/**
 * The Songs catalogue: search, persisted sort, player-only instrument filter,
 * right-edge section index and glass rows.
 *
 * @param viewModel Songs logic.
 * @param visibleInstruments Settings-visible charts (filter choices).
 * @param artworkUrl Artwork resolver.
 * @param onSortChange Persist a sort.
 * @param onSongClick Open a song (push on phones, select on two-pane layouts).
 * @param selectedSongId Highlighted song in two-pane layouts.
 * @param modifier Modifier.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongsScreen(
    viewModel: SongsViewModel,
    visibleInstruments: Set<Instrument>,
    artworkUrl: (String?) -> String?,
    onSortChange: (SongSortMode, Boolean) -> Unit,
    onSongClick: (Song) -> Unit,
    selectedSongId: String? = null,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val search by viewModel.searchInput.collectAsStateWithLifecycle()
    val shell = LocalShellActions.current
    var showSort by rememberSaveable { mutableStateOf(false) }
    var showFilter by rememberSaveable { mutableStateOf(false) }
    val hasPlayer = shell.selectedPlayer != null
    FestivalScreen(
        title = "Songs",
        isRoot = true,
        modifier = modifier,
        actions = {
            val sortTint = if (state.query.sort != SongSortMode.Title || !state.query.ascending) BrandTokens.gold else BrandTokens.textPrimary
            IconButton(onClick = { showSort = true }, modifier = Modifier.testTag("fst.songs.sort")) {
                Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort songs", tint = sortTint)
            }
            if (hasPlayer) {
                val filterTint = if (state.query.instrument != null) BrandTokens.gold else BrandTokens.textPrimary
                IconButton(onClick = { showFilter = true }, modifier = Modifier.testTag("fst.songs.filter")) {
                    Icon(Icons.Filled.FilterList, contentDescription = "Filter songs", tint = filterTint)
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
                SongList(
                    songs = state.songs,
                    sections = state.sections,
                    search = search,
                    onSearchChange = viewModel::onSearchChange,
                    instrument = state.query.instrument,
                    artworkUrl = artworkUrl,
                    onSongClick = onSongClick,
                    selectedSongId = selectedSongId,
                    padding = padding,
                )
            }
        }
    }
    if (showSort) {
        SortSheet(state.query.sort, state.query.ascending, onChange = onSortChange, onDismiss = { showSort = false })
    }
    if (showFilter) {
        FilterSheet(state.query.instrument, visibleInstruments, onSelect = viewModel::setInstrumentFilter, onDismiss = { showFilter = false })
    }
}

@Composable
private fun SongList(
    songs: List<Song>,
    sections: List<SongSection>,
    search: String,
    onSearchChange: (String) -> Unit,
    instrument: Instrument?,
    artworkUrl: (String?) -> String?,
    onSongClick: (Song) -> Unit,
    selectedSongId: String?,
    padding: PaddingValues,
) {
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(
                start = 16.dp,
                end = if (sections.isEmpty()) 16.dp else 28.dp,
                top = padding.calculateTopPadding(),
                bottom = padding.calculateBottomPadding() + 16.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.songs.list"),
        ) {
            item(key = "search", contentType = "search") {
                SearchField(search, onSearchChange)
            }
            if (songs.isEmpty()) {
                item(key = "empty", contentType = "empty") {
                    Text(
                        if (instrument != null) "No songs match the filters." else "No songs match “${search.trim()}”.",
                        color = BrandTokens.textPrimary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(32.dp).testTag("fst.songs.empty"),
                    )
                }
            }
            items(songs, key = { it.songId }, contentType = { "song" }) { song ->
                SongRow(song, instrument, artworkUrl(song.albumArt), selected = song.songId == selectedSongId) { onSongClick(song) }
            }
        }
        if (sections.size > 1) {
            SectionIndexScrubber(
                sections = sections,
                onJump = { section -> scope.launch { listState.scrollToItem(section.firstIndex + 1) } },
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(top = padding.calculateTopPadding() + 56.dp, bottom = padding.calculateBottomPadding() + 8.dp)
                    .fillMaxHeight(),
            )
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

// region Row

/**
 * One glass song card; the whole card is the tap target (no chevron), with one
 * merged accessibility stop.
 *
 * @param song Catalogue row.
 * @param instrument Active chart filter; shows that chart's meter.
 * @param artUrl Resolved artwork.
 * @param selected Highlighted in two-pane layouts.
 * @param onClick Open the song.
 */
@Composable
fun SongRow(song: Song, instrument: Instrument?, artUrl: String?, selected: Boolean = false, onClick: () -> Unit) {
    GlassCard(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("fst.songs.row.${song.songId}")
            .semantics { this.selected = selected },
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .background(if (selected) BrandTokens.accentPurple.copy(alpha = 0.35f) else Color.Transparent)
                .padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
            )
            Column(Modifier.weight(1f)) {
                Text(song.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
                Text(song.subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
            }
            val level = instrument?.let { song.difficulty?.chartedValue(it) }
            if (level != null) DifficultyMeter(level)
        }
    }
}

// endregion

// region Section index

/**
 * Contacts-style right-edge index: tap or drag to jump. Labels are sampled when
 * there are more sections than fit, while drag positions still reach every section.
 *
 * @param sections Sections in list order.
 * @param onJump Scroll to a section.
 * @param modifier Modifier.
 */
@Composable
fun SectionIndexScrubber(sections: List<SongSection>, onJump: (SongSection) -> Unit, modifier: Modifier = Modifier) {
    var active by remember { mutableStateOf<String?>(null) }
    BoxWithConstraints(modifier.width(24.dp).testTag("fst.songs.section-index")) {
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
                .semantics { contentDescription = "Section index" }
                .pointerInput(sections) { detectTapGestures { jumpTo(it.y) } }
                .pointerInput(sections) {
                    detectVerticalDragGestures(onDragEnd = { active = null }) { change, _ -> jumpTo(change.position.y) }
                },
        ) {
            sections.filterIndexed { index, _ -> index % stride == 0 }.forEach { section ->
                Text(
                    section.label.take(4),
                    fontSize = if (section.label.length > 2) 8.sp else 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (section.label == active) BrandTokens.gold else BrandTokens.textSecondary,
                    modifier = Modifier.clearAndSetSemantics { },
                )
            }
        }
    }
}

// endregion

// region Sheets

/**
 * Sort sheet: field and direction apply immediately and persist.
 *
 * @param mode Current field.
 * @param ascending Current direction.
 * @param onChange Apply a sort.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SortSheet(mode: SongSortMode, ascending: Boolean, onChange: (SongSortMode, Boolean) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = BrandTokens.cardBackground) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).selectableGroup()) {
            SectionHeader("Sort Songs")
            SongSortMode.entries.forEach { option ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .selectable(selected = option == mode, role = Role.RadioButton) { onChange(option, ascending) }
                        .testTag("fst.songs.sort.${option.name.lowercase()}"),
                ) {
                    RadioButton(selected = option == mode, onClick = null)
                    Spacer(Modifier.width(12.dp))
                    Text(option.label, color = BrandTokens.textPrimary)
                }
            }
            SectionHeader("Direction")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(true to "Ascending", false to "Descending").forEachIndexed { index, (value, label) ->
                    SegmentedButton(
                        selected = ascending == value,
                        onClick = { onChange(mode, value) },
                        shape = SegmentedButtonDefaults.itemShape(index, 2),
                    ) { Text(label) }
                }
            }
        }
    }
}

/**
 * Filter sheet (selected player only): one chart or all.
 *
 * @param instrument Current filter.
 * @param visibleInstruments Settings-visible charts.
 * @param onSelect Apply a filter.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterSheet(instrument: Instrument?, visibleInstruments: Set<Instrument>, onSelect: (Instrument?) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = BrandTokens.cardBackground) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).selectableGroup()) {
            SectionHeader("Instrument")
            val options = listOf<Instrument?>(null) + Instrument.entries.filter { it in visibleInstruments }
            options.forEach { option ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .selectable(selected = option == instrument, role = Role.RadioButton) { onSelect(option) },
                ) {
                    RadioButton(selected = option == instrument, onClick = null)
                    Spacer(Modifier.width(12.dp))
                    if (option != null) {
                        InstrumentIcon(option, size = 28.dp, decorative = true)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(option?.label ?: "All Instruments", color = BrandTokens.textPrimary)
                }
            }
        }
    }
}

// endregion
