package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The shared accordion (`load-transition` R10, issue #561) on a device, through the reported
 * Suggestions **Filter** sheet's Instrument-Specific section. Picking an instrument chip opens
 * its suggestion-type switches: the chip reads Selected, each switch is one 48 dp stop with the
 * Switch role, its label and On state, read after the chip in sheet order, with its text
 * unclipped at the device's text size and at 200% system text; picking the chip again closes
 * them and brings the hint back. With system animations on, the section is still growing three frames
 * after the tap (it animates); under the app's Reduce Motion it is at full height by then
 * (opens at once, R6), and closes at once too. ATF runs on every step. Run with
 * `device.py test com.festivalscoretracker.android.journeys.AccordionAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class AccordionAccessibilityJourneyTest {
    /** Sheets compose in their own window, so only the system font scale reaches them. */
    @get:Rule(order = 0)
    val fontScale = SystemFontScaleRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val chip = "fst.suggestions.filter.instrument-picker.${Instrument.Bass.wireId}"

    private fun switchTag(type: SuggestionCategoryType) = "fst.suggestions.filter.type.${Instrument.Bass.wireId}.${type.key}"

    // region Helpers

    private fun openFilter(reduceMotion: Boolean = false) {
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
            MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to reduceMotion)),
        )
        h.waitForTag("fst.suggestions.list")
        h.tap("fst.suggestions.filter-button")
        h.waitForTag(FORM)
    }

    /** Scroll the lazy form until [tag] is composed and on screen. */
    private fun scrollTo(tag: String) {
        rule.onNodeWithTag(FORM).performScrollToNode(hasTestTag(tag))
        rule.waitForIdle()
    }

    private fun assertChipSelected(selected: Boolean) =
        rule.onNodeWithTag(chip).assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, selected))

    /** Laid-out height (px) of the accordion that holds the switches, 0 when it is gone. */
    private fun sectionHeight(): Float =
        rule.onAllNodesWithTag(SECTION, useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()?.size?.height?.toFloat() ?: 0f

    /**
     * Tap the chip with the clock paused and return the section's height three frames later and
     * once settled.
     *
     * @return (height three frames after the tap, settled height) in px.
     */
    private fun tapAndMeasure(): Pair<Float, Float> {
        rule.mainClock.autoAdvance = false
        try {
            rule.onNodeWithTag(chip).performClick()
            repeat(3) { rule.mainClock.advanceTimeByFrame() }
            val early = sectionHeight()
            rule.mainClock.advanceTimeBy(600)
            return early to sectionHeight()
        } finally {
            rule.mainClock.autoAdvance = true
            rule.waitForIdle()
        }
    }

    /**
     * Open the Bass section and check its switches, order and text, then close it.
     *
     * @param screen Reading-order log name.
     * @param scale Font scale the switch labels must be laid out at.
     */
    private fun openAndCloseSection(screen: String, scale: Float) {
        scrollTo(chip)
        assertChipSelected(false)
        h.assertTouchTarget(screen, chip)
        assertEquals("$screen: hint shown while no instrument is picked", 1, rule.onAllNodesWithText(HINT).fetchSemanticsNodes().size)
        h.tap(chip)
        h.waitForTag(switchTag(SuggestionCategoryType.entries.first()))
        assertChipSelected(true)
        rule.waitUntil(5_000) { rule.onAllNodesWithText(HINT).fetchSemanticsNodes().isEmpty() }
        SuggestionCategoryType.entries.forEach { type ->
            scrollTo(switchTag(type))
            h.assertSwitchStop(screen, switchTag(type), on = true)
            h.assertTouchTarget(screen, switchTag(type))
            h.assertTextUnclipped(screen, switchTag(type), type.label, scale)
        }
        scrollTo(chip)
        val order = h.readingOrder("$screen-open", fresh = true)
        // Each chip is one stop ("Bass, Selected"; the label may be cut off-screen); the switches follow.
        val picked = order.indexOfFirst { it == "Selected" || it.endsWith(", Selected") }
        assertTrue("$screen: the picked chip is a stop in $order", picked >= 0)
        val stops = order.withIndex().filter { (i, s) -> i > picked && SuggestionCategoryType.entries.any { s == it.label || s.startsWith("${it.label},") } }
        assertTrue("$screen: the switches read after the picked chip in $order", stops.isNotEmpty())
        val labels = stops.map { (_, s) -> SuggestionCategoryType.entries.first { s == it.label || s.startsWith("${it.label},") }.label }
        assertEquals("$screen: switches in sheet order in $order", SuggestionCategoryType.entries.map { it.label }.filter { it in labels }, labels)
        h.tap(chip)
        h.waitGone(switchTag(SuggestionCategoryType.entries.first()))
        assertChipSelected(false)
        rule.waitUntil(5_000) { rule.onAllNodesWithText(HINT).fetchSemanticsNodes().isNotEmpty() }
        h.readingOrder("$screen-closed", fresh = true)
    }

    /** Runs [body] with the system animator duration scale at [scale] (device CI turns it off), then restores it. */
    private fun withAnimatorScale(scale: String, body: () -> Unit) {
        val saved = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale $scale")
        try {
            body()
        } finally {
            shell(if (saved == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
        }
    }

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    // endregion

    /** Device text size: the section opens and closes with its switches in order, as stops, with full targets. */
    @Test
    @DeviceCi
    fun instrumentSectionOpensAndClosesWithStatesOrderAndTargets() {
        openFilter()
        openAndCloseSection("accordion-suggestions", rule.activity.resources.configuration.fontScale)
        h.assertAccessible()
    }

    /** 200% system text: the switches' labels grow unclipped and keep their order and targets. */
    @Test
    @DeviceCi
    @SystemFontScale(2f)
    fun instrumentSectionAtDoubleTextKeepsOrderTargetsAndUnclippedText() {
        openFilter()
        assertEquals(2f, rule.activity.resources.configuration.fontScale, 0.01f)
        openAndCloseSection("accordion-suggestions-2x", scale = 2f)
        h.assertAccessible()
    }

    /** Animations on: three frames after the tap the section is still growing (R10 height step). */
    @Test
    @DeviceCi
    fun instrumentSectionAnimatesOpen() = withAnimatorScale("1") {
        openFilter()
        scrollTo(chip)
        val (early, settled) = tapAndMeasure()
        assertTrue("open: section settles with height ($settled px)", settled > 0f)
        assertTrue("open: still growing three frames in ($early of $settled px)", early < settled)
        h.assertAccessible()
    }

    /** The app's Reduce Motion: the section is full height three frames after the tap and gone as fast (R6). */
    @Test
    @DeviceCi
    fun reduceMotionOpensAndClosesTheSectionAtOnce() {
        openFilter(reduceMotion = true)
        scrollTo(chip)
        val (early, settled) = tapAndMeasure()
        assertTrue("reduce motion: section opens ($settled px)", settled > 0f)
        assertEquals("reduce motion: full height at once", settled, early, 1f)
        h.assertSwitchStop("accordion-reduce-motion", switchTag(SuggestionCategoryType.entries.first()), on = true)
        val (closing, closed) = tapAndMeasure()
        assertEquals("reduce motion: closed at once", 0f, closing, 1f)
        assertEquals(0f, closed, 1f)
        h.assertAccessible()
    }

    private companion object {
        const val FORM = "fst.suggestions.filter.form"
        const val SECTION = "fst.suggestions.filter.instrument-types"
        const val HINT = "Choose an instrument to fine-tune its suggestion types."
    }
}
