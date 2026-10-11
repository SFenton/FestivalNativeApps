package com.festivalscoretracker.android.journeys

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Privacy Policy in landscape (issue #609), with the Accessibility Test Framework on
 * every interaction. On a list/detail window (a phone turned to landscape, a tablet, an unfolded
 * fold) the policy reads inside one glass card in the detail pane, never straight on the
 * artwork:
 *
 * - TalkBack reads the pane heading, its hint, the effective date, then the first section's
 *   heading, and the card is one traversal group.
 * - The card sits inside the pane at the detail column's readable width (≤ 840 dp) and every
 *   checked line is inside it, unclipped.
 * - With Reduce Transparency the card is the opaque card colour, so contrast never depends on
 *   the artwork behind it.
 * - At 200 % text the window drops to one column and the policy opens in the shared modal,
 *   whose title, effective date and first heading stay unclipped; Close dismisses it.
 *
 * Phones are turned through the activity's requested orientation (never the global rotation
 * settings, issue #549). Fixtures only. Run with
 * `device.py test com.festivalscoretracker.android.journeys.PrivacyPolicyPaneAccessibilityJourneyTest --avd FST_Phone`;
 * reading orders go to logcat `FST_A11Y`.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class PrivacyPolicyPaneAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Journeys

    /** Landscape at 100 %: the policy card in the pane; at 200 %: the modal. */
    @Test
    fun policyReadsInACardInLandscapeAndInTheModalAtLargeText() {
        var scale by mutableFloatStateOf(1f)
        turnToLandscape("privacy-pane")
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), FakeTransport.standard(), fontScale = { scale })
        h.waitForTag("fst.settings.list")
        if (h.exists("fst.settings.detail-pane")) {
            openInPane()
            assertCard("privacy-pane fs 1")
        } else {
            Log.i(JourneyHarness.READING_ORDER_TAG, "privacy-pane | no list/detail window (w${rule.activity.resources.configuration.screenWidthDp}dp)")
        }

        scale = 2f
        rule.waitForIdle()
        h.waitForTag("fst.settings.list")
        if (h.exists("fst.settings.detail-pane")) {
            // Large screens keep list/detail at 200 %: the same card, re-laid at the new scale.
            openInPane()
            assertCard("privacy-pane fs 2", scale = 2f)
        } else {
            assertModal("privacy-modal fs 2", scale = 2f)
        }
        h.assertAccessible()
    }

    /** Reduce Transparency: the pane's card is the opaque card colour over the artwork. */
    @Test
    fun reduceTransparencyMakesThePolicyCardOpaque() {
        turnToLandscape("privacy-pane-reduce-transparency")
        h.enableAccessibilityChecks()
        val preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_TRANSPARENCY) to true))
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), FakeTransport.standard(), preferences)
        h.waitForTag("fst.settings.list")
        if (!h.exists("fst.settings.detail-pane")) {
            // The modal is opaque in every mode (modal-shell); nothing pane-specific to check.
            assertModal("privacy-modal-reduce-transparency", scale = rule.activity.resources.configuration.fontScale)
            return
        }
        openInPane()
        assertCard("privacy-pane-reduce-transparency")
        val card = rule.onNodeWithTag(CARD, useUnmergedTree = true)
        val size = card.fetchSemanticsNode().size
        val pixels = card.captureToImage().toPixelMap()
        // Just inside the top edge, clear of the 2 dp contrast border and the text.
        val fill = pixels[size.width / 2, with(rule.density) { 8.dp.roundToPx() }].toArgb()
        val opaque = BrandTokens.cardBackground.toArgb()
        assertTrue("card fill #%06X is the opaque card #%06X".format(fill and 0xFFFFFF, opaque and 0xFFFFFF), distance(fill, opaque) <= 6)
        h.assertAccessible()
    }

    // endregion

    // region Helpers

    /**
     * Turn a phone to landscape through the activity's requested orientation; large screens
     * may ignore it and run at their own.
     *
     * @param screen Log name.
     */
    private fun turnToLandscape(screen: String) {
        val sw = rule.activity.resources.configuration.smallestScreenWidthDp
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        val turned = runCatching {
            rule.waitUntil(10_000) { rule.activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE }
        }.isSuccess
        rule.waitForIdle()
        Log.i(JourneyHarness.READING_ORDER_TAG, "$screen | landscape $turned (sw${sw}dp, w${rule.activity.resources.configuration.screenWidthDp}dp)")
        if (sw < 600) assertTrue("$screen: a phone turns to landscape on request", turned)
    }

    /** Open Privacy Policy in the detail pane from its chevron row. */
    private fun openInPane() {
        if (!h.exists(CARD)) {
            h.scrollTo("fst.settings.list", ROW)
            h.tap(ROW)
        }
        h.waitForTag(CONTENT)
        rule.waitForIdle()
    }

    /**
     * The pane's card: inside the pane at the readable width, one traversal group, read after
     * the pane heading, with its first lines unclipped.
     *
     * @param screen Log name.
     * @param scale Expected font scale.
     */
    private fun assertCard(screen: String, scale: Float = 1f) {
        val pane = bounds("fst.settings.detail-pane")
        val card = bounds(CARD)
        assertTrue("$screen: card $card inside the pane $pane", card.left >= pane.left - 1 && card.right <= pane.right + 1)
        val maxWidth = with(rule.density) { 840.dp.toPx() } + 1
        assertTrue("$screen: card ${card.width} px at most 840 dp", card.width <= maxWidth)
        assertTrue(
            "$screen: the card is one traversal group",
            rule.onAllNodes(hasTestTag(CARD) and SemanticsMatcher.expectValue(SemanticsProperties.IsTraversalGroup, true), useUnmergedTree = true)
                .fetchSemanticsNodes().isNotEmpty(),
        )
        val order = h.readingOrder(screen, fresh = true)
        // The list row reads "Privacy Policy, <hint>, Selected"; the pane's own stops are exact.
        val title = order.indexOfFirst { it == TITLE }
        val hint = order.indexOfFirst { it == HINT }
        val date = order.indexOfFirst { it == EFFECTIVE }
        val overview = order.indexOfFirst { it == OVERVIEW }
        assertTrue("$screen: title, hint, effective date, Overview ($order)", title >= 0 && hint > title && date > hint && overview > date)
        listOf(EFFECTIVE, OVERVIEW).forEach { h.assertTextUnclipped(screen, CARD, it, scale) }
    }

    /**
     * The one-column window: the row opens the shared modal, whose lines stay unclipped, and
     * Close dismisses it (portrait and compact landscape are unchanged by issue #609).
     *
     * @param screen Log name.
     * @param scale Expected font scale.
     */
    private fun assertModal(screen: String, scale: Float) {
        assertTrue("$screen: no pane card in one column", rule.onAllNodesWithTag(CARD).fetchSemanticsNodes().isEmpty())
        if (!h.exists(SHEET)) {
            h.scrollTo("fst.settings.list", ROW)
            h.tap(ROW)
        }
        h.waitForTag(CONTENT)
        rule.waitForIdle()
        h.readingOrder(screen, fresh = true)
        h.assertTouchTarget(screen, "fst.privacy-policy.close")
        h.assertTextUnclipped(screen, SHEET, EFFECTIVE, scale)
        h.tap("fst.privacy-policy.close")
        h.waitGone(SHEET)
    }

    private fun bounds(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInWindow

    private fun distance(a: Int, b: Int): Int = maxOf(
        abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)),
        abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)),
        abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b)),
    )

    // endregion

    private companion object {
        const val ROW = "fst.settings.privacy-policy"
        const val CARD = "fst.privacy-policy.card"
        const val CONTENT = "fst.privacy-policy.content"
        const val SHEET = "fst.privacy-policy.sheet"
        const val TITLE = "Privacy Policy"
        const val HINT = "How Festival Score Tracker handles your information."
        const val EFFECTIVE = "Effective October 3, 2026"
        const val OVERVIEW = "Overview"
    }
}
