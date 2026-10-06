package com.festivalscoretracker.android.rivals

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.onNodeWithText
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import org.junit.Assert.assertEquals
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.rivals.RivalPill
import com.festivalscoretracker.android.ui.rivals.RivalRow
import com.festivalscoretracker.android.ui.shell.FestivalApp
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Process-local preferences so device journeys never touch the app's saved settings. */
private class MemoryPreferences : DataStore<Preferences> {
    private val state = MutableStateFlow(emptyPreferences())
    override val data: Flow<Preferences> = state
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
        transform(state.value).also { state.value = it }
}

/**
 * Rivals journeys on a real device/emulator against synthetic rivals (run with
 * `device.py test com.festivalscoretracker.android.rivals.RivalsDeviceJourneyTest --avd …`,
 * adding `--posture half` on book folds): hub → Rival Detail → Rivalry, and the Leaderboard
 * tab, with no card straddling a separating hinge.
 */
@RunWith(AndroidJUnit4::class)
class RivalsDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val ids = RivalsFixtures.RIVALS

    private val transport = RivalsFixtures.transport().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun launch(route: AppRoute = RivalsRoute) {
        val debug = DebugLaunch(route = route, profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
    }

    private fun waitForTag(tag: String) = rule.waitUntil(15_000) { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onAllNodesWithTag(tag)[0].performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    private fun scrollTo(tag: String) {
        waitForTag("fst.rivals.grid")
        rule.onNodeWithTag("fst.rivals.grid").performScrollToNode(hasTestTag(tag))
        rule.waitForIdle()
    }

    /** Separating vertical hinges in window pixels (empty on phones and flat folds). */
    private fun hinges(): List<Rect> = runBlocking {
        val info = withTimeoutOrNull(5_000) { WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first() }
        info?.displayFeatures.orEmpty().filterIsInstance<FoldingFeature>()
            .filter { it.isSeparating && it.orientation == FoldingFeature.Orientation.VERTICAL }
            .map { Rect(it.bounds.left.toFloat(), it.bounds.top.toFloat(), it.bounds.right.toFloat(), it.bounds.bottom.toFloat()) }
    }

    private fun assertNothingStraddles(vararg tags: String) {
        val folds = hinges()
        tags.forEach { tag ->
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().forEach { node ->
                val box = node.boundsInWindow
                folds.forEach { fold -> assertTrue("$tag straddles the fold at ${fold.left}", box.right <= fold.left || box.left >= fold.right) }
            }
        }
    }

    @Test
    fun hubDetailAndRivalry() {
        launch()
        waitForTag("fst.rivals.section.common")
        assertNothingStraddles("fst.rivals.section.common", "fst.rivals.row.${ids[1]}")
        scrollTo("fst.rivals.section.Solo_Guitar")
        assertNothingStraddles("fst.rivals.section.Solo_Guitar")
        scrollTo("fst.rivals.section.common")
        tap("fst.rivals.row.${ids[1]}")
        waitForTag("fst.rival-detail.title")
        tap("fst.rival-detail.see-all.closest_battles")
        waitForTag("fst.rivalry.title")
        waitForTag("fst.rivals.song.s-alpha.Solo_Guitar")
        assertNothingStraddles("fst.rivalry.title", "fst.rivals.song.s-alpha.Solo_Guitar", "fst.rivals.song.s-beta.Solo_Guitar")
        tap("fst.rivalry.sort")
        waitForTag("fst.rivalry.sort.menu")
        rule.onNodeWithTag("fst.rivalry.sort.category").assertIsSelected()
        tap("fst.rivalry.sort.title")
        tap("fst.rivalry.sort")
        waitForTag("fst.rivalry.sort.menu")
        rule.onNodeWithTag("fst.rivalry.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.rivalry.sort.category").assertIsNotSelected()
    }

    @Test
    fun leaderboardTabShowsNeighbours() {
        launch()
        waitForTag("fst.rivals.tab.leaderboard")
        tap("fst.rivals.tab.leaderboard")
        waitForTag("fst.rivals.section.leaderboard.Solo_Guitar")
        assertNothingStraddles("fst.rivals.section.leaderboard.Solo_Guitar")
    }

    /**
     * All Rivals (issue #108): Common Rivals names its charts, every row is a ≥ 48 dp
     * target that stays off a separating hinge (also at the device's current font scale),
     * and a row opens Rival Detail.
     */
    @Test
    fun allRivalsListFitsAndOpensDetail() {
        launch(RivalRoutes.allRivals(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))))
        waitForTag("fst.all-rivals.list")
        waitForTag("fst.all-rivals.subtitle")
        val rows = listOf("fst.rivals.row.${ids[0]}", "fst.rivals.row.${ids[1]}")
        rows.forEach { waitForTag(it) }
        assertNothingStraddles(*rows.toTypedArray())
        val minTargetPx = 48 * rule.activity.resources.displayMetrics.density
        rows.forEach { tag ->
            val box = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().first().boundsInWindow
            assertTrue("$tag is ${box.height}px tall", box.height >= minTargetPx)
        }
        tap(rows[0])
        waitForTag("fst.rival-detail.title")
    }

    /**
     * Issues #68/#176: a hub card's View All Rivals is a ≥ 48 dp target that stays off a
     * separating hinge and opens that card's All Rivals list.
     */
    @Test
    fun viewAllRivalsIsATargetOffTheHingeAndOpensTheList() {
        launch()
        waitForTag("fst.rivals.section.Solo_Guitar")
        val viewAll = hasTestTag("fst.rivals.view-all") and hasAnyAncestor(hasTestTag("fst.rivals.section.Solo_Guitar"))
        rule.onNodeWithTag("fst.rivals.grid").performScrollToNode(viewAll)
        rule.waitForIdle()
        // view-all-cta R4: TalkBack reads the visible label, then the card.
        val node = rule.onNode(viewAll).assertContentDescriptionEquals("${RivalText.VIEW_ALL_RIVALS}, Lead Rivals").fetchSemanticsNode()
        assertEquals(Role.Button, node.config[SemanticsProperties.Role])
        val minTargetPx = 48 * rule.activity.resources.displayMetrics.density
        assertTrue("View All Rivals is ${node.size.height}px tall", node.size.height >= minTargetPx)
        val box = node.boundsInWindow
        hinges().forEach { fold -> assertTrue("View All Rivals straddles the fold at ${fold.left}", box.right <= fold.left || box.left >= fold.right) }
        rule.onNode(viewAll).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.all-rivals.list")
    }

    /**
     * Issues #68/#176: with the device's real fonts, View All Rivals and View Full
     * Leaderboards are the same shared button: same size at the device's font scale and at
     * 2.0, with the label inside the button.
     */
    @Test
    fun viewAllRivalsMatchesViewFullLeaderboardsWithRealFonts() {
        val entry = RivalEntry(RivalSummary(ids[0], "Ann", 1.0, sharedSongCount = 10, aheadCount = 6, behindCount = 4), RivalDirection.Above)
        var fontScale by mutableFloatStateOf(rule.activity.resources.configuration.fontScale)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(300.dp)) { RivalPreviewRows(listOf(entry), onRival = {}, onViewAll = {}) }
                        Box(Modifier.requiredWidth(300.dp)) {
                            ViewFullLeaderboardButton(onClick = {}, label = CompeteText.VIEW_FULL_LEADERBOARDS, testTag = "fst.compete.view-full-leaderboards")
                        }
                    }
                }
            }
        }
        for (scale in listOf(fontScale, 2f)) {
            fontScale = scale
            rule.waitForIdle()
            val rivals = rule.onNodeWithTag("fst.rivals.view-all").fetchSemanticsNode()
            val board = rule.onNodeWithTag("fst.compete.view-full-leaderboards").fetchSemanticsNode()
            assertEquals("same width at font scale $scale", board.size.width, rivals.size.width)
            assertTrue("48 dp minimum target at $scale", rivals.size.height >= 48 * rule.activity.resources.displayMetrics.density)
            val label = rule.onNodeWithText(RivalText.VIEW_ALL_RIVALS, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            val button = rivals.boundsInRoot
            assertTrue("label $label inside $button at $scale", label.top >= button.top && label.bottom <= button.bottom && label.left >= button.left && label.right <= button.right)
        }
    }

    /** Issue #107: with real fonts at 2.0 scale, a narrow card wraps its pills and grows to show both. */
    @Test
    fun largeTextRowShowsBothPills() {
        fun entry(id: String) = RivalEntry(RivalSummary(id, "Ann", 1.0, sharedSongCount = 162, aheadCount = 110, behindCount = 52), RivalDirection.Above)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(300.dp)) { RivalRow(entry(ids[0]), onClick = {}) }
                        Box(Modifier.requiredWidth(720.dp)) { RivalRow(entry(ids[1]), onClick = {}) }
                        RivalPill("110 songs behind", win = false, modifier = Modifier.testTag("pill"))
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
}
