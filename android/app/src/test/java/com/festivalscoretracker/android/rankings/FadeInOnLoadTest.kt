package com.festivalscoretracker.android.rankings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FADE_IN_MILLIS
import com.festivalscoretracker.android.ui.common.FADE_IN_STAGGER_MILLIS
import com.festivalscoretracker.android.ui.common.fadeInAlpha
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** `Modifier.festivalFadeIn`: fresh content fades in; cached content and Reduce Motion do not. */
@RunWith(AndroidJUnit4::class)
class FadeInOnLoadTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun alphaFollowsProgressUnlessMotionIsReduced() {
        assertEquals(0.25f, fadeInAlpha(0.25f, isLoaded = true, reduceMotion = false))
        assertEquals(1f, fadeInAlpha(0f, isLoaded = true, reduceMotion = true))
        assertEquals(0f, fadeInAlpha(0f, isLoaded = false, reduceMotion = true))
        assertEquals(1f, fadeInAlpha(1.4f, isLoaded = true, reduceMotion = false))
    }

    @Test
    fun staggerIsCapped() {
        assertEquals(0, fadeInStagger(-1))
        assertEquals(2 * FADE_IN_STAGGER_MILLIS, fadeInStagger(2))
        assertEquals(fadeInStagger(12), fadeInStagger(40))
    }

    @Test
    fun loadCyclesRunWithAndWithoutReducedMotion() {
        var loaded by mutableStateOf(false)
        var reduce by mutableStateOf(false)
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduce)) {
                val revealed = rememberRevealed(loaded)
                Box(Modifier.size(40.dp).festivalFadeIn(revealed, delayMillis = 125).testTag("fresh"))
                Box(Modifier.size(40.dp).festivalFadeIn(isLoaded = true).testTag("cached"))
            }
        }
        rule.onNodeWithTag("cached").assertIsDisplayed()
        loaded = true
        rule.mainClock.advanceTimeBy(FADE_IN_MILLIS * 3L)
        rule.onNodeWithTag("fresh").assertIsDisplayed()
        loaded = false
        reduce = true
        rule.waitForIdle()
        loaded = true
        rule.waitForIdle()
        rule.onNodeWithTag("fresh").assertIsDisplayed()
    }
}
