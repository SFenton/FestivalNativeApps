package com.festivalscoretracker.android.rankings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.profile.PlayerRankHistorySnapshot
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.rankings.RankHistoryResponse
import com.festivalscoretracker.android.core.rankings.RankHistorySnapshot
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.leaderboards.ColumnProbe
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardsScreen
import com.festivalscoretracker.android.ui.leaderboards.LocalColumnProbe
import com.festivalscoretracker.android.ui.profile.RankHistoryChart
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every rank-history list (Leaderboards, Profile, Band) draws its rows' rank and value in one
 * right-aligned column each, measured over the whole chart, so the bold newest row and the
 * tapped bar's detail line up with the others at default and 200% text (issue #594,
 * `leaderboard-row` R1).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RankHistoryColumnsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val bounds = mutableMapOf<String, Rect>()
    private val probe = ColumnProbe { key, rect -> bounds[key] = rect }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Ranks and values of every digit count, newest last, so no two neighbouring rows are the same width. */
    private val days = listOf(12_345 to 98_765_432L, 98 to 1_234_567L, 1_234 to 23_456L, 7 to 987_654_321L, 45 to 5_000L, 3 to 12_345_678L)

    /**
     * Asserts the rank and value columns of [keys] share their left and right edges.
     *
     * @param keys Probe keys (`<surface>.<row>`).
     */
    private fun assertColumnsAligned(keys: List<String>) {
        assertTrue("rows ${bounds.keys}", keys.size >= 2)
        listOf("rank", "value").forEach { column ->
            val first = bound("history.$column.${keys.first()}")
            keys.drop(1).forEach { key ->
                val other = bound("history.$column.$key")
                assertEquals("$column right, $key", first.right, other.right, 1f)
                assertEquals("$column left, $key", first.left, other.left, 1f)
            }
        }
    }

    private fun bound(key: String): Rect = bounds[key] ?: error("no $key in ${bounds.keys}")

    /** Robolectric xxhdpi: px per dp. */
    private val density = 3f

    /**
     * Asserts every row in [keys] is at least the shared 48 dp row baseline (`leaderboard-row` R2).
     *
     * @param keys Probe keys.
     */
    private fun assertRowsAtLeast48(keys: List<String>) {
        keys.forEach { key -> assertTrue("row height $key: ${bound("history.row.$key").height / density} dp", bound("history.row.$key").height >= 48f * density - 0.5f) }
    }

    /**
     * Asserts [keys] use the lines layout (value under rank) and each column keeps its one
     * measured width, right-aligned, rather than spanning the row (`leaderboard-row` R11).
     *
     * @param keys Probe keys.
     */
    private fun assertLinesKeepMeasuredColumns(keys: List<String>) {
        assertColumnsAligned(keys)
        assertRowsAtLeast48(keys)
        keys.forEach { key ->
            val rank = bound("history.rank.$key")
            val value = bound("history.value.$key")
            val row = bound("history.row.$key")
            assertTrue("$key lines: rank $rank above value $value", value.top >= rank.bottom - 1f)
            assertEquals("$key: rank and value share the right edge", rank.right, value.right, 1f)
            assertTrue("$key: rank keeps its measured width ${rank.width} < row ${row.width}", rank.width < row.width - 1f)
            assertTrue("$key: value keeps its measured width ${value.width} < row ${row.width}", value.width < row.width - 1f)
            // Cells spanning the row would share one width; measured columns differ.
            assertTrue("$key: rank ${rank.width} and value ${value.width} keep their own widths", kotlin.math.abs(rank.width - value.width) > 1f)
        }
    }

    // region Leaderboards

    private fun leaderboards(days: List<Pair<Int, Long>> = this.days) {
        val fake = FakeReads()
        val today = LocalDate.now()
        val history = days.mapIndexed { i, (rank, score) ->
            RankHistorySnapshot(today.minusDays((days.size - 1 - i).toLong()).toString(), totalScoreRank = rank, totalScore = score)
        }
        val reads = fake.reads.copy(rankHistory = { instrument, accountId -> RankHistoryResponse(instrument.wireId, accountId, history) })
        val settings = MutableStateFlow<AppSettings?>(
            AppSettings(selectedPlayer = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), visibleInstruments = setOf(Instrument.Lead)),
        )
        val rankBy = MutableStateFlow(RankingMetric.TotalScore)
        val viewModel = LeaderboardsViewModel(reads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        rule.setContent { CompositionLocalProvider(LocalColumnProbe provides probe) { LeaderboardsScreen(viewModel, isRoot = true) } }
        waitForTag("fst.leaderboards.rank-history.row.4")
        rule.onNodeWithTag("fst.leaderboards").performScrollToNode(hasTestTag("fst.leaderboards.rank-history.plot"))
        settle()
        rule.onNodeWithTag("fst.leaderboards.rank-history.plot").performTouchInput { click(centerLeft.copy(x = 4f)) }
        waitForTag("fst.leaderboards.rank-history.detail")
        rule.onNodeWithTag("fst.leaderboards").performScrollToNode(hasTestTag("fst.leaderboards.rank-history.row.4"))
        settle()
    }

    private fun assertLeaderboardsAligned() {
        val keys = (0..4).map { "leaderboards.row.$it" } + "leaderboards.detail.row"
        assertColumnsAligned(keys)
        assertRowsAtLeast48(keys)
    }

    @Test
    fun leaderboardsRankHistoryRowsAndDetailShareColumns() {
        leaderboards()
        assertLeaderboardsAligned()
    }

    @Test
    fun leaderboardsRankHistoryRowsShareColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        leaderboards()
        assertLeaderboardsAligned()
    }

    /** Eight-digit ranks and twelve-digit values: at 200% on a 320 dp phone, rank and value no longer fit on one line. */
    private val wideDays = listOf(12_345_678 to 987_654_321_012L, 23_456_789 to 876_543_210_987L, 34_567_890 to 765_432_109_876L, 45_678_901 to 654_321_098_765L, 56_789_012 to 543_210_987_654L, 67_890_123 to 432_109_876_543L)

    @Test
    @Config(qualifiers = "w320dp-h891dp-xxhdpi")
    fun leaderboardsRankHistoryLinesKeepMeasuredColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        leaderboards(wideDays)
        assertLinesKeepMeasuredColumns((0..4).map { "leaderboards.row.$it" } + "leaderboards.detail.row")
    }

    // endregion

    // region Profile

    private fun profile(): List<String> {
        val snapshots = days.mapIndexed { i, (rank, score) ->
            PlayerRankHistorySnapshot(snapshotDate = "2026-09-%02d".format(20 + i), totalScoreRank = rank, totalScore = score, rankedAccountCount = 20_000)
        }
        val model = RankHistoryChartModel.build(snapshots)!!
        rule.setContent { CompositionLocalProvider(LocalColumnProbe provides probe) { Box(Modifier.width(380.dp)) { RankHistoryChart(model) } } }
        settle()
        return snapshots.takeLast(5).map { "player.${it.snapshotDate}" }
    }

    @Test
    fun profileRankHistoryRowsShareColumns() {
        val keys = profile()
        assertColumnsAligned(keys)
        assertRowsAtLeast48(keys)
    }

    @Test
    fun profileRankHistoryRowsShareColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        val keys = profile()
        assertColumnsAligned(keys)
        assertRowsAtLeast48(keys)
    }

    // endregion

    // region Band

    private fun band(rankBase: Int = 0) {
        val transport = BandFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        ).apply {
            on("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/history", headers = mapOf("X-FST-Publication-Id" to "7")) { BandFixtures.history(rankBase = rankBase) }
        }
        val debug = DebugLaunch(route = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { CompositionLocalProvider(LocalColumnProbe provides probe) { FestivalApp(container, debug) } }
        waitForTag("fst.band.history-row.2024-01-01")
        settle()
    }

    /** The fixture's three ranked snapshots, newest (bold) first. */
    private val bandRows = listOf("band.2024-01-03", "band.2024-01-02", "band.2024-01-01")

    @Test
    fun bandRankHistoryRowsShareColumns() {
        band()
        assertColumnsAligned(bandRows)
        assertRowsAtLeast48(bandRows)
    }

    @Test
    fun bandRankHistoryRowsShareColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        band()
        assertColumnsAligned(bandRows)
        assertRowsAtLeast48(bandRows)
    }

    @Test
    @Config(qualifiers = "w320dp-h891dp-xxhdpi")
    fun bandRankHistoryLinesKeepMeasuredColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        band(rankBase = 123_456_780)
        assertLinesKeepMeasuredColumns(bandRows)
    }

    // endregion
}
