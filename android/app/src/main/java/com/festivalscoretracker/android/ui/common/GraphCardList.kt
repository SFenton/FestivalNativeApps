package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Ease
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.shell.GraphListPhase
import com.festivalscoretracker.android.core.shell.GraphListPolicy
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.delay

// region Graph card list

/** Test-only semantics: the list's [GraphListPhase]. Not exposed to accessibility services. */
internal val GraphListPhaseKey = SemanticsPropertyKey<GraphListPhase>("GraphListPhase")

/**
 * The animated list under a graph card (web `GraphCard` list + `useListAnimation`, issue #169).
 * When the rows change, the old rows fade out with a 40 ms stagger, the list eases to its new
 * height (300 ms) with the rows hidden, then the new rows fade in with a 60 ms stagger
 * ([GraphListPolicy]). A newer change cancels the running one; rows that are the same as the
 * last requested ones ([identity]) update in place. Reduced motion swaps at once.
 *
 * @param items Rows to show.
 * @param identity Row identity (web `listIdentity`); equal identities mean the same row.
 * @param modifier Modifier (carries the list's test tag).
 * @param spacing Gap between rows.
 * @param row One row.
 */
@Composable
fun <T> GraphCardList(
    items: List<T>,
    identity: (T) -> Any,
    modifier: Modifier = Modifier,
    spacing: Dp = 6.dp,
    row: @Composable (item: T, index: Int) -> Unit,
) {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val keys = items.map(identity)
    val latest by rememberUpdatedState(items)
    var shown by remember { mutableStateOf(items) }
    var requested by remember { mutableStateOf(keys) }
    var phase by remember { mutableStateOf(GraphListPhase.Idle) }
    LaunchedEffect(keys, reduceMotion) {
        // A newer change relaunches this effect, cancelling the running sequence (web clears its timers).
        val plan = GraphListPolicy.plan(same = keys == requested, shownCount = shown.size, reduceMotion = reduceMotion)
        requested = keys
        when (plan) {
            GraphListPolicy.Plan.Keep, GraphListPolicy.Plan.Instant -> {
                shown = latest
                phase = GraphListPhase.Idle
            }
            GraphListPolicy.Plan.Enter -> {
                shown = latest
                phase = GraphListPhase.In
                delay(GraphListPolicy.inMillis(latest.size).toLong())
                phase = GraphListPhase.Idle
            }
            GraphListPolicy.Plan.Swap -> {
                val wait = GraphListPolicy.outWait(phase, shown.size)
                if (wait > 0) {
                    phase = GraphListPhase.Out
                    delay(wait.toLong())
                }
                shown = latest
                phase = GraphListPhase.Resize
                delay(GraphListPolicy.HEIGHT_MS.toLong())
                phase = GraphListPhase.In
                delay(GraphListPolicy.inMillis(latest.size).toLong())
                phase = GraphListPhase.Idle
            }
        }
    }
    // Same rows as requested and settled: draw the latest values; otherwise the sequence's rows.
    val rendered = if (phase == GraphListPhase.Idle && keys == requested) items else shown
    Column(
        modifier
            .semantics { this[GraphListPhaseKey] = phase }
            .then(if (reduceMotion) Modifier else Modifier.animateContentSize(tween(GraphListPolicy.HEIGHT_MS, easing = Ease))),
        verticalArrangement = Arrangement.spacedBy(spacing),
    ) {
        rendered.forEachIndexed { index, item ->
            key(identity(item), index) {
                GraphListRow(phase, index) { row(item, index) }
            }
        }
    }
}

/**
 * One row's fade and drift for the list [phase].
 *
 * @param phase The list's phase.
 * @param index Row position (stagger).
 * @param content The row.
 */
@Composable
private fun GraphListRow(phase: GraphListPhase, index: Int, content: @Composable () -> Unit) {
    // Rows installed mid-sequence start hidden; rows on screen at first composition start shown.
    val alpha = remember { Animatable(if (phase == GraphListPhase.Idle) 1f else 0f) }
    LaunchedEffect(phase) {
        when (phase) {
            GraphListPhase.Idle -> alpha.snapTo(1f)
            GraphListPhase.Resize -> alpha.snapTo(0f)
            GraphListPhase.Out -> {
                delay(GraphListPolicy.rowOutDelay(index).toLong())
                alpha.animateTo(0f, tween(GraphListPolicy.ROW_OUT_MS, easing = EaseIn))
            }
            GraphListPhase.In -> {
                alpha.snapTo(0f)
                delay(GraphListPolicy.rowInDelay(index).toLong())
                alpha.animateTo(1f, tween(GraphListPolicy.ROW_IN_MS, easing = EaseOut))
            }
        }
    }
    Box(
        Modifier.graphicsLayer {
            this.alpha = alpha.value
            translationY = GraphListPolicy.rowDriftDp(phase, alpha.value).dp.toPx()
        },
    ) { content() }
}

// endregion
