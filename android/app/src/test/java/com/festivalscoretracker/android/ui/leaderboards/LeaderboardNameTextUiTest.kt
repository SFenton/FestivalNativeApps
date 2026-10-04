package com.festivalscoretracker.android.ui.leaderboards

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issue #292: a long name in a leaderboard row scrolls (marquee) inside its flexible name
 * column instead of truncating, short names stay still, Reduce Motion tail-truncates, and the
 * row keeps its width and 48 dp height with the full name in its spoken description.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LeaderboardNameTextUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val longName = "A Remarkably Long Synthetic Player Display Name That Cannot Fit"

    private fun show(reduceMotion: Boolean = false, content: @Composable () -> Unit) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduceMotion)) {
                    Column(Modifier.width(360.dp)) { content() }
                }
            }
        }
    }

    private fun layout(tag: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
        return results.single()
    }

    @Test
    fun longNameScrollsInsteadOfTruncating() {
        show { LeaderboardNameText(longName, Modifier.width(120.dp).testTag("name")) }
        val text = layout("name")
        assertFalse("a moving name is never ellipsized", text.isLineEllipsized(0))
        assertEquals(1, text.lineCount)
        val column = rule.onNodeWithTag("name").getUnclippedBoundsInRoot()
        assertEquals("the marquee stays inside its column", 120f, column.width.value, 0.5f)
        val columnPx = rule.onNodeWithTag("name").fetchSemanticsNode().size.width
        assertTrue("the full name is laid out wider than the column, so it scrolls", text.size.width > columnPx)
    }

    @Test
    fun shortNameStaysStill() {
        show { LeaderboardNameText("Short", Modifier.width(120.dp).testTag("name")) }
        val text = layout("name")
        val columnPx = rule.onNodeWithTag("name").fetchSemanticsNode().size.width
        assertFalse(text.isLineEllipsized(0))
        assertTrue("a short name fits (${text.size.width} <= $columnPx px), so the marquee has nothing to scroll", text.size.width <= columnPx)
    }

    @Test
    fun reduceMotionTailTruncates() {
        show(reduceMotion = true) { LeaderboardNameText(longName, Modifier.width(120.dp).testTag("name")) }
        val text = layout("name")
        assertTrue(text.isLineEllipsized(0))
        assertEquals(1, text.lineCount)
        assertEquals(longName, rule.onNodeWithTag("name").fetchSemanticsNode().config[SemanticsProperties.Text].single().text)
    }

    @Test
    fun rowsWithLongNamesKeepTheirShape() = assertRowsKeepShape(reduceMotion = false)

    @Test
    fun rowsWithLongNamesKeepTheirShapeUnderReduceMotion() = assertRowsKeepShape(reduceMotion = true)

    private fun assertRowsKeepShape(reduceMotion: Boolean) {
        val ranking = AccountRankingEntry(accountId = "b".repeat(32), displayName = longName, songsPlayed = 731, totalChartedSongs = 731, totalScore = 108_382_873, totalScoreRank = 1)
        val score = LeaderboardEntry(accountId = "a".repeat(32), displayName = longName, score = 412_345, rank = 1, accuracy = 1_000_000.0, isFullCombo = true, stars = 6, season = 12)
        show(reduceMotion) {
            Column(Modifier.testTag("ranking-row")) { AccountRankingRow(ranking, RankingMetric.TotalScore, isSelected = true, route = null, onOpen = {}, tag = "ranking") }
            Column(Modifier.testTag("score")) { ScoreRow(score, isSelected = true, navigable = true) }
        }
        listOf("ranking-row", "score").forEach { tag ->
            val bounds = rule.onNodeWithTag(tag, useUnmergedTree = true).getUnclippedBoundsInRoot()
            assertEquals("$tag width", 360f, bounds.width.value, 0.5f)
            assertEquals("$tag height", LEADERBOARD_ROW_MIN_HEIGHT.value, bounds.height.value, 0.5f)
        }
        val description = rule.onNodeWithTag("ranking").fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.single().orEmpty()
        assertTrue(description, description.contains(longName))
    }
}
