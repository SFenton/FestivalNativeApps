package com.festivalscoretracker.android.ui.quicklinks

import com.festivalscoretracker.android.ui.common.LocalFadeInWindow
import com.festivalscoretracker.android.ui.common.FadeInWindow
import com.festivalscoretracker.android.ui.design.popupTestTags
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.Toc
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.Accessibility
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.StackedBarChart
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.quicklinks.QuickLinkFrame
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinkTracker
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.roundToInt
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Controller

/**
 * One laid-out lazy item.
 *
 * @property index Item index.
 * @property top Top edge relative to the visible viewport top (the list's `offset` plus its leading content padding).
 * @property bottom Bottom edge.
 */
internal data class QuickLinkItem(val index: Int, val top: Int, val bottom: Int)

/**
 * A lazy layout's visible items, in viewport coordinates (0 = the visible top edge, just below the top bar).
 *
 * @property items Visible items.
 * @property viewportHeight Viewport height without the trailing content padding.
 */
internal data class QuickLinkLayout(val items: List<QuickLinkItem>, val viewportHeight: Float)

/** The scrolling surface a controller drives: a `LazyColumn` or a `LazyVerticalGrid`. */
internal interface QuickLinkScroller {
    /** Current layout; reads snapshot state, so `snapshotFlow` follows it. */
    fun layout(): QuickLinkLayout

    /**
     * Bring an item's top to the landing line.
     *
     * @param index Item index.
     * @param animate Animate the scroll.
     * @param landingPx Landing line below the visible viewport top, in pixels.
     */
    suspend fun scrollTo(index: Int, animate: Boolean, landingPx: Int)

    /** A scroll is running (a user drag or fling while no jump is scrolling). */
    val isScrollInProgress: Boolean

    /** The content can scroll further down. */
    val canScrollForward: Boolean

    /** The content can scroll further up. */
    val canScrollBackward: Boolean

    /**
     * Scroll position (a lazy layout's first visible index and offset, or a scroll state's value).
     * Content resizing above the anchor leaves it unchanged; any scroll moves it.
     */
    val position: Long
}

/**
 * Packs a lazy layout's first visible item and its scroll offset into one comparable position.
 *
 * @param index First visible item index.
 * @param offset Scroll offset into that item.
 * @return Position.
 */
private fun lazyPosition(index: Int, offset: Int): Long = (index.toLong() shl 32) or (offset.toLong() and 0xFFFF_FFFFL)

/** [QuickLinkScroller] over a `LazyColumn`. */
private class ListScroller(private val state: LazyListState) : QuickLinkScroller {
    override fun layout(): QuickLinkLayout {
        val info = state.layoutInfo
        val start = info.viewportStartOffset
        return QuickLinkLayout(
            info.visibleItemsInfo.map { QuickLinkItem(it.index, it.offset - start, it.offset + it.size - start) },
            (info.viewportEndOffset - start - info.afterContentPadding).toFloat(),
        )
    }

    override suspend fun scrollTo(index: Int, animate: Boolean, landingPx: Int) {
        val offset = QuickLinks.lazyLandingScrollOffset(landingPx, state.layoutInfo.beforeContentPadding)
        if (animate) state.animateScrollToItem(index, offset) else state.scrollToItem(index, offset)
    }

    override val isScrollInProgress: Boolean get() = state.isScrollInProgress
    override val canScrollForward: Boolean get() = state.canScrollForward
    override val canScrollBackward: Boolean get() = state.canScrollBackward
    override val position: Long get() = lazyPosition(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset)
}

/** [QuickLinkScroller] over a `LazyVerticalGrid` (several items can share a row and its top edge). */
private class GridScroller(private val state: LazyGridState) : QuickLinkScroller {
    override fun layout(): QuickLinkLayout {
        val info = state.layoutInfo
        val start = info.viewportStartOffset
        return QuickLinkLayout(
            info.visibleItemsInfo.map { QuickLinkItem(it.index, it.offset.y - start, it.offset.y + it.size.height - start) },
            (info.viewportEndOffset - start - info.afterContentPadding).toFloat(),
        )
    }

    override suspend fun scrollTo(index: Int, animate: Boolean, landingPx: Int) {
        val offset = QuickLinks.lazyLandingScrollOffset(landingPx, state.layoutInfo.beforeContentPadding)
        if (animate) state.animateScrollToItem(index, offset) else state.scrollToItem(index, offset)
    }

