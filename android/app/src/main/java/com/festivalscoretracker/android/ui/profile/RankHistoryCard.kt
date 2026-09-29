package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardDoubleArrowLeft
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.ChartGeometry
import com.festivalscoretracker.android.core.profile.ChartTick
import com.festivalscoretracker.android.core.profile.PlayerRankHistorySnapshot
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.profile.RankHistoryColors
import com.festivalscoretracker.android.core.profile.RankHistoryPlot
import com.festivalscoretracker.android.core.profile.RankHistoryWindow
import com.festivalscoretracker.android.ui.leaderboards.FrostedPagerButton
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlin.math.abs
import com.festivalscoretracker.android.ui.common.chartAxisTextStyle

// region Rank history

private const val PLOT_HEIGHT = 220
private const val AXIS_WIDTH = 44

/** Widest bar (web bars fill 80% of a slot of at least 96 px). */
private const val MAX_BAR_WIDTH = 120

/** `0xRRGGBB` → opaque [Color]. */
internal fun rgb(value: Int, alpha: Float = 1f): Color = Color(0xFF000000 or value.toLong()).copy(alpha = alpha)

/**
 * Web `RankHistoryChart` (Total Score): Total Score bars coloured by rank
 * (`rankColor`) and the rank line (#4C7DFF, #1 on top) on one chart, a window of
 * the bars that fit, swipe or ◀◀ ◀ ▶ ▶▶ to move through the 30 days, tap a bar
 * for its details, and the five newest snapshots below.
 *
 * @param chart Snapshots and summary.
 * @param modifier Modifier (carries the test tag).
 */
@Composable
fun RankHistoryChart(chart: RankHistoryChartModel, modifier: Modifier = Modifier) {
    var offset by rememberSaveable(chart.snapshots) { mutableStateOf(0) }
    var selected by rememberSaveable(chart.snapshots) { mutableStateOf<Int?>(null) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Legend()
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val plotWidthDp = (maxWidth.value - 2 * AXIS_WIDTH).coerceAtLeast(1f)
            val window = RankHistoryWindow(chart.snapshots, RankHistoryWindow.barsFor(plotWidthDp), offset, selected)
            val update: (RankHistoryWindow) -> Unit = { next -> offset = next.offset; selected = next.selected }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Plot(window, chart.totalAccounts, update)
                if (window.needsPagination) Pager(window, update)
                window.selectedPoint?.let { point -> Detail(point, chart.totalAccounts) }
            }
        }
        // Web `GraphCard` lists the newest snapshots under the chart without a heading.
        RankHistoryPlot.recent(chart.snapshots).forEachIndexed { index, point ->
            SnapshotRow(point, chart.totalAccounts, best = index == 0, modifier = Modifier.testTag("fst.player.rank-history.row.${point.snapshotDate}"))
        }
    }
}

@Composable
private fun Legend() {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clearAndSetSemantics { }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(width = 20.dp, height = 12.dp).background(
                    Brush.horizontalGradient(listOf(rgb(RankHistoryColors.accuracy(0.0)), rgb(RankHistoryColors.accuracy(100.0)))),
                    RoundedCornerShape(2.dp),
                ),
            )
            Text("Total Score", style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 6.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(width = 24.dp, height = 12.dp)) {
                val y = size.height / 2
                drawLine(rgb(RankHistoryColors.RANK_LINE), Offset(0f, y), Offset(size.width * 0.75f, y), strokeWidth = 2.dp.toPx())
                drawCircle(rgb(RankHistoryColors.RANK_LINE), radius = 3.dp.toPx(), center = Offset(size.width * 0.75f, y))
            }
            Text("Rank", style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 6.dp))
        }
    }
}

