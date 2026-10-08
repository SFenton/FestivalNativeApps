package com.festivalscoretracker.android.ui.shop

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.text.style.TextOverflow
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ShoppingCart
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.rememberRevealed
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.ui.unit.LayoutDirection
import com.festivalscoretracker.android.core.shop.ShopColumnPolicy
import com.festivalscoretracker.android.core.shop.ShopColumns
import com.festivalscoretracker.android.ui.settings.rememberHingeSplit
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import kotlin.math.roundToInt
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.FoldLane
import com.festivalscoretracker.android.ui.common.ProvideFoldLane
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.ui.songs.SongsTokens
import com.festivalscoretracker.android.ui.songs.SongRowCard
import com.festivalscoretracker.android.ui.songs.pulseOutline
import com.festivalscoretracker.android.ui.songs.rememberShopBreathe
import com.festivalscoretracker.android.ui.songs.rememberShopPulse
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.data.songs.ShopViewMode
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.shop.ShopOfferItem
import com.festivalscoretracker.android.presentation.shop.ShopUiState
import com.festivalscoretracker.android.presentation.shop.ShopViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.launch
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.common.oneLineUnlessLarge

// region Route

/**
 * Item Shop route wiring: shared Shop feed, best-effort catalogue for Details
 * links and the persisted grid/list preference.
 *
 * @param container Process dependencies.
 * @param shellViewModel Shell (effective settings).
 */
@Composable
fun ShopRouteScreen(container: AppContainer, shellViewModel: ShellViewModel) {
    val api = container.api
    val viewModel: ShopViewModel = viewModel {
        ShopViewModel(container.shop.state, { api.catalog(it) }, shellViewModel.settings, container.backoff)
    }
    LaunchedEffect(Unit) { container.shop.ensureStarted() }
    val prefs by container.songsPreferences.state.collectAsStateWithLifecycle(null)
    val scope = rememberCoroutineScope()
    ShopScreen(
        viewModel = viewModel,
        viewMode = prefs?.shopViewMode ?: ShopViewMode.Grid,
        onViewMode = { mode -> scope.launch { container.songsPreferences.setShopViewMode(mode) } },
        artworkUrl = api::artworkUrl,
        onRetry = container.shop::retry,
    )
}

// endregion

// region Screen

/**
 * Item Shop: title-ordered offers with New / Leaving Tomorrow badges, the official
 * Shop link and an in-app Details action for catalogue songs. Compact widths
 * always use the list; wider windows offer a grid/list toggle.
 *
 * @param viewModel Shop logic.
 * @param viewMode Saved layout.
 * @param onViewMode Persist a layout.
 * @param artworkUrl Artwork resolver.
 * @param onRetry Retry the Shop read.
 */
