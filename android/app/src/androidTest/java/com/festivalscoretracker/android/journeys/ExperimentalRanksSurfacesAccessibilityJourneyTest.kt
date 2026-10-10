package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The other surfaces Settings → Enable Experimental Leaderboard Ranks gates (#541,
 * `experimental-ranks` R1/R4), read from the persisted setting with the Accessibility Test
 * Framework on every step:
 *
 * - **Player profile:** off, an instrument's stat grid has the Total Score Rank tile only and
 *   TalkBack reads no experimental rank; on, it adds Adjusted, Weighted, FC Rate and Max Score %
 *   rank tiles, each a labelled 48 dp button read after Total Score Rank in metric order, at
 *   1.0x and 2.0x text. Turning the setting off in place removes them.
 * - **Rivals:** the Leaderboard tab has no Rank By while off (and only Total Score lists are
 *   read); on, it is a labelled 48 dp control at 1.0x and 2.0x text whose menu lists every
 *   metric and loads the chosen one. The Song tab never shows it.
 * - **First Run:** the Leaderboards tour leaves out the Experimental Ranking Metrics slide while
 *   off and includes it, readable, while on.
 *
 * Fixtures only. Run with `device.py test
 * com.festivalscoretracker.android.journeys.ExperimentalRanksSurfacesAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`. `@DeviceCi`: both CI device checks run it.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ExperimentalRanksSurfacesAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val key = booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS)

    private fun preferences(experimentalRanks: Boolean) = MemoryPreferences(mutablePreferencesOf(key to experimentalRanks))

    // region Player profile

    @Test
    fun profileShowsOnlyTheTotalScoreRankTileWhileOff() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        launchProfile(preferences(false)) { scale }
        SCALES.forEach { s ->
            scale = s
            showTile(TOTAL_TILE, TILES.getValue(TOTAL_TILE))
            EXPERIMENTAL_TILES.forEach { tag -> assertFalse("fs $s: $tag shown with Experimental Ranks off", h.exists(tag)) }
            val order = h.readingOrder("profile-ranks-off fs $s", fresh = true)
            assertTrue("fs $s: TalkBack never reads the Total Score Rank tile: $order", TILES.getValue(TOTAL_TILE) in order)
            EXPERIMENTAL_TILES.forEach { tag ->
                val label = TILES.getValue(tag).substringBefore(':')
                assertTrue("fs $s: TalkBack reads $label with Experimental Ranks off: $order", order.none { it.startsWith(label) })
            }
        }
        h.assertAccessible()
    }

    @Test
    fun profileShowsEveryRankTileInMetricOrderWhileOnAndDropsThemWhenTurnedOff() {
        var scale by mutableFloatStateOf(1f)
        val prefs = preferences(true)
        h.enableAccessibilityChecks()
        launchProfile(prefs) { scale }
        val heights = SCALES.map { s ->
            scale = s
            showTile(TOTAL_TILE, TILES.getValue(TOTAL_TILE))
            val read = mutableSetOf<String>()
            TILES.forEach { (tag, label) ->
                h.scrollTo(GRID, tag)
                val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
                assertEquals("fs $s: $tag label", listOf(label), node.config.getOrNull(SemanticsProperties.ContentDescription))
                assertEquals("fs $s: $tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
                assertTrue("fs $s: $tag is not tappable", SemanticsActions.OnClick in node.config)
                h.assertTouchTarget("profile-ranks-on fs $s", tag)
                val order = h.readingOrder("profile-ranks-on fs $s ${tag.substringAfterLast('.')}", fresh = true)
                val ranks = order.filter { it in TILES.values }
                assertEquals("fs $s: rank tiles read out of metric order: $order", TILES.values.filter { it in ranks }, ranks)
                read += ranks
            }
            assertEquals("fs $s: TalkBack missed rank tiles", TILES.values.toSet(), read)
            rule.onNodeWithTag(TILES.keys.last()).fetchSemanticsNode().size.height
        }
        assertTrue("200% text did not grow the Max Score % Rank tile ($heights px)", heights[1] > heights[0])
        runBlocking { prefs.edit { it[key] = false } }
        rule.waitUntil(5_000) { EXPERIMENTAL_TILES.none(h::exists) }
        h.scrollTo(GRID, TOTAL_TILE)
        assertTrue("Total Score Rank left with the experimental tiles", h.exists(TOTAL_TILE))
        h.assertAccessible()
    }

    /**
     * The selected player's own page (every tile action available) with experimental ranks in
     * the Lead ranking row, waiting for Overview.
     */
    private fun launchProfile(prefs: MemoryPreferences, scale: () -> Float) {
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
            on("/api/rankings/Solo_Guitar/${Fixtures.ACCOUNT_A}") { LEAD_RANKING }
        }
        h.launch(DebugLaunch(profile = PROFILE_PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport, prefs, fontScale = scale)
        h.waitForTag("fst.player.overview")
        h.publishTalkBackTree()
    }

    /** Scroll to [tag] and wait for its loaded announcement [label]. */
    private fun showTile(tag: String, label: String) {
        rule.waitForIdle()
        h.scrollTo(GRID, tag)
        rule.waitUntil(15_000) {
            rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription) == listOf(label)
        }
    }

    // endregion

    // region Rivals

    @Test
    fun rivalsLeaderboardHasNoRankByWhileOff() {
        h.enableAccessibilityChecks()
        val transport = launchRivals(false) { 1f }
        assertFalse("Song Rivals offers Rank By", h.exists(RIVALS_RANK_BY))
        showLeaderboardTab()
        assertFalse("Leaderboard Rivals offers Rank By with Experimental Ranks off", h.exists(RIVALS_RANK_BY))
        val order = h.readingOrder("rivals-leaderboard-experimental-off", fresh = true)
        assertTrue("TalkBack reads Rank By with Experimental Ranks off: $order", order.none { it.startsWith("Rank By") })
        rule.waitUntil(10_000) { rankByRequests(transport).isNotEmpty() }
        assertEquals("Leaderboard Rivals loaded another metric", setOf("totalscore"), rankByRequests(transport))
        h.assertAccessible()
    }

    @Test
    fun rivalsLeaderboardRankByIsAFullSizeControlWhileOn() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        val transport = launchRivals(true) { scale }
        assertFalse("Song Rivals offers Rank By", h.exists(RIVALS_RANK_BY))
        showLeaderboardTab()
        SCALES.forEach { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag(RIVALS_RANK_BY)
            val node = h.accessibilityNode(RIVALS_RANK_BY)
            assertNotNull("fs $s: Rank By missing with Experimental Ranks on", node)
            assertEquals("fs $s: Rank By label", "Rank By, Total Score", node!!.contentDescription?.toString())
            assertTrue("fs $s: Rank By is not clickable", node.isClickable)
            h.assertTouchTarget("rivals-rank-by fs $s", RIVALS_RANK_BY)
            val order = h.readingOrder("rivals-leaderboard-experimental-on fs $s", fresh = true)
            assertEquals("fs $s: Rank By read once: $order", 1, order.count { it == "Rank By, Total Score" })
        }
        h.tap(RIVALS_RANK_BY)
        METRICS.forEach { h.waitForTag("$RIVALS_RANK_BY_ITEM.$it") }
        h.readingOrder("rivals-rank-by-menu")
        h.tap("$RIVALS_RANK_BY_ITEM.adjusted")
        rule.waitUntil(10_000) { "adjusted" in rankByRequests(transport) }
        rule.waitUntil(5_000) { h.accessibilityNode(RIVALS_RANK_BY)?.contentDescription?.toString() == "Rank By, Adjusted" }
        h.assertAccessible()
    }

    private fun launchRivals(experimentalRanks: Boolean, scale: () -> Float): FakeTransport {
        val transport = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        h.launch(DebugLaunch(route = RivalsRoute, profile = RIVALS_PLAYER, stillBackground = true), transport, preferences(experimentalRanks), fontScale = scale)
        h.waitForTag("fst.rivals.section.common")
        h.publishTalkBackTree()
        return transport
    }

    private fun showLeaderboardTab() {
        h.tap("fst.rivals.tab.leaderboard")
        h.waitForTag("fst.rivals.section.leaderboard.Solo_Guitar")
        h.awaitAccessibilityTree(present = "fst.rivals.section.leaderboard.Solo_Guitar")
    }

    /** `rankBy` values of every Leaderboard Rivals list read so far. */
    private fun rankByRequests(transport: FakeTransport): Set<String> = runCatching { transport.requests.toList() }.getOrDefault(emptyList())
        .map { it.url }
        .filter { url -> url.substringBefore('?').substringAfter("/leaderboard-rivals/", "/").let { it.isNotEmpty() && '/' !in it } }
        .mapNotNull { url -> url.substringAfter('?', "").split('&').firstOrNull { it.startsWith("rankBy=") }?.substringAfter('=') }
        .toSet()

    // endregion

    // region First Run

    @Test
    fun leaderboardsTourLeavesOutTheExperimentalSlideWhileOff() {
        h.enableAccessibilityChecks()
        val ids = launchLeaderboardsTour(false)
        assertFalse("the Experimental Ranking Metrics slide shows with Experimental Ranks off ($ids)", EXPERIMENTAL_SLIDE in ids)
        assertTrue("the Leaderboards tour lost its other slides ($ids)", "leaderboards-overview" in ids)
        readEverySlide(ids)
        h.assertAccessible()
    }

    @Test
    fun leaderboardsTourIncludesTheExperimentalSlideWhileOn() {
        h.enableAccessibilityChecks()
        val ids = launchLeaderboardsTour(true)
        assertTrue("the Experimental Ranking Metrics slide is missing with Experimental Ranks on ($ids)", EXPERIMENTAL_SLIDE in ids)
        val read = readEverySlide(ids)
        assertTrue("TalkBack never reads the Experimental Ranking Metrics slide: $read", read.any { EXPERIMENTAL_TITLE in it })
        h.assertAccessible()
    }

    /** Leaderboards' first-visit tour from a fresh seen store; returns its slide ids. */
    private fun launchLeaderboardsTour(experimentalRanks: Boolean): List<String> {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = RANKINGS_PLAYER, firstRun = "on", stillBackground = true)
        val transport = RankingsFixtures.install(FakeTransport.standard())
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = preferences(experimentalRanks))
        rule.setContent { FestivalApp(container, debug) }
        h.waitForTag("fst.first-run.dialog")
        return checkNotNull(container.firstRun.active.value) { "no tour" }.slides.map { it.id }
    }

    /** Page through every slide, reading each; returns everything read. */
    private fun readEverySlide(ids: List<String>): List<String> = ids.indices.flatMap { index ->
        if (index > 0) {
            h.tap("fst.first-run.next")
            rule.waitUntil(5_000) {
                rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode()
                    .config.getOrNull(SemanticsProperties.StateDescription)?.startsWith("Slide ${index + 1} of ") == true
            }
        }
        h.readingOrder("leaderboards-tour ${ids[index]}", fresh = true)
    }

    // endregion

    private companion object {
        val SCALES = listOf(1f, 2f)
        val PROFILE_PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        val RIVALS_PLAYER = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
        val RANKINGS_PLAYER = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
        const val GRID = "fst.player.available"
        const val TOTAL_TILE = "fst.player.tile.Solo_Guitar.global-rank"

        /** Lead rank tiles in metric order with their TalkBack labels (unique: other charts rank #8 by Total Score). */
        val TILES = linkedMapOf(
            TOTAL_TILE to "Total Score Rank: #2",
            "$TOTAL_TILE-adjusted" to "Adjusted Percentile Rank: #3",
            "$TOTAL_TILE-weighted" to "Weighted Percentile Rank: #4",
            "$TOTAL_TILE-fcrate" to "FC Rate Rank: #5",
            "$TOTAL_TILE-maxscore" to "Max Score % Rank: #6",
        )
        val EXPERIMENTAL_TILES = TILES.keys.drop(1)
        val LEAD_RANKING = """{"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","instrument":"","totalScore":1234567,""" +
            """"totalScoreRank":2,"adjustedSkillRank":3,"weightedRank":4,"fcRateRank":5,"maxScorePercentRank":6,""" +
            """"totalRankedAccounts":500,"songsPlayed":3,"totalChartedSongs":3}"""
        val METRICS = listOf("totalscore", "adjusted", "weighted", "fcrate", "maxscore")
        const val RIVALS_RANK_BY = "fst.rivals.rank-by-menu"
        const val RIVALS_RANK_BY_ITEM = "fst.rivals.rank-by"
        const val EXPERIMENTAL_SLIDE = "leaderboards-experimental-metrics"
        const val EXPERIMENTAL_TITLE = "Experimental Ranking Metrics"
    }
}
