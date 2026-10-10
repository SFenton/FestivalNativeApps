package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.espresso.Espresso
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issues #133 and #600: the Profile Selection control on a real device/emulator against synthetic
 * fixtures (`device.py test com.festivalscoretracker.android.journeys.ProfileSelectionDeviceTest
 * --avd FST_Phone`, and `--avd FST_Book_Fold --posture half`). Accessibility Test Framework
 * checks run on every interaction, each sheet state logs its TalkBack reading order (All ·
 * Players · Bands scopes, then the field, then players and bands), every sheet target is at
 * least 48 dp and nothing straddles a separating hinge.
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
        // TalkBack's order (geometric, with traversal links), not raw tree order.
        h.publishTalkBackTree()
        h.waitForTag("fst.profile.hint")
        val anonymous = h.readingOrder("profile-sheet-anonymous")
        // Issue #600: the scopes read All, Players, Bands (starting on All), then the field and hint.
        before(anonymous, "Profiles", "All")
        before(anonymous, "All", "Players")
        before(anonymous, "Players", "Bands")
        before(anonymous, "Bands", "Search players and bands")
        before(anonymous, "Search players and bands", "Enter at least two characters to search for players or bands.")
        assertTargets("fst.profile.close", "fst.profile.scope.all", "fst.profile.scope.players", "fst.profile.scope.bands")
        h.assertNothingStraddles("fst.profile.sheet")

        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        h.waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        h.waitForTag("fst.profile.section.bands")
        Espresso.closeSoftKeyboard()
        rule.onNodeWithTag("fst.profile.results").performScrollToNode(hasTestTag(DUO))
        h.awaitAccessibilityTree(DUO)
        val results = h.readingOrder("profile-sheet-results")
        // All lists players, then bands, each under its section title.
        before(results, "Find a Profile", "Synthetic Player")
        before(results, "Synthetic Player", "Synthetic Lead + Synthetic Bass")
        assertTargets("fst.profile.clear", DUO)
        h.assertNothingStraddles("fst.profile.results", DUO)
        rule.onNodeWithTag("fst.profile.results").performScrollToNode(hasTestTag("fst.profile.result.${Fixtures.ACCOUNT_A}"))
        assertTargets("fst.profile.result.${Fixtures.ACCOUNT_A}")
        h.assertNothingStraddles("fst.profile.result.${Fixtures.ACCOUNT_A}")

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
        // TalkBack's order (geometric, with traversal links), not raw tree order.
        h.publishTalkBackTree()
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
    fun bandsScopeSearchesAndOpensTheBandPage() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(opensProfileSheet = true, stillBackground = true), transport)
        // TalkBack's order (geometric, with traversal links), not raw tree order.
        h.publishTalkBackTree()
        h.tap("fst.profile.scope.bands")
        h.waitForTag("fst.profile.hint")
        before(h.readingOrder("profile-sheet-bands-hint"), "Bands", "Enter at least two characters to search for bands.")
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        h.waitForTag(DUO)
        Espresso.closeSoftKeyboard()
        h.awaitAccessibilityTree(DUO)
        // Bands narrows to bands: no players and, in a single scope, no section title.
        assertTrue(!h.exists("fst.profile.result.${Fixtures.ACCOUNT_A}"))
        assertTrue(!h.exists("fst.profile.section.bands"))
        before(h.readingOrder("profile-sheet-bands"), "Search players and bands", "Synthetic Lead + Synthetic Bass")
        assertTargets("fst.profile.scope.bands", DUO)
        h.assertNothingStraddles(DUO)
        assertTrue(transport.requests.count { it.url.contains("/api/bands/search") } == 1)
        // A band can't be the selected profile yet: its result opens the Band page.
        h.tap(DUO)
        h.waitForTag("fst.band.screen")
        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
        h.assertAccessible()
    }

    private companion object {
        const val DUO = "fst.profile.band.${BandFixtures.DUO_ID}"
    }
}
