package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song

// region Placement

/**
 * One ranked song on one chart (web `PlayerSongRow` inputs).
 *
 * @property songId Song.
 * @property instrument Chart.
 * @property title Catalogue title, or the first eight ID characters when the song is missing (web fallback).
 * @property artist Catalogue artist ("" when missing).
 * @property year Release year.
 * @property artUrl Resolved artwork URL, or null.
 * @property rank Rank on the song's board.
 * @property totalEntries Board population.
 */
data class PlayerSongPlacement(
    val songId: String,
    val instrument: Instrument,
    val title: String,
    val artist: String,
    val year: Int?,
    val artUrl: String?,
    val rank: Int,
    val totalEntries: Int,
) {
    /** Placement as a percentage of the board, capped at 100 (web `Math.min(rank / te * 100, 100)`). */
    val percent: Double get() = minOf(rank.toDouble() / totalEntries * 100, 100.0)

    /** "Top 5%" pill (web `formatPercentileBucket`). */
    val bucket: String get() = ScoreFormatting.percentileBucket(rank, totalEntries) ?: "—"

    /** Whether the pill is gold (top 5%). */
    val isTopFive: Boolean get() = percent <= 5

    /** "Artist · Year" subtitle. */
    val subtitle: String get() = listOfNotNull(artist.takeIf { it.isNotEmpty() }, year?.toString()).joinToString(" · ")

    /** Screen-reader text for the whole row. */
    val announcement: String get() = listOf(title, subtitle.takeIf { it.isNotEmpty() }, bucket).filterNotNull().joinToString(", ")
}

// endregion

// region Top and bottom five

/**
 * One chart's best and worst placements (web `buildTopSongsItems`,
 * `pages/player/components/TopSongsSection.tsx`).
 *
 * @property instrument Chart.
 * @property top Up to five best placements, best first.
 * @property bottom The five worst placements, worst first; empty unless more than five are ranked.
 */
data class PlayerTopSongs(val instrument: Instrument, val top: List<PlayerSongPlacement>, val bottom: List<PlayerSongPlacement>) {
    /** Whether the chart has no ranked score (the section shows its empty state). */
    val isEmpty: Boolean get() = top.isEmpty()

    companion object {
        /** Rows per list. */
        const val LIST_SIZE = 5

        /**
         * Rank one chart's scores by `rank / totalEntries` (stable, so ties keep the profile's order).
         *
         * @param profile Validated profile.
         * @param instrument Chart.
         * @param songs Catalogue by song ID (titles, artists, art).
         * @param artworkUrl Resolve a catalogue art path (`FestivalApi.artworkUrl`).
         * @return Top five and, with more than five ranked scores, the bottom five.
         */
        fun build(profile: PlayerProfileResponse, instrument: Instrument, songs: Map<String, Song>, artworkUrl: (String?) -> String? = { it }): PlayerTopSongs {
            val ranked = profile.scores
                .filter { it.instrument == instrument && (it.rank ?: 0) > 0 && (it.totalEntries ?: 0) > 0 }
                .sortedBy { it.rank!!.toDouble() / it.totalEntries!! }
            fun placement(score: PlayerScore): PlayerSongPlacement {
                val song = songs[score.songId]
                return PlayerSongPlacement(
                    songId = score.songId,
                    instrument = instrument,
                    title = song?.title ?: score.songId.take(8),
                    artist = song?.artist ?: "",
                    year = song?.year,
                    artUrl = artworkUrl(song?.albumArt),
                    rank = score.rank!!,
                    totalEntries = score.totalEntries!!,
                )
            }
            val bottom = if (ranked.size > LIST_SIZE) ranked.takeLast(LIST_SIZE).reversed().map(::placement) else emptyList()
            return PlayerTopSongs(instrument, ranked.take(LIST_SIZE).map(::placement), bottom)
        }
    }
}

// endregion
