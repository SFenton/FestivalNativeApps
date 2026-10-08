package com.festivalscoretracker.android.ui.songs

import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.DragInteraction
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.songs.InvalidScoreWarning
import com.festivalscoretracker.android.core.songs.SongFilterDraft
import com.festivalscoretracker.android.core.songs.SongListHeader
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSectionIndex
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongsUiState
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.coveredByModal
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.festivalEmptyStateItem
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksController
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.settings.rememberHingeSplit
import com.festivalscoretracker.android.ui.shell.RegisterPageFind
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.roundToInt
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog

// region Songs screen

/**
 * The Songs catalogue: search, draft Sort/Filter sheets, pause notices,
 * sort-bucket headers with Quick Links (sheet on compact / menu elsewhere; hinge split per
 * form factor), a right-edge section index for Title/Artist and glass rows
 * with Shop pulses and selected-player chips or metadata.
 *
 * @param viewModel Songs logic.
 * @param artworkUrl Artwork resolver.
 * @param onApplySort Persist a sort draft (mode, direction, metadata priority).
 * @param onApplyFilter Persist a filter draft.
 * @param onClearFilters Clear every filter (also repairs a corrupt saved filter).
 * @param onSongClick Open a song (push on phones, select on two-pane layouts).
 * @param selectedSongId Highlighted song in two-pane layouts.
 * @param visibleInstruments Settings-visible charts (Filter choices).
 * @param onOpenSettings Open Settings (invalid-score alert action).
 * @param modifier Modifier.
 */
@Composable
fun SongsScreen(
    viewModel: SongsViewModel,
    artworkUrl: (String?) -> String?,
    onApplySort: (SongSortDraft) -> Unit,
    onApplyFilter: (SongFilterDraft) -> Unit,
    onClearFilters: () -> Unit,
    onSongClick: (Song) -> Unit,
    selectedSongId: String? = null,
    visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    onOpenSettings: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val search by viewModel.searchInput.collectAsStateWithLifecycle()
    var showSort by rememberSaveable { mutableStateOf(false) }
    var showFilter by rememberSaveable { mutableStateOf(false) }
    var warning by remember { mutableStateOf<InvalidScoreWarning?>(null) }
    val listState = rememberLazyListState()
    val listed = state.catalog is LoadState.Loaded && !state.invalidSavedFilter
    val leading = state.notices.size
    val linkSections = remember(state.headers, listed) { if (listed) state.headers.map { it.quickLink } else emptyList() }
    // Headers are their own (sticky) items, so a header's list index counts the headers before it.
    // They pin under the top bar, so jumps land them flush rather than 32 dp down (#51).
    // The page's fade window, here so Quick Links jumps rush it (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    val quickLinks = rememberQuickLinks(listState, state.quickLinksTitle, linkSections, pinnedHeaders = true, fadeInWindow = fadeIn) { id ->
        state.headers.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.let { ordinal -> leading + state.headers[ordinal].firstIndex + ordinal }
    }
    val density = LocalDensity.current
    val windowWidthDp = with(density) { currentWindowSize().width.toDp().value.toInt() }
    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    val split = rememberHingeSplit()
    BoxWithConstraints(modifier.fillMaxSize().then(split.modifier)) {
        val hinge = split.value?.takeIf { quickLinks.available }
        FestivalScreen(
            title = "Songs",
            isRoot = true,
            fadeInWindow = fadeIn,
            scrolled = scrolled,
            // Sort, Filter and Quick Links stay reachable while the list scrolls (issue #52).
            pinActions = true,
            // TalkBack swipes reach Quick Links, Sort and Filter before the ~700 rows,
            // not after them (issue #160, as Suggestions #112).
            actionsReadFirst = true,
            actions = {
                SongsPageTools(state, quickLinks, windowWidthDp, onSort = { showSort = true }, onFilter = { showFilter = true })
            },
        ) { padding ->
            Row(Modifier.fillMaxSize()) {
                val listModifier = if (hinge != null) Modifier.width(with(density) { hinge.first.toDp() }) else Modifier.weight(1f)
                Box(listModifier.fillMaxHeight()) {
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
                                    SongList(
                                        state, listState, search, viewModel::onSearchChange, artworkUrl, onSongClick, selectedSongId, padding,
                                    ) { warning = it }
                                }
                            }
                        }
                    }
                }
                // Book posture: the list stays on the leading side of the hinge (hinge-safe).
                if (hinge != null) Spacer(Modifier.width(with(density) { hinge.second.toDp() }))
            }
        }
    }
    if (showSort) {
        SortSheet(state, onApply = onApplySort, onDismiss = { showSort = false })
    }
    if (showFilter) {
        val prefs = state.prefs
        FilterSheet(
            initial = SongFilterDraft.from(prefs.filter, prefs.general, prefs.playerFilter, visibleInstruments),
            hasPlayer = state.hasPlayer,
            hideShop = state.hideShop,
            filterInvalidScores = state.filterInvalidScores,
            availableSeasons = state.availableSeasons,
            decades = state.availableDecades,
            durations = state.durationBuckets,
            onApply = onApplyFilter,
            onDismiss = { showFilter = false },
        )
    }
    warning?.let { shown ->
        InvalidScoreAlert(shown, onDismiss = { warning = null }, onOpenSettings = { warning = null; onOpenSettings() })
    }
}

