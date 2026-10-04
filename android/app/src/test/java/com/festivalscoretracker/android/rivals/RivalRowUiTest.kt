package com.festivalscoretracker.android.rivals

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.rivals.RivalPill
import org.junit.Assert.assertTrue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalSummary
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.rivals.RivalRow
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

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

    /**
     * Issue #107: at font scale 2.0 the wrapped "songs behind" pill was clipped off the card
     * (FlowRow's intrinsic height under the row's old IntrinsicSize.Min ignored wrapped lines).
     * Native graphics measure text with real fonts; the legacy stub (~1 px per character)
     * never wraps.
     */
    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun wrappedPillsGrowTheCardAtLargeText() {
        val narrow = RivalsFixtures.RIVALS[0]
        val wide = RivalsFixtures.RIVALS[1]
        fun entry(id: String) = RivalEntry(RivalSummary(id, "Ann", 1.0, sharedSongCount = 162, aheadCount = 110, behindCount = 52), RivalDirection.Above)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(300.dp)) { RivalRow(entry(narrow), onClick = {}) }
                        Box(Modifier.requiredWidth(720.dp)) { RivalRow(entry(wide), onClick = {}) }
                        RivalPill("110 songs behind", win = false, modifier = Modifier.testTag("pill"))
                    }
                }
            }
        }

        fun height(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().size.height
        val pill = height("pill")
        val oneLine = height("fst.rivals.row.$wide")
        val wrapped = height("fst.rivals.row.$narrow")
        assertTrue("wrapped row $wrapped px should fit a second pill line ($oneLine + $pill px)", wrapped >= oneLine + pill)
    }
}
