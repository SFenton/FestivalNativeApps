package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.core.shell.LoadSwapPolicy
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// region Load swap

/**
 * The shared load **and reload** transition (issue #71; web `useLoadPhase`, `LoadGate`,
 * `PaginatedLeaderboard`): when a selector, filter, instrument or page change makes the shown
 * content stale, it fades out (300 ms), the white spinner shows at full opacity until the new
 * data is ready, fades out (500 ms), and the new content staggers in (`fadeInUp`, 400 ms with a
 * 125 ms stagger). First loads run the spinner half of the same sequence.
 *
 * It holds the last committed value, so view models keep their plain `Loading → Loaded`
 * states: stale content is drawn from [shown] while it fades, and never shows under the
 * spinner. Data that arrives during the fade-out is applied once it finished; a newer reload
 * while the spinner fades brings it back. Data ready at first composition (cached, a page
 * returned to) shows at once. Updates for the same selection while content is in (a silent
 * refresh) apply in place without a transition. Remove animations / Reduce Motion: no fades,
 * no waits; the spinner shows only while data is loading and content swaps at once.
 *
 * A held spinner ([rememberLoadSwap] `holdSpinner`, the publication refresh of load-transition
 * R3/R9, Apple `PublicationRefreshTransition`) runs all four phases even when the data is ready
 * before the content has faded out: content out 300 ms → spinner in 150 ms (web
 * `QUICK_FADE_MS`) → spinner on screen at least 400 ms from its appearance and until the data
 * is ready (web `MIN_SPINNER_MS`) → spinner out 500 ms → content in. Under Reduce Motion the
 * fades are instant and the spinner still holds 400 ms so it never blinks (R6).
 *
 * Obtain one with [rememberLoadSwap]; draw [shown] with [staggered] (or [contentModifier]) while
 * [showsContent] (a card that groups several rows takes [card] and its rows no fade, R11), and
 * [LoadSwapSpinner] / [loadSwapSpinnerItem] while [showsSpinner]. A pinned
 * row kept composed beside the spinner adds [pinnedStaggered] and [pinnedContentModifier]; pagers
 * and pickers add neither and stay usable.
 *
 * @param T Value the content is drawn from (usually a `LoadState`).
 */
@Stable
class LoadSwap<T> internal constructor(initial: T, ready: Boolean, key: Any?, pinnedKey: Any?, spinnerStartsHidden: Boolean = false) {
    /** Current phase. */
    var phase: LoadSwapPhase by mutableStateOf(LoadSwapPolicy.initial(ready))
        internal set

    /**
     * False for one frame after new content replaced the spinner (so [festivalFadeIn] sees the
     * change and staggers it in), true otherwise.
     */
    var revealed: Boolean by mutableStateOf(true)
        internal set

    internal var committed: T = initial
    internal var committedKey: Any? by mutableStateOf(key)
    internal var sawSpinner: Boolean = !ready
    internal val contentAlpha = Animatable(1f)
    internal val spinnerAlpha = Animatable(if (spinnerStartsHidden) 0f else 1f)
    internal var current: T by mutableStateOf(initial)

    /** Pinned key of the latest inputs (see [rememberLoadSwap]). */
    internal var pinnedKey: Any? by mutableStateOf(pinnedKey)

    /** Pinned key of the committed content, [NeverCommitted] before the first commit. */
    internal var committedPinnedKey: Any? by mutableStateOf(if (ready) pinnedKey else NeverCommitted)

    /** Whether the last commit changed the pinned key (or was the first load), so pinned content re-enters. */
    internal var pinnedEnters: Boolean by mutableStateOf(!ready)

    /**
     * Whether pinned content is stale: the pending reload can change it because its pinned key
     * differs from the committed one (or it re-runs on every reload). False while content is in.
     */
    val pinnedStale: Boolean get() = phase != LoadSwapPhase.ContentIn && (pinnedKey === EveryReload || pinnedKey != committedPinnedKey)
    /** The value to draw: the latest data while content is in, the stale value while it fades out. */
    val shown: T get() = current

    /** Whether content (from [shown]) is composed. */
    val showsContent: Boolean get() = phase == LoadSwapPhase.ContentIn || phase == LoadSwapPhase.ContentOut

    /** Whether the spinner is composed. */
    val showsSpinner: Boolean get() = !showsContent

    /** Content opacity for the fade-out, read only in the draw phase. */
    val contentModifier: Modifier = Modifier.graphicsLayer { alpha = contentAlpha.value }

