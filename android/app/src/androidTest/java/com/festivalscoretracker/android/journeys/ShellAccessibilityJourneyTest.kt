package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
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
}
