package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardDoubleArrowLeft
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.core.songs.ScoreRowSeasonPolicy
import com.festivalscoretracker.android.core.songs.SongHistoryChart
import com.festivalscoretracker.android.core.songs.SongHistoryPaging
import com.festivalscoretracker.android.core.songs.SongHistoryPoint
import com.festivalscoretracker.android.core.songs.SongHistorySwap
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentSelector
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.leaderboards.FrostedPagerButton
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import java.text.NumberFormat
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.max

// region Score history card

/**
 * The selected player's score history on the song page (web `ScoreHistoryChart` in a
 * `GraphCard`, operator batch 6, item 6.39): an Instrument Selector over the charts
 * with history, accuracy bars (red→green, gold for a 100% FC) with the score line,
 * tap a bar for its detail row, « ‹ › » paging when bars don't fit, the five best
 * scores (best highlighted) and "View all scores" to the full history page when there
 * are more than five. Switching chart fades the graph and best scores out and the new
 * chart's back in ([SongHistorySwap]; instant with reduced motion) while the card keeps
 * its height: the pager row stays reserved when any chart pages and the height is held
 * during the swap.
 *
 * @param entries This song's history rows (every chart, invalid scores already dropped).
 * @param visible Settings-visible charted instruments.
 * @param keyboard Keys artwork for Lead/Pro Lead.
 * @param initialInstrument Preferred chart (`?instrument=`), or null.
 * @param onViewAll Open the full history page for a chart.
 * @param modifier Modifier.
 */
@Composable
fun SongHistoryCard(
    entries: List<ScoreHistoryEntry>,
    visible: Set<Instrument>,
    keyboard: Boolean,
    initialInstrument: Instrument?,
    onViewAll: (Instrument) -> Unit,
    modifier: Modifier = Modifier,
) {
    val counts = remember(entries) { SongHistoryChart.counts(entries) }
    val available = remember(counts, visible) { SongHistoryChart.available(counts, visible) }
    var chosen by rememberSaveable { mutableStateOf(initialInstrument) }
    val selected = SongHistoryChart.resolve(chosen, available) ?: return
    // The selector follows the choice at once; the graph keeps the shown chart until it has faded out.
    var shown by remember { mutableStateOf(selected) }
    val chart = if (shown in available) shown else selected
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val fade = remember { Animatable(1f) }
    // Card height (px) held while swapping, so the card keeps its size; 0 = not pinned.
    val pin = remember { Animatable(0f) }
    var natural by remember { mutableIntStateOf(0) }
    LaunchedEffect(selected, reduceMotion) {
        // A newer choice relaunches this effect, cancelling the running swap.
        when (SongHistorySwap.plan(chart, selected, reduceMotion)) {
            SongHistorySwap.Plan.None -> Unit
            SongHistorySwap.Plan.Instant -> {
                shown = selected
                fade.snapTo(1f)
                pin.snapTo(0f)
            }
            SongHistorySwap.Plan.Settle -> {
                shown = selected
                if (reduceMotion) fade.snapTo(1f) else fade.animateTo(1f, tween(SongHistorySwap.FADE_IN_MILLIS, easing = LinearOutSlowInEasing))
                releasePin(pin, natural, reduceMotion)
            }
            SongHistorySwap.Plan.Fade -> {
                if (pin.value == 0f) pin.snapTo(natural.toFloat())
                fade.animateTo(0f, tween(SongHistorySwap.FADE_OUT_MILLIS, easing = FastOutLinearInEasing))
                shown = selected
                fade.animateTo(1f, tween(SongHistorySwap.FADE_IN_MILLIS, easing = LinearOutSlowInEasing))
                releasePin(pin, natural, reduceMotion)
            }
        }
    }
    val points = remember(entries, chart) { SongHistoryChart.points(entries, chart) }
    val pinned = with(LocalDensity.current) { pin.value.toDp() }
    Column(modifier.fillMaxWidth().testTag("fst.song-detail.history")) {
        SectionHeader("Score History")
        GlassCard(Modifier.fillMaxWidth().heightIn(min = pinned).testTag("fst.song-detail.history.card")) {
            Column(
                Modifier.padding(horizontal = 12.dp, vertical = 12.dp).onSizeChanged { natural = it.height },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                InstrumentSelector(
                    instruments = available,
                    selected = selected,
                    onSelect = { next -> if (next != null) chosen = next },
                    required = true,
                    keyboard = keyboard,
                    tag = "fst.song-detail.history.instrument",
                )
                Text(
                    "Select a bar to see more score details.",
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.fillMaxWidth(),
                )
                HistoryChart(
                    points,
                    chart,
                    reservesPager = { maxBars -> SongHistoryChart.reservesPager(counts, available, maxBars) },
                    modifier = Modifier.graphicsLayer { alpha = fade.value },
                )
            }
        }
        val top = remember(points) { SongHistoryChart.top(points) }
        // Issue #62: the list shows seasons only when its rows are at least 520 dp wide (web QUERY_SHOW_SEASON).
        BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 8.dp).graphicsLayer { alpha = fade.value }) {
            val width = maxWidth.value
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                top.forEachIndexed { index, point ->
                    HistoryRow(
                        point,
                        best = index == 0,
                        tag = "fst.song-detail.history.top.$index",
                        showSeason = ScoreRowSeasonPolicy.showsSeason(ScoreRowSeasonPolicy.Surface.HistoryList, width, point.season),
                    )
                }
            }
        }
        if (points.size > SongHistoryChart.TOP_COUNT) {
            ViewFullLeaderboardButton(
                onClick = { onViewAll(chart) },
                label = "View All Scores",
                testTag = "fst.song-detail.history.view-all",
                modifier = Modifier.padding(top = 8.dp).graphicsLayer { alpha = fade.value },
            )
        }
    }
}

