package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.Ease
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import com.festivalscoretracker.android.core.shell.ChartPage
import com.festivalscoretracker.android.core.shell.ChartPageMotion
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// region Chart page slide

/**
 * A paged chart's animated window (`load-transition` R12, issue #593). Read [start],
 * [valueTop] and [labelShift] only while drawing or placing, so a slide redraws the chart
 * and re-places its date row without recomposing anything.
 */
@Stable
class ChartPageSlide internal constructor(
    private val target: Int,
    private val targetTop: Float,
    private val instant: Boolean,
    private val position: Animatable<Float, AnimationVector1D>,
    private val top: Animatable<Float, AnimationVector1D>,
) {
    /** Fractional index of the first band (the window's start at rest). */
    val start: Float get() = if (instant) target.toFloat() else position.value

    /** The value axis top the marks are drawn against (eases to the new window's top). */
    val valueTop: Float get() = if (instant) targetTop else top.value

    /** Bands the date row trails its laid-out window by ([ChartPageMotion.labelShift]). */
    val labelShift: Float get() = ChartPageMotion.labelShift(target, start)
}

/**
 * The one paging motion for graph card charts: when [page]'s start changes, the window slides
 * there over [ChartPageMotion.SLIDE_MILLIS] on the web `ease` curve while the value axis top
 * eases to [valueTop], like iOS `PlayerProfileCharts` `move(to:)` with the web
 * `CHART_ANIM_DURATION`. A newer page change retargets the running slide from where it is. A new
 * band count, point count or [key] (another chart, width or data) re-fits at once, and system or
 * in-app reduced motion pages at once (R6).
 *
 * @param page The window to show.
 * @param valueTop The new window's value axis top (0 when the bars or line have no scale).
 * @param key Identity of the chart's data; a change re-fits without sliding.
 * @return The slide to draw from.
 */
@Composable
fun rememberChartPageSlide(page: ChartPage, valueTop: Float, key: Any?): ChartPageSlide {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val position = remember(page.bands, page.count, key) { Animatable(page.start.toFloat()) }
    val top = remember(page.bands, page.count, key) { Animatable(valueTop) }
    val drawn = remember(page.bands, page.count, key) { arrayOf(page) }
    LaunchedEffect(position, page.start, valueTop, reduceMotion) {
        val plan = ChartPageMotion.plan(drawn[0], page, reduceMotion)
        drawn[0] = page
        if (plan == ChartPageMotion.Plan.Slide) {
            val spec = tween<Float>(ChartPageMotion.SLIDE_MILLIS, easing = Ease)
            coroutineScope {
                launch { position.animateTo(page.start.toFloat(), spec) }
                launch { top.animateTo(valueTop, spec) }
            }
        } else {
            position.snapTo(page.start.toFloat())
            top.snapTo(valueTop)
        }
    }
    return ChartPageSlide(page.start, valueTop, reduceMotion, position, top)
}

// endregion
