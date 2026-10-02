package com.festivalscoretracker.android.ui.quicklinks

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
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.Toc
import androidx.compose.material.icons.outlined.Accessibility
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Dns
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.quicklinks.QuickLinkFrame
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinkTracker
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
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

/** The scrolling surface a controller drives: a `LazyColumn` or a staggered grid. */
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
}

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
}

/** [QuickLinkScroller] over a `LazyVerticalStaggeredGrid` (several items can share a row). */
private class StaggeredScroller(private val state: LazyStaggeredGridState) : QuickLinkScroller {
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
}

/**
 * Quick Links state for one page backed by a lazy list or staggered grid whose
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
    completePx: Float,
) {
    private val tracker = QuickLinkTracker(activationOffset = activationPx, band = bandPx, completeThreshold = completePx)

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

    /** Whether jumps animate (off under reduce motion). */
    internal var animate: Boolean = true

    /** Active section ID. */
    var activeId: String? by mutableStateOf(null)
        private set

    /** Whether the page has enough sections to show Quick Links. */
    val available: Boolean get() = QuickLinks.isAvailable(sections.size)

    /** Title of the active section. */
    val activeTitle: String? get() = sections.firstOrNull { it.id == activeId }?.title

    /**
     * Jump to a section: it becomes active immediately and owns the viewport after landing.
     *
     * @param id Section ID.
     */
    fun jump(id: String) {
        val index = indexOf(id) ?: return
        tracker.beginJump(id)
        activeId = tracker.activeId
        scope.launch {
            scroller.scrollTo(index, animate, landingPx.roundToInt())
            val layout = scroller.layout()
            tracker.settle(sections, frames(layout), layout.viewportHeight)
            activeId = tracker.activeId
        }
    }

    internal fun onLayout(layout: QuickLinkLayout) {
        tracker.update(sections, frames(layout), layout.viewportHeight)
        if (activeId != tracker.activeId) activeId = tracker.activeId
    }

    /** Frames: visible items from layout; items above the first visible one are "far above"; below is unknown. */
    private fun frames(layout: QuickLinkLayout): Map<String, QuickLinkFrame> {
        val first = layout.items.minOfOrNull { it.index } ?: return emptyMap()
        val result = HashMap<String, QuickLinkFrame>()
        sections.forEach { section ->
            val index = indexOf(section.id) ?: return@forEach
            val item = layout.items.firstOrNull { it.index == index }
            when {
                item != null -> result[section.id] = QuickLinkFrame(item.top.toFloat(), item.bottom.toFloat())
                index < first -> result[section.id] = QuickLinkFrame(-1_000_000f, -999_999f)
            }
        }
        return result
    }
}

/**
 * Remember a page's Quick Links controller and keep its sections current.
 *
 * @param listState The page's list state.
 * @param title Quick Links title.
 * @param sections Sections in order (duplicates are dropped).
 * @param pinnedHeaders Section headers are sticky (Songs): jumps land them flush so they pin, with a 16 dp activation line.
 * @param indexOf Section ID → list item index.
 * @return Controller.
 */
@Composable
fun rememberQuickLinks(
    listState: LazyListState,
    title: String,
    sections: List<QuickLinkSection>,
    pinnedHeaders: Boolean = false,
    indexOf: (String) -> Int?,
): QuickLinksController =
    rememberQuickLinks(remember(listState) { ListScroller(listState) }, title, sections, pinnedHeaders, indexOf)

/**
 * Remember a Quick Links controller for a page laid out as a staggered grid.
 *
 * @param gridState The page's grid state.
 * @param title Quick Links title.
 * @param sections Sections in order (duplicates are dropped).
 * @param indexOf Section ID → grid item index.
 * @return Controller.
 */
@Composable
fun rememberQuickLinks(gridState: LazyStaggeredGridState, title: String, sections: List<QuickLinkSection>, indexOf: (String) -> Int?): QuickLinksController =
    rememberQuickLinks(remember(gridState) { StaggeredScroller(gridState) }, title, sections, pinnedHeaders = false, indexOf = indexOf)

/**
 * Remember a controller over any [QuickLinkScroller].
 *
 * Jumps land a section 32 dp below the visible top of the page (the web's default offset, #51) and the
 * activation line matches, so the landed section is the highlighted one. Lists with sticky headers land
 * them flush instead ([pinnedHeaders]).
 */
@Composable
internal fun rememberQuickLinks(
    scroller: QuickLinkScroller,
    title: String,
    sections: List<QuickLinkSection>,
    pinnedHeaders: Boolean = false,
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
    // Quick Links teleport to the section like the web (operator batch 7.15), never an animated scroll.
    controller.animate = false
    LaunchedEffect(controller) {
        snapshotFlow { scroller.layout() }.collect(controller::onLayout)
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
    "trash" -> Icons.Outlined.Delete
    "accessibility" -> Icons.Outlined.Accessibility
    "trophy" -> Icons.Outlined.EmojiEvents
    "people" -> Icons.Outlined.People
    "chart" -> Icons.Outlined.BarChart
    "timer" -> Icons.Outlined.Timer
    else -> Icons.AutoMirrored.Outlined.Toc
}

@Composable
private fun SectionIcon(section: QuickLinkSection) {
    val instrument = section.instrument
    if (instrument != null) InstrumentIcon(instrument, size = 24.dp, decorative = true) else Icon(quickLinkIcon(section.icon), contentDescription = null)
}

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
                        text = { Text(section.title, fontWeight = if (current) FontWeight.Bold else null, modifier = Modifier.clearAndSetSemantics {}) },
                        leadingIcon = { SectionIcon(section) },
                        trailingIcon = if (current) ({ Text("Current", style = MaterialTheme.typography.labelSmall, color = BrandTokens.textSecondary, modifier = Modifier.clearAndSetSemantics {}) }) else null,
                        onClick = {
                            open = false
                            controller.jump(section.id)
                        },
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
            skipPartiallyExpanded = controller.sections.size <= 8,
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
                modifier = Modifier.padding(start = (12 + 16 * section.depth).dp).testTag(section.testTag).currentSection(section, current),
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
