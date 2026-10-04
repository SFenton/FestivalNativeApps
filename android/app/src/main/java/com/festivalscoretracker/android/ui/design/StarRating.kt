package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.R
import com.festivalscoretracker.android.core.format.StarRatingSpec
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Stars

/** Visual treatment, matching the two web components. */
enum class StarRatingStyle {
    /** Plain star images in a tight row, 2 dp apart (web `GoldStars` and inline rows). */
    Inline,

    /**
     * Web `MiniStars` (score metadata): each star centred in a circle 1.2× its edge,
     * 3 dp apart, with a 1.5 dp gold outline when the row is gold.
     */
    Mini,
}

/**
 * Star count with the web's star images (`public/star_white.png`, `star_gold.png`):
 * 1–5 white stars (at least one, web `MiniStars`), or five gold stars for a gold
 * (6-star) result. One image-role accessibility element ("4 stars", "5 gold stars").
 * Hosts that mean "no stars" must not compose it: 0 draws one white star, like the web.
 *
 * @param stars Service stars, 0–6.
 * @param modifier Modifier.
 * @param size Star image edge.
 * @param gold Force the gold treatment (a perfect average of six).
 * @param style [StarRatingStyle.Inline] or the web `MiniStars` circles.
 */
@Composable
fun StarRating(
    stars: Int,
    modifier: Modifier = Modifier,
    size: Dp = 16.dp,
    gold: Boolean = false,
    style: StarRatingStyle = StarRatingStyle.Inline,
) {
    val display = StarRatingSpec.display(stars, gold)
    val painter = bundledPainter(if (display.gold) R.drawable.star_gold else R.drawable.star_white)
    val mini = style == StarRatingStyle.Mini
    Row(
        modifier.clearAndSetSemantics {
            contentDescription = display.label
            role = Role.Image
        },
        horizontalArrangement = Arrangement.spacedBy(if (mini) 3.dp else 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(display.count) {
            if (mini) {
                val circle = size * 1.2f
                val ring = if (display.gold) Modifier.border(1.5.dp, BrandTokens.gold, CircleShape) else Modifier
                Box(Modifier.size(circle).clip(CircleShape).then(ring), contentAlignment = Alignment.Center) {
                    Image(painter, contentDescription = null, modifier = Modifier.size(size))
                }
            } else {
                Image(painter, contentDescription = null, modifier = Modifier.size(size))
            }
        }
    }
}

/**
 * TalkBack text for a star count, as the star row speaks it.
 *
 * @param stars Service stars, 0–6.
 * @return "1 star", "N stars" or "5 gold stars".
 */
fun starsDescription(stars: Int): String = StarRatingSpec.display(stars).label

// endregion
