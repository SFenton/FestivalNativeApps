package com.festivalscoretracker.android.core.shell

// region Load swap

/**
 * Phases of a page's load **and reload** (issue #71, web `useLoadPhase` + `LoadGate`): when a
 * selector, filter, instrument or page change makes shown content stale, it fades out, the
 * spinner shows until the new data is ready and fades out, and the new content staggers in.
 */
enum class LoadSwapPhase {
    /** Content shows (and staggers in when it replaced the spinner). */
    ContentIn,

    /** Stale content fades out (web `ContentOut`); the new data may already be loading. */
    ContentOut,

    /** Only the spinner shows, at full opacity. */
    Loading,

    /** Data ready: the spinner fades out; content is not composed yet. */
    SpinnerOut,
}

/**
 * Pure phase rules for the shared load swap (`ui/common/LoadSwap.kt`).
 *
 * Inputs are whether the latest data is [ready] (failures count as ready, so their state shows
 * after the same cycle) and whether it is [swapped]: ready data for another selection than the
 * content on screen (an instant, cached read). A reload never shows stale content under the
 * spinner, and data that arrives during the fade-out is applied only once it finished.
 */
object LoadSwapPolicy {
    /** Fade-out of stale content (web `CONTENT_OUT_MS`). */
    const val CONTENT_OUT_MS = 300

    /** Spinner fade-out (web `SPINNER_FADE_MS`). */
    const val SPINNER_FADE_MS = LoadGatePolicy.SPINNER_FADE_MS

    /**
     * Phase for the first composition: data that is already available shows at once without a
     * spinner, as the web skips the transition for a page returned to with cached data.
     *
     * @param ready Whether the data is ready.
     * @return Starting phase.
     */
    fun initial(ready: Boolean): LoadSwapPhase = if (ready) LoadSwapPhase.ContentIn else LoadSwapPhase.Loading

    /**
     * Next phase when the inputs change (or are re-read after a step finished).
     *
     * @param current Current phase.
     * @param ready Whether the latest data is ready.
     * @param swapped Whether ready data belongs to another selection than the shown content.
     * @param reduceMotion Remove animations / Reduce Motion: no fades, content swaps at once.
     * @return New phase; [LoadSwapPhase.ContentIn] with [swapped] under Reduce Motion means
     *   "commit the new data in place".
     */
    fun onInputs(current: LoadSwapPhase, ready: Boolean, swapped: Boolean, reduceMotion: Boolean): LoadSwapPhase = when (current) {
        LoadSwapPhase.ContentIn -> when {
            ready && !swapped -> LoadSwapPhase.ContentIn
            reduceMotion -> if (ready) LoadSwapPhase.ContentIn else LoadSwapPhase.Loading
            else -> LoadSwapPhase.ContentOut
        }
        // The fade-out always finishes first ([afterContentOut]).
        LoadSwapPhase.ContentOut -> if (reduceMotion) afterContentOut(ready, reduceMotion = true) else LoadSwapPhase.ContentOut
        LoadSwapPhase.Loading -> when {
            !ready -> LoadSwapPhase.Loading
            reduceMotion -> LoadSwapPhase.ContentIn
            else -> LoadSwapPhase.SpinnerOut
        }
        // A newer reload while the spinner fades brings it back at full opacity.
        LoadSwapPhase.SpinnerOut -> when {
            !ready -> LoadSwapPhase.Loading
            reduceMotion -> LoadSwapPhase.ContentIn
            else -> LoadSwapPhase.SpinnerOut
        }
    }

    /**
     * Phase after stale content finished fading out: the spinner shows (web goes through
     * `Loading` even when the data is cached, so the spinner always fades out before content).
     *
     * @param ready Whether the latest data is ready.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return [LoadSwapPhase.SpinnerOut] when ready, else [LoadSwapPhase.Loading] (or
     *   [LoadSwapPhase.ContentIn] for ready data under Reduce Motion).
     */
    fun afterContentOut(ready: Boolean, reduceMotion: Boolean): LoadSwapPhase = when {
        !ready -> LoadSwapPhase.Loading
        reduceMotion -> LoadSwapPhase.ContentIn
        else -> LoadSwapPhase.SpinnerOut
    }

    /**
     * Phase after the spinner fade finished.
     *
     * @param current Current phase.
     * @return [LoadSwapPhase.ContentIn] after a fade, otherwise unchanged.
     */
    fun afterSpinnerFade(current: LoadSwapPhase): LoadSwapPhase =
        if (current == LoadSwapPhase.SpinnerOut) LoadSwapPhase.ContentIn else current

    /**
     * Whether newly committed content runs its staggered entrance: only when it replaced the
     * spinner (never for content ready at first composition) and never under Reduce Motion.
     *
     * @param sawSpinner The spinner showed before this content.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return True to animate the entrance.
     */
    fun animatesEntrance(sawSpinner: Boolean, reduceMotion: Boolean): Boolean = sawSpinner && !reduceMotion
}

// endregion
