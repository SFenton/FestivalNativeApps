package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.flow.takeWhile
import kotlin.math.abs

// region Fade in on load

/**
 * Fade content in (with the web's short upward drift, `fadeInUp`) when it finishes
 * loading, like the web's staggered row entrances.
 *
 * Content that is already loaded the first time this modifier is composed (a cached
 * card, or a row scrolled back into view) appears immediately, as the web skips its
 * animation for cached data. Inside a page that provides [LocalFadeInWindow], content
 * that finishes loading after the page has scrolled also appears immediately, so only
 * what was visible at load fades. Remove animations / Reduce Motion
 * ([LocalFestivalAccessibility]) shows content at once. The animated values are read
 * only in the graphics layer, so the fade never recomposes the content.
 *
 * Place it on a container that stays composed while loading (the skeleton lives
 * outside it), so it sees the loading → loaded transition.
 *
 * @param isLoaded Whether the content is ready to show.
 * @param delayMillis Delay before the fade starts (stagger between siblings).
 * @return Modifier.
 */
fun Modifier.festivalFadeIn(isLoaded: Boolean, delayMillis: Int = 0): Modifier = composed {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val window = LocalFadeInWindow.current
    val progress = remember { Animatable(if (isLoaded) 1f else 0f) }
    LaunchedEffect(isLoaded, reduceMotion) {
        when {
            !isLoaded -> progress.snapTo(0f)
            reduceMotion -> progress.snapTo(1f)
            // The page has scrolled: content that finishes loading now shows in place.
            // A fade that already started keeps running (this is read only when it starts).
            window?.isOpen == false -> progress.snapTo(1f)
            else -> progress.animateTo(1f, tween(FADE_IN_MILLIS, delayMillis, FadeInEasing))
        }
    }
    val drift = FADE_IN_DRIFT_DP.dp
    graphicsLayer {
        val value = fadeInAlpha(progress.value, isLoaded, reduceMotion)
        alpha = value
        translationY = (1f - value) * drift.toPx()
    }
}

/**
 * Opacity drawn for a fade: fully shown under Reduce Motion once loaded, else the
 * animation's progress.
 *
 * @param progress Animation progress, 0 to 1.
 * @param isLoaded Whether the content is ready.
 * @param reduceMotion Remove animations / Reduce Motion.
 * @return Alpha.
 */
internal fun fadeInAlpha(progress: Float, isLoaded: Boolean, reduceMotion: Boolean): Float =
    if (reduceMotion && isLoaded) 1f else progress.coerceIn(0f, 1f)

/**
 * Whether freshly loaded content should now be shown: false for one frame after a
 * loading to loaded transition (so [festivalFadeIn] on newly composed children sees
 * the change and fades them in), true at once for content that was already loaded or
 * when Remove animations / Reduce Motion is on or the page's [FadeInWindow] has closed.
 *
 * @param isLoaded Whether the content is ready.
 * @return Value to pass to [festivalFadeIn].
 */
@Composable
fun rememberRevealed(isLoaded: Boolean): Boolean {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val window = LocalFadeInWindow.current
    var revealed by remember { mutableStateOf(isLoaded) }
    LaunchedEffect(isLoaded) { revealed = isLoaded }
    // No fade to set up under Remove animations or once the page has scrolled: show
    // loaded content in its first frame.
    return if (reduceMotion || window?.isOpen == false) isLoaded else revealed
}

/**
 * Stagger delay for the item at [index] (web `staggerDelay`), capped so long lists
 * finish promptly.
 *
 * @param index Zero-based sibling index.
 * @return Delay in milliseconds.
 */
fun fadeInStagger(index: Int): Int = index.coerceIn(0, FADE_IN_MAX_STAGGERED) * FADE_IN_STAGGER_MILLIS

/** Fade duration (web `FADE_DURATION`). */
const val FADE_IN_MILLIS = 400

/** Delay between staggered siblings (web `STAGGER_INTERVAL`). */
const val FADE_IN_STAGGER_MILLIS = 125