/**
 * Release the swap's height pin: ease from the held height to the new content height,
 * or at once with reduced motion.
 *
 * @param pin Held card height in px (0 = not pinned).
 * @param natural New content height in px.
 * @param reduceMotion System or app reduced motion.
 */
private suspend fun releasePin(pin: Animatable<Float, AnimationVector1D>, natural: Int, reduceMotion: Boolean) {
    if (!reduceMotion && pin.value > natural) pin.animateTo(natural.toFloat(), tween(SongHistorySwap.FADE_IN_MILLIS, easing = FastOutSlowInEasing))
    pin.snapTo(0f)
}

/**
 * Bars + line on one canvas (drawn, never recomposed per frame), paging and the
 * selected bar's detail row.
 *
 * @param points The shown chart's points.
 * @param chart Shown chart.
 * @param reservesPager Whether to keep the pager row's space for a page size, so the card
 *   keeps its size across charts that do and don't page.
 * @param modifier Modifier (the swap fade).
 */
@Composable
private fun HistoryChart(points: List<SongHistoryPoint>, chart: Instrument, reservesPager: (Int) -> Boolean, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val maxBars = SongHistoryChart.maxBars((maxWidth - AXES_WIDTH).value)
        var paging by remember(chart) { mutableStateOf(SongHistoryPaging(points.size, maxBars)) }
        if (paging.size != points.size || paging.maxBars != maxBars) paging = paging.resized(points.size, maxBars)
        val page = points.subList(paging.pageStart, paging.pageEnd)
        val measurer = rememberTextMeasurer()
        val summary = remember(points, chart) { summary(points, chart) }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(
                Modifier
                    .fillMaxWidth()
                    .height(CHART_HEIGHT)
                    .testTag("fst.song-detail.history.chart")
                    .semantics { contentDescription = summary }
                    .pointerInput(page, paging.pageStart) {
                        detectTapGestures { offset ->
                            val axis = AXIS_WIDTH.toPx()
                            val plot = size.width - axis * 2
                            if (page.isEmpty() || offset.x < axis || offset.x > axis + plot) return@detectTapGestures
                            val slot = plot / page.size
                            val index = ((offset.x - axis) / slot).toInt().coerceIn(0, page.lastIndex)
                            paging = paging.toggle(paging.pageStart + index)
                        }
                    },
            ) {
                val axis = AXIS_WIDTH.toPx()
                val bottomAxis = LABEL_HEIGHT.toPx()
                val plotWidth = size.width - axis * 2
                val plotHeight = size.height - bottomAxis
                val topScore = niceMax(page.maxOfOrNull { it.score } ?: 0L)
                val tick = TextStyle(color = BrandTokens.textMuted, fontSize = 10.sp)
                // Axis ticks: score (left) and accuracy (right).
                listOf(0f, 0.5f, 1f).forEach { f ->
                    val y = plotHeight * (1 - f)
                    val scoreLabel = measurer.measure(compactScore((topScore * f).toLong()), tick)
                    drawText(scoreLabel, topLeft = Offset(axis - scoreLabel.size.width - 4f, (y - scoreLabel.size.height / 2).coerceIn(0f, plotHeight)))
                    val accLabel = measurer.measure("${(100 * f).toInt()}%", tick)
                    drawText(accLabel, topLeft = Offset(axis + plotWidth + 4f, (y - accLabel.size.height / 2).coerceIn(0f, plotHeight)))
                }
                if (page.isEmpty()) return@Canvas
                val slot = plotWidth / page.size
                val barWidth = minOf(slot * 0.9f, MAX_BAR.toPx())
                val radius = CornerRadius(4.dp.toPx())
                page.forEachIndexed { i, point ->
                    val x = axis + slot * i + (slot - barWidth) / 2
                    val h = (plotHeight * (point.accuracyPercent / 100.0)).toFloat().coerceAtLeast(1f)
                    val color = if (point.isGold) BrandTokens.gold else accuracyColor(point.accuracyPercent)
                    drawRoundRect(color, Offset(x, plotHeight - h), Size(barWidth, h), radius)
                    if (paging.selected == paging.pageStart + i) {
                        drawRoundRect(BrandTokens.accentPurple, Offset(x, plotHeight - h), Size(barWidth, h), radius, style = Stroke(3.dp.toPx()))
                    }
                    val label = measurer.measure(point.dateLabel, tick)
                    drawText(label, topLeft = Offset(axis + slot * i + (slot - label.size.width) / 2, plotHeight + 4f))
                }
                // Score line with dots (web accentBlueBright).
                val line = Path()
                page.forEachIndexed { i, point ->
                    val cx = axis + slot * i + slot / 2
                    val cy = plotHeight * (1 - point.score.toFloat() / topScore)
                    if (i == 0) line.moveTo(cx, cy) else line.lineTo(cx, cy)
                }
                drawPath(line, SCORE_BLUE, style = Stroke(2.dp.toPx()))
                page.forEachIndexed { i, point ->
                    drawCircle(SCORE_BLUE, 4.dp.toPx(), Offset(axis + slot * i + slot / 2, plotHeight * (1 - point.score.toFloat() / topScore)))
                }
            }
            Legend(page)
            AnimatedVisibility(
                visible = paging.selected != null,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut(),
            ) {
                paging.selected?.let { points.getOrNull(it) }?.let {
                    HistoryRow(
                        it,
                        best = false,
                        tag = "fst.song-detail.history.detail",
                        showSeason = ScoreRowSeasonPolicy.showsSeason(ScoreRowSeasonPolicy.Surface.HistoryDetail, Float.NaN, it.season),
                    )
                }
            }
            if (paging.needsPaging) {
                Pager(paging) { paging = it }
            } else if (reservesPager(maxBars)) {
                // Another chart pages: keep the pager row's height, empty and silent for TalkBack.
                Spacer(Modifier.fillMaxWidth().height(PAGER_HEIGHT).testTag("fst.song-detail.history.pager-slot").clearAndSetSemantics { })
            }
        }
    }
}

