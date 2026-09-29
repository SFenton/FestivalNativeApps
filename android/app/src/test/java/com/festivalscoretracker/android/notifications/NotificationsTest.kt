package com.festivalscoretracker.android.notifications

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.notifications.ImprovementNotification
import com.festivalscoretracker.android.core.notifications.NotificationDestination
import com.festivalscoretracker.android.core.notifications.NotificationEventPayload
import com.festivalscoretracker.android.core.notifications.NotificationFlagKind
import com.festivalscoretracker.android.core.notifications.NotificationMedia
import com.festivalscoretracker.android.core.notifications.NotificationMediaRules
import com.festivalscoretracker.android.core.notifications.NotificationMessagePart
import com.festivalscoretracker.android.core.notifications.NotificationPayload
import com.festivalscoretracker.android.core.notifications.NotificationRouting
import com.festivalscoretracker.android.core.notifications.NotificationSeenStore
import com.festivalscoretracker.android.core.notifications.NotificationText
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.notifications.playerNotifications
import com.festivalscoretracker.android.presentation.notifications.NotificationsState
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class NotificationsTest {
    private val now = Instant.parse("2026-09-28T12:00:00Z")

    private fun item(
        guid: String, kind: String, song: String? = "s-alpha", instrument: String? = "Solo_Guitar",
        newNumeric: Double? = null, oldNumeric: Double? = null, oldRank: Int? = null, newRank: Int? = null,
        metric: String? = null, payload: NotificationPayload? = null, at: String = "2026-09-28T11:00:00Z",
    ) = ImprovementNotification(
        eventId = 1, notificationGuid = guid, accountId = Fixtures.ACCOUNT_A, eventKind = kind, songId = song, instrument = instrument,
        metric = metric, oldNumeric = oldNumeric, newNumeric = newNumeric, oldRank = oldRank, newRank = newRank, payload = payload, detectedAt = at,
    )

    // region Text and routing

    @Test
    fun formatsPlayerKindsLikeTheWeb() {
        val pb = NotificationText.format(item("a", "player_score_pb", newNumeric = 123456.0), "Alpha Tune")
        assertEquals("Alpha Tune · Lead", pb.title)
        assertEquals("You set a new personal best on Lead for Alpha Tune with 123,456 points.", pb.message)
        assertEquals("New High Score", pb.flag)
        assertEquals(NotificationDestination.Song("s-alpha", Instrument.Lead), pb.destination)

        val first = NotificationText.format(item("b", "player_first_score", newNumeric = 5.0, newRank = 1234), null)
        assertEquals("Your first Lead play on this song scored 5 points and started at #1,234.", first.message)
        assertEquals("Notification", first.title)

        val rank = NotificationText.format(item("c", "player_skill_rank_improved", song = null, oldRank = 10, newRank = 3), null)
        assertEquals("Adjusted Percentile Rank Improved", rank.title)
        assertEquals("You moved up from #10 to #3 in Lead adjusted percentile rankings.", rank.message)
        assertEquals("Rank Up", rank.flag)
        assertEquals(NotificationDestination.Rankings("adjusted", Instrument.Lead), rank.destination)

        val total = NotificationText.format(item("d", "player_total_score_improved", song = null, instrument = null, newNumeric = 1.5), null)
        assertEquals("Total Score Improved", total.title)
        assertEquals("Your this instrument total score increased to 1.5 points.", total.message)
        assertEquals("Progress", total.flag)
        assertNull(total.destination)

        val unknown = NotificationText.format(item("e", "mystery_kind", song = null), null)
        assertEquals("New improvement detected.", unknown.message)
        assertEquals("Improvement", unknown.flag)

        val shop = NotificationText.format(
            item("f", "service_new_shop_song", instrument = null, payload = NotificationPayload(songTitle = " Beta ", artist = null)), null,
        )
        assertEquals("New Song · Beta - Unknown Artist", shop.title)
        assertEquals("Beta by Unknown Artist has been added to the Item Shop.", shop.message)
        assertNull(shop.flag)
        assertEquals(NotificationDestination.Song("s-alpha", null), shop.destination)

        assertEquals("You improved from more to 5 stars on Lead for X.", NotificationText.format(item("g", "player_stars_improved", newNumeric = 5.0), "X").message)
        assertEquals("You improved your difficulty on Lead for X from 2 to a higher difficulty.", NotificationText.format(item("h", "player_difficulty_bumped", oldNumeric = 2.0), "X").message)
        assertEquals("Full Combo Count Improved", NotificationText.format(item("i", "player_fc_count_improved", song = null), null).title)
        listOf(
            "player_fc_achieved" to "Full Combo", "player_gold_stars_achieved" to "Gold Stars", "player_stars_improved" to "Stars Up",
            "player_difficulty_bumped" to "Difficulty Up", "player_fc_count_improved" to "Progress",
        ).forEach { (kind, flag) -> assertEquals(flag, NotificationText.flag(kind)) }
    }

    @Test
    fun mediaFollowsTheWebRail() {
        val art = "https://cdn.example/alpha.jpg"
        // Resolved art alone, art over an instrument grid for multi-chart rows, else the chart icon.
        assertEquals(NotificationMedia.Song(art), NotificationMediaRules.media(item("a", "player_score_pb"), art))
        val multi = item(
            "b", "player_fc_achieved",
            payload = NotificationPayload(
                coalescedEvents = listOf(NotificationEventPayload("player_fc_achieved", "Solo_Drums"), NotificationEventPayload("player_fc_achieved", "Solo_Guitar")),
                coalescedInstruments = listOf("Solo_Bass", "Not_A_Chart"),
            ),
        )
        val grid = NotificationMediaRules.media(multi, art) as NotificationMedia.SongInstrumentGrid
        assertEquals(listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums), grid.instruments)
        assertEquals("Affected instruments: Lead, Bass, Drums", grid.label)
        assertEquals(NotificationMedia.SoloInstrument(Instrument.Drums), NotificationMediaRules.media(item("c", "player_score_pb", instrument = "Solo_Drums"), null))
        assertEquals(NotificationMedia.SoloInstrument(Instrument.Lead), NotificationMediaRules.media(item("d", "player_total_score_improved", instrument = null), " "))
        // Shop songs: art when known, else the Lead icon (web `DEFAULT_INSTRUMENT`), never a grid.
        assertEquals(NotificationMedia.Song(art), NotificationMediaRules.media(item("e", "service_new_shop_song", instrument = null), art))
        assertEquals(NotificationMedia.SoloInstrument(Instrument.Lead), NotificationMediaRules.media(item("f", "service_new_shop_song"), null))
        // format() carries the media through.
        assertEquals(NotificationMedia.Song(art), NotificationText.format(item("g", "player_score_pb"), "Alpha Tune", art).media)
    }

    @Test
    fun messagesBoldTheWebsEmphasisTerms() {
        val pb = NotificationText.format(item("a", "player_score_pb", newNumeric = 123456.0), "Alpha Tune")
        assertEquals(NotificationFlagKind.NewHighScore, pb.flagKind)
        assertEquals(
            listOf(
                NotificationMessagePart("You set a new personal best on "), NotificationMessagePart("Lead", true), NotificationMessagePart(" for "),
                NotificationMessagePart("Alpha Tune", true), NotificationMessagePart(" with "), NotificationMessagePart("123,456", true),
                NotificationMessagePart(" points."),
            ),
            pb.messageParts,
        )
        assertEquals(pb.message, pb.messageParts.joinToString("") { it.text })
        // Fallback wording ("this song", "your new rank") is never bold.
        val first = NotificationText.format(item("b", "player_first_score", newNumeric = 5.0), null)
        assertEquals(listOf("Lead", "5"), first.messageParts.filter { it.emphasis }.map { it.text })
        val stars = NotificationText.format(item("c", "player_stars_improved", oldNumeric = 4.0, newNumeric = 5.0), "Alpha Tune")
        assertTrue(stars.messageParts.any { it.emphasis && it.text == "4 to 5 stars" })
        val fc = NotificationText.format(item("d", "player_fc_achieved"), "Alpha Tune")
        assertTrue(fc.messageParts.any { it.emphasis && it.text == "Full Combo" })
        val gold = NotificationText.format(item("e", "player_gold_stars_achieved"), "Alpha Tune")
        assertTrue(gold.messageParts.any { it.emphasis && it.text == "gold stars" })
        val bump = NotificationText.format(item("f", "player_difficulty_bumped", oldNumeric = 3.0, newNumeric = 4.0), "Alpha Tune")
        assertEquals(listOf("Lead", "Alpha Tune", "3", "4"), bump.messageParts.filter { it.emphasis }.map { it.text })
        val shop = NotificationText.format(
            item("g", "service_new_shop_song", payload = NotificationPayload(songTitle = "Shop Tune", artist = "Band X")), null,
        )
        assertEquals(listOf("Shop Tune", "Band X"), shop.messageParts.filter { it.emphasis }.map { it.text })
        assertNull(shop.flagKind)
        assertEquals(listOf(NotificationMessagePart("plain")), NotificationText.emphasize("plain", listOf("", "this song", "absent")))
        NotificationFlagKind.entries.forEach { assertEquals(it.label, NotificationText.flag(kindFor(it))) }
    }

    private fun kindFor(kind: NotificationFlagKind) = when (kind) {
        NotificationFlagKind.Improvement -> "mystery"
        NotificationFlagKind.FirstPlay -> "player_first_score"
        NotificationFlagKind.NewHighScore -> "player_score_pb"
        NotificationFlagKind.FullCombo -> "player_fc_achieved"
        NotificationFlagKind.RankUp -> "player_song_rank_improved"
        NotificationFlagKind.GoldStars -> "player_gold_stars_achieved"
        NotificationFlagKind.StarsUp -> "player_stars_improved"
        NotificationFlagKind.DifficultyUp -> "player_difficulty_bumped"
        NotificationFlagKind.Progress -> "player_fc_count_improved"
    }

    @Test
    fun routingUsesCoalescedEventsAndMetricFallbacks() {
        val multi = item(
            "a", "player_score_pb",
            payload = NotificationPayload(
                coalescedEvents = listOf(NotificationEventPayload("player_score_pb", "Solo_Guitar"), NotificationEventPayload("player_fc_achieved", "Solo_Bass")),
            ),
        )
        assertEquals(NotificationDestination.Song("s-alpha", null), NotificationRouting.destination(multi))
        val byMetric = item("b", "player_rank_changed", song = null, instrument = null, metric = "fc_rate_rank")
        assertEquals(NotificationDestination.Rankings("fcrate", null), NotificationRouting.destination(byMetric))
        assertEquals("maxscore", NotificationRouting.rankingMetric(null, " composite_rank_max_score "))
        assertNull(NotificationRouting.rankingMetric("nope", "nope"))
    }

    @Test
    fun relativeTimeAndBadge() {
        assertEquals("Just now", NotificationText.relativeTime(now.minusSeconds(30), now))
        assertEquals("5m ago", NotificationText.relativeTime(now.minusSeconds(300), now))
        assertEquals("3h ago", NotificationText.relativeTime(now.minusSeconds(3 * 3600), now))
        assertEquals("2d ago", NotificationText.relativeTime(now.minusSeconds(2 * 86400), now))
        assertTrue(NotificationText.relativeTime(now.minusSeconds(30L * 86400), now).matches(Regex("[A-Z][a-z]{2} \\d{1,2}")))
        assertEquals("99+", NotificationsViewModel.badgeText(120))
        assertEquals("7", NotificationsViewModel.badgeText(7))
        assertEquals("Notifications", NotificationsViewModel.bellLabel(0))
        assertEquals("Notifications, 1 unread", NotificationsViewModel.bellLabel(1))
        assertEquals("Notifications, 4 unread", NotificationsViewModel.bellLabel(4))
        assertEquals("Your this instrument Full Combo count increased to more.", NotificationText.format(item("x", "player_fc_count_improved", song = null, instrument = null), null).message)
    }

    // endregion

    // region Envelope and API

    @Test
    fun envelopeValidationAndGeneratedFlag() {
        assertTrue(NotificationsEnvelope(sourceRunId = 3, items = emptyList()).isGenerated)
        assertFalse(NotificationsEnvelope(items = emptyList()).isGenerated)
        assertFalse(NotificationsEnvelope(notificationsGenerated = false, sourceRunId = 1, items = emptyList()).isGenerated)
        NotificationsEnvelope(items = listOf(item("a", "k"))).validate(5)
        listOf(
            NotificationsEnvelope(items = null),
            NotificationsEnvelope(items = listOf(item("a", "k"), item("b", "k"))),
            NotificationsEnvelope(items = listOf(item("a", "k"), item("a", "k"))),
            NotificationsEnvelope(items = listOf(item("", "k"))),
            NotificationsEnvelope(items = listOf(item("a/b", "k"))),
            NotificationsEnvelope(items = listOf(item("a", ""))),
            NotificationsEnvelope(items = listOf(item("a", "k", song = "x/y"))),
        ).forEach { envelope ->
            try {
                envelope.validate(1)
                fail("expected InvalidResponse for $envelope")
            } catch (_: FestivalApiException.InvalidResponse) {
            }
        }
    }

    @Test
    fun apiReadsKeylessPinnedFeed() = runTest {
        val transport = FakeTransport.standard().apply {
            on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) {
                """{"generatedAt":"2026-09-28T11:00:00Z","expiresAfterHours":72,"sourceRunId":4,"items":[
                   {"eventId":1,"notificationGuid":"g1","accountId":"${Fixtures.ACCOUNT_A}","eventKind":"player_score_pb","songId":"s-alpha","instrument":"Solo_Guitar","newNumeric":100,"detectedAt":"2026-09-28T11:00:00Z","expiresAt":"2026-10-01T11:00:00Z","unknown":1}]}"""
            }
        }
        val api = FestivalApi("https://fixture.test", transport)
        val envelope = api.playerNotifications(Fixtures.ACCOUNT_A, limit = 10)
        assertEquals(1, envelope.items!!.size)
        assertTrue(envelope.isGenerated)
        val sent = transport.sent("/api/player/${Fixtures.ACCOUNT_A}/notifications").single()
        assertTrue(sent.url.endsWith("?limit=10"))
        transport.requests.forEach { RequestGate.validateKeyless(it) }
        try {
            api.playerNotifications("bad id")
            fail()
        } catch (_: FestivalApiException.InvalidResource) {
        }
        try {
            api.playerNotifications(Fixtures.ACCOUNT_A, limit = 500)
            fail()
        } catch (_: FestivalApiException.InvalidResource) {
        }
    }

    // endregion

    // region Seen store

    @Test
    fun seenStoreIsPerAccountPrunedAndBounded() = runBlocking {
        val blob = MemoryBlobStore()
        val store = NotificationSeenStore(blob)
        store.markSeen(Fixtures.ACCOUNT_A, listOf("a", "b"))
        store.markSeen(Fixtures.ACCOUNT_B, listOf("z"))
        assertEquals(setOf("a", "b"), store.seen(Fixtures.ACCOUNT_A))
        assertEquals(setOf("z"), store.seen(Fixtures.ACCOUNT_B))
        store.markSeen(Fixtures.ACCOUNT_A, listOf("c"), currentFeed = listOf("b", "c"))
        assertEquals(setOf("b", "c"), store.seen(Fixtures.ACCOUNT_A))
        val before = blob.value
        store.markSeen(Fixtures.ACCOUNT_A, listOf("c"), currentFeed = listOf("b", "c"))
        assertEquals(before, blob.value)
        store.markSeen(Fixtures.ACCOUNT_A, (0 until 500).map { "id$it" })
        assertEquals(NotificationSeenStore.MAX_PER_ACCOUNT, store.seen(Fixtures.ACCOUNT_A).size)
        assertTrue("id499" in store.seen(Fixtures.ACCOUNT_A))
        (0 until 25).forEach { i -> store.markSeen("%032x".format(i + 100), listOf("x")) }
        assertEquals(NotificationSeenStore.MAX_ACCOUNTS, NotificationSeenStore.decode(blob.value).size)
        assertTrue(NotificationSeenStore.decode("{{").isEmpty())
        assertEquals(setOf(Fixtures.ACCOUNT_A), NotificationSeenStore.decode("""{"${Fixtures.ACCOUNT_A}":["ok",5,""],"bad id!":["x"]}""").keys)
        assertEquals(listOf("ok"), NotificationSeenStore.decode("""{"${Fixtures.ACCOUNT_A}":["ok",5,""]}""")[Fixtures.ACCOUNT_A])
    }

    // endregion

    // region View model

    @Test
    fun viewModelStatesUnreadActivationAndDismissal() = runTest {
        val vmScope = CoroutineScope(StandardTestDispatcher(testScheduler) + Job())
        val player = MutableStateFlow<SelectedPlayer?>(null)
        var fail = false
        var generated = true
        var feed = listOf(
            item("old", "player_fc_achieved", at = "2026-09-27T12:00:00Z"),
            item("new", "player_score_pb", newNumeric = 10.0),
        )
        val store = NotificationSeenStore(MemoryBlobStore())
        val vm = NotificationsViewModel(
            player,
            load = { if (fail) throw FestivalApiException.HttpStatus(500) else NotificationsEnvelope(sourceRunId = if (generated) 1 else null, items = feed) },
            seenStore = store,
            songTitle = { if (it == "s-alpha") "Alpha Tune" else null },
            artwork = { if (it.songId == "s-alpha") "https://cdn.example/alpha.jpg" else null },
            clock = { now },
            scope = vmScope,
        )
        advanceUntilIdle()
        assertEquals(NotificationsState.NoPlayer, vm.state.value)

        player.value = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        advanceUntilIdle()
        val loaded = vm.state.value as NotificationsState.Loaded
        assertEquals(listOf("new", "old"), loaded.newRows.map { it.id })
        assertEquals(2, vm.unreadCount.value)
        assertEquals("1h ago", loaded.newRows.first().timeText)
        assertTrue(loaded.newRows.first().accessibleText.startsWith("Unread. Alpha Tune · Lead."))
        assertEquals(NotificationMedia.Song("https://cdn.example/alpha.jpg"), loaded.newRows.first().presentation.media)

        val destination = vm.activate(loaded.newRows.first())
        advanceUntilIdle()
        assertEquals(NotificationDestination.Song("s-alpha", Instrument.Lead), destination)
        assertEquals(1, vm.unreadCount.value)
        vm.markAllSeen()
        advanceUntilIdle()
        assertEquals(0, vm.unreadCount.value)
        assertEquals(2, (vm.state.value as NotificationsState.Loaded).olderRows.size)

        // A failed refresh keeps the previous feed.
        fail = true
        vm.refresh()
        advanceUntilIdle()
        assertTrue(vm.state.value is NotificationsState.Loaded)

        // Switching accounts shows loading then failure, then an empty generated/not-generated feed.
        player.value = SelectedPlayer(Fixtures.ACCOUNT_B, "Other")
        advanceUntilIdle()
        assertEquals(ServiceIssue.Other("HTTP 500").javaClass, (vm.state.value as NotificationsState.Failed).issue.javaClass)
        fail = false
        feed = emptyList()
        vm.refresh()
        advanceUntilIdle()
        assertTrue((vm.state.value as NotificationsState.Empty).generated)
        generated = false
        vm.refresh()
        advanceUntilIdle()
        val empty = vm.state.value as NotificationsState.Empty
        assertFalse(empty.generated)
        assertTrue(empty.body.startsWith("Notifications may appear here after the next leaderboard update."))
        assertTrue(NotificationsState.Empty(true).body.startsWith("Notifications will appear here"))
        vm.markAllSeen()

        player.value = null
        advanceUntilIdle()
        assertEquals(NotificationsState.NoPlayer, vm.state.value)
        assertEquals(0, vm.unreadCount.value)
        vmScope.cancel()
    }

    // endregion
}
