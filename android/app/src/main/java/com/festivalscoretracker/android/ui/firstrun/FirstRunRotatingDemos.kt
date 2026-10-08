package com.festivalscoretracker.android.ui.firstrun

import android.net.ConnectivityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoBars
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoPools
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoRival
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoScorePattern
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoScoreState
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSong
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSongs
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSuggestionTemplate
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoTiming
import com.festivalscoretracker.android.core.firstrun.FirstRunMetadataRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunRowRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunSlotRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunWindowRotation
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.songs.SongInstrumentBadge
import com.festivalscoretracker.android.core.songs.SongInstrumentStatus
import com.festivalscoretracker.android.core.songs.SongMetadataPill
import com.festivalscoretracker.android.core.firstrun.FirstRunStillDemoData
import com.festivalscoretracker.android.core.firstrun.RivalGroupsFit
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.ui.rivals.RivalRow
import com.festivalscoretracker.android.ui.rivals.RivalSectionHeader
import com.festivalscoretracker.android.ui.rivals.RivalSongRow
import com.festivalscoretracker.android.ui.rivals.categoryColor
import com.festivalscoretracker.android.ui.songs.MetadataPill
import com.festivalscoretracker.android.ui.songs.StatusChips
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Surface
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.ui.leaderboards.ChoiceMenuItems
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoFit
import com.festivalscoretracker.android.core.firstrun.FirstRunEntrance
import com.festivalscoretracker.android.core.firstrun.FirstRunInfiniteScroll
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade
import com.festivalscoretracker.android.core.songs.SongHistoryPoint
import com.festivalscoretracker.android.core.suggestions.SuggestionCategory
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.core.suggestions.SuggestionSongItem
import com.festivalscoretracker.android.presentation.suggestions.SuggestionCard
import com.festivalscoretracker.android.presentation.suggestions.SuggestionRow
import com.festivalscoretracker.android.ui.common.coveredByModal
import com.festivalscoretracker.android.ui.common.drawScrollEdgeRamp
import com.festivalscoretracker.android.ui.common.rememberScrollEdgeHardEdge
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.songdetail.HistoryChart
import com.festivalscoretracker.android.ui.songs.SongRowCard
import com.festivalscoretracker.android.ui.suggestions.SuggestionCardView
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import com.festivalscoretracker.android.ui.songdetail.HistoryRow as SongHistoryRow

// region Driver

/** CSS `ease`, the web demos' fade curve. */
private val DemoEase = FirstRunDemoTiming.EASE.let { CubicBezierEasing(it[0], it[1], it[2], it[3]) }

/**
 * Fade state of one rotating demo: which slots are fading and their shared opacity.
 */
@Stable
internal class DemoFade {
    /** Slots currently fading out or in. */
    var fading by mutableStateOf(emptySet<Int>())

    /** Opacity of the fading slots. */
    val alpha = Animatable(1f)

    /**
     * Opacity of one slot.
     *
     * @param slot Slot index.
     * @return 1 unless the slot is fading.
     */
    fun alphaOf(slot: Int): Float = if (slot in fading) alpha.value else 1f
}

/**
 * Whether rotating demos may run: the app is resumed (foreground) and Data Saver
 * is off (no artwork loads, matching iOS Low Data Mode).
 *
 * @return True when ticking is allowed.
 */
@Composable
internal fun rememberDemoRotationAllowed(): Boolean {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateFlow.collectAsState()
    return state.isAtLeast(Lifecycle.State.RESUMED) && !rememberDataSaver()
}

/**
 * Whether Android Data Saver restricts this app (artwork is not loaded then).
 *
 * @return True under Data Saver.
 */
@Composable
internal fun rememberDataSaver(): Boolean {
    val context = LocalContext.current
    return remember {
        context.getSystemService(ConnectivityManager::class.java)?.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    }
}

