package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #136: the Notifications control on a real device/emulator against synthetic fixtures
 * (`device.py test com.festivalscoretracker.android.journeys.NotificationsDeviceTest --avd FST_Phone`,
 * and `--avd FST_Book_Fold --posture half`). Accessibility Test Framework checks run on every
 * interaction, each sheet state logs its TalkBack reading order, rows and the sheet's buttons
 * are at least 48 dp, nothing straddles a separating hinge, and rows open Song Detail and
 * full rankings.
 */
@RunWith(AndroidJUnit4::class)
class NotificationsDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")

    private fun transport(feed: String) = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/player/${RankingsFixtures.SELECTED}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) { feed }
        },
    )

    private val feed = """{"sourceRunId":3,"items":[
      {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-alpha","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"},
      {"eventId":2,"notificationGuid":"n-rank","eventKind":"player_weighted_rank_improved","instrument":"Solo_Guitar","metric":"weighted_rank","oldRank":45,"newRank":40,"detectedAt":"2026-09-28T10:00:00Z"},
      {"eventId":3,"notificationGuid":"n-total","eventKind":"player_total_score_improved","newNumeric":5,"detectedAt":"2026-09-27T11:00:00Z"}]}"""

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

    private fun assertKeyless(transport: FakeTransport) = transport.requests.forEach { request ->
        RequestGate.validateKeyless(request)
        assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
    }

    private fun openBell() = h.tap("fst.shell.notifications")

    /** Settings with Experimental Ranks [on] (`experimental-ranks` R4: rank rows show only while on). */
    private fun experimentalRanks(on: Boolean) =
        MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS) to on))

    @Test
    fun unreadThenOlderRowsOpenSongDetailAndFullRankings() {
        h.enableAccessibilityChecks()
        val transport = transport(feed)
        h.launch(DebugLaunch(profile = player, opensNotifications = true, stillBackground = true), transport, experimentalRanks(true))
        h.waitForTag("fst.notifications.row.n-song")
        val unread = h.readingOrder("notifications-unread")
        before(unread, "Notifications", "New")
        before(unread, "New", "Unread. Alpha Tune")
        before(unread, "Alpha Tune", "Unread. Weighted")
        assertTargets("fst.notifications.close", "fst.notifications.row.n-song", "fst.notifications.row.n-rank")
        h.assertNothingStraddles("fst.notifications.sheet", "fst.notifications.row.n-song")

        // A song row marks itself seen, closes the sheet and opens Song Detail.
        h.tap("fst.notifications.row.n-song")
        h.waitGone("fst.notifications.sheet")
        h.waitForTag("fst.song-detail.list")

        // Reopened, every row is read ("Older"); a rank row opens full rankings.
        openBell()
        h.waitForTag("fst.notifications.row.n-rank")
        val older = h.readingOrder("notifications-older")
        before(older, "Older", "Alpha Tune")
        assertTrue(older.none { it.startsWith("Unread") })
        h.scrollTo("fst.notifications.list", "fst.notifications.row.n-total")
        assertTargets("fst.notifications.row.n-total")
        h.tap("fst.notifications.row.n-rank")
        h.waitGone("fst.notifications.sheet")
        h.waitForTag("fst.full-rankings.pager")

        assertKeyless(transport)
        h.assertAccessible()
    }

    @Test
    fun experimentalRankRowsHideWhileTheSettingIsOff() {
        h.enableAccessibilityChecks()
        val transport = transport(feed)
        h.launch(DebugLaunch(profile = player, opensNotifications = true, stillBackground = true), transport, experimentalRanks(false))
        h.waitForTag("fst.notifications.row.n-total")
        val unread = h.readingOrder("notifications-experimental-off")
        before(unread, "Unread. Alpha Tune", "Unread. Total Score Improved")
        assertTrue("experimental rank row read with Experimental Ranks off: $unread", unread.none { it.contains("Weighted") })
        assertFalse(h.exists("fst.notifications.row.n-rank"))
        assertKeyless(transport)
        h.assertAccessible()
    }

    @Test
    fun emptyAndNoProfileStatesAreAccessible() {
        h.enableAccessibilityChecks()
        val transport = transport("""{"sourceRunId":3,"notificationsGenerated":true,"items":[]}""")
        h.launch(DebugLaunch(profile = player, opensNotifications = true, stillBackground = true), transport)
        h.waitForTag("fst.notifications.empty")
        before(h.readingOrder("notifications-empty"), "No notifications available", "Notifications will appear here")
        h.assertNothingStraddles("fst.notifications.sheet", "fst.notifications.empty")
        assertKeyless(transport)
        h.assertAccessible()
    }

    @Test
    fun noProfileOffersProfileSelection() {
        h.enableAccessibilityChecks()
        val transport = transport(feed)
        h.launch(DebugLaunch(opensNotifications = true, stillBackground = true), transport)
        h.waitForTag("fst.notifications.no-player")
        before(h.readingOrder("notifications-no-player"), "Select a player profile", "Select Player Profile")
        h.assertNothingStraddles("fst.notifications.sheet", "fst.notifications.no-player")
        assertTrue(transport.requests.none { it.url.contains("/notifications") })
        h.assertAccessible()
    }
}