/**
 * Quick Links, Sort and Filter (always; General filters only without a player): the page's own tools, in the floating
 * toolbar on phones and the top app bar elsewhere. Sort and Filter speak their state, not only their gold tint.
 *
 * @param state Songs state (gold tints for a changed sort / active filters).
 * @param quickLinks Sort-bucket Quick Links.
 * @param windowWidthDp Window width (sheet vs menu).
 * @param onSort Open the Sort sheet.
 * @param onFilter Open the Filter sheet.
 */
@Composable
private fun SongsPageTools(state: SongsUiState, quickLinks: QuickLinksController, windowWidthDp: Int, onSort: () -> Unit, onFilter: () -> Unit) {
    QuickLinksAction(quickLinks, windowWidthDp)
    val sortState = SongSortDraft.describe(state.sort, state.ascending)
    IconButton(onClick = onSort, modifier = Modifier.testTag("fst.songs.sort.open").semantics { stateDescription = sortState }) {
        Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort songs", tint = if (state.sortChanged) BrandTokens.gold else BrandTokens.textPrimary)
    }
    // The spoken state carries what the gold tint shows (issue #181; Item Shop precedent #145).
    val filterState = state.filterStateDescription
    IconButton(onClick = onFilter, modifier = Modifier.testTag("fst.songs.filter.open").semantics { stateDescription = filterState }) {
        Icon(
            Icons.Filled.FilterList,
            contentDescription = "Filter songs",
            tint = if (state.filterActive) BrandTokens.gold else BrandTokens.textPrimary,
        )
    }
}

/**
 * The "Filtered Score" alert behind a row's invalid-score icon (web
 * `InvalidScoreIcon` confirm: OK / Settings).
 *
 * @param warning Row warning.
 * @param onDismiss OK.
 * @param onOpenSettings Settings.
 */
@Composable
fun InvalidScoreAlert(warning: InvalidScoreWarning, onDismiss: () -> Unit, onOpenSettings: () -> Unit) {
    FestivalAlertDialog(
        title = warning.title,
        text = warning.message,
        tag = "fst.songs.invalid-score.alert",
        textTag = "fst.songs.invalid-score.message",
        confirmLabel = "Settings",
        confirmTag = "fst.songs.invalid-score.settings",
        onConfirm = onOpenSettings,
        dismissLabel = "OK",
        dismissTag = "fst.songs.invalid-score.ok",
        onDismissRequest = onDismiss,
    )
}

