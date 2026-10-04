package com.festivalscoretracker.android.ui.quicklinks

import androidx.compose.foundation.ScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import kotlin.math.roundToInt

// region Scroll-state sections

/**
 * Quick Links over a plain `verticalScroll` column (pages that are not lazy lists, such as
 * Band Detail). Sections mark themselves with [section]; the scroll container marks its
 * viewport with [viewport]. Offsets are content coordinates, so a jump is one
 * `scrollTo` and layout tracking reads only snapshot state.
 *
 * @property scrollState The column's scroll state.
 */
@Stable
internal class ScrollQuickLinkSections(private val scrollState: ScrollState) : QuickLinkScroller {
    /** Section ID → (top, bottom) in content pixels. */
    private val frames = mutableStateMapOf<String, Pair<Int, Int>>()
    private var viewportTop by mutableFloatStateOf(0f)
    private var viewportHeight by mutableIntStateOf(0)

    /** Section IDs in page order (item index = position here). */
    internal var ids: List<String> = emptyList()

    /**
     * Mark the scroll container (the element carrying `verticalScroll`).
     *
     * @return Modifier recording the viewport's window position and height.
     */
    fun Modifier.viewport(): Modifier = onGloballyPositioned {
        viewportTop = it.positionInRoot().y
        viewportHeight = it.size.height
    }

    /**
     * Mark one section.
     *
     * @param id Quick Links section ID.
     * @return Modifier recording the section's content offset.
     */
    fun Modifier.section(id: String): Modifier = onGloballyPositioned {
        val top = (it.positionInRoot().y - viewportTop).roundToInt() + scrollState.value
        frames[id] = top to top + it.size.height
    }

    override val scrolling: Boolean get() = scrollState.isScrollInProgress
    override val canScrollForward: Boolean get() = scrollState.canScrollForward
    override val canScrollBackward: Boolean get() = scrollState.canScrollBackward

    override fun layout(): QuickLinkLayout {
        val scrolled = scrollState.value
        val items = ids.mapIndexedNotNull { index, id -> frames[id]?.let { (top, bottom) -> QuickLinkItem(index, top - scrolled, bottom - scrolled) } }
        return QuickLinkLayout(items, viewportHeight.toFloat())
    }

    override suspend fun scrollTo(index: Int, animate: Boolean, landingPx: Int) {
        val top = ids.getOrNull(index)?.let(frames::get)?.first ?: return
        val target = QuickLinks.scrollLandingTarget(top, landingPx, scrollState.maxValue)
        if (animate) scrollState.animateScrollTo(target) else scrollState.scrollTo(target)
    }
}

/**
 * Remember Quick Links for a `verticalScroll` column.
 *
 * @param scrollState The column's scroll state.
 * @param title Quick Links title.
 * @param sections Sections in order.
 * @return The controller and the section marker for the page's modifiers.
 */
@Composable
internal fun rememberScrollQuickLinks(scrollState: ScrollState, title: String, sections: List<QuickLinkSection>): Pair<QuickLinksController, ScrollQuickLinkSections> {
    val anchors = remember(scrollState) { ScrollQuickLinkSections(scrollState) }
    val ordered = QuickLinks.ordered(sections)
    anchors.ids = ordered.map { it.id }
    val controller = rememberQuickLinks(anchors, title, ordered) { id -> anchors.ids.indexOf(id).takeIf { it >= 0 } }
    return controller to anchors
}

// endregion
