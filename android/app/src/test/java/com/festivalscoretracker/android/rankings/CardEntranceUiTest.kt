package com.festivalscoretracker.android.rankings

import android.os.Looper
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.math.roundToInt

/**
 * A card that groups several rows fades in as one with all its rows, never row by row
 * (load-transition R11, owner-approved #614 variant): mid-entrance every row of the board card
 * (or Leaderboards overview card) still drifts by the same amount, and Reduce Motion shows them
 * in place at once.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class CardEntranceUiTest : LeaderboardsHarness() {
    // region Helpers

    /** Distinct visible rows whose tag starts with [prefix] (inside [ancestor] when given), top first. */
    private fun rows(prefix: String, ancestor: String?): List<String> {
        val row = SemanticsMatcher("row $prefix") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true }
        val matcher = if (ancestor != null) row and hasAnyAncestor(hasTestTag(ancestor)) else row
        return rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes()
            .filter { it.boundsInRoot.height > 0f }
            .sortedBy { it.boundsInRoot.top }
            .distinctBy { it.boundsInRoot.top.roundToInt() }
            .map { it.config[SemanticsProperties.TestTag] }
    }

    private fun top(tag: String) = node(tag).fetchSemanticsNode().boundsInRoot.top

    /**
     * Releases [gate] with the frame clock paused, steps frames until [loading] has gone and the
     * card's first [ROWS] rows are composed, then returns how far (px) each of them still sits
     * below its settled place [PROBE_MS] into the entrance (`fadeInUp` drifts 12 dp up).
     */
    private fun entranceDrifts(gate: CompletableDeferred<Unit>, loading: String, prefix: String, ancestor: String? = null): List<Float> {
        rule.mainClock.autoAdvance = false
        gate.complete(Unit)
        var frames = 0
        while (exists(loading) || rows(prefix, ancestor).size < ROWS) {
            check(frames++ < 2_000) { "the card never revealed" }
            shadowOf(Looper.getMainLooper()).idle()
            rule.mainClock.advanceTimeByFrame()
        }
        val tags = rows(prefix, ancestor).take(ROWS)
        rule.mainClock.advanceTimeBy(PROBE_MS)
        val mid = tags.map(::top)
        rule.mainClock.advanceTimeBy(2_000)
        rule.mainClock.autoAdvance = true
        return tags.mapIndexed { index, tag -> mid[index] - top(tag) }
    }

    /** One frame of the entrance (16 ms of 400 ms ≈ 10% of the 12 dp drift). */
    private fun frameTolerance() = with(rule.density) { 1.2.dp.toPx() }

    private fun assertOneFade(drifts: List<Float>) {
        assertTrue("the card is still drifting up: $drifts", drifts.first() > 0.5f)
        // Without R11 the fifth row would wait 500 ms for its stagger while the first moved.
        drifts.forEach { assertEquals("every row drifts with its card: $drifts", drifts.first(), it, frameTolerance()) }
    }

    private fun reduceMotion() {
        runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
    }

    // endregion

    @Test
    fun songLeaderboardRowsFadeInWithTheirCard() {
        val first = CompletableDeferred<Unit>()
        hold = { request -> first.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForTag("fst.song-leaderboard.loading")
        assertOneFade(entranceDrifts(first, "fst.song-leaderboard.loading", "fst.song-leaderboard.row."))
    }

    @Test
    fun fullRankingsRowsFadeInWithTheirCard() {
        val first = CompletableDeferred<Unit>()
        hold = { request -> first.takeIf { request.url.contains("/api/rankings/Solo_Guitar?") } }
        launch("fullRankings:Solo_Guitar")
        waitForTag("fst.full-rankings.loading")
        assertOneFade(entranceDrifts(first, "fst.full-rankings.loading", "fst.rankings.row."))
    }

    @Test
    fun bandRankingsRowsFadeInWithTheirCard() {
        val first = CompletableDeferred<Unit>()
        hold = { request -> first.takeIf { request.url.contains("/api/rankings/bands/Band_Trios?") } }
        launch("bandRankings:Band_Trios")
        waitForTag("fst.band-rankings.loading")
        assertOneFade(entranceDrifts(first, "fst.band-rankings.loading", "fst.band-rankings.row."))
    }

    @Test
    fun overviewCardRowsFadeInWithTheirCard() {
        val first = CompletableDeferred<Unit>()
        hold = { request -> first.takeIf { request.url.contains("/api/rankings/Solo_Guitar?") } }
        launch("leaderboards")
        waitForTag("fst.leaderboards.loading")
        assertOneFade(entranceDrifts(first, "fst.leaderboards.loading", "fst.rankings.row.", "fst.leaderboards.card.Solo_Guitar"))
    }

    @Test
    fun boardCardShowsInPlaceUnderReduceMotion() {
        reduceMotion()
        val first = CompletableDeferred<Unit>()
        hold = { request -> first.takeIf { request.url.contains("/api/rankings/Solo_Guitar?") } }
        launch("fullRankings:Solo_Guitar")
        waitForTag("fst.full-rankings.loading")
        val drifts = entranceDrifts(first, "fst.full-rankings.loading", "fst.rankings.row.")
        drifts.forEach { assertEquals("no fade under Reduce Motion: $drifts", 0f, it, 0.5f) }
    }

    private companion object {
        /** Rows compared: the fifth would start 500 ms after the first under a row stagger. */
        const val ROWS = 5

        /** Well into the card's 400 ms entrance, before the second row's old 125 ms slot ends. */
        const val PROBE_MS = 120L
    }
}
