package com.festivalscoretracker.android.ui.common

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle

// region Large text

/**
 * Font scale from which dense one-line layouts reflow: rows stack their columns, one-line
 * names wrap instead of scrolling or truncating, and two-column tile grids drop to one
 * column. Android's "Large" font size is 1.15 and 200% is 2.0; 1.3 is the first step at
 * which the one-line leaderboard and Songs rows ran out of room on a 411 dp phone.
 */
const val LARGE_TEXT_SCALE = 1.3f

/**
 * Whether the user's font size calls for reflowed layouts ([LARGE_TEXT_SCALE] or larger).
 *
 * @return True at large font scales.
 */
@Composable
fun isLargeText(): Boolean = LocalDensity.current.fontScale >= LARGE_TEXT_SCALE

/**
 * `maxLines` for a primary one-line text (song title, artist, player name): one line, or
 * unlimited at large font scales so it wraps instead of ending in an ellipsis.
 *
 * @return 1, or [Int.MAX_VALUE] at [LARGE_TEXT_SCALE] and above.
 */
@Composable
fun oneLineUnlessLarge(): Int = if (isLargeText()) Int.MAX_VALUE else 1

/**
 * Tick-label style for chart axes that sit in a fixed-width gutter: `labelSmall` that does
 * not grow with the font scale (at 200% "100" clipped to "10"). The ticks are decorative:
 * TalkBack reads the chart's description, and the same values are listed at full size in
 * the rows under each chart.
 *
 * @return `labelSmall` at its 100% size.
 */
@Composable
fun chartAxisTextStyle(): TextStyle {
    val style = MaterialTheme.typography.labelSmall
    val scale = LocalDensity.current.fontScale
    return if (scale <= 1f) style else style.copy(fontSize = style.fontSize / scale, lineHeight = style.lineHeight / scale)
}

// endregion
