package com.festivalscoretracker.android.rankings

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.ui.leaderboards.RankingColumns
import com.festivalscoretracker.android.ui.leaderboards.rememberAccountColumns
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Compete's songs column yields to names on narrow cards (issue #38), measured with real text. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RankingColumnsUiTest {
    @get:Rule
    val rule = createComposeRule()

    /** Row width inside a Compete card on a 411 dp portrait phone (measured on the Pixel 9 emulator). */
    private val phoneRow = 362f

    private fun rows(vararg names: String): List<AccountRankingEntry> = names.mapIndexed { index, name ->
        AccountRankingEntry(
            accountId = "a".repeat(24) + index.toString().padStart(8, '0'),
            displayName = name,
            songsPlayed = 312 - index,
            totalChartedSongs = 340,
            totalScore = 123_456_789L - index,
            totalScoreRank = index + 1,
        )
    }

    /** Columns for each `(rows, fitNamesTo)` case, all composed at once. */
    private fun columns(vararg cases: Pair<List<AccountRankingEntry>, Float?>): List<RankingColumns> {
        val results = arrayOfNulls<RankingColumns>(cases.size)
        rule.setContent {
            FestivalTheme {
                cases.forEachIndexed { index, (entries, width) -> results[index] = rememberAccountColumns(entries, RankingMetric.TotalScore, fitNamesTo = width) }
            }
        }
        rule.waitForIdle()
        return results.map { requireNotNull(it) }
    }

    @Test
    fun songsShowOnlyWhenEveryNameFits() {
        val long = rows("Sixteen Chars Nm", "Short", "Another LongName")
        val short = rows("Ana", "Bo", "Cy")
        val (longPhone, shortPhone, longWide, longUnknown, longUnfitted) = columns(
            long to phoneRow,
            short to phoneRow,
            long to 700f,
            long to Float.NaN,
            long to null,
        )
        // A long name on a portrait phone: the whole card hides songs, keeping rank and rating widths.
        assertFalse(longPhone.showSongs)
        assertEquals(0.dp, longPhone.songs)
        assertEquals(longWide.rank, longPhone.rank)
        assertEquals(longWide.rating, longPhone.rating)
        // Short names, or a wide card, leave room for songs.
        assertTrue(shortPhone.showSongs)
        assertTrue(shortPhone.songs > 0.dp)
        assertTrue(longWide.showSongs)
        // Before the first layout the songs column waits.
        assertFalse(longUnknown.showSongs)
        // Other rankings (no name fitting) keep songs at any width.
        assertTrue(longUnfitted.showSongs)
    }
}