@Composable
private fun Legend(page: List<SongHistoryPoint>) {
    val hasGold = page.any { it.isGold }
    val hasOther = page.any { !it.isGold }
    // Decorative for TalkBack: the chart's own description already names accuracy and score.
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }) {
        if (hasOther) LegendItem("Accuracy") { Box(Modifier.size(14.dp, 12.dp).clip(RoundedCornerShape(2.dp)).background(Brush.horizontalGradient(listOf(accuracyColor(0.0), accuracyColor(100.0))))) }
        if (hasGold) LegendItem("Accuracy (FC)") { Box(Modifier.size(14.dp, 12.dp).clip(RoundedCornerShape(2.dp)).background(BrandTokens.gold)) }
        LegendItem("Score") {
            Canvas(Modifier.size(24.dp, 12.dp)) {
                drawLine(SCORE_BLUE, Offset(0f, size.height / 2), Offset(size.width * 0.75f, size.height / 2), 2.dp.toPx())
                drawCircle(SCORE_BLUE, 3.dp.toPx(), Offset(size.width * 0.75f, size.height / 2))
            }
        }
    }
}

@Composable
private fun LegendItem(label: String, swatch: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        swatch()
        Text(label, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textPrimary)
    }
}

@Composable
private fun Pager(paging: SongHistoryPaging, onChange: (SongHistoryPaging) -> Unit) {
    // The web GraphCard pager: the same frosted circle buttons as the boards and Rank History (7.4).
    val tag = "fst.song-detail.history"
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), modifier = Modifier.fillMaxWidth().testTag("$tag.pager")) {
        FrostedPagerButton(Icons.Filled.KeyboardDoubleArrowLeft, "Back one page", "$tag.back-page", !paging.backDisabled) { onChange(paging.step(-paging.maxBars)) }
        FrostedPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Back one entry", "$tag.back-entry", !paging.backDisabled) { onChange(paging.step(-1)) }
        FrostedPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Forward one entry", "$tag.forward-entry", !paging.forwardDisabled) { onChange(paging.step(1)) }
        FrostedPagerButton(Icons.Filled.KeyboardDoubleArrowRight, "Forward one page", "$tag.forward-page", !paging.forwardDisabled) { onChange(paging.step(paging.maxBars)) }
    }
}

