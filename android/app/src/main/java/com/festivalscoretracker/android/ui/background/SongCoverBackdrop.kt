package com.festivalscoretracker.android.ui.background

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import com.festivalscoretracker.android.presentation.BackgroundController

// region Song cover backdrop

/**
 * Shows a song's static album art on the shared [ArtworkBackground] while the calling
 * song-scoped page is composed (web `PageBackground src={song.albumArt}`; pattern
 * `song-header`). Song Detail, the solo song leaderboard and the song band leaderboard
 * each call it, so a pushed page keeps the cover even after the previous destination
 * pops its own focus (issue #317).
 *
 * @param background Shared backdrop controller, or null in previews and tests without one.
 * @param albumArt Song `albumArt`; null (song still loading or no art) shows nothing extra.
 */
@Composable
fun SongCoverBackdrop(background: BackgroundController?, albumArt: String?) {
    DisposableEffect(background, albumArt) {
        val token = background?.pushFocus(albumArt)
        onDispose { background?.popFocus(token) }
    }
}

// endregion
