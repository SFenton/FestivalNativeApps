package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.design.readingGroup
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import com.festivalscoretracker.android.ui.common.rememberMeasuredPx

// region Hinge

/**
 * A vertical separating hinge expressed relative to a composable's own left edge.
 *
 * @property start Hinge leading edge in dp from the container's left.
 * @property end Hinge trailing edge in dp from the container's left.
 */
@Immutable
data class HingeSplit(val start: Dp, val end: Dp)

/**
 * Track where a vertical **separating** hinge (half-open book fold, or any fold
 * WindowManager reports as separating) crosses a container, from Jetpack
 * WindowManager's posture — never device names or pixel heuristics.
 *
 * @return The split (null when no such hinge crosses the container) and the
 *   modifier that must be applied to the container to measure it.
 */
@Composable
fun rememberHingeSplit(): Pair<HingeSplit?, Modifier> {
    val density = LocalDensity.current
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    var left by rememberMeasuredPx(Float.NaN)
    var width by rememberMeasuredPx(0f)
    val modifier = Modifier.onGloballyPositioned {
        left = it.positionInWindow().x
        width = it.size.width.toFloat()
    }
    // No split under TalkBack or at large text: one column, full width (rememberSingleColumn).
    val singleColumn = rememberSingleColumn()
    if (hinge == null || left.isNaN() || singleColumn) return null to modifier
    val start = hinge.bounds.left - left
    val end = hinge.bounds.right - left
    if (start <= 0f || end >= width) return null to modifier
    val split = with(density) { HingeSplit(start.toDp(), end.toDp()) }
    return split to modifier
}

// endregion

// region Card grid row

/**
 * One row of the overview's card grid. Around a hinge the two cards sit on either
 * side of the fold with [gap] clearance; otherwise cards share the width equally.
 * Rows are as tall as their content (top-aligned), so a spotlight or failure in one
 * card never clips its neighbour.
 *
 * @param cards Cards in this row (at most `columns`).
 * @param columns Columns in the grid.
 * @param hinge Hinge split relative to the row's left edge, or null.
 * @param gap Gap between cards.
 */
@Composable
fun CardGridRow(cards: List<@Composable () -> Unit>, columns: Int, hinge: HingeSplit?, gap: Dp = 16.dp) {
    if (hinge != null && columns == 2) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Box(Modifier.width((hinge.start - gap / 2).coerceAtLeast(0.dp)).readingGroup()) { cards.getOrNull(0)?.invoke() }
            Spacer(Modifier.width(hinge.end - hinge.start + gap))
            Box(Modifier.weight(1f).readingGroup()) { cards.getOrNull(1)?.invoke() }
        }
        return
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.Top) {
        repeat(columns) { index ->
            Box(Modifier.weight(1f).readingGroup()) { cards.getOrNull(index)?.invoke() }
        }
    }
}

// endregion
