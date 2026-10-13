package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_SPINNER_TAG
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_STATUS
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_STATUS_TAG
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Songs follows a new service publication in place (load-transition R9, issue #616), with ATF on
 * every state. With a player selected, a newer publication (as the live socket or the bell would
 * observe it) holds the new catalogue read open:
 * - the page stays on Songs; the status reads "Loading new scores" once, as indeterminate
 *   progress, and no stale song row stays readable under the swap's spinner;
 * - once the catalogue and the player's scores land, the rows come back with the player's scores,
 *   never "Player scores paused until songs update", and the status goes silent.
 *
 * `device.py test com.festivalscoretracker.android.journeys.PublicationRefreshAccessibilityJourneyTest --avd …`
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class PublicationRefreshAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    @Volatile
    private var songsGate: CompletableDeferred<Unit>? = null
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        beforeRespond = { request -> if (request.url.contains("/api/songs")) songsGate?.await() }
    }

    @After
    fun release() {
        songsGate?.complete(Unit)
    }

    /** Nodes TalkBack would read as a paused score row. */
    private fun pausedRows() = rule.onAllNodes(
        hasContentDescription(PAUSED, substring = true) or hasText(PAUSED, substring = true),
        useUnmergedTree = true,
    ).fetchSemanticsNodes()

    @Test
    fun newPublicationRefreshesSongsInPlaceAndSpeaksOnce() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag(ROW)
        h.publishTalkBackTree()
        assertTrue("paused before the publication", pausedRows().isEmpty())
        assertEquals(null, rule.onNodeWithTag(PUBLICATION_REFRESH_STATUS_TAG, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription))

        // Publication 8 lands; its catalogue read stays open so the refresh state can be read.
        val headers = mapOf("X-FST-Publication-Id" to "8")
        songsGate = CompletableDeferred()
        transport.on("/api/publication") { Fixtures.publication(8) }
        transport.on("/api/songs", headers = headers) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(transport, headers = headers)
        runBlocking { h.launchedContainer!!.api.publication(force = true) }

        h.waitForTag(PUBLICATION_REFRESH_SPINNER_TAG)
        h.awaitAccessibilityTree(present = "fst.songs.search", absent = ROW)
        val status = rule.onNodeWithTag(PUBLICATION_REFRESH_STATUS_TAG, useUnmergedTree = true).fetchSemanticsNode().config
        assertEquals(listOf(PUBLICATION_REFRESH_STATUS), status.getOrNull(SemanticsProperties.ContentDescription))
        assertEquals(ProgressBarRangeInfo.Indeterminate, status.getOrNull(SemanticsProperties.ProgressBarRangeInfo))
        val order = h.readingOrder("songs-publication-refresh", fresh = true)
        assertEquals("\"$PUBLICATION_REFRESH_STATUS\" is not one stop in $order", 1, order.count { it.startsWith(PUBLICATION_REFRESH_STATUS) })
        assertTrue("stale rows readable under the refresh: $order", order.none { it.contains("Alpha") })
        assertTrue("left Songs", h.exists("fst.songs.list") || h.exists(PUBLICATION_REFRESH_SPINNER_TAG))
        h.assertAccessible()

        songsGate!!.complete(Unit)
        h.waitForTag(ROW)
        h.waitGone(PUBLICATION_REFRESH_SPINNER_TAG)
        assertTrue("paused rows after the refresh", pausedRows().isEmpty())
        rule.waitUntil(5_000) {
            rule.onNodeWithTag(PUBLICATION_REFRESH_STATUS_TAG, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription) == null
        }
        h.readingOrder("songs-publication-refreshed", fresh = true)
        h.assertAccessible()
    }

    private companion object {
        const val ROW = "fst.songs.row.s-alpha"
        const val PAUSED = "paused until songs update"
    }
}
