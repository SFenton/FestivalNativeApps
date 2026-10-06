package com.festivalscoretracker.android.leaderboards

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Process-local preferences so device journeys never touch the app's saved settings. */
private class MemoryPreferences : DataStore<Preferences> {
    private val state = MutableStateFlow(emptyPreferences())
    override val data: Flow<Preferences> = state
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
        transform(state.value).also { state.value = it }
}

/**
 * Leaderboards journeys on a real device/emulator against synthetic rankings (run with
 * `device.py test com.festivalscoretracker.android.leaderboards.LeaderboardsDeviceJourneyTest
 * --avd …`, adding `--posture half` on book folds). On a half-open fold, Rank History and the
 * first instrument card take one panel each and no card straddles the hinge.
 */
@RunWith(AndroidJUnit4::class)
class LeaderboardsDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
        unranked = setOf("Solo_Bass"),
    )
    private val selected = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
    private val lead = "fst.leaderboards.card.Solo_Guitar"

    private fun launch(route: String) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = selected, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) {
        try {
            rule.waitUntil(15_000) { exists(tag) }
        } catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $tag", timeout)
        }
    }

    private fun waitGone(tag: String) = rule.waitUntil(15_000) { !exists(tag) }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    private fun scrollTo(list: String, tag: String) {
        waitForTag(list)
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        rule.waitForIdle()
    }

    /** Separating vertical hinges in window pixels (empty on phones and flat folds). */
    private fun hinges(): List<Rect> = runBlocking {
        val info = withTimeoutOrNull(5_000) { WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first() }
        info?.displayFeatures.orEmpty().filterIsInstance<FoldingFeature>()
            .filter { it.isSeparating && it.orientation == FoldingFeature.Orientation.VERTICAL }
            .map { Rect(it.bounds.left.toFloat(), it.bounds.top.toFloat(), it.bounds.right.toFloat(), it.bounds.bottom.toFloat()) }
    }

    private fun assertNothingStraddles(vararg tags: String) {
        val folds = hinges()
        tags.forEach { tag ->
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().forEach { node ->
                val box = node.boundsInWindow
                folds.forEach { fold -> assertTrue("$tag straddles the fold at ${fold.left}", box.right <= fold.left || box.left >= fold.right) }
            }
        }
    }

    @Test
    fun overviewPairsHistoryAcrossTheFoldAndOpensTheFullBoard() {
        launch("leaderboards")
        waitForTag("fst.leaderboards.rank-history")
        val folds = hinges()
        // On a phone the chart fills the first screen; Lead's card is the next item.
        if (folds.isEmpty()) scrollTo("fst.leaderboards", lead)
        waitForTag(lead)
        assertNothingStraddles("fst.leaderboards.rank-history", lead)
        if (folds.isNotEmpty()) {
            // Half-open book fold: the chart on the leading panel, Lead's card on the trailing one.
            val history = rule.onAllNodesWithTag("fst.leaderboards.rank-history").fetchSemanticsNodes().first().boundsInWindow
            val card = rule.onAllNodesWithTag(lead).fetchSemanticsNodes().first().boundsInWindow
            assertTrue("Rank History on the leading panel", history.right <= folds.first().left)
            assertTrue("Lead card on the trailing panel", card.left >= folds.first().right)
        }
        scrollTo("fst.leaderboards", "$lead.spotlight")
        waitForTag("$lead.spotlight")
        scrollTo("fst.leaderboards", "$lead.view-all")
        tap("$lead.view-all")
        waitForTag("fst.full-rankings.pager")
    }

    @Test
    fun fullRankingsPinsTheSelectedRowOnEveryPage() {
        launch("fullRankings:Solo_Guitar")
        waitForTag("fst.full-rankings.spotlight-footer")
        assertNothingStraddles("fst.full-rankings.pager", "fst.full-rankings.spotlight-footer")
        tap("fst.full-rankings.page-next")
        rule.waitUntil(15_000) { rule.onAllNodesWithContentDescription("Page 2 of 3", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        waitForTag("fst.rankings.row.${RankingsFixtures.SELECTED}")
        // Issue #318: still pinned above the pager on the player's own page.
        waitForTag("fst.full-rankings.spotlight-footer")
        assertNothingStraddles("fst.full-rankings.pager", "fst.full-rankings.spotlight-footer")
    }
}
