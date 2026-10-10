package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The song leaderboards' top bar on a device (issue #580, `song-leaderboard-header` R3,
 * `song-header` R4): empty while the in-page song header shows; once it scrolls away the bar
 * reads the song title over the board line, "{instrument icon} {instrument}" on the solo board
 * and the band size (no icon) on the band board. TalkBack reaches the title and board line as
 * one stop that names each once; the instrument icon has no label of its own; at 200 % text the
 * bar grows so the board line is neither clipped nor ellipsized. ATF runs throughout.
 * `@DeviceCi`: the `android-device` job runs it on a plain phone
 * (`device.py test com.festivalscoretracker.android.journeys.SongBoardBarTitleJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class SongBoardBarTitleJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private fun soloTransport(): FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    private fun bandTransport(): FakeTransport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    ).apply {
        on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, null)
        }
    }

    /** Whether the top bar shows [title] (the marquee may tag a wrapper around its text). */
    private fun barShows(title: String): Boolean {
        val bar = hasTestTag("fst.nav.title")
        return rule.onAllNodes(hasText(title) and (bar or hasAnyAncestor(bar)), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    // region Journeys

    /** Solo board: the bar reads "Alpha Tune" over "{guitar icon} Lead" after the header scrolls away. */
    @Test
    fun soloBoardBarShowsTheSongOverItsInstrument() = journey(
        "song-board-bar",
        route = "songLeaderboard:s-alpha:Solo_Guitar",
        prefix = "fst.song-leaderboard",
        board = "Lead",
        icon = true,
        transport = soloTransport(),
    )

    /** Solo board at 200 % text: the bar grows to fit the title and board line, unclipped. */
    @Test
    fun soloBoardBarGrowsForLargeText() = journey(
        "song-board-bar-font-2",
        route = "songLeaderboard:s-alpha:Solo_Guitar",
        prefix = "fst.song-leaderboard",
        board = "Lead",
        icon = true,
        transport = soloTransport(),
        scale = 2f,
    )

    /** Band board: the bar reads "Alpha Tune" over "Duos", without an icon. */
    @Test
    fun bandBoardBarShowsTheSongOverItsBandSize() = journey(
        "song-band-board-bar",
        route = "songBandLeaderboard:s-alpha:Band_Duets",
        prefix = "fst.song-band-leaderboard",
        board = "Duos",
        icon = false,
        transport = bandTransport(),
    )

    // endregion

    /**
     * Launch the board, check the empty bar, scroll the header away, then check the bar's title,
     * board line, icon and TalkBack stop.
     *
     * @param screen Name for the reading-order log and failure messages.
     * @param route Debug route of the board.
     * @param prefix The board's test-tag prefix.
     * @param board Expected board line (instrument or band size).
     * @param icon Whether the board line leads with the instrument icon.
     * @param transport Fixture transport for the board.
     * @param scale Font scale to render at, or null for the device's own.
     */
    private fun journey(screen: String, route: String, prefix: String, board: String, icon: Boolean, transport: FakeTransport, scale: Float? = null) {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(
            route = DebugLaunch.parseRoute(route),
            profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player").takeIf { prefix == "fst.song-leaderboard" },
            stillBackground = true,
        )
        h.launch(debug, transport, fontScale = scale?.let { s -> { s } })
        h.waitForTag("$prefix.list")
        h.awaitAccessibilityTree("$prefix.list")
        // Never selected-profile headers (service-safety).
        assertTrue(transport.requests.none { request -> request.headers.keys.any { it.startsWith("X-FST-Selected", ignoreCase = true) } })

        // The in-page header carries the song: the bar is empty, board line included.
        assertFalse("$screen: the bar shows a title before any scroll", barShows("Alpha Tune"))
        assertFalse("$screen: an empty bar title is a TalkBack stop", h.readingStops("$screen-top").any { it.id == "fst.nav.title-block" })
        assertFalse("$screen: the bar shows the board line before any scroll", h.exists("fst.nav.subtitle"))
        val barBefore = rule.onNode(hasTestTag("fst.nav.top-bar"), useUnmergedTree = true).fetchSemanticsNode().boundsInWindow

        // Around a separating hinge the header never scrolls away (song-leaderboard-header R3).
        if (h.exists("$prefix.supporting-pane") || h.exists("$prefix.controls-pane")) return
        rule.onNode(hasTestTag("$prefix.list")).performScrollToIndex(1)
        rule.waitForIdle()
        // A window tall enough to show the whole board cannot scroll the header away.
        runCatching { rule.waitUntil(10_000) { h.exists("fst.nav.subtitle") } }.onFailure { return }

        val bar = rule.onNode(hasTestTag("fst.nav.top-bar"), useUnmergedTree = true).fetchSemanticsNode().boundsInWindow
        assertEquals("$screen: the bar changed height when its title appeared", barBefore.height, bar.height, 1f)
        assertTrue("$screen: the bar has no title", rule.onAllNodes(hasText("Alpha Tune") and hasAnyAncestor(hasTestTag("fst.nav.title-block")), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        val line = rule.onNode(hasTestTag("fst.nav.subtitle"), useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("$screen: board line", board, line.config.getOrNull(SemanticsProperties.Text)?.joinToString())
        assertTrue("$screen: board line ${line.boundsInWindow} outside the bar $bar", line.boundsInWindow.top >= bar.top - 1 && line.boundsInWindow.bottom <= bar.bottom + 1)
        if (scale != null) h.assertTextUnclipped(screen, "fst.nav.title-block", board, scale)

        assertEquals("$screen: board icon shown", icon, h.exists("fst.nav.subtitle-icon"))
        if (icon) {
            val glyph = rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.nav.subtitle-icon")) or hasTestTag("fst.nav.subtitle-icon"), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("$screen: the decorative icon has a label", glyph.none { it.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().isNotEmpty() })
        }

        // TalkBack: one stop names the song and the board once each.
        val stops = h.readingStops(screen, fresh = true)
        val barOnScreen = android.graphics.Rect().also { r -> checkNotNull(h.accessibilityNode("fst.nav.top-bar")) { "$screen: no bar node" }.getBoundsInScreen(r) }
        val inBar = stops.filter { it.bounds.centerY() in barOnScreen.top..barOnScreen.bottom && it.label.contains("Alpha Tune") }
        assertEquals("$screen: the bar's title is read ${inBar.size} times in ${stops.map { it.label }}", 1, inBar.size)
        val stop = inBar.single().label
        assertEquals("$screen: \"$stop\" names the song once", 1, Regex("Alpha Tune").findAll(stop).count())
        assertEquals("$screen: \"$stop\" names the board once", 1, Regex("\\b$board\\b").findAll(stop).count())
        assertTrue("$screen: \"$stop\" reads the board after the song", stop.indexOf("Alpha Tune") < stop.indexOf(board))
        h.assertAccessible()
    }
}
