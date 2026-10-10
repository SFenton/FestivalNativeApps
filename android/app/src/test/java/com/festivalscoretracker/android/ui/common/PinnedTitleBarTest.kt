package com.festivalscoretracker.android.ui.common

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/** [PinnedTitleBar.height]: the bar carrying a pinned title and its board line (issue #580). */
class PinnedTitleBarTest {
    @Test
    fun standardTextKeepsMaterialsSixtyFourDpBar() {
        // Title Large (28 sp line) over Label Medium (16 sp line) at 1.0×: 44 + 16 < 64.
        assertEquals(64.dp, PinnedTitleBar.height(28.dp, 16.dp))
    }

    @Test
    fun largeTextGrowsTheBarToFitBothLinesWithPadding() {
        // 200 %: 56 + 32 lines + 8 dp above and below.
        assertEquals(104.dp, PinnedTitleBar.height(56.dp, 32.dp))
    }

    @Test
    fun exactlyFittingLinesKeepTheMinimum() {
        assertEquals(64.dp, PinnedTitleBar.height(30.dp, 18.dp))
        assertEquals(65.dp, PinnedTitleBar.height(31.dp, 18.dp))
    }
}