/**
 * Bounded first-paint gate: the first reveal waits (≤ 900 ms) for the first rows'
 * artwork to decode, then fades in like the web's `fadeInUp` (instant under reduced
 * motion). Later updates
 * never re-block.
 *
 * @param state Songs state.
 * @param artworkUrl Artwork resolver.
 * @param content List.
 */
@Composable
private fun FirstPaintGate(state: SongsUiState, artworkUrl: (String?) -> String?, content: @Composable () -> Unit) {
    val context = LocalContext.current
    var revealed by rememberSaveable { mutableStateOf(false) }
    // Rows are derived in the same state as the loaded catalogue, so Loaded means ready — including
    // a filter that matches nothing (its empty state must still be revealed).
    val hasRows = state.catalog is LoadState.Loaded
    LaunchedEffect(hasRows) {
        if (revealed || !hasRows) return@LaunchedEffect
        val loader = SingletonImageLoader.get(context)
        val urls = state.rows.take(FIRST_PAINT_ROWS).mapNotNull { artworkUrl(it.song.albumArt) }
        withTimeoutOrNull(FIRST_PAINT_BUDGET_MS) {
            urls.map { url -> async { loader.execute(ImageRequest.Builder(context).data(url).build()) } }.awaitAll()
        }
        revealed = true
    }
    Box(Modifier.fillMaxSize().festivalFadeIn(revealed).testTag(if (revealed) "fst.songs.revealed" else "fst.songs.priming")) { content() }
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
        Button(onClick = onReset, colors = festivalFilledButtonColors(), modifier = Modifier.testTag("fst.songs.filter-reset-invalid")) { Text("Reset Filters") }
    }
}