@Composable
fun ShopScreen(
    viewModel: ShopViewModel,
    viewMode: ShopViewMode,
    onViewMode: (ShopViewMode) -> Unit,
    artworkUrl: (String?) -> String?,
    onRetry: () -> Unit,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var showFilter by rememberSaveable { mutableStateOf(false) }
    // Book/passport posture: content splits at a separating vertical hinge (issue #131).
    val split = rememberHingeSplit(keepWhenSingleColumn = true)
    val singleColumn = rememberSingleColumn()
    BoxWithConstraints(Modifier.fillMaxSize().then(split.modifier)) {
        val compact = maxWidth < COMPACT_WIDTH
        val effective = if (compact) ShopViewMode.List else viewMode
        // TalkBack / large text: the list and centred states go full width (as on every page), but the
        // grid keeps its columns, so it still splits at the fold rather than putting cards across it (#113).
        val hinge = split.value.takeUnless { singleColumn }
        val contentHinge = if (effective == ShopViewMode.Grid) split.value else hinge
        FestivalScreen(
            title = "Item Shop",
            isRoot = false,
            actions = {
                if (!state.hidden) {
                    // The gold tint alone would hide the filter state from TalkBack (issue #145).
                    val filterState = state.filter.stateDescription
                    IconButton(
                        onClick = { showFilter = true },
                        modifier = Modifier.testTag("fst.shop.filter.open").semantics { stateDescription = filterState },
                    ) {
                        Icon(
                            Icons.Filled.FilterList,
                            contentDescription = "Filter Item Shop",
                            tint = if (state.filter.isActive) BrandTokens.gold else BrandTokens.textPrimary,
                        )
                    }
                }
                if (!compact && !state.hidden) {
                    val next = if (effective == ShopViewMode.Grid) ShopViewMode.List else ShopViewMode.Grid
                    IconButton(onClick = { onViewMode(next) }, modifier = Modifier.testTag("fst.shop.view-toggle")) {
                        Icon(
                            if (next == ShopViewMode.List) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView,
                            contentDescription = if (next == ShopViewMode.List) "List View" else "Grid View",
                        )
                    }
                }
            },
        ) { padding ->
            val loadedRevealed = rememberRevealed(state.shop is LoadState.Loaded)
            when {
                state.hidden -> StartPane(hinge) { HiddenView(padding) }
                else -> when (val shop = state.shop) {
                    LoadState.Loading -> StartPane(hinge) { LoadingView("Loading Item Shop", Modifier.padding(padding)) }
                    is LoadState.Failed -> StartPane(hinge) {
                        Box(Modifier.testTag("fst.shop.error")) {
                            ServiceStatusView(shop.issue, "Item Shop unavailable", shop.countdown, onRetry, contentPadding = padding)
                        }
                    }
                    // A List ↔ Grid switch recomposes the new layout from the top with the web's
                    // fade/stagger again (web `useViewTransition`, operator 6.10).
                    is LoadState.Loaded -> key(effective) {
                        val switched = rememberViewSwitch(effective)
                        ShopContent(state, effective, artworkUrl, viewModel::retryCatalog, padding, loadedRevealed && switched, contentHinge)
                    }
                }
            }
        }
    }
    if (showFilter && !state.hidden) {
        ShopFilterSheet(state.filter, onChange = viewModel::setFilter, onDismiss = { showFilter = false })
    }
}

/** Widths below this always use the list. */
private val COMPACT_WIDTH = 600.dp

/**
 * False for one frame when [mode] differs from the last shown layout, so a freshly
 * switched layout fades in again; true otherwise (first visit uses the load fade).
 *
 * @param mode Layout now shown.
 * @return Value to AND into the reveal flag.
 */
@Composable
private fun rememberViewSwitch(mode: ShopViewMode): Boolean {
    var last by rememberSaveable { mutableStateOf<ShopViewMode?>(null) }
    val switching = last != null && last != mode
    var shown by remember { mutableStateOf(!switching) }
    LaunchedEffect(mode) {
        last = mode
        shown = true
    }
    return shown
}

/** Gap between grid cells and between list rows across a hinge. */
private val SHOP_GUTTER = 10.dp

/** A hinge leaving less than this on either side does not split the content. */
private val SHOP_MIN_PANE = 240.dp

/**
 * Keep a centred state (loading, failure, hidden, empty) on the leading side of a
 * separating hinge so its text and buttons never sit on the fold.
 *
 * @param hinge (start pane width, hinge width) in pixels, or null without a split.
 * @param content The state.
 */
@Composable
private fun StartPane(hinge: Pair<Float, Float>?, content: @Composable () -> Unit) {
    if (hinge == null) {
        content()
        return
    }
    val width = with(LocalDensity.current) { hinge.first.toDp() }
    Box(Modifier.fillMaxHeight().width(width).testTag("fst.shop.start-pane")) { content() }
}

/**
 * Grid cells and their horizontal arrangement in one object: [ShopColumnPolicy] sizes and
 * places the cells so that, with a separating hinge, a wider gap sits on the fold.
 *
 * @property hinge Hinge start/end relative to the content's leading edge in pixels, or null.
 * @property gutterPx Normal gap in pixels.
 * @property minPanePx Smallest pane worth splitting for, in pixels.
 * @property densityValue Pixels per dp (grid columns are chosen in dp).
 * @property grid True for the card grid (web columns per pane), false for the one-cell-per-pane list.
 * @property capExtraPx Width the 1040 dp cap removed from an unsplit row; its columns still follow the page width (web).
 */
