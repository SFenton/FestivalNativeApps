package com.festivalscoretracker.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

// region Difficulty geometry

/** Seven ascending bar heights inside a 62 × 20 branded-content frame. */
object DifficultyGeometry {
    const val width = 62f
    const val height = 20f
    const val barWidth = 6f
    const val gap = (width - 7 * barWidth) / 6f
    val heights = listOf(5f, 7.5f, 10f, 12.5f, 15f, 17.5f, 20f)

    /** Returns the top-left and size for [index], where 0 is the shortest bar. */
    fun bar(index: Int): Pair<Offset, Size> {
        require(index in 0..6)
        val barHeight = heights[index]
        return Offset(index * (barWidth + gap), height - barHeight) to Size(barWidth, barHeight)
    }
}

/** Draws [difficulty] active bars with one merged accessible label and a stable test ID. */
@Composable
fun DifficultyMeter(difficulty: Int, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.primary) {
    require(difficulty in 1..7)
    val inactiveColor = MaterialTheme.colorScheme.outline
    Canvas(
        modifier
            .size(DifficultyGeometry.width.dp, DifficultyGeometry.height.dp)
            .testTag("fst.songs.difficulty-meter")
            .semantics { contentDescription = "Difficulty $difficulty of 7" },
    ) {
        val scale = size.width / DifficultyGeometry.width
        repeat(7) { index ->
            val (offset, barSize) = DifficultyGeometry.bar(index)
            drawRect(
                color = if (index < difficulty) color else inactiveColor,
                topLeft = Offset(offset.x * scale, offset.y * scale),
                size = Size(barSize.width * scale, barSize.height * scale),
            )
        }
    }
}

// endregion