@Composable
private fun SongList(
    state: SongsUiState,
    listState: LazyListState,
    search: String,
    onSearchChange: (String) -> Unit,
    artworkUrl: (String?) -> String?,
    onSongClick: (Song) -> Unit,
    selectedSongId: String?,
    padding: PaddingValues,
    onWarning: (InvalidScoreWarning) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val leading = state.notices.size
    val showIndex = state.sections.size > 1
    val pulse = rememberShopPulse(active = state.rows.any { it.pulse != null || it.warning != null })
    val breathe = rememberShopBreathe(active = state.rows.any { it.pulse != null })
    // Scroll back to the top only when the sort or filters reshape the list (not on returning to it).
    val shape = "${state.effectiveSort}:${state.ascending}:${state.prefs.hashCode()}"
    var lastShape by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(shape) {
        if (lastShape != null && lastShape != shape) listState.scrollToItem(0)
        lastShape = shape
    }
    // Ctrl+F focuses the Songs filter pinned above the list (always on screen).
    val findFocus = remember { FocusRequester() }
    RegisterPageFind {
        scope.launch {
            withFrameNanos { }
            runCatching { findFocus.requestFocus() }
        }
    }
    val endPadding = if (showIndex) 28.dp else 16.dp
    val density = LocalDensity.current
    // Rows fade out below the pinned bucket header, or meet it at a hard edge under the contrast,
    // transparency and motion settings (rememberScrollEdgeHardEdge). Bucket headers record their
    // drawing into the edge's layers; the list redraws them over the cut and band (issues #91, #288).
    val firstHeaderKey = state.headers.firstOrNull()?.let { headerKey(it) }
    val headerEdge = rememberPinnedHeaderEdge(listState, firstHeaderKey, LIST_SPACING, IS_HEADER_KEY)
    val headerStart = with(density) { 16.dp.toPx() }
    // The list filter is pinned above the scrolling list on every window size (issue #52; phones
    // too since issue #309, like the web toolbar and Apple's Filter Songs field): it never scrolls
    // away, so nothing moves or animates between the top and scrolled states. Global search stays
    // in the top app bar and Sort/Filter/Quick Links in the page tools.
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.padding(start = 16.dp, end = endPadding, top = padding.calculateTopPadding())) {
            SearchField(search, onSearchChange, findFocus)
        }
        Box(Modifier.fillMaxWidth().weight(1f)) {
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(
                    start = 16.dp,
                    end = endPadding,
                    bottom = padding.calculateBottomPadding() + 16.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(LIST_SPACING),
                modifier = Modifier.fillMaxSize()
                    .pinnedHeaderEdgeFade(headerEdge, headerStart)
                    .testTag("fst.songs.list"),
            ) {
                state.notices.forEachIndexed { index, notice ->
                    item(key = "notice-$index", contentType = "notice") { Notice(notice, if (notice == state.sortPaused) "fst.songs.sort-paused" else "fst.songs.notice.$index") }
                }
                // Web full-page EmptyState, vertically centred in the viewport (6.33).
                if (state.rows.isEmpty()) festivalEmptyStateItem(state.emptyMessage, subtitle = "Try adjusting your search or filters.", tag = "fst.songs.empty", state = listState)
                val songRow: @Composable (SongRowModel) -> Unit = { row ->
                    SongRow(
                        row, artworkUrl(row.song.albumArt), selected = row.song.songId == selectedSongId, pulse = pulse, breathe = breathe,
                        onWarning = row.warning?.let { shown -> { onWarning(shown) } },
                    ) { onSongClick(row.song) }
                }
                if (state.headers.isEmpty()) {
                    items(state.rows, key = { it.song.songId }, contentType = { "song" }) { songRow(it) }
                } else {
                    // Bucket headers stick under the pinned search field with no backing (issue #91, like the
                    // Title/Artist list and iOS): rows passing beneath are hidden behind them and fade out
                    // just below them (pinnedHeaderEdgeFade, issue #49).
                    val first = state.headers.first().firstIndex
                    if (first > 0) items(state.rows.subList(0, first), key = { it.song.songId }, contentType = { "song" }) { songRow(it) }
                    state.headers.forEachIndexed { ordinal, header ->
                        val end = state.headers.getOrNull(ordinal + 1)?.firstIndex ?: state.rows.size
                        stickyHeader(key = headerKey(header), contentType = "header") { BucketHeader(header, headerEdge.layers) }
                        items(state.rows.subList(header.firstIndex, end), key = { it.song.songId }, contentType = { "song" }) { songRow(it) }
                    }
                }
            }
            // Fully qualified: the ColumnScope overload would otherwise capture this call.
            // Reduce Motion (in-app or Remove animations) shows and hides the rail at once.
            val stillRail = LocalFestivalAccessibility.current.reduceMotion
            androidx.compose.animation.AnimatedVisibility(
                visible = showIndex,
                enter = if (stillRail) EnterTransition.None else fadeIn() + slideInHorizontally { it },
                exit = if (stillRail) ExitTransition.None else fadeOut() + slideOutHorizontally { it },
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(top = 8.dp, bottom = padding.calculateBottomPadding() + 8.dp)
                    .fillMaxHeight(),
            ) {
                val position = rememberSectionPosition(listState, state.sections, leading)
                SectionIndexScrubber(
                    sections = state.sections,
                    current = position.current,
                    onJump = { section -> scope.launch { position.jumpTo(section) } },
                )
            }
        }
    }
}

/**
 * One shared Shop outline pulse for every visible row (web `shopPulse`: 0 -> 0.7 -> 0
 * opacity over 2 s, ease-in-out). Rows read it in the draw phase only, so the pulse
 * never recomposes them; with nothing pulsing no animation runs. Reduced motion
 * (the app setting or Android's Remove animations) holds it at 0.7, like the web.
 *
 * @param active Whether any row pulses.
 * @return Outline alpha provider.
 */
