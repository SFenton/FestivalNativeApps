package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument

// region Sort draft

/**
 * Sort sheet draft: changes stay local until Apply; Reset restores defaults in
 * the draft only (spec `songs-sort` draft semantics).
 *
 * @property mode Draft mode.
 * @property ascending Draft direction.
 * @property appliedMode Saved mode.
 * @property appliedAscending Saved direction.
 */
data class SongSortDraft(
    val mode: SongSortMode,
    val ascending: Boolean,
    val appliedMode: SongSortMode = mode,
    val appliedAscending: Boolean = ascending,
) {
    /** Whether the draft differs from the saved sort. */
    val changed: Boolean get() = mode != appliedMode || ascending != appliedAscending

    /** Restore defaults in the draft. */
    fun reset(): SongSortDraft = copy(mode = SongSortMode.Title, ascending = true)

    companion object {
        /**
         * Choices shown in the sheet: Item Shop is removed while the Shop is hidden.
         *
         * @param hideShop Hide Item Shop setting.
         * @return Modes in menu order.
         */
        fun modes(hideShop: Boolean): List<SongSortMode> = SongSortMode.entries.filter { it != SongSortMode.Shop || !hideShop }
    }
}

// endregion

// region Filter draft

/**
 * Filter sheet draft over the public chart/difficulty filter, Shop toggles and the
 * selected player's score/FC checks. Hidden-chart checks stay in the draft but are
 * disclosed, and are removed on Apply (source sanitization).
 *
 * @property filter Public filter.
 * @property shopFilter Shop filter.
 * @property playerFilter Player filter.
 * @property visible Settings-visible charts.
 * @property applied Saved values to compare against.
 */
data class SongFilterDraft(
    val filter: SongFilter = SongFilter(),
    val shopFilter: SongShopFilter = SongShopFilter(),
    val playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    val visible: Set<Instrument> = Instrument.entries.toSet(),
    val applied: Triple<SongFilter, SongShopFilter, SongPlayerScoreFilter> = Triple(filter, shopFilter, playerFilter),
) {
    /** Whether the difficulty range is ordered. */
    val isValid: Boolean get() = filter.isValid

    /** Whether Apply would change anything. */
    val changed: Boolean get() = Triple(filter, shopFilter, playerFilter.scopedTo(visible)) != applied

    /** Whether Apply is enabled. */
    val canApply: Boolean get() = isValid && changed

    /** Whether hidden-chart score checks are saved but inactive. */
    val hasHiddenChecks: Boolean get() = playerFilter.scopedTo(visible) != playerFilter

    /** The values Apply persists (hidden-chart checks removed). */
    val result: Triple<SongFilter, SongShopFilter, SongPlayerScoreFilter>
        get() = Triple(filter.scopedTo(visible), shopFilter, playerFilter.scopedTo(visible))

    /** Clear the draft (Apply still required). */
    fun reset(): SongFilterDraft = copy(filter = SongFilter(), shopFilter = SongShopFilter(), playerFilter = SongPlayerScoreFilter())

    /**
     * Choose one chart or all.
     *
     * @param instrument Chart or null.
     * @return Updated draft.
     */
    fun withInstrument(instrument: Instrument?): SongFilterDraft = copy(filter = filter.copy(instrument = instrument))

    /**
     * Set the 1–7 difficulty range.
     *
     * @param min Lowest.
     * @param max Highest.
     * @return Updated draft.
     */
    fun withDifficulty(min: Int, max: Int): SongFilterDraft =
        copy(filter = filter.copy(minDifficulty = min.coerceIn(1, 7), maxDifficulty = max.coerceIn(1, 7)))

    /**
     * Toggle one per-chart check.
     *
     * @param kind Check.
     * @param instrument Chart.
     * @param enabled Value.
     * @return Updated draft.
     */
    fun withCheck(kind: SongScoreFilterKind, instrument: Instrument, enabled: Boolean): SongFilterDraft =
        copy(playerFilter = playerFilter.with(kind, instrument, enabled))

    /**
     * Toggle a global check over the visible charts.
     *
     * @param kind Check.
     * @param enabled Value.
     * @return Updated draft.
     */
    fun withAll(kind: SongScoreFilterKind, enabled: Boolean): SongFilterDraft =
        copy(playerFilter = playerFilter.withAll(kind, visible, enabled))

    /**
     * Whether a global check covers every visible chart.
     *
     * @param kind Check.
     * @return True when on.
     */
    fun allOn(kind: SongScoreFilterKind): Boolean = playerFilter.allVisible(kind, visible)

    companion object {
        /**
         * Start a draft from saved values (a corrupt saved player filter starts empty).
         *
         * @param filter Saved public filter.
         * @param shopFilter Saved Shop filter.
         * @param playerFilter Saved player filter, or null when corrupt.
         * @param visible Settings-visible charts.
         * @return Draft.
         */
        fun from(filter: SongFilter, shopFilter: SongShopFilter, playerFilter: SongPlayerScoreFilter?, visible: Set<Instrument>): SongFilterDraft {
            val player = playerFilter ?: SongPlayerScoreFilter()
            return SongFilterDraft(filter, shopFilter, player, visible, Triple(filter, shopFilter, player.scopedTo(visible)))
        }
    }
}

// endregion
