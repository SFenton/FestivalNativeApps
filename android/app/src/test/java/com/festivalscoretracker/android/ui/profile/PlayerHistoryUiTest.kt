package com.festivalscoretracker.android.ui.profile

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.presentation.profile.HistoryPhase
import com.festivalscoretracker.android.presentation.profile.PlayerHistoryUiState
import com.festivalscoretracker.android.presentation.profile.PlayerHistoryViewModel
import com.festivalscoretracker.android.presentation.profile.ScoreHistoryRow
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.leaderboards.HingeSplit
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.runner.RunWith
import org.junit.Test
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf

// region Harness

/**
 * Launches the whole shell on the Score History route against synthetic fixtures.
 *
 * @property rule Compose rule of the owning test.
 */
internal class PlayerHistoryHarness(private val rule: androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, ComponentActivity>) {
    /** Fixture transport (score history for account A: two Lead rows and one Bass row on `s-alpha`). */
    val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    /**
     * Compose the app on `/songs/s-alpha/<instrument>/history`.
     *
     * @param instrument Wire chart.
     * @param player Selected player, or null for none.
     * @param fontScale Font scale applied to the whole composition (sheets included).
     */
    fun launch(instrument: String = "Solo_Guitar", player: SelectedPlayer? = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), fontScale: Float = 1f) {
        val debug = DebugLaunch(profile = player, route = PlayerHistoryRoute("s-alpha", instrument), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) { FestivalApp(container, debug) }
        }
        settle()
    }

    /** Advance the paused main looper and let Compose settle. */
    fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    /**
     * Wait until a node with [tag] exists.
     *
     * @param tag Test tag.
     */
    fun waitForTag(tag: String) = rule.waitUntil(10_000) {
        settle()
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    /**
     * Wait until [text] is shown.
     *
     * @param text Exact text.
     */
    fun waitForText(text: String) = rule.waitUntil(10_000) {
        settle()
        rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
    }

    /**
     * Click the node tagged [tag].
     *
     * @param tag Test tag.
     */
    fun tap(tag: String) {
        waitForTag(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    /** The rows' TalkBack descriptions, in list order. */
    fun rowAnnouncements(): List<String> =
        rule.onAllNodes(hasContentDescription(", score ", substring = true)).fetchSemanticsNodes()
            .sortedBy { it.boundsInRoot.top }
            .mapNotNull { it.config.getOrNull(SemanticsProperties.ContentDescription)?.single() }

    /** Every request was keyless and sent no selected-profile header. */
    fun assertSafeRequests() = transport.requests.forEach { request ->
        RequestGate.validateKeyless(request)
        assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
    }
}

// endregion

// region Phone portrait

/** Every reachable Score History state on a compact portrait phone. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PlayerHistoryUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val app = PlayerHistoryHarness(rule)

    @Test
    fun loadedRowsAnnounceAndThePersonalBestFollowsTheSort() {
        app.launch()
        app.waitForTag("fst.history.chart")
        rule.onNodeWithText("Alpha Tune · Lead").assertIsDisplayed()
        rule.onNodeWithText("Score Over Time").assertIsDisplayed()
        // The chart is one TalkBack stop: its summary, not each axis label.
        val chart = rule.onNodeWithTag("fst.history.chart").fetchSemanticsNode()
        assertTrue(chart.children.isEmpty())
        assertTrue(chart.config[SemanticsProperties.ContentDescription].single().startsWith("Score over time. "))
        // Default: Score, descending; the best score leads and carries "personal best".
        rule.onNodeWithTag("fst.history.sort.open").assertContentDescriptionEquals("Sort by Score, descending")
        val initial = app.rowAnnouncements()
        assertEquals(2, initial.size)
        assertTrue(initial[0], initial[0].contains("score 850,000") && initial[0].contains("full combo") && initial[0].endsWith("personal best"))
        assertTrue(initial[1], initial[1].contains("score 700,000") && initial[1].contains("4 stars") && !initial[1].contains("personal best"))

        app.tap("fst.history.sort.open")
        app.waitForTag("fst.history.sort.mode.date")
        // Each choice group is introduced by a heading (M3: label radio groups).
        assertEquals(1, rule.onAllNodes(isHeading() and hasText("Sort By")).fetchSemanticsNodes().size)
        assertEquals(1, rule.onAllNodes(isHeading() and hasText("Sort Direction")).fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.history.sort.mode.score").assertIsSelected()
        rule.onNodeWithTag("fst.history.sort.direction.descending").assertIsSelected()
        app.tap("fst.history.sort.mode.date")
        app.tap("fst.history.sort.direction.ascending")
        rule.onNodeWithTag("fst.history.sort.mode.date").assertIsSelected()
        rule.onNodeWithTag("fst.history.sort.direction.ascending").assertIsSelected()
        rule.onNodeWithTag("fst.history.sort.open").assertContentDescriptionEquals("Sort by Date, ascending")
        // Oldest first now, and the personal-best highlight moved with its row.
        val byDate = app.rowAnnouncements()
        assertTrue(byDate[0], byDate[0].contains("score 700,000") && !byDate[0].contains("personal best"))
        assertTrue(byDate[1], byDate[1].contains("score 850,000") && byDate[1].endsWith("personal best"))

        app.tap("fst.history.sort.reset")
        rule.onNodeWithTag("fst.history.sort.open").assertContentDescriptionEquals("Sort by Score, descending")
        app.tap("fst.history.sort.close")
        rule.waitUntil(10_000) { app.settle(); rule.onAllNodesWithTag("fst.history.sort").fetchSemanticsNodes().isEmpty() }
        assertEquals(1, app.transport.sent("/api/player/${Fixtures.ACCOUNT_A}/history").size)
        app.assertSafeRequests()
    }

    @Test
    fun aSingleRowHasNoChart() {
        app.launch(instrument = "Solo_Bass")
        app.waitForTag("fst.history.rows")
        rule.onNodeWithText("Alpha Tune · Bass").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.history.chart").fetchSemanticsNodes().size)
        assertEquals(1, app.rowAnnouncements().size)
    }

    @Test
    fun aChartWithoutHistoryIsEmpty() {
        app.launch(instrument = "Solo_Drums")
        app.waitForText("No History Yet")
        rule.onNodeWithText("No score history for Drums on this song.").assertIsDisplayed()
        // Sorting only exists for loaded rows.
        assertEquals(0, rule.onAllNodesWithTag("fst.history.sort.open").fetchSemanticsNodes().size)
    }

    @Test
    fun withoutAPlayerTheDeepLinkRedirectsToSongs() {
        // Web parity (ProfileRoutePolicy): profile-only routes fall back to Songs.
        app.launch(player = null)
        app.waitForTag("fst.songs.row.s-alpha")
        assertEquals(0, rule.onAllNodesWithTag("fst.history").fetchSemanticsNodes().size)
        assertEquals(0, app.transport.requests.count { it.url.contains("/history") })
    }

    @Test
    fun syncingOffersRetry() {
        app.transport.on("/api/player/${Fixtures.ACCOUNT_A}/history", status = 202) { """{"accountId":"${Fixtures.ACCOUNT_A}","count":0,"history":[]}""" }
        app.launch()
        app.waitForText("Still Syncing")
        app.tap("fst.history.retry")
        app.waitForText("Still Syncing")
        assertEquals(2, app.transport.sent("/api/player/${Fixtures.ACCOUNT_A}/history").size)
    }

    @Test
    fun aFailedReadRetriesIntoRows() {
        app.transport.on("/api/player/${Fixtures.ACCOUNT_A}/history", status = 500) { "{}" }
        app.launch()
        app.waitForTag("fst.service-status.retry")
        rule.onNodeWithText("History unavailable").assertIsDisplayed()
        ProfileFixtures.register(app.transport)
        app.tap("fst.service-status.retry")
        app.waitForTag("fst.history.chart")
        assertEquals(2, app.rowAnnouncements().size)
    }
}

// endregion

// region Short landscape window at 2× text

/**
 * Landscape phone (411 dp tall) at font scale 2: the Sort Scores sheet opens fully and its
 * body scrolls, so the direction buttons stay reachable (issue #105).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class PlayerHistoryLandscapeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val app = PlayerHistoryHarness(rule)

    @Test
    fun sortSheetScrollsToTheDirectionAtLargeText() {
        app.launch(fontScale = 2f)
        app.waitForTag("fst.history.rows")
        app.tap("fst.history.sort.open")
        app.waitForTag("fst.history.sort.form")
        rule.onNodeWithTag("fst.history.sort.form").performScrollToNode(hasTestTag("fst.history.sort.direction.ascending"))
        app.settle()
        rule.onNodeWithTag("fst.history.sort.direction.ascending").assertIsDisplayed()
        app.tap("fst.history.sort.direction.ascending")
        rule.onNodeWithTag("fst.history.sort.direction.ascending").assertIsSelected()
        rule.onNodeWithTag("fst.history.sort.open").assertContentDescriptionEquals("Sort by Score, ascending")
        // The pinned header keeps Reset and Close on screen while the body scrolls.
        rule.onNodeWithTag("fst.history.sort.reset").assertIsDisplayed()
        rule.onNodeWithTag("fst.history.sort.close").assertIsDisplayed()
    }
}

// endregion

// region Page without a player

/**
 * The page itself when no player is selected (only reachable while the shell is redirecting
 * after a deselect): an explanatory message and no request.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PlayerHistoryNoPlayerUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun noSelectedPlayerExplainsAndMakesNoRequest() {
        val calls = mutableListOf<String>()
        val viewModel = PlayerHistoryViewModel(
            songId = "s-alpha",
            instrument = Instrument.Lead,
            read = { account, _, _ -> calls += account; error("no read without a player") },
            findSong = { id -> Fixtures.song(id, "Alpha Tune") },
            settings = MutableStateFlow(AppSettings(selectedPlayer = null)),
            backoff = ServiceRetryBackoff(),
        )
        rule.setContent { FestivalTheme { PlayerHistoryScreen(viewModel) } }
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.onAllNodesWithText("No Player Selected").fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithText("Select a player profile to see score history.").assertIsDisplayed()
        assertEquals(1, rule.onAllNodes(isHeading() and hasText("No Player Selected")).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("fst.history.sort.open").fetchSemanticsNodes().size)
        assertTrue(calls.isEmpty())
    }
}

// endregion

// region Hinge

/** A half-open book fold: the summary and the rows each keep to one side of the hinge. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h700dp-xxhdpi")
class PlayerHistoryHingeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val state = PlayerHistoryUiState(
        phase = HistoryPhase.Loaded,
        rows = listOf(
            ScoreHistoryRow(ScoreHistoryEntry(newScore = 120_000, accuracy = 99.0, stars = 6, changedAt = "2025-02-01T00:00:00Z"), true, "Feb 1, 2025"),
            ScoreHistoryRow(ScoreHistoryEntry(newScore = 100_000, accuracy = 95.0, stars = 5, changedAt = "2025-01-01T00:00:00Z"), false, "Jan 1, 2025"),
        ),
        songTitle = "Alpha",
    )

    @Test
    fun aSeparatingHingeSplitsTheSummaryFromTheRows() {
        rule.setContent {
            FestivalTheme {
                HistoryLoaded(Instrument.Lead, state, revealed = true, padding = PaddingValues(0.dp), hinge = HingeSplit(440.dp, 460.dp), modifier = Modifier.fillMaxSize())
            }
        }
        rule.waitForIdle()
        val summary = rule.onNodeWithTag("fst.history.summary").getBoundsInRoot()
        val rows = rule.onNodeWithTag("fst.history.rows").getBoundsInRoot()
        assertTrue("summary ends before the hinge: ${summary.right}", summary.right <= 440.dp)
        assertTrue("rows start after the hinge: ${rows.left}", rows.left >= 460.dp)
        rule.onNodeWithTag("fst.history.subtitle").assertIsDisplayed()
        rule.onNode(hasContentDescription("score 120,000", substring = true)).assertIsDisplayed()
    }

    @Test
    fun withoutAHingeOneCentredColumnHoldsEverything() {
        rule.setContent {
            FestivalTheme {
                HistoryLoaded(Instrument.Lead, state, revealed = true, padding = PaddingValues(0.dp), hinge = null, modifier = Modifier.fillMaxSize())
            }
        }
        rule.waitForIdle()
        assertTrue(rule.onAllNodesWithTag("fst.history.split").fetchSemanticsNodes().isEmpty())
        val rows = rule.onNodeWithTag("fst.history.rows").getBoundsInRoot()
        assertTrue("list capped at 840dp: ${rows.width}", rows.width <= 840.dp)
        rule.onNodeWithTag("fst.history.subtitle").assertIsDisplayed()
    }
}

// endregion