@Composable
private fun Plot(window: RankHistoryWindow, totalAccounts: Int, onChange: (RankHistoryWindow) -> Unit) {
    val plot = remember(window, totalAccounts) { RankHistoryPlot.build(window, totalAccounts) }
    val current by rememberUpdatedState(window)
    val change by rememberUpdatedState(onChange)
    var dragged by remember { mutableFloatStateOf(0f) }
    val visible = window.visible
    val description = buildString {
        append("Rank history chart, ")
        append(RankHistoryPlot.displayDate(visible.first())).append(" to ").append(RankHistoryPlot.displayDate(visible.last())).append(". ")
        visible.forEach { append(RankHistoryPlot.displayDate(it)).append(": ").append(ProfileFormatting.rank(it.totalScoreRank)).append(". ") }
    }
    Column {
        Row(Modifier.fillMaxWidth()) {
            AxisColumn(plot.scoreTicks, TextAlign.End)
            Canvas(
                Modifier
                    .weight(1f)
                    .height(PLOT_HEIGHT.dp)
                    .testTag("fst.player.rank-history.plot")
                    .semantics { contentDescription = description }
                    .pointerInput(Unit) {
                        detectTapGestures { tap ->
                            ChartGeometry.bandAt(tap.x, current.visible.size, size.width.toFloat())?.let { change(current.toggle(it)) }
                        }
                    }
                    .pointerInput(Unit) {
                        // Drag the history like a strip: finger right reveals older days, one bar per slot.
                        detectHorizontalDragGestures(onDragEnd = { dragged = 0f }, onDragCancel = { dragged = 0f }) { _, dx ->
                            dragged += dx
                            val slot = size.width.toFloat() / current.visible.size.coerceAtLeast(1)
                            val bars = (dragged / slot).toInt()
                            if (bars != 0 && abs(dragged) >= slot) {
                                dragged -= bars * slot
                                change(current.swiped(bars))
                            }
                        }
                    },
            ) {
                plot.rankTicks.forEach { tick ->
                    val y = tick.y * size.height
                    drawLine(BrandTokens.glassBorder.copy(alpha = 0.3f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
                }
                plot.bars.forEach { bar ->
                    val rect = ChartGeometry.bandBar(bar.bar, plot.bars.size, size.width, size.height, MAX_BAR_WIDTH.dp.toPx())
                    drawRoundRect(
                        rgb(bar.color, RankHistoryColors.BAR_ALPHA),
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(rect.width, rect.height),
                        cornerRadius = CornerRadius(4.dp.toPx()),
                    )
                    if (bar.selected) {
                        drawRoundRect(
                            BrandTokens.accentPurple,
                            topLeft = Offset(rect.left, rect.top),
                            size = Size(rect.width, rect.height),
                            cornerRadius = CornerRadius(4.dp.toPx()),
                            style = Stroke(width = 3.dp.toPx()),
                        )
                    }
                }
                val points = plot.line.map { ChartGeometry.point(it, size.width, size.height, 0f).let { p -> Offset(p.x, p.y) } }
                val path = Path()
                points.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
                val blue = rgb(RankHistoryColors.RANK_LINE)
                drawPath(path, blue, style = Stroke(width = 2.dp.toPx()))
                points.forEachIndexed { i, p -> drawCircle(blue, radius = (if (plot.line[i].highlight) 6 else 4).dp.toPx(), center = p) }
            }
            AxisColumn(plot.rankTicks, TextAlign.Start)
        }
        // Axis dates are in the chart's own description; TalkBack skips them.
        Row(Modifier.fillMaxWidth().padding(horizontal = AXIS_WIDTH.dp, vertical = 4.dp).clearAndSetSemantics { }, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(RankHistoryPlot.displayDate(visible.first()), style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted)
            if (visible.size > 1) Text(RankHistoryPlot.displayDate(visible.last()), style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted)
        }
    }
}

@Composable
private fun AxisColumn(ticks: List<ChartTick>, align: TextAlign) {
    Box(Modifier.width(AXIS_WIDTH.dp).height(PLOT_HEIGHT.dp).clearAndSetSemantics { }) {
        ticks.forEach { tick ->
            Text(
                tick.label,
                style = chartAxisTextStyle(),
                color = BrandTokens.textMuted,
                maxLines = 1,
                textAlign = align,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp)
                    .padding(top = ChartGeometry.labelTop(tick, PLOT_HEIGHT.toFloat(), 14f).dp),
            )
        }
    }
}

@Composable
private fun Pager(window: RankHistoryWindow, onChange: (RankHistoryWindow) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        PagerButton(Icons.Filled.KeyboardDoubleArrowLeft, "Back one page", "fst.player.rank-history.back-page", !window.backDisabled) { onChange(window.backPage()) }
        PagerButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Back one entry", "fst.player.rank-history.back-entry", !window.backDisabled) { onChange(window.backEntry()) }
        PagerButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Forward one entry", "fst.player.rank-history.forward-entry", !window.forwardDisabled) { onChange(window.forwardEntry()) }
        PagerButton(Icons.Filled.KeyboardDoubleArrowRight, "Forward one page", "fst.player.rank-history.forward-page", !window.forwardDisabled) { onChange(window.forwardPage()) }
    }
}

/** The web GraphCard pager: the same frosted circle buttons as the boards' pager. */
@Composable
private fun PagerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, enabled: Boolean, onClick: () -> Unit) =
    FrostedPagerButton(icon, label, tag, enabled, onClick)

@Composable
private fun Detail(point: PlayerRankHistorySnapshot, totalAccounts: Int) {
    Surface(
        color = BrandTokens.accentPurple.copy(alpha = 0.25f),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth().testTag("fst.player.rank-history.detail").semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        SnapshotContent(point, totalAccounts, bold = true)
    }
}

@Composable
private fun SnapshotRow(point: PlayerRankHistorySnapshot, totalAccounts: Int, best: Boolean, modifier: Modifier) {
    Surface(
        color = if (best) BrandTokens.accentPurple.copy(alpha = 0.25f) else BrandTokens.surfaceSubtle.copy(alpha = 0.7f),
        shape = RoundedCornerShape(10.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        SnapshotContent(point, totalAccounts, bold = best)
    }
}

@Composable
private fun SnapshotContent(point: PlayerRankHistorySnapshot, totalAccounts: Int, bold: Boolean) {
    val weight = if (bold) FontWeight.Bold else FontWeight.Normal
    val date = RankHistoryPlot.displayDate(point)
    val rank = ProfileFormatting.rank(point.totalScoreRank)
    val score = point.totalScore?.let { ProfileFormatting.count(it) } ?: "—"
    Row(
        Modifier.heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 10.dp).clearAndSetSemantics { contentDescription = "$date: rank $rank, Total Score $score" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(date, style = MaterialTheme.typography.bodyMedium, fontWeight = weight, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
        Text(
            rank,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.SemiBold,
            color = rgb(RankHistoryColors.rank(point.totalScoreRank, point.rankedAccountCount ?: totalAccounts)),
        )
        Text(score, style = MaterialTheme.typography.bodyMedium, fontWeight = weight, color = BrandTokens.textPrimary)
    }
}

// endregion