/**
 * The web demos' swap clock (`setInterval` every [intervalMs]): while [running], each tick
 * fades the [plan]ned slots out, [commit]s the new data while they are hidden and fades them
 * back in. Without [fade], or under reduce motion, the data swaps at once with no motion
 * ([DemoSlot] then shows the new value in the same frame). Stopping mid-fade still completes the swap.
 *
 * @param running Visible settled slide, app in the foreground.
 * @param fade Fade state, or null for an unfaded swap.
 * @param intervalMs Time between swaps.
 * @param fadeMs Fade-out (and fade-in) time.
 * @param plan Slots the next swap changes; empty skips the tick.
 * @param commit Applies the swap of those slots.
 */
@Composable
internal fun DemoTicker(
    running: Boolean,
    fade: DemoFade?,
    intervalMs: Long = FirstRunDemoTiming.SWAP_INTERVAL_MS,
    fadeMs: Int = FirstRunDemoTiming.FADE_MS,
    plan: () -> List<Int>,
    commit: (List<Int>) -> Unit,
) {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val probe = LocalDemoProbe.current
    val currentPlan by rememberUpdatedState(plan)
    val currentCommit by rememberUpdatedState(commit)
    LaunchedEffect(running, reduceMotion, fade, probe) {
        if (!running || probe) return@LaunchedEffect
        while (true) {
            delay(intervalMs)
            val slots = currentPlan()
            if (slots.isEmpty()) continue
            if (fade == null || reduceMotion) {
                currentCommit(slots)
                continue
            }
            var committed = false
            try {
                fade.fading = slots.toSet()
                fade.alpha.animateTo(0f, tween(fadeMs, easing = DemoEase))
                currentCommit(slots)
                committed = true
                fade.alpha.animateTo(1f, tween(fadeMs, easing = DemoEase))
            } finally {
                if (!committed) currentCommit(slots)
                withContext(NonCancellable) { fade.alpha.snapTo(1f) }
                fade.fading = emptySet()
            }
        }
    }
}

/**
 * One swappable part of a demo. With motion it fades with [fade] (and moves by [shift],
 * positive = down, as it fades out). Under reduce motion a new [value] replaces the old one in
 * the same frame, with no fade or movement (`load-transition` R6).
 *
 * @param T Content value.
 * @param value Current value.
 * @param fade Demo fade state.
 * @param slot This part's slot index.
 * @param modifier Modifier for the part.
 * @param shift Movement while faded out.
 * @param content Renders a value.
 */
@Composable
internal fun <T> DemoSlot(value: T, fade: DemoFade, slot: Int, modifier: Modifier = Modifier, shift: Dp = 0.dp, content: @Composable (T) -> Unit) {
    if (LocalFestivalAccessibility.current.reduceMotion) {
        Box(modifier) { content(value) }
    } else {
        Box(
            modifier.graphicsLayer {
                val alpha = fade.alphaOf(slot)
                this.alpha = alpha
                translationY = (1f - alpha) * shift.toPx()
            },
        ) { content(value) }
    }
}

// endregion

// region Shared rows

/**
 * A demo song row: the real Songs [SongRowCard] (web `DemoSongRow` + `SongInfo`), or the
 * [PlaceholderSongCard] skeleton for a placeholder.
 *
 * @param song Song or placeholder.
 * @param modifier Modifier (entrance).
 * @param trailing Trailing content beside the title (pills).
 * @param below Content under the row (status chips, metadata pills).
 */
@Composable
private fun DemoSongRow(song: FirstRunDemoSong, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}, below: (@Composable ColumnScope.() -> Unit)? = null) {
    if (song.isPlaceholder) {
        PlaceholderSongCard(modifier)
        return
    }
    val dataSaver = rememberDataSaver()
    SongRowCard(
        title = song.title,
        subtitle = listOfNotNull(song.artist, song.year?.toString()).joinToString(" · "),
        artUrl = song.artUrl.takeUnless { dataSaver },
        onClick = {},
        modifier = modifier,
        trailing = trailing,
        below = below ?: {},
        titleTag = demoSongTag(song.id),
    )
}

/**
 * The demo pool: real catalogue songs from [LocalFirstRunDemoCatalog] (shared with the still
 * demos), else placeholders.
 */