/**
 * One score card (web score list card): date, season, score and accuracy; the best
 * score is purple-highlighted and bold like a selected leaderboard row.
 *
 * @param point The score.
 * @param best Whether this is the best score (highlighted).
 * @param tag Test tag.
 * @param showSeason Whether to show the season pill and read it to TalkBack ([ScoreRowSeasonPolicy]).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HistoryRow(point: SongHistoryPoint, best: Boolean, tag: String, showSeason: Boolean) {
    val season = point.season?.takeIf { showSeason }
    val shape = RoundedCornerShape(12.dp)
    val date = longDate(point.dateKey)
    val accuracy = "${ScoreFormatting.accuracy(point.accuracyPercent * 10_000)}%"
    val score = NumberFormat.getIntegerInstance().format(point.score)
    val modifier = Modifier
        .fillMaxWidth()
        .heightIn(min = 48.dp)
        .clip(shape)
        .background(if (best) PurpleHighlight else BrandTokens.surfaceFrosted)
        .border(1.dp, if (best) PurpleHighlightBorder else BrandTokens.glassBorder, shape)
        .testTag(tag)
        // One stop that reads the summary once (not the summary and then each child text).
        .clearAndSetSemantics {
            contentDescription = listOfNotNull(date, season?.let { "Season $it" }, "score $score", "accuracy $accuracy", "full combo".takeIf { point.isFullCombo }, "best score".takeIf { best }).joinToString(", ")
        }
    val dateWeight = if (best) FontWeight.Bold else null
    if (isLargeText()) {
        // Large text: the date on its own line and the values flowing under it, so the date
        // never ends in an ellipsis and the accuracy pill never breaks "100%" (like StackedScoreRow).
        Column(modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(date, color = BrandTokens.textPrimary, fontWeight = dateWeight)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp), itemVerticalAlignment = Alignment.CenterVertically) {
                season?.let { SeasonPill(it) }
                Text(score, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold)
                AccuracyText(accuracy, point.isFullCombo)
            }
        }
    } else {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = modifier.padding(horizontal = 12.dp)) {
            Text(date, color = BrandTokens.textPrimary, fontWeight = dateWeight, modifier = Modifier.weight(1f), maxLines = 1)
            season?.let { SeasonPill(it) }
            Text(score, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold)
            AccuracyText(accuracy, point.isFullCombo)
        }
    }
}

@Composable
private fun SeasonPill(season: Int) {
    Text(
        "S$season",
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted).padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
private fun AccuracyText(text: String, fullCombo: Boolean) {
    // A minimum, not a fixed width: at 200% "100%" outgrew 64 dp and wrapped to "100 / %".
    Box(Modifier.widthIn(min = ACCURACY_WIDTH), contentAlignment = Alignment.Center) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            softWrap = false,
            fontWeight = FontWeight.SemiBold,
            color = if (fullCombo) BrandTokens.gold else BrandTokens.textPrimary,
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .then(if (fullCombo) Modifier.border(1.5.dp, BrandTokens.gold, RoundedCornerShape(6.dp)) else Modifier)
                .padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

// endregion

// region Helpers

/** Web `accuracyColor`: rgb(220,40,40) at 0% to rgb(46,204,113) at 100%. */
internal fun accuracyColor(percent: Double): Color {
    val t = (percent / 100).coerceIn(0.0, 1.0).toFloat()
    return Color(red = (220 * (1 - t) + 46 * t) / 255f, green = (40 * (1 - t) + 204 * t) / 255f, blue = (40 * (1 - t) + 113 * t) / 255f)
}

