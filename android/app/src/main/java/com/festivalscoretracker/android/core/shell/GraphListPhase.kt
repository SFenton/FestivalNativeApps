package com.festivalscoretracker.android.core.shell

// region Graph card list

/**
 * Phases of the animated list under a graph card (web `useListAnimation` in `GraphCard`, issue
 * #169): when the list's items change, the old rows fade out (staggered), the list eases to its
 * new height with the rows hidden, then the new rows fade in (staggered).
 */
enum class GraphListPhase {
    /** Rows show at full opacity. */
    Idle,

    /** The old rows fade out and drift up (web `ListPhase.Out`). */
    Out,

    /** Rows hidden while the list eases to the new height (web shrink/grow step). */
    Resize,

    /** The new rows fade in and drift up into place (web `ListPhase.In`, `fadeInUp`). */
    In,
}

/**
 * Pure timing and sequencing rules for the shared graph card list (`ui/common/GraphCardList.kt`),
 * with the web `useListAnimation` constants.
 */
object GraphListPolicy {
    /** Out phase length for one row (web `OUT_BASE_MS`). */
    const val OUT_BASE_MS = 200

    /** Out stagger per row (web `OUT_STEP_MS`, the row `transition` delay `i * 40`). */
    const val OUT_STEP_MS = 40

    /** In phase length for one row (web `IN_BASE_MS`). */
    const val IN_BASE_MS = 300

    /** In stagger per row (web `IN_STEP_MS`, the row `fadeInUp` delay `i * 60`). */
    const val IN_STEP_MS = 60

    /** The list's height transition (web `HEIGHT_TRANSITION_MS`, `height 0.3s ease`). */
    const val HEIGHT_MS = 300

    /** One row's fade-out (web `opacity 0.15s ease-in`). */
    const val ROW_OUT_MS = 150

    /** One row's fade-in (web `fadeInUp 300ms ease-out`). */
    const val ROW_IN_MS = 300

    /** Upward drift of a row fading out, in dp (web `translateY(-8px)`). */
    const val ROW_OUT_DRIFT_DP = -8f

    /** Start offset of a row fading in, in dp (web `fadeInUp` from `translateY(12px)`). */
    const val ROW_IN_DRIFT_DP = 12f

    /** What to do when the list's items change. */
    enum class Plan {
        /** Same rows: update in place without animation. */
        Keep,

        /** Replace at once (reduced motion; web `skipAnimation`). */
        Instant,

        /** No rows on screen: show the new rows and fade them in. */
        Enter,

        /** Fade the old rows out, ease to the new height, fade the new rows in. */
        Swap,
    }

    /**
     * Plan a list change (web `useListAnimation` effect).
     *
     * @param same The new rows are the same as the last requested ones (web `areListsEqual`).
     * @param shownCount Rows on screen now.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return The change to perform.
     */
    fun plan(same: Boolean, shownCount: Int, reduceMotion: Boolean): Plan = when {
        same -> Plan.Keep
        reduceMotion -> Plan.Instant
        shownCount == 0 -> Plan.Enter
        else -> Plan.Swap
    }

    /**
     * Length of the out phase for [count] rows (web `outDuration`).
     *
     * @param count Rows fading out.
     * @return Milliseconds; 0 without rows.
     */
    fun outMillis(count: Int): Int = if (count > 0) OUT_BASE_MS + (count - 1) * OUT_STEP_MS else 0

    /**
     * Length of the in phase for [count] rows (web `inDuration`).
     *
     * @param count Rows fading in.
     * @return Milliseconds; 0 without rows.
     */
    fun inMillis(count: Int): Int = if (count > 0) IN_BASE_MS + (count - 1) * IN_STEP_MS else 0

    /**
     * How long a swap waits for the shown rows to fade out: rows already hidden by an
     * interrupted swap's resize step skip straight to the next resize.
     *
     * @param phase Current phase.
     * @param shownCount Rows on screen now.
     * @return Milliseconds.
     */
    fun outWait(phase: GraphListPhase, shownCount: Int): Int = if (phase == GraphListPhase.Resize) 0 else outMillis(shownCount)

    /**
     * Delay before row [index] starts fading out.
     *
     * @param index Row position.
     * @return Milliseconds.
     */
    fun rowOutDelay(index: Int): Int = index * OUT_STEP_MS

    /**
     * Delay before row [index] starts fading in.
     *
     * @param index Row position.
     * @return Milliseconds.
     */
    fun rowInDelay(index: Int): Int = index * IN_STEP_MS

    /**
     * Vertical offset of a row at [alpha] in [phase], in dp: drifting up while fading out and
     * rising from below while fading in.
     *
     * @param phase Current phase.
     * @param alpha The row's current opacity.
     * @return Offset in dp (negative is up).
     */
    fun rowDriftDp(phase: GraphListPhase, alpha: Float): Float = when (phase) {
        GraphListPhase.Out -> ROW_OUT_DRIFT_DP * (1f - alpha)
        GraphListPhase.In -> ROW_IN_DRIFT_DP * (1f - alpha)
        GraphListPhase.Idle, GraphListPhase.Resize -> 0f
    }
}

// endregion
