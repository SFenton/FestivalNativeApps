package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionContains
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongGeneralFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.songs.SongsPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.data.PublicationConnection
import com.festivalscoretracker.android.presentation.PublicationLiveUpdates
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** R9: a publication read refreshes filtered/sorted Songs in place with one named busy stop. */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class PublicationRefreshAccessibilityJourneyTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    private val h = JourneyHarness(rule)

    @Test fun refreshKeepsSongsFiltersSortAndReadingOrder() = journey(1f, false)
    @Test fun refreshAtLargeTextKeepsNamedTargetsAndReadingOrder() = journey(2f, false)
    @Test fun refreshUnderReducedMotionStillAnnouncesTheBusyState() = journey(1f, true)
    @Test fun notificationFirstRefreshesSongsBeforeTheSheetCloses() = journey(1f, false, bellFirst = true)

    private fun journey(scale: Float, reduceMotion: Boolean, bellFirst: Boolean = false) {
        val preferences = MemoryPreferences()
        val settings = SettingsRepository(preferences)
        runBlocking {
            settings.setSelectedPlayer(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
            settings.setSongSort(SongSortMode.Year, false)
            settings.update { it.copy(reduceMotion = reduceMotion) }
            SongsPreferences(settings).setFilters(
                SongFilter(Instrument.Lead), SongGeneralFilter(),
                SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)),
            )
        }
        val transport = FakeTransport.standard().apply {
            ProfileFixtures.register(this)
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"items":[]}""" }
        }
        lateinit var container: AppContainer
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true),
            transport, preferences, fontScale = { scale }, onContainer = { container = it },
        )
        h.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Year, descending"))
        h.publishTalkBackTree()
        val before = h.readingOrder("publication-before-$scale")
        assertTrue(before.toString(), before.indexOfFirst { it.startsWith("Filter songs") } < before.indexOfFirst { it.startsWith("Alpha Tune") })
        assertNull("Fixture launches must not open real sockets", container.liveUpdates)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val messages = Channel<String>(Channel.UNLIMITED)
        val socketIds = mutableListOf<Int>()
        val held = CompletableDeferred<Unit>()
        try {
            if (!bellFirst) {
                val live = PublicationLiveUpdates(
                    container.api.publicationChanges,
                    { container.api.publication(force = true).publicationId },
                    { id ->
                        socketIds += id
                        object : PublicationConnection {
                            override suspend fun awaitOpen() = Unit
                            override suspend fun receive(): String? = messages.receiveCatching().getOrThrow()
                            override fun cancel() = Unit
                        }
                    },
                    { throw AssertionError(it) },
                )
                scope.launch { live.run() }
                rule.waitUntil(5_000) { socketIds == listOf(7) }
            }
            transport.publish(8)
            transport.on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "8")) {
                Fixtures.songsJson.replace("Alpha Tune", "Alpha Refreshed").replace("\"alpha-512.jpg\"", "null")
            }
            transport.on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "8")) {
                ProfileFixtures.profile(rows = listOf(ProfileFixtures.score("s-alpha", score = 100_000, fc = true)))
            }
            transport.beforeRespond = { request -> if (request.url.substringBefore('?').endsWith("/api/songs")) held.await() }
            if (bellFirst) {
                h.tap("fst.shell.notifications")
                rule.waitUntil(5_000) { container.api.publicationChanges.value == 8 }
                h.tap("fst.notifications.close")
            } else {
                messages.trySend("""{"type":"publication_changed","publicationId":8}""").getOrThrow()
            }
            h.waitForTag("fst.songs.loading")
            rule.onNodeWithContentDescription("Loading new scores")
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
            rule.onNodeWithTag("fst.songs.row.s-alpha").assertDoesNotExist()
            val during = h.readingOrder("publication-loading-$scale", fresh = true)
            assertTrue(during.toString(), during.count { it.startsWith("Loading new scores") } == 1)
            assertTrue(during.toString(), during.indexOfFirst { it.startsWith("Filter songs") } < during.indexOfFirst { it.startsWith("Loading new scores") })
            rule.onNodeWithTag("fst.songs.search").assertExists()
            h.assertAccessible()
            val revealStart = SystemClock.uptimeMillis()
            held.complete(Unit)
            h.waitForTag("fst.songs.row.s-alpha")
            assertTrue("ready scores must reappear within seconds", SystemClock.uptimeMillis() - revealStart < 5_000)
            rule.onNodeWithTag("fst.songs.row.s-alpha").assertContentDescriptionContains("100,000", substring = true)
            rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Year, descending"))
            val after = h.readingOrder("publication-after-$scale", fresh = true)
            val alpha = after.indexOfFirst { it.startsWith("Alpha Refreshed") }
            assertTrue(after.toString(), alpha >= 0 && after.none { it.contains("paused until") || it.startsWith("Loading new scores") || it.startsWith("Beta Song") })
            assertTrue(rule.onNodeWithTag("fst.songs.row.s-alpha").fetchSemanticsNode().size.height >= with(rule.density) { 48.dp.toPx() } - 1)
            h.assertAccessible()
        } finally {
            held.complete(Unit)
            scope.cancel()
            messages.cancel()
        }
    }
}