/** A rounded axis maximum so the line never touches the top. */
internal fun niceMax(value: Long): Long {
    if (value <= 0) return 1
    val padded = value * 1.1
    val magnitude = Math.pow(10.0, Math.floor(Math.log10(padded)))
    val step = magnitude / 2
    return max(1L, (Math.ceil(padded / step) * step).toLong())
}

/** Web tick format: `12k`, else the number. */
internal fun compactScore(value: Long): String = if (value >= 1000) "${value / 1000}k" else value.toString()

private fun longDate(dateKey: String): String = try {
    DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US).format(OffsetDateTime.parse(dateKey).atZoneSameInstant(ZoneId.systemDefault()))
} catch (_: DateTimeParseException) {
    dateKey.take(10)
}

private fun summary(points: List<SongHistoryPoint>, chart: Instrument): String {
    if (points.isEmpty()) return "No score history for ${chart.label}"
    val best = points.maxBy { it.score }
    return "${chart.label} score history: ${points.size} scores from ${points.first().dateLabel} to ${points.last().dateLabel}. " +
        "Best ${NumberFormat.getIntegerInstance().format(best.score)} on ${best.dateLabel}."
}

/** Web `purpleHighlight`: selected-player and best-score rows. */
internal val PurpleHighlight get() = BrandTokens.purpleHighlight

/** Web `purpleHighlightBorder`. */
internal val PurpleHighlightBorder get() = BrandTokens.purpleHighlightBorder

private val SCORE_BLUE = Color(0xFF4C7DFF)
private val CHART_HEIGHT = 220.dp

/** Pager row height: the 48 dp frosted buttons. */
private val PAGER_HEIGHT = 48.dp

/** Widest bar, so a short history doesn't draw slabs. */
private val MAX_BAR = 72.dp
private val AXIS_WIDTH = 40.dp
private val AXES_WIDTH = AXIS_WIDTH * 2
private val LABEL_HEIGHT = 18.dp
private val ACCURACY_WIDTH = 64.dp

// endregion
