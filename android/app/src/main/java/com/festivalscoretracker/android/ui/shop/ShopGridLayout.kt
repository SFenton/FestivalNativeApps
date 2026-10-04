package com.festivalscoretracker.android.ui.shop

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// region Card text

/**
 * Height caps for a grid card's title and artist. Large text wraps inside the fixed
 * square tile, so without caps a long title pushes the artist past the tile's bottom
 * edge. The title gets about two thirds of the room and the artist the rest, each at
 * least one line; both then end in an ellipsis instead of clipping.
 *
 * @param tile Tile height.
 * @param titleLine One title line.
 * @param artistLine One artist line.
 * @param badge Whether a large-text Leaving Tomorrow pill takes the tile's top.
 * @return Title and artist maximum heights.
 */
internal fun shopCardTextHeights(tile: Dp, titleLine: Dp, artistLine: Dp, badge: Boolean): Pair<Dp, Dp> {
    // Scrim padding (10 dp top and bottom) and the 2 dp gap; at 2x the pill is two ~34 dp lines plus its 10 dp inset.
    val room = tile - 22.dp - if (badge) SHOP_BADGE_LARGE_RESERVE_DP.dp else 0.dp
    val artist = maxOf(room / 3, artistLine)
    val title = maxOf(room - artist, titleLine)
    return title to artist
}

/** Room a large-text, two-line Leaving Tomorrow pill takes at a grid tile's top, with its inset. */
internal const val SHOP_BADGE_LARGE_RESERVE_DP = 80f

/** Smallest size a large-text pill word shrinks to so it fits a tile without breaking. */
internal const val SHOP_BADGE_MIN_SP = 8f

// endregion

// region Badge text

/**
 * Pill text. With [wordPerLine] each word gets its own line, so a narrow tile at large
 * text never breaks a word mid-way; the label shrinks instead.
 *
 * @param label Badge label ("Leaving Tomorrow").
 * @param wordPerLine Whether to put one word on each line.
 * @return Text to draw.
 */
internal fun shopBadgeText(label: String, wordPerLine: Boolean): String =
    if (wordPerLine) label.trim().split(Regex("\\s+")).joinToString("\n") else label

// endregion