@Composable
private fun demoPool(): List<FirstRunDemoSong> {
    val catalog = LocalFirstRunDemoCatalog.current
    return remember(catalog) { FirstRunDemoSongs.rotationPool(catalog.songs, catalog.artworkUrl) }
}

/**
 * Whether song rows may rotate: placeholders hold still until real songs arrive.
 *
 * @receiver Pool.
 */
private val List<FirstRunDemoSong>.rotates: Boolean get() = none { it.isPlaceholder }

/** Rotating song rows with an optional trailing/below part per row. */
@Composable
private fun RotatingSongRows(
    id: String,
    running: Boolean,
    visible: Int,
    trailing: @Composable (index: Int, song: FirstRunDemoSong) -> Unit = { _, _ -> },
    below: (@Composable (FirstRunDemoSong) -> Unit)? = null,
) {
    val pool = demoPool()
    DemoFitFirst(remember(visible) { FirstRunDemoFit.rowCandidates(visible) }) { rows ->
        var rotation by remember(pool, rows) { mutableStateOf(FirstRunRowRotation.start(pool, rows) { it.id }) }
        val fade = remember { DemoFade() }
        DemoTicker(running && pool.rotates, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            rotation.rows.forEachIndexed { index, song ->
                DemoSlot(song, fade, index, Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) { shown ->
                    DemoSongRow(shown, trailing = { trailing(index, shown) }, below = below?.let { { it(shown) } })
                }
            }
        }
    }
}

// endregion

// region Rotating demos

/**
 * The twelve web demos that swap data on a timer (issue #58).
 *
 * @param id Slide ID (one of [com.festivalscoretracker.android.core.firstrun.FirstRunRotatingDemos.IDS]).
 * @param active Whether the slide is the settled current page.
 */
@Composable
internal fun FirstRunRotatingDemo(id: String, active: Boolean) {
    val running = active && rememberDemoRotationAllowed()
    when (id) {
        "songs-song-list" -> RotatingSongRows(id, running, visible = 3)
        "songs-icons" -> RotatingSongRows(id, running, visible = 2, below = { song -> if (!song.isPlaceholder) IconChips(song) })
        "songs-metadata" -> MetadataDemo(id, running)
        "statistics-top-songs" -> RotatingSongRows(id, running, visible = 3, trailing = { index, song ->
            if (!song.isPlaceholder) {
                val label = FirstRunDemoPools.topSongPercentile(index)
                MetadataPill(SongMetadataPill(MetadataField.Percentile, label, label, percentile = FirstRunDemoPools.percentileTier(label)), song.id)
            }
        })
        "songinfo-bar-select" -> BarSelectDemo(running)
        "suggestions-category-card" -> CategoryCardDemo(running)
        "leaderboards-experimental-metrics" -> ExperimentalMetricsDemo(running)
        "compete-hub" -> CompeteHubDemo(running)
        "compete-rivals", "rivals-overview" -> RivalGroupsDemo(id, running)
        "rivals-instruments" -> RivalsInstrumentsDemo(running)
        "rivals-detail" -> RivalsDetailDemo(running)
    }
}

/** Instruments the icons demo shows (the default visible charts' order). */
internal val ICON_INSTRUMENTS = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals, Instrument.ProLead, Instrument.ProBass)

@Composable
private fun IconChips(song: FirstRunDemoSong) {
    val badges = remember(song.title) {
        FirstRunDemoScorePattern.states(song.title, ICON_INSTRUMENTS.size).mapIndexed { index, state ->
            val status = when (state) {
                FirstRunDemoScoreState.FullCombo -> SongInstrumentStatus.FullCombo
                FirstRunDemoScoreState.Scored -> SongInstrumentStatus.Scored
                FirstRunDemoScoreState.NoScore -> SongInstrumentStatus.NoScore
            }
            SongInstrumentBadge(ICON_INSTRUMENTS[index], status)
        }
    }
    StatusChips(badges, song.id, keyboard = false)
}

