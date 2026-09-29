package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardDoubleArrowLeft
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.text.style.TextAlign
import com.festivalscoretracker.android.core.profile.ChartTick
import com.festivalscoretracker.android.core.profile.RankHistoryColors
import com.festivalscoretracker.android.core.profile.RankHistoryWindow
import com.festivalscoretracker.android.core.rankings.RankHistoryPoint
import java.time.format.DateTimeFormatter
import kotlin.math.abs
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
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.time.LocalDate
import com.festivalscoretracker.android.ui.common.chartAxisTextStyle

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
                    LoadState.Loading -> Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 96.dp).testTag("fst.leaderboards.rank-history.loading"),
                    ) {
                        FestivalLoading("Loading rank history")
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
                            HistoryChart(chart)
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

/**
 * The windowed chart (web `GraphCard`, same interaction as the profile's
 * `RankHistoryChart`): the bars that fit, swipe or « ‹ › » to move through the days,
 * tap a bar for its detail. Bars are the metric value coloured by rank (web
 * `rankColor`); the line is the rank (#1 on top).
 *
 * @param chart Card data.
 */
@Composable
private fun HistoryChart(chart: RankHistoryChart) {
    var offset by rememberSaveable(chart.snapshots) { mutableIntStateOf(0) }
    var selected by rememberSaveable(chart.snapshots) { mutableStateOf<Int?>(null) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clearAndSetSemantics { }) {
            LegendSwatch(chart.metric.label) {
                Box(
                    Modifier.size(width = 20.dp, height = 12.dp).background(
                        Brush.horizontalGradient(listOf(rgb(RankHistoryColors.accuracy(0.0)), rgb(RankHistoryColors.accuracy(100.0)))),
                        RoundedCornerShape(2.dp),
                    ),
                )
            }
            LegendSwatch("Rank") { Box(Modifier.width(18.dp).height(2.dp).background(rgb(RankHistoryColors.RANK_LINE))) }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val plotWidthDp = (maxWidth.value - 2 * AXIS_WIDTH_DP).coerceAtLeast(1f)
            val window = RankHistoryWindow(chart.snapshots, RankHistoryWindow.barsFor(plotWidthDp), offset, selected)
            val update: (RankHistoryWindow) -> Unit = { next -> offset = next.offset; selected = next.selected }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                HistoryPlot(chart, window, update)
                if (window.needsPagination) HistoryPager(window, update)
                chart.detail(window)?.let { detail ->
                    Surface(
                        color = BrandTokens.accentPurple.copy(alpha = 0.25f),
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth().testTag("fst.leaderboards.rank-history.detail").semantics { liveRegion = LiveRegionMode.Polite },
                    ) { HistoryRow(detail, Modifier) }
                }
            }
        }
    }
}

@Composable
private fun HistoryPlot(chart: RankHistoryChart, window: RankHistoryWindow, onChange: (RankHistoryWindow) -> Unit) {
    val plot = remember(window, chart) { chart.plot(window) }
    val valueTicks = plot.scoreTicks
    val description = remember(window, chart) { chart.windowDescription(window) }
    val current by rememberUpdatedState(window)
    val change by rememberUpdatedState(onChange)
    var dragged by remember { mutableFloatStateOf(0f) }
    val visible = chart.points.subList(window.pageStart, window.pageEnd)
    Column {
        Row(Modifier.fillMaxWidth()) {
            AxisLabels(valueTicks, TextAlign.End)
            Canvas(
                Modifier
                    .weight(1f)
                    .height(CHART_HEIGHT_DP.dp)
                    .testTag("fst.leaderboards.rank-history.plot")
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
                    drawLine(BrandTokens.glassBorder.copy(alpha = 0.5f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
                }
                plot.bars.forEach { bar ->
                    val rect = ChartGeometry.bandBar(bar.bar, plot.bars.size, size.width, size.height, 72.dp.toPx())
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
            AxisLabels(plot.rankTicks, TextAlign.Start)
        }
        // Axis dates are in the chart's own description; TalkBack skips them.
        Row(Modifier.fillMaxWidth().padding(horizontal = AXIS_WIDTH_DP.dp, vertical = 4.dp).clearAndSetSemantics { }, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(shortDate(visible.first()), style = MaterialTheme.typography.labelSmall, color = BrandTokens.textPrimary)
            if (visible.size > 1) Text(shortDate(visible.last()), style = MaterialTheme.typography.labelSmall, color = BrandTokens.textPrimary)
        }
    }
}

@Composable
private fun AxisLabels(ticks: List<ChartTick>, align: TextAlign) {
    Box(Modifier.width(AXIS_WIDTH_DP.dp).height(CHART_HEIGHT_DP.dp).clearAndSetSemantics { }) {
        ticks.forEach { tick ->
            Text(
                tick.label,
                style = chartAxisTextStyle(),
                color = BrandTokens.textPrimary,
                maxLines = 1,
                textAlign = align,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp)
                    .padding(top = ChartGeometry.labelTop(tick, CHART_HEIGHT_DP.toFloat(), AXIS_LABEL_HEIGHT).dp),
            )
        }
    }
}

@Composable
private fun HistoryPager(window: RankHistoryWindow, onChange: (RankHistoryWindow) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        HistoryPagerButton(Icons.Filled.KeyboardDoubleArrowLeft, "Back one page", "back-page", !window.backDisabled) { onChange(window.backPage()) }
        HistoryPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Back one entry", "back-entry", !window.backDisabled) { onChange(window.backEntry()) }
        HistoryPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Forward one entry", "forward-entry", !window.forwardDisabled) { onChange(window.forwardEntry()) }
        HistoryPagerButton(Icons.Filled.KeyboardDoubleArrowRight, "Forward one page", "forward-page", !window.forwardDisabled) { onChange(window.forwardPage()) }
    }
}

@Composable
private fun HistoryPagerButton(icon: ImageVector, label: String, id: String, enabled: Boolean, onClick: () -> Unit) =
    FrostedPagerButton(icon, label, "fst.leaderboards.rank-history.$id", enabled, onClick)

private fun shortDate(point: RankHistoryPoint): String = point.date.format(DateTimeFormatter.ofPattern("M/d/yy"))

/** `0xRRGGBB` to an opaque colour with [alpha]. */
private fun rgb(value: Int, alpha: Float = 1f): Color = Color(0xFF000000 or value.toLong()).copy(alpha = alpha)

@Composable
private fun LegendSwatch(label: String, swatch: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        swatch()
        Text(label, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary)
    }
}

@Composable
private fun HistoryRow(row: RankHistoryRow, background: Modifier? = null) {
    val shape = RoundedCornerShape(10.dp)
    var modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(shape)
    modifier = when {
        background != null -> modifier.then(background)
        row.latest -> modifier.background(BrandTokens.accentPurple.copy(alpha = 0.18f)).border(BorderStroke(1.dp, BrandTokens.accentPurple), shape)
        else -> modifier.background(BrandTokens.surfaceSubtle.copy(alpha = 0.5f))
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

/** Chart height in dp (the profile chart's plot height). */
private const val CHART_HEIGHT_DP = 180

/** Width of each axis label column in dp. */
private const val AXIS_WIDTH_DP = 44

/** Axis label line height in dp. */
private const val AXIS_LABEL_HEIGHT = 14f

// endregion
