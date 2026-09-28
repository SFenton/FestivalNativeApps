package com.festivalscoretracker.android.presentation.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
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
 * The selected player's scores as Songs may use them: available only when the
 * catalogue, the score read and the session observed the same publication.
 * Loading, 202, failure and mismatch stay explicit (never an empty success).
 *
 * @receiver Shared selected-profile state.
 * @param catalogPublication Generation observed for the catalogue.
 * @param current Latest observed generation.
 * @return Score source.
 */
fun SelectedProfileState.songScoreSource(catalogPublication: Int?, current: Int?): SongScoreSource {
    if (player == null) return SongScoreSource.NONE
    return when (status) {
        SelectedProfileStatus.None, SelectedProfileStatus.Loading -> SongScoreSource.LOADING
        SelectedProfileStatus.Syncing -> SongScoreSource.SYNCING
        SelectedProfileStatus.Failed -> SongScoreSource.failed(issue?.message ?: "Something went wrong.")
        SelectedProfileStatus.Available -> {
            val index = scoreIndex
            if (index != null && SongRelatedPublicationPolicy.matches(catalogPublication, observedPublicationId, current)) {
                val details = HashMap<String, Map<Instrument, SongScoreDetail>>(index.size)
                SongScoreSource(hasPlayer = true, detail = { songId, chart ->
                    details.getOrPut(songId) { index[songId]?.mapValues { it.value.toSongDetail() }.orEmpty() }[chart]
                })
            } else {
                SongScoreSource.PAUSED
            }
        }
    }
}

// endregion
