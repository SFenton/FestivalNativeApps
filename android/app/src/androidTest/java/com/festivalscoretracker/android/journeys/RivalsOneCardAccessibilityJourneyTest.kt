package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.rivals.RIVALS_CARD_SEGMENT_TAG
import com.festivalscoretracker.android.ui.rivals.RIVALS_CARD_TAG
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #603 accessibility: every rival list is one card of hairline-separated rows (iOS
 * `FestivalGlassSection`). TalkBack must still read each card as separate rows: on the Rivals hub
 * the Lead card reads its rival rows, then View All Rivals, all inside the card; Rival Detail's
 * Closest Battles reads its heading, View All, then its song rows inside the one card; Rivalry reads
 * its songs top to bottom across the card's touching lazy segments. Every row is one 48 dp Button
 * whose label names the song, both ranks and who leads (no hidden score gap), at 100% and 200%
 * text. ATF runs on every step. Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class RivalsOneCardAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, PLAYER_NAME)

    private fun launch(debug: DebugLaunch, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        h.launch(debug, RivalsFixtures.transport(), fontScale = fontScale)
        h.publishTalkBackTree()
    }

    private fun minTargetPx(): Float = with(rule.density) { 48.dp.toPx() } - 1

    private fun tagStartsWith(prefix: String) = SemanticsMatcher("tag $prefix*") {
        it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true
    }

    /** [node]'s bounds on screen, comparable with [JourneyHarness.ReadingStop.bounds]. */
    private fun screenBounds(node: SemanticsNode): Rect {
        val origin = IntArray(2).also { rule.activity.window.decorView.getLocationOnScreen(it) }
        return node.boundsInWindow.translate(origin[0].toFloat(), origin[1].toFloat())
    }

    /** Reading stops whose centre lies inside [box]. */
    private fun stopsInside(screen: String, box: Rect): List<JourneyHarness.ReadingStop> =
        h.readingStops(screen, fresh = true).filter { box.contains(androidx.compose.ui.geometry.Offset(it.bounds.exactCenterX(), it.bounds.exactCenterY())) }

    /**
     * Assert every [rows] node is one element at least 48 dp tall and wide: a Button when it opens
     * something, while an anonymous rival ("Unknown User", not tappable, as on the web) has no click.
     *
     * @param rows Row nodes.
     * @param what Row kind, for messages.
     */
    private fun assertButtonRows(rows: List<SemanticsNode>, what: String) {
        assertTrue("No $what rows", rows.isNotEmpty())
        assertTrue("No tappable $what rows", rows.any { it.config.contains(SemanticsActions.OnClick) })
        rows.forEach { row ->
            val label = row.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString()
            if (row.config.contains(SemanticsActions.OnClick)) {
                assertEquals("$what \"$label\" is not a Button", Role.Button, row.config.getOrNull(SemanticsProperties.Role))
            } else {
                assertTrue("$what \"$label\" has no click but is not anonymous", label.startsWith("Unknown User"))
            }
            assertTrue("$what \"$label\" is ${row.size} px, under 48 dp", row.size.width >= minTargetPx() && row.size.height >= minTargetPx())
        }
    }

    /** Song rows speak title, chart, both ranks and who leads, and never the score gap the row no longer shows. */
    private fun assertSongLabels(rows: List<SemanticsNode>) = rows.forEach { row ->
        val label = row.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString()
        assertTrue("Song row \"$label\" misses a rank", "$PLAYER_NAME rank" in label && " rank " in label.substringAfter("$PLAYER_NAME rank"))
        assertTrue("Song row \"$label\" misses who leads", Regex("""(lead|leads) by \d[\d,]* ranks?$|, tied$""").containsMatchIn(label))
        assertTrue("Song row \"$label\" speaks a score the row doesn't show", "score" !in label)
    }

    /** Hub Lead card: rows then View All Rivals, all inside one card, at 100% and 200% text. */
    @Test
    fun hubCardReadsItsRowsThenViewAllInsideOneCard() {
        var scale by mutableFloatStateOf(1f)
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true)) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(LEAD_SECTION)
            h.scrollTo(GRID, LEAD_SECTION)
            h.awaitAccessibilityTree(present = LEAD_SECTION)
            val lead = hasAnyAncestor(hasTestTag(LEAD_SECTION))
            val cards = rule.onAllNodes(hasTestTag(RIVALS_CARD_TAG) and lead, useUnmergedTree = true).fetchSemanticsNodes()
            assertEquals("Lead rivals are not one card at ${fontScale}x", 1, cards.size)
            val inCard = hasAnyAncestor(hasTestTag(RIVALS_CARD_TAG) and lead)
            val rows = rule.onAllNodes(tagStartsWith("fst.rivals.row.") and lead).fetchSemanticsNodes()
            assertEquals("A Lead row sits outside its card", rows.size, rule.onAllNodes(tagStartsWith("fst.rivals.row.") and inCard).fetchSemanticsNodes().size)
            assertButtonRows(rows, "Rival")
            assertEquals("View All Rivals is not inside the card", 1, rule.onAllNodes(hasTestTag(VIEW_ALL) and inCard).fetchSemanticsNodes().size)

            val box = screenBounds(rule.onAllNodes(hasTestTag(RIVALS_CARD_TAG) and lead, useUnmergedTree = true).fetchSemanticsNodes().single())
            val stops = stopsInside("rivals-hub-lead-card-${fontScale}x", box).filter { it.isClickable }
            val ids = stops.mapNotNull { it.id }
            val iViewAll = ids.indexOf(VIEW_ALL)
            val rowIds = ids.filter { it.startsWith("fst.rivals.row.") }
            assertTrue("TalkBack reads no rows in the Lead card: $ids", rowIds.isNotEmpty())
            // At 200% the card can be taller than the screen: rows read before View All whenever both show.
            if (iViewAll >= 0) assertTrue("View All Rivals is read before a row: $ids", ids.take(iViewAll).containsAll(rowIds))
            h.assertAccessible()
        }
    }

    /** Rival Detail's Closest Battles card and Rivalry's segmented card read like separate rows, at 100% and 200% text. */
    @Test
    fun detailCategoryAndRivalryReadTheirOneCardAsRows() {
        var scale by mutableFloatStateOf(1f)
        val route = RivalRoutes.detail(RivalsFixtures.RIVALS[0], RIVAL_NAME, RivalScopes.song(listOf(Instrument.Lead)))
        launch(DebugLaunch(route = route, profile = player, stillBackground = true)) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(CLOSEST)
            h.awaitAccessibilityTree(present = CLOSEST)
            val category = hasAnyAncestor(hasTestTag(CLOSEST))
            assertEquals("Closest Battles is not one card at ${fontScale}x", 1, rule.onAllNodes(hasTestTag(RIVALS_CARD_TAG) and category, useUnmergedTree = true).fetchSemanticsNodes().size)
            val songs = rule.onAllNodes(tagStartsWith("fst.rivals.song.") and category).fetchSemanticsNodes()
            assertEquals("A Closest Battles row sits outside its card", songs.size, rule.onAllNodes(tagStartsWith("fst.rivals.song.") and hasAnyAncestor(hasTestTag(RIVALS_CARD_TAG) and category)).fetchSemanticsNodes().size)
            assertButtonRows(songs, "Song")
            assertSongLabels(songs)

            val box = screenBounds(rule.onAllNodesWithTag(CLOSEST, useUnmergedTree = true).fetchSemanticsNodes().first())
            val ids = stopsInside("rival-detail-closest-${fontScale}x", box).filter { it.isClickable }.mapNotNull { it.id }
            val iViewAll = ids.indexOf(SEE_ALL_CLOSEST)
            assertTrue("TalkBack misses Closest Battles' View All: $ids", iViewAll >= 0)
            val songIds = ids.filter { it.startsWith("fst.rivals.song.") }
            assertTrue("A Closest Battles row is read before its View All: $ids", songIds.all { ids.indexOf(it) > iViewAll })
            h.assertAccessible()
        }

        scale = 1f
        rule.waitForIdle()
        h.tap(SEE_ALL_CLOSEST)
        h.waitForTag(RIVALRY_TITLE)
        h.awaitAccessibilityTree(present = RIVALRY_TITLE, absent = TITLE)
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(RIVALRY_TITLE)
            val segments = rule.onAllNodesWithTag(RIVALS_CARD_SEGMENT_TAG, useUnmergedTree = true).fetchSemanticsNodes().sortedBy { it.boundsInRoot.top }
            assertTrue("Rivalry draws no card segments", segments.isNotEmpty())
            segments.zipWithNext().forEach { (above, below) ->
                assertEquals("Rivalry's card has a gap between rows at ${fontScale}x", above.boundsInRoot.bottom, below.boundsInRoot.top, 1f)
            }
            val songs = rule.onAllNodes(tagStartsWith("fst.rivals.song.") and hasAnyAncestor(hasTestTag(RIVALS_CARD_SEGMENT_TAG))).fetchSemanticsNodes()
            assertEquals("A Rivalry row sits outside the card", rule.onAllNodes(tagStartsWith("fst.rivals.song.")).fetchSemanticsNodes().size, songs.size)
            assertButtonRows(songs, "Rivalry song")
            assertSongLabels(songs)
            val visual = songs.sortedBy { it.boundsInRoot.top }.map { it.config[SemanticsProperties.TestTag] }
            val read = h.readingStops("rivalry-one-card-${fontScale}x", fresh = true).mapNotNull { it.id }.filter { it.startsWith("fst.rivals.song.") }
            assertTrue("TalkBack reads no Rivalry rows", read.isNotEmpty())
            assertEquals("Rivalry rows are read out of visual order", visual.filter { it in read }, read)
            h.assertAccessible()
        }
    }

    private companion object {
        const val PLAYER_NAME = "Synthetic Player"
        const val RIVAL_NAME = "Synthetic Rival"
        const val GRID = "fst.rivals.grid"
        const val LEAD_SECTION = "fst.rivals.section.Solo_Guitar"
        const val VIEW_ALL = "fst.rivals.view-all"
        const val TITLE = "fst.rival-detail.title"
        const val CLOSEST = "fst.rival-detail.category.closest_battles"
        const val SEE_ALL_CLOSEST = "fst.rival-detail.see-all.closest_battles"
        const val RIVALRY_TITLE = "fst.rivalry.title"
    }
}