private data class ShopCells(
    val hinge: Pair<Int, Int>?,
    val gutterPx: Int,
    val minPanePx: Int,
    val densityValue: Float,
    val grid: Boolean,
    val capExtraPx: Int = 0,
) : GridCells, Arrangement.Horizontal {
    override val spacing: Dp get() = (gutterPx / densityValue).dp

    private fun resolve(available: Int): ShopColumns = ShopColumnPolicy.resolve(
        available = available,
        gutter = gutterPx,
        hingeStart = hinge?.first,
        hingeEnd = hinge?.second,
        minPane = minPanePx,
        uniform = grid,
        columnsFor = { px -> if (grid) ShopColumnPolicy.gridColumns((px + if (px >= available) capExtraPx else 0) / densityValue) else 1 },
    )

    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): List<Int> = resolve(availableSize).sizes

    override fun Density.arrange(totalSize: Int, sizes: IntArray, layoutDirection: LayoutDirection, outPositions: IntArray) {
        val columns = resolve(totalSize)
        sizes.indices.forEach { index ->
            val start = columns.positions.getOrElse(index) { 0 }
            outPositions[index] = if (layoutDirection == LayoutDirection.Rtl) totalSize - start - sizes[index] else start
        }
    }
}

/** Widest Shop grid/list (web `min(window, 1080) - 40`; M3 "constrain body content to 840–1040 dp"). */
internal const val SHOP_CONTENT_MAX_WIDTH_DP = 1040f

/** Minimum side margin of the Shop content (M3 compact margin). */
private const val SHOP_SIDE_MARGIN_DP = 16f

/**
 * Side margin that keeps the Shop content at most [SHOP_CONTENT_MAX_WIDTH_DP] wide and
 * centred (M3 large-screen layout), while the list/grid still scrolls edge to edge.
 *
 * @param widthDp Width available to the page.
 * @return Start/end content padding in dp: 16, or half the space beyond the cap.
 */
internal fun shopSideMargin(widthDp: Float): Float =
    maxOf(SHOP_SIDE_MARGIN_DP, (widthDp - SHOP_CONTENT_MAX_WIDTH_DP) / 2f)

@Composable
private fun HiddenView(padding: PaddingValues) {
    val shell = LocalShellActions.current
    FestivalEmptyState(
        "Item Shop Is Hidden",
        Modifier.fillMaxSize().padding(padding).testTag("fst.shop.hidden"),
        subtitle = "Turn off Hide Item Shop in Settings to see today's Jam Tracks.",
        action = { OutlinedButton(onClick = shell.back) { Text("Go Back") } },
    )
}

@Composable
private fun ShopContent(
    state: ShopUiState,
    mode: ShopViewMode,
    artworkUrl: (String?) -> String?,
    onRetryCatalog: () -> Unit,
    padding: PaddingValues,
    revealed: Boolean,
    hinge: Pair<Float, Float>?,
) {
    val shell = LocalShellActions.current
    val uri = LocalUriHandler.current
    val openOfficial: (ShopOfferItem) -> Unit = { item -> item.officialUrl?.let(uri::openUri) }
    val openDetail: (ShopOfferItem) -> Unit = { item -> item.detailSongId?.let { shell.navigate(SongDetailRoute(it)) } }
    val pulse = rememberShopPulse(active = state.offers.any { it.highlight != null })
    if (state.offers.isEmpty()) {
        StartPane(hinge) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val side = shopSideMargin(maxWidth.value).dp
                Column(Modifier.fillMaxSize().padding(start = side, end = side, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp)) {
                    if (state.detailsUnavailable) DetailsUnavailable(onRetryCatalog)
                    if (state.filteredEmpty) NoMatchingOffers(Modifier.weight(1f)) else EmptyShop(Modifier.weight(1f))
                }
            }
        }
        return
    }
    val grid = mode == ShopViewMode.Grid
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
        // Wide windows centre the content at SHOP_CONTENT_MAX_WIDTH_DP (M3 large-screen body width).
        val sideDp = shopSideMargin(maxWidth.value).dp
        val side = with(density) { sideDp.roundToPx() }
        val pageWidth = constraints.maxWidth
        val contentPadding = PaddingValues(start = sideDp, end = sideDp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp)
        // The hinge in the content's leading-edge coordinates (the cells mirror back for RTL).
        val contentHinge = hinge?.let { (start, width) ->
            val left = start.roundToInt()
            val right = (start + width).roundToInt()
            if (rtl) (pageWidth - right - side) to (pageWidth - left - side) else (left - side) to (right - side)
        }
        // Columns follow the page width (web window width) while tiles fill the capped content.
        val capExtra = with(density) { (sideDp - SHOP_SIDE_MARGIN_DP.dp).roundToPx() } * 2
        val cells = remember(contentHinge, density, grid, capExtra) {
            ShopCells(contentHinge, with(density) { SHOP_GUTTER.roundToPx() }, with(density) { SHOP_MIN_PANE.roundToPx() }, density.density, grid, capExtra)
        }
        // The Details warning spans the row but stays on the leading pane (its Retry never sits on the fold).
        val leadingWidth = remember(cells, pageWidth, side) {
            val columns = ShopColumnPolicy.resolve(pageWidth - 2 * side, cells.gutterPx, contentHinge?.first, contentHinge?.second, cells.minPanePx) { 1 }
            if (columns.split) with(density) { (columns.positions[0] + columns.sizes[0]).toDp() } else null
        }
        ProvideFoldLane(leadingWidth) {
            LazyVerticalGrid(
                columns = cells,
                contentPadding = contentPadding,
                horizontalArrangement = cells,
                verticalArrangement = Arrangement.spacedBy(if (grid) 10.dp else 6.dp),
                modifier = Modifier.fillMaxSize().testTag(if (grid) "fst.shop.grid" else "fst.shop.list"),
            ) {
                // Always present: a stable first key keeps the list anchored at the top when offers change.
                item(key = "header", span = { GridItemSpan(maxLineSpan) }) {
                    FoldLane {
                        if (state.detailsUnavailable) DetailsUnavailable(onRetryCatalog)
                    }
                }
                itemsIndexed(state.offers, key = { _, item -> item.offer.songId }) { index, item ->
                    Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                        if (grid) {
                            ShopGridCard(item, artworkUrl(item.offer.albumArt), pulse, { openOfficial(item) }, { openDetail(item) })
                        } else {
                            ShopListRow(item, artworkUrl(item.offer.albumArt), pulse, { openOfficial(item) }, { openDetail(item) })
                        }
                    }
                }
            }
        }
    }
}