@Composable
private fun MetadataDemo(id: String, running: Boolean) {
    val pool = demoPool()
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(2) }) { rows ->
    var rotation by remember(pool, rows) { mutableStateOf(FirstRunMetadataRotation.start(pool, rows)) }
    val fade = remember { DemoFade() }
    DemoTicker(running && pool.rotates, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rotation.rows.forEachIndexed { index, row ->
            DemoSlot(row, fade, index, Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) { shown ->
                DemoSongRow(shown.song, below = if (shown.song.isPlaceholder) null else {
                    {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                            FirstRunMetadataRotation.pills(shown.meta, shown.layout).forEach { MetadataPill(it, shown.song.id) }
                        }
                    }
                })
            }
        }
    }
    }
}

/**
 * Song Detail's real history chart with the selected bar moving every 2.5 s and the real history
 * row for it fading in underneath (web `BarSelectDemo`).
 */
@Composable
private fun BarSelectDemo(running: Boolean) {
    var selected by remember { mutableIntStateOf(0) }
    val fade = remember { DemoFade() }
    val points = remember {
        val bars = FirstRunDemoBars.BARS
        bars.mapIndexed { index, bar ->
            val date = OffsetDateTime.now().minusDays((bars.size - 1 - index).toLong()).withNano(0)
            SongHistoryPoint(date.toString(), date.format(DateTimeFormatter.ofPattern("M/d/yy")), bar.score.toLong(), bar.accuracy.toDouble(), bar.fullCombo)
        }
    }
    val best = remember(points) { points.maxOf { it.score } }
    DemoTicker(
        running,
        fade,
        intervalMs = FirstRunDemoTiming.BAR_SELECT_INTERVAL_MS,
        fadeMs = FirstRunDemoTiming.BAR_SELECT_FADE_MS,
        plan = { listOf(0) },
        commit = { selected = (selected + 1) % points.size },
    )
    GlassCard(Modifier.fillMaxWidth().demoEntrance(0)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            HistoryChart(points, Instrument.Lead, reservesPager = { false }, plotHeight = 90.dp, showAll = true, selected = selected, detailTag = "fst.first-run.demo.chart.detail", showDetail = false)
            DemoSlot(selected, fade, 0, Modifier.testTag("fst.first-run.demo.bar-detail")) { index ->
                SongHistoryRow(points[index], best = points[index].score == best, tag = "fst.first-run.demo.bar-detail.row", showSeason = false)
            }
        }
    }
}

/**
 * One real Suggestions card (narrow layout) whose category changes every few seconds, dropping in
 * like the web's `CategoryCardDemo`; skeleton song rows until real songs arrive.
 */
@Composable
private fun CategoryCardDemo(running: Boolean) {
    val pool = demoPool()
    if (!pool.rotates) {
        DemoPlaceholderRows("suggestions-category-card")
        return
    }
    var template by remember { mutableIntStateOf(0) }
    val fade = remember { DemoFade() }
    val templates = FirstRunDemoSuggestionTemplate.TEMPLATES
    val dataSaver = rememberDataSaver()
    DemoTicker(running, fade, plan = { listOf(0) }, commit = { template = (template + 1) % templates.size })
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(CATEGORY_CARD_ROWS) }) { rows ->
        DemoSlot(template, fade, 0, Modifier.demoEntrance(0), shift = FirstRunDemoTiming.CARD_DROP_DP.dp) { index ->
            val card = remember(index, pool, rows) { demoSuggestionCard(index, templates[index], pool, rows) }
            SuggestionCardView(card, narrow = true, artworkUrl = { url -> url.takeUnless { dataSaver } }, onSong = {})
        }
    }
}

/**
 * Three [PlaceholderSongCard] rows with the row entrance, while the catalogue loads.
 *
 * @param id Slide ID (entrance cadence).
 */
@Composable
private fun DemoPlaceholderRows(id: String) {
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(3) }) { rows ->
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(rows) { PlaceholderSongCard(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, it))) }
        }
    }
}

