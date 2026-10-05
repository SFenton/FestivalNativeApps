package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
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
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

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
     * widths, Leaderboards + Rivals on regular ones), Statistics, and the drawer's player row.
     */
    @Test
    fun appNavigationPlayerStates() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), navigationTransport)
        h.waitForTag("fst.songs.list")
        h.waitForTag("fst.nav.tab.suggestions")
        h.waitForTag("fst.nav.tab.statistics")
        assertTrue(h.exists("fst.nav.tab.compete") != h.exists("fst.nav.tab.rivals"))
        h.assertNothingStraddles(*NAV_TAGS)
        h.readingOrder("nav-player")
        h.tap("fst.nav.tab.statistics")
        h.waitForTag("fst.statistics")
        h.waitGone("fst.songs.list")
        h.awaitAccessibilityTree("fst.statistics", absent = "fst.songs.list")
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsSelected()
        h.readingOrder("nav-player-statistics")
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
            "fst.nav.tab.songs", "fst.nav.tab.leaderboards", "fst.nav.tab.settings", "fst.nav.tab.statistics",
        )
    }
}
