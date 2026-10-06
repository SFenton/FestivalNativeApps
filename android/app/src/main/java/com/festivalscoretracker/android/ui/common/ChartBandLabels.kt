package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.ChartGeometry
import kotlin.math.roundToInt

// region Chart band labels

/** Minimum space between two shown band labels. */
private val BAND_LABEL_GAP = 8.dp

/**
 * The date row under a bar chart: one label per bar, each centred under its band
 * ([ChartGeometry.bandLabelLefts]); labels that would collide hide, keeping the newest.
 * The bands span the row minus [plotInset] on each side (the y-axis gutters). The row is as
 * tall as its tallest label, so it grows with the text size and never clips a date. The dates
 * are decorative: TalkBack reads them from the chart's own description.
 *
 * @param labels One label per visible bar, left to right.
 * @param plotInset Gutter on each side of the plot.
 * @param style Label style.
 * @param color Label colour.
 * @param modifier Modifier.
 */
@Composable
fun ChartBandLabels(labels: List<String>, plotInset: Dp, style: TextStyle, color: Color, modifier: Modifier = Modifier) {
    Layout(
        content = { labels.forEach { Text(it, style = style, color = color, maxLines = 1, softWrap = false) } },
        modifier = modifier.fillMaxWidth().clearAndSetSemantics { },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val placeables = measurables.map { it.measure(Constraints(maxWidth = width)) }
        val inset = plotInset.toPx()
        val lefts = ChartGeometry.bandLabelLefts(
            placeables.map { it.width.toFloat() },
            plotLeft = inset,
            plotWidth = (width - 2 * inset).coerceAtLeast(0f),
            totalWidth = width.toFloat(),
            gap = BAND_LABEL_GAP.toPx(),
        )
        layout(width, placeables.maxOfOrNull { it.height } ?: 0) {
            placeables.forEachIndexed { i, placeable -> lefts[i]?.let { placeable.place(it.roundToInt(), 0) } }
        }
    }
}

// endregion
