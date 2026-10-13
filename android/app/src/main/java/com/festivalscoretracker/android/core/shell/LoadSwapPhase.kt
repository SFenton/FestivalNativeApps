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

    /** Fade-in of a held spinner (web `QUICK_FADE_MS`; Apple `ReloadTransition.Timing.spinnerInDuration`). */
    const val SPINNER_IN_MS = 150

    /**
     * Shortest time a held spinner stays, counted from its appearance, so it never blinks (web
     * `MIN_SPINNER_MS`, measured from the spinner's start like `PathsModal`'s `elapsed`; Apple
     * `ReloadTransition.Timing.minimumSpinnerDuration`).
     */
    const val MIN_SPINNER_MS = 400

    /**
     * Spinner fade-in for a held spinner (load-transition R3): none under Reduce Motion, where
     * the spinner shows at once and still keeps [MIN_SPINNER_MS] (R6).
     *
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return Fade-in in milliseconds (0 = show at once).
     */
    fun spinnerInMs(reduceMotion: Boolean): Int = if (reduceMotion) 0 else SPINNER_IN_MS

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
     * @param holdsSpinner Publication refresh (load-transition R3, R9): content never leaves
     *   without the spinner, which fades in and holds before it may go (see [afterContentOut]).
     * @return New phase; [LoadSwapPhase.ContentIn] with [swapped] under Reduce Motion means
     *   "commit the new data in place".
     */
    fun onInputs(current: LoadSwapPhase, ready: Boolean, swapped: Boolean, reduceMotion: Boolean, holdsSpinner: Boolean = false): LoadSwapPhase = when (current) {
        LoadSwapPhase.ContentIn -> when {
            ready && !swapped -> LoadSwapPhase.ContentIn
            reduceMotion -> if (ready && !holdsSpinner) LoadSwapPhase.ContentIn else LoadSwapPhase.Loading
            else -> LoadSwapPhase.ContentOut
        }
        // The fade-out always finishes first ([afterContentOut]).
        LoadSwapPhase.ContentOut -> if (reduceMotion) afterContentOut(ready, reduceMotion = true, holdsSpinner = holdsSpinner) else LoadSwapPhase.ContentOut
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
     * A held spinner (the publication refresh, load-transition R3) always goes to
     * [LoadSwapPhase.Loading], even for data that landed during the fade-out: there it fades in
     * ([SPINNER_IN_MS]) and stays at least [MIN_SPINNER_MS] before [onInputs] lets it fade out.
     *
     * @param ready Whether the latest data is ready.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @param holdsSpinner Whether the spinner fades in and holds (publication refresh).
     * @return [LoadSwapPhase.SpinnerOut] when ready, else [LoadSwapPhase.Loading] (or
     *   [LoadSwapPhase.ContentIn] for ready data under Reduce Motion); always
     *   [LoadSwapPhase.Loading] with [holdsSpinner].
     */
    fun afterContentOut(ready: Boolean, reduceMotion: Boolean, holdsSpinner: Boolean = false): LoadSwapPhase = when {
        holdsSpinner || !ready -> LoadSwapPhase.Loading
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
