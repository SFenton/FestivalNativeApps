package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Reset Settings without a card (#599, web `resetRow`), with the Accessibility Test
 * Framework on every interaction, at font scale 1.0 and 2.0:
 *
 * - TalkBack reads the "Reset Settings" heading, its description, then the Reset All Settings
 *   button, and nothing groups them into a card.
 * - The button keeps a 48 dp target and its text is neither clipped nor ellipsized.
 * - It still opens the Reset Settings confirmation; Cancel closes it.
 *
 * Run with `device.py test com.festivalscoretracker.android.journeys.ResetSettingsAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ResetSettingsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    @Test
    fun resetReadsInOrderWithoutACardAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), FakeTransport.standard(), fontScale = { scale })
        h.waitForTag("fst.settings.list")
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            h.scrollTo("fst.settings.list", BUTTON)
            // Reset is the last section: scroll to the end so the list's bottom padding clears it
            // (a minimal scroll leaves it flush with the viewport, which clips the touch area).
            rule.onNodeWithTag("fst.settings.list").performScrollToKey("reset")
            rule.waitForIdle()
            val inReset = hasAnyAncestor(hasTestTag(SECTION))
            assertTrue(
                "fs $s: Reset is inside a card",
                rule.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.IsTraversalGroup, true) and inReset, useUnmergedTree = true)
                    .fetchSemanticsNodes().isEmpty(),
            )
            val order = h.readingOrder("settings-reset fs $s", fresh = true)
            val title = order.indexOfFirst { it.startsWith(TITLE) }
            val description = order.indexOfFirst { it.contains(DESCRIPTION) }
            val button = order.indexOfFirst { it.startsWith(LABEL) }
            assertTrue("fs $s: heading, description, button ($order)", title >= 0 && description > title && button > description)
            h.assertTouchTarget("settings-reset fs $s", BUTTON)
            listOf(TITLE, DESCRIPTION, LABEL).forEach { h.assertTextUnclipped("settings-reset fs $s", SECTION, it, s) }
        }
        h.tap(BUTTON)
        h.waitForTag("fst.settings.reset.dialog")
        h.readingOrder("settings-reset-dialog")
        h.tap("fst.settings.reset.cancel")
        h.waitGone("fst.settings.reset.dialog")
        h.assertAccessible()
    }

    private companion object {
        const val SECTION = "fst.settings.section.reset"
        const val BUTTON = "fst.settings.reset"
        const val TITLE = "Reset Settings"
        const val DESCRIPTION = "Restore all settings to their default values."
        const val LABEL = "Reset All Settings"
    }
}
