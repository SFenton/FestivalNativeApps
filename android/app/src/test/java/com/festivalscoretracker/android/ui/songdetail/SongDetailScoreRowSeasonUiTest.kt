package com.festivalscoretracker.android.ui.songdetail

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Song Detail instrument-card top-score rows (issues #62 and #170, web `resolveTopScoresColumns`):
 * the season column shows only on a card at least 520 dp wide, decided by the card's own
 * width (a two-column grid or hinge half is narrower than the window), at default and large text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h900dp-xxhdpi")
// Native graphics so text measures at its real width (the fitter's stacking depends on it).
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongDetailScoreRowSeasonUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val entries = listOf(
        LeaderboardEntry(accountId = "a".repeat(32), displayName = "First Player", score = 412_345, rank = 1, accuracy = 990_000.0, isFullCombo = false, stars = 6, season = 15),
        LeaderboardEntry(accountId = "b".repeat(32), displayName = "Second Player", score = 400_000, rank = 2, accuracy = 1_000_000.0, isFullCombo = true, stars = 5, season = 15),
        LeaderboardEntry(accountId = "", displayName = null, score = 399_999, rank = 3),
    )

    /** Deep ranks and long scores, as on a popular chart's appended player row. */
    private val longEntries = listOf(
        LeaderboardEntry(accountId = "c".repeat(32), displayName = "A Rather Long Display Name", score = 1_234_567, rank = 1_234_567, accuracy = 990_000.0, isFullCombo = false, stars = 6, season = 15),
        LeaderboardEntry(accountId = "d".repeat(32), displayName = "Another Long Display Name", score = 1_199_999, rank = 1_234_568, accuracy = 1_000_000.0, isFullCombo = true, stars = 5, season = 15),
    )

    private val cardWidth = mutableIntStateOf(0)

    /** Shows the card's [rows] [width] dp wide at [fontScale]; later calls only resize the card. */
    private fun showAt(width: Int, fontScale: Float = 1f, rows: List<LeaderboardEntry> = entries) {
        val first = cardWidth.intValue == 0
        cardWidth.intValue = width
        if (first) {
            rule.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    FestivalTheme {
                        Box(Modifier.width(cardWidth.intValue.dp)) {
                            val columns = rememberScoreColumns(rows)
                            LeaderboardSectionMember(columns, "card") {
                                rows.forEach { ScoreRow(it, columns = columns.plan) }
                            }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun seasons() = rule.onAllNodes(hasContentDescription("Season 15"), useUnmergedTree = true).fetchSemanticsNodes().size

    private fun seasonLabels() = rule.onAllNodes(hasText("S15"), useUnmergedTree = true).fetchSemanticsNodes().size

    private fun stars() = rule.onAllNodes(hasTestTag("fst.stars"), useUnmergedTree = true).fetchSemanticsNodes().size

    @Test
    fun cardsNarrowerThan520HideTheSeasonAndWiderOnesShowIt() {
        showAt(411)
        assertEquals(0, seasons())
        showAt(519)
        assertEquals(0, seasons())
        showAt(520)
        // Both seasoned rows show "S15"; the row without a season keeps an empty slot.
        assertEquals(2, seasons())
        assertEquals(2, seasonLabels())
        showAt(519)
        assertEquals(0, seasons())
    }

    @Test
    fun aStackedPlanStacksAtDefaultTextAndKeepsTheSeason() {
        // A plan the fitter stacked (one-line columns don't fit) draws the stacked row even at 100%.
        val plan = LeaderboardColumnPlan(gap = 12f, rankWidth = 40f, showMeta = true, metaWidth = 30f, valueWidth = 70f, showAccuracy = true, accuracyWidth = 56f, showStars = true, starsWidth = 116f, stacked = true)
        rule.setContent { FestivalTheme { Box(Modifier.width(520.dp)) { ScoreRow(entries.first(), columns = plan) } } }
        rule.waitForIdle()
        assertEquals(1, seasons())
        assertEquals(1, stars())
        // The stacked row lets the name wrap rather than marquee in a squeezed column.
        rule.onAllNodes(hasText("First Player"), useUnmergedTree = true).assertCountEquals(1)
    }

    @Test
    fun largeTextStackedRowsKeepTheWidthRule() {
        showAt(411, fontScale = 2f)
        assertEquals(0, seasons())
        showAt(900)
        assertEquals(2, seasons())
        // Stars from 700 dp stay too: the stacked rows wrap them rather than the section dropping them.
        assertEquals(2, stars())
    }

    @Test
    fun largeTextWithLongRanksAndScoresKeepsTheSeasonFrom520() {
        // Issue #170 review: the one-line columns (rank, name, season, score, accuracy at 200%)
        // overflow 520-640 dp, so the rows stack and keep the season instead of dropping it.
        showAt(519, fontScale = 2f, rows = longEntries)
        assertEquals(0, seasons())
        for (width in listOf(520, 600)) {
            showAt(width)
            assertEquals("season at $width dp", 2, seasons())
            assertEquals("S15 at $width dp", 2, seasonLabels())
            rule.onAllNodes(hasText("#1,234,567"), useUnmergedTree = true).assertCountEquals(1)
            rule.onAllNodes(hasText("1,234,567"), useUnmergedTree = true).assertCountEquals(1)
        }
    }
}