/** Web Item Shop `EmptyState` (`shop.empty` / `shop.emptyHint`), centred in the page (6.33). */
@Composable
private fun EmptyShop(modifier: Modifier = Modifier) {
    FestivalEmptyState(
        "No Songs in the Item Shop",
        modifier.fillMaxSize().testTag("fst.shop.empty"),
        subtitle = "Check back later — the shop updates regularly.",
    )
}

/**
 * Every offer is hidden by the page filter: the shared centred empty state with copy distinct
 * from the genuine empty Shop. No card and no Reset button (#377); the Filter sheet's Reset restores every offer.
 * The web Shop has no filter, so the copy follows its Songs (`songs.noResults`) and Suggestions
 * (`suggestions.noSuggestionsFiltered`) filtered empty states.
 */
@Composable
private fun NoMatchingOffers(modifier: Modifier = Modifier) {
    FestivalEmptyState(
        SHOP_FILTERED_EMPTY_TITLE,
        modifier.fillMaxSize().testTag("fst.shop.filter.empty"),
        subtitle = SHOP_FILTERED_EMPTY_SUBTITLE,
    )
}

/** Filtered-empty title (web `songs.noResults` wording for the Item Shop). */
internal const val SHOP_FILTERED_EMPTY_TITLE = "No Item Shop songs match your filters."

/** Filtered-empty subtitle (web `suggestions.noSuggestionsFiltered` wording). */
internal const val SHOP_FILTERED_EMPTY_SUBTITLE = "Try changing your filters to see more songs."

@Composable
private fun DetailsUnavailable(onRetry: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.shop.song-details-error")) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) {
            Icon(Icons.Filled.Info, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(20.dp))
            Text("Song details unavailable", color = BrandTokens.textPrimary, modifier = Modifier.weight(1f).padding(start = 10.dp))
            TextButton(onClick = onRetry) { Text("Retry") }
        }
    }
}

// endregion

// region Offer views

/**
 * New / Leaving Tomorrow badge (visible text, never color alone).
 *
 * @param highlight Accent.
 * @param songId Song (test tag).
 * @param wordPerLine Large text in a narrow tile: one word per line, each shrunk only as far as
 *   needed to fit, so a word is never broken across lines ("Tomorro / w").
 */
