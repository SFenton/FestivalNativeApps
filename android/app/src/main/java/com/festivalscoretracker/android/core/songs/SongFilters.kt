package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.shop.ShopSong
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Public chart filter

/**
 * Public-data filter: one charted instrument (web `instrumentFilter`) and its
 * hidden Song Intensity buckets (web `difficultyFilter` `false` entries, keys
 * [SongIntensityBucket.KEYS]). Intensity applies only with an instrument, like the web.
 *
 * @property instrument Single chart, or null for all.
 * @property excludedIntensities Hidden intensity buckets (1–7 bars, 0 = no chart value).
 */
data class SongFilter(val instrument: Instrument? = null, val excludedIntensities: Set<Int> = emptySet()) {
    /** Whether this filter changes the list (intensity buckets need an instrument). */
    val isActive: Boolean get() = instrument != null

    /** Whether every hidden bucket is a known key. */
    val isValid: Boolean get() = SongIntensityBucket.KEYS.containsAll(excludedIntensities)

    /**
     * Whether a song passes: charted for the instrument and in a shown intensity bucket.
     *
     * @param song Catalogue row.
     * @return True when kept.
     */
    fun matches(song: Song): Boolean {
        val chart = instrument ?: return true
        if (!song.supports(chart)) return false
        return SongIntensityBucket.of(song.difficulty?.chartedValue(chart)) !in excludedIntensities
    }

    /**
     * Drop a chart hidden in Settings (hidden buckets stay saved, inert without a chart).
     *
     * @param visible Settings-visible charts.
     * @return This filter, or one without the hidden chart.
     */
    fun scopedTo(visible: Set<Instrument>): SongFilter = if (instrument != null && instrument !in visible) copy(instrument = null) else this
}

// endregion

// region Shop filter

/**
 * Applied public Item Shop filter; Leaving Tomorrow implies membership.
 * Independent of any selected player's scores.
 *
 * @property inShop Require current Shop membership.
 * @property leavingTomorrow Require an offer leaving tomorrow.
 */
data class SongShopFilter(val inShop: Boolean = false, val leavingTomorrow: Boolean = false) {
    /** Whether either toggle is on. */
    val isActive: Boolean get() = inShop || leavingTomorrow

    /**
     * Filter rows without changing order.
     *
     * @param songs Rows.
     * @param offers Validated same-publication offers (callers pause instead of passing null).
     * @return Matching rows; a validated empty Shop yields an honest empty list.
     */
    fun filter(songs: List<Song>, offers: Map<String, ShopSong>): List<Song> {
        if (!isActive) return songs
        return songs.filter { song -> offers[song.songId]?.let { !leavingTomorrow || it.leavingTomorrow } == true }
    }
}

// endregion

// region Player score filter

/**
 * The independent per-chart checks (web `FilterModal`). [OverThreshold] exists
 * only while Filter Invalid Scores is on.
 *
 * @property label Title Case label.
 */
enum class SongScoreFilterKind(val label: String) {
    MissingScores("Missing Scores"),
    HasScores("Has Scores"),
    MissingFCs("Missing FCs"),
    HasFCs("Has FCs"),
    OverThreshold("Over CHOpt Threshold");

    companion object {
        /**
         * Checks the Filter sheet offers.
         *
         * @param filterInvalidScores Filter Invalid Scores setting.
         * @return The four score/FC checks, plus Over CHOpt Threshold when filtering invalid scores.
         */
        fun offered(filterInvalidScores: Boolean): List<SongScoreFilterKind> =
            if (filterInvalidScores) entries else entries - OverThreshold
    }
}

/**
 * One chart's score facts for filters and chips.
 *
 * @property score Score (0 = no score).
 * @property isFullCombo Explicit FC flag (never inferred from accuracy).
 * @property overThreshold The raw score shown exceeds the CHOpt maximum (Over CHOpt Threshold view).
 * @property stars Stars (6 = gold), or null.
 * @property season Season the score was set in, or null.
 * @property rank One-based rank, or null.
 * @property totalEntries Board population, or null.
 */
data class ChartScoreFacts(
    val score: Long,
    val isFullCombo: Boolean?,
    val overThreshold: Boolean = false,
    val stars: Int? = null,
    val season: Int? = null,
    val rank: Int? = null,
    val totalEntries: Int? = null,
) {
    /** Whether the chart has a positive score. */
    val scored: Boolean get() = score > 0

    /**
     * This score's key in a player-scoped bucket section.
     *
     * @param kind Season, Percentile or Stars.
     * @return Key (0 = no score).
     */
    fun bucket(kind: SongBucketKind): Int = when (kind) {
        SongBucketKind.Season -> SongSeasonBucket.of(scored, season)
        SongBucketKind.Percentile -> SongPercentileBucket.of(scored, rank, totalEntries)
        SongBucketKind.Stars -> if (scored) SongStarsBucket.of(stars) else 0
        SongBucketKind.Intensity -> 0
    }
}