    override val isScrollInProgress: Boolean get() = state.isScrollInProgress
    override val canScrollForward: Boolean get() = state.canScrollForward
    override val canScrollBackward: Boolean get() = state.canScrollBackward
    override val position: Long get() = lazyPosition(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset)
}

/**
 * Quick Links state for one page backed by a lazy list or grid whose
 * sections are items. Layout is observed only through `snapshotFlow` of the
 * layout info, and [activeId] changes only when the active section changes, so
 * scrolling does not recompose the page.
 *
 * @param title Title Case title (web `settings.quickLinks` etc.); see [QuickLinksController.title].
 * @param landingPx Where a jump lands a section's top below the visible top, in pixels.
 * @param activationPx Activation line below the visible top, in pixels (the landing line, or just below a flush pinned header).
 * @param bandPx Reachable band, in pixels.
 * @param completePx Landing tolerance, in pixels.
 */
@Stable
class QuickLinksController internal constructor(
    private val scroller: QuickLinkScroller,
    title: String,
    private val scope: CoroutineScope,
    private val landingPx: Float,
    activationPx: Float,
    bandPx: Float,
    private val completePx: Float,
) {
    private val tracker = QuickLinkTracker(activationOffset = activationPx, band = bandPx, completeThreshold = completePx)
    private val completeThreshold = completePx.roundToInt()
    private var landing: Job? = null

    /**
     * Whether a landed jump keeps its target on the landing line while content above it resizes
     * (off for sticky-header lists, whose fixed rows cannot shift a landed header).
     */
    internal var holdLanding: Boolean = true

    /**
     * Section ID → how far its heading sits below the top of its item, in pixels (the heading's own top
     * padding). Jumps land the heading on the landing line and the activation line tracks it
     * (`section-jump-landing` R2, issue #587).
     */
    internal var headingInset: (String) -> Float = { 0f }

    /**
     * Title Case title (Songs: "<Sort> Quick Links"). Snapshot state, so a page keeps one controller
     * when its title changes: the shell's floating toolbar re-runs a page's actions only for state
     * reads, and a replaced controller could leave it showing a stale one with no sections.
     */
    var title: String by mutableStateOf(title)
        internal set

    /** Sections in order. */
    var sections: List<QuickLinkSection> by mutableStateOf(emptyList())
        internal set

    /** Section ID → item index. */
    internal var indexOf: (String) -> Int? = { null }

    /**
     * Section ID → the section's top below its item's top in pixels (0 for a section that is a whole
     * item; null while a nested section's anchor has not been measured). Reads snapshot state.
     */
    internal var offsetOf: (String) -> Int? = { 0 }

    /** Whether jumps animate (off under reduce motion). */
    internal var animate: Boolean = true

    /** The page's fade window, rushed by a jump like any scroll (load-transition R5, issue #323). */
    internal var fadeInWindow: FadeInWindow? = null

    /** Active section ID. */
    var activeId: String? by mutableStateOf(null)
        private set

    /** Whether the page has enough sections to show Quick Links. */
    val available: Boolean get() = QuickLinks.isAvailable(sections.size)

    /** Title of the active section. */
    val activeTitle: String? get() = sections.firstOrNull { it.id == activeId }?.title

    /**
     * Jump to a section: it becomes active immediately and owns the viewport after landing.
     * The landing is held for [QuickLinks.LANDING_HOLD_MS] (or until the user scrolls): content that
     * starts loading once the jump composes it (a profile's rank history above Top Songs, its bands
     * below the Bands heading) would otherwise push the section off the landing line, because a lazy
     * list keeps its first visible item where it is when that item grows.
     *
     * @param id Section ID.
     */
    fun jump(id: String) {
        val index = indexOf(id) ?: return
        tracker.beginJump(id)
        activeId = tracker.activeId
        // A jump is a scroll: fades that have not started yet run together (web `useStaggerRush`).
        fadeInWindow?.rush()
        landing?.cancel()
        landing = scope.launch {
            val px = QuickLinks.itemLandingPx(landingPx.roundToInt(), headingInset(id).roundToInt())
            // A nested section (a card inside its item) lands at its own top once measured; until
            // then the item's top lands and the hold below moves on as soon as the anchor reports.
            scroller.scrollTo(index, animate, px - (offsetOf(id) ?: 0))
            settle()
            if (holdLanding) keepLanded(id, index, px)
        }
    }

    private fun settle() {
        val layout = scroller.layout()
        tracker.settle(sections, frames(layout), layout.viewportHeight)
        activeId = tracker.activeId
    }

    /**
     * Keep a landed target on the landing line while the item above it (the lazy list's scroll anchor)
     * composes for the first time and grows (issue #106: Profile Rank History loads after the jump and
     * pushed Top Songs half a screen down; #111: Statistics). Ends at the first user scroll (a drag, or a
     * programmatic scroll such as a TalkBack scroll-to-index or a page's scroll-to-top, which moves
     * [QuickLinkScroller.position] between the hold's own landings), the next jump, after
     * [QuickLinks.MAX_LANDING_CORRECTIONS] corrections or after [QuickLinks.LANDING_HOLD_MS].
     */
    private suspend fun keepLanded(id: String, index: Int, px: Int) {
        var corrections = 0
        // The position the hold last saw; null right after its own landing, which moves it.
        var expected: Long? = null
        withTimeoutOrNull(QuickLinks.LANDING_HOLD_MS) {
            snapshotFlow { Triple(scroller.layout(), scroller.position, offsetOf(id)) }
                .takeWhile { (_, position, _) ->
                    val unmoved = expected == null || expected == position
                    expected = position
                    unmoved && !scroller.isScrollInProgress && corrections < QuickLinks.MAX_LANDING_CORRECTIONS
                }
                .collect { (layout, _, offset) ->
                    val inset = offset ?: 0
                    val top = layout.items.firstOrNull { it.index == index }?.top?.plus(inset)
                    val below = if (top == null) (layout.items.maxOfOrNull { it.index } ?: -1) < index else null
                    if (QuickLinks.needsReland(top, px, completeThreshold, scroller.canScrollForward, scroller.canScrollBackward, below)) {
                        corrections++
                        scroller.scrollTo(index, animate = false, landingPx = px - inset)
                        expected = null
                        tracker.beginJump(id)
                        settle()
                    }
                }
        }
    }

    internal fun onLayout(layout: QuickLinkLayout) {
        tracker.update(sections, frames(layout), layout.viewportHeight)
        if (activeId != tracker.activeId) activeId = tracker.activeId
    }

    /**
     * Frames: visible items from layout, starting at their headings (a nested section from its anchor's
     * offset down to the item's bottom, skipped while unmeasured); items above the first visible one are
     * "far above"; below is unknown.
     */
    private fun frames(layout: QuickLinkLayout): Map<String, QuickLinkFrame> {
        val first = layout.items.minOfOrNull { it.index } ?: return emptyMap()
        val result = HashMap<String, QuickLinkFrame>()
        sections.forEach { section ->
            val index = indexOf(section.id) ?: return@forEach
            val item = layout.items.firstOrNull { it.index == index }
            when {
                item != null -> offsetOf(section.id)?.let { offset ->
                    result[section.id] = QuickLinks.headingFrame((item.top + offset).toFloat(), item.bottom.toFloat(), headingInset(section.id))
                }
                index < first -> result[section.id] = QuickLinkFrame(-1_000_000f, -999_999f)
            }
        }
        return result
    }
}