@Composable
fun ShopBadgeLabel(highlight: ShopHighlight, songId: String, modifier: Modifier = Modifier, wordPerLine: Boolean = false) {
    val leaving = highlight == ShopHighlight.LeavingTomorrow
    val style = MaterialTheme.typography.labelMedium
    Text(
        shopBadgeText(highlight.label, wordPerLine),
        style = style,
        softWrap = !wordPerLine,
        autoSize = if (wordPerLine) TextAutoSize.StepBased(minFontSize = SHOP_BADGE_MIN_SP.sp, maxFontSize = style.fontSize) else null,
        fontWeight = FontWeight.Bold,
        color = if (leaving) BrandTokens.textPrimary else BrandTokens.gold,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(if (leaving) BrandTokens.statusRed else BrandTokens.appBackground)
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .testTag(if (leaving) "fst.shop.badge.leaving.$songId" else "fst.shop.badge.new.$songId"),
    )
}

/**
 * Shop card outline pulse color (web `ShopCard`: red Leaving Tomorrow, gold New; every
 * card is in the Shop, so there is no green).
 *
 * @param highlight Accent.
 * @return Outline color, or null without a highlight.
 */
internal fun shopOutline(highlight: ShopHighlight?): Color? = when (highlight) {
    ShopHighlight.LeavingTomorrow -> SongsTokens.pulse(ShopPulse.LeavingTomorrow)
    ShopHighlight.New -> SongsTokens.pulse(ShopPulse.New)
    null -> null
}

/**
 * Shop card outline pulse modifier ([shopOutline]).
 *
 * @param highlight Accent.
 * @param pulse Shared alpha.
 * @return Modifier.
 */
private fun Modifier.shopPulse(highlight: ShopHighlight?, pulse: () -> Float): Modifier =
    shopOutline(highlight)?.let { pulseOutline(it, pulse) } ?: this

/**
 * Web `ShopCard`: square artwork filling the card, title and artist on a bottom scrim,
 * a "Leaving Tomorrow" pill top-right, and the red/gold outline pulse. The card opens
 * the official Shop page (or the song when there is none); Song Details is a custom
 * accessibility action and a long press.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ShopGridCard(item: ShopOfferItem, artUrl: String?, pulse: () -> Float, onOfficial: () -> Unit, onDetail: () -> Unit) {
    val offer = item.offer
    val shape = RoundedCornerShape(12.dp)
    val open = if (item.officialUrl != null) onOfficial else onDetail
    val titleStyle = MaterialTheme.typography.titleSmall
    val artistStyle = MaterialTheme.typography.bodySmall
    val density = LocalDensity.current
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .shopPulse(item.highlight, pulse)
            .clip(shape)
            .background(BrandTokens.accentPurple.copy(alpha = 0.35f))
            .combinedClickable(onClick = open, onLongClick = if (item.detailSongId != null) onDetail else null)
            .semantics {
                contentDescription = item.announcement + if (item.officialUrl != null) ". Opens the Fortnite Item Shop" else ""
                if (item.detailSongId != null) customActions = listOf(CustomAccessibilityAction("Song Details") { onDetail(); true })
            }
            .testTag("fst.shop.song.${offer.songId}"),
    ) {
        if (artUrl != null) {
            AsyncImage(model = artUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        // Large text wraps inside a fixed square: split the room so both texts end in "…" rather than clip.
        val lines = shopCardTextHeights(
            tile = maxHeight,
            titleLine = with(density) { titleStyle.lineHeight.takeIf { it.isSp }?.toDp() ?: 20.dp },
            artistLine = with(density) { artistStyle.lineHeight.takeIf { it.isSp }?.toDp() ?: 16.dp },
            badge = item.highlight == ShopHighlight.LeavingTomorrow && isLargeText(),
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .clearAndSetSemantics { },
        ) {
            Text(offer.title, style = titleStyle, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis, modifier = Modifier.heightIn(max = lines.first))
            Text(offer.artist, style = artistStyle, color = BrandTokens.textSecondary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp).heightIn(max = lines.second))
        }
        if (item.highlight == ShopHighlight.LeavingTomorrow) {
            // The card's description already says "Leaving Tomorrow".
            Box(Modifier.align(Alignment.TopEnd).padding(10.dp).testTag("fst.shop.badge.leaving.${offer.songId}")) {
                ShopBadgeLabel(ShopHighlight.LeavingTomorrow, offer.songId, Modifier.clearAndSetSemantics { }, wordPerLine = isLargeText())
            }
        }
        if (item.officialUrl != null) Box(Modifier.size(0.dp).testTag("fst.shop.external.${offer.songId}"))
    }
}

/**
 * Item Shop list row: the shared Songs [SongRowCard] (glass surface, art, marquee title
 * and subtitle, red/gold outline pulse) with the New / Leaving Tomorrow badge under
 * the subtitle and the official Shop link (cart + chevron) as its own button. The row
 * opens Song Details when matched, else the official link; TalkBack reads its texts.
 */
