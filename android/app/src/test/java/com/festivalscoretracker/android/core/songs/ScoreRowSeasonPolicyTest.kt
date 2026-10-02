package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.songs.ScoreRowSeasonPolicy.Surface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #62: the song page shows a score's season only on wide rows, and always in the tapped-bar detail. */
class ScoreRowSeasonPolicyTest {
    @Test
    fun breakpointMatchesTheLeaderboardSeasonColumn() {
        assertEquals(520f, ScoreRowSeasonPolicy.BREAKPOINT)
        assertEquals(LeaderboardColumnLayout.SEASON_BREAKPOINT, ScoreRowSeasonPolicy.BREAKPOINT)
    }

    @Test
    fun widthGatedRowsShowTheSeasonFrom520() {
        for (surface in listOf(Surface.HistoryList, Surface.TopScores)) {
            for (narrow in listOf(0f, 360f, 412f, 519.9f, Float.NaN, Float.NEGATIVE_INFINITY, Float.POSITIVE_INFINITY)) {
                assertFalse("$surface at $narrow", ScoreRowSeasonPolicy.showsSeason(surface, narrow, 40))
                assertFalse("$surface column at $narrow", ScoreRowSeasonPolicy.showsColumn(surface, narrow))
            }
            for (wide in listOf(520f, 600f, 1200f)) {
                assertTrue("$surface at $wide", ScoreRowSeasonPolicy.showsSeason(surface, wide, 40))
                assertTrue("$surface column at $wide", ScoreRowSeasonPolicy.showsColumn(surface, wide))
            }
        }
    }

    @Test
    fun detailRowAlwaysShowsAKnownSeason() {
        for (width in listOf(0f, 280f, 519f, 520f, Float.NaN)) {
            assertTrue(ScoreRowSeasonPolicy.showsSeason(Surface.HistoryDetail, width, 40))
            assertTrue(ScoreRowSeasonPolicy.showsColumn(Surface.HistoryDetail, width))
        }
    }

    @Test
    fun missingOrInvalidSeasonsNeverShow() {
        for (surface in Surface.entries) {
            for (season in listOf(null, 0, -3)) {
                assertFalse("$surface $season", ScoreRowSeasonPolicy.showsSeason(surface, 900f, season))
            }
        }
    }
}
