package com.festivalscoretracker.android.core.model

import kotlinx.serialization.Serializable

// region Wire models

/**
 * Chart difficulties keyed by the service's ordinary names (not instrument IDs).
 *
 * Values are raw 0–6 levels; `99` is the service's "not charted" sentinel.
 */
@Serializable
data class SongDifficulty(
    val guitar: Double? = null,
    val bass: Double? = null,
    val drums: Double? = null,
    val vocals: Double? = null,
    val proGuitar: Double? = null,
    val proBass: Double? = null,
    val proDrums: Double? = null,
    val proCymbals: Double? = null,
    val proVocals: Double? = null,
) {
    /**
     * Return the chart's finite raw difficulty, or null when it is not charted.
     *
     * @param instrument Chart to inspect.
     * @return Raw level, or null for absent, negative, non-finite or `99` values.
     */
    fun chartedValue(instrument: Instrument): Double? {
        val value = when (instrument) {
            Instrument.Lead -> guitar
            Instrument.Bass -> bass
            Instrument.Drums -> drums
            Instrument.Vocals -> vocals
            Instrument.ProLead -> proGuitar
            Instrument.ProBass -> proBass
            Instrument.Karaoke -> proVocals
            Instrument.ProCymbals -> proCymbals
            Instrument.ProDrums -> proDrums
        } ?: return null
        return if (value.isFinite() && value >= 0 && value != 99.0) value else null
    }
}

/**
 * Fields read from one `/api/songs` wire object. Unused wire keys (population
 * tiers, path provenance, genres…) are skipped by the decoder.
 */
@Serializable
data class Song(
    val songId: String,
    val title: String,
    val artist: String,
    val album: String? = null,
    val year: Int? = null,
    val durationSeconds: Int? = null,
    val albumArt: String? = null,
    val difficulty: SongDifficulty? = null,
    val sig: String? = null,
    val maxScores: Map<String, Int>? = null,
    val pathArtifactGenerationId: String? = null,
) {
    /** Whether Lead/Pro Lead should use the keys icon variant. */
    val usesKeyboardIcon: Boolean get() = sig == "Keyboard"

    /**
     * Whether an instrument has a playable chart, independent of visibility.
     *
     * @param instrument Chart to check.
     * @return True when its raw difficulty is present and charted.
     */
    fun supports(instrument: Instrument): Boolean = difficulty?.chartedValue(instrument) != null

    /**
     * This chart's engine-maximum score, if the service reported a positive one.
     *
     * @param instrument Chart to look up.
     * @return The max score or null.
     */
    fun maxScore(instrument: Instrument): Int? = maxScores?.get(instrument.wireId)?.takeIf { it > 0 }

    /** `m:ss` or `h:mm:ss` for a positive duration, like the web Song info block. */
    val formattedDuration: String?
        get() {
            val total = durationSeconds ?: return null
            if (total <= 0) return null
            val hours = total / 3_600
            val minutes = (total % 3_600) / 60
            val seconds = (total % 60).toString().padStart(2, '0')
            return if (hours > 0) {
                "$hours:${minutes.toString().padStart(2, '0')}:$seconds"
            } else {
                "$minutes:$seconds"
            }
        }

    /** Artist, year and duration joined with ` · `, omitting missing parts. */
    val subtitle: String
        get() = buildList {
            add(artist)
            year?.takeIf { it != 0 }?.let { add(it.toString()) }
            formattedDuration?.let { add(it) }
        }.joinToString(" · ")
}

/** `/api/songs` envelope. */
@Serializable
data class SongsResponse(
    val count: Int,
    val currentSeason: Int? = null,
    val songs: List<Song>,
) {
    /**
     * Reject contradictory catalogue cardinality instead of showing false data.
     *
     * @throws FestivalApiException.InvalidCatalogue when count or identity fields are inconsistent.
     */
    fun validate() {
        if (count < 0 || count != songs.size || songs.any { it.songId.isEmpty() || it.title.isEmpty() }) {
            throw FestivalApiException.InvalidCatalogue()
        }
    }
}

// endregion
