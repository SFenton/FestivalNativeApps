package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.core.rankings.LeaderboardRowKind
import com.festivalscoretracker.android.core.rankings.LeaderboardSection
import com.festivalscoretracker.android.core.rankings.ScoreSectionTexts

// region Section columns

/**
 * Widths of the places one section's rows are drawn (its card and, on song boards, the
 * pinned footer). The section fits its columns to the narrowest, so every member shows the
 * same columns at the same widths (issue #37).
 */
@Stable
class LeaderboardSectionWidths {
    private val widths = mutableStateMapOf<String, Float>()

    /** Narrowest member width in dp, or NaN before the first layout. */
    val width: Float get() = widths.values.minOrNull() ?: Float.NaN

    /**
     * Records a member's width.
     *
     * @param key Member key.
     * @param width Width in dp.
     */
    fun report(key: String, width: Float) {
        if (widths[key] != width) widths[key] = width
    }

    /**
     * Drops a member that left the composition.
     *
     * @param key Member key.
     */
    fun forget(key: String) {
        widths.remove(key)
    }
}

/**
 * One section's shared columns: the [LeaderboardColumnLayout] plan every row draws with,
 * and the member widths it was fitted to.
 *
 * @property plan Columns and widths for every row.
 * @property widths Member widths.
 */
@Stable
class LeaderboardSectionColumns(val plan: LeaderboardColumnPlan, val widths: LeaderboardSectionWidths)

/**
 * Measures a score section once — every row plus the pinned selected-player row, bold as
 * the selected row draws them — and fits it to the section's narrowest member (web
 * `computeRankWidth`, the score `ch` width and `topScoresLayout`; issue #37).
 *
 * @param entries Section rows, including the pinned row.
 * @return Shared columns.
 */
@Composable
fun rememberScoreColumns(entries: List<LeaderboardEntry>): LeaderboardSectionColumns {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    val widths = remember { LeaderboardSectionWidths() }
    val section = remember(entries, density, typography) {
        val texts = ScoreSectionTexts.of(entries)
        fun widest(list: List<String>, style: TextStyle): Float = with(density) {
            val px = list.maxOfOrNull { measurer.measure(it, style.copy(fontWeight = FontWeight.Bold), maxLines = 1).size.width } ?: return@with 0f
            (px.toDp() + TEXT_SLACK).value
        }
        LeaderboardSection(
            kind = LeaderboardRowKind.Score,
            rankWidth = widest(texts.ranks, typography.labelLarge),
            metaWidth = widest(texts.seasons, typography.labelLarge),
            valueWidth = widest(texts.scores, typography.bodyMedium),
            hasAccuracy = texts.hasAccuracy,
            hasStars = texts.hasStars,
        )
    }
    val width = widths.width
    val plan = remember(section, width, density.fontScale) { LeaderboardColumnLayout.fit(section, width, density.fontScale) }
    return remember(plan, widths) { LeaderboardSectionColumns(plan, widths) }
}

/**
 * A place a section's rows are drawn (its card, or the pinned footer): reports its width
 * so the whole section fits to the narrowest one.
 *
 * @param columns Section columns.
 * @param key Member key, unique within the section.
 * @param modifier Modifier.
 * @param content Rows.
 */
@Composable
fun LeaderboardSectionMember(columns: LeaderboardSectionColumns, key: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val density = LocalDensity.current
    val widths = columns.widths
    DisposableEffect(widths, key) { onDispose { widths.forget(key) } }
    Column(modifier.onSizeChanged { widths.report(key, with(density) { it.width.toDp().value }) }, content = content)
}

/** Room added to measured text so a column equal to its widest text never wraps on rounding. */
internal val TEXT_SLACK = 2.dp

// endregion
