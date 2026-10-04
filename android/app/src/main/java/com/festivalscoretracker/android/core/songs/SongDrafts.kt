package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.SettingsOrder

// region Sort draft

/**
 * Sort sheet state. The Android sheet applies every change live (operator rule: no
 * Cancel/Apply or discard confirmation), so Reset restores and applies the defaults;
 * [changed] still compares against the saved sort.
 *
 * @property mode Draft mode.
 * @property ascending Draft direction.
 * @property metadataOrder Draft metadata sort priority (every field once).
 * @property appliedMode Saved mode.
 * @property appliedAscending Saved direction.
 * @property appliedMetadataOrder Saved metadata sort priority.
 */
data class SongSortDraft(
    val mode: SongSortMode,
    val ascending: Boolean,
    val metadataOrder: List<MetadataField> = MetadataField.entries,
    val appliedMode: SongSortMode = mode,
    val appliedAscending: Boolean = ascending,
    val appliedMetadataOrder: List<MetadataField> = metadataOrder,
) {
    /** Whether the draft differs from the saved sort. */
    val changed: Boolean get() = mode != appliedMode || ascending != appliedAscending || metadataOrder != appliedMetadataOrder

    /** Restore defaults in the draft (web: mode, direction and metadata priority). */
    fun reset(): SongSortDraft = copy(mode = SongSortMode.Title, ascending = true, metadataOrder = MetadataField.entries)

    /**
     * Move one visible metadata field up or down the priority list; hidden fields
     * keep their saved place after the visible ones (like Settings' visual order).
     *
     * @param visibleMetadata Settings-visible fields.
     * @param index Position among the visible fields.
     * @param offset −1 (up) or +1 (down).
     * @return Updated draft; unchanged at either end.
     */
    fun move(visibleMetadata: Set<MetadataField>, index: Int, offset: Int): SongSortDraft {
        val visible = visiblePriority(metadataOrder, visibleMetadata)
        if (index !in visible.indices || index + offset !in visible.indices) return this
        val moved = SettingsOrder.move(visible, index, offset)
        return copy(metadataOrder = moved + metadataOrder.filter { it !in visibleMetadata })
    }

    companion object {
        /**
         * General choices (web "Mode"): Item Shop is removed while the Shop is hidden;
         * Has FC and Last Played need a selected player (the web lists Has FC
         * anonymously, where it can only produce title order).
         *
         * @param hideShop Hide Item Shop setting.
         * @param hasPlayer A player is selected.
         * @return Modes in menu order.
         */
        fun modes(hideShop: Boolean, hasPlayer: Boolean = false): List<SongSortMode> = SongSortMode.entries.filter { mode ->
            when (mode.group) {
                SongSortGroup.Catalog -> mode != SongSortMode.Shop || !hideShop
                SongSortGroup.Player -> hasPlayer
                SongSortGroup.SingleChart -> false
            }
        }

        /**
         * Single-chart choices (web "Filtered Instrument Sort Mode"): only with a player
         * and a single-chart filter; a mode whose metadata field Settings hides is removed.
         *
         * @param hasPlayer A player is selected.
         * @param chart Settings-visible single-chart filter.
         * @param visibleMetadata Settings-visible metadata fields.
         * @return Modes in menu order.
         */
        fun chartModes(hasPlayer: Boolean, chart: Instrument?, visibleMetadata: Set<MetadataField>): List<SongSortMode> {
            if (!hasPlayer || chart == null) return emptyList()
            return SongSortMode.entries.filter { it.group == SongSortGroup.SingleChart && (it.metadata == null || it.metadata in visibleMetadata) }
        }

        /**
         * Metadata priority rows the sheet shows: visible fields in draft order (hidden
         * ones keep their place when reordered).
         *
         * @param order Full order.
         * @param visibleMetadata Settings-visible fields.
         * @return Visible fields in order.
         */
        fun visiblePriority(order: List<MetadataField>, visibleMetadata: Set<MetadataField>): List<MetadataField> = order.filter { it in visibleMetadata }

        /**
         * The sort to keep when a filter change removes the single-chart filter (web
         * `normalizeSongSettings`: single-chart modes fall back to Title ascending).
         *
         * @param mode Saved mode.
         * @param ascending Saved direction.
         * @param chart New single-chart filter.
         * @return Mode and direction to persist.
         */
        fun normalized(mode: SongSortMode, ascending: Boolean, chart: Instrument?): Pair<SongSortMode, Boolean> =
            if (mode.needsChart && chart == null) SongSortMode.Title to true else mode to ascending

        /**
         * TalkBack state of the Sort button, which otherwise shows a changed sort only by
         * its gold tint.
         *
         * @param mode Saved mode.
         * @param ascending Saved direction.
         * @return For example "Artist, descending".
         */
        fun describe(mode: SongSortMode, ascending: Boolean): String = "${mode.label}, ${if (ascending) "ascending" else "descending"}"
    }
}

// endregion

// region Filter draft

