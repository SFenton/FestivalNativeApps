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
import com.festivalscoretracker.android.core.profile.ChartGeometry
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
        chart.totalScoreLine?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textPrimary) }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            AxisLabels(chart.rankTicks, Modifier.width(52.dp).height(CHART_HEIGHT.dp))
            Canvas(Modifier.weight(1f).height(CHART_HEIGHT.dp)) {
                gridLines(chart.rankTicks)
                val barWidth = ChartGeometry.barWidth(chart.scoreBars.size, size.width, 24.dp.toPx())
                chart.scoreBars.forEach { bar ->
                    val rect = ChartGeometry.bar(bar, size.width, size.height, barWidth, 8.dp.toPx())
                    drawRoundRect(
                        BrandTokens.accentBlue.copy(alpha = 0.35f),
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(rect.width, rect.height),
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
                    color = if (bar.gold) BrandTokens.gold else BrandTokens.textPrimary,
                    modifier = Modifier.width(76.dp),
                )
                Box(Modifier.weight(1f).height(14.dp)) {
                    Box(
                        Modifier
                            .fillMaxWidth(ChartGeometry.percentileFraction(bar.fraction))
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
                style = MaterialTheme.typography.labelSmall,
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
