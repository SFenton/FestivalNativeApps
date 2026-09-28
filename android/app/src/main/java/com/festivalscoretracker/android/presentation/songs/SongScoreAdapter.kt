package com.festivalscoretracker.android.presentation.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
import com.festivalscoretracker.android.core.songs.InvalidScorePolicy
import com.festivalscoretracker.android.core.songs.InvalidScoreResolution
import com.festivalscoretracker.android.core.songs.SongScoreDetail
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.presentation.profile.SelectedProfileStatus

// region Score adapter

/**
 * Map a validated wire score to the row detail (valid last-played preferred).
 *
 * @receiver Wire row.
 * @return Detail.
 */
fun PlayerScore.toSongDetail(): SongScoreDetail = SongScoreDetail(
    score = score.toLong(),
    accuracy = accuracy,
    isFullCombo = isFullCombo,
    stars = stars,
    season = season,
    difficulty = difficulty,
    rank = rank,
    totalEntries = totalEntries,
    lastPlayedAt = validLastPlayedAt ?: lastPlayedAt,
)

/**
 * Filter Invalid Scores inputs for one rebuild.
 *
 * @property leeway Leeway percent.
 * @property songs Catalogue rows by ID (CHOpt maxima and population tiers).
 * @property overThreshold Charts whose raw invalid scores stay visible (Over CHOpt Threshold filter).
 */
data class InvalidScoreContext(
    val leeway: Double,
    val songs: Map<String, Song>,
    val overThreshold: Set<Instrument> = emptySet(),
)

/**
 * The selected player's scores as Songs may use them: available only when the
 * catalogue, the score read and the session observed the same publication.
 * Loading, 202, failure and mismatch stay explicit (never an empty success).
 * With [invalid], each chart shows its effective score (the next valid score, or
 * none) and reports why (web `SongsPage` substitution).
 *
 * @receiver Shared selected-profile state.
 * @param catalogPublication Generation observed for the catalogue.
 * @param current Latest observed generation.
 * @param invalid Filter Invalid Scores context, or null when the setting is off.
 * @return Score source.
 */
fun SelectedProfileState.songScoreSource(catalogPublication: Int?, current: Int?, invalid: InvalidScoreContext? = null): SongScoreSource {
    if (player == null) return SongScoreSource.NONE
    return when (status) {
        SelectedProfileStatus.None, SelectedProfileStatus.Loading -> SongScoreSource.LOADING
        SelectedProfileStatus.Syncing -> SongScoreSource.SYNCING
        SelectedProfileStatus.Failed -> SongScoreSource.failed(issue?.message ?: "Something went wrong.")
        SelectedProfileStatus.Available -> {
            val index = scoreIndex
            if (index != null && SongRelatedPublicationPolicy.matches(catalogPublication, observedPublicationId, current)) {
                val resolved = HashMap<String, Map<Instrument, InvalidScoreResolution>>(index.size)
                fun song(songId: String) = resolved.getOrPut(songId) {
                    index[songId]?.mapValues { (chart, score) -> resolve(score, songId, chart, invalid) }.orEmpty()
                }
                SongScoreSource(
                    hasPlayer = true,
                    detail = { songId, chart -> song(songId)[chart]?.detail },
                    invalid = { songId ->
                        if (invalid == null) emptyMap() else song(songId).mapNotNull { (chart, resolution) -> resolution.reason?.let { chart to it } }.toMap()
                    },
                )
            } else {
                SongScoreSource.PAUSED
            }
        }
    }
}

private fun resolve(score: PlayerScore, songId: String, chart: Instrument, invalid: InvalidScoreContext?): InvalidScoreResolution {
    val raw = score.toSongDetail()
    if (invalid == null) return InvalidScoreResolution(raw, null)
    return InvalidScorePolicy.resolve(score, raw, invalid.songs[songId], chart, invalid.leeway, chart in invalid.overThreshold)
}

// endregion
