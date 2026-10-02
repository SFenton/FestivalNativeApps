package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout

// region Score row season policy

/**
 * When a score row on the song page shows the season the score was achieved (issues #32
 * and #62), ported from the web's width rules:
 *
 * - Score History list rows: at least 520 wide (web `QUERY_SHOW_SEASON`, used by
 *   `ScoreHistoryChart` `renderListItem`). The web compares the viewport. Android compares the
 *   rows' own measured width, so a split or half-hinge pane that is narrower than the window
 *   still hides the pill.
 * - The tapped bar's detail row: always, when the score has a season (`renderDetailCard`
 *   passes `showSeason={point.season != null}`).
 * - Top-score rows in an instrument card: card width at least 520 (`resolveTopScoresColumns`).
 *   Android already applies this through [LeaderboardColumnLayout.fit]. It is listed here so
 *   the song page's season rule lives in one place.
 *
 * CSS pixels on the web correspond to dp on Android.
 */
object ScoreRowSeasonPolicy {
    /** Web `MEDIUM_BREAKPOINT` / `SEASON_BREAKPOINT` (520 dp). */
    const val BREAKPOINT: Float = LeaderboardColumnLayout.SEASON_BREAKPOINT

    /** The song-page row kinds that can carry a season pill. */
    enum class Surface {
        /** A Score History list row, measured against the rows' width. */
        HistoryList,

        /** The row shown under the Score History chart for a tapped bar. */
        HistoryDetail,

        /** A top-score row in an instrument card, measured against the card width. */
        TopScores,
    }

    /**
     * Whether a row of [surface] shows a season pill at [width].
     *
     * @param surface The row kind.
     * @param width The rows' width in dp for [Surface.HistoryList], the card width for
     *   [Surface.TopScores]; ignored for [Surface.HistoryDetail]. Zero, NaN or unmeasured
     *   widths hide the season (web `resolveTopScoresColumns(0)`).
     * @param season The score's season, if the service reported one.
     * @return True only when the width rule allows it and the season is positive.
     */
    fun showsSeason(surface: Surface, width: Float, season: Int?): Boolean =
        season != null && season > 0 && showsColumn(surface, width)

    /**
     * Whether rows of [surface] show the season column at [width], independent of any one
     * row's season.
     *
     * @param surface The row kind.
     * @param width As in [showsSeason].
     * @return True when the column is on at this width.
     */
    fun showsColumn(surface: Surface, width: Float): Boolean = when (surface) {
        Surface.HistoryDetail -> true
        Surface.HistoryList, Surface.TopScores -> width.isFinite() && width >= BREAKPOINT
    }
}

// endregion
