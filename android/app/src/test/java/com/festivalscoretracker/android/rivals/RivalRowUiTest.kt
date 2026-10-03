package com.festivalscoretracker.android.rivals

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalSummary
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.rivals.RivalRow
import com.festivalscoretracker.android.ui.rivals.RivalSectionHeader
import com.festivalscoretracker.android.ui.rivals.RivalSongRow
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Rival row content (issue #67, Android port of #40): ahead/behind pills stay, the
 * redundant "N shared songs" count (always ahead + behind) is gone from the row and its
 * TalkBack label.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class RivalRowUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun description(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    @Test
    fun songRivalRowReadsAheadAndBehindWithoutSharedCount() {
        val id = RivalsFixtures.RIVALS[0]
        var opened = 0
        val rival = RivalSummary(id, "Synthetic Alpha", 1.0, sharedSongCount = 1234, aheadCount = 7, behindCount = 3)
        rule.setContent { FestivalTheme { RivalRow(RivalEntry(rival, RivalDirection.Below), onClick = { opened++ }) } }

        val text = description("fst.rivals.row.$id")
        assertEquals("Synthetic Alpha, you lead, 3 songs ahead, 7 songs behind", text)
        assertFalse(text.contains("shared", ignoreCase = true))
        rule.onNodeWithTag("fst.rivals.row.$id").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, opened)
    }

    @Test
    fun leaderboardAndAnonymousRowsOmitSharedCount() {
        val id = RivalsFixtures.RIVALS[1]
        rule.setContent {
            FestivalTheme {
                Column {
                    RivalRow(RivalEntry(LeaderboardRivalSummary(id, "Synthetic Beta", sharedSongCount = 40, aheadCount = 25, behindCount = 15), RivalDirection.Above), onClick = {})
                    RivalRow(RivalEntry(RivalSummary("", null, 1.0, sharedSongCount = 9, aheadCount = 5, behindCount = 4), RivalDirection.Above), onClick = {})
                }
            }
        }

        assertEquals("Synthetic Beta, ahead of you, 15 songs ahead, 25 songs behind", description("fst.rivals.row.$id"))
        val anonymous = description("fst.rivals.row.anonymous")
        assertEquals("Unknown User, ahead of you, 4 songs ahead, 5 songs behind", anonymous)
        assertFalse(anonymous.contains("shared", ignoreCase = true))
    }

    @Test
    fun sectionHeaderGroupsTitleAndDescriptionBeforeSeeAll() {
        var opened = 0
        rule.setContent {
            FestivalTheme {
                RivalSectionHeader(title = "Closest Battles", description = "Neck and neck.", onSeeAll = { opened++ }, seeAllTag = "see-all")
            }
        }
        val description = rule.onNodeWithText("Neck and neck.", useUnmergedTree = true).fetchSemanticsNode()
        val group = description.parent!!
        assertEquals(true, group.config.getOrNull(SemanticsProperties.IsTraversalGroup))
        assertTrue(group.children.any { it.config.contains(SemanticsProperties.Heading) })
        rule.onNodeWithTag("see-all").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, opened)
    }

    @Test
    fun songRowSpeaksFullUnsignedGapsWithSingularNouns() {
        var opened = 0
        rule.setContent {
            FestivalTheme {
                Column {
                    RivalSongRow(
                        RivalSongComparison("s-behind", "Behind Song", "A", "Solo_Guitar", userRank = 57, rivalRank = 56, rankDelta = -1, userScore = 158_795, rivalScore = 158_889),
                        catalogSong = null, artUrl = null, playerName = "Player", rivalName = "Rival", onClick = { opened++ },
                    )
                    RivalSongRow(
                        RivalSongComparison("s-ahead", "Ahead Song", "A", "Solo_Guitar", userRank = 3, rivalRank = 15_403, rankDelta = 15_400, userScore = 1_001, rivalScore = 1_000),
                        catalogSong = null, artUrl = null, playerName = null, rivalName = null, onClick = {},
                    )
                    RivalSongRow(
                        RivalSongComparison("s-tied", "Tied Song", "A", "Solo_Guitar", userRank = 4, rivalRank = 4, rankDelta = 0, userScore = 500, rivalScore = 500),
                        catalogSong = null, artUrl = null, playerName = "Player", rivalName = "Rival", onClick = {},
                    )
                }
            }
        }

        val lead = Instrument.Lead.label
        assertEquals(
            "Behind Song, $lead, Player rank 57, Rival rank 56, Rival leads by 1 rank, your score is 94 points lower",
            description("fst.rivals.song.s-behind.Solo_Guitar"),
        )
        assertEquals(
            "Ahead Song, $lead, You rank 3, Them rank 15,403, you lead by 15,400 ranks, your score is 1 point higher",
            description("fst.rivals.song.s-ahead.Solo_Guitar"),
        )
        assertEquals(
            "Tied Song, $lead, Player rank 4, Rival rank 4, tied on rank, same score",
            description("fst.rivals.song.s-tied.Solo_Guitar"),
        )
        rule.onNodeWithTag("fst.rivals.song.s-behind.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, opened)
    }
}
