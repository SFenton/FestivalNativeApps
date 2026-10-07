package com.festivalscoretracker.android.compete

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.rivals.RivalPill
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compete journeys on a real device/emulator against synthetic boards and rivals (run with
 * `device.py test com.festivalscoretracker.android.compete.CompeteDeviceJourneyTest --avd …`,
 * adding `--posture half|unfolded|folded` on folds). Compete opens as the tab below 600 dp (the
 * user path) and as the pushed route on wider windows. Every screen and interaction runs the
 * Accessibility Test Framework; reading orders go to logcat `FST_A11Y`; no card may straddle
 * a separating hinge.
 */
@RunWith(AndroidJUnit4::class)
class CompeteDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = CompeteFixtures.transport()
    private val player = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player")
    private val leadCard = "fst.compete.leaderboard-card.Solo_Guitar"
    private val leadRivals = "fst.compete.rivals-card.Solo_Guitar"
    private val rival = "fst.rivals.row.${RivalsFixtures.RIVALS[0]}"

    private fun launch() {
        h.enableAccessibilityChecks()
        h.launch(debug(), transport)
        h.waitForTag("fst.compete.leaderboard-card.0f")
    }

    private fun debug(): DebugLaunch {
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        return if (compact) {
            DebugLaunch(section = FestivalSection.Compete, profile = player, stillBackground = true)
        } else {
            DebugLaunch(route = CompeteRoute, profile = player, stillBackground = true)
        }
    }

    /** Scrolls the lazy grid until a node matching [matcher] is composed (cards load asynchronously). */
    private fun scrollUntil(matcher: SemanticsMatcher) {
        rule.waitUntil(15_000) {
            runCatching { rule.onNodeWithTag(GRID).performScrollToNode(matcher) }.isSuccess &&
                rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        rule.waitForIdle()
    }

    private fun back() {
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
    }

    /**
     * Issue #354 (web `CompetePage` `usePageTransition`, load-transition R1): while any read is
     * in flight Compete shows one labelled, indeterminate Material 3 progress indicator that
     * TalkBack reads, and no headers or cards; once every read settles the spinner gives way to
     * the headers and cards, and no card ever shows its own spinner.
     */
    @Test
    fun pageShowsOneLabelledSpinnerUntilEveryReadSettles() {
        val gate = CompletableDeferred<Unit>()
        transport.beforeRespond = { request -> if ("/api/rankings" in request.url || "/rivals/" in request.url) gate.await() }
        h.enableAccessibilityChecks()
        h.launch(debug(), transport)
        h.waitForTag(PAGE_LOADING)
        rule.onNode(hasContentDescription(CompeteText.LOADING), useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
        h.awaitAccessibilityTree(present = PAGE_LOADING)
        val spoken = h.readingOrder("compete-loading")
        assertTrue("TalkBack never reaches the page spinner: $spoken", spoken.any { it.startsWith(CompeteText.LOADING) })
        listOf(GRID, "fst.compete.section.leaderboards", "fst.compete.leaderboard-card.0f", "$leadCard.loading").forEach { tag ->
            assertTrue("$tag shown while Compete loads", !h.exists(tag))
        }

        gate.complete(Unit)
        h.waitForTag("fst.compete.section.leaderboards")
        h.waitGone(PAGE_LOADING)
        scrollUntil(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        assertTrue("A card showed its own spinner", !h.exists("$leadCard.loading"))
        h.assertAccessible()
    }
    @Test
    fun leaderboardsGroupOpensTheFullBoardAndComesBack() {
        launch()
        h.readingOrder("compete-leaderboards")
        h.assertNothingStraddles("fst.compete.section.leaderboards", "fst.compete.leaderboard-card.0f", leadCard)
        scrollUntil(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        h.assertNothingStraddles(leadCard, "fst.compete.spotlight.Solo_Guitar")
        val viewFull = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag(leadCard)))
        scrollUntil(viewFull)
        val cells = SONGS_CELL.and(hasAnyAncestor(hasTestTag(leadCard)))
        fun songsShown() = rule.onAllNodes(cells, useUnmergedTree = true).fetchSemanticsNodes().size
        fun cardBounds() = rule.onNodeWithTag(leadCard).fetchSemanticsNode().boundsInRoot
        val songsBefore = songsShown()
        val boundsBefore = cardBounds()
        rule.onNode(viewFull, useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        h.waitForTag("fst.full-rankings.pager")

        // Issues #82/#185: Back shows the card where it was, with the same columns on every frame.
        rule.mainClock.autoAdvance = false
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        val frames = mutableListOf<Int>()
        val placements = mutableListOf<Any?>()
        repeat(60) {
            rule.mainClock.advanceTimeByFrame()
            val node = rule.onAllNodes(hasTestTag(leadCard)).fetchSemanticsNodes().firstOrNull()
            if (node != null) {
                frames += songsShown()
                placements += node.boundsInRoot
            }
        }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        h.waitForTag(GRID)
        h.waitForTag(leadCard)
        assertTrue("Compete never reappeared", frames.isNotEmpty())
        assertTrue("Songs cells changed while returning: $songsBefore before, frames $frames", frames.all { it == songsBefore })
        assertTrue("The Lead card moved while returning: $boundsBefore before, frames $placements", placements.all { it == boundsBefore })
        assertEquals("The Lead card moved after returning", boundsBefore, cardBounds())
        assertTrue("Compete reloaded the Lead card", !h.exists("$leadCard.loading"))
        h.assertAccessible()
    }

    @Test
    fun rivalsGroupOpensRivalDetail() {
        launch()
        h.tap("fst.quick-links.open")
        h.tap("fst.quick-links.item.rivals")
        h.waitForTag("fst.compete.section.rivals")
        scrollUntil(hasTestTag(rival).and(hasAnyAncestor(hasTestTag(leadRivals))))
        h.readingOrder("compete-rivals")
        h.assertNothingStraddles("fst.compete.section.rivals", leadRivals, rival)
        h.tap(rival)
        h.waitForTag("fst.rival-detail.title")
        back()
        h.waitForTag(leadRivals)
        h.assertAccessible()
    }

    /** With device fonts at 2.0 scale, a phone-width Compete rival row wraps its pills and grows to show both. */
    @Test
    fun largeTextRivalRowsShowBothPills() {
        val ids = RivalsFixtures.RIVALS
        fun entry(id: String) = RivalEntry(RivalSummary(id, "SFentonX", 1.0, sharedSongCount = 512, aheadCount = 324, behindCount = 188), RivalDirection.Above)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(379.dp)) { RivalPreviewRows(listOf(entry(ids[0])), onRival = {}, onViewAll = null) }
                        Box(Modifier.requiredWidth(840.dp)) { RivalPreviewRows(listOf(entry(ids[1])), onRival = {}, onViewAll = null) }
                        RivalPill("324 songs behind", win = false, modifier = Modifier.testTag("pill"))
                    }
                }
            }
        }
        fun height(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().size.height
        val pill = height("pill")
        val oneLine = height("fst.rivals.row.${ids[1]}")
        val wrapped = height("fst.rivals.row.${ids[0]}")
        assertTrue("wrapped row $wrapped px should fit a second pill line ($oneLine + $pill px)", wrapped >= oneLine + pill)
    }

    private companion object {
        const val GRID = "fst.compete.grid"
        const val PAGE_LOADING = "fst.compete.loading"

        /** A board row's `X / Y` songs cell (issue #38). */
        val SONGS_CELL = SemanticsMatcher("songs cell") { node ->
            node.config.getOrElse(SemanticsProperties.Text) { emptyList() }.any { Regex("""^\d+ / \d+$""").matches(it.text) }
        }
    }
}
