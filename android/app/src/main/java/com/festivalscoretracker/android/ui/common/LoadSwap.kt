package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.core.shell.LoadSwapPolicy
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.coroutineScope
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
 * Obtain one with [rememberLoadSwap]; draw [shown] with [staggered] (or [contentModifier]) while
 * [showsContent], and [LoadSwapSpinner] / [loadSwapSpinnerItem] while [showsSpinner]. A pinned
 * row kept composed beside the spinner adds [pinnedContentModifier]; pagers and pickers add
 * neither and stay usable.
 *
 * @param T Value the content is drawn from (usually a `LoadState`).
 */
@Stable
class LoadSwap<T> internal constructor(initial: T, ready: Boolean, key: Any?) {
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
    internal val spinnerAlpha = Animatable(1f)
    internal var current: T by mutableStateOf(initial)

    /** The value to draw: the latest data while content is in, the stale value while it fades out. */
    val shown: T get() = current

    /** Whether content (from [shown]) is composed. */
    val showsContent: Boolean get() = phase == LoadSwapPhase.ContentIn || phase == LoadSwapPhase.ContentOut

    /** Whether the spinner is composed. */
    val showsSpinner: Boolean get() = !showsContent

    /** Content opacity for the fade-out, read only in the draw phase. */
    val contentModifier: Modifier = Modifier.graphicsLayer { alpha = contentAlpha.value }

    /**
     * For stale result content kept composed beside the spinner (a pinned row whose slot holds
     * the pager in place, issue #93): while the spinner shows it is hidden, silent to TalkBack
     * and ignores touches, with or without Reduce Motion, so stale content never shows under
     * the spinner (issue #149). Never apply it to controls: pickers and pagers stay visible and
     * usable during a swap so a newer selection supersedes the pending one (load-transition R4).
     */
    val pinnedContentModifier: Modifier get() = if (showsSpinner) HiddenWhileLoading else Modifier

    /** Spinner opacity for its fade-out, read only in the draw phase. */
    val spinnerModifier: Modifier = Modifier.graphicsLayer { alpha = spinnerAlpha.value }

    /**
     * Content fade-out plus the web's staggered `fadeInUp` entrance for the child at [index].
     *
     * @param index Zero-based order of the child in the content.
     * @return Modifier.
     */
    fun Modifier.staggered(index: Int): Modifier = then(contentModifier).festivalFadeIn(revealed, fadeInStagger(index))
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
 * @return Swap state.
 */
@Composable
fun <T> rememberLoadSwap(target: T, ready: Boolean, key: Any? = null): LoadSwap<T> {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val swap = remember { LoadSwap(target, ready, key) }
    val inputs = remember { MutableStateFlow(LoadSwapInputs(target, ready, key, reduceMotion)) }
    val live = swap.phase == LoadSwapPhase.ContentIn && ready && key == swap.committedKey
    swap.current = if (live) target else swap.committed
    SideEffect {
        if (live) swap.committed = target
        inputs.value = LoadSwapInputs(target, ready, key, reduceMotion)
    }
    LaunchedEffect(swap) {
        fun swapped(input: LoadSwapInputs<T>) = input.key != swap.committedKey

        suspend fun commit(animate: Boolean) {
            val latest = inputs.value
            swap.committed = latest.target
            swap.current = latest.target
            swap.committedKey = latest.key
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
            if (!swap.showsSpinner) swap.spinnerAlpha.snapTo(1f)
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
                    step(LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, input.ready, swapped(input), input.reduceMotion))
                }
                LoadSwapPhase.ContentOut -> {
                    if (!inputs.value.reduceMotion) {
                        swap.contentAlpha.animateTo(0f, tween(LoadSwapPolicy.CONTENT_OUT_MS, easing = FadeInEasing))
                    }
                    step(LoadSwapPolicy.afterContentOut(inputs.value.ready, inputs.value.reduceMotion))
                }
                LoadSwapPhase.Loading -> {
                    swap.sawSpinner = true
                    swap.spinnerAlpha.snapTo(1f)
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
 * @property reduceMotion Remove animations / Reduce Motion.
 */
private data class LoadSwapInputs<T>(val target: T, val ready: Boolean, val key: Any?, val reduceMotion: Boolean)

/**
 * The swap's spinner, centred in the space it is given, with its fade-out.
 *
 * @param swap Swap state.
 * @param label Accessible description.
 * @param modifier Modifier (defaults to filling the content area).
 * @param tag Test tag.
 */
@Composable
fun LoadSwapSpinner(swap: LoadSwap<*>, label: String = "Loading", modifier: Modifier = Modifier.fillMaxSize(), tag: String = LOAD_SWAP_SPINNER_TAG) {
    Box(modifier.then(swap.spinnerModifier).testTag(tag), contentAlignment = Alignment.Center) { FestivalLoading(label) }
}

/**
 * [LoadSwapSpinner] as a lazy-list item centred in most of the list's viewport, for pages whose
 * selectors or header rows stay in the same list above the swapped content.
 *
 * @param swap Swap state.
 * @param label Accessible description.
 * @param tag Test tag.
 * @param key Item key.
 */
fun LazyListScope.loadSwapSpinnerItem(swap: LoadSwap<*>, label: String = "Loading", tag: String = LOAD_SWAP_SPINNER_TAG, key: Any = "load-swap-spinner") {
    item(key = key, contentType = "load-swap-spinner") { SpinnerItem(swap, label, tag) }
}

@Composable
private fun LazyItemScope.SpinnerItem(swap: LoadSwap<*>, label: String, tag: String) {
    LoadSwapSpinner(swap, label, Modifier.fillParentMaxWidth().fillParentMaxHeight(SPINNER_ITEM_HEIGHT_FRACTION), tag)
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

/** Default test tag of the swap spinner. */
const val LOAD_SWAP_SPINNER_TAG = "fst.load-swap.spinner"

/** Share of a list's viewport the spinner item centres in (below a page's header rows). */
private const val SPINNER_ITEM_HEIGHT_FRACTION = 0.6f

// endregion
