package com.festivalscoretracker.android.bands

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.bands.BAND_RANK_MIN_WIDTH
import com.festivalscoretracker.android.ui.leaderboards.ColumnProbe
import com.festivalscoretracker.android.ui.leaderboards.LocalColumnProbe
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
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
 * The full song band board shares one column plan between its member cards and the pinned
 * selected band (`leaderboard-row` R1, R5; issue #172): with the band off-page at #9,968, the
 * footer's rank and name columns sit exactly over the page rows' at default and 200% text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongBandBoardColumnsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val bounds = mutableMapOf<String, Rect>()

    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    ).apply {
        on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, PINNED.takeIf { "accountId=${BandFixtures.PLAYER}" in request.url })
        }
    }

    private fun launch() {
        val debug = DebugLaunch(
            route = DebugLaunch.parseRoute("songBandLeaderboard:s-alpha:Band_Duets"),
            profile = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player"),
            stillBackground = true,
        )
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        val probe = ColumnProbe { key, rect -> bounds[key] = rect }
        rule.setContent { CompositionLocalProvider(LocalColumnProbe provides probe) { FestivalApp(container, debug) } }
        waitForTag("fst.song-band-leaderboard.spotlight-footer")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        rule.onNodeWithTag("fst.song-band-leaderboard.list").performScrollToNode(hasTestTag("fst.song-band-leaderboard.row.band-1:1"))
        settle()
    }

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

    private fun bound(key: String): Rect = bounds[key] ?: error("no $key in ${bounds.keys}")

    /** The pinned row's rank and name columns coincide with page rows 1 and 2's; the rank column fits "#9,968". */
    private fun assertFooterSharesTheBoardColumns() {
        val density = rule.activity.resources.displayMetrics.density
        val footerRank = bound("score.rank.$PINNED")
        val footerName = bound("score.name.$PINNED")
        listOf(1, 2).forEach { rank ->
            val rowRank = bound("band.rank.$rank")
            val rowName = bound("band.name.$rank")
            assertEquals("rank left, row $rank", rowRank.left, footerRank.left, 1f)
            assertEquals("rank right, row $rank", rowRank.right, footerRank.right, 1f)
            assertEquals("name left, row $rank", rowName.left, footerName.left, 1f)
        }
        assertTrue("rank column ${footerRank.width / density} dp fits #9,968", footerRank.width / density > BAND_RANK_MIN_WIDTH.value)
    }

    @Test
    fun offPagePinnedBandSharesTheRowsColumns() {
        launch()
        assertFooterSharesTheBoardColumns()
    }

    @Test
    fun offPagePinnedBandSharesTheRowsColumnsAt200Percent() {
        RuntimeEnvironment.setFontScale(2f)
        launch()
        assertFooterSharesTheBoardColumns()
    }

    private companion object {
        /** The selected player's band rank: far off page 1 of a 60-band board. */
        const val PINNED = 9_968
    }
}