@Composable
internal fun ShopListRow(item: ShopOfferItem, artUrl: String?, pulse: () -> Float, onOfficial: () -> Unit, onDetail: () -> Unit, modifier: Modifier = Modifier, titleTag: String? = null) {
    val offer = item.offer
    SongRowCard(
        title = offer.title,
        subtitle = offer.subtitle,
        artUrl = artUrl,
        onClick = if (item.detailSongId != null) onDetail else onOfficial,
        modifier = modifier.testTag("fst.shop.song.${offer.songId}"),
        titleTag = titleTag,
        outline = shopOutline(item.highlight),
        pulse = pulse,
        details = { item.highlight?.let { ShopBadgeLabel(it, offer.songId, Modifier.padding(top = 4.dp)) } },
        end = {
            if (item.officialUrl != null) {
                IconButton(
                    onClick = onOfficial,
                    // M3 minimum touch target on both axes (the icon pair is narrower than 48 dp).
                    modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).testTag("fst.shop.external.${offer.songId}"),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.ShoppingCart, contentDescription = "Open ${offer.title} in the Fortnite Item Shop", tint = BrandTokens.textPrimary, modifier = Modifier.size(20.dp))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.size(18.dp))
                    }
                }
            }
        },
    )
}

// endregion

// region Detail action

/**
 * Official Shop action for Song Detail: the "Item Shop" pill (its status is in the
 * spoken label; no separate New / Leaving chip, operator rule). With a
 * pulse the button breathes between the dark surface and green (in Shop), gold
 * (New) or red (Leaving Tomorrow) every 3 s (web `shopBreathe*`); reduced motion
 * holds the target color. The color is read only while drawing.
 *
 * @param highlight Effective badge.
 * @param url Validated official URL.
 * @param songId Song (test tag).
 * @param pulse Effective Shop pulse.
 */
@Composable
fun ShopDetailAction(highlight: ShopHighlight?, url: String, songId: String, pulse: ShopPulse? = null) {
    val uri = LocalUriHandler.current
    val fraction = rememberShopBreathe(active = pulse != null)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.song-detail.shop")) {
        ShopActionButton(highlight, pulse, fraction) { uri.openUri(url) }
    }
}

/**
 * The "Item Shop" pill itself: filled, or breathing in the [pulse] color with [fraction] read
 * only while drawing. Shared by Song Detail and its first-run demos (issue #380).
 *
 * @param highlight Effective badge (spoken).
 * @param pulse Effective Shop pulse, or null for the plain filled button.
 * @param fraction Breathe fraction ([rememberShopBreathe]).
 * @param onClick Open the official Shop page.
 */
@Composable
internal fun ShopActionButton(highlight: ShopHighlight?, pulse: ShopPulse?, fraction: () -> Float, onClick: () -> Unit) {
    val breathe: (() -> Color)? = pulse?.let { status -> { SongsTokens.breathe(status, fraction()) } }
    Button(
        onClick = onClick,
        colors = if (breathe != null) ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = BrandTokens.textPrimary) else festivalFilledButtonColors(),
        modifier = Modifier
            .semantics { contentDescription = listOfNotNull("Item Shop", highlight?.label, "opens the Fortnite Item Shop").joinToString(", ") }
            .then(
                if (breathe != null) {
                    Modifier.testTag("fst.song-detail.shop-breathe.${pulse!!.name}").drawBehind { drawRoundRect(breathe(), cornerRadius = CornerRadius(size.height / 2)) }
                } else {
                    Modifier
                },
            ),
    ) {
        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(18.dp))
        // The button's description already says "Item Shop".
        Text("Item Shop", modifier = Modifier.padding(start = 6.dp).clearAndSetSemantics {})
    }
}

// endregion