/**
 * Measured tops of nested Quick Link sections: cards inside one lazy item (the player page's
 * per-chart Rank History and Percentiles, #590), so the page's Quick Links list them like iOS.
 * Mark each card with [quickLinkAnchor]; pass [offsetOf] to [rememberQuickLinks].
 */
@Stable
class QuickLinkAnchors {
    private val offsets = mutableStateMapOf<String, Int>()

    /**
     * A nested section's top below its item's top, or null until measured (snapshot state).
     *
     * @param id Section ID.
     * @return Offset in pixels.
     */
    fun offsetOf(id: String): Int? = offsets[id]

    internal fun report(id: String, offset: Int) {
        if (offsets[id] != offset) offsets[id] = offset
    }
}

/**
 * Report this element's top as nested section [id]'s offset in its lazy item. The element must be
 * a direct child of a layout placed at the item's top (the player page's chart `Column`), and this
 * must be its first modifier so the offset is its placement in that parent.
 *
 * @param anchors Page anchors.
 * @param id Section ID.
 * @return Modifier.
 */
fun Modifier.quickLinkAnchor(anchors: QuickLinkAnchors, id: String): Modifier =
    onPlaced { anchors.report(id, it.positionInParent().y.roundToInt()) }

/**
 * Remember a page's Quick Links controller and keep its sections current.
 *
 * @param listState The page's list state.
 * @param title Quick Links title.
 * @param sections Sections in order (duplicates are dropped).
 * @param pinnedHeaders Section headers are sticky (Songs): jumps land them flush so they pin, with a 16 dp activation line.
 * @param fadeInWindow The page's fade window, which jumps rush (defaults to the enclosing one).
 * @param headingInset Section ID → how far its heading sits below its item's top (the heading's own top
 *   padding, such as [com.festivalscoretracker.android.ui.design.SECTION_HEADER_TOP_PADDING]); jumps land
 *   the heading, not that padding, on the landing line (issue #587). Ignored with [pinnedHeaders].
 * @param indexOf Section ID → list item index.
 * @return Controller.
 */