/**
 * The real Rank By menu (Leaderboards' top-bar [ChoiceMenuItems] on a Material menu surface) with
 * the check moving through the experimental metrics like the web `ExperimentalMetricsDemo`. The
 * header is left off so the four items fit the 220 dp demo frame.
 */
@Composable
private fun ExperimentalMetricsDemo(running: Boolean) {
    var selected by remember { mutableIntStateOf(0) }
    val metrics = remember { RankingMetric.entries - RankingMetric.TotalScore }
    DemoTicker(running, fade = null, plan = { listOf(0) }, commit = { selected = (selected + 1) % metrics.size })
    Surface(
        shape = MenuDefaults.shape,
        color = BrandTokens.cardBackground,
        tonalElevation = MenuDefaults.TonalElevation,
        shadowElevation = MenuDefaults.ShadowElevation,
        modifier = Modifier.widthIn(min = 200.dp).demoEntrance(0),
    ) {
        Column(Modifier.width(IntrinsicSize.Max).padding(vertical = 8.dp)) {
            ChoiceMenuItems(
                label = null,
                options = metrics,
                selected = metrics[selected],
                optionLabel = RankingMetric::label,
                itemTag = { index, _ -> if (index == selected) "fst.first-run.demo.metric.selected" else "fst.first-run.demo.metric" },
                onSelect = { selected = metrics.indexOf(it) },
            )
        }
    }
}

/**
 * Rival rows shown by the group demos: the real Rivals [RivalRow] with decorative demo data
 * (web demos pass `onClick={NOOP}` to their real `RivalRow`).
 *
 * @param rivals Rivals in order.
 * @param direction Their side of the list.
 * @param id Slide ID (entrance cadence).
 * @param firstEntrance Entrance index of the first row.
 */
@Composable
private fun DemoRivalRows(rivals: List<FirstRunDemoRival>, direction: RivalDirection, id: String, firstEntrance: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(RIVAL_ROW_GAP)) {
        rivals.forEachIndexed { index, rival ->
            RivalRow(rival.entry(direction), onClick = null, modifier = Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, firstEntrance + index)))
        }
    }
}

/**
 * An "Above You"/"Below You" label: the real Rivals section header (web demo label, `Font.lg` bold).
 *
 * @param title Label.
 * @param id Slide ID.
 * @param entrance Entrance index.
 */
@Composable
private fun DemoRivalLabel(title: String, id: String, entrance: Int) {
    RivalSectionHeader(title, Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, entrance)))
}

/**
 * Web `CompeteHubDemo`: the real Leaderboards card (top players plus the player's own row)
 * alternating with the real rival groups, rising as they swap.
 */
@Composable
private fun CompeteHubDemo(running: Boolean) {
    val id = "compete-hub"
    var rivalsLayout by remember { mutableStateOf(false) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { listOf(0) }, commit = { rivalsLayout = !rivalsLayout })
    DemoSlot(rivalsLayout, fade, 0, shift = (-FirstRunDemoTiming.HUB_RISE_DP).dp) { rivals ->
        if (rivals) {
            DemoFitFirst(remember { FirstRunDemoFit.rivalGroupCandidates() }) { fit ->
                if (fit.single) {
                    DemoRivalRows(FirstRunDemoPools.RIVALS_ABOVE.take(1), RivalDirection.Above, id, 0)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(RIVAL_GROUP_GAP)) {
                        DemoRivalLabel(ABOVE_YOU, id, 0)
                        DemoRivalRows(FirstRunDemoPools.RIVALS_ABOVE.take(fit.perGroup), RivalDirection.Above, id, 1)
                        DemoRivalLabel(BELOW_YOU, id, fit.perGroup + 1)
                        DemoRivalRows(FirstRunDemoPools.RIVALS_BELOW.take(fit.perGroup), RivalDirection.Below, id, fit.perGroup + 2)
                    }
                }
            }
        } else {
            val player = FirstRunStillDemoData.NEIGHBOURHOOD[FirstRunStillDemoData.PLAYER_INDEX]
            DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(HUB_RANKING_ROWS) }) { rows ->
                DemoRankingsCard(id, remember(rows) { FirstRunStillDemoData.RANKINGS.take(rows) + player }, header = false)
            }
        }
    }
}

