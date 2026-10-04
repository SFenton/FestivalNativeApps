package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #133: the Profile Selection control on a real device/emulator against synthetic
 * fixtures (`device.py test com.festivalscoretracker.android.journeys.ProfileSelectionDeviceTest
 * --avd FST_Phone`, and `--avd FST_Book_Fold --posture half`). Accessibility Test Framework
 * checks run on every interaction, each sheet state logs its TalkBack reading order, every
 * sheet target is at least 48 dp and nothing straddles a separating hinge.
 */
@RunWith(AndroidJUnit4::class)
class ProfileSelectionDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    /** Touch bounds (including Material's minimum interactive padding) of every [tags] node are at least 48 dp. */
    private fun assertTargets(vararg tags: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        tags.forEach { tag ->
            val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot
            assertTrue("$tag touch target is ${bounds.width} x ${bounds.height} px", bounds.width >= min && bounds.height >= min)
        }
    }

    private fun before(order: List<String>, first: String, second: String) {
        val a = order.indexOfFirst { it.contains(first) }
        val b = order.indexOfFirst { it.contains(second) }
        assertTrue("'$first' before '$second' in $order", a >= 0 && b > a)
    }

    @Test
    fun searchViewSelectThenDeselectIsAccessibleAndClearOfTheFold() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(opensProfileSheet = true, stillBackground = true), transport)
        h.waitForTag("fst.profile.hint")
        val anonymous = h.readingOrder("profile-sheet-anonymous")
        before(anonymous, "Profiles", "Players")
        before(anonymous, "Players", "Enter at least 2 characters")
        assertTargets("fst.profile.close", "fst.profile.scope.players", "fst.profile.scope.bands")
        h.assertNothingStraddles("fst.profile.sheet")

        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        h.waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        val results = h.readingOrder("profile-sheet-results")
        before(results, "Find a Profile", "Synthetic Player")
        assertTargets("fst.profile.clear", "fst.profile.result.${Fixtures.ACCOUNT_A}")
        h.assertNothingStraddles("fst.profile.results", "fst.profile.result.${Fixtures.ACCOUNT_A}")

        // Opening a result views the player without selecting it.
        h.tap("fst.profile.result.${Fixtures.ACCOUNT_A}")
        h.waitForTag("fst.player.select")
        h.readingOrder("player-viewed")
        h.assertNothingStraddles("fst.player.identity")
        h.tap("fst.player.select")
        h.waitForTag("fst.nav.tab.statistics")

        // Issue #290: with a profile selected the chip opens it (Statistics), not the sheet.
        h.tap(if (h.exists("fst.nav.profile")) "fst.nav.profile" else "fst.nav.rail.profile")
        h.waitForTag("fst.statistics")
        assertTrue(!h.exists("fst.profile.sheet"))

        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
        h.assertAccessible()
    }

    @Test
    fun selectedSheetViewsAndDeselectsAccessibly() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), opensProfileSheet = true, stillBackground = true), transport)
        // The selected sheet views and deselects (confirmed) the player.
        h.waitForTag("fst.profile.selected")
        val selected = h.readingOrder("profile-sheet-selected")
        before(selected, "Selected Profile", "Synthetic Player")
        before(selected, "View Profile", "Deselect")
        assertTargets("fst.profile.view-selected", "fst.profile.deselect")
        h.tap("fst.profile.deselect")
        h.waitForTag("fst.profile.deselect-confirm")
        before(h.readingOrder("profile-deselect-confirm"), "Deselect Profile?", "Cancel")
        h.tap("fst.profile.deselect-confirm.ok")
        h.waitGone("fst.profile.deselect-confirm")
        h.waitGone("fst.profile.selected")

        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
        h.assertAccessible()
    }

    @Test
    fun bandsTargetExplainsWithoutSearching() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(opensProfileSheet = true, stillBackground = true), transport)
        h.tap("fst.profile.scope.bands")
        h.waitForTag("fst.profile.bands-unavailable")
        h.readingOrder("profile-sheet-bands")
        assertTrue(transport.requests.none { it.url.contains("/api/bands") })
        h.assertAccessible()
    }
}
