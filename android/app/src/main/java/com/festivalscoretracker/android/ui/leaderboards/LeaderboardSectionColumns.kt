package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.HistoryColumnPlan
import com.festivalscoretracker.android.core.rankings.HistoryColumnTexts
import com.festivalscoretracker.android.core.rankings.HistoryRowLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.core.rankings.LeaderboardRowKind
import com.festivalscoretracker.android.core.rankings.LeaderboardSection
import com.festivalscoretracker.android.core.rankings.ScoreSectionTexts
import com.festivalscoretracker.android.ui.design.METADATA_PILL_PADDING_H
import com.festivalscoretracker.android.ui.design.SEASON_PILL_MIN_WIDTH

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
 * @param minRankWidth Rank column the section's other rows already use (the band board's
 *   member cards, `leaderboard-row` R1), so a pinned row drawn here keeps their column.
 * @return Shared columns.
 */
@Composable
fun rememberScoreColumns(entries: List<LeaderboardEntry>, minRankWidth: Dp = 0.dp): LeaderboardSectionColumns {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    val widths = remember { LeaderboardSectionWidths() }
    val section = remember(entries, density, typography, minRankWidth) {
        val texts = ScoreSectionTexts.of(entries)
        fun widest(list: List<String>, style: TextStyle): Float = with(density) {
            val px = list.maxOfOrNull { measurer.measure(it, style.copy(fontWeight = FontWeight.Bold), maxLines = 1).size.width } ?: return@with 0f
            (px.toDp() + TEXT_SLACK).value
        }
        LeaderboardSection(
            kind = LeaderboardRowKind.Score,
            rankWidth = maxOf(widest(texts.ranks, typography.labelLarge), minRankWidth.value),
            // The season column holds the shared [SeasonPill]: its label plus padding, never below the pill's minimum.
            metaWidth = widest(texts.seasons, typography.labelLarge).let { if (it == 0f) 0f else maxOf(it + 2 * METADATA_PILL_PADDING_H.value, SEASON_PILL_MIN_WIDTH.value) },
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

// region History columns

/** OpenType tabular figures (web `fontVariantNumeric: tabular-nums`), so equal-length numbers line up digit by digit. */
private const val TABULAR_FIGURES = "tnum"

/**
 * One text of a rank-history row.
 *
 * @property text Label.
 * @property color Colour.
 * @property weight Weight (the newest row is bold, web `i === 0`).
 */
@Immutable
data class HistoryCell(val text: String, val color: Color, val weight: FontWeight)

/**
 * Measures a rank-history list's shared columns once (`leaderboard-row` R1, issue #594; web
 * `computeRankWidth` and the value `ch` width over every chart point): the widest date, rank
 * and value of [texts] in bold with tabular figures, at the current font scale.
 *
 * @param texts Every chart day's labels, not only the listed rows.
 * @param style Text style the rows draw with.
 * @param gap Space between columns.
 * @return Column plan for [HistoryColumnsRow].
 */
@Composable
fun rememberHistoryColumns(texts: HistoryColumnTexts, style: TextStyle, gap: Dp): HistoryColumnPlan {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    return remember(texts, style, gap, density) {
        val bold = style.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR_FIGURES)
        fun widest(list: List<String>): Float = with(density) {
            val px = list.distinct().maxOfOrNull { measurer.measure(it, bold, maxLines = 1, softWrap = false).size.width } ?: return@with 0f
            (px.toDp() + TEXT_SLACK).value
        }
        HistoryColumnPlan(widest(texts.dates), widest(texts.ranks), widest(texts.values), gap.value)
    }
}

/**
 * One rank-history row's date, rank and value on the list's shared columns
 * ([rememberHistoryColumns]): the date takes the rest of the row, the rank and value are
 * right-aligned at fixed widths with tabular figures, so every row (bold newest included) and
 * the tapped bar's detail line up. When large text leaves no room for the widest date beside
 * the columns, the date moves above them and the row grows (`leaderboard-row` R2); when even the
 * two columns don't fit on one line, each takes its own line at its same measured width,
 * right-aligned, so the columns still line up and never clip. Every row is at least
 * [LEADERBOARD_ROW_MIN_HEIGHT] (48 dp, web `Layout.entryRowHeight`) tall, padding included.
 * Semantics belong to the caller's row (one TalkBack stop).
 *
 * @param plan Shared columns.
 * @param date Date.
 * @param rank Rank.
 * @param value Value.
 * @param style Text style ([rememberHistoryColumns] was measured with it).
 * @param modifier Modifier (padding, background, semantics); drawn inside the 48 dp minimum.
 * @param probeKey Key the row, rank and value report to [LocalColumnProbe] (`history.row|rank|value.<key>`).
 */
@Composable
fun HistoryColumnsRow(
    plan: HistoryColumnPlan,
    date: HistoryCell,
    rank: HistoryCell,
    value: HistoryCell,
    style: TextStyle,
    modifier: Modifier = Modifier,
    probeKey: String? = null,
) {
    val probe = LocalColumnProbe.current
    val tabular = style.copy(fontFeatureSettings = TABULAR_FIGURES)
    val gap = plan.gap.dp
    val rankKey = probeKey?.let { "history.rank.$it" }
    val valueKey = probeKey?.let { "history.value.$it" }
    val outer = (if (probeKey == null) Modifier else Modifier.columnProbe(probe, "history.row.$probeKey"))
        .heightIn(min = LEADERBOARD_ROW_MIN_HEIGHT)
    BoxWithConstraints(outer.then(modifier), contentAlignment = Alignment.CenterStart) {
        val row = maxWidth.value
        when (plan.layoutFor(row)) {
            HistoryRowLayout.Line -> Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(gap)) {
                HistoryDate(date, style, Modifier.weight(1f))
                HistoryColumn(rank, tabular, plan.rankWidth, wrap = false, probe, rankKey)
                HistoryColumn(value, tabular, plan.valueWidth, wrap = false, probe, valueKey)
            }
            HistoryRowLayout.DateAbove -> Column(Modifier.fillMaxWidth()) {
                HistoryDate(date, style, Modifier)
                Row(Modifier.align(Alignment.End), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(gap)) {
                    HistoryColumn(rank, tabular, plan.rankWidth, wrap = false, probe, rankKey)
                    HistoryColumn(value, tabular, plan.valueWidth, wrap = false, probe, valueKey)
                }
            }
            HistoryRowLayout.Lines -> Column(Modifier.fillMaxWidth()) {
                HistoryDate(date, style, Modifier)
                HistoryColumn(rank, tabular, plan.columnWidth(plan.rankWidth, row), wrap = plan.rankWidth > row, probe, rankKey, Modifier.align(Alignment.End))
                HistoryColumn(value, tabular, plan.columnWidth(plan.valueWidth, row), wrap = plan.valueWidth > row, probe, valueKey, Modifier.align(Alignment.End))
            }
        }
    }
}

@Composable
private fun HistoryDate(cell: HistoryCell, style: TextStyle, modifier: Modifier) =
    Text(cell.text, style = style, color = cell.color, fontWeight = cell.weight, modifier = modifier)

/**
 * A right-aligned rank or value column at its measured width.
 *
 * @param width Width in dp.
 * @param wrap Whether the text may wrap (only when the column is capped at a narrower row).
 */
@Composable
private fun HistoryColumn(cell: HistoryCell, style: TextStyle, width: Float, wrap: Boolean, probe: ColumnProbe?, key: String?, modifier: Modifier = Modifier) = Text(
    cell.text,
    style = style,
    color = cell.color,
    fontWeight = cell.weight,
    textAlign = TextAlign.End,
    maxLines = if (wrap) Int.MAX_VALUE else 1,
    softWrap = wrap,
    modifier = modifier.width(width.dp).then(if (key == null) Modifier else Modifier.columnProbe(probe, key)),
)

// endregion

// region Column probe

/**
 * Test hook recording where rows draw their rank and name columns, so UI tests can check
 * that a section's rows and its pinned row share them (`leaderboard-row` R1). Row semantics
 * are merged or cleared for TalkBack, so the columns have no nodes of their own.
 */
internal fun interface ColumnProbe {
    /**
     * Records a column's bounds.
     *
     * @param key `<row kind>.<column>.<rank>`, e.g. `band.rank.12` or `score.name.9968`.
     * @param bounds Unclipped bounds in the root, px (a row under the pinned footer still reports its columns).
     */
    fun record(key: String, bounds: Rect)
}

/** The active [ColumnProbe]; null (no cost) outside tests. */
internal val LocalColumnProbe = staticCompositionLocalOf<ColumnProbe?> { null }

/**
 * Reports this column's bounds to [probe] when one is installed.
 *
 * @param probe [LocalColumnProbe] value.
 * @param key Probe key.
 * @return Modifier.
 */
internal fun Modifier.columnProbe(probe: ColumnProbe?, key: String): Modifier =
    if (probe == null) this else onGloballyPositioned { probe.record(key, Rect(it.positionInRoot(), it.size.toSize())) }

// endregion