@Composable
fun rememberQuickLinks(
    listState: LazyListState,
    title: String,
    sections: List<QuickLinkSection>,
    pinnedHeaders: Boolean = false,
    fadeInWindow: FadeInWindow? = LocalFadeInWindow.current,
    headingInset: (String) -> Dp = NO_HEADING_INSET,
    indexOf: (String) -> Int?,
): QuickLinksController =
    rememberQuickLinks(remember(listState) { ListScroller(listState) }, title, sections, pinnedHeaders, fadeInWindow, headingInset, indexOf = indexOf)

/**
 * Remember a Quick Links controller for a page laid out as a row-major card grid.
 *
 * @param gridState The page's grid state.
 * @param title Quick Links title.
 * @param sections Sections in order (duplicates are dropped).
 * @param fadeInWindow The page's fade window, which jumps rush (defaults to the enclosing one).
 * @param headingInset Section ID → how far its heading sits below its item's top (issue #587).
 * @param offsetOf Section ID → the section's top below its item's top in pixels, or null while
 *   unmeasured ([QuickLinkAnchors.offsetOf] for nested sections); 0 for whole-item sections.
 * @param indexOf Section ID → grid item index.
 * @return Controller.
 */
@Composable
fun rememberQuickLinks(
    gridState: LazyGridState,
    title: String,
    sections: List<QuickLinkSection>,
    fadeInWindow: FadeInWindow? = LocalFadeInWindow.current,
    headingInset: (String) -> Dp = NO_HEADING_INSET,
    offsetOf: (String) -> Int? = { 0 },
    indexOf: (String) -> Int?,
): QuickLinksController =
    rememberQuickLinks(remember(gridState) { GridScroller(gridState) }, title, sections, pinnedHeaders = false, fadeInWindow = fadeInWindow, headingInset = headingInset, offsetOf = offsetOf, indexOf = indexOf)

/** Sections whose headings sit flush with their items' tops (Settings, Leaderboards). */
internal val NO_HEADING_INSET: (String) -> Dp = { 0.dp }

/**
 * Remember a controller over any [QuickLinkScroller].
 *
 * Jumps land a section's heading 32 dp below the visible top of the page (the web's default offset, #51;
 * the heading rather than its item's padded top, #587) and the activation line matches, so the landed
 * section is the highlighted one. Lists with sticky headers land them flush instead ([pinnedHeaders]).
 */
