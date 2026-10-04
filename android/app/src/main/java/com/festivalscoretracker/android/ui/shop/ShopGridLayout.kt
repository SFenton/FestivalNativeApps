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
    // Scrim padding (10 dp top and bottom) and the 2 dp gap; the pill is ~36 dp at 2x plus its 10 dp inset.
    val room = tile - 22.dp - if (badge) 56.dp else 0.dp
    val artist = maxOf(room / 3, artistLine)
    val title = maxOf(room - artist, titleLine)
    return title to artist
}

// endregion
