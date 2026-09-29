package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.R

// region Stars

/**
 * Star count with the web's star images (`public/star_white.png`, `star_gold.png`;
 * web `GoldStars`): 1–5 white stars, or five gold stars for a gold (6-star) result.
 * One accessibility element ("5 stars", "Gold stars").
 *
 * @param stars Stars, 0–6 (0 draws nothing).
 * @param modifier Modifier.
 * @param size Star size.
 */
@Composable
fun StarRating(stars: Int, modifier: Modifier = Modifier, size: Dp = 16.dp) {
    if (stars <= 0) return
    val gold = stars >= 6
    val count = if (gold) 5 else stars.coerceAtMost(5)
    val painter = bundledPainter(if (gold) R.drawable.star_gold else R.drawable.star_white)
    Row(
        modifier.clearAndSetSemantics { contentDescription = starsDescription(stars) },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { Image(painter, contentDescription = null, modifier = Modifier.size(size)) }
    }
}

/**
 * TalkBack text for a star count.
 *
 * @param stars Stars, 0–6.
 * @return "Gold stars", "1 star" or "N stars".
 */
fun starsDescription(stars: Int): String = when {
    stars >= 6 -> "Gold stars"
    stars == 1 -> "1 star"
    else -> "$stars stars"
}

// endregion