@Composable
internal fun rememberQuickLinks(
    scroller: QuickLinkScroller,
    title: String,
    sections: List<QuickLinkSection>,
    pinnedHeaders: Boolean = false,
    fadeInWindow: FadeInWindow? = LocalFadeInWindow.current,
    headingInset: (String) -> Dp = NO_HEADING_INSET,
    offsetOf: (String) -> Int? = { 0 },
    indexOf: (String) -> Int?,
): QuickLinksController {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val landingDp = if (pinnedHeaders) 0 else QuickLinks.LANDING_OFFSET_DP
    val activationDp = if (pinnedHeaders) QuickLinks.PINNED_HEADER_ACTIVATION_OFFSET_DP else QuickLinks.LANDING_OFFSET_DP
    val controller = remember(scroller, pinnedHeaders, density) {
        with(density) {
            QuickLinksController(
                scroller, title, scope,
                landingPx = landingDp.dp.toPx(),
                activationPx = activationDp.dp.toPx(),
                bandPx = QuickLinks.REACHABLE_BAND_DP.dp.toPx(),
                completePx = QuickLinks.COMPLETE_THRESHOLD_DP.dp.toPx(),
            )
        }
    }
    controller.title = title
    controller.sections = QuickLinks.ordered(sections)
    controller.indexOf = indexOf
    controller.offsetOf = offsetOf
    // Quick Links teleport to the section like the web (operator batch 7.15), never an animated scroll.
    controller.animate = false
    controller.holdLanding = !pinnedHeaders
    controller.headingInset = if (pinnedHeaders) { _ -> 0f } else { id -> with(density) { headingInset(id).toPx() } }
    controller.fadeInWindow = fadeInWindow
    LaunchedEffect(controller) {
        // Nested anchors report after their item's layout, so their offsets are followed too.
        snapshotFlow { scroller.layout() to controller.sections.map { controller.offsetOf(it.id) } }.collect { controller.onLayout(it.first) }
    }
    return controller
}

// endregion

// region Icons

/**
 * Material icon for a section icon token.
 *
 * @param token Token from [QuickLinkSection.icon].
 * @return Icon.
 */
fun quickLinkIcon(token: String?): ImageVector = when (token) {
    "settings" -> Icons.Outlined.Settings
    "info" -> Icons.Outlined.Info
    "shop" -> Icons.Outlined.ShoppingBag
    "music" -> Icons.Outlined.LibraryMusic
    "list" -> Icons.AutoMirrored.Outlined.List
    "service" -> Icons.Outlined.Dns
    "sparkles" -> Icons.Outlined.AutoAwesome
    "document" -> Icons.Outlined.Description
    "privacy" -> Icons.Outlined.PrivacyTip
    "trash" -> Icons.Outlined.Delete
    "accessibility" -> Icons.Outlined.Accessibility
    "trophy" -> Icons.Outlined.EmojiEvents
    "people" -> Icons.Outlined.People
    "chart" -> Icons.Outlined.BarChart
    "timer" -> Icons.Outlined.Timer
    "trend" -> Icons.AutoMirrored.Outlined.TrendingUp
    "percentiles" -> Icons.Outlined.StackedBarChart
    else -> Icons.AutoMirrored.Outlined.Toc
}

@Composable
private fun SectionIcon(section: QuickLinkSection) {
    val instrument = section.instrument
    if (instrument != null) InstrumentIcon(instrument, size = 24.dp, decorative = true) else Icon(quickLinkIcon(section.icon), contentDescription = null)
}

/**
 * A menu item's visible label: the title, bold with a "Current" line beneath it for the current
 * section. "Current" sits under the title rather than trailing it because menu items are capped
 * at 280 dp: a trailing label squeezed long titles until words broke mid-word at 2.0 font scale
 * (issue #137, FST_Tablet). TalkBack reads the item's own label and state instead.
 *
 * @param title Section title.
 * @param current Whether this is the current section.
 * @param modifier Modifier (the caller clears its semantics).
 */
@Composable
internal fun QuickLinkMenuLabel(title: String, current: Boolean, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, fontWeight = if (current) FontWeight.Bold else null, modifier = Modifier.testTag(MENU_TITLE_TAG))
        if (current) Text(QUICK_LINKS_CURRENT, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textSecondary, modifier = Modifier.testTag(MENU_CURRENT_TAG))
    }
}

/** Test tag of a menu label's title (only reachable where the caller keeps semantics). */
internal const val MENU_TITLE_TAG = "fst.quick-links.menu-label.title"

/** Test tag of a menu label's "Current" line. */
internal const val MENU_CURRENT_TAG = "fst.quick-links.menu-label.current"

// endregion

// region Entry point

/**
 * Top-app-bar entry (compact and medium widths): a "Quick Links" action that
 * opens a modal bottom sheet on compact windows and an anchored menu on
 * medium ones. Hidden with fewer than two sections.
 *
 * @param controller Page controller.
 * @param windowWidthDp Window width, choosing sheet vs menu.
 */