/** Siblings after this index start together. */
private const val FADE_IN_MAX_STAGGERED = 12

/** Upward drift at the start of the fade (web `fadeInUp`: `translateY(12px)`). */
private const val FADE_IN_DRIFT_DP = 12

/** Web `fadeInUp` timing function: CSS `ease-out`, `cubic-bezier(0, 0, 0.58, 1)`. */
internal val FadeInEasing = CubicBezierEasing(0f, 0f, 0.58f, 1f)

// endregion

// region Page fade window

/**
 * A page's load-only fade window (iOS `FestivalFadeInScope`): open while the page rests
 * where it loaded, closed for good once a scroll moves it. While closed, [festivalFadeIn]
 * and [rememberRevealed] show content that finishes loading in place, so a section that
 * starts loading when it is scrolled into view (Player Profile rank history and bands, a
 * Leaderboards card still loading) does not fade in under the reader. Fades already
 * running finish.
 *
 * Only movement while the list reports a scroll in progress closes the window; while idle
 * the resting position follows the list, so items inserted above (which shift the first
 * visible index) do not close it.
 *
 * @param thresholdPx Scroll distance within the resting item that still counts as at
 *   rest (absorbs sub-pixel settling).
 */
class FadeInWindow(private val thresholdPx: Float) {
    private var restingIndex: Int? = null
    private var restingOffset = 0

    /** Whether content may still fade in. */
    var isOpen: Boolean = true
        private set

    /**
     * Record the list's position.
     *
     * @param index First visible item index.
     * @param offsetPx Scroll offset within that item, in pixels.
     * @param scrolling Whether a scroll (gesture, fling or animated jump) is in progress.
     * @return Whether the window is still open.
     */
    fun note(index: Int, offsetPx: Int, scrolling: Boolean): Boolean {
        if (!isOpen) return false
        val rest = restingIndex
        when {
            rest == null || !scrolling -> {
                restingIndex = index
                restingOffset = offsetPx
            }
            index != rest || abs(offsetPx - restingOffset) > thresholdPx -> isOpen = false
        }
        return isOpen
    }
}

/** The enclosing page's fade window; null outside a page that limits fades to its load. */
val LocalFadeInWindow = staticCompositionLocalOf<FadeInWindow?> { null }

/**
 * A fade window that closes once [state] scrolls; provide it with [LocalFadeInWindow].
 *
 * @param state The page's list.
 * @param reset Reopens the window when it changes (another player's page in the same list).
 * @return Window.
 */
@Composable
fun rememberFadeInWindow(state: LazyListState, reset: Any? = null): FadeInWindow =
    rememberFadeInWindow(state, reset) { Triple(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset, state.isScrollInProgress) }

/**
 * A fade window that closes once [state] scrolls; provide it with [LocalFadeInWindow].
 *
 * @param state The page's grid.
 * @param reset Reopens the window when it changes (another player's page in the same grid).
 * @return Window.
 */
@Composable
fun rememberFadeInWindow(state: LazyStaggeredGridState, reset: Any? = null): FadeInWindow =
    rememberFadeInWindow(state, reset) { Triple(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset, state.isScrollInProgress) }

@Composable
private fun rememberFadeInWindow(key: Any, reset: Any?, position: () -> Triple<Int, Int, Boolean>): FadeInWindow {
    val threshold = with(LocalDensity.current) { FADE_IN_SCROLL_THRESHOLD_DP.dp.toPx() }
    val window = remember(key, reset) { FadeInWindow(threshold) }
    LaunchedEffect(window) {
        snapshotFlow(position)
            .takeWhile { (index, offset, scrolling) -> window.note(index, offset, scrolling) }
            .collect {}
    }
    return window
}

/** Scroll that closes a page's fade window (iOS `FestivalFadeInScope`: 4 pt). */
private const val FADE_IN_SCROLL_THRESHOLD_DP = 4

// endregion
