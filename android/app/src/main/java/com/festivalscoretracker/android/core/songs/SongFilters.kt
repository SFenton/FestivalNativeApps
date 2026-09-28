package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.shop.ShopSong
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Public chart filter

/**
 * Public-data filter: one charted instrument and an inclusive 1–7 display
 * difficulty range for it (or for any charted instrument when none is chosen).
 *
 * @property instrument Single chart, or null for all.
 * @property minDifficulty Lowest display level, 1–7.
 * @property maxDifficulty Highest display level, 1–7.
 */
data class SongFilter(val instrument: Instrument? = null, val minDifficulty: Int = 1, val maxDifficulty: Int = 7) {
    /** Whether this filter changes the list. */
    val isActive: Boolean get() = instrument != null || minDifficulty > 1 || maxDifficulty < 7

    /** Whether the range is in bounds and ordered. */
    val isValid: Boolean get() = minDifficulty in 1..7 && maxDifficulty in 1..7 && minDifficulty <= maxDifficulty

    /**
     * Whether a song passes.
     *
     * @param song Catalogue row.
     * @return True when kept.
     */
    fun matches(song: Song): Boolean {
        val chart = instrument
        if (chart != null) return song.difficulty?.chartedValue(chart)?.let { inRange(it) } == true
        if (minDifficulty <= 1 && maxDifficulty >= 7) return true
        return Instrument.entries.any { song.difficulty?.chartedValue(it)?.let(::inRange) == true }
    }

    /**
     * Drop a chart hidden in Settings.
     *
     * @param visible Settings-visible charts.
     * @return This filter, or one without the hidden chart.
     */
    fun scopedTo(visible: Set<Instrument>): SongFilter = if (instrument != null && instrument !in visible) copy(instrument = null) else this

    private fun inRange(raw: Double): Boolean {
        val bars = DifficultyMeterSpec.filledBars(raw, raw = true) ?: return false
        return bars in minDifficulty..maxDifficulty
    }
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
 */
data class ChartScoreFacts(val score: Long, val isFullCombo: Boolean?, val overThreshold: Boolean = false)

/**
 * Selected-player predicates: AND within one chart's checks, OR across active
 * charts. Bounded, typed JSON so it persists safely; hidden charts stay saved but
 * inactive; cleared on confirmed deselection (Apple `SongPlayerScoreFilter`).
 *
 * @property missingScores Charts requiring no positive score.
 * @property hasScores Charts requiring a positive score.
 * @property missingFCs Charts without an explicit FC.
 * @property hasFCs Charts with an explicit FC.
 * @property overThreshold Charts showing only raw scores over the CHOpt maximum (Filter Invalid Scores only).
 */
data class SongPlayerScoreFilter(
    val missingScores: Set<Instrument> = emptySet(),
    val hasScores: Set<Instrument> = emptySet(),
    val missingFCs: Set<Instrument> = emptySet(),
    val hasFCs: Set<Instrument> = emptySet(),
    val overThreshold: Set<Instrument> = emptySet(),
) {
    /** Whether any check is set. */
    val isActive: Boolean
        get() = missingScores.isNotEmpty() || hasScores.isNotEmpty() || missingFCs.isNotEmpty() || hasFCs.isNotEmpty() || overThreshold.isNotEmpty()

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
    fun scopedTo(visible: Set<Instrument>): SongPlayerScoreFilter = SongPlayerScoreFilter(
        missingScores intersect visible, hasScores intersect visible, missingFCs intersect visible, hasFCs intersect visible,
        overThreshold intersect visible,
    )

    /**
     * OR across active charted instruments, AND within each chart's checks.
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
        if (active.isEmpty()) return songs
        return songs.filter { song -> active.any { chart -> scoped.matches(song, chart, scores(song.songId, chart)) } }
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
        return Json.encodeToString(Stored.serializer(), Stored(ids(missingScores), ids(hasScores), ids(missingFCs), ids(hasFCs), ids(overThreshold)))
    }

    @Serializable
    private data class Stored(
        val missingScores: List<String>,
        val hasScores: List<String>,
        val missingFCs: List<String>,
        val hasFCs: List<String>,
        val overThreshold: List<String> = emptyList(),
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
            return SongPlayerScoreFilter(
                parse(stored.missingScores) ?: return null,
                parse(stored.hasScores) ?: return null,
                parse(stored.missingFCs) ?: return null,
                parse(stored.hasFCs) ?: return null,
                parse(stored.overThreshold) ?: return null,
            )
        }
    }
}

// endregion
