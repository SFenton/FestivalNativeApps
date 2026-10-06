package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Metrics

/**
 * Metrics and the fit rule of the canonical read-only Settings value row (pattern
 * `settings-value-row`, `.agents/patterns/settings-value-row.md`).
 */
internal object SettingsValueRowMetrics {
    /** Gap between the title column and the trailing value when they share a line. */
    val INLINE_GAP: Dp = 12.dp

    /** Gap between the title, its supporting line and the stacked value. */
    val LINE_GAP: Dp = 4.dp

    /** Minimum height of a one-line row (title only). */
    val MIN_HEIGHT: Dp = 48.dp

    /** Minimum height of a row with a supporting line under the title. */
    val MIN_HEIGHT_WITH_SUPPORTING: Dp = 56.dp

    /**
     * Whether the trailing value stays on the title's line (R1): the title and the value fit side
     * by side at their natural one-line widths with [INLINE_GAP] between them. Supporting text
     * never counts, since it wraps under the title.
     *
     * @param titleWidth Title's natural one-line width, in px.
     * @param trailingWidth Trailing value's natural width, in px.
     * @param gap Inline gap, in px.
     * @param available Row content width, in px.
     * @return `true` to lay out inline, `false` to stack the value under the text.
     */
    fun fitsInline(titleWidth: Int, trailingWidth: Int, gap: Int, available: Int): Boolean =
        titleWidth + gap + trailingWidth <= available
}

// endregion

// region Row

/**
 * The one read-only Settings "title … value" row (pattern `settings-value-row`): Version rows
 * and the Service Info state row. The trailing value sits at the end of the title's line when
 * both fit at their natural widths ([SettingsValueRowMetrics.fitsInline]); otherwise (large
 * text, narrow panes and covers, a long service origin) it stacks under the title and its
 * supporting line, so the title is never squeezed into a narrow column (issues #121, #184).
 * The row is one merged, non-interactive TalkBack item read title → supporting → value.
 *
 * @param title Row label (Body Large, primary text).
 * @param tag Test tag of the merged row; the value slot is tagged `<tag>.value`.
 * @param supporting Optional supporting line under the title (Body Medium, secondary text).
 * @param trailing Trailing value content.
 */
@Composable
internal fun SettingsValueRow(
    title: String,
    tag: String,
    supporting: String? = null,
    trailing: @Composable () -> Unit,
) {
    val minHeight = if (supporting == null) SettingsValueRowMetrics.MIN_HEIGHT else SettingsValueRowMetrics.MIN_HEIGHT_WITH_SUPPORTING
    Layout(
        content = {
            Text(title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
            supporting?.let { Text(it, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium) }
            Box(Modifier.testTag("$tag.value")) { trailing() }
        },
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag(tag)
            .semantics(mergeDescendants = true) {},
    ) { measurables, constraints ->
        val titleText = measurables.first()
        val supportingText = if (supporting != null) measurables[1] else null
        val value = measurables.last()
        val width = constraints.maxWidth
        val gap = SettingsValueRowMetrics.INLINE_GAP.roundToPx()
        val lineGap = SettingsValueRowMetrics.LINE_GAP.roundToPx()
        val valueWidth = value.maxIntrinsicWidth(Constraints.Infinity)
        val inline = SettingsValueRowMetrics.fitsInline(titleText.maxIntrinsicWidth(Constraints.Infinity), valueWidth, gap, width)
        val valuePlaceable = value.measure(Constraints(maxWidth = if (inline) minOf(valueWidth, width) else width))
        val textWidth = if (inline) width - gap - valuePlaceable.width else width
        val titlePlaceable = titleText.measure(Constraints(maxWidth = textWidth))
        val supportingPlaceable = supportingText?.measure(Constraints(maxWidth = textWidth))
        val textHeight = titlePlaceable.height + (supportingPlaceable?.let { lineGap + it.height } ?: 0)
        if (inline) {
            val height = maxOf(constraints.minHeight, textHeight, valuePlaceable.height)
            layout(width, height) {
                val top = (height - textHeight) / 2
                titlePlaceable.placeRelative(0, top)
                supportingPlaceable?.placeRelative(0, top + titlePlaceable.height + lineGap)
                valuePlaceable.placeRelative(width - valuePlaceable.width, (height - valuePlaceable.height) / 2)
            }
        } else {
            val valueTop = textHeight + lineGap
            val height = maxOf(constraints.minHeight, valueTop + valuePlaceable.height)
            layout(width, height) {
                titlePlaceable.placeRelative(0, 0)
                supportingPlaceable?.placeRelative(0, titlePlaceable.height + lineGap)
                valuePlaceable.placeRelative(0, valueTop)
            }
        }
    }
}

/**
 * A [SettingsValueRow] whose value is plain secondary text (Version rows).
 *
 * @param title Row label.
 * @param value Trailing value.
 * @param tag Test tag of the merged row.
 */
@Composable
internal fun SettingsValueRow(title: String, value: String, tag: String) {
    SettingsValueRow(title, tag) { Text(value, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyLarge) }
}

// endregion