/**
 * Web `CompeteRivalsDemo`/`RivalsOverviewDemo`: the real rival rows under "Above You" and
 * "Below You", the groups swapping in turn; the web's compact single card (one row that
 * alternates sides) when two labelled groups don't fit.
 *
 * @param id Slide ID.
 * @param running Whether the groups rotate.
 */
@Composable
private fun RivalGroupsDemo(id: String, running: Boolean) {
    DemoFitFirst(remember { FirstRunDemoFit.rivalGroupCandidates() }) { fit -> RivalGroups(id, running, fit) }
}

/**
 * [RivalGroupsDemo] for one fit.
 *
 * @param id Slide ID.
 * @param running Whether the groups rotate.
 * @param fit Rivals per group, labels and compact mode.
 */
@Composable
private fun RivalGroups(id: String, running: Boolean, fit: RivalGroupsFit) {
    var above by remember(fit) { mutableStateOf(FirstRunWindowRotation(FirstRunDemoPools.RIVALS_ABOVE, fit.perGroup)) }
    var below by remember(fit) { mutableStateOf(FirstRunWindowRotation(FirstRunDemoPools.RIVALS_BELOW, fit.perGroup)) }
    var nextAbove by remember(fit) { mutableStateOf(true) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { listOf(if (fit.single || nextAbove) 0 else 1) }, commit = {
        if (nextAbove) above = above.advanced() else below = below.advanced()
        nextAbove = !nextAbove
    })
    val drop = FirstRunDemoTiming.GROUP_DROP_DP.dp
    if (fit.single) {
        // Web compact mode: the shown side advances, then the card switches sides.
        DemoSlot(if (nextAbove) above.rows to RivalDirection.Above else below.rows to RivalDirection.Below, fade, 0, shift = drop) { (rows, direction) ->
            DemoRivalRows(rows, direction, id, 0)
        }
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(RIVAL_GROUP_GAP)) {
        DemoRivalLabel(ABOVE_YOU, id, 0)
        DemoSlot(above.rows, fade, 0, shift = drop) { DemoRivalRows(it, RivalDirection.Above, id, 1) }
        DemoRivalLabel(BELOW_YOU, id, fit.perGroup + 1)
        DemoSlot(below.rows, fade, 1, shift = drop) { DemoRivalRows(it, RivalDirection.Below, id, fit.perGroup + 2) }
    }
}

/**
 * Web `RivalsInstrumentsDemo`: one real Rivals section per instrument (its header with the
 * instrument icon, then its above and below [RivalRow]s), random cards swapping to the next rival
 * from their pool. When a section with both cards doesn't fit, one section shows a single card
 * that alternates sides (web single-card mode).
 */
