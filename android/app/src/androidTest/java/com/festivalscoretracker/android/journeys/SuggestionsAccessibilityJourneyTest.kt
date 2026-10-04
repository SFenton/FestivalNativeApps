package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Suggestions on a real device (issue #112): ATF on the feed and the filter sheet, the
 * TalkBack reading order in logcat `FST_A11Y` and no card straddling a separating hinge
 * (`device.py test com.festivalscoretracker.android.journeys.SuggestionsAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SuggestionsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private fun launch() {
        h.launch(
            DebugLaunch(section = FestivalSection.Suggestions, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true, suggestionsSeed = 7),
            SuggestionFixtures.transport(),
        )
        h.waitForTag("fst.suggestions.list")
    }

    @Test
    fun feedFilterAndReadingOrder() {
        h.enableAccessibilityChecks()
        launch()
        val order = h.readingOrder("suggestions")
        assertTrue("Filter missing from $order", order.any { it.startsWith("Filter Suggestions") })
        assertTrue("A card is missing from $order", order.any { it.contains("Synthetic Track") })
        // Filter-before-feed order is asserted on the semantics tree (SuggestionsUiTest) and with
        // real TalkBack (talkback_walk.py); this harness walk can split Compose's traversal chain.
        val cards = rule.onAllNodes(SemanticsMatcher("card") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true }, useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }.distinct()
        assertTrue("No cards", cards.isNotEmpty())
        h.assertNothingStraddles(*cards.toTypedArray())
        h.tap("fst.suggestions.filter-button")
        h.waitForTag("fst.suggestions.filter.done")
        h.readingOrder("suggestions-filter")
        h.tap("fst.suggestions.filter.done")
        h.waitGone("fst.suggestions.filter.done")
        h.assertAccessible()
    }
}
