package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.bands.BandFixtures
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Songs Quick Links, profile sort modes, invalid-score fallback and Shop pulses on Robolectric. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsParityUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    /** Alpha's Lead score is invalid at the default +1% leeway (minimum 2%) with an 80,000 fallback. */
    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":3,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z",
           "ml":2.0,"vs":[{"sc":80000,"acc":950,"fc":false,"st":5,"ml":0.5,"rt":[{"l":0,"r":60}]}]},
          {"si":"s-beta","ins":"01","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000,"lp":"2026-09-20T12:00:00Z"},
          {"si":"s-beta","ins":"02","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000,"lp":"2026-09-25T12:00:00Z"}
        ]}
    """.trimIndent()

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { profileJson }
    }

    private fun prefs(vararg pairs: Preferences.Pair<*>) = InMemoryPreferences(mutablePreferencesOf(*pairs))

    private fun launch(debug: DebugLaunch, prefs: InMemoryPreferences = InMemoryPreferences()) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String, unmerged: Boolean = false) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun exists(tag: String, unmerged: Boolean = false) = rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun durationSortOpensQuickLinksSheetOnPhone() {
        launch(DebugLaunch(stillBackground = true), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Duration"))
        waitForTag("fst.songs.section.duration.1to2")
        assertTrue(exists("fst.songs.section.duration.4to5"))
        assertTrue(!exists("fst.songs.section-index"))
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.sheet")
        waitForTag("fst.quick-links.item.duration:4to5")
        click("fst.quick-links.item.duration:4to5")
        waitGone("fst.quick-links.sheet")
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun expandedTwoPaneUsesQuickLinksMenu() {
        launch(DebugLaunch(stillBackground = true), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop"))
        waitForTag("fst.songs.shop-section.leaving-tomorrow")
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.menu")
        click("fst.quick-links.item.shop:not-in-shop")
        waitGone("fst.quick-links.menu")
    }

    @Test
    fun playerSortModesGroupRowsAndInvalidScoreAlertOpensSettings() {
        launch(DebugLaunch(profile = player, stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.songs.invalid-score.s-alpha")
        click("fst.songs.sort.open")
        settle()
        assertTrue(exists("fst.songs.sort.lastplayed"))
        assertTrue(!exists("fst.songs.sort.chart-mode"))
        click("fst.songs.sort.hasfc")
        click("fst.songs.sort.done")
        waitForTag("fst.songs.section.hasfc.no-fc")
        // The fallback is a non-FC score, so Alpha is no longer in the FC bucket.
        assertTrue(!exists("fst.songs.section.hasfc.fc"))

        click("fst.songs.invalid-score.s-alpha")
        waitForTag("fst.songs.invalid-score.alert")
        rule.onNodeWithTag("fst.songs.invalid-score.message").assertExistsWithText("The Lead chip reflects the next valid score.")
        click("fst.songs.invalid-score.ok")
        waitGone("fst.songs.invalid-score.alert")
        click("fst.songs.invalid-score.s-alpha")
        waitForTag("fst.songs.invalid-score.settings")
        click("fst.songs.invalid-score.settings")
        waitForTag("fst.settings.list")
    }

    @Test
    fun singleChartSortsShowMaxScoreAndReorderPriority() {
        launch(
            DebugLaunch(profile = player, stillBackground = true),
            prefs(
                booleanPreferencesKey(SettingsRegistry.SHOW_INSTRUMENT_ICONS) to false,
                booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true,
                stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar"}""",
            ),
        )
        waitForTag("fst.songs.row.s-alpha")
        click("fst.songs.sort.open")
        settle()
        rule.onNodeWithTag("fst.songs.sort.form").performScrollToNode(hasTestTag("fst.songs.sort.maxdistance"))
        click("fst.songs.sort.maxdistance")
        rule.onNodeWithTag("fst.songs.sort.form").performScrollToNode(hasTestTag("fst.songs.sort.priority.0.down"))
        click("fst.songs.sort.priority.0.down")
        click("fst.songs.sort.done")
        waitForTag("fst.songs.max-score.s-alpha", unmerged = true)
        waitForTag("fst.songs.section.maxdistance.100")

        // Clearing the chart filter drops the single-chart sort back to Title.
        click("fst.songs.filter.open")
        settle()
        click("fst.songs.filter.instrument.all")
        click("fst.songs.filter.done")
        waitForTag("fst.songs.section-index")
    }

    @Test
    fun overThresholdFilterShowsRawInvalidScoresWithAWarning() {
        launch(DebugLaunch(profile = player, stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.songs.row.s-beta")
        click("fst.songs.filter.open")
        settle()
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.score.instrument.Solo_Guitar.OverThreshold"))
        click("fst.songs.filter.score.instrument.Solo_Guitar.OverThreshold")
        click("fst.songs.filter.done")
        waitGone("fst.songs.row.s-beta")
        waitForTag("fst.songs.invalid-score.s-alpha")
        click("fst.songs.invalid-score.s-alpha")
        waitForTag("fst.songs.invalid-score.alert")
        rule.onNodeWithTag("fst.songs.invalid-score.message").assertExistsWithText("exceeds the CHOpt maximum")
    }

    @Test
    fun songDetailShopButtonBreathesByOffer() {
        launch(DebugLaunch(songQuery = "s-beta", stillBackground = true))
        waitForTag("fst.song-detail.shop-breathe.New", unmerged = true)
    }

    @Test
    fun songDetailFallbackSummaryMarksTheNextValidScore() {
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.your-score.Solo_Guitar"))
        waitForTag("fst.song-detail.your-score.Solo_Guitar", unmerged = true)
        rule.onNodeWithText("Your score: 80,000", substring = true, useUnmergedTree = true).assertExists()
        rule.onNodeWithText("next valid score", substring = true, useUnmergedTree = true).assertExists()
        assertEquals(1, rule.onAllNodesWithTag("fst.song-detail.shop-breathe.LeavingTomorrow", useUnmergedTree = true).fetchSemanticsNodes().size)
    }

    @Test
    fun songDetailBandLinksOpenTheSongBandLeaderboard() {
        BandFixtures.install(transport)
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band.Band_Duets"))
        click("fst.song-detail.band.Band_Duets")
        waitForTag("fst.song-band-leaderboard.screen")
        waitForTag("fst.song-band-leaderboard.row.band-1:1", unmerged = true)
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").isNotEmpty())
    }

    @Test
    fun songLeaderboardReadsWithLeewayAndSpotlightsTheNextValidScore() {
        launch(
            DebugLaunch(profile = player, route = SongLeaderboardRoute("s-alpha", "Solo_Guitar", 3), stillBackground = true),
            prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true),
        )
        waitForTag("fst.song-leaderboard.list")
        rule.waitUntil(10_000) { settle(100); transport.sent("/api/leaderboard/s-alpha/Solo_Guitar").isNotEmpty() }
        assertTrue(transport.sent("/api/leaderboard/s-alpha/Solo_Guitar").all { it.url.contains("leeway=1.0") })
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertExistsWithText(fragment: String) {
        val config = fetchSemanticsNode().config.toString()
        assertTrue(config, config.contains(fragment))
    }
}
