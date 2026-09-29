package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument

// region Instrument selector logic

/**
 * Pure rules behind the shared Instrument Selector (web
 * `components/common/InstrumentSelector.tsx`): hidden, disabled and muted charts,
 * optional/required selection, auto-compact arrow cycling and deferred selection.
 */
object InstrumentSelection {
    /** Web `Layout.demoInstrumentBtn`: one circle button's side. */
    const val BUTTON_DP = 64f

    /** Web `Gap.md` between buttons. */
    const val GAP_DP = 12f

    /**
     * Charts the selector renders.
     *
     * @param instruments Source list, in order.
     * @param hidden Charts removed from the rendered selector.
     * @return Rendered charts.
     */
    fun available(instruments: List<Instrument>, hidden: Set<Instrument>): List<Instrument> = instruments.filter { it !in hidden }

    /**
     * The selection the selector shows: a selection that is hidden or absent reads as none.
     *
     * @param selected Caller's selection.
     * @param available Rendered charts.
     * @return Effective selection.
     */
    fun effective(selected: Instrument?, available: List<Instrument>): Instrument? = selected?.takeIf { it in available }

    /**
     * Web auto-compact: switch to arrow cycling when the full row can't fit.
     *
     * @param widthDp Row width.
     * @param count Rendered charts.
     * @param buttonDp Button side.
     * @param gapDp Gap between buttons.
     * @return True for the compact arrows.
     */
    fun needsCompact(widthDp: Float, count: Int, buttonDp: Float = BUTTON_DP, gapDp: Float = GAP_DP): Boolean {
        if (widthDp <= 0f || count <= 0) return false
        return widthDp < count * buttonDp + (count - 1) * gapDp
    }

    /**
     * Result of tapping a full-row button.
     *
     * @param selected Effective selection.
     * @param tapped Tapped chart.
     * @param required Selection can't be cleared.
     * @return New selection (null clears).
     */
    fun press(selected: Instrument?, tapped: Instrument, required: Boolean): Instrument? =
        if (selected == tapped && !required) null else tapped

    /**
     * Next enabled index from [start] in [direction], wrapping (web `findNextSelectableIndex`).
     *
     * @param available Rendered charts.
     * @param start Starting index (may be −1 to start before the first).
     * @param direction +1 or −1.
     * @param disabled Charts that can't be selected.
     * @return Index, or −1 when none is enabled.
     */
    fun nextSelectable(available: List<Instrument>, start: Int, direction: Int, disabled: Set<Instrument>): Int {
        val size = available.size
        for (offset in 1..size) {
            val next = Math.floorMod(start + offset * direction, size)
            if (available[next] !in disabled) return next
        }
        return -1
    }

    /**
     * Compact arrow press.
     *
     * @param available Rendered charts.
     * @param selected Effective selection.
     * @param previewIndex Deferred preview index.
     * @param direction +1 (next) or −1 (previous).
     * @param deferSelection Arrows move a local preview while nothing is selected.
     * @param disabled Charts that can't be selected.
     * @return What changed.
     */
    fun cycle(
        available: List<Instrument>,
        selected: Instrument?,
        previewIndex: Int,
        direction: Int,
        deferSelection: Boolean,
        disabled: Set<Instrument>,
    ): Cycle {
        if (available.isEmpty()) return Cycle.None
        if (selected == null) {
            if (deferSelection) return Cycle.Preview(Math.floorMod(previewIndex + direction, available.size))
            val index = nextSelectable(available, if (direction == 1) -1 else 0, direction, disabled)
            return if (index >= 0) Cycle.Select(available[index]) else Cycle.None
        }
        val index = nextSelectable(available, available.indexOf(selected), direction, disabled)
        return if (index >= 0) Cycle.Select(available[index]) else Cycle.None
    }

    /**
     * Compact centre-button press.
     *
     * @param selected Effective selection.
     * @param preview Previewed chart.
     * @param required Selection can't be cleared.
     * @return New selection, or [Cycle.None].
     */
    fun compactPress(selected: Instrument?, preview: Instrument?, required: Boolean): Cycle = when {
        selected != null -> if (required) Cycle.None else Cycle.Select(null)
        preview != null -> Cycle.Select(preview)
        else -> Cycle.None
    }

    /** Outcome of a compact interaction. */
    sealed interface Cycle {
        /** Nothing changes. */
        data object None : Cycle

        /**
         * Commit a selection (null clears).
         *
         * @property instrument New selection.
         */
        data class Select(val instrument: Instrument?) : Cycle

        /**
         * Move the deferred preview.
         *
         * @property index New preview index.
         */
        data class Preview(val index: Int) : Cycle
    }
}

// endregion
