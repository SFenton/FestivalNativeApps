package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song

// region Category type

/**
 * Broad family a generated [SuggestionCategory] belongs to, used by the filter
 * sheet (web `SuggestionTypeId`, Apple `SuggestionCategoryType`). Band families
 * are not ported (no selected-band context) and the web's `lb_rival_*` type is
 * dead code there (no pipeline emits it), so neither has a case.
 *
 * @property key Persisted/stable key; equals the Apple raw value.
 * @property label Title Case label for the filter sheet.
 * @property filterDescription One-line explanation under the filter row.
 */
enum class SuggestionCategoryType(val key: String, val label: String, val filterDescription: String) {
    NearFC("nearFC", "Near FC", "Songs you're close to full-comboing."),
    StarProgress("starProgress", "Star Progress", "Push five-star runs to gold, or gain more stars."),
    Unplayed("unplayed", "Unplayed", "Songs you haven't played yet."),
    VarietyPack("varietyPack", "Variety Pack", "A mix of songs from different artists."),
    ArtistEssentials("artistEssentials", "Artist Essentials", "A selection of songs by a single artist."),
    ArtistDiscover("artistDiscover", "Artist Discover", "Unplayed songs from a single artist."),
    SameName("sameName", "Same Name", "Different tracks that share the same title."),
    AlmostElite("almostElite", "Almost Elite", "Top 5% — one good run could crack the top 1%."),
    PercentilePush("percentilePush", "Percentile Push", "Close to the next percentile bracket."),
    Stale("stale", "Stale Songs", "Songs you haven't played in a while."),
    PctImprove("pctImprove", "Percentile Improve", "Songs with room for percentile improvement."),
    NearMax("nearMax", "Near Max Score", "Songs close to the CHOpt theoretical max score."),
    SongRivals("songRivals", "Song Rivals", "Suggestions based on per-song rivals."),
    ;

    companion object {
        /**
         * Parse a persisted key.
         *
         * @param key Apple raw value such as `nearFC`.
         * @return The type, or null for an unknown key.
         */
        fun fromKey(key: String): SuggestionCategoryType? = entries.firstOrNull { it.key == key }
    }
}

// endregion

// region Score input

/**
 * The score fields the generator reads, decoupled from any wire model so the
 * profile read can evolve independently (Windows `SuggestionScore`).
 *
 * @property score Raw score.
 * @property accuracy Expanded accuracy (ten-thousandths of a percent, `1_000_000` = 100%).
 * @property isFullCombo Full-combo flag, never inferred from accuracy.
 * @property stars Stars 0–6 (6 = gold).
 * @property season Season the score was set.
 * @property rank One-based chart rank.
 * @property totalEntries Chart population.
 */
data class SuggestionScore(
    val score: Int,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
    val season: Int? = null,
    val rank: Int? = null,
    val totalEntries: Int? = null,
)

/** Selected player's scores: songId → chart → score. */
typealias SuggestionScoreIndex = Map<String, Map<Instrument, SuggestionScore>>

// endregion

// region Suggested song

/**
 * One song inside a [SuggestionCategory], annotated with the fields relevant to
 * that category (web/Apple `SuggestionSongItem`).
 *
 * @property song Catalogue row.
 * @property instrument Chart the row is about in a mixed-instrument category; null otherwise.
 * @property stars Current stars on that chart.
 * @property percent Accuracy as 0–100 (descaled).
 * @property fullCombo Whether that score is a full combo.
 * @property percentileDisplay Precomputed "Top N%" label.
 * @property rivalName Closest rival's display name (rival families).
 * @property rivalAccountId That rival's account ID.
 * @property rivalRankDelta Signed rank delta vs. the rival; negative means the rival leads.
 */
data class SuggestionSongItem(
    val song: Song,
    val instrument: Instrument? = null,
    val stars: Int? = null,
    val percent: Double? = null,
    val fullCombo: Boolean? = null,
    val percentileDisplay: String? = null,
    val rivalName: String? = null,
    val rivalAccountId: String? = null,
    val rivalRankDelta: Int? = null,
) {
    /** Stable row identity: `songId` or `songId|Solo_X`. */
    val id: String get() = instrument?.let { "${song.songId}|${it.wireId}" } ?: song.songId
}

// endregion

// region Category

/**
 * One titled group of suggested songs (web `SuggestionCategory` + generator key).
 *
 * @property key Generator key, unique within one mix.
 * @property title Card title.
 * @property description Card subtitle.
 * @property type Filter family.
 * @property instrument The single chart this category is about, or null when mixed.
 * @property songs Rows.
 */
data class SuggestionCategory(
    val key: String,
    val title: String,
    val description: String,
    val type: SuggestionCategoryType,
    val instrument: Instrument?,
    val songs: List<SuggestionSongItem>,
)

// endregion

// region Season fallback

/** Season used by "stale" categories when the catalogue hasn't reported one. */
object SuggestionSeason {
    /**
     * Catalogue season when positive, else the highest season in the player's own scores.
     *
     * @param currentSeason Catalogue-reported season.
     * @param scores Selected player's score index.
     * @return A season ≥ 0; 0 disables the stale families.
     */
    fun effective(currentSeason: Int?, scores: SuggestionScoreIndex): Int {
        if (currentSeason != null && currentSeason > 0) return currentSeason
        var highest = 0
        for (perInstrument in scores.values) {
            for (score in perInstrument.values) {
                val season = score.season ?: 0
                if (season > highest) highest = season
            }
        }
        return highest
    }
}

// endregion
