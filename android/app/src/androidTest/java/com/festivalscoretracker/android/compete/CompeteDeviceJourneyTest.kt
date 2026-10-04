package com.festivalscoretracker.android.compete

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
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
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        val debug = if (compact) {
            DebugLaunch(section = FestivalSection.Compete, profile = player, stillBackground = true)
        } else {
            DebugLaunch(route = CompeteRoute, profile = player, stillBackground = true)
        }
        h.launch(debug, transport)
        h.waitForTag("fst.compete.leaderboard-card.0f")
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

    @Test
    fun leaderboardsGroupOpensTheFullBoardAndComesBack() {
        launch()
        h.readingOrder("compete-leaderboards")
        h.assertNothingStraddles("fst.compete.section.leaderboards", "fst.compete.leaderboard-card.0f", leadCard)
        scrollUntil(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        h.assertNothingStraddles(leadCard, "fst.compete.spotlight.Solo_Guitar")
        val viewFull = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag(leadCard)))
        scrollUntil(viewFull)
        rule.onNode(viewFull, useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        h.waitForTag("fst.full-rankings.pager")
        back()
        h.waitForTag(GRID)
        h.waitForTag(leadCard)
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
    }
}
