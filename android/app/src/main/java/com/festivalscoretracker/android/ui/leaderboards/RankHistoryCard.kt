package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.ChartGeometry
import com.festivalscoretracker.android.core.rankings.RankHistoryChart
import com.festivalscoretracker.android.core.rankings.RankHistoryRow
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.time.LocalDate

// region Rank history card

/**
 * The selected player's rank history on the Leaderboards overview (web
 * `RankHistoryChart` in `LeaderboardsOverviewPage`): a heading outside the card, then
 * a chart picker, metric value bars under the rank line (#1 on top) and the five
 * newest days. Only one chart's history is read at a time; the picker loads others
 * on demand. Geometry is precomputed, so the canvas redraws only on data or size.
 *
 * @param viewModel Overview logic.
 * @param instruments Settings-visible charts.
 * @param metric Rank By metric.
 * @param selected Selected player (the card is only composed with one).
 */
@Composable
fun RankHistoryCard(viewModel: LeaderboardsViewModel, instruments: List<Instrument>, metric: RankingMetric, selected: String) {
    val current by viewModel.historyInstrument.collectAsStateWithLifecycle()
    val instrument = current ?: return
    LaunchedEffect(instrument, selected) { viewModel.ensureHistory(instrument) }
    val state by viewModel.rankHistory(instrument).collectAsStateWithLifecycle()
    Column(Modifier.fillMaxWidth().testTag("fst.leaderboards.rank-history"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.padding(start = 4.dp).semantics(mergeDescendants = true) { heading() }) {
            Text("Rank History", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
            Text(
                "Your ranking progression over the past ${RankHistoryChart.DAYS} days.",
                style = MaterialTheme.typography.bodyMedium,
                color = BrandTokens.textPrimary,
            )
        }
        GlassCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (instruments.size > 1) HistoryInstrumentPicker(instruments, instrument, viewModel::selectHistoryInstrument)
                when (val value = state) {
                    LoadState.Loading -> Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.heightIn(min = 48.dp).testTag("fst.leaderboards.rank-history.loading"),
                    ) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = BrandTokens.textPrimary, strokeWidth = 2.dp)
                        Text("Loading rank history…", color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 12.dp))
                    }
                    is LoadState.Failed -> ServiceStatusInline(value.issue, "Rank history unavailable", value.countdown, { viewModel.retryHistory(instrument) })
                    is LoadState.Loaded -> {
                        val chart = remember(value.value, metric) { RankHistoryChart.build(value.value.history, metric, LocalDate.now()) }
                        if (chart == null) {
                            Text(
                                "No rank history for ${instrument.label}",
                                color = BrandTokens.textPrimary,
                                modifier = Modifier.padding(vertical = 8.dp).testTag("fst.leaderboards.rank-history.empty"),
                            )
                        } else {
                            HistoryChart(chart, metric)
                            chart.rows.forEach { HistoryRow(it) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryInstrumentPicker(instruments: List<Instrument>, selected: Instrument, onSelect: (Instrument) -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).testTag("fst.leaderboards.rank-history.picker"),
    ) {
        instruments.forEach { instrument ->
            val isSelected = instrument == selected
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) BrandTokens.accentPurple.copy(alpha = 0.35f) else BrandTokens.surfaceSubtle.copy(alpha = 0.6f))
                    .border(BorderStroke(if (isSelected) 2.dp else 1.dp, if (isSelected) BrandTokens.accentPurple else BrandTokens.glassBorder), CircleShape)
                    .selectable(selected = isSelected, role = Role.Tab) { onSelect(instrument) }
                    .testTag("fst.leaderboards.rank-history.picker.${instrument.wireId}")
                    .semantics { contentDescription = instrument.label },
            ) {
                InstrumentIcon(instrument, size = 30.dp, decorative = true)
            }
        }
    }
}

