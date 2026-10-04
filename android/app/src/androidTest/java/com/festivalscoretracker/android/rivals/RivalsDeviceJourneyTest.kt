package com.festivalscoretracker.android.rivals

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.rivals.RivalPill
import com.festivalscoretracker.android.ui.rivals.RivalRow
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
 * Rivals journeys on a real device/emulator against synthetic rivals (run with
 * `device.py test com.festivalscoretracker.android.rivals.RivalsDeviceJourneyTest --avd …`,
 * adding `--posture half` on book folds): hub → Rival Detail → Rivalry, and the Leaderboard
 * tab, with no card straddling a separating hinge.
 */
@RunWith(AndroidJUnit4::class)
class RivalsDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val ids = RivalsFixtures.RIVALS

    private val transport = RivalsFixtures.transport().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun launch() {
        val debug = DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
    }

    private fun waitForTag(tag: String) = rule.waitUntil(15_000) { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onAllNodesWithTag(tag)[0].performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    private fun scrollTo(tag: String) {
        waitForTag("fst.rivals.grid")
        rule.onNodeWithTag("fst.rivals.grid").performScrollToNode(hasTestTag(tag))
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
    fun hubDetailAndRivalry() {
        launch()
        waitForTag("fst.rivals.section.common")
        assertNothingStraddles("fst.rivals.section.common", "fst.rivals.row.${ids[1]}")
        scrollTo("fst.rivals.section.Solo_Guitar")
        assertNothingStraddles("fst.rivals.section.Solo_Guitar")
        scrollTo("fst.rivals.section.common")
        tap("fst.rivals.row.${ids[1]}")
        waitForTag("fst.rival-detail.title")
        tap("fst.rival-detail.see-all.closest_battles")
        waitForTag("fst.rivalry.title")
        waitForTag("fst.rivals.song.s-alpha.Solo_Guitar")
        assertNothingStraddles("fst.rivalry.title", "fst.rivals.song.s-alpha.Solo_Guitar", "fst.rivals.song.s-beta.Solo_Guitar")
        tap("fst.rivalry.sort")
        waitForTag("fst.rivalry.sort.menu")
        rule.onNodeWithTag("fst.rivalry.sort.category").assertIsSelected()
        tap("fst.rivalry.sort.title")
        tap("fst.rivalry.sort")
        waitForTag("fst.rivalry.sort.menu")
        rule.onNodeWithTag("fst.rivalry.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.rivalry.sort.category").assertIsNotSelected()
    }

    @Test
    fun leaderboardTabShowsNeighbours() {
        launch()
        waitForTag("fst.rivals.tab.leaderboard")
        tap("fst.rivals.tab.leaderboard")
        waitForTag("fst.rivals.section.leaderboard.Solo_Guitar")
        assertNothingStraddles("fst.rivals.section.leaderboard.Solo_Guitar")
    }

    /** Issue #107: with real fonts at 2.0 scale, a narrow card wraps its pills and grows to show both. */
    @Test
    fun largeTextRowShowsBothPills() {
        fun entry(id: String) = RivalEntry(RivalSummary(id, "Ann", 1.0, sharedSongCount = 162, aheadCount = 110, behindCount = 52), RivalDirection.Above)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(300.dp)) { RivalRow(entry(ids[0]), onClick = {}) }
                        Box(Modifier.requiredWidth(720.dp)) { RivalRow(entry(ids[1]), onClick = {}) }
                        RivalPill("110 songs behind", win = false, modifier = Modifier.testTag("pill"))
                    }
                }
            }
        }
        fun height(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().size.height
        val pill = height("pill")
        val oneLine = height("fst.rivals.row.${ids[1]}")
        val wrapped = height("fst.rivals.row.${ids[0]}")
        assertTrue("wrapped row $wrapped px should fit a second pill line ($oneLine + $pill px)", wrapped >= oneLine + pill)
    }
}