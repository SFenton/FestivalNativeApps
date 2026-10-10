package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility journeys over the player features: Statistics (profile), Leaderboards and
 * Full Rankings, Rivals (hub, detail, rivalry) and Compete. ATF on every screen and
 * interaction; reading orders in logcat `FST_A11Y`
 * (`device.py test com.festivalscoretracker.android.journeys.PlayerAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class PlayerAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    @Test
    fun statisticsProfile() {
        h.enableAccessibilityChecks()
        val transport = FakeTransport.standard().apply(songs).also { ProfileFixtures.register(it) }
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.player.available")
        h.readingOrder("statistics")
        h.scrollTo("fst.player.available", "fst.player.top-songs")
        h.readingOrder("statistics-top-songs")
        h.assertAccessible()
    }

    @Test
    fun leaderboardsAndFullRankings() {
        h.enableAccessibilityChecks()
        val transport = RankingsFixtures.install(FakeTransport.standard().apply(songs))
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true), transport)
        h.waitForTag("fst.leaderboards.rank-history")
        h.readingOrder("leaderboards")
        h.scrollTo("fst.leaderboards", "fst.leaderboards.card.Solo_Guitar.view-all")
        h.tap("fst.leaderboards.card.Solo_Guitar.view-all")
        h.waitForTag("fst.full-rankings.pager")
        h.readingOrder("full-rankings")
        h.assertAccessible()
    }

    @Test
    fun rivalsHubDetailAndRivalry() {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply(songs)
        h.launch(DebugLaunch(route = RivalsRoute, profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.rivals.section.common")
        h.readingOrder("rivals")
        h.tap("fst.rivals.row.${RivalsFixtures.RIVALS[1]}")
        h.waitForTag("fst.rival-detail.title")
        h.readingOrder("rival-detail")
        // Rival Detail's categories are real sections and keep Quick Links.
        h.waitForTag("fst.quick-links.open")
        h.tap("fst.rival-detail.see-all.closest_battles")
        h.waitForTag("fst.rivalry.title")
        h.waitGone("fst.quick-links.open")
        h.awaitAccessibilityTree(present = "fst.rivalry.title", absent = "fst.quick-links.open")
        // Owner, #545: Rivalry has no Quick Links; TalkBack reads Sort, then View Profile.
        val rivalry = h.readingOrder("rivalry", fresh = true)
        assertFalse("no Quick Links stop on Rivalry: $rivalry", rivalry.any { it.startsWith("Quick Links") })
        val sort = rivalry.indexOfFirst { it.startsWith("Sort: ") }
        val profile = rivalry.indexOfFirst { it.startsWith("View ") && it.endsWith("Profile") }
        assertTrue("Sort precedes View Profile: $rivalry", sort >= 0 && profile > sort)
        h.assertTouchTarget("rivalry", "fst.rivalry.sort")
        h.assertTouchTarget("rivalry", "fst.rival-detail.view-profile")
        h.assertAccessible()
    }

    /** Rival Detail's chooser at 100% text: a distinct decorative icon per category (#605). */
    @Test
    @DeviceCi
    fun rivalDetailQuickLinksIconsAreDecorative() = rivalDetailQuickLinks(1f)

    /** The same at 200% text: rows stay 48 dp, in order and named only by their category. */
    @Test
    @DeviceCi
    fun rivalDetailQuickLinksIconsAreDecorativeAtDoubleText() = rivalDetailQuickLinks(2f)

    /**
     * Opens Rival Detail's Quick Links (sheet on phones, menu when wide) and checks every
     * category row: it reads only its category name (the icon adds nothing to TalkBack), the
     * rows read in page order, no node inside a row is an image or has its own label, and each
     * row is a 48 dp target (pattern `quick-links` R6, R9).
     *
     * @param scale Font scale.
     */
    private fun rivalDetailQuickLinks(scale: Float) {
        val config = "${scale}x"
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply(songs)
        h.launch(DebugLaunch(route = RivalDetailRoute(RivalsFixtures.RIVALS[1]), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport, fontScale = { scale })
        h.waitForTag("fst.rival-detail.title")
        h.waitForTag(OPEN)
        h.publishTalkBackTree()
        h.tap(OPEN)
        rule.waitUntil(10_000) { h.exists(SHEET) || h.exists(MENU) }
        val rows = rule.onAllNodes(categoryRow, useUnmergedTree = true).fetchSemanticsNodes()
            .sortedBy { it.positionInWindow.y }
            .map { it.config[SemanticsProperties.TestTag].removePrefix(ROW_PREFIX) }
        assertTrue("$config: fewer than two category rows: $rows", rows.size >= 2)
        assertEquals("$config: rows out of page order: $rows", rows.sortedBy(RivalCategorization.keys::indexOf), rows)
        rows.forEach { key ->
            val tag = "$ROW_PREFIX$key"
            rule.onNodeWithTag(tag).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(RivalCategorization.title(key))))
            val inner = rule.onAllNodes(hasAnyAncestor(hasTestTag(tag)) and (SemanticsMatcher.keyIsDefined(SemanticsProperties.ContentDescription) or SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Image)), useUnmergedTree = true)
                .fetchSemanticsNodes()
            assertTrue("$config: $key's icon is exposed to TalkBack: ${inner.map { it.config }}", inner.isEmpty())
        }
        val stops = h.readingStops("rival-detail-quick-links-$config").filter { it.id?.startsWith(ROW_PREFIX) == true }
        val read = stops.map { it.id!!.removePrefix(ROW_PREFIX) }
        assertEquals("$config: TalkBack reads the shown rows out of page order: $read", rows.filter { it in read }, read)
        assertTrue("$config: fewer than two rows read: $read", read.size >= 2)
        stops.forEach { stop ->
            val title = RivalCategorization.title(stop.id!!.removePrefix(ROW_PREFIX))
            assertTrue("$config: row reads more than its name: ${stop.label}", stop.label == title || stop.label == "$title, $CURRENT")
        }
        stops.filter { it.bounds.height() > 0 }.take(2).forEach { h.assertTouchTarget("rival-detail-quick-links-$config", it.id!!) }
        h.assertAccessible()
    }

    /** Rival Detail's category rows in the open chooser. */
    private val categoryRow = SemanticsMatcher("Rival Detail category row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ROW_PREFIX) == true }

    @Test
    fun compete() {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply(songs).also { RankingsFixtures.install(it) }
        // Compete is a tab only on compact widths; the route works everywhere.
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("compete"), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.compete.grid")
        h.readingOrder("compete")
        h.assertAccessible()
    }

    private companion object {
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val ROW_PREFIX = "fst.quick-links.item.rival-category:"
        const val CURRENT = "Current section"
    }
}
