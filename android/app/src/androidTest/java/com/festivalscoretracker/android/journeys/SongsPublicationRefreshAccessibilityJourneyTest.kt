package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_LABEL
import com.festivalscoretracker.android.ui.common.PUBLICATION_REFRESH_TAG
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #616 accessibility (load-transition R9): with a player selected, a newer publication
 * (seen by the live socket's `/api/publication` re-read, or by any other read such as the
 * bell) refreshes Songs in place. TalkBack meets one polite live-region progress indicator
 * labelled "Loading new scores" instead of rows that say "Player scores paused until songs
 * update", then reads the rebuilt list in the same order as before, at 100% and 200% text and
 * under the in-app Reduce Motion setting (the held spinner shows without fades, R6).
 * ATF runs on every step. Fixtures only (the socket is off for fixture transports); `@DeviceCi`
 * puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class SongsPublicationRefreshAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = SuggestionFixtures.transport()
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val spinner = hasContentDescription(PUBLICATION_REFRESH_LABEL).and(hasAnyAncestor(hasTestTag(PUBLICATION_REFRESH_TAG)))

    private fun pausedShown() = rule.onAllNodes(hasText(PAUSED, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /**
     * The reading order once Songs settled with the player's scores (no paused rows).
     *
     * @param screen Reading-order log name.
     * @return Songs' reading order.
     */
    private fun settledOrder(screen: String): List<String> {
        h.waitForTag(FIRST_ROW)
        rule.waitUntil(15_000) { !h.exists(PUBLICATION_REFRESH_TAG) && !pausedShown() }
        h.awaitAccessibilityTree(present = FIRST_ROW, absent = PUBLICATION_REFRESH_TAG)
        val order = h.readingOrder(screen, fresh = true)
        assertTrue("TalkBack reads paused scores on Songs: $order", order.none { PAUSED in it })
        return order
    }

    /**
     * Publish [publication], re-read it as the live socket does, and check the refresh state
     * while the catalogue read is held.
     *
     * @param publication New publication ID.
     * @param screen Reading-order log name.
     */
    private fun publishAndCheckRefresh(publication: Int, screen: String) {
        val gate = CompletableDeferred<Unit>()
        transport.beforeRespond = { request -> if ("/api/songs" in request.url) withTimeoutOrNull(15_000) { gate.await() } }
        try {
            transport.publish(publication)
            runBlocking { h.container.api.publication(force = true) }
            h.waitForTag(PUBLICATION_REFRESH_TAG)
            rule.waitUntil(15_000) { rule.onAllNodes(spinner).fetchSemanticsNodes().isNotEmpty() }
            val node = rule.onNode(spinner).fetchSemanticsNode()
            assertEquals(LiveRegionMode.Polite, node.config.getOrNull(SemanticsProperties.LiveRegion))
            assertTrue("The refresh spinner is not a progress indicator", node.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo) != null)
            h.awaitAccessibilityTree(present = PUBLICATION_REFRESH_TAG, absent = FIRST_ROW)
            val during = h.readingOrder("$screen-refreshing", fresh = true)
            // One stop: the label plus the indicator's own state ("Loading new scores, In progress"), never a second unnamed one (R2).
            assertEquals("TalkBack does not hear \"$PUBLICATION_REFRESH_LABEL\" once: $during", 1, during.count { it.startsWith(PUBLICATION_REFRESH_LABEL) })
            assertTrue("The refresh spinner has a second, unnamed stop: $during", during.none { it == IN_PROGRESS || it == UNLABELLED })
            assertTrue("TalkBack reads paused scores during the refresh: $during", during.none { PAUSED in it })
        } finally {
            gate.complete(Unit)
            transport.beforeRespond = {}
        }
    }

    /** At 100% and 200% text, a newer publication refreshes Songs in place with the same reading order. */
    @Test
    fun newerPublicationRefreshesSongsInPlaceAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport, fontScale = { scale })
        var publication = 8
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            val screen = "songs-publication-${fontScale}x"
            val before = settledOrder(screen)
            val reads = transport.sent("/api/songs").size
            publishAndCheckRefresh(publication++, screen)
            val after = settledOrder("$screen-refreshed")
            assertTrue("Songs never re-read the catalogue at ${fontScale}x", transport.sent("/api/songs").size > reads)
            assertEquals("TalkBack reads Songs differently after the refresh at ${fontScale}x", before, after)
        }
        h.assertAccessible()
    }

    /**
     * Under the in-app Reduce Motion setting the refresh has no fades (R6) but the same accessible
     * contract: one "Loading new scores" stop, no paused rows, the same order afterwards.
     */
    @Test
    fun reduceMotionRefreshesSongsInPlaceWithTheSameContract() {
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(profile = player, stillBackground = true),
            transport,
            MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true)),
        )
        val before = settledOrder("songs-publication-reduce-motion")
        val reads = transport.sent("/api/songs").size
        publishAndCheckRefresh(8, "songs-publication-reduce-motion")
        val after = settledOrder("songs-publication-reduce-motion-refreshed")
        assertTrue("Songs never re-read the catalogue under Reduce Motion", transport.sent("/api/songs").size > reads)
        assertEquals("TalkBack reads Songs differently after the refresh under Reduce Motion", before, after)
        h.assertAccessible()
    }

    private companion object {
        const val FIRST_ROW = "fst.songs.row.sg-0"
        const val PAUSED = "paused until songs update"
        const val IN_PROGRESS = "In progress"
        const val UNLABELLED = "<unlabelled>"
    }
}