    /**
     * For stale result content kept composed beside or beneath the spinner (a pinned row whose
     * slot holds the pager in place, issue #93; the Leaderboards overview list, whose cards keep
     * loading under the spinner, issue #178): while the spinner shows it is hidden, silent to TalkBack
     * and ignores touches, with or without Reduce Motion, so stale content never shows under
     * the spinner (issue #149). Content whose pinned key the reload doesn't change (a page-only
     * reload of a board whose "your score" row is the same on every page, issue #190) stays
     * visible and usable, like the web footer (load-transition R2). Never apply it to controls:
     * pickers and pagers stay visible and usable during a swap so a newer selection supersedes
     * the pending one (load-transition R4).
     */
    val pinnedContentModifier: Modifier get() = if (showsSpinner && pinnedStale) HiddenWhileLoading else Modifier

    /** Spinner opacity for its fade-out, read only in the draw phase. */
    val spinnerModifier: Modifier = Modifier.graphicsLayer { alpha = spinnerAlpha.value }

    /**
     * Content fade-out plus the web's staggered `fadeInUp` entrance for the child at [index].
     *
     * @param index Zero-based order of the child in the content.
     * @return Modifier.
     */
    fun Modifier.staggered(index: Int): Modifier = then(contentModifier).festivalFadeIn(revealed, fadeInStagger(index))

    /**
     * Entrance of a card that groups several rows (a board's rows card, a Leaderboards overview
     * card; load-transition R11, owner #614): the card fades out with the content and fades in
     * as one unit at its [index], rows and all. Its rows take no fade of their own, so they never
     * stagger inside it; separate cards on a page still stagger by their own index.
     *
     * @param index Zero-based order of the card among the content's children.
     * @return Modifier.
     */
    fun Modifier.card(index: Int = BOARD_CARD_INDEX): Modifier = staggered(index)

    /**
     * [staggered] for pinned content (web `PaginatedLeaderboard` `footerAnimKey`): it fades out
     * with the rows and re-enters with the child at [index] on the first load and when its pinned
     * key changes; on any other reload (page, retry) it stays in place without a fade (issue #190).
     *
     * @param index Zero-based order of the child it enters with.
     * @return Modifier.
     */
    fun Modifier.pinnedStaggered(index: Int): Modifier = then(pinnedFade).festivalFadeIn(revealed || !pinnedEnters, fadeInStagger(index))

    /** The content fade-out, applied only while the pinned content is stale. */
    private val pinnedFade: Modifier = Modifier.graphicsLayer { alpha = if (pinnedStale) contentAlpha.value else 1f }
}

/**
 * Remember a [LoadSwap] for a page's data.
 *
 * @param target Latest value from the view model.
 * @param ready Whether [target] can be shown (loaded, empty or failed); false while a load or a
 *   user-initiated reload is in flight.
 * @param key Selection [target] belongs to, for view models that swap to ready data at once
 *   (cache hits); a change runs the transition even if [ready] never went false. Leave null
 *   when every reload passes through a not-ready state.
 * @param pinnedKey What pinned content beside the rows depends on (web `footerAnimKey`: the
 *   instrument, metric or invalid-score leeway, never the page). Pinned content hides beside the
 *   spinner and re-enters with the rows only when it changes; the default hides it on every reload.
 * @param holdSpinner Publication refresh (load-transition R3, R9): the spinner always shows,
 *   fades in over [LoadSwapPolicy.SPINNER_IN_MS] and stays at least
 *   [LoadSwapPolicy.MIN_SPINNER_MS] from its appearance before it fades out, even for data that
 *   was ready during the content fade-out; Reduce Motion keeps only the hold.
 * @return Swap state.
 */