@Composable
internal fun rememberShopPulse(active: Boolean): () -> Float {
    val still = LocalFestivalAccessibility.current.reduceMotion
    // Behind a newer modal the outline holds its reduced-motion frame (`modal-shell` R10, issue #186).
    if (!active || still || coveredByModal()) return STILL_PULSE
    val transition = rememberInfiniteTransition(label = "shopPulse")
    val alpha = transition.animateFloat(
        initialValue = 0f,
        targetValue = SHOP_PULSE_PEAK,
        animationSpec = infiniteRepeatable(tween(SHOP_PULSE_HALF_MS, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "shopPulseAlpha",
    )
    return remember(alpha) { { alpha.value } }
}

/** Web pulse peak opacity (also the reduced-motion outline). */
internal const val SHOP_PULSE_PEAK = 0.7f

/** Half of the web's 2 s pulse. */
private const val SHOP_PULSE_HALF_MS = 1_000

private val STILL_PULSE: () -> Float = { SHOP_PULSE_PEAK }

/**
 * One shared Shop "breathe" for filled Shop indicators (web `shopBreathe*`: the
 * fill eases between the dark surface and the status color over 3 s). Read in the
 * draw phase only; reduced motion holds the status color (fraction 1), like the web.
 *
 * @param active Whether anything breathes.
 * @return Fraction provider (0 = surface, 1 = status color).
 */
@Composable
internal fun rememberShopBreathe(active: Boolean): () -> Float {
    val still = LocalFestivalAccessibility.current.reduceMotion
    if (!active || still || coveredByModal()) return STILL_BREATHE
    val fraction = rememberInfiniteTransition(label = "shopBreathe").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(SHOP_BREATHE_HALF_MS, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "shopBreatheFraction",
    )
    return remember(fraction) { { fraction.value } }
}

/** Half of the web's 3 s breathe. */
private const val SHOP_BREATHE_HALF_MS = 1_500

private val STILL_BREATHE: () -> Float = { 1f }

/**
 * The section-index position: the section containing the first visible row, except that a
 * section the list could not bring to the top (one of the last, with the list at its end)
 * stays current after a jump. Without that, TalkBack's Next section would stop at the
 * section at the top of the last screen and never reach the final sections.
 *
 * @property listState List state.
 * @property sections Sections.
 * @property leading Non-row items before the first row.
 */
@Stable
private class SectionPosition(private val listState: LazyListState, private val sections: List<SongSection>, private val leading: Int) {
    /** Last jump target, until the list scrolls back from its end or the user drags it. */
    private var jumped by mutableStateOf<SongSection?>(null)

    /** Current section, or null. */
    val current: SongSection? by derivedStateOf {
        val top = sections.lastOrNull { it.firstIndex <= (listState.firstVisibleItemIndex - leading).coerceAtLeast(0) }
        val target = jumped
        if (target != null && !listState.canScrollForward && target.firstIndex > (top?.firstIndex ?: -1)) target else top
    }

    /**
     * Scrolls [section]'s first row to the top, or as near as the list's end allows.
     *
     * @param section Section to show.
     */
    suspend fun jumpTo(section: SongSection) {
        jumped = section
        listState.scrollToItem(section.firstIndex + leading)
    }

    /** Forgets the jump target once the list leaves its end or the user drags it. */
    suspend fun forgetJumpsOnMove() = coroutineScope {
        launch { snapshotFlow { listState.canScrollForward }.collect { if (it) jumped = null } }
        listState.interactionSource.interactions.collect { if (it is DragInteraction.Start) jumped = null }
    }
}

/**
 * Remembers the [SectionPosition] for [sections].
 *
 * @param listState List state.
 * @param sections Sections.
 * @param leading Non-row items before the first row.
 * @return Section position.
 */
@Composable
private fun rememberSectionPosition(listState: LazyListState, sections: List<SongSection>, leading: Int): SectionPosition {
    val position = remember(listState, sections, leading) { SectionPosition(listState, sections, leading) }
    LaunchedEffect(position) { position.forgetJumpsOnMove() }
    return position
}

/**
 * One bucket header: transparent like the rest of the list (issue #91). It records its own
 * drawing into a [GraphicsLayer] registered under its key in [layers], so the list can redraw it
 * above the cut that hides rows scrolling under it ([rememberPinnedHeaderRecorder], [pinnedHeaderEdgeFade]).
 *
 * @param header Header.
 * @param layers Recorded header drawings by list key.
 */
@Composable
private fun BucketHeader(header: SongListHeader, layers: MutableMap<Any, GraphicsLayer>) {
    SectionHeader(
        header.label,
        rememberPinnedHeaderRecorder(headerKey(header), layers)
            .padding(horizontal = 4.dp)
            .testTag(header.testTag)
            .semantics { contentDescription = header.spoken },
    )
}

/** Gap between Songs list items. */
private val LIST_SPACING = 4.dp

private const val HEADER_KEY_PREFIX = "header:"

private fun headerKey(header: SongListHeader): String = HEADER_KEY_PREFIX + header.id

private val IS_HEADER_KEY: (Any) -> Boolean = { key -> key is String && key.startsWith(HEADER_KEY_PREFIX) }

@Composable
private fun Notice(text: String, tag: String) {
    GlassCard(Modifier.fillMaxWidth().padding(bottom = 4.dp).testTag(tag)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(12.dp)) {
            Icon(Icons.Filled.Info, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(20.dp))
            Text(text, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp))
        }
    }
}

