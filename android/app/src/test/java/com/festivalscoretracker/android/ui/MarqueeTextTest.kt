package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

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
}
