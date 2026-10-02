package com.festivalscoretracker.android.ui.firstrun

import android.net.ConnectivityManager
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil3.compose.AsyncImage
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
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.songs.MetadataPill
import com.festivalscoretracker.android.ui.songs.StatusChips
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import java.text.NumberFormat
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

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
 * back in. Without [fade], or under reduce motion, the data swaps at once (rows then
 * cross-fade through [DemoSlot]). Stopping mid-fade still completes the swap.
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
    val currentPlan by rememberUpdatedState(plan)
    val currentCommit by rememberUpdatedState(commit)
    LaunchedEffect(running, reduceMotion, fade) {
        if (!running) return@LaunchedEffect
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
 * positive = down, as it fades out); under reduce motion a new [value] cross-fades in.
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
        Crossfade(targetState = value, animationSpec = tween(FirstRunDemoTiming.FADE_MS), label = "fre-demo-swap", modifier = modifier) { content(it) }
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

/** Decorative album art (shared Coil loader); none under Data Saver or before the catalogue loads. */
@Composable
private fun DemoArt(url: String?, size: Dp) {
    val modifier = Modifier.size(size).clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted)
    if (url != null && !rememberDataSaver()) {
        AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
    } else {
        Box(modifier)
    }
}

/** A demo song row (web `DemoSongRow` + `SongInfo`); a placeholder shows redacted bars. */
@Composable
private fun DemoSongRow(song: FirstRunDemoSong, artSize: Dp = 36.dp, trailing: @Composable () -> Unit = {}, below: (@Composable () -> Unit)? = null) {
    DemoCard {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                DemoArt(song.artUrl, artSize)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    if (song.isPlaceholder) {
                        RedactedBar(0.7f, 14.dp)
                        RedactedBar(0.45f, 10.dp)
                    } else {
                        Text(song.title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("fst.first-run.demo.song.${song.id}"))
                        val subtitle = listOfNotNull(song.artist, song.year?.toString()).joinToString(" · ")
                        Text(subtitle, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                trailing()
            }
            below?.invoke()
        }
    }
}

