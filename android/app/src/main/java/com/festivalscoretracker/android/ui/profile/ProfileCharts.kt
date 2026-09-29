package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.suggestions.PercentileTier
import com.festivalscoretracker.android.presentation.profile.PercentileRow
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.suggestions.PercentilePill
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.ChartGeometry
import com.festivalscoretracker.android.core.profile.ChartPoint
import com.festivalscoretracker.android.core.profile.ChartTick
import com.festivalscoretracker.android.core.profile.ScoreHistoryChartModel
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.chartAxisTextStyle

// region Percentiles

/**
 * The web's percentile table card (`PlayerPercentileHeader` + `PlayerPercentileRow`):
 * a "PERCENTILE | SONGS" header, then one row per non-empty band with a "Top N%" pill
 * and its song count, hairline separators between rows. A row with an action opens
 * Songs filtered to that band (web `instPercentileBucketUpdater`).
 *
 * @param rows Bands, best first.
 * @param canRun Whether a row's action is available now.
 * @param onAction Row tap.
 * @param modifier Modifier (carries the test tag).
 */
@Composable
internal fun PercentileTable(rows: List<PercentileRow>, canRun: (PlayerTileAction) -> Boolean, onAction: (PlayerTileAction) -> Unit, modifier: Modifier = Modifier) {
    GlassCard(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp).clearAndSetSemantics { }) {
            TableHeader("Percentile", Modifier.weight(1f))
            TableHeader("Songs")
        }
        rows.forEachIndexed { index, row ->
            HorizontalDivider(color = BrandTokens.glassBorder)
            val action = row.action?.takeIf(canRun)
            val content: @Composable () -> Unit = {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f)) { PercentilePill(row.bucket.label, percentileTier(row.bucket.topPercent)) }
                    Text(row.bucket.count.toString(), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
                    if (action != null) {
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = BrandTokens.textPrimary,
                            modifier = Modifier.padding(start = 8.dp).size(20.dp),
                        )
                    }
                }
            }
            val tag = Modifier.testTag("fst.player.percentile-row.${row.bucket.topPercent}")
            if (action == null) {
                Box(tag.clearAndSetSemantics { contentDescription = row.announcement }) { content() }
            } else {
                Surface(
                    onClick = { onAction(action) },
                    color = Color.Transparent,
                    modifier = tag.clearAndSetSemantics {
                        contentDescription = row.announcement
                        role = Role.Button
                        onClick(label = actionLabel(action)) { onAction(action); true }
                    },
                    content = content,
                )
            }
        }
    }
}

@Composable
private fun TableHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.6.sp,
        color = BrandTokens.textSecondary,
        modifier = modifier,
    )
}

/** Web `PercentilePill` tier for a band: gold italic at Top 1%, gold outline to Top 5%. */
internal fun percentileTier(topPercent: Int): PercentileTier = when {
    topPercent <= 1 -> PercentileTier.Top1
    topPercent <= 5 -> PercentileTier.Top5
    else -> PercentileTier.Default
}

// endregion

// region Score history

/**
 * Score-over-time line with the personal best in gold.
 *
 * @param chart Geometry.
 * @param modifier Modifier.
 */
@Composable
fun ScoreHistoryChart(chart: ScoreHistoryChartModel, modifier: Modifier = Modifier) {
    Column(modifier.testTag("fst.history.chart").semantics { contentDescription = "Score over time. ${chart.summary}" }) {
        Row(Modifier.fillMaxWidth()) {
            AxisLabels(chart.ticks, Modifier.width(72.dp).height(CHART_HEIGHT.dp))
            Canvas(Modifier.weight(1f).height(CHART_HEIGHT.dp)) {
                gridLines(chart.ticks)
                line(chart.points, BrandTokens.accentBlue, highlight = BrandTokens.gold)
            }
        }
        DateAxis(chart.startLabel, chart.endLabel)
    }
}

// endregion

// region Shared drawing

private const val CHART_HEIGHT = 140

/** Axis label line height in dp. */
private const val AXIS_LABEL_HEIGHT = 14f

private fun DrawScope.gridLines(ticks: List<ChartTick>) {
    ticks.forEach { tick ->
        val y = tick.y * size.height
        drawLine(BrandTokens.glassBorder.copy(alpha = 0.3f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
    }
}

private fun DrawScope.line(points: List<ChartPoint>, color: Color, highlight: Color) {
    if (points.isEmpty()) return
    val pad = 8.dp.toPx()
    val pixels = points.map { ChartGeometry.point(it, size.width, size.height, pad) }
    val path = Path()
    pixels.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
    drawPath(path, color, style = Stroke(width = 2.5.dp.toPx()))
    points.forEachIndexed { i, p ->
        drawCircle(if (p.highlight) highlight else color, radius = (if (p.highlight) 5 else 3).dp.toPx(), center = Offset(pixels[i].x, pixels[i].y))
    }
}

@Composable
private fun AxisLabels(ticks: List<ChartTick>, modifier: Modifier) {
    Box(modifier) {
        ticks.forEach { tick ->
            Text(
                tick.label,
                style = chartAxisTextStyle(),
                color = BrandTokens.textMuted,
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = ChartGeometry.labelTop(tick, CHART_HEIGHT.toFloat(), AXIS_LABEL_HEIGHT).dp),
            )
        }
    }
}

@Composable
private fun DateAxis(start: String, end: String) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(start, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted)
        Text(end, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted)
    }
}

// endregion
