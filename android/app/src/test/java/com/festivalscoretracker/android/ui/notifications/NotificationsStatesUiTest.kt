package com.festivalscoretracker.android.ui.notifications

import android.os.Looper
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.notifications.ImprovementNotification
import com.festivalscoretracker.android.core.notifications.NotificationSeenStore
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.presentation.notifications.NotificationsState
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Issue #136: every reachable Notifications control state on the sheet (spec "States"):
 * no-profile, both empty variants, loaded, the unread "New" and read "Older" sections, and
 * row taps that navigate to Song Detail or full rankings (or stay put without a destination).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class NotificationsStatesUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val seenStore = NotificationSeenStore(MemoryBlobStore())
    private var loads = 0
    private var dismissed = 0
    private var choseProfile = 0
    private val routes = mutableListOf<AppRoute>()

    private fun item(guid: String, kind: String, detectedAt: String, song: String? = null, instrument: String? = null, metric: String? = null) = ImprovementNotification(
        eventId = 1, notificationGuid = guid, accountId = Fixtures.ACCOUNT_A, eventKind = kind, songId = song, instrument = instrument,
        metric = metric, oldRank = 9, newRank = 4, oldNumeric = 100.0, newNumeric = 200.0, detectedAt = detectedAt,
    )

    private val song = item("n-song", "player_score_pb", "2026-09-28T11:00:00Z", song = "s-alpha", instrument = "Solo_Guitar")
    private val rank = item("n-rank", "player_weighted_rank_improved", "2026-09-28T10:00:00Z", instrument = "Solo_Drums", metric = "weighted_rank")
    private val hub = item("n-hub", "player_total_score_rank_improved", "2026-09-28T09:00:00Z")
    private val total = item("n-total", "player_total_score_improved", "2026-09-27T11:00:00Z")

    private fun show(envelope: NotificationsEnvelope?, player: SelectedPlayer? = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")): NotificationsViewModel {
        val vm = NotificationsViewModel(
            player = MutableStateFlow(player),
            load = { loads++; envelope ?: error("no feed") },
            seenStore = seenStore,
            songTitle = { if (it == "s-alpha") "Alpha Tune" else null },
            clock = { Instant.parse("2026-09-28T12:00:00Z") },
        )
        rule.setContent {
            FestivalTheme {
                NotificationsSheet(vm, onDismiss = { dismissed++ }, onNavigate = { routes += it }, onChooseProfile = { choseProfile++ })
            }
        }
        idle()
        return vm
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))

    private fun waitFor(tag: String) = rule.waitUntil(10_000) {
        idle()
        rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun row(guid: String) = rule.onNodeWithTag("fst.notifications.row.$guid")

    private fun scrollTo(guid: String) = rule.onNodeWithTag("fst.notifications.list").performScrollToNode(hasTestTag("fst.notifications.row.$guid"))

    private fun description(guid: String): String = row(guid).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    private fun tapRow(guid: String) {
        scrollTo(guid)
        row(guid).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
        idle()
    }

    @Test
    fun noProfileAsksForAPlayerWithoutReading() {
        show(NotificationsEnvelope(sourceRunId = 1, items = listOf(song)), player = null)
        waitFor("fst.notifications.no-player")
        rule.onNodeWithText("Select a player profile to see notifications about new high scores and rank changes.").assertIsDisplayed()
        rule.onNodeWithText("Select Player Profile").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
        assertEquals(0, loads)
        assertEquals(1, dismissed)
        assertEquals(1, choseProfile)
    }

    @Test
    fun emptyGeneratedFeedSaysNotificationsWillAppear() {
        show(NotificationsEnvelope(sourceRunId = 3, notificationsGenerated = true, items = emptyList()))
        waitFor("fst.notifications.empty")
        rule.onNodeWithText("No notifications available").assertIsDisplayed()
        rule.onNodeWithText("Notifications will appear here", substring = true).assertIsDisplayed()
        assertFalse(exists("fst.notifications.list"))
    }

    @Test
    fun emptyNotGeneratedFeedSaysAfterTheNextUpdate() {
        show(NotificationsEnvelope(items = emptyList()))
        waitFor("fst.notifications.empty")
        rule.onNodeWithText("No notifications available").assertIsDisplayed()
        rule.onNodeWithText("Notifications may appear here after the next leaderboard update", substring = true).assertIsDisplayed()
    }

    @Test
    fun loadedFeedListsEveryRowNewestFirstWithDestinationsSpoken() {
        val vm = show(NotificationsEnvelope(sourceRunId = 3, items = listOf(total, hub, song, rank)))
        waitFor("fst.notifications.list")
        val loaded = vm.state.value as NotificationsState.Loaded
        assertEquals(listOf("n-song", "n-rank", "n-hub", "n-total"), loaded.newRows.map { it.id })
        listOf("n-song", "n-rank", "n-hub", "n-total").forEach { guid -> scrollTo(guid); row(guid).assertIsDisplayed() }
        scrollTo("n-song")
        assertTrue(description("n-song"), description("n-song").startsWith("Unread. Alpha Tune, Lead."))
        assertTrue(description("n-song"), description("n-song").endsWith("New High Score. 1 hour ago"))
        listOf("n-song", "n-rank", "n-hub").forEach { guid ->
            scrollTo(guid)
            row(guid).assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, androidx.compose.ui.semantics.Role.Button))
            row(guid).assert(SemanticsMatcher("$guid opens") { it.config[SemanticsActions.OnClick].label == "Open notification" })
        }
        scrollTo("n-total")
        row("n-total").assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Role))
    }

    @Test
    fun unreadRowsSitUnderNewAndTheBellCountsThem() {
        val vm = show(NotificationsEnvelope(sourceRunId = 3, items = listOf(song, rank)))
        waitFor("fst.notifications.list")
        rule.onNodeWithText("NEW", useUnmergedTree = true).assertIsDisplayed()
        assertTrue(rule.onAllNodesWithText("OLDER", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        assertEquals(2, vm.unreadCount.value)
        assertEquals("Notifications, 2 unread", NotificationsViewModel.bellLabel(vm.unreadCount.value))
        assertTrue(description("n-rank").startsWith("Unread. "))
    }

    @Test
    fun seenRowsSitUnderOlderAfterTheUnreadOnes() {
        runBlocking { seenStore.markSeen(Fixtures.ACCOUNT_A, listOf("n-rank", "n-total")) }
        val vm = show(NotificationsEnvelope(sourceRunId = 3, items = listOf(song, rank, total)))
        waitFor("fst.notifications.list")
        val newTop = rule.onNodeWithText("NEW", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top
        val olderTop = rule.onNodeWithText("OLDER", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top
        val songTop = row("n-song").fetchSemanticsNode().boundsInRoot.top
        scrollTo("n-rank")
        assertTrue(newTop < songTop && songTop < olderTop)
        assertFalse(description("n-rank").startsWith("Unread"))
        assertEquals(1, vm.unreadCount.value)
    }

    @Test
    fun songRowMarksSeenClosesAndOpensSongDetail() {
        val vm = show(NotificationsEnvelope(sourceRunId = 3, items = listOf(song, total)))
        waitFor("fst.notifications.list")
        tapRow("n-song")
        rule.waitUntil(5_000) { idle(); vm.unreadCount.value == 0 }
        assertEquals(listOf<AppRoute>(SongDetailRoute("s-alpha", "Solo_Guitar")), routes)
        assertEquals(1, dismissed)
        assertTrue(runBlocking { seenStore.seen(Fixtures.ACCOUNT_A) }.containsAll(listOf("n-song", "n-total")))
    }

    @Test
    fun rankRowsOpenFullRankingsOrTheLeaderboardsHub() {
        show(NotificationsEnvelope(sourceRunId = 3, items = listOf(rank, hub)))
        waitFor("fst.notifications.list")
        tapRow("n-rank")
        tapRow("n-hub")
        assertEquals(listOf(FullRankingsRoute("Solo_Drums", "weighted"), LeaderboardsRoute), routes)
        assertEquals(2, dismissed)
    }

    @Test
    fun rowWithoutADestinationOnlyMarksItSeen() {
        val vm = show(NotificationsEnvelope(sourceRunId = 3, items = listOf(total)))
        waitFor("fst.notifications.list")
        tapRow("n-total")
        rule.waitUntil(5_000) { idle(); vm.unreadCount.value == 0 }
        assertTrue(routes.isEmpty())
        assertEquals(0, dismissed)
        rule.onNodeWithText("OLDER", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun failedReadOffersRetry() {
        show(null)
        waitFor("fst.notifications.failed")
        val before = loads
        rule.onNodeWithText("Retry").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(5_000) { idle(); loads > before }
        assertTrue(exists("fst.notifications.failed"))
    }
}