/**
 * Filter sheet draft over the General filters (Year, Duration, Item Shop, Double Bass), the
 * public instrument/intensity filter and the
 * selected player's score/FC checks and Season/Percentile/Stars buckets. Hidden-chart checks stay in the draft but are
 * disclosed, and are removed on Apply (source sanitization).
 *
 * @property filter Public filter.
 * @property general General filters (Year, Duration, Item Shop, Double Bass).
 * @property playerFilter Player filter.
 * @property visible Settings-visible charts.
 * @property applied Saved values to compare against.
 */
data class SongFilterDraft(
    val filter: SongFilter = SongFilter(),
    val general: SongGeneralFilter = SongGeneralFilter(),
    val playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    val visible: Set<Instrument> = Instrument.entries.toSet(),
    val applied: Triple<SongFilter, SongGeneralFilter, SongPlayerScoreFilter> = Triple(filter, general, playerFilter),
) {
    /** Whether every hidden intensity, decade and duration bucket is a known key. */
    val isValid: Boolean get() = filter.isValid && general.isValid

    /** Whether Apply would change anything. */
    val changed: Boolean get() = Triple(filter, general, playerFilter.scopedTo(visible)) != applied

    /** Whether Apply is enabled. */
    val canApply: Boolean get() = isValid && changed

    /** Whether hidden-chart score checks are saved but inactive. */
    val hasHiddenChecks: Boolean get() = playerFilter.scopedTo(visible) != playerFilter

    /** The values Apply persists (hidden-chart checks removed). */
    val result: Triple<SongFilter, SongGeneralFilter, SongPlayerScoreFilter>
        get() = Triple(filter.scopedTo(visible), general, playerFilter.scopedTo(visible))

    /** Clear the draft (Apply still required). */
    fun reset(): SongFilterDraft = copy(filter = SongFilter(), general = SongGeneralFilter(), playerFilter = SongPlayerScoreFilter())

    /**
     * Choose one chart or all.
     *
     * @param instrument Chart or null.
     * @return Updated draft.
     */
    fun withInstrument(instrument: Instrument?): SongFilterDraft = copy(filter = filter.copy(instrument = instrument))

    /**
     * Hidden keys of one "Selected Instrument Filters" section.
     *
     * @param kind Section.
     * @return Hidden keys.
     */
    fun excluded(kind: SongBucketKind): Set<Int> =
        if (kind == SongBucketKind.Intensity) filter.excludedIntensities else playerFilter.excluded(kind)

    /**
     * Show or hide one bucket (web toggle rows: every bucket starts shown).
     *
     * @param kind Section.
     * @param key Bucket key.
     * @param shown New value.
     * @return Updated draft.
     */
    fun withBucket(kind: SongBucketKind, key: Int, shown: Boolean): SongFilterDraft {
        val keys = if (shown) excluded(kind) - key else excluded(kind) + key
        return withExcluded(kind, keys)
    }

    /**
     * Select All (none hidden) or Clear All (every key hidden) for one section.
     *
     * @param kind Section.
     * @param keys Every key the section lists.
     * @param shown True for Select All.
     * @return Updated draft.
     */
    fun withAllBuckets(kind: SongBucketKind, keys: List<Int>, shown: Boolean): SongFilterDraft =
        withExcluded(kind, if (shown) emptySet() else keys.toSet())

    private fun withExcluded(kind: SongBucketKind, keys: Set<Int>): SongFilterDraft =
        if (kind == SongBucketKind.Intensity) copy(filter = filter.copy(excludedIntensities = keys)) else copy(playerFilter = playerFilter.withExcluded(kind, keys))

    /**
     * Show or hide one Year or Duration bucket (every bucket starts shown).
     *
     * @param kind Year or Duration.
     * @param key Decade or minute bucket.
     * @param shown New value.
     * @return Updated draft.
     */
    fun withGeneralBucket(kind: SongGeneralBucketKind, key: Int, shown: Boolean): SongFilterDraft {
        val hidden = general.excluded(kind)
        return copy(general = general.withExcluded(kind, if (shown) hidden - key else hidden + key))
    }

    /**
     * Year/Duration Select All (nothing hidden, web `{}`) or Clear All (every listed key hidden).
     *
     * @param kind Year or Duration.
     * @param keys Every key the section lists.
     * @param shown True for Select All.
     * @return Updated draft.
     */
    fun withAllGeneralBuckets(kind: SongGeneralBucketKind, keys: List<Int>, shown: Boolean): SongFilterDraft =
        copy(general = general.withExcluded(kind, if (shown) emptySet() else general.excluded(kind) + keys))

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
         * @param general Saved General filters.
         * @param playerFilter Saved player filter, or null when corrupt.
         * @param visible Settings-visible charts.
         * @return Draft.
         */
        fun from(filter: SongFilter, general: SongGeneralFilter, playerFilter: SongPlayerScoreFilter?, visible: Set<Instrument>): SongFilterDraft {
            val player = playerFilter ?: SongPlayerScoreFilter()
            return SongFilterDraft(filter, general, player, visible, Triple(filter, general, player.scopedTo(visible)))
        }
    }
}

// endregion