/** Songs filter placeholder (web `songs.searchPlaceholder`). */
internal const val SONGS_SEARCH_PLACEHOLDER = "Search songs or artists"

@Composable
private fun SearchField(value: String, onChange: (String) -> Unit, focus: FocusRequester) {
    val focusManager = LocalFocusManager.current
    TextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        // The keyboard's Search key only dismisses the keyboard: the list already filters as you type.
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
        // One line: a wrapped placeholder doubled the pinned field's
        // height in a medium-width list pane (issue #101).
        placeholder = { Text(SONGS_SEARCH_PLACEHOLDER, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).focusRequester(focus).testTag("fst.songs.search"),
    )
}

// endregion

// region Section index

/**
 * Contacts-style right-edge index: tap or drag to jump. Labels are sampled when
 * there are more sections than fit, each centred in an equal slot: a touch on a
 * drawn label opens that label's section, while positions between labels still
 * reach the skipped sections ([SongSectionIndex.sectionAt]). While a finger is down,
 * a value indicator beside the touch names the section it opens (like Material's
 * slider value label), so skipped sections are visible too. One accessibility
 * element whose state names the current section, with next/previous actions
 * (only where a section exists) equivalent to dragging one section.
 *
 * @param sections Sections in list order.
 * @param current Section at the top of the list.
 * @param onJump Scroll to a section.
 * @param modifier Modifier.
 */