/** Quick Links button glyph size. */
private const val QUICK_LINKS_ICON_DP = 30

/** Visible marker under the current section in the menu. */
private const val QUICK_LINKS_CURRENT = "Current"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickLinksAction(controller: QuickLinksController, windowWidthDp: Int) {
    if (!controller.available) return
    var open by remember { mutableStateOf(false) }
    val label = controller.activeTitle?.let { "${controller.title}, current section $it" } ?: controller.title
    Box {
        IconButton(
            onClick = { open = true },
            modifier = Modifier.testTag("fst.quick-links.open").semantics { contentDescription = label },
        ) {
            // The Toc glyph is thin and short; at the 24 dp default it looked lost in the 64 dp
            // floating-toolbar circle (batch 6.24), so it uses the web FAB's larger icon size.
            Icon(Icons.AutoMirrored.Outlined.Toc, contentDescription = null, modifier = Modifier.size(QUICK_LINKS_ICON_DP.dp))
        }
        if (!QuickLinks.usesSheet(windowWidthDp)) {
            DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.popupTestTags().testTag("fst.quick-links.menu")) {
                controller.sections.forEach { section ->
                    val current = section.id == controller.activeId
                    DropdownMenuItem(
                        // "Current" sits under the title rather than trailing it: menu items are capped at
                        // 280 dp, so a trailing label squeezed long titles until words broke mid-word at
                        // 2.0 font scale (issue #137, FST_Tablet).
                        text = { QuickLinkMenuLabel(section.title, current, Modifier.clearAndSetSemantics {}) },
                        leadingIcon = { SectionIcon(section) },
                        onClick = {
                            open = false
                            controller.jump(section.id)
                        },
                        // Nested sections indent 16 dp per level, like the sheet's list (#590).
                        contentPadding = PaddingValues(start = (12 + 16 * section.depth).dp, end = 12.dp),
                        modifier = Modifier.testTag(section.testTag).currentSection(section, current),
                    )
                }
            }
        }
    }
    if (open && QuickLinks.usesSheet(windowWidthDp)) {
        FestivalModalSheet(
            title = controller.title,
            closeTag = "fst.quick-links.close",
            onDismissRequest = { open = false },
            modifier = Modifier.testTag("fst.quick-links.sheet"),
        ) {
            SectionList(controller, Modifier.fillMaxWidth().testTag("fst.quick-links.list"), PaddingValues(start = 12.dp, end = 12.dp, bottom = 24.dp)) { id ->
                open = false
                controller.jump(id)
            }
        }
    }
}

@Composable
private fun SectionList(controller: QuickLinksController, modifier: Modifier, padding: PaddingValues, onSelect: (String) -> Unit) {
    LazyColumn(modifier, contentPadding = padding) {
        items(controller.sections, key = { it.id }) { section ->
            val current = section.id == controller.activeId
            NavigationDrawerItem(
                label = { Text(section.title, maxLines = 2, modifier = Modifier.clearAndSetSemantics {}) },
                icon = { SectionIcon(section) },
                selected = current,
                onClick = { onSelect(section.id) },
                colors = NavigationDrawerItemDefaults.colors(
                    selectedContainerColor = BrandTokens.accentPurple.copy(alpha = 0.45f),
                    unselectedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                    selectedTextColor = BrandTokens.textPrimary,
                    unselectedTextColor = BrandTokens.textSecondary,
                    selectedIconColor = BrandTokens.textPrimary,
                    unselectedIconColor = BrandTokens.textSecondary,
                ),
                // Indicator inset 24 dp on both sides (12 dp list padding + 12 dp), lining up with the
                // sheet title and close glyph; depth indents only the start.
                modifier = Modifier.padding(start = (12 + 16 * section.depth).dp, end = 12.dp).testTag(section.testTag).currentSection(section, current),
            )
        }
    }
}

/**
 * TalkBack: label plus a "Current section" state (the native `aria-current="location"`).
 * The visible texts are hidden so the label is not read twice.
 */
private fun Modifier.currentSection(section: QuickLinkSection, current: Boolean): Modifier = semantics {
    contentDescription = section.accessibleTitle
    selected = current
    if (current) stateDescription = "Current section"
}

// endregion
