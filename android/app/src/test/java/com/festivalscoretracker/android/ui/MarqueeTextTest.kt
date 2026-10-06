package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/** Web `MarqueeText` timing and the Reduce Motion fallback. */
@RunWith(AndroidJUnit4::class)
class MarqueeTextTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun cycleIsEightSecondsWhateverTheLength() {
        // 7.2 s of movement per cycle (5% pause at each end) over text + 28 dp gap.
        assertEquals((172f + 28f) / 7.2f, FestivalMarquee.velocityDp(172f), 0.01f)
        assertEquals(400, FestivalMarquee.PAUSE_MS)
        assertTrue(FestivalMarquee.velocityDp(0f) >= 1f)
    }

    @Test
    fun scrollsOrTruncatesBySetting() {
        val long = "A very long rival display name that cannot fit"
        rule.setContent {
            FestivalMarqueeText(long, Modifier.width(80.dp).testTag("moving"))
            CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true)) {
                FestivalMarqueeText("Still $long", Modifier.width(80.dp).testTag("still"))
            }
        }
        rule.onNodeWithTag("moving").assertIsDisplayed()
        rule.onNodeWithTag("still").assertIsDisplayed()
        rule.onNodeWithText(long).assertIsDisplayed()
    }

    @Test
    fun overflowNeedsAMeasuredBoxNarrowerThanTheText() {
        assertTrue(FestivalMarquee.overflows(textWidthPx = 300, boxWidthPx = 200))
        assertFalse(FestivalMarquee.overflows(textWidthPx = 200, boxWidthPx = 200))
        assertFalse(FestivalMarquee.overflows(textWidthPx = 100, boxWidthPx = 200))
        // Not measured yet: never claims an overflow.
        assertFalse(FestivalMarquee.overflows(textWidthPx = 300, boxWidthPx = 0))
    }

    @Test
    fun fallbackModeNamesWrappedTruncatedOrStill() {
        assertEquals(FestivalMarquee.Mode.Wrapped, FestivalMarquee.fallbackMode(lineCount = 2, ellipsized = false))
        assertEquals(FestivalMarquee.Mode.Truncated, FestivalMarquee.fallbackMode(lineCount = 1, ellipsized = true))
        assertEquals(FestivalMarquee.Mode.Static, FestivalMarquee.fallbackMode(lineCount = 1, ellipsized = false))
    }

    /** Issue #315: the top app bar learns whether a marquee title overflows, in motion and Reduce Motion. */
    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun reportsOverflowWhileScrollingAndTruncating() {
        val long = "Through the Fire and Flames, an overflowing synthetic title"
        var moving: Boolean? = null
        var still: Boolean? = null
        var fits: Boolean? = null
        rule.setContent {
            Column {
                FestivalMarqueeText(long, Modifier.width(80.dp), wrapAtLargeText = false, onOverflowChange = { moving = it })
                FestivalMarqueeText("Hi", Modifier.width(200.dp), onOverflowChange = { fits = it })
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true)) {
                    FestivalMarqueeText(long, Modifier.width(80.dp), onOverflowChange = { still = it })
                }
            }
        }
        rule.waitForIdle()
        assertEquals("moving", true, moving)
        assertEquals("still", true, still)
        assertEquals("fits", false, fits)
        // TalkBack reads each full title once, whatever is drawn.
        rule.onAllNodesWithText(long, useUnmergedTree = true).assertCountEquals(2)
    }
}