@Composable
fun <T> rememberLoadSwap(target: T, ready: Boolean, key: Any? = null, pinnedKey: Any? = EveryReload, holdSpinner: Boolean = false): LoadSwap<T> {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val swap = remember { LoadSwap(target, ready, key, pinnedKey, spinnerStartsHidden = !ready && holdSpinner && !reduceMotion) }
    val inputs = remember { MutableStateFlow(LoadSwapInputs(target, ready, key, pinnedKey, reduceMotion, holdSpinner)) }
    val live = swap.phase == LoadSwapPhase.ContentIn && ready && key == swap.committedKey && pinnedKey == swap.committedPinnedKey
    swap.current = if (live) target else swap.committed
    swap.pinnedKey = pinnedKey
    SideEffect {
        if (live) swap.committed = target
        inputs.value = LoadSwapInputs(target, ready, key, pinnedKey, reduceMotion, holdSpinner)
    }
    LaunchedEffect(swap) {
        fun swapped(input: LoadSwapInputs<T>) = input.key != swap.committedKey || input.pinnedKey != swap.committedPinnedKey

        // Whether the spinner just replaced content (or is the first load), so a held spinner fades in and holds.
        var freshSpinner = swap.phase == LoadSwapPhase.Loading
        suspend fun commit(animate: Boolean) {
            val latest = inputs.value
            swap.committed = latest.target
            swap.current = latest.target
            swap.committedKey = latest.key
            swap.pinnedEnters = latest.pinnedKey === EveryReload || latest.pinnedKey != swap.committedPinnedKey
            swap.committedPinnedKey = latest.pinnedKey
            swap.sawSpinner = false
            swap.contentAlpha.snapTo(1f)
            swap.revealed = !animate
            swap.phase = LoadSwapPhase.ContentIn
            if (animate) {
                withFrameNanos { }
                swap.revealed = true
            }
        }

        suspend fun showSpinner(next: LoadSwapPhase) {
            val fresh = next == LoadSwapPhase.Loading && !swap.showsSpinner
            if (fresh) freshSpinner = true
            val input = inputs.value
            when {
                fresh && input.holdsSpinner && LoadSwapPolicy.spinnerInMs(input.reduceMotion) > 0 -> swap.spinnerAlpha.snapTo(0f)
                !swap.showsSpinner -> swap.spinnerAlpha.snapTo(1f)
            }
            swap.sawSpinner = true
            swap.phase = next
        }

        suspend fun step(next: LoadSwapPhase, animateEntrance: Boolean = false) {
            when (next) {
                LoadSwapPhase.ContentIn -> commit(animateEntrance)
                LoadSwapPhase.ContentOut -> swap.phase = next
                LoadSwapPhase.Loading, LoadSwapPhase.SpinnerOut -> showSpinner(next)
            }
        }

        while (true) {
            when (swap.phase) {
                LoadSwapPhase.ContentIn -> {
                    val input = inputs.first { !it.ready || swapped(it) }
                    step(LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, input.ready, swapped(input), input.reduceMotion, input.holdsSpinner))
                }
                LoadSwapPhase.ContentOut -> {
                    if (!inputs.value.reduceMotion) {
                        swap.contentAlpha.animateTo(0f, tween(LoadSwapPolicy.CONTENT_OUT_MS, easing = FadeInEasing))
                    }
                    val input = inputs.value
                    step(LoadSwapPolicy.afterContentOut(input.ready, input.reduceMotion, input.holdsSpinner))
                }
                LoadSwapPhase.Loading -> {
                    swap.sawSpinner = true
                    val hold = freshSpinner && inputs.value.holdsSpinner
                    freshSpinner = false
                    if (hold) {
                        // Spinner in, then at least MIN_SPINNER_MS on screen from its appearance (R3; R6 keeps the hold).
                        val fadeIn = LoadSwapPolicy.spinnerInMs(inputs.value.reduceMotion)
                        coroutineScope {
                            launch {
                                if (fadeIn > 0) swap.spinnerAlpha.animateTo(1f, tween(fadeIn, easing = FadeInEasing)) else swap.spinnerAlpha.snapTo(1f)
                            }
                            delay(LoadSwapPolicy.MIN_SPINNER_MS.toLong())
                        }
                    } else {
                        swap.spinnerAlpha.snapTo(1f)
                    }
                    val input = inputs.first { it.ready }
                    step(LoadSwapPolicy.onInputs(LoadSwapPhase.Loading, ready = true, swapped = true, reduceMotion = input.reduceMotion))
                }
                LoadSwapPhase.SpinnerOut -> {
                    var interrupted = false
                    if (!inputs.value.reduceMotion) {
                        coroutineScope {
                            val fade = launch { swap.spinnerAlpha.animateTo(0f, tween(LoadSwapPolicy.SPINNER_FADE_MS, easing = FadeInEasing)) }
                            val watch = launch {
                                inputs.first { !it.ready }
                                interrupted = true
                                fade.cancel()
                            }
                            fade.join()
                            watch.cancel()
                        }
                    }
                    val next = if (interrupted) LoadSwapPhase.Loading else LoadSwapPolicy.afterSpinnerFade(LoadSwapPhase.SpinnerOut)
                    step(next, LoadSwapPolicy.animatesEntrance(swap.sawSpinner, inputs.value.reduceMotion))
                }
            }
        }
    }
    return swap
}

/**
 * Latest inputs of a [rememberLoadSwap], published after each composition.
 *
 * @property target Latest value.
 * @property ready Whether [target] can be shown.
 * @property key Selection [target] belongs to.
 * @property pinnedKey What pinned content beside the rows depends on.
 * @property reduceMotion Remove animations / Reduce Motion.
 * @property holdsSpinner The spinner fades in and holds (publication refresh, R3).
 */
