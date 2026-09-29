package com.festivalscoretracker.android.core.shell

// region Load gate

/**
 * Page load phases (web `LoadPhase`, `@festival/core/runtime`): the spinner shows while a
 * page's data loads, fades out once it is ready, and only then does the content appear with
 * its staggered entrance, so a page never shows half-built content (operator batch 6.41).
 */
enum class LoadGatePhase {
    /** Data loading: only the spinner shows. */
    Loading,

    /** Data ready: the spinner fades out; content is not composed yet. */
    SpinnerOut,

    /** Content shows (and staggers in when it arrived after the spinner). */
    ContentIn,
}

/** Pure phase rules for the shared load gate (`ui/common/LoadGate.kt`). */
object LoadGatePolicy {
    /** Spinner fade-out (web `SPINNER_FADE_MS`). */
    const val SPINNER_FADE_MS = 500

    /**
     * Phase for a gate's first composition: content that is already available (cached data,
     * a page returned to) shows at once without a spinner, as the web skips it for visited pages.
     *
     * @param ready Whether the page's data is ready.
     * @return Starting phase.
     */
    fun initial(ready: Boolean): LoadGatePhase = if (ready) LoadGatePhase.ContentIn else LoadGatePhase.Loading

    /**
     * Next phase when readiness changes.
     *
     * @param current Current phase.
     * @param ready Whether the page's data is ready.
     * @param reduceMotion Remove animations / Reduce Motion: skip the spinner fade.
     * @return New phase.
     */
    fun onReady(current: LoadGatePhase, ready: Boolean, reduceMotion: Boolean): LoadGatePhase = when {
        // A reload (pull to refresh, new player) goes back to the spinner only from the spinner
        // phases; content that is already in stays up while it refreshes.
        !ready -> if (current == LoadGatePhase.ContentIn) LoadGatePhase.ContentIn else LoadGatePhase.Loading
        current == LoadGatePhase.Loading -> if (reduceMotion) LoadGatePhase.ContentIn else LoadGatePhase.SpinnerOut
        else -> current
    }

    /**
     * Phase after the spinner fade finished.
     *
     * @param current Current phase.
     * @return [LoadGatePhase.ContentIn] after a fade, otherwise unchanged.
     */
    fun afterFade(current: LoadGatePhase): LoadGatePhase = if (current == LoadGatePhase.SpinnerOut) LoadGatePhase.ContentIn else current

    /**
     * Whether content that just appeared should run its entrance (fade + stagger) rather than
     * show at once: only when it replaced a spinner, never for content that was ready at first
     * composition, and never under Reduce Motion.
     *
     * @param sawSpinner The gate showed its spinner at some point.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return True to animate the entrance.
     */
    fun animatesEntrance(sawSpinner: Boolean, reduceMotion: Boolean): Boolean = sawSpinner && !reduceMotion
}

// endregion
