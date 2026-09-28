package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.ChartPoint
import com.festivalscoretracker.android.core.profile.ChartTick
import com.festivalscoretracker.android.core.profile.PercentileBar
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.profile.ScoreHistoryChartModel
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Rank history

/**
 * Rank line (#1 on top) over Total Score bars on one date axis. Geometry is
 * precomputed ([RankHistoryChartModel]); the canvas only redraws on data or size
 * change. One accessibility element carrying the trend summary.
 *
 * @param chart Geometry.
 * @param modifier Modifier.
 */
@Composable
fun RankHistoryChart(chart: RankHistoryChartModel, modifier: Modifier = Modifier) {
    Column(modifier.clearAndSetSemantics { contentDescription = "Rank history. ${chart.headline}. ${chart.summary}" }) {
        Text(chart.headline, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        chart.totalScoreLine?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary) }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            AxisLabels(chart.rankTicks, Modifier.width(52.dp).height(CHART_HEIGHT.dp))
            Canvas(Modifier.weight(1f).height(CHART_HEIGHT.dp)) {
                gridLines(chart.rankTicks)
                val barWidth = (size.width / (chart.scoreBars.size.coerceAtLeast(1) * 1.6f)).coerceIn(2f, 24.dp.toPx())
                chart.scoreBars.forEach { bar ->
                    val h = bar.height * size.height * 0.45f
                    drawRoundRect(
                        BrandTokens.accentBlue.copy(alpha = 0.35f),
                        topLeft = Offset(inset(bar.x, size.width) - barWidth / 2, size.height - h),
                        size = Size(barWidth, h),
                        cornerRadius = CornerRadius(3.dp.toPx()),
                    )
                }
                line(chart.rankLine, BrandTokens.accentPurple, highlight = BrandTokens.gold)
            }
        }
        DateAxis(chart.startLabel, chart.endLabel)
    }
}

// endregion

// region Percentiles

/**
 * Horizontal placement bars ("Top 5%" gold), one accessibility element per bar.
 *
 * @param bars Bars, best first.
 * @param modifier Modifier.
 */
@Composable
fun PercentileBars(bars: List<PercentileBar>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        bars.forEach { bar ->
            Row(
                Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = bar.announcement },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    bar.label,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (bar.gold) BrandTokens.gold else BrandTokens.textSecondary,
                    modifier = Modifier.width(76.dp),
                )
                Box(Modifier.weight(1f).height(14.dp)) {
                    Box(
                        Modifier
                            .fillMaxWidth(bar.fraction.coerceIn(0.02f, 1f))
                            .height(14.dp)
                            .background(if (bar.gold) BrandTokens.gold else BrandTokens.accentPurple, RoundedCornerShape(4.dp)),
                    )
                }
                Text(
                    bar.count.toString(),
                    style = MaterialTheme.typography.labelMedium,
                    color = BrandTokens.textPrimary,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(44.dp),
                )
            }
        }
    }
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

/** Horizontal inset so end points and bars stay inside the canvas. */
private fun DrawScope.inset(x: Float, width: Float): Float {
    val pad = 8.dp.toPx()
    return pad + x * (width - 2 * pad)
}

private fun DrawScope.gridLines(ticks: List<ChartTick>) {
    ticks.forEach { tick ->
        val y = tick.y * size.height
        drawLine(BrandTokens.glassBorder.copy(alpha = 0.3f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
    }
}

private fun DrawScope.line(points: List<ChartPoint>, color: Color, highlight: Color) {
    if (points.isEmpty()) return
    val path = Path()
    points.forEachIndexed { i, p ->
        val x = inset(p.x, size.width)
        val y = p.y * size.height
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    drawPath(path, color, style = Stroke(width = 2.5.dp.toPx()))
    points.forEach { p ->
        val center = Offset(inset(p.x, size.width), p.y * size.height)
        drawCircle(if (p.highlight) highlight else color, radius = (if (p.highlight) 5 else 3).dp.toPx(), center = center)
    }
}

@Composable
private fun AxisLabels(ticks: List<ChartTick>, modifier: Modifier) {
    Box(modifier) {
        ticks.forEach { tick ->
            Text(
                tick.label,
                style = MaterialTheme.typography.labelSmall,
                color = BrandTokens.textMuted,
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = (tick.y * (CHART_HEIGHT - 14)).dp),
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
