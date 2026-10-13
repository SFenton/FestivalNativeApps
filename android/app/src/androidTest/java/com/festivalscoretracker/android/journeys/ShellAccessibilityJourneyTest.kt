package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasContentDescriptionExactly
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.CompeteFixtures
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp

/**
 * Accessibility journeys over the shell: navigation drawer, profile sheet, global search,
 * notifications, first run and What's New. ATF on every screen and interaction; reading
 * orders in logcat `FST_A11Y`
 * (`device.py test com.festivalscoretracker.android.journeys.ShellAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class ShellAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) {
            """{"sourceRunId":3,"items":[
              {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-alpha","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"},
              {"eventId":2,"notificationGuid":"n-total","eventKind":"player_total_score_improved","newNumeric":5,"detectedAt":"2026-09-27T11:00:00Z"}]}"""
        }
        ProfileFixtures.register(this)
    }

    /** Songs and profile fixtures plus every rankings route, so Leaderboards shows populated cards. */
    private val navigationTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
        },
    )

    @Test
    fun drawerAndProfileSheet() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, opensDrawer = true, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.readingOrder(if (h.exists("fst.nav.drawer-sheet")) "drawer" else "navigation")
        h.assertAccessible()
    }

    @Test
    @DeviceCi
    fun drawerCompetitivePagesReadTheirOwningTabAndBackKeepsPlace() = competitiveDrawerJourney(1f)

    @Test
    @DeviceCi
    fun drawerCompetitivePagesAtDoubleTextKeepLabelsTargetsAndOrder() = competitiveDrawerJourney(2f)

    @Test
    @DeviceCi
    fun compactWindowDrawerCompetitivePagesKeepTheirParentAndPlace() = competitiveDrawerJourney(1f, compactWindow = true)

    @Test
    @DeviceCi
    fun compactWindowDrawerCompetitivePagesAtDoubleTextStayAccessible() = competitiveDrawerJourney(2f, compactWindow = true)

    /**
     * Compact drawer routes belong to Compete; regular-width routes remain independent roots.
     * Both modes preserve the originating Songs filter and the selected navigation semantics.
     *
     * @param scale System text scale for this composition and its drawer.
     * @param compactWindow Compose's 411 x 600 dp test viewport exercises compact navigation
     *   on a shared unfolded AVD without changing its display or posture.
     */
    private fun competitiveDrawerJourney(scale: Float, compactWindow: Boolean = false) {
        val fixture = CompeteFixtures.transport().apply { ProfileFixtures.register(this, CompeteFixtures.PLAYER) }
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true),
            fixture,
            fontScale = { scale },
            size = if (compactWindow) DpSize(411.dp, 600.dp) else null,
        )
        h.waitForTag("fst.songs.row.s-beta")
        h.publishTalkBackTree()
        rule.onNodeWithTag("fst.songs.search").performTextInput("beta")
        h.waitGone("fst.songs.row.s-alpha")
        val compact = h.exists("fst.nav.tab.compete")
        if (compactWindow) assertTrue("the activity must actually have a compact navigation window", compact)
        listOf("rivals" to "fst.rivals.tab.song", "leaderboards" to "fst.leaderboards").forEach { (section, page) ->
            if (h.exists("fst.nav.drawer")) {
                h.tap("fst.nav.drawer")
                h.waitForTag("fst.nav.drawer.$section")
            }
            val row = if (h.exists("fst.nav.permanent-drawer")) "fst.nav.tab.$section" else "fst.nav.drawer.$section"
            rule.onNodeWithTag(row).performScrollTo()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
                .assert(hasText(if (section == "rivals") "Rivals" else "Leaderboards"))
            h.assertFullTouchTarget(row)
            val drawerOrder = h.readingOrder("drawer-$section-${scale}x", fresh = true)
            assertTrue("drawer destinations read in order: $drawerOrder", drawerOrder.indexOf("Rivals") in 0 until drawerOrder.indexOf("Leaderboards"))
            h.tap(row)
            h.waitForTag(page)
            val tab = "fst.nav.tab.${if (compact) "compete" else section}"
            rule.onNodeWithTag(tab).assertIsSelected()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
                .assert(hasText(if (compact) "Compete" else if (section == "rivals") "Rivals" else "Leaderboards") or
                    hasContentDescription(if (compact) "Compete" else if (section == "rivals") "Rivals" else "Leaderboards"))
            h.assertFullTouchTarget(tab)
            h.awaitAccessibilityTree(page)
            val order = h.readingOrder("drawer-$section-page-${scale}x", fresh = true)
            if (compact) {
                rule.onNodeWithTag("fst.nav.back").assert(hasContentDescriptionExactly("Back"))
                    .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                h.assertFullTouchTarget("fst.nav.back")
                assertTrue("Back before title: $order", order.indexOf("Back") in 0 until order.indexOf(if (section == "rivals") "Rivals" else "Leaderboards"))
                if (section == "rivals") h.tap("fst.nav.back") else rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
                h.waitForTag("fst.compete.grid")
                h.waitGone(page)
                rule.onNodeWithTag(tab).assertIsSelected()
                assertFalse(h.exists("fst.nav.back"))
                h.readingOrder("drawer-$section-back-${scale}x", fresh = true)
            } else {
                assertFalse(h.exists("fst.nav.back"))
            }
            h.tap("fst.nav.tab.songs")
            h.waitForTag("fst.songs.row.s-beta")
            rule.onNodeWithTag("fst.songs.search").assert(hasText("beta"))
            assertFalse(h.exists("fst.songs.row.s-alpha"))
        }
        h.assertAccessible()
    }

    @Test
    fun profileSheetWithoutAPlayer() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(opensProfileSheet = true, stillBackground = true), transport)
        h.waitForTag("fst.profile.sheet")
        h.readingOrder("profile-sheet")
        h.assertAccessible()
    }

    @Test
    fun globalSearch() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(searchQuery = "alpha", stillBackground = true), transport)
        h.waitForTag("fst.global-search.surface")
        rule.waitForIdle()
        h.readingOrder("global-search")
        h.assertAccessible()
    }

    @Test
    fun notifications() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, opensNotifications = true, stillBackground = true), transport)
        h.waitForTag("fst.notifications.list")
        h.readingOrder("notifications")
        h.assertAccessible()
    }

    @Test
    fun firstRunGuide() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(firstRun = "force", stillBackground = true), transport)
        h.waitForTag("fst.first-run.dialog")
        h.readingOrder("first-run")
        if (h.exists("fst.first-run.next")) {
            h.tap("fst.first-run.next")
            h.readingOrder("first-run-2")
        }
        h.assertAccessible()
    }

    @Test
    fun whatsNew() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(whatsNew = "force", stillBackground = true), transport)
        h.waitForTag("fst.whats-new.sheet")
        h.readingOrder("whats-new")
        h.assertAccessible()
    }

    /**
     * App Navigation (issue #132), anonymous: `songs`, `leaderboards`, `settings` and `reselect`
     * on whichever chrome (bar, rail or permanent drawer) the AVD's window gets, with ATF on
     * every state and nothing across a separating hinge.
     */
    @Test
    fun appNavigationAnonymousStates() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), navigationTransport)
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
        h.assertNothingStraddles(*NAV_TAGS)
        h.readingOrder("nav-songs")
        // Narrow and medium windows push the detail; expanded windows show it beside the list.
        h.tap("fst.songs.row.s-alpha")
        h.waitForTag("fst.song-detail.intensity")
        h.tap("fst.nav.tab.leaderboards")
        h.waitForTag("fst.leaderboards")
        h.waitGone("fst.songs.list")
        h.awaitAccessibilityTree("fst.leaderboards", absent = "fst.songs.list")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
        h.readingOrder("nav-leaderboards")
        h.tap("fst.nav.tab.settings")
        h.waitForTag("fst.settings.list")
        h.waitGone("fst.leaderboards")
        h.awaitAccessibilityTree("fst.settings.list", absent = "fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.settings").assertIsSelected()
        h.readingOrder("nav-settings")
        // Back to Songs restores its pushed detail; re-tapping Songs pops to the list root.
        h.tap("fst.nav.tab.songs")
        h.waitForTag("fst.song-detail.intensity")
        h.waitGone("fst.settings.list")
        h.tap("fst.nav.tab.songs")
        h.waitForTag("fst.songs.row.s-alpha")
        h.awaitAccessibilityTree("fst.songs.row.s-alpha", absent = "fst.settings.list")
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
        h.readingOrder("nav-reselect")
        h.assertAccessible()
    }

    /**
     * App Navigation (issue #132), selected player: the player tab set (Compete on compact
     * widths, Leaderboards + Rivals on regular ones), the Item Shop tab that replaces
     * Statistics (#601), Statistics through the profile chip, and the drawer's player row.
     */
    @Test
    fun appNavigationPlayerStates() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), navigationTransport)
        h.waitForTag("fst.songs.list")
        h.waitForTag("fst.nav.tab.suggestions")
        h.waitForTag("fst.nav.tab.shop")
        assertFalse(h.exists("fst.nav.tab.statistics"))
        assertTrue(h.exists("fst.nav.tab.compete") != h.exists("fst.nav.tab.rivals"))
        h.assertNothingStraddles(*NAV_TAGS)
        h.readingOrder("nav-player")
        // #601: Item Shop is a named, selectable tab where Statistics was.
        rule.onNodeWithTag("fst.nav.tab.shop").assert(hasText("Item Shop") or hasContentDescription("Item Shop"))
        h.tap("fst.nav.tab.shop")
        h.waitForTag("fst.shop.sort.open")
        h.waitGone("fst.songs.list")
        h.awaitAccessibilityTree("fst.shop.sort.open", absent = "fst.songs.list")
        rule.onNodeWithTag("fst.nav.tab.shop").assertIsSelected()
        h.readingOrder("nav-player-shop")
        // The profile chip still opens the selected profile's Statistics, pushed with Back.
        h.tap("fst.nav.profile")
        h.waitForTag("fst.statistics")
        h.waitForTag("fst.nav.back")
        h.awaitAccessibilityTree("fst.statistics", absent = "fst.shop.sort.open")
        h.readingOrder("nav-player-statistics")
        h.tap("fst.nav.back")
        h.waitForTag("fst.shop.sort.open")
        h.waitGone("fst.statistics")
        if (h.exists("fst.nav.drawer")) {
            h.tap("fst.nav.drawer")
            h.waitForTag("fst.nav.drawer.deselect")
            h.awaitAccessibilityTree("fst.nav.drawer.deselect")
            h.readingOrder("nav-player-drawer")
        } else {
            h.waitForTag("fst.nav.drawer.deselect")
        }
        // Issue #162: the player row is one "Profile: <name>" stop with no "Selected Player" caption.
        rule.onNodeWithTag("fst.nav.drawer.player").assert(hasContentDescriptionExactly("Profile: Synthetic Player"))
        val drawer = hasAnyAncestor(hasTestTag("fst.nav.drawer-sheet"))
        assertTrue(rule.onAllNodes(drawer and hasText("Selected", substring = true, ignoreCase = true), useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        h.assertAccessible()
    }

    private companion object {
        /** Navigation chrome that must never straddle a hinge. */
        val NAV_TAGS = arrayOf(
            "fst.nav.bar", "fst.nav.rail", "fst.nav.permanent-drawer",
            "fst.nav.tab.songs", "fst.nav.tab.leaderboards", "fst.nav.tab.settings", "fst.nav.tab.shop",
        )
    }
}
