package com.festivalscoretracker.android.ui.songs

import androidx.compose.ui.semantics.getOrNull
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assert
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Songs Quick Links, profile sort modes, invalid-score fallback and Shop pulses on Robolectric. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
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

    private fun launch(debug: DebugLaunch, prefs: InMemoryPreferences = InMemoryPreferences(), transport: HttpTransport = this.transport) {
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
        // 20 s: the full Robolectric suite runs these journeys under heavy load (seen flaking at 10 s).
        try {
            rule.waitUntil(20_000) {
                settle(100)
                rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()
            }
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $tag; present: ${presentTags()}", timeout)
        }
    }

    /** The `fst.` test tags on screen, so a CI-only timeout names what was showing instead. */
    private fun presentTags(): List<String> =
        rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.TestTag), useUnmergedTree = true)
            .fetchSemanticsNodes()
            .map { it.config[SemanticsProperties.TestTag] }
            .filter { it.startsWith("fst.") }
            .distinct()
            .take(60)

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun exists(tag: String, unmerged: Boolean = false) = rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun durationSortOpensQuickLinksSheetOnPhone() {
        launch(DebugLaunch(stillBackground = true), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Duration"))
        waitForTag("fst.songs.section.duration.1to2")
        assertTrue(exists("fst.songs.section.duration.4to5"))
        assertTrue(!exists("fst.songs.section-index"))
        // The toolbar registers Quick Links a frame after the sections exist (full-suite flake).
        waitForTag("fst.quick-links.open")
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.sheet")
        // The sheet's list is lazy: bring the bucket into composition before waiting for it.
        waitForTag("fst.quick-links.list")
        rule.onNodeWithTag("fst.quick-links.list").performScrollToNode(hasTestTag("fst.quick-links.item.duration:4to5"))
        waitForTag("fst.quick-links.item.duration:4to5")
        click("fst.quick-links.item.duration:4to5")
        waitGone("fst.quick-links.sheet")
    }

    @Test
    fun quickLinksAppearAfterSwitchingToDurationSortOnPhone() {
        launch(DebugLaunch(stillBackground = true))
        waitForTag("fst.songs.row.s-alpha")
        click("fst.songs.sort.open")
        settle()
        click("fst.songs.sort.duration")
        click("fst.songs.sort.done")
        waitForTag("fst.songs.section.duration.1to2")
        waitForTag("fst.quick-links.open")
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
        rule.onNodeWithTag("fst.songs.sort.form").performScrollToNode(hasTestTag("fst.songs.sort.priority.0"))
        rule.onNodeWithTag("fst.songs.sort.priority.0").performCustomAccessibilityActionWithLabel("Move down")
        click("fst.songs.sort.done")
        waitForTag("fst.songs.max-score.s-alpha", unmerged = true)
        waitForTag("fst.songs.section.maxdistance.100")

        // Clearing the chart filter drops the single-chart sort back to Title.
        click("fst.songs.filter.open")
        settle()
        // The selected instrument (compact selector centre) toggles off.
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.instrument.preview"))
        click("fst.songs.filter.instrument.preview")
        click("fst.songs.filter.done")
        waitForTag("fst.songs.section-index")
    }

    @Test
    fun overThresholdFilterShowsRawInvalidScoresWithAWarning() {
        launch(DebugLaunch(profile = player, stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.songs.row.s-beta")
        click("fst.songs.filter.open")
        settle()
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.score.chart.Solo_Guitar"))
        click("fst.songs.filter.score.chart.Solo_Guitar")
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
    fun songDetailSpotlightUsesTheNextValidScore() {
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.song-detail.list")
        assertEquals(1, rule.onAllNodesWithTag("fst.song-detail.shop-breathe.LeavingTomorrow", useUnmergedTree = true).fetchSemanticsNodes().size)
    }

    @Test
    fun songDetailBandPreviewsComeLastAndOpenTheFullBoard() {
        BandFixtures.install(transport)
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        // Web: a ten-row preview per band size after the instrument cards; Quads is empty.
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-empty.Band_Quad"))
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-row.Band_Duets.9"))
        assertFalse(exists("fst.song-detail.band-row.Band_Duets.10"))
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").all { "top=10&offset=0" in it.url && "accountId" !in it.url })
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-view-all.Band_Duets"))
        click("fst.song-detail.band-view-all.Band_Duets")
        waitForTag("fst.song-band-leaderboard.screen")
        waitForTag("fst.song-band-leaderboard.row.band-1:1", unmerged = true)
    }

    @Test
    fun songDetailBandPreviewsSpotlightTheSelectedPlayersBand() {
        BandFixtures.install(transport)
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-selected.Band_Duets"))
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").all { "accountId=${Fixtures.ACCOUNT_A}" in it.url })
        // Trios ranks the player's band 2nd: highlighted in place, not appended.
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-row.Band_Trios.1"))
        assertFalse(exists("fst.song-detail.band-selected.Band_Trios"))
        // TalkBack names the highlighted band (issue #172); other rows read plainly. One Button stop each, opening Band Detail.
        assertTrue(description("fst.song-detail.band-row.Band_Trios.1").startsWith("Your band, Rank 2, "))
        assertTrue(description("fst.song-detail.band-row.Band_Trios.0").startsWith("Rank 1, "))
        rule.onNodeWithTag("fst.song-detail.band-row.Band_Trios.1")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher("opens Band Detail") { it.config.getOrNull(SemanticsActions.OnClick)?.label == "Open band" })
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-selected.Band_Duets"))
        assertTrue(description("fst.song-detail.band-selected.Band_Duets").startsWith("Your band, Rank 12, "))
        // Leaderboard-row R7 (issue #307): the appended row jumps to the band's place on the
        // full board, like the solo spotlight row; in-place rows still open the band.
        fun label(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick)?.label
        assertEquals("Jump to your band's position", label("fst.song-detail.band-selected.Band_Duets"))
        assertEquals("Open band", label("fst.song-detail.band-row.Band_Trios.1"))
        click("fst.song-detail.band-selected.Band_Duets")
        waitForTag("fst.song-band-leaderboard.screen")
        waitForTag("fst.song-band-leaderboard.row.band-12:12", unmerged = true)
        waitForTag("fst.song-band-leaderboard.spotlight-footer", unmerged = true)
        assertFalse(exists("fst.band.screen"))
    }

    private fun description(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    @Test
    fun songDetailBandPreviewRetryShowsALabelledSpinnerThenRows() {
        BandFixtures.install(transport)
        var fail = true
        val gate = CompletableDeferred<Unit>()
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                if ("/bands/Band_Trios" in request.url) {
                    if (fail) return HttpResult(500, ByteArray(0))
                    gate.await()
                }
                return transport.send(request)
            }
        }
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport = gated)
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-retry.Band_Trios"))
        fail = false
        click("fst.song-detail.band-retry.Band_Trios")
        // Loading: a labelled spinner in the section (M3 progress indicators name what loads).
        waitForTag("fst.song-detail.band-loading.Band_Trios")
        assertEquals("Loading Trios scores", description("fst.song-detail.band-loading.Band_Trios"))
        gate.complete(Unit)
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-row.Band_Trios.0"))
        assertFalse(exists("fst.song-detail.band-retry.Band_Trios"))
        assertTrue(exists("fst.song-detail.band-view-all.Band_Trios"))
    }

    @Test
    fun songDetailBandPreviewFailureRetries() {
        transport.onRaw("/api/leaderboard/s-alpha/bands/Band_Trios") { com.festivalscoretracker.android.data.HttpResult(500, ByteArray(0)) }
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-preview.Band_Trios"))
        assertTrue(rule.onAllNodes(hasText("Trios scores unavailable", substring = true) and hasAnyAncestor(hasTestTag("fst.song-detail.band-preview.Band_Trios")), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun songDetailQuickLinksJumpToEverySection() {
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        waitForTag("fst.quick-links.open")
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.sheet")
        listOf("intensity", "instrument-Solo_Guitar", "band-Band_Duets", "band-Band_Quad").forEach { waitForTag("fst.quick-links.item.$it") }
        assertFalse(exists("fst.quick-links.item.score-history"))
        click("fst.quick-links.item.band-Band_Quad")
        waitGone("fst.quick-links.sheet")
        waitForTag("fst.song-detail.band-preview.Band_Quad")
        assertFalse(exists("fst.song-detail.header"))
    }

    @Test
    fun songDetailInstrumentFocusScrollsToTheChart() {
        launch(DebugLaunch(songQuery = "s-alpha", songInstrument = "Solo_Vocals", stillBackground = true))
        waitForTag("fst.song-detail.list")
        waitForTag("fst.song-detail.preview.Solo_Vocals")
        rule.waitUntil(10_000) { settle(100); !exists("fst.song-detail.header") }
    }

    @Test
    fun songDetailIgnoresAHiddenInstrumentFocus() {
        launch(DebugLaunch(songQuery = "s-alpha", songInstrument = "bogus", stillBackground = true))
        waitForTag("fst.song-detail.intensity.Solo_Guitar", unmerged = true)
        settle()
        assertTrue(exists("fst.song-detail.header"))
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

    @Test
    fun songLeaderboardHeaderSwitchesInstrument() {
        launch(DebugLaunch(route = SongLeaderboardRoute("s-alpha", "Solo_Guitar", 1), stillBackground = true))
        waitForTag("fst.song-leaderboard.list")
        waitForTag("fst.song-leaderboard.instrument")
        click("fst.song-leaderboard.instrument")
        waitForTag("fst.song-leaderboard.instrument.Solo_Bass")
        click("fst.song-leaderboard.instrument.Solo_Bass")
        rule.waitUntil(10_000) { settle(100); transport.sent("/api/leaderboard/s-alpha/Solo_Bass").isNotEmpty() }
    }

    @Test
    fun songDetailHeaderScrollsAwayAndTheBarTakesTheTitle() {
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.header")
        waitForTag("fst.song-detail.intensity.Solo_Guitar", unmerged = true)
        waitForTag("fst.song-detail.paths.open")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.band-preview.Band_Quad"))
        settle()
        assertFalse(exists("fst.song-detail.header"))
        assertEquals(1, rule.onAllNodes(hasText("Alpha Tune") and hasAnyAncestor(hasTestTag("fst.nav.top-bar"))).fetchSemanticsNodes().size)
    }

    /**
     * Operator 6.12 (production Winterfest Wish, Lead): with Filter Invalid Scores the
     * preview is the service's leeway board (few valid rows, raw Epic ranks like the web),
     * the selected player's next valid score follows it, and over-threshold history rows
     * are dropped from the song's score history.
     */
    @Test
    fun filterInvalidScoresUsesTheLeewayBoardAndDropsInvalidHistory() {
        transport.on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            if (request.url.contains("leeway=")) {
                """{"songId":"s-alpha","instrument":"Solo_Guitar","count":2,"totalEntries":12438,"localEntries":2,"entries":[
                  {"accountId":"${Fixtures.ACCOUNT_B}","displayName":"Valid One","score":89000,"rank":55942,"localRank":1,"accuracy":980000,"isFullCombo":false},
                  {"accountId":"0123456789abcdef0123456789abcdee","displayName":"Valid Two","score":88000,"rank":65259,"localRank":2,"accuracy":990000,"isFullCombo":false}]}"""
            } else {
                Fixtures.leaderboard("s-alpha")
            }
        }
        transport.on("/api/player/${Fixtures.ACCOUNT_A}/history") {
            """{"accountId":"${Fixtures.ACCOUNT_A}","count":2,"history":[
              {"songId":"s-alpha","instrument":"Solo_Guitar","newScore":95198,"newRank":42,"accuracy":987000,"isFullCombo":true,"changedAt":"2024-08-02T00:00:00Z"},
              {"songId":"s-alpha","instrument":"Solo_Guitar","newScore":80000,"newRank":60,"accuracy":950000,"isFullCombo":false,"changedAt":"2024-07-02T00:00:00Z"}]}"""
        }
        launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), prefs(booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES) to true))
        waitForTag("fst.song-detail.list")
        assertTrue(transport.sent("/api/leaderboard/s-alpha/Solo_Guitar").all { it.url.contains("leeway=") })
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        waitForTag("fst.song-detail.preview-row.Solo_Guitar.${Fixtures.ACCOUNT_B}")
        assertEquals(1, rule.onAllNodesWithText("#55,942", useUnmergedTree = true).fetchSemanticsNodes().size)
        // History: 95,198 exceeds 90,000 × 1.01, so only the 80,000 row is listed.
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.history"))
        waitForTag("fst.song-detail.history.top.0")
        assertEquals(0, rule.onAllNodesWithTag("fst.song-detail.history.top.1").fetchSemanticsNodes().size)
        assertTrue(rule.onNodeWithTag("fst.song-detail.history.top.0").fetchSemanticsNode().config.toString().contains("80,000"))
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertExistsWithText(fragment: String) {
        val config = fetchSemanticsNode().config.toString()
        assertTrue(config, config.contains(fragment))
    }
}
