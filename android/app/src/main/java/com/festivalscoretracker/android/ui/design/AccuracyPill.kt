package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Accuracy pill

/**
 * Web `AccuracyDisplay`: the accuracy percentage in a pill tinted red→green by accuracy, or
 * — for a full combo — the same percentage in the web's gold outline, skewed (italic),
 * never a separate "FC" chip (operator batch 7, 7.11). Sized for "XX.X%" (7.1).
 *
 * @param accuracy Accuracy in ten-thousandths of a percent (1,000,000 = 100%), or null.
 * @param isFullCombo Whether the score is a full combo.
 * @param modifier Modifier.
 */
@Composable
fun AccuracyPill(accuracy: Double?, isFullCombo: Boolean, modifier: Modifier = Modifier) {
    val value = accuracy?.takeIf { it > 0 } ?: 0.0
    val text = "${ScoreFormatting.accuracy(value)}%"
    val shape = RoundedCornerShape(6.dp)
    val tint = ScoreFormatting.accuracyTint(value)?.let { Color(0xFF000000 or it.toLong()) }
    val styled = if (isFullCombo) {
        modifier.clip(shape).border(BorderStroke(2.dp, BrandTokens.gold), shape)
    } else {
        modifier.clip(shape).background(tint?.copy(alpha = 0.8f) ?: BrandTokens.surfaceMuted)
    }
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = if (isFullCombo) FontWeight.Bold else FontWeight.SemiBold,
        fontStyle = if (isFullCombo) FontStyle.Italic else FontStyle.Normal,
        color = if (isFullCombo) BrandTokens.gold else BrandTokens.textPrimary,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = styled
            .widthIn(min = ACCURACY_PILL_MIN_DP.dp)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .clearAndSetSemantics { contentDescription = if (isFullCombo) "Full combo, $text" else "Accuracy $text" },
    )
}

/** Web `MetadataSize.accuracyPillMinWidth`: fits "100.0%" without growing. */
private const val ACCURACY_PILL_MIN_DP = 56

// endregion