@Composable
fun SectionIndexScrubber(sections: List<SongSection>, current: SongSection?, onJump: (SongSection) -> Unit, modifier: Modifier = Modifier) {
    var active by remember { mutableStateOf<SongSection?>(null) }
    var touchY by remember { mutableFloatStateOf(0f) }
    val accessibility = LocalFestivalAccessibility.current
    val opaque = accessibility.increaseContrast || accessibility.reduceTransparency
    val position = current?.id ?: 0
    val idle = MaterialTheme.colorScheme.onSurfaceVariant
    val highlight = MaterialTheme.colorScheme.tertiary
    BoxWithConstraints(modifier.width(24.dp)) {
        // Each label is one 14 sp line plus breathing room; in sp so larger text samples more.
        val density = LocalDensity.current
        val labelStep = with(density) { SECTION_LABEL_STEP.toDp() }
        val maxLabels = (maxHeight / labelStep).toInt().coerceAtLeast(2)
        val stride = SongSectionIndex.stride(sections.size, maxLabels)
        val drawn = sections.filterIndexed { index, _ -> index % stride == 0 }
        val heightPx = constraints.maxHeight.toFloat()
        // A touch within a drawn label's line opens exactly that label (issue #48).
        val labelHalf = with(density) { SECTION_LABEL_LINE.toPx() } / 2f / (heightPx / drawn.size.coerceAtLeast(1))
        fun jumpTo(y: Float) {
            touchY = y.coerceIn(0f, heightPx)
            val index = SongSectionIndex.sectionAt(y / heightPx, sections.size, stride, labelHalf)
            val section = sections.getOrNull(index) ?: return
            if (section == active) return
            active = section
            onJump(section)
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .testTag("fst.songs.section-index")
                .clearAndSetSemantics {
                    contentDescription = "Section index"
                    stateDescription = SongSectionIndex.spokenLabel(current?.label ?: sections.firstOrNull()?.label.orEmpty())
                    customActions = listOfNotNull(
                        sections.getOrNull(position + 1)?.let { next -> CustomAccessibilityAction("Next section") { onJump(next); true } },
                        sections.getOrNull(position - 1)?.let { previous -> CustomAccessibilityAction("Previous section") { onJump(previous); true } },
                    )
                }
                .background(
                    when {
                        active == null -> Color.Transparent
                        opaque -> BrandTokens.cardBackground
                        else -> BrandTokens.surfaceFrosted
                    },
                    CircleShape,
                )
                // One gesture for press and drag: the touch tracks from the first down (no slop),
                // and the indicator stays up until that finger lifts or the gesture is cancelled.
                .pointerInput(sections, stride, heightPx) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        try {
                            jumpTo(down.position.y)
                            while (true) {
                                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                if (change.positionChanged()) {
                                    change.consume()
                                    jumpTo(change.position.y)
                                }
                            }
                        } finally {
                            active = null
                        }
                    }
                },
        ) {
            // Equal slots put label k's centre at (k + ½) / labels of the height, where sectionAt expects it.
            drawn.forEach { section ->
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text(
                        section.label.take(4),
                        fontSize = if (section.label.length > 2) 8.sp else 11.sp,
                        lineHeight = SECTION_LABEL_LINE,
                        fontWeight = FontWeight.Bold,
                        color = if (section == active) highlight else idle,
                    )
                }
            }
        }
        active?.let { section -> SectionIndexIndicator(section.label, touchY, heightPx, opaque) }
    }
}

/**
 * The scrubbing value indicator: an opaque pill left of the rail at the touch height
 * naming the section the touch opens. Decorative for TalkBack (the rail's state already
 * names it); it grows with the font scale and stays within the rail's height.
 *
 * @param label Section label.
 * @param touchY Touch height in rail pixels.
 * @param railHeight Rail height in pixels.
 * @param opaqueBorder Increased contrast or reduced transparency: 2 dp white border.
 */
@Composable
private fun SectionIndexIndicator(label: String, touchY: Float, railHeight: Float, opaqueBorder: Boolean) {
    val gap = with(LocalDensity.current) { SECTION_INDICATOR_GAP.roundToPx() }
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .testTag("fst.songs.section-index.indicator")
            .clearAndSetSemantics {}
            .layout { measurable, _ ->
                val placeable = measurable.measure(Constraints())
                layout(0, 0) {
                    val top = (touchY - placeable.height / 2f).roundToInt().coerceIn(0, (railHeight.roundToInt() - placeable.height).coerceAtLeast(0))
                    placeable.place(-placeable.width - gap, top)
                }
            }
            .sizeIn(minWidth = SECTION_INDICATOR_SIZE, minHeight = SECTION_INDICATOR_SIZE)
            .background(MaterialTheme.colorScheme.surface, CircleShape)
            .border(
                if (opaqueBorder) 2.dp else 1.dp,
                if (opaqueBorder) BrandTokens.textPrimary else BrandTokens.glassBorder,
                CircleShape,
            )
            .padding(horizontal = 12.dp, vertical = 4.dp),
    ) {
        Text(label, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.tertiary)
    }
}

/** Vertical space budgeted per section-index label (a 14 sp line plus spacing). */
private val SECTION_LABEL_STEP = 20.sp

/** Smallest value indicator: a 56 dp circle for one letter at the default font scale. */
private val SECTION_INDICATOR_SIZE = 56.dp

/** Space between the value indicator and the rail. */
private val SECTION_INDICATOR_GAP = 8.dp

/** One section-index label's line height. */
private val SECTION_LABEL_LINE = 14.sp

// endregion
