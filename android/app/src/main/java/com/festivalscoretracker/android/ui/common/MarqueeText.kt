package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.MarqueeAnimationMode
import androidx.compose.foundation.MarqueeSpacing
import androidx.compose.foundation.basicMarquee
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Marquee

/**
 * Web `MarqueeText` timing (`components/common/MarqueeText.tsx` + `.module.css`): one scroll
 * cycle lasts 8 s whatever the text length, pauses ~5% at each end, and the two copies are
 * 28 px apart.
 */
object FestivalMarquee {
    /** Web `DEFAULT_CYCLE`. */
    const val CYCLE_MS = 8_000

    /** Web `DEFAULT_GAP` (CSS px ≈ dp). */
    const val GAP_DP = 28

    /** Keyframe pause at each end (5% of the cycle). */
    const val PAUSE_MS = CYCLE_MS / 20

    /**
     * Scroll speed that covers one text-plus-gap distance in the moving 90% of the cycle.
     *
     * @param textWidthDp Full text width.
     * @return Velocity in dp per second (at least 1).
     */
    fun velocityDp(textWidthDp: Float): Float = ((textWidthDp + GAP_DP) / ((CYCLE_MS - 2 * PAUSE_MS) / 1_000f)).coerceAtLeast(1f)
}

/**
 * Single-line text that scrolls like the web's `MarqueeText` when it overflows and stays still
 * when it fits. Under Remove animations / Reduce Motion it truncates with an ellipsis instead.
 * `basicMarquee` animates in the draw phase, so scrolling never recomposes the row.
 *
 * @param text Text.
 * @param modifier Modifier (width constraints decide whether it overflows).
 * @param style Text style.
 * @param color Text color.
 * @param fontWeight Optional weight override.
 */
@Composable
fun FestivalMarqueeText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    color: Color = Color.Unspecified,
    fontWeight: FontWeight? = null,
) {
    if (LocalFestivalAccessibility.current.reduceMotion) {
        Text(text, modifier, color = color, style = style, fontWeight = fontWeight, maxLines = 1, overflow = TextOverflow.Ellipsis)
        return
    }
    val density = LocalDensity.current
    var widthPx by remember(text) { mutableIntStateOf(0) }
    val velocity = with(density) { FestivalMarquee.velocityDp(widthPx.toDp().value) }
    Text(
        text,
        modifier.basicMarquee(
            iterations = Int.MAX_VALUE,
            animationMode = MarqueeAnimationMode.Immediately,
            repeatDelayMillis = 2 * FestivalMarquee.PAUSE_MS,
            initialDelayMillis = FestivalMarquee.PAUSE_MS,
            spacing = MarqueeSpacing(FestivalMarquee.GAP_DP.dp),
            velocity = velocity.dp,
        ),
        color = color,
        style = style,
        fontWeight = fontWeight,
        maxLines = 1,
        overflow = TextOverflow.Clip,
        onTextLayout = { widthPx = it.size.width },
    )
}

// endregion