/** A compact song title, or a redacted bar for a placeholder. */
@Composable
private fun DemoSongTitle(song: FirstRunDemoSong, modifier: Modifier) {
    if (song.isPlaceholder) {
        Box(modifier) { RedactedBar(0.6f, 10.dp) }
    } else {
        Text(song.title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = modifier.testTag("fst.first-run.demo.song.${song.id}"))
    }
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
    running: Boolean,
    visible: Int,
    trailing: @Composable (index: Int, song: FirstRunDemoSong) -> Unit = { _, _ -> },
    below: (@Composable (FirstRunDemoSong) -> Unit)? = null,
) {
    val pool = demoPool()
    var rotation by remember(pool) { mutableStateOf(FirstRunRowRotation.start(pool, visible) { it.id }) }
    val fade = remember { DemoFade() }
    DemoTicker(running && pool.rotates, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rotation.rows.forEachIndexed { index, song ->
            DemoSlot(song, fade, index) { shown ->
                DemoSongRow(shown, trailing = { trailing(index, shown) }, below = below?.let { { it(shown) } })
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
        "songs-song-list" -> RotatingSongRows(running, visible = 3)
        "songs-icons" -> RotatingSongRows(running, visible = 2, below = { song -> if (!song.isPlaceholder) IconChips(song) })
        "songs-metadata" -> MetadataDemo(running)
        "statistics-top-songs" -> RotatingSongRows(running, visible = 3, trailing = { index, song ->
            if (!song.isPlaceholder) {
                val label = FirstRunDemoPools.topSongPercentile(index)
                MetadataPill(SongMetadataPill(MetadataField.Percentile, label, label, percentile = FirstRunDemoPools.percentileTier(label)), song.id)
            }
        })
        "songinfo-bar-select" -> BarSelectDemo(running)
        "suggestions-category-card" -> CategoryCardDemo(running)
        "leaderboards-experimental-metrics" -> ExperimentalMetricsDemo(running)
        "compete-hub" -> CompeteHubDemo(running)
        "compete-rivals", "rivals-overview" -> RivalGroupsDemo(running, perGroup = 2)
        "rivals-instruments" -> RivalsInstrumentsDemo(running)
        "rivals-detail" -> RivalsDetailDemo(running)
    }
}

/** Instruments the icons demo shows (the default visible charts' order). */
private val ICON_INSTRUMENTS = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals, Instrument.ProLead, Instrument.ProBass)

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
private fun MetadataDemo(running: Boolean) {
    val pool = demoPool()
    var rotation by remember(pool) { mutableStateOf(FirstRunMetadataRotation.start(pool, 2)) }
    val fade = remember { DemoFade() }
    DemoTicker(running && pool.rotates, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rotation.rows.forEachIndexed { index, row ->
            DemoSlot(row, fade, index) { shown ->
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

@Composable
private fun BarSelectDemo(running: Boolean) {
    var selected by remember { mutableIntStateOf(0) }
    val fade = remember { DemoFade() }
    val bars = FirstRunDemoBars.BARS
    DemoTicker(
        running,
        fade,
        intervalMs = FirstRunDemoTiming.BAR_SELECT_INTERVAL_MS,
        fadeMs = FirstRunDemoTiming.BAR_SELECT_FADE_MS,
        plan = { listOf(0) },
        commit = { selected = (selected + 1) % bars.size },
    )
    DemoCard {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(Modifier.fillMaxWidth().height(110.dp)) {
                val gap = 24.dp.toPx()
                val width = (size.width - gap * (bars.size - 1)) / bars.size
                bars.forEachIndexed { index, bar ->
                    val height = size.height * bar.accuracy / 100f
                    val x = index * (width + gap)
                    val color = if (bar.fullCombo) BrandTokens.gold else BrandTokens.accentBlue
                    drawRoundRect(color, Offset(x, size.height - height), Size(width, height), CornerRadius(6f, 6f))
                    if (index == selected) {
                        drawRoundRect(BrandTokens.accentPurple, Offset(x, size.height - height), Size(width, height), CornerRadius(6f, 6f), style = Stroke(3.dp.toPx()))
                    }
                }
            }
            DemoSlot(selected, fade, 0) { index ->
                val bar = bars[index]
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().testTag("fst.first-run.demo.bar-detail")) {
                    Text(NumberFormat.getIntegerInstance().format(bar.score), color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Text(if (bar.fullCombo) "${bar.accuracy}% FC" else "${bar.accuracy}%", color = if (bar.fullCombo) BrandTokens.gold else BrandTokens.textPrimary, modifier = Modifier.padding(end = 12.dp))
                    Text(bar.date, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun CategoryCardDemo(running: Boolean) {
    val pool = demoPool()
    var template by remember { mutableIntStateOf(0) }
    val fade = remember { DemoFade() }
    val templates = FirstRunDemoSuggestionTemplate.TEMPLATES
    DemoTicker(running, fade, plan = { listOf(0) }, commit = { template = (template + 1) % templates.size })
    DemoSlot(template, fade, 0, shift = FirstRunDemoTiming.CARD_DROP_DP.dp) { index ->
        val card = templates[index]
        DemoCard(border = BrandTokens.accentPurple) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(card.title, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).testTag("fst.first-run.demo.category"))
                    card.instrument?.let { InstrumentIcon(it, size = 22.dp, decorative = true) }
                }
                Text(card.description, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                card.items(index, pool, count = 3).forEach { item ->
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                        DemoArt(item.song.artUrl, 28.dp)
                        DemoSongTitle(item.song, Modifier.weight(1f).padding(horizontal = 8.dp))
                        item.detail?.let { Text(it, color = BrandTokens.gold, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(end = 6.dp)) }
                        item.instrument?.let { InstrumentIcon(it, size = 18.dp, decorative = true) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ExperimentalMetricsDemo(running: Boolean) {
    var selected by remember { mutableIntStateOf(0) }
    val metrics = FirstRunDemoPools.EXPERIMENTAL_METRICS
    DemoTicker(running, fade = null, plan = { listOf(0) }, commit = { selected = (selected + 1) % metrics.size })
    DemoCard {
        Column {
            Text("Rank By", color = BrandTokens.textPrimary, style = MaterialTheme.typography.labelLarge)
            metrics.forEachIndexed { index, (label, description) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = index == selected, onClick = null, modifier = Modifier.testTag(if (index == selected) "fst.first-run.demo.metric.selected" else "fst.first-run.demo.metric"))
                    Column(Modifier.padding(start = 8.dp)) {
                        Text(label, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium)
                        Text(description, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** A compact rivals/rankings row. */
@Composable
private fun DemoNameRow(leading: String, name: String, trailing: String, highlight: Boolean = false, leadingColor: Color = BrandTokens.textSecondary) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth()
            .background(if (highlight) BrandTokens.accentPurple.copy(alpha = 0.5f) else BrandTokens.surfaceFrosted, RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 5.dp),
    ) {
        Text(leading, color = leadingColor, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(end = 10.dp))
        Text(name, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).testTag("fst.first-run.demo.name"))
        Text(trailing, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun RivalRows(title: String, rivals: List<FirstRunDemoRival>, above: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, color = if (above) BrandTokens.statusGreen else BrandTokens.statusRed, style = MaterialTheme.typography.labelMedium)
        rivals.forEach { DemoNameRow(if (above) "▲" else "▼", it.name, "${it.shared} songs", leadingColor = if (above) BrandTokens.statusGreen else BrandTokens.statusRed) }
    }
}

@Composable
private fun CompeteHubDemo(running: Boolean) {
    var rivalsLayout by remember { mutableStateOf(false) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { listOf(0) }, commit = { rivalsLayout = !rivalsLayout })
    DemoSlot(rivalsLayout, fade, 0, shift = (-FirstRunDemoTiming.HUB_RISE_DP).dp) { rivals ->
        if (rivals) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                RivalRows("Above", FirstRunDemoPools.RIVALS_ABOVE.take(2), above = true)
                RivalRows("Below", FirstRunDemoPools.RIVALS_BELOW.take(2), above = false)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                (FirstRunDemoPools.RANKINGS.take(4) + FirstRunDemoPools.PLAYER).forEach {
                    DemoNameRow("#${it.rank}", it.name, it.rating, highlight = it.isPlayer)
                }
            }
        }
    }
}

@Composable
private fun RivalGroupsDemo(running: Boolean, perGroup: Int) {
    var above by remember { mutableStateOf(FirstRunWindowRotation(FirstRunDemoPools.RIVALS_ABOVE, perGroup)) }
    var below by remember { mutableStateOf(FirstRunWindowRotation(FirstRunDemoPools.RIVALS_BELOW, perGroup)) }
    var nextAbove by remember { mutableStateOf(true) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { listOf(if (nextAbove) 0 else 1) }, commit = {
        if (nextAbove) above = above.advanced() else below = below.advanced()
        nextAbove = !nextAbove
    })
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DemoSlot(above.rows, fade, 0, shift = FirstRunDemoTiming.GROUP_DROP_DP.dp) { RivalRows("Above you", it, above = true) }
        DemoSlot(below.rows, fade, 1, shift = FirstRunDemoTiming.GROUP_DROP_DP.dp) { RivalRows("Below you", it, above = false) }
    }
}

@Composable
private fun RivalsInstrumentsDemo(running: Boolean) {
    val instruments = FirstRunDemoPools.INSTRUMENT_RIVAL_ORDER
    val pools = remember {
        instruments.flatMap { instrument -> FirstRunDemoPools.INSTRUMENT_RIVALS.getValue(instrument).let { listOf(it.first, it.second) } }
    }
    var rotation by remember { mutableStateOf(FirstRunSlotRotation(pools.map { it.size })) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { rotation.nextIndices() }, commit = { rotation = rotation.swapped(it) })
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        instruments.forEachIndexed { column, instrument ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                InstrumentIcon(instrument, size = 28.dp, decorative = true)
                listOf(column * 2, column * 2 + 1).forEach { slot ->
                    val above = slot % 2 == 0
                    DemoSlot(pools[slot][rotation.positions[slot]], fade, slot) { rival ->
                        Column(
                            Modifier.fillMaxWidth()
                                .background(BrandTokens.surfaceFrosted, RoundedCornerShape(8.dp))
                                .border(1.dp, if (above) BrandTokens.statusGreen else BrandTokens.statusRed, RoundedCornerShape(8.dp))
                                .padding(horizontal = 6.dp, vertical = 4.dp),
                        ) {
                            Text(if (above) "▲ Above" else "▼ Below", color = if (above) BrandTokens.statusGreen else BrandTokens.statusRed, style = MaterialTheme.typography.labelSmall)
                            Text(rival.name, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("fst.first-run.demo.name"))
                            Text("${rival.shared} songs", color = BrandTokens.textSecondary, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RivalsDetailDemo(running: Boolean) {
    val pool = demoPool()
    val categories = FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES
    var category by remember { mutableIntStateOf(0) }
    var songs by remember(pool) { mutableStateOf(FirstRunWindowRotation(pool, 4)) }
    val fade = remember { DemoFade() }
    DemoTicker(running, fade, plan = { listOf(0) }, commit = {
        category = (category + 1) % categories.size
        songs = songs.advanced()
    })
    DemoSlot(category to songs.rows, fade, 0) { (index, rows) ->
        val shown = categories[index]
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(shown.title, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).testTag("fst.first-run.demo.category"))
                Text("vs ${FirstRunDemoPools.DETAIL_RIVAL}", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
            }
            rows.zip(shown.ranks).forEach { (song, rank) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().background(BrandTokens.surfaceFrosted, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    DemoArt(song.artUrl, 28.dp)
                    DemoSongTitle(song, Modifier.weight(1f).padding(horizontal = 8.dp))
                    Text(
                        "#${rank.userRank} vs #${rank.rivalRank}",
                        color = if (rank.playerWins) BrandTokens.statusGreen else BrandTokens.statusRed,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}

// endregion