@Composable
private fun RivalsInstrumentsDemo(running: Boolean) {
    val id = "rivals-instruments"
    val order = FirstRunDemoPools.INSTRUMENT_RIVAL_ORDER
    DemoFitFirst(remember { FirstRunDemoFit.instrumentSectionCandidates(order.size) }) { fit ->
        val instruments = order.take(fit.sections)
        // One pool per card: above then below per instrument, or one alternating pool per instrument.
        val pools = remember(fit) {
            instruments.flatMap { instrument ->
                val (above, below) = FirstRunDemoPools.INSTRUMENT_RIVALS.getValue(instrument)
                if (fit.cards == 2) {
                    listOf(above.map { it.entry(RivalDirection.Above) }, below.map { it.entry(RivalDirection.Below) })
                } else {
                    listOf(above.zip(below).flatMap { (a, b) -> listOf(a.entry(RivalDirection.Above), b.entry(RivalDirection.Below)) })
                }
            }
        }
        var rotation by remember(fit) { mutableStateOf(FirstRunSlotRotation(pools.map { it.size })) }
        val fade = remember { DemoFade() }
        DemoTicker(running, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
        Column(verticalArrangement = Arrangement.spacedBy(RIVAL_GROUP_GAP)) {
            var entrance = 0
            instruments.forEachIndexed { section, instrument ->
                Column(verticalArrangement = Arrangement.spacedBy(RIVAL_ROW_GAP)) {
                    RivalSectionHeader(instrument.label, Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, entrance++)), instrument = instrument)
                    repeat(fit.cards) { card ->
                        val slot = section * fit.cards + card
                        val delay = FirstRunEntrance.rowDelay(id, entrance++)
                        DemoSlot(pools[slot][rotation.positions[slot]], fade, slot, Modifier.demoEntrance(delay)) { entry ->
                            RivalRow(entry, onClick = null)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Web `RivalsDetailDemo`: one real Rival Detail category (its tinted section header and real
 * [RivalSongRow]s on catalogue songs) changing every few seconds; skeleton rows until real songs
 * arrive.
 */
@Composable
private fun RivalsDetailDemo(running: Boolean) {
    val id = "rivals-detail"
    val pool = demoPool()
    if (!pool.rotates) {
        DemoPlaceholderRows(id)
        return
    }
    val catalog = LocalFirstRunDemoCatalog.current.songs
    val dataSaver = rememberDataSaver()
    val categories = FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(DETAIL_ROWS) }) { rows ->
        var category by remember(rows) { mutableIntStateOf(0) }
        var songs by remember(pool, rows) { mutableStateOf(FirstRunWindowRotation(pool, rows)) }
        val fade = remember { DemoFade() }
        DemoTicker(running, fade, plan = { listOf(0) }, commit = {
            category = (category + 1) % categories.size
            songs = songs.advanced()
        })
        DemoSlot(category to songs.rows, fade, 0) { (index, shownSongs) ->
            val shown = categories[index]
            Column(verticalArrangement = Arrangement.spacedBy(RIVAL_ROW_GAP)) {
                RivalSectionHeader(
                    shown.title,
                    Modifier.demoEntrance(0).testTag("fst.first-run.demo.category"),
                    titleColor = categoryColor(shown.sentiment),
                )
                shownSongs.zip(shown.ranks).forEachIndexed { row, (song, rank) ->
                    RivalSongRow(
                        song = rank.comparison(song),
                        catalogSong = catalog?.firstOrNull { it.songId == song.id },
                        artUrl = song.artUrl.takeUnless { dataSaver },
                        playerName = PLAYER_NAME,
                        rivalName = FirstRunDemoPools.DETAIL_RIVAL,
                        onClick = null,
                        modifier = Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, row, lead = 1)),
                    )
                }
            }
        }
    }
}

/** Gap between rival rows (the real Rivals list's 8 dp). */
private val RIVAL_ROW_GAP = 8.dp

/** Gap between rival groups and sections (web `Gap.md`). */
private val RIVAL_GROUP_GAP = 12.dp

/** Web rival demo labels. */
private const val ABOVE_YOU = "Above You"
private const val BELOW_YOU = "Below You"

/** The player's name in the demo comparisons. */
private const val PLAYER_NAME = "You"

/** Most top players the hub's Leaderboards card shows above the player's row (web `CompeteHubDemo`). */
private const val HUB_RANKING_ROWS = 4

/** Most songs the Rival Detail demo shows (web: four per category). */
private const val DETAIL_ROWS = 4
// endregion

// region Infinite scroll

/**
 * Real Suggestions cards scrolling upward forever at the web's 30 dp/s (web
 * `InfiniteScrollDemo`): the card list is drawn twice and wraps at one copy's height, under the
 * scroll-edge ramp (bottom from the start, top once it moves; hard edges per `scroll-edge` R7).
 * It holds still until real songs arrive, off the settled page, behind a newer modal, with the
 * app in the background or Data Saver on, and under reduce motion. The offset is read only while
 * drawing, so scrolling never recomposes the cards.
 *
 * @param active Whether the slide is the settled current page.
 */
@Composable
internal fun InfiniteSuggestionsDemo(active: Boolean) {
    val id = "suggestions-infinite-scroll"
    val pool = demoPool()
    if (!pool.rotates) {
        DemoPlaceholderRows(id)
        return
    }
    val dataSaver = rememberDataSaver()
    val cards = remember(pool) { FirstRunDemoSuggestionTemplate.TEMPLATES.mapIndexed { index, template -> demoSuggestionCard(index, template, pool) } }
    val artworkUrl: (String?) -> String? = remember(dataSaver) { { url -> url.takeUnless { dataSaver } } }
    val running = active && !LocalFestivalAccessibility.current.reduceMotion && rememberDemoRotationAllowed() && !coveredByModal()
    val density = LocalDensity.current
    var loopDp by remember { mutableFloatStateOf(0f) }
    val offset = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(running, loopDp) {
        if (!running || loopDp <= 0f) return@LaunchedEffect
        delay(FirstRunEntrance.SCROLL_START_MS)
        val from = offset.floatValue
        val start = withFrameMillis { it }
        while (true) {
            withFrameMillis { now -> offset.floatValue = (from + FirstRunInfiniteScroll.offset(now - start, loopDp)) % loopDp }
        }
    }
    val hardEdge = rememberScrollEdgeHardEdge()
    val gap = 12.dp
    Box(
        Modifier.fillMaxWidth().height(FirstRunDemoFit.FRAME_DP.dp).clipToBounds()
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                if (!hardEdge) {
                    val bottom = ScrollEdgeFade.BOTTOM_DP.dp.toPx()
                    drawScrollEdgeRamp(size.height, size.height - bottom)
                    if (offset.floatValue > 0f) drawScrollEdgeRamp(0f, ScrollEdgeFade.TOP_DP.dp.toPx())
                }
            }
            .testTag("fst.first-run.demo.infinite-scroll"),
    ) {
        Column(
            Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top, unbounded = true).graphicsLayer { translationY = -offset.floatValue.dp.toPx() },
            verticalArrangement = Arrangement.spacedBy(gap),
        ) {
            repeat(2) { copy ->
                Column(
                    Modifier.then(if (copy == 0) Modifier.onSizeChanged { loopDp = with(density) { it.height.toDp().value } + gap.value } else Modifier),
                    verticalArrangement = Arrangement.spacedBy(gap),
                ) {
                    cards.forEachIndexed { index, card ->
                        val entrance = if (copy == 0) Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index)) else Modifier
                        SuggestionCardView(card, narrow = true, artworkUrl = artworkUrl, onSong = {}, modifier = entrance)
                    }
                }
            }
        }
    }
}

