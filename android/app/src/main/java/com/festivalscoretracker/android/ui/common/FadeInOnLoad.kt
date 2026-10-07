package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext
import kotlin.math.abs

// region Fade in on load

/**
 * Fade content in (with the web's short upward drift, `fadeInUp`) when it finishes
 * loading, like the web's staggered row entrances.
 *
 * Inside a page's [FadeInWindow] ([LocalFadeInWindow]: every [FestivalScreen], modal sheet
 * and dialog provides one) the fade runs on the window's shared timeline, like the web's
 * `useStaggerRush` (load-transition R5, issue #323):
 * - a scroll of any kind (drag, fling, Quick Links jump, selected-row reveal) rushes every
 *   fade that has not started yet, so the rest fade in together instead of waiting out
 *   their stagger;
 * - content first composed already loaded while the page's entrance is still running (a
 *   lazy row the scroll or prefetch reaches) joins that entrance instead of appearing
 *   opaque in the middle of it;
 * - once the entrance has finished, content first composed loaded (a cached card, a row
 *   scrolled back into view) appears immediately, as the web skips its animation for
 *   cached data, so scrolling never replays an entrance.
 *
 * In a window that closes on scroll ([rememberFadeInWindow]: Player Profile, Leaderboards),
 * content that finishes loading after the page has scrolled also appears immediately, so
 * only what was visible at load fades. Remove animations / Reduce Motion
 * ([LocalFestivalAccessibility]) shows content at once. The animated values are read
 * only in the graphics layer, so the fade never recomposes the content.
 *
 * Place it on a container that stays composed while loading (the skeleton lives
 * outside it), so it sees the loading → loaded transition.
 *
 * @param isLoaded Whether the content is ready to show.
 * @param delayMillis Delay before the fade starts (stagger between siblings).
 * @param rushOnScroll Join the window's shared timeline (default). Off for content that keeps
 *   its own stagger while the page scrolls (Suggestions' later batches, which arrive while
 *   the reader scrolls, like the web, which rushes only once per page).
 * @return Modifier.
 */
fun Modifier.festivalFadeIn(isLoaded: Boolean, delayMillis: Int = 0, rushOnScroll: Boolean = true): Modifier = composed {
    val window = LocalFadeInWindow.current
    if (window != null && rushOnScroll) timedFadeIn(window, isLoaded, delayMillis) else animatedFadeIn(window, isLoaded, delayMillis)
}

/**
 * [festivalFadeIn] on a [FadeInWindow]'s shared timeline.
 *
 * @param window Page window.
 * @param isLoaded Whether the content is ready to show.
 * @param delayMillis Stagger delay.
 * @return Modifier.
 */
@Composable
private fun Modifier.timedFadeIn(window: FadeInWindow, isLoaded: Boolean, delayMillis: Int): Modifier {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    // The fade's anchor on the window's clock, or SHOWN / PENDING. Read without observation so
    // the window finishing an entrance does not recompose every row.
    val anchor = remember(window) {
        mutableLongStateOf(Snapshot.withoutReadObservation { window.initialAnchor(isLoaded, reduceMotion) })
    }
    LaunchedEffect(window, isLoaded, reduceMotion) {
        val current = anchor.longValue
        when {
            !isLoaded -> anchor.longValue = FadeInWindow.PENDING
            reduceMotion -> anchor.longValue = FadeInWindow.SHOWN
            current == FadeInWindow.SHOWN -> Unit
            // Joined a running entrance when first composed: keep the window running until it ends.
            current != FadeInWindow.PENDING -> window.arm(current, delayMillis)
            // The page has scrolled (a window that closes on scroll): content loaded now shows in place.
            !window.isOpen -> anchor.longValue = FadeInWindow.SHOWN
            else -> {
                val now = withFrameNanos { it }
                window.arm(now, delayMillis)
                anchor.longValue = now
            }
        }
    }
    val drift = FADE_IN_DRIFT_DP.dp
    return graphicsLayer {
        val progress = when (val value = anchor.longValue) {
            FadeInWindow.SHOWN -> 1f
            FadeInWindow.PENDING -> 0f
            else -> window.progress(value, delayMillis)
        }
        val shown = fadeInAlpha(FadeInEasing.transform(progress), isLoaded, reduceMotion)
        alpha = shown
        translationY = (1f - shown) * drift.toPx()
    }
}

/**
 * [festivalFadeIn] with its own animation (no window, or a fade that keeps its stagger).
 *
 * @param window Page window, if any (a closed one shows newly loaded content in place).
 * @param isLoaded Whether the content is ready to show.
 * @param delayMillis Stagger delay.
 * @return Modifier.
 */
