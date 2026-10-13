package com.festivalscoretracker.android.rankings

import android.os.Looper
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.toSize
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.common.FADE_IN_MILLIS
import com.festivalscoretracker.android.ui.common.FadeInWindow
import com.festivalscoretracker.android.ui.common.FadeInWindowProbe
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.math.abs

/**
 * The selected-row reveal's arrival, frame by frame, at its real call sites (issue #323,
 * load-transition R5/R6, `leaderboard-row` R7; accessibility backfill #470). Each board opens on
 * the selected player's page with the reveal requested (web `navToPlayer` / `navToBand`); its
 * page read is held, the frame clock paused, the read released and every 16 ms frame sampled
 * from the first one that composes the rows: the list's scroll offset, the unclipped tops of the
 * selected row and a row two ranks below it (while the list is still they move only by the
 * `fadeInUp` drift), the pinned footer, and [FadeInWindowProbe]'s [FadeInWindow.rush] calls.
 * - The selected row and the rows its scroll will reach arrive through the rows card's fade
 *   (drifting from 12 dp below, not already in place and opaque): one card, one fade (R11, #614).
 * - The reveal leaves the list still until that fade has ended (at least 400 ms; the row and the
 *   footer have stopped drifting), then calls the page's [FadeInWindow.rush] before its scroll
 *   moves the list. A scroll alone also rushes, but only after it has moved the list past the
 *   window's threshold, so a reveal that stopped calling `rush()` fails here.
 * - Under Reduce Motion nothing drifts and the reveal scrolls at once, still through the rush (R6).
 * - Once it rests, the selected row is wholly in view above the footer as one 48 dp button that
 *   names its destination, and the footer opens the same destination.
 *
 * Runs in every pull request's `android-unit` job. The device journey
 * `SelectedRowRevealAccessibilityJourneyTest` checks the settled result through TalkBack's tree,
 * reading order, 200 % text and ATF.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SelectedRowArrivalUiTest : LeaderboardsHarness() {
    /** The selected player's solo rank: deep on page 2, so the reveal has to scroll. */
    private val soloRank = 45

    /** The selected player's band rank: deep on page 2 of the band board. */
    private val bandRank = 47

    init {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", score = 100_000 - soloRank, rank = soloRank, total = 60)))
        }
        transport.on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val offset = Regex("offset=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 0
            val board = Fixtures.leaderboard("s-alpha", rows = minOf(25, 60 - offset), total = 60, startRank = offset + 1)
            // Page 2's row `soloRank` (index 19) belongs to the selected player.
            val synthetic = "\"accountId\":\"${Fixtures.ACCOUNT_A.dropLast(2)}${10 + soloRank - 26}\",\"displayName\":\"Synthetic Player $soloRank\""
            if (offset == 25) board.replace(synthetic, "\"accountId\":\"${RankingsFixtures.SELECTED}\",\"displayName\":\"Selected Player\"") else board
        }
        transport.on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, bandRank.takeIf { "accountId=${BandFixtures.PLAYER}" in request.url })
        }
    }

    /**
     * One board whose reveal is checked.
     *
     * @property route Debug route opening the selected row's page with the reveal requested.
     * @property profile Selected player.
     * @property prefix Board id prefix (`.list`, `.bottom-bar`, `.spotlight-footer`).
     * @property selectedTag The selected row's test tag.
     * @property neighbourTag A row two ranks below it, which the reveal's scroll brings on screen.
     * @property openLabel Click label of the selected row, and of the footer once the row is on screen.
     * @property held The board's page read, held until the clock is paused.
     * @property footerFades Whether the pinned footer fades in with the rows card (`pinnedStaggered(0)`).
     */
    private data class Board(
        val route: String,
        val profile: SelectedPlayer,
        val prefix: String,
        val selectedTag: String,
        val neighbourTag: String,
        val openLabel: String,
        val held: Regex,
        val footerFades: Boolean,
    )

    private val solo = Board(
        route = "songLeaderboard:s-alpha:Solo_Guitar:2:reveal",
        profile = selected,
        prefix = "fst.song-leaderboard",
        selectedTag = "fst.song-leaderboard.row.${RankingsFixtures.SELECTED}",
        neighbourTag = "fst.song-leaderboard.row.${Fixtures.ACCOUNT_A.dropLast(2)}${10 + soloRank + 2 - 26}",
        openLabel = SelectedRowLabels.OPEN_STATISTICS,
        held = Regex("/api/leaderboard/s-alpha/Solo_Guitar\\?.*offset=25"),
        footerFades = true,
    )

    private val band = Board(
        route = "songBandLeaderboard:s-alpha:Band_Duets:2:reveal",
        profile = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player"),
        prefix = "fst.song-band-leaderboard",
        selectedTag = "fst.song-band-leaderboard.row.band-$bandRank:$bandRank",
        neighbourTag = "fst.song-band-leaderboard.row.band-${bandRank + 2}:${bandRank + 2}",
        openLabel = SelectedRowLabels.OPEN_BAND,
        held = Regex("/api/leaderboard/s-alpha/bands/Band_Duets\\?"),
        footerFades = true,
    )

    private val fullRankings = Board(
        route = "fullRankings:Solo_Guitar:2",
        profile = selected,
        prefix = "fst.full-rankings",
        selectedTag = "fst.rankings.row.${RankingsFixtures.SELECTED}",
        neighbourTag = "fst.rankings.row.${RankingsFixtures.accountId(RankingsFixtures.SELECTED_RANK + 2)}",
        openLabel = SelectedRowLabels.OPEN_STATISTICS,
        held = Regex("/api/rankings/Solo_Guitar\\?"),
        footerFades = false,
    )

    @After
    fun clearProbe() {
        FadeInWindowProbe.onRush = null
    }

    // region Helpers

    private fun semantics(tag: String) =
        rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()

    private fun bounds(tag: String): Rect? = semantics(tag)?.boundsInRoot

    /** Unclipped bounds (with the fade's drift): a row below the viewport keeps its real place. */
    private fun placed(tag: String): Rect? = semantics(tag)?.let { Rect(it.positionInRoot, it.size.toSize()) }

    /** Whether [row] sits wholly below the top bar and above the pinned footer and pager. */
    private fun inView(board: Board, row: Rect): Boolean {
        val list = bounds("${board.prefix}.list") ?: return false
        val top = maxOf(list.top, bounds("fst.nav.top-bar")?.bottom ?: list.top)
        val bottom = minOf(list.bottom, bounds("${board.prefix}.bottom-bar")?.top ?: list.bottom)
        return row.top >= top - 1 && row.bottom <= bottom + 1 && row.width > 0f
    }

    private fun reduceMotion() {
        runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
    }

    // endregion

    // region Arrival

    /**
     * One frame of the arrival.
     *
     * @property ms Frame clock time.
     * @property scroll The list's scroll offset (`VerticalScrollAxisRange`; it never fades).
     * @property row Top of the selected row (unclipped: scroll plus the card's drift).
     * @property neighbour Top of the row two ranks below it.
     * @property footer Top of the pinned footer (its own drift; it never scrolls), or null before it shows.
     * @property rushes [FadeInWindow.rush] calls so far.
     * @property rowInView Whether the selected row is wholly in view above the footer.
     */
    private data class Frame(val ms: Long, val scroll: Float, val row: Float, val neighbour: Float?, val footer: Float?, val rushes: Int, val rowInView: Boolean)

    private fun frame(board: Board, rushes: Int): Frame {
        val row = placed(board.selectedTag)!!
        val scroll = semantics("${board.prefix}.list")!!.config[SemanticsProperties.VerticalScrollAxisRange].value()
        return Frame(
            rule.mainClock.currentTime,
            scroll,
            row.top,
            placed(board.neighbourTag)?.top,
            placed("${board.prefix}.spotlight-footer")?.top,
            rushes,
            inView(board, row),
        )
    }

    private fun step() {
        shadowOf(Looper.getMainLooper()).idle()
        rule.mainClock.advanceTimeByFrame()
    }

    /**
     * Release the held board read on a paused frame clock and sample every frame from the first
     * one that composes the selected row until the reveal has rested in view for 10 frames.
     *
     * @param board Board.
     * @param gate Holds the board's page read.
     * @return Frames, the first one being the rows' first.
     */
    private fun observeArrival(board: Board, gate: CompletableDeferred<Unit>): List<Frame> {
        var rushes = 0
        FadeInWindowProbe.onRush = { rushes++ }
        rule.mainClock.autoAdvance = false
        try {
            gate.complete(Unit)
            var waited = 0
            while (semantics(board.selectedTag) == null) {
                check(waited++ < 2_000) { "${board.route}: the rows never arrived" }
                step()
            }
            val frames = mutableListOf<Frame>()
            while (frames.size < 400) {
                frames += frame(board, rushes)
                val rest = frames.takeLast(10)
                val scrolled = frames.any { abs(it.scroll - frames.first().scroll) > 0.5f }
                if (scrolled && rest.size == 10 && rest.all { it.rowInView && it.row == rest.first().row }) break
                step()
            }
            return frames
        } finally {
            rule.mainClock.autoAdvance = true
            settle()
        }
    }

    /**
     * The arrival: the selected row and its neighbour enter through the rows card's fade (not
     * already in place), the reveal leaves the list still until that fade has ended and rushes the
     * page's fade window before its scroll moves the list; under Reduce Motion nothing drifts and
     * the scroll comes at once.
     */
    private fun assertArrival(board: Board, frames: List<Frame>, reduceMotion: Boolean) {
        val first = frames.first()
        val log = frames.joinToString("\n") { "${it.ms - first.ms} ms scroll=${it.scroll} row=${it.row} next=${it.neighbour} footer=${it.footer} rushes=${it.rushes} inView=${it.rowInView}" }
        val screen = board.route
        assertTrue("$screen: the row two ranks below the selected one is not composed with it\n$log", first.neighbour != null)
        val start = frames.indexOfFirst { abs(it.scroll - first.scroll) > 0.5f }
        assertTrue("$screen: the reveal never scrolled\n$log", start > 0)
        assertTrue("$screen: the reveal left the row out of view\n$log", frames.last().rowInView)
        val driftPx = with(rule.density) { FADE_DRIFT_DP.dp.toPx() }
        // The board's first layout pass may still move the rows (Full Rankings' header settles a
        // frame after them); a jump larger than the whole drift in one frame is not the fade.
        val settled = (1 until start).lastOrNull { abs(frames[it].row - frames[it - 1].row) > driftPx } ?: 0
        val still = frames.subList(settled, start)
        // While the list is still, a row moves only by the card's fadeInUp drift.
        val drift = still.map { it.row - still.last().row }
        val neighbourDrift = still.map { it.neighbour!! - still.last().neighbour!! }
        val rush = frames.indexOfFirst { it.rushes > 0 }
        assertTrue("$screen: the reveal never rushed the page's fade window\n$log", rush >= 0)
        // A scroll's own rush (the window closing) comes only once the list has moved; the
        // reveal's comes first.
        assertTrue("$screen: the list scrolled (frame $start) before the reveal rushed the fades (frame $rush)\n$log", rush < start)
        val footerRested = frames.last().footer
        if (reduceMotion) {
            assertTrue("$screen: the selected row drifted under Reduce Motion: $drift", drift.all { abs(it) <= 0.5f })
            if (board.footerFades) assertEquals("$screen: the pinned footer drifted under Reduce Motion\n$log", footerRested!!, still.first { it.footer != null }.footer!!, 0.5f)
            assertTrue("$screen: the reveal waited ${frames[start].ms - first.ms} ms under Reduce Motion\n$log", frames[start].ms - first.ms <= 4 * FRAME_MS)
            return
        }
        // The selected row, and the rows the scroll will reach, arrive drifting through the card's
        // fade rather than already in place: one card, one fade (R11).
        val arrival = drift.max()
        assertTrue("$screen: the selected row arrived at most $arrival px from rest (no fade); expected about $driftPx px\n$log", arrival >= driftPx * 0.75f)
        assertEquals("$screen: the row the reveal reaches drifts with the selected row's card\n$log", arrival, neighbourDrift.max(), 0.5f)
        // The reveal waits for that fade: no rush and no scroll before 400 ms, nothing still drifting.
        assertTrue("$screen: the reveal rushed ${frames[rush].ms - first.ms} ms after the rows arrived, before their 400 ms fade\n$log", frames[rush].ms - first.ms >= FADE_IN_MILLIS)
        assertEquals("$screen: the selected row was still drifting when the reveal rushed: $drift", 0f, drift[rush - settled], 1f)
        if (board.footerFades) {
            val footer = frames[rush].footer
            assertTrue("$screen: the pinned footer (same fade) was ${footer?.minus(footerRested!!)} px from rest when the reveal rushed\n$log", footer != null && abs(footer - footerRested!!) <= 1f)
        }
    }

    /** The settled reveal: one 48 dp button naming its destination, and the footer opens it too (R7). */
    private fun assertSettled(board: Board) {
        val row = rule.onAllNodes(hasTestTag(board.selectedTag)).fetchSemanticsNodes().first()
        assertEquals("${board.route}: selected row role", Role.Button, row.config.getOrNull(SemanticsProperties.Role))
        assertEquals("${board.route}: selected row action", board.openLabel, row.config.getOrNull(SemanticsActions.OnClick)?.label)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("${board.route}: selected row ${row.boundsInRoot.size} is under 48 dp", row.boundsInRoot.width >= min && row.boundsInRoot.height >= min)
        assertEquals("${board.route}: footer action once the row is on screen", board.openLabel, node("${board.prefix}.spotlight-footer").fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick)?.label)
    }

    private fun arrive(board: Board, reduceMotion: Boolean = false) {
        if (reduceMotion) reduceMotion()
        val gate = CompletableDeferred<Unit>()
        var requested = false
        hold = { request -> gate.takeIf { board.held.containsMatchIn(request.url) }?.also { requested = true } }
        launch(board.route, board.profile)
        rule.waitUntil(10_000) { settle(100); requested }
        settle()
        assertArrival(board, observeArrival(board, gate), reduceMotion)
        assertSettled(board)
    }

    // endregion

    @Test
    fun soloRevealWaitsForTheCardsFadeThenRushesBeforeItScrolls() = arrive(solo)

    @Test
    fun soloRevealUnderReduceMotionScrollsAtOnceWithoutDrift() = arrive(solo, reduceMotion = true)

    @Test
    fun bandRevealWaitsForTheCardsFadeThenRushesBeforeItScrolls() = arrive(band)

    @Test
    fun fullRankingsRevealWaitsForTheCardsFadeThenRushesBeforeItScrolls() = arrive(fullRankings)

    private companion object {
        /** Web `fadeInUp`'s upward drift (`translateY(12px)`). */
        const val FADE_DRIFT_DP = 12

        /** One frame of the paused test clock. */
        const val FRAME_MS = 16L
    }
}
