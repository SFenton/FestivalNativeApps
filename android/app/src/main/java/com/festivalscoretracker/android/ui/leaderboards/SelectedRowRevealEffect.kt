package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Stable
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onPlaced
import com.festivalscoretracker.android.core.rankings.SelectedRowReveal
import com.festivalscoretracker.android.ui.common.FADE_IN_MILLIS
import com.festivalscoretracker.android.ui.common.FadeInWindow

// region Selected-row reveal

/**
 * Where the selected row sits inside its lazy item, for boards whose rows share one item
 * (the solo song board's rows card). Attach [item] to the item's root and [row] to the
 * selected row, outside any fade-in transform, so the measured position is the settled one.
 */
@Stable
internal class SelectedRowAnchor {
    private var itemCoordinates: LayoutCoordinates? = null
    private var rowCoordinates: LayoutCoordinates? = null

    /** Records the lazy item's root. */
    val item: Modifier = Modifier.onPlaced { itemCoordinates = it }

    /** Records the selected row. */
    val row: Modifier = Modifier.onPlaced { rowCoordinates = it }

    /**
     * The selected row's top inside its item and its height.
     *
     * @return `(top, height)` in px, or null before both are laid out.
     */
    fun bounds(): Pair<Int, Int>? {
        val item = itemCoordinates?.takeIf { it.isAttached } ?: return null
        val row = rowCoordinates?.takeIf { it.isAttached } ?: return null
        return item.localPositionOf(row, Offset.Zero).y.toInt() to row.size.height
    }
}

/**
 * Bring the selected row into view centred in the part of the list above the pinned footer
 * and pager (web `scrollIntoView({ block: 'center' })` after `navToPlayer` / `navToBand`;
 * `leaderboard-row` R7, issue #307): animated, or instant under Reduce Motion.
 *
 * @param itemKey Key of the lazy item holding the row.
 * @param itemIndex Index to scroll to first when that item isn't composed, or null to give up.
 * @param rowTop Row top inside the item (px); 0 when the row is the item.
 * @param rowHeight Row height (px), or null for the whole item.
 * @param animate Animate the scroll (false under Reduce Motion).
 * @return True when the row was found and scrolled to.
 */
internal suspend fun LazyListState.revealSelectedRow(itemKey: Any, itemIndex: Int?, rowTop: Int = 0, rowHeight: Int? = null, animate: Boolean): Boolean {
    if (layoutInfo.visibleItemsInfo.none { it.key == itemKey }) {
        if (itemIndex == null) return false
        scrollToItem(itemIndex)
        withFrameNanos { }
    }
    val info = layoutInfo
    val item = info.visibleItemsInfo.firstOrNull { it.key == itemKey } ?: return false
    val delta = SelectedRowReveal.centerDelta(
        rowTop = item.offset + rowTop,
        rowHeight = rowHeight ?: item.size,
        visibleStart = info.viewportStartOffset,
        visibleEnd = info.viewportEndOffset - info.afterContentPadding,
    )
    if (delta != 0f) {
        if (animate) animateScrollBy(delta) else scrollBy(delta)
    }
    return true
}

/**
 * Wait for the selected row's own entrance before revealing it (web `navToPlayer` /
 * `navToBand`; load-transition R5, issue #323), then rush the page's remaining fades so the
 * rows the reveal's scroll reaches fade in together instead of popping in.
 *
 * @param window The page's fade window, if any.
 * @param rowDelayMillis The selected row's stagger delay.
 * @param reduceMotion Remove animations / Reduce Motion (no wait).
 * @return False when the reader scrolled during the wait (the reveal then leaves the list
 *   where they put it, like the web's `userScrolledRef`).
 */
internal suspend fun awaitSelectedRowEntrance(window: FadeInWindow?, rowDelayMillis: Int, reduceMotion: Boolean): Boolean {
    val scrolls = window?.userScrolls
    awaitFrameMillis(SelectedRowReveal.entranceWaitMillis(rowDelayMillis, FADE_IN_MILLIS, reduceMotion))
    if (window != null && window.userScrolls != scrolls) return false
    window?.rush()
    return true
}

/**
 * Suspend for [millis] on the frame clock (so tests' paused clocks drive it).
 *
 * @param millis Milliseconds; nothing to wait for at 0.
 */
internal suspend fun awaitFrameMillis(millis: Int) {
    if (millis <= 0) return
    val start = withFrameNanos { it }
    while (withFrameNanos { it } - start < millis * 1_000_000L) Unit
}

// endregion