@Composable
private fun Modifier.animatedFadeIn(window: FadeInWindow?, isLoaded: Boolean, delayMillis: Int): Modifier {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
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
    return graphicsLayer {
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
 * Shared timeline of a page's first-load fades (web `useStaggerRush`, load-transition R5).
 *
 * Every fade starts [anchor] + its stagger delay later, unless a rush (a scroll) falls
 * between its anchor and that start: then it starts at the rush, together with every other
 * fade that had not started, as the web restarts every `fadeInUp` element still at opacity 0
 * with no delay. A fade that has already started keeps running. Pure, so it is unit tested.
 */
internal object FadeTimeline {
    /**
     * When a fade starts.
     *
     * @param anchorNanos Frame time the fade was armed (the content was revealed).
     * @param delayNanos Its stagger delay.
     * @param rushes Rush frame times, ascending.
     * @return Start frame time.
     */
    fun startNanos(anchorNanos: Long, delayNanos: Long, rushes: List<Long>): Long {
        val natural = anchorNanos + delayNanos
        return rushes.firstOrNull { it >= anchorNanos && it < natural } ?: natural
    }

    /**
     * Linear progress of a fade at [clockNanos].
     *
     * @param clockNanos Current frame time.
     * @param startNanos Its start.
     * @param durationNanos Fade duration (0 shows it at its start).
     * @return 0 to 1.
     */
    fun progress(clockNanos: Long, startNanos: Long, durationNanos: Long): Float = when {
        clockNanos < startNanos -> 0f
        durationNanos <= 0L -> 1f
        else -> ((clockNanos - startNanos).toDouble() / durationNanos).toFloat().coerceIn(0f, 1f)
    }
}

/**
 * A page's fade window: the shared timeline [festivalFadeIn] fades run on, and the rule for
 * content that loads after the page scrolls (iOS `FestivalFadeInScope`; web `useStaggerRush`).
 *
 * Every [FestivalScreen], [FestivalModalSheet] and [FestivalModalDialog] provides a page
 * window ([rememberPageFadeInWindow], `closesOnScroll = false`), which [rush]es on any scroll:
 * fades that have not started run together, and content loaded later still fades in. A list
 * page that limits fades to its load ([rememberFadeInWindow]: Player Profile, Leaderboards)
 * provides a window that is also open while the page rests where it loaded and closed for
 * good once a scroll moves it: closing rushes, and while closed [festivalFadeIn] and
 * [rememberRevealed] show content that finishes loading in place, so a section that starts
 * loading when it is scrolled into view does not fade in under the reader.
 *
 * Only movement while the list reports a scroll in progress closes the window; while idle
 * the resting position follows the list, so items inserted above (which shift the first
 * visible index) do not close it.
 *
 * The window's clock ticks once per frame only while an entrance runs ([isAnimating]); fades
 * read it in their graphics layer, so the entrance never recomposes the content.
 *
 * @param thresholdPx Scroll distance within the resting item that still counts as at
 *   rest (absorbs sub-pixel settling).
 * @param closesOnScroll Whether [note] closes the window (list windows) or it stays open (page windows).
 */
class FadeInWindow(private val thresholdPx: Float, private val closesOnScroll: Boolean = true) {
    private var restingIndex: Int? = null
    private var restingOffset = 0

    /** Whether content may still fade in. */
    var isOpen: Boolean = true
        private set

    // region Timeline

    private var clockNanos by mutableLongStateOf(0L)
    private var rushes by mutableStateOf(emptyList<Long>())
    private var settledArmNanos by mutableLongStateOf(Long.MIN_VALUE)
    private var animating by mutableStateOf(false)
    private var rushRequested by mutableStateOf(false)
    private var epochNanos = Long.MIN_VALUE
    private var lastArmNanos = Long.MIN_VALUE
    private var endNanos = Long.MIN_VALUE

    /** Animator duration scale (`MotionDurationScale`), read by the clock. */
    internal var durationScale: Float = 1f

    /** Whether an entrance is running (some fade has not finished). */
    val isAnimating: Boolean get() = animating

    /** Whether a [rush] is waiting for the next frame. */
    internal val isRushPending: Boolean get() = rushRequested

    /** Drags and flings seen by [fadeInRushOnScroll] (programmatic scrolls dispatch none). */
    internal var userScrolls: Int = 0
        private set

    /** A drag or fling moved the page: count it and [rush]. */
    internal fun noteUserScroll() {
        userScrolls++
        rush()
    }

    /**
     * Rush every fade that has not started yet: on the next frame they start together (web
     * `useStaggerRush`). Call on any scroll: a drag or fling (the page's nested scroll does
     * this), or a programmatic scroll (Quick Links jump, selected-row reveal). Does nothing
     * once the entrance has finished, so a later scroll never replays one (R5).
     */
    fun rush() {
        if (animating && !rushRequested) rushRequested = true
    }

    /**
     * Anchor for a fade first composed with [isLoaded]: it joins the running entrance (a row a
     * scroll or prefetch composes mid-entrance) from the entrance's first anchor, so a row that
     * leaves and comes back is never behind where it was; otherwise loaded content shows and
     * unloaded content waits.
     *
     * @param isLoaded Whether the content is ready.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return Anchor, [SHOWN] or [PENDING].
     */
    internal fun initialAnchor(isLoaded: Boolean, reduceMotion: Boolean): Long = when {
        !isLoaded -> PENDING
        reduceMotion || !animating -> SHOWN
        else -> epochNanos
    }

    /**
     * Arm a fade on the timeline (or keep the clock running for a fade that joined it).
     *
     * @param anchorNanos Frame time the content was revealed.
     * @param delayMillis Its stagger delay.
     */
    internal fun arm(anchorNanos: Long, delayMillis: Int) {
        if (!animating) {
            epochNanos = anchorNanos
            endNanos = Long.MIN_VALUE
        }
        if (anchorNanos > lastArmNanos) lastArmNanos = anchorNanos
        val start = FadeTimeline.startNanos(anchorNanos, scaled(delayMillis), rushes)
        endNanos = maxOf(endNanos, start + scaled(FADE_IN_MILLIS))
        animating = true
    }

    /**
     * Advance the clock to a frame: stamp a pending rush (at most once per reveal, so fades it
     * collapsed never move again) and end the entrance once every fade has finished.
     *
     * @param frameNanos Frame time.
     */
    internal fun tick(frameNanos: Long) {
        clockNanos = frameNanos
        if (rushRequested) {
            rushRequested = false
            if (animating && (rushes.isEmpty() || rushes.last() < lastArmNanos)) {
                rushes = rushes + frameNanos
                // Fades armed by now start no later than this frame.
                endNanos = minOf(endNanos, frameNanos + scaled(FADE_IN_MILLIS))
            }
        }
        if (animating && frameNanos >= endNanos) {
            animating = false
            settledArmNanos = lastArmNanos
            rushes = emptyList()
        }
    }

    /**
     * Linear progress of the fade anchored at [anchorNanos]; read in a graphics layer.
     *
     * @param anchorNanos Its anchor.
     * @param delayMillis Its stagger delay.
     * @return 0 to 1.
     */
    internal fun progress(anchorNanos: Long, delayMillis: Int): Float {
        if (anchorNanos <= settledArmNanos) return 1f
        val start = FadeTimeline.startNanos(anchorNanos, scaled(delayMillis), rushes)
        return FadeTimeline.progress(clockNanos, start, scaled(FADE_IN_MILLIS))
    }

    /** Tick the clock every frame while an entrance runs or a rush waits. */
    internal suspend fun runClock() {
        durationScale = coroutineContext[MotionDurationScale]?.scaleFactor ?: 1f
        while (true) {
            snapshotFlow { animating || rushRequested }.first { it }
            while (animating || rushRequested) withFrameNanos(::tick)
        }
    }

    private fun scaled(millis: Int): Long = (millis * 1_000_000L * durationScale).toLong()

    // endregion

    /**
     * Record the list's position.
     *
     * @param index First visible item index.
     * @param offsetPx Scroll offset within that item, in pixels.
     * @param scrolling Whether a scroll (gesture, fling or animated jump) is in progress.
     * @return Whether the window is still open (always for a page window).
     */
    fun note(index: Int, offsetPx: Int, scrolling: Boolean): Boolean {
        if (!isOpen) return false
        val rest = restingIndex
        when {
            rest == null || !scrolling -> {
                restingIndex = index
                restingOffset = offsetPx
            }
            index != rest || abs(offsetPx - restingOffset) > thresholdPx -> if (closesOnScroll) isOpen = false
        }
        return isOpen
    }

    /** Anchor values that are not frame times. */
    internal companion object {
        /** Content shown without a fade. */
        const val SHOWN = Long.MAX_VALUE

        /** Content waiting to load (drawn transparent). */
        const val PENDING = Long.MIN_VALUE
    }
}

/** The enclosing page's fade window; null outside a page (each [FestivalScreen], modal sheet and dialog provides one). */
val LocalFadeInWindow = staticCompositionLocalOf<FadeInWindow?> { null }

/**
 * A page's fade window ([FadeInWindow] with `closesOnScroll = false`), its clock running.
 * [FestivalScreen] and the modals create one; a page whose body scrolls programmatically
 * before its [FestivalScreen] (a selected-row reveal, Quick Links) creates it there and
 * passes it in, so the body can [FadeInWindow.rush] it.
 *
 * @return Window.
 */
@Composable
fun rememberPageFadeInWindow(): FadeInWindow {
    val window = remember { FadeInWindow(thresholdPx = 0f, closesOnScroll = false) }
    LaunchedEffect(window) { window.runClock() }
    return window
}

/**
 * Rush [window] whenever a scrollable inside moves (a drag or fling; programmatic scrolls
 * dispatch no nested scroll, so their callers rush themselves). Observes only.
 *
 * @param window Page window.
 * @return Modifier.
 */
fun Modifier.fadeInRushOnScroll(window: FadeInWindow): Modifier = composed {
    val connection = remember(window) {
        object : NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (consumed != Offset.Zero) window.noteUserScroll()
                return Offset.Zero
            }
        }
    }
    nestedScroll(connection)
}

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
        launch { window.runClock() }
        snapshotFlow(position)
            .takeWhile { (index, offset, scrolling) -> window.note(index, offset, scrolling) }
            .collect {}
        // Closed by a scroll: fades that have not started run together (web `useStaggerRush`).
        window.rush()
    }
    return window
}

/** Scroll that closes a page's fade window (iOS `FestivalFadeInScope`: 4 pt). */
private const val FADE_IN_SCROLL_THRESHOLD_DP = 4

// endregion
