package com.festivalscoretracker.android.profile

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
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
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
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
 * Player-page journeys on a real device/emulator against synthetic fixtures (run with
 * `device.py test com.festivalscoretracker.android.profile.ProfileDeviceJourneyTest --avd …`,
 * adding `--posture half` on book folds). Every card is checked against the separating
 * hinges WindowManager reports, so a half-open fold proves nothing straddles it.
 */
@RunWith(AndroidJUnit4::class)
class ProfileDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        ProfileFixtures.register(this, Fixtures.ACCOUNT_B)
    }

    private fun launch(debug: DebugLaunch) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
    }

    private fun waitForTag(tag: String) = rule.waitUntil(15_000) { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun waitGone(tag: String) = rule.waitUntil(15_000) { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    private fun scrollTo(tag: String) {
        waitForTag("fst.player.available")
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag(tag))
        rule.waitForIdle()
    }

    /** Separating vertical hinges in window pixels (empty on phones and flat folds). */
    private fun hinges(): List<Rect> = runBlocking {
        val info = withTimeoutOrNull(5_000) { WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first() }
        info?.displayFeatures.orEmpty().filterIsInstance<FoldingFeature>()
            .filter { it.isSeparating && it.orientation == FoldingFeature.Orientation.VERTICAL }
            .map { Rect(it.bounds.left.toFloat(), it.bounds.top.toFloat(), it.bounds.right.toFloat(), it.bounds.bottom.toFloat()) }
    }

    /** No realized card crosses a separating hinge. */
    private fun assertNothingStraddles(vararg tags: String) {
        val folds = hinges()
        tags.forEach { tag ->
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().forEach { node ->
                val box = node.boundsInWindow
                folds.forEach { fold ->
                    assertTrue("$tag straddles the fold at ${fold.left}", box.right <= fold.left || box.left >= fold.right)
                }
            }
        }
    }

    @Test
    fun selectStaysOnThePage() {
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        tap("fst.player.select")
        waitForTag("fst.nav.tab.statistics")
        waitForTag("fst.player.overview")
        assertNothingStraddles("fst.player.identity", "fst.player.overview", "fst.player.instrument.Solo_Guitar", "fst.player.instrument.Solo_Bass")
        // Operator 7.12: no page-header Deselect (the drawer owns it, like the web sidebar).
        waitForTag("fst.player")
    }

    @Test
    fun switchIsConfirmedAndStaysOnThePage() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_B, "Other"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        waitForTag("fst.player.select")
        rule.onNodeWithText("Switch to This Profile").assertIsDisplayed()
        tap("fst.player.select")
        tap("fst.player.switch-confirm.ok")
        waitForTag("fst.nav.tab.statistics")
        waitForTag("fst.player")
    }

    @Test
    fun instrumentTileFiltersSongs() {
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        scrollTo("fst.player.tile.Solo_Bass.songs-played")
        assertNothingStraddles("fst.player.instrument.Solo_Bass", "fst.player.tile.Solo_Bass.songs-played")
        tap("fst.player.tile.Solo_Bass.songs-played")
        waitForTag("fst.songs.list")
        waitForTag("fst.songs.row.s-alpha")
        waitGone("fst.songs.row.s-beta")
    }

    @Test
    fun topSongsAndQuickLinks() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        waitForTag("fst.player.overview")
        scrollTo("fst.player.top-songs")
        scrollTo("fst.player.top-song.Solo_Guitar.s-alpha")
        assertNothingStraddles("fst.player.top-songs", "fst.player.top-songs.Solo_Guitar", "fst.player.top-song.Solo_Guitar.s-alpha")
        tap("fst.player.top-song.Solo_Guitar.s-alpha")
        waitForTag("fst.song-detail.list")
    }

    @Test
    fun historySortSheet() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerHistoryRoute("s-alpha", "Solo_Guitar"), stillBackground = true))
        waitForTag("fst.history.rows")
        tap("fst.history.sort.open")
        tap("fst.history.sort.mode.date")
        tap("fst.history.sort.direction.ascending")
        tap("fst.history.sort.reset")
        rule.onNodeWithText("Sort Scores").assertIsDisplayed()
    }
}
