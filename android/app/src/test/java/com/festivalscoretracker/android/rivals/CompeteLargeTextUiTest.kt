package com.festivalscoretracker.android.rivals

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.rivals.RivalPill
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Compete's Rivals cards at font scale 2.0 (issue #120): on a phone-width card the two
 * "songs ahead / songs behind" pills wrap onto two lines and the row must grow to show both.
 * Native graphics measure text with real fonts; the legacy stub never wraps.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CompeteLargeTextUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun entry(id: String) =
        RivalEntry(RivalSummary(id, "SFentonX", 1.0, sharedSongCount = 512, aheadCount = 324, behindCount = 188), RivalDirection.Above)

    @Test
    fun rivalPreviewRowsShowBothPillsOnPhoneWidthCards() {
        val narrow = RivalsFixtures.RIVALS[0]
        val wide = RivalsFixtures.RIVALS[1]
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                FestivalTheme {
                    Column {
                        // A Compete card on a 411 dp phone: the grid's 16 dp margins leave ~379 dp.
                        Box(Modifier.requiredWidth(379.dp)) { RivalPreviewRows(listOf(entry(narrow)), onRival = {}, onViewAll = null) }
                        Box(Modifier.requiredWidth(840.dp)) { RivalPreviewRows(listOf(entry(wide)), onRival = {}, onViewAll = null) }
                        RivalPill("324 songs behind", win = false, modifier = Modifier.testTag("pill"))
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
