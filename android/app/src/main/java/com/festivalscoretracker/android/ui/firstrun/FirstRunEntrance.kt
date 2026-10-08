package com.festivalscoretracker.android.ui.firstrun

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoFit
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import kotlin.math.ceil
import kotlinx.coroutines.launch

// region Slide entrance

/**
 * Whether the slide around a demo has been revealed: false while the slide is off screen or
 * still being swiped to, true once it settles (or at once under Reduce Motion). Each visit
 * replays the entrance, like the web carousel remounting the slide. Defaults to true, so a demo
 * composed outside the carousel (tests, previews) is simply shown.
 */
internal val LocalFirstRunReveal = compositionLocalOf { true }

/**
 * One step of a demo's web `fadeInUp` cascade (issue #380) through the shared
 * `load-transition` fade ([festivalFadeIn]): 400 ms, 12 dp rise, delayed by [delayMillis] from
 * the slide settling. Its own animation, never a page window's rush (the dialog does not scroll
 * content into view), and still under Reduce Motion.
 *
 * @param delayMillis Delay from the slide settling (see
 *   [com.festivalscoretracker.android.core.firstrun.FirstRunEntrance.rowDelay]).
 * @return Modifier.
 */
internal fun Modifier.demoEntrance(delayMillis: Int = 0): Modifier = composed {
    festivalFadeIn(LocalFirstRunReveal.current, delayMillis, rushOnScroll = false)
}

// endregion

// region Fitting

/**
 * The demo's height budget: the 220 dp frame, or less when the frame is given less.
 *
 * @param constraints Incoming constraints.
 * @param framePx Frame height in px.
 * @return Budget in px.
 */
private fun budget(constraints: Constraints, framePx: Int): Int =
    if (constraints.hasBoundedHeight) minOf(framePx, constraints.maxHeight) else framePx

/**
 * True inside [DemoFitFirst]'s measuring probes: demo timers and pulses hold still there, so only
 * the shown copy animates.
 */
internal val LocalDemoProbe = staticCompositionLocalOf { false }

/** [DemoFitFirst]'s slot for the shown candidate (its state survives a change of candidate). */
private object ShownSlot

/**
 * A fitted candidate for one width and height budget.
 *
 * @property width Width it was fitted at, in px.
 * @property limit Height budget, in px.
 * @property pick Index of the candidate shown.
 */
private data class DemoFit(val width: Int, val limit: Int, val pick: Int)

/**
 * [DemoFitFirst]'s remembered fit and a counter bumped to measure again after probing.
 *
 * @property fit Last fit, or null to probe.
 * @property pass Measure trigger.
 */
private class DemoFitMemo(var fit: DemoFit? = null, val pass: MutableIntState = mutableIntStateOf(0))

/**
 * Shows the first of [candidates] whose content fits the demo frame whole, else the last (web
 * `useSlideHeight`: demos measure the slide and draw only whole rows, never a clipped or squashed
 * one). When the width or budget changes, each candidate is composed as a still, semantics-free
 * probe and measured at full height until one fits, so the real rows and controls decide how many
 * show at any width, font and density. The pick is remembered, so the probes are gone again after
 * the next measure; if the shown demo later outgrows the frame (a longer song swapped in) it
 * fits again.
 *
 * @param T Candidate type (row count, or rows plus an optional section).
 * @param candidates Candidates, most preferred first (see [FirstRunDemoFit.rowCandidates]).
 * @param modifier Modifier.
 * @param content Demo for one candidate.
 */
@Composable
internal fun <T> DemoFitFirst(candidates: List<T>, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    val memo = remember(candidates) { DemoFitMemo() }
    val scope = rememberCoroutineScope()
    // Read in composition and captured below, so each bump after probing makes a new measure
    // policy: the next measure skips the probes, which disposes them (a state read inside this
    // measure block alone did not schedule it again).
    val pass = memo.pass.intValue
    SubcomposeLayout(modifier) { constraints ->
        check(pass >= 0)
        val limit = budget(constraints, FirstRunDemoFit.FRAME_DP.dp.roundToPx())
        val open = constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity)
        val cached = memo.fit?.takeIf { it.width == constraints.maxWidth && it.limit == limit }
        val pick = cached?.pick ?: run {
            var found = candidates.lastIndex
            if (candidates.size > 1) {
                for ((index, candidate) in candidates.withIndex()) {
                    val probe = subcompose(index) {
                        CompositionLocalProvider(LocalDemoProbe provides true, LocalFirstRunReveal provides true) {
                            Box(Modifier.clearAndSetSemantics {}) { content(candidate) }
                        }
                    }
                    if ((probe.maxOfOrNull { it.measure(open).height } ?: 0) <= limit) {
                        found = index
                        break
                    }
                }
                scope.launch { memo.pass.intValue++ }
            }
            memo.fit = DemoFit(constraints.maxWidth, limit, found)
            found
        }
        val shown = subcompose(ShownSlot) { content(candidates[pick]) }.map { it.measure(open) }
        val height = shown.maxOfOrNull { it.height } ?: 0
        if (cached != null && height > limit && pick < candidates.lastIndex) {
            memo.fit = null
            scope.launch { memo.pass.intValue++ }
        }
        val width = (shown.maxOfOrNull { it.width } ?: 0).coerceIn(constraints.minWidth, constraints.maxWidth)
        layout(width, height.coerceAtLeast(constraints.minHeight)) { shown.forEach { it.placeRelative(0, 0) } }
    }
}

/**
 * The demo frame's safety net: a demo with a fixed structure (a chart card, rival groups) that is
 * taller than the frame at this width scales down uniformly from the top centre, like the
 * carousel's short-window scaling, instead of running into the slide title. Row lists fit with
 * [DemoFitFirst] first, so they never need it.
 *
 * @param content Demo.
 */
@Composable
internal fun DemoFrame(content: @Composable () -> Unit) {
    Layout(content = { Box(Modifier.testTag(DEMO_CONTENT_TAG)) { content() } }) { measurables, constraints ->
        val limit = budget(constraints, FirstRunDemoFit.FRAME_DP.dp.roundToPx())
        val placeable = measurables.single().measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
        val scale = FirstRunDemoFit.scale(placeable.height.toFloat(), limit.toFloat())
        val width = placeable.width.coerceIn(constraints.minWidth, constraints.maxWidth)
        layout(width, ceil(placeable.height * scale).toInt().coerceAtLeast(constraints.minHeight)) {
            placeable.placeWithLayer((width - placeable.width) / 2, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0.5f, 0f)
            }
        }
    }
}

/** Test tag of the demo inside [DemoFrame] (its layout size is the unscaled demo height). */
internal const val DEMO_CONTENT_TAG = "fst.first-run.demo.content"

// endregion