private data class LoadSwapInputs<T>(val target: T, val ready: Boolean, val key: Any?, val pinnedKey: Any?, val reduceMotion: Boolean, val holdsSpinner: Boolean)

/** Default pinned key: pinned content is stale on every reload. */
private object EveryReload

/** Committed pinned key before the first commit. */
private object NeverCommitted

/**
 * The swap's spinner, centred in the space it is given, with its fade-out.
 *
 * @param swap Swap state.
 * @param label Accessible description.
 * @param modifier Modifier (defaults to filling the content area).
 * @param tag Test tag.
 * @param announce Make the spinner a polite live region, so TalkBack speaks [label] when it
 *   appears without moving focus (the publication refresh, load-transition R9).
 * @param avoidHinge False for an in-card loading region.
 */
@Composable
fun LoadSwapSpinner(
    swap: LoadSwap<*>,
    label: String = "Loading",
    modifier: Modifier = Modifier.fillMaxSize(),
    tag: String = LOAD_SWAP_SPINNER_TAG,
    announce: Boolean = false,
    avoidHinge: Boolean = true,
) {
    // The progress indicator is its own merged node, so the live region sits on it with the label.
    val live = if (announce) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier
    LoadingRegion(label, modifier.then(swap.spinnerModifier).testTag(tag), live, avoidHinge)
}

/** Spoken label of the in-place publication refresh spinner (load-transition R9, Apple `PublicationRefreshBoundary`). */
const val PUBLICATION_REFRESH_LABEL = "Loading new scores"

/** Test tag of the in-place publication refresh spinner (Apple `fst.publication.refreshing`). */
const val PUBLICATION_REFRESH_TAG = "fst.publication.refreshing"

/**
 * [LoadSwapSpinner] as a lazy-list item centred in the visible region left by headers,
 * controls and lower chrome, using the same sizing as an empty result.
 *
 * @param swap Swap state.
 * @param label Accessible description.
 * @param tag Test tag.
 * @param key Item key.
 * @param state List state for measuring the result region.
 */
fun LazyListScope.loadSwapSpinnerItem(
    swap: LoadSwap<*>,
    label: String = "Loading",
    tag: String = LOAD_SWAP_SPINNER_TAG,
    key: Any = "load-swap-spinner",
    state: LazyListState,
) {
    item(key = key, contentType = "load-swap-spinner") {
        val height = Modifier.fillEmptyRegion(rememberEmptyRegion(state, key))
        LoadSwapSpinner(swap, label, Modifier.fillParentMaxWidth().then(height), tag)
    }
}

/**
 * The whole load swap in one box: [LoadSwapSpinner] while loading, [content] (drawn from the
 * shown value, use [LoadSwap.staggered] on its children) otherwise.
 *
 * @param T Value type.
 * @param target Latest value.
 * @param ready Whether [target] can be shown.
 * @param modifier Modifier for the content area (the spinner centres in it).
 * @param key Selection [target] belongs to (see [rememberLoadSwap]).
 * @param label Spinner's accessible description.
 * @param content Content for the shown value.
 */
@Composable
fun <T> FestivalLoadSwap(
    target: T,
    ready: Boolean,
    modifier: Modifier = Modifier,
    key: Any? = null,
    label: String = "Loading",
    content: @Composable BoxScope.(LoadSwap<T>, T) -> Unit,
) {
    val swap = rememberLoadSwap(target, ready, key)
    Box(modifier) {
        if (swap.showsContent) {
            Box(Modifier.then(swap.contentModifier).then(if (swap.phase == LoadSwapPhase.ContentOut) Modifier.clearAndSetSemantics { } else Modifier)) {
                content(swap, swap.shown)
            }
        } else {
            LoadSwapSpinner(swap, label)
        }
    }
}

/** Stale pinned content kept composed while the spinner shows: invisible, unread and untouchable. */
private val HiddenWhileLoading: Modifier = Modifier
    .graphicsLayer { alpha = 0f }
    .clearAndSetSemantics { }
    .pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
        }
    }

/**
 * Entrance index of a board's one rows card ([LoadSwap.card]): its rows, the selected one
 * included, enter with it, so a selected-row reveal waits for this index (load-transition R11).
 */
const val BOARD_CARD_INDEX = 0

/** Default test tag of the swap spinner. */
const val LOAD_SWAP_SPINNER_TAG = "fst.load-swap.spinner"

// endregion