/**
 * One demo Suggestions card from a web template, built through the real row presentation.
 *
 * @param index Template index.
 * @param template Template.
 * @param pool Real songs.
 * @return Card.
 */
private fun demoSuggestionCard(index: Int, template: FirstRunDemoSuggestionTemplate, pool: List<FirstRunDemoSong>, count: Int = CATEGORY_CARD_ROWS): SuggestionCard {
    val type = when {
        template.key.startsWith("pct_push") -> SuggestionCategoryType.PercentilePush
        template.key.startsWith("unplayed") -> SuggestionCategoryType.Unplayed
        else -> SuggestionCategoryType.NearFC
    }
    val items = template.items(index, pool, count = count).map { item ->
        val number = item.detail?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull()
        SuggestionSongItem(
            song = Song(songId = item.song.id, title = item.song.title, artist = item.song.artist, year = item.song.year, albumArt = item.song.artUrl),
            instrument = item.instrument ?: template.instrument,
            percent = number,
            percentileDisplay = item.detail,
        )
    }
    val category = SuggestionCategory(template.key, template.title, template.description, type, template.instrument, items)
    val rows = items.map { item ->
        SuggestionRow(item.id, SuggestionRowPresentation.create(category, item, null, ICON_INSTRUMENTS), item.song.songId, item.song.albumArt, usesKeyboardIcon = false)
    }
    return SuggestionCard("fst-first-run-${template.key}", category, rows)
}

/** Songs a demo Suggestions card lists at most (web `CategoryCardDemo`). */
private const val CATEGORY_CARD_ROWS = 3

// endregion
