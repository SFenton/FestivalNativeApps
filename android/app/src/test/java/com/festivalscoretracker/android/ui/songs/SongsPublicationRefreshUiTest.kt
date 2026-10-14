package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_LABEL
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_TAG
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Issue #616 (load-transition R9): with a player selected, a newer publication observed by any
 * read (the bell, the live socket's `/api/publication` re-read) refreshes Songs in place. The
 * page shows one polite live-region spinner TalkBack reads as "Loading new scores", never the
 * "Player scores paused until songs update" rows or notice, then the rebuilt rows with scores.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsPublicationRefreshUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = SuggestionFixtures.transport()
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private fun settle(millis: Long = 100) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis))
        rule.waitForIdle()
    }

    private fun waitUntil(condition: () -> Boolean) = rule.waitUntil(10_000) {
        settle()
        condition()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun pausedShown() = rule.onAllNodes(hasText("paused until", substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private val notice = SemanticsMatcher("Songs notice") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.songs.notice") == true }

    @Test
    fun newerPublicationRefreshesSongsInPlaceWithAnAnnouncedSpinnerAndNoPausedRows() {
        val debug = DebugLaunch(profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        // Fixture transport: no live socket (it is only for the public HTTPS origin).
        assertNull(container.liveUpdates)
        rule.setContent { FestivalApp(container, debug) }
        waitUntil { exists("fst.songs.row.sg-0") }
        waitUntil { !pausedShown() && rule.onAllNodes(hasText("Loading scores"), useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }

        // Hold the catch-up's catalogue read so the refresh state can be observed.
        val gate = CompletableDeferred<Unit>()
        transport.beforeRespond = { request -> if ("/api/songs" in request.url) gate.await() }
        transport.publish(8)
        runBlocking { container.api.publication(force = true) }

        waitUntil { exists(PUBLICATION_REFRESH_TAG) }
        settle(400)
        val spinner = rule.onNode(hasContentDescription(PUBLICATION_REFRESH_LABEL) and hasAnyAncestor(hasTestTag(PUBLICATION_REFRESH_TAG))).fetchSemanticsNode()
        assertEquals(LiveRegionMode.Polite, spinner.config.getOrNull(SemanticsProperties.LiveRegion))
        assertTrue("The refresh spinner is not a progress indicator", spinner.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo) != null)
        assertTrue("Old rows stay readable behind the refresh spinner", !exists("fst.songs.row.sg-0"))
        assertTrue("Songs paused instead of refreshing in place", !pausedShown())
        assertTrue("A notice card showed during the refresh", rule.onAllNodes(notice, useUnmergedTree = true).fetchSemanticsNodes().isEmpty())

        gate.complete(Unit)
        waitUntil { exists("fst.songs.row.sg-0") && !exists(PUBLICATION_REFRESH_TAG) }
        assertTrue("Rows paused after the refresh", !pausedShown())
        assertTrue("The catalogue was not re-read for publication 8", transport.sent("/api/songs").size >= 2)
        assertEquals(8, container.api.publicationChanges.value)
    }
}
