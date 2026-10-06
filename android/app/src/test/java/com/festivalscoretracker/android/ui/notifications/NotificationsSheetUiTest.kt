package com.festivalscoretracker.android.ui.notifications

import android.os.Looper
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.notifications.ImprovementNotification
import com.festivalscoretracker.android.core.notifications.NotificationEventPayload
import com.festivalscoretracker.android.core.notifications.NotificationFlagKind
import com.festivalscoretracker.android.core.notifications.NotificationPayload
import com.festivalscoretracker.android.core.notifications.NotificationSeenStore
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** The web-style notification rows (6.34): media rail variants, flags and the empty state. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class NotificationsSheetUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val art = "https://cdn.example/art.jpg"

    private fun row(guid: String, kind: String, song: String? = "s-alpha", payload: NotificationPayload? = null) = ImprovementNotification(
        eventId = 1, notificationGuid = guid, accountId = Fixtures.ACCOUNT_A, eventKind = kind, songId = song,
        instrument = "Solo_Guitar", newNumeric = 10.0, oldNumeric = 9.0, oldRank = 5, newRank = 2, payload = payload,
        detectedAt = "2026-09-28T11:00:00Z",
    )

    private fun show(items: List<ImprovementNotification>) {
        val vm = NotificationsViewModel(
            player = MutableStateFlow(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")),
            load = { NotificationsEnvelope(sourceRunId = 1, items = items) },
            seenStore = NotificationSeenStore(MemoryBlobStore()),
            songTitle = { "Alpha Tune" },
            artwork = { item -> art.takeIf { item.songId == "s-alpha" } },
        )
        rule.setContent { FestivalTheme { NotificationsSheet(vm, onDismiss = {}, onNavigate = {}, onChooseProfile = {}) } }
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.onAllNodesWithTag("fst.notifications.list").fetchSemanticsNodes().isNotEmpty() ||
                rule.onAllNodesWithTag("fst.notifications.empty").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun media(guid: String, kind: String) {
        rule.onNodeWithTag("fst.notifications.list").performScrollToNode(hasTestTag("fst.notifications.row.$guid"))
        rule.onNodeWithTag("fst.notifications.row.$guid").assert(SemanticsMatcher.expectValue(NotificationMediaKind, kind))
    }

    @Test
    fun rowsShowTheWebMediaRail() {
        val grid = NotificationPayload(coalescedEvents = listOf(NotificationEventPayload("player_fc_achieved", "Solo_Drums"), NotificationEventPayload("player_fc_achieved", "Solo_Guitar")))
        show(
            listOf(
                row("art", "player_score_pb"),
                row("grid", "player_fc_achieved", payload = grid),
                row("icon", "player_total_score_improved", song = null),
                row("shop", "service_new_shop_song", song = "s-shop", payload = NotificationPayload(songTitle = "Shop Tune", artist = "Band X")),
            ),
        )
        media("art", "song")
        media("grid", "songInstrumentGrid")
        media("icon", "soloInstrument")
        media("shop", "soloInstrument")
        rule.onNodeWithText("NEW", useUnmergedTree = true).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("New")))
    }

    @Test
    fun emptyFeedShowsTheWebEmptyState() {
        show(emptyList())
        rule.onNodeWithText("No notifications available", useUnmergedTree = true).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
    }

    @Test
    fun rowsDrawEveryFlagAndPerChartFlagGroups() {
        val coalesced = NotificationPayload(
            newFullCombo = true,
            newStars = 6.0,
            coalescedEvents = listOf(NotificationEventPayload("player_first_score", "Solo_Guitar", newNumeric = 100.0, newRank = 3.0)),
        )
        val multi = NotificationPayload(
            coalescedEvents = listOf(
                NotificationEventPayload("player_score_pb", "Solo_Guitar", newNumeric = 100.0),
                NotificationEventPayload("player_fc_achieved", "Solo_Bass"),
            ),
        )
        show(listOf(row("chips", "player_first_score", payload = coalesced), row("groups", "player_score_pb", payload = multi)))
        rule.onNodeWithTag("fst.notifications.list").performScrollToNode(hasTestTag("fst.notifications.row.chips"))
        rule.onNodeWithTag("fst.notifications.row.chips").assert(SemanticsMatcher.expectValue(NotificationFlagsKey, "FirstPlay,FullCombo,GoldStars"))
        val chips = rule.onNodeWithTag("fst.notifications.row.chips").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(chips, chips.contains("got a Full Combo, and earned gold stars. First Play, Full Combo, Gold Stars."))
        rule.onNodeWithTag("fst.notifications.list").performScrollToNode(hasTestTag("fst.notifications.row.groups"))
        rule.onNodeWithTag("fst.notifications.row.groups").assert(SemanticsMatcher.expectValue(NotificationFlagsKey, "Lead:NewHighScore|Bass:FullCombo"))
        val groups = rule.onNodeWithTag("fst.notifications.row.groups").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(groups, groups.contains("For Lead, your play set a new personal best with 100 points. For Bass, got a Full Combo. Lead: New High Score. Bass: Full Combo."))
    }

    @Test
    fun flagColoursMatchTheWeb() {
        val colours = NotificationFlagKind.entries.map { it.color() }
        assertEquals(NotificationFlagKind.entries.size, colours.toSet().size)
        assertEquals(Color(0xFF1D4ED8), NotificationFlagKind.RankUp.color())
        // White 12 sp semibold labels need WCAG AA 4.5:1 on every pill colour.
        NotificationFlagKind.entries.forEach { kind ->
            val ratio = 1.05f / (kind.color().luminance() + 0.05f)
            assertTrue("$kind contrast $ratio", ratio >= 4.5f)
        }
    }
}