@Composable
private fun HistoryChart(chart: RankHistoryChart, metric: RankingMetric) {
    Column(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "Rank history chart. ${chart.summary}" }) {
        Row(Modifier.fillMaxWidth()) {
            Canvas(Modifier.weight(1f).height(CHART_HEIGHT_DP.dp)) {
                chart.rankTicks.forEach { tick ->
                    val y = tick.y * size.height
                    drawLine(BrandTokens.glassBorder.copy(alpha = 0.5f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
                }
                val pad = 8.dp.toPx()
                val barWidth = ChartGeometry.barWidth(chart.bars.size, size.width, 18.dp.toPx())
                chart.bars.forEach { bar ->
                    val rect = ChartGeometry.bar(bar, size.width, size.height, barWidth, pad)
                    drawRoundRect(
                        BrandTokens.accentPurple.copy(alpha = 0.45f),
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(rect.width, rect.height),
                        cornerRadius = CornerRadius(3.dp.toPx()),
                    )
                }
                if (chart.rankLine.isNotEmpty()) {
                    val pixels = chart.rankLine.map { ChartGeometry.point(it, size.width, size.height, pad) }
                    val path = Path()
                    pixels.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
                    drawPath(path, BrandTokens.accentBlue, style = Stroke(width = 2.dp.toPx()))
                    chart.rankLine.forEachIndexed { i, point ->
                        drawCircle(
                            if (point.highlight) BrandTokens.gold else BrandTokens.accentBlue,
                            radius = (if (point.highlight) 4.5f else 2.5f).dp.toPx(),
                            center = Offset(pixels[i].x, pixels[i].y),
                        )
                    }
                }
            }
            Box(Modifier.width(56.dp).height(CHART_HEIGHT_DP.dp)) {
                chart.rankTicks.forEach { tick ->
                    Text(
                        tick.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = BrandTokens.textPrimary,
                        maxLines = 1,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(top = ChartGeometry.labelTop(tick, CHART_HEIGHT_DP.toFloat(), AXIS_LABEL_HEIGHT).dp),
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp, end = 56.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(chart.startLabel, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textPrimary)
            Text(chart.endLabel, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textPrimary)
        }
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            LegendSwatch(metric.label) { Box(Modifier.size(12.dp).clip(RoundedCornerShape(3.dp)).background(BrandTokens.accentPurple.copy(alpha = 0.6f))) }
            LegendSwatch("Rank") { Box(Modifier.width(18.dp).height(2.dp).background(BrandTokens.accentBlue)) }
        }
    }
}

@Composable
private fun LegendSwatch(label: String, swatch: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        swatch()
        Text(label, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary)
    }
}

@Composable
private fun HistoryRow(row: RankHistoryRow) {
    val shape = RoundedCornerShape(10.dp)
    var modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(shape)
    modifier = if (row.latest) {
        modifier.background(BrandTokens.accentPurple.copy(alpha = 0.18f)).border(BorderStroke(1.dp, BrandTokens.accentPurple), shape)
    } else {
        modifier.background(BrandTokens.surfaceSubtle.copy(alpha = 0.5f))
    }
    val weight = if (row.latest) FontWeight.Bold else FontWeight.Normal
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier
            .padding(horizontal = 12.dp)
            .clearAndSetSemantics { contentDescription = "${row.date}, rank ${row.rank}, ${row.value}" },
    ) {
        Text(row.date, color = BrandTokens.textPrimary, fontWeight = weight, modifier = Modifier.weight(1f))
        Text(row.rank, color = BrandTokens.textPrimary, fontWeight = if (row.latest) FontWeight.Bold else FontWeight.SemiBold)
        Text(row.value, color = BrandTokens.textPrimary, fontWeight = weight)
    }
}

/** Chart height in dp (web `ChartSize.height` is taller; phones need the list visible). */
private const val CHART_HEIGHT_DP = 160

/** Axis label line height in dp. */
private const val AXIS_LABEL_HEIGHT = 14f

// endregion