/**
 * Selected-player predicates: AND within one chart's checks, OR across active
 * charts, then the Songs instrument's Season / Percentile / Stars buckets (web
 * `seasonFilter`/`percentileFilter`/`starsFilter`, applied only with one instrument).
 * Bounded, typed JSON so it persists safely; hidden charts stay saved but inactive;
 * cleared on confirmed deselection (Apple `SongPlayerScoreFilter`).
 *
 * @property missingScores Charts requiring no positive score.
 * @property hasScores Charts requiring a positive score.
 * @property missingFCs Charts without an explicit FC.
 * @property hasFCs Charts with an explicit FC.
 * @property overThreshold Charts showing only raw scores over the CHOpt maximum (Filter Invalid Scores only).
 * @property excludedSeasons Hidden season buckets on the Songs instrument (0 = no score).
 * @property excludedPercentiles Hidden [SongPercentileBucket] keys on the Songs instrument.
 * @property excludedStars Hidden [SongStarsBucket] keys on the Songs instrument.
 */
data class SongPlayerScoreFilter(
    val missingScores: Set<Instrument> = emptySet(),
    val hasScores: Set<Instrument> = emptySet(),
    val missingFCs: Set<Instrument> = emptySet(),
    val hasFCs: Set<Instrument> = emptySet(),
    val overThreshold: Set<Instrument> = emptySet(),
    val excludedSeasons: Set<Int> = emptySet(),
    val excludedPercentiles: Set<Int> = emptySet(),
    val excludedStars: Set<Int> = emptySet(),
) {
    /** Whether any check or bucket is set. */
    val isActive: Boolean
        get() = hasChecks || hasBucketChecks

    /** Whether any per-chart score/FC check is set. */
    val hasChecks: Boolean
        get() = missingScores.isNotEmpty() || hasScores.isNotEmpty() || missingFCs.isNotEmpty() || hasFCs.isNotEmpty() || overThreshold.isNotEmpty()

    /** Whether a Season, Percentile or Stars bucket is hidden (these need one Songs instrument). */
    val hasBucketChecks: Boolean
        get() = excludedSeasons.isNotEmpty() || excludedPercentiles.isNotEmpty() || excludedStars.isNotEmpty()

    /**
     * Whether this filter narrows the list for a Songs instrument (buckets need one, like the web).
     *
     * @param selectedInstrument Songs instrument filter, or null.
     * @return True when something applies.
     */
    fun appliesTo(selectedInstrument: Instrument?): Boolean = hasChecks || (hasBucketChecks && selectedInstrument != null)

    /**
     * The hidden keys of one bucket section.
     *
     * @param kind Season, Percentile or Stars.
     * @return Hidden keys.
     */
    fun excluded(kind: SongBucketKind): Set<Int> = when (kind) {
        SongBucketKind.Season -> excludedSeasons
        SongBucketKind.Percentile -> excludedPercentiles
        SongBucketKind.Stars -> excludedStars
        SongBucketKind.Intensity -> emptySet()
    }

    /**
     * Replace one bucket section's hidden keys.
     *
     * @param kind Season, Percentile or Stars.
     * @param keys Hidden keys.
     * @return Updated filter.
     */
    fun withExcluded(kind: SongBucketKind, keys: Set<Int>): SongPlayerScoreFilter = when (kind) {
        SongBucketKind.Season -> copy(excludedSeasons = keys)
        SongBucketKind.Percentile -> copy(excludedPercentiles = keys)
        SongBucketKind.Stars -> copy(excludedStars = keys)
        SongBucketKind.Intensity -> this
    }

    /**
     * Web `cleanFilters` for a stat-tile preset: every bucket shown again and this chart's
     * score/FC/threshold checks cleared (other charts' checks stay).
     *
     * @param instrument Chart.
     * @return Updated filter.
     */
    fun cleanedFor(instrument: Instrument): SongPlayerScoreFilter =
        SongScoreFilterKind.entries.fold(copy(excludedSeasons = emptySet(), excludedPercentiles = emptySet(), excludedStars = emptySet())) { filter, kind ->
            filter.with(kind, instrument, false)
        }

    /**
     * Show only one star bucket (web `instStarsUpdater`).
     *
     * @param key A [SongStarsBucket.KEYS] key.
     * @return Updated filter.
     */
    fun onlyStars(key: Int): SongPlayerScoreFilter = copy(excludedStars = SongStarsBucket.KEYS.toSet() - key)

    /**
     * Show only one percentile bucket (web `instPercentileBucketUpdater`).
     *
     * @param key A [SongPercentileBucket.KEYS] key.
     * @return Updated filter.
     */
    fun onlyPercentile(key: Int): SongPlayerScoreFilter = copy(excludedPercentiles = SongPercentileBucket.KEYS.toSet() - key)

    /**
     * The checks that apply under the current Filter Invalid Scores setting
     * (Over CHOpt Threshold stays saved but inactive while it is off, like the web).
     *
     * @param filterInvalidScores Filter Invalid Scores setting.
     * @return This filter, or one without [overThreshold].
     */
    fun effective(filterInvalidScores: Boolean): SongPlayerScoreFilter = if (filterInvalidScores || overThreshold.isEmpty()) this else copy(overThreshold = emptySet())

    /**
     * The set for one check.
     *
     * @param kind Check.
     * @return Charts.
     */
    fun charts(kind: SongScoreFilterKind): Set<Instrument> = when (kind) {
        SongScoreFilterKind.MissingScores -> missingScores
        SongScoreFilterKind.HasScores -> hasScores
        SongScoreFilterKind.MissingFCs -> missingFCs
        SongScoreFilterKind.HasFCs -> hasFCs
        SongScoreFilterKind.OverThreshold -> overThreshold
    }

    /**
     * Whether a check is set for a chart.
     *
     * @param kind Check.
     * @param instrument Chart.
     * @return True when set.
     */
    fun contains(kind: SongScoreFilterKind, instrument: Instrument): Boolean = instrument in charts(kind)

    /**
     * Set or clear one check without touching the other three.
     *
     * @param kind Check.
     * @param instrument Chart.
     * @param enabled New value.
     * @return Updated filter.
     */
    fun with(kind: SongScoreFilterKind, instrument: Instrument, enabled: Boolean): SongPlayerScoreFilter {
        val updated = if (enabled) charts(kind) + instrument else charts(kind) - instrument
        return when (kind) {
            SongScoreFilterKind.MissingScores -> copy(missingScores = updated)
            SongScoreFilterKind.HasScores -> copy(hasScores = updated)
            SongScoreFilterKind.MissingFCs -> copy(missingFCs = updated)
            SongScoreFilterKind.HasFCs -> copy(hasFCs = updated)
            SongScoreFilterKind.OverThreshold -> copy(overThreshold = updated)
        }
    }

    /**
     * The source's global switch: whether every visible chart has a check.
     *
     * @param kind Check.
     * @param visible Settings-visible charts.
     * @return True when all visible charts are set.
     */
    fun allVisible(kind: SongScoreFilterKind, visible: Set<Instrument>): Boolean = visible.isNotEmpty() && charts(kind).containsAll(visible)

    /**
     * Set or clear a check on every visible chart only (hidden choices stay saved).
     *
     * @param kind Check.
     * @param visible Settings-visible charts.
     * @param enabled New value.
     * @return Updated filter.
     */
    fun withAll(kind: SongScoreFilterKind, visible: Set<Instrument>, enabled: Boolean): SongPlayerScoreFilter =
        visible.fold(this) { filter, chart -> filter.with(kind, chart, enabled) }

    /**
     * Restrict to visible charts (hidden checks inactive, not erased).
     *
     * @param visible Settings-visible charts.
     * @return Scoped filter.
     */
    fun scopedTo(visible: Set<Instrument>): SongPlayerScoreFilter = copy(
        missingScores = missingScores intersect visible, hasScores = hasScores intersect visible,
        missingFCs = missingFCs intersect visible, hasFCs = hasFCs intersect visible, overThreshold = overThreshold intersect visible,
    )

    /**
     * OR across active charted instruments, AND within each chart's checks; then, with a
     * Songs instrument, its Season / Percentile / Stars buckets (web `useFilteredSongs`).
     *
     * @param songs Search-, chart- and Shop-filtered rows.
     * @param scores Facts for a matching, available index (null for no row).
     * @param visible Settings-visible charts.
     * @param selectedInstrument Optional single-chart Songs filter.
     * @return Matching rows in source order.
     */
    fun filter(
        songs: List<Song>,
        scores: (String, Instrument) -> ChartScoreFacts?,
        visible: Set<Instrument>,
        selectedInstrument: Instrument?,
    ): List<Song> {
        val scoped = scopedTo(visible)
        val active = Instrument.entries.filter { chart ->
            (selectedInstrument == null || selectedInstrument == chart) && SongScoreFilterKind.entries.any { scoped.contains(it, chart) }
        }
        val buckets = selectedInstrument?.takeIf { hasBucketChecks && it in visible }
        if (active.isEmpty() && buckets == null) return songs
        return songs.filter { song ->
            (active.isEmpty() || active.any { chart -> scoped.matches(song, chart, scores(song.songId, chart)) }) &&
                (buckets == null || inBuckets(scores(song.songId, buckets)))
        }
    }

    private fun inBuckets(facts: ChartScoreFacts?): Boolean {
        val shown = facts ?: ChartScoreFacts(0, null)
        return BUCKET_KINDS.none { kind -> shown.bucket(kind) in excluded(kind) }
    }

    private fun matches(song: Song, chart: Instrument, facts: ChartScoreFacts?): Boolean {
        if (!song.supports(chart)) return false
        val scored = (facts?.score ?: 0) > 0
        val fullCombo = facts?.isFullCombo == true
        val missing = chart in missingScores
        val has = chart in hasScores
        val missingFc = chart in missingFCs
        val hasFc = chart in hasFCs
        val scoreMatches = !(missing || has) || (missing && !scored) || (has && scored)
        val comboMatches = !(missingFc || hasFc) || (missingFc && !fullCombo) || (hasFc && fullCombo)
        val overMatches = chart !in overThreshold || (scored && facts?.overThreshold == true)
        return scoreMatches && comboMatches && overMatches
    }

    /**
     * Deterministic JSON (service-ordered chart IDs), or an empty string for the default.
     *
     * @return Stored text.
     */
    fun encoded(): String {
        if (!isActive) return ""
        fun ids(set: Set<Instrument>) = Instrument.entries.filter { it in set }.map { it.wireId }
        val stored = Stored(
            ids(missingScores), ids(hasScores), ids(missingFCs), ids(hasFCs), ids(overThreshold),
            excludedSeasons.sorted(), excludedPercentiles.sorted(), excludedStars.sorted(),
        )
        return Json.encodeToString(Stored.serializer(), stored)
    }

    @Serializable
    private data class Stored(
        val missingScores: List<String>,
        val hasScores: List<String>,
        val missingFCs: List<String>,
        val hasFCs: List<String>,
        val overThreshold: List<String> = emptyList(),
        val excludedSeasons: List<Int> = emptyList(),
        val excludedPercentiles: List<Int> = emptyList(),
        val excludedStars: List<Int> = emptyList(),
    )

    companion object {
        /** Largest accepted saved filter. */
        const val MAX_STORED_BYTES = 4_096

        /**
         * Decode a saved filter; corrupt data must block the list until an explicit Reset.
         *
         * @param raw Stored text; null/empty is the default.
         * @return The filter, or null when the saved value is corrupt (oversized, malformed,
         *   unknown or duplicate charts).
         */
        fun decodeSaved(raw: String?): SongPlayerScoreFilter? {
            if (raw.isNullOrEmpty()) return SongPlayerScoreFilter()
            if (raw.length > MAX_STORED_BYTES) return null
            val stored = try {
                Json.decodeFromString(Stored.serializer(), raw)
            } catch (error: SerializationException) {
                return null
            } catch (error: IllegalArgumentException) {
                return null
            }
            fun parse(ids: List<String>): Set<Instrument>? {
                val charts = ids.map { Instrument.fromWireId(it) ?: return null }
                return charts.toSet().takeIf { it.size == charts.size }
            }
            fun keys(values: List<Int>, valid: (Int) -> Boolean): Set<Int>? =
                values.toSet().takeIf { set -> set.size == values.size && values.all(valid) }
            return SongPlayerScoreFilter(
                parse(stored.missingScores) ?: return null,
                parse(stored.hasScores) ?: return null,
                parse(stored.missingFCs) ?: return null,
                parse(stored.hasFCs) ?: return null,
                parse(stored.overThreshold) ?: return null,
                keys(stored.excludedSeasons) { it in 0..SongSeasonBucket.MAX_SEASON } ?: return null,
                keys(stored.excludedPercentiles) { it in SongPercentileBucket.KEYS } ?: return null,
                keys(stored.excludedStars) { it in SongStarsBucket.KEYS } ?: return null,
            )
        }

        /** Player-scoped bucket sections. */
        private val BUCKET_KINDS = SongBucketKind.entries.filter { it.playerScoped }
    }
}

// endregion
