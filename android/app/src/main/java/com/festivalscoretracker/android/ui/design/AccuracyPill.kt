package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.format.ScoreAccuracyBadge
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlin.math.tan

// region Accuracy pill

/**
 * The score-accuracy control (web `AccuracyDisplay`, `.agents/controls/score-accuracy/android.md`):
 * the percentage in a pill tinted red→green at 25% opacity, or — for a full combo — the
 * percentage in the web's gold skewed outline, never a separate "FC" chip (operator batch
 * 7.11). A full combo without accuracy shows `FC` (never an invented `0%`), a non-finite
 * accuracy a neutral `—`, and no accuracy without a full combo draws nothing (the caller
 * keeps the column slot). Sized for "XX.X%" (7.1); at large font scales ([expanded]) the
 * full spoken label is shown and may wrap.
 *
 * @param accuracy Accuracy in ten-thousandths of a percent (1,000,000 = 100%), or null.
 * @param isFullCombo Whether the score is a full combo.
 * @param modifier Modifier.
 * @param id Row identity for the `fst.score.accuracy.<id>` test tag (account, band or row key).
 * @param expanded Show the full label ("Full combo, accuracy 98%") instead of the compact one.
 */
@Composable
fun AccuracyPill(accuracy: Double?, isFullCombo: Boolean, modifier: Modifier = Modifier, id: String? = null, expanded: Boolean = false) {
    val badge = ScoreAccuracyBadge.of(accuracy, isFullCombo) ?: return
    AccuracyBadge(badge, modifier, id, expanded)
}

/**
 * Draws one resolved [ScoreAccuracyBadge].
 *
 * @param badge Badge policy.
 * @param modifier Modifier.
 * @param id Row identity for the test tag.
 * @param expanded Show [ScoreAccuracyBadge.announcement] instead of [ScoreAccuracyBadge.text].
 */
@Composable
fun AccuracyBadge(badge: ScoreAccuracyBadge, modifier: Modifier = Modifier, id: String? = null, expanded: Boolean = false) {
    val shape = RoundedCornerShape(ACCURACY_PILL_RADIUS_DP.dp)
    val tagged = if (id != null) modifier.testTag("$ACCURACY_TAG_PREFIX$id") else modifier
    val surface = when (badge.kind) {
        ScoreAccuracyBadge.Kind.Graded -> {
            val tint = badge.tint?.let { Color(0xFF000000 or it.toLong()) } ?: BrandTokens.surfaceMuted
            tagged.clip(shape).background(tint.copy(alpha = ScoreAccuracyBadge.GRADED_TINT_ALPHA))
        }
        ScoreAccuracyBadge.Kind.Invalid -> tagged.clip(shape).background(BrandTokens.surfaceMuted)
        ScoreAccuracyBadge.Kind.FullCombo, ScoreAccuracyBadge.Kind.FullComboNoAccuracy -> tagged.goldOutline(skewed = !expanded)
    }
    Text(
        if (expanded) badge.announcement else badge.text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = if (badge.isGold) FontWeight.Bold else FontWeight.SemiBold,
        fontStyle = if (badge.isGold) FontStyle.Italic else FontStyle.Normal,
        color = if (badge.isGold) BrandTokens.gold else BrandTokens.textPrimary,
        textAlign = TextAlign.Center,
        maxLines = if (expanded) Int.MAX_VALUE else 1,
        modifier = surface
            .widthIn(min = ACCURACY_PILL_MIN_DP.dp)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .clearAndSetSemantics { contentDescription = badge.announcement },
    )
}

/**
 * Web `goldOutlineSkew`: a 2 dp `goldStroke` rounded outline sheared like CSS `skewX(-8deg)`
 * about the badge's vertical centre (top edge leaning right). The rectangle is inset by the
 * shear first, so the slanted outline stays inside the badge's bounds and column.
 *
 * @param skewed Apply the shear (off for the wrapping large-text label).
 * @return Modifier.
 */
private fun Modifier.goldOutline(skewed: Boolean): Modifier = drawBehind {
    val stroke = GOLD_STROKE_DP.dp.toPx()
    val shear = if (skewed) GOLD_SKEW_TAN else 0f
    val shift = shear * size.height / 2
    val matrix = Matrix().apply {
        values[Matrix.SkewX] = -shear
        values[Matrix.TranslateX] = shift
    }
    withTransform({ transform(matrix) }) {
        drawRoundRect(
            color = BrandTokens.goldStroke,
            topLeft = Offset(shift + stroke / 2, stroke / 2),
            size = Size((size.width - 2 * shift - stroke).coerceAtLeast(0f), (size.height - stroke).coerceAtLeast(0f)),
            cornerRadius = CornerRadius(ACCURACY_PILL_RADIUS_DP.dp.toPx()),
            style = Stroke(stroke),
        )
    }
}

/** Test-tag root of the control. */
const val ACCURACY_TAG_PREFIX = "fst.score.accuracy."

/** Web `MetadataSize.accuracyPillMinWidth`: fits "100.0%" without growing. */
private const val ACCURACY_PILL_MIN_DP = 56

/** Web `Radius.xs`. */
private const val ACCURACY_PILL_RADIUS_DP = 8

/** Web `Border.thick`. */
private const val GOLD_STROKE_DP = 2

/** `tan(8°)`, the web's `GOLD_SKEW`. */
private val GOLD_SKEW_TAN = tan(Math.toRadians(8.0)).toFloat()

// endregion
