package com.festivalscoretracker.android.ui.songdetail

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Song Detail instrument-card top-score rows (issues #62 and #170, web `resolveTopScoresColumns`):
 * the season column shows only on a card at least 520 dp wide, decided by the card's own
 * width (a two-column grid or hinge half is narrower than the window), at default and large text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h900dp-xxhdpi")
class SongDetailScoreRowSeasonUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val entries = listOf(
        LeaderboardEntry(accountId = "a".repeat(32), displayName = "First Player", score = 412_345, rank = 1, accuracy = 990_000.0, isFullCombo = false, stars = 6, season = 15),
        LeaderboardEntry(accountId = "b".repeat(32), displayName = "Second Player", score = 400_000, rank = 2, accuracy = 1_000_000.0, isFullCombo = true, stars = 5, season = 15),
        LeaderboardEntry(accountId = "", displayName = null, score = 399_999, rank = 3),
    )

    private val cardWidth = mutableIntStateOf(0)

    /** Shows the card's rows [width] dp wide at [fontScale]; later calls only resize the card. */
    private fun showAt(width: Int, fontScale: Float = 1f) {
        val first = cardWidth.intValue == 0
        cardWidth.intValue = width
        if (first) {
            rule.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    FestivalTheme {
                        Box(Modifier.width(cardWidth.intValue.dp)) {
                            val columns = rememberScoreColumns(entries)
                            LeaderboardSectionMember(columns, "card") {
                                entries.forEach { ScoreRow(it, columns = columns.plan) }
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
    fun largeTextStackedRowsKeepTheWidthRule() {
        showAt(411, fontScale = 2f)
        assertEquals(0, seasons())
        showAt(900)
        assertEquals(2, seasons())
    }
}
