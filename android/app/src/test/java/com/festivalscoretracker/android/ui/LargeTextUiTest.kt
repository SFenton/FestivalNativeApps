package com.festivalscoretracker.android.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.profile.StatGridColumns
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.chartAxisTextStyle
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.common.oneLineUnlessLarge
import com.festivalscoretracker.android.ui.leaderboards.AccountRankingRow
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** 200% font scale: rows stack, names wrap instead of disappearing into an ellipsis. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LargeTextUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val longName = "Synthetic Player With A Long Name"

    /** Content at [fontScale] in a phone-width column. */
    private fun show(fontScale: Float, content: @Composable () -> Unit) {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    Column(Modifier.width(320.dp)) { content() }
                }
            }
        }
    }

    @Test
    fun scoreRowKeepsTheWholeNameAt200Percent() {
        show(2f) {
            ScoreRow(LeaderboardEntry(accountId = "a".repeat(32), displayName = longName, score = 99_900, rank = 1_234, accuracy = 980_000.0), navigable = true)
        }
        // Stacked: the name takes the row's width (wrapping), not the sliver left beside
        // rank, score and pill.
        val name = rule.onNodeWithText(longName, useUnmergedTree = true).getUnclippedBoundsInRoot()
        val rank = rule.onNodeWithText("#1,234", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val score = rule.onNodeWithText("99,900", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("name $name rank $rank score $score", name.width > 150.dp)
    }

    @Test
    fun rankingRowStacksAt200Percent() {
        show(2f) {
            AccountRankingRow(
                AccountRankingEntry(accountId = "b".repeat(32), displayName = longName, songsPlayed = 39, totalChartedSongs = 50, totalScore = 89_000_000, totalScoreRank = 1),
                RankingMetric.TotalScore,
                isSelected = true,
                route = null,
                onOpen = {},
            )
        }
        val name = rule.onNodeWithText(longName, useUnmergedTree = true).getUnclippedBoundsInRoot()
        val songs = rule.onNodeWithText("39 / 50", substring = true, useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("name width ${name.width}", name.width > 150.dp)
        // Songs sits below the name instead of overlapping the rating.
        assertTrue(songs.top >= name.bottom)
    }

    @Test
    fun marqueeTextWrapsAndHelpersFollowTheScale() {
        var large = false
        var lines = 0
        var axisSize = 0f
        show(2f) {
            large = isLargeText()
            lines = oneLineUnlessLarge()
            axisSize = chartAxisTextStyle().fontSize.value
            FestivalMarqueeText(longName)
        }
        rule.waitForIdle()
        assertTrue(large)
        assertEquals(Int.MAX_VALUE, lines)
        // Axis ticks stay at their 100% size (11 sp / 2).
        assertEquals(5.5f, axisSize, 0.01f)
        assertTrue(rule.onNodeWithText(longName, useUnmergedTree = true).getUnclippedBoundsInRoot().height > 40.dp)
    }

    @Test
    fun normalScaleKeepsOneLineLayouts() {
        var large = true
        var lines = 0
        show(1f) {
            large = isLargeText()
            lines = oneLineUnlessLarge()
        }
        rule.waitForIdle()
        assertFalse(large)
        assertEquals(1, lines)
        assertEquals(2, StatGridColumns.count(300f, 1f))
    }
}
