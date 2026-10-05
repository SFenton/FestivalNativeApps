package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasContentDescriptionExactly
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.DrawerContent
import com.festivalscoretracker.android.ui.shell.FestivalRail
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Drawer rows mirror the web sidebar; Settings and the profile row sit at the bottom. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShellDrawerUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun noProfileShowsSongsLeaderboardsShopThenSelectProfileAndSettings() {
        val sections = mutableListOf<FestivalSection>()
        val routes = mutableListOf<AppRoute>()
        var profileOpened = false
        rule.setContent {
            DrawerContent(
                visible = FestivalTabPolicy.sections(ProfileKind.None, regularWidth = false),
                selected = FestivalSection.Songs,
                profile = ProfileKind.None,
                player = null,
                onSection = { sections += it },
                onRoute = { routes += it },
                onOpenProfile = { profileOpened = true },
                onDeselect = {},
            )
        }
        rule.onNodeWithTag("fst.nav.drawer.songs").assertIsSelected()
        listOf("suggestions", "statistics", "rivals", "bands", "licenses").forEach { entry ->
            assertEquals(entry, 0, rule.onAllNodesWithTag("fst.nav.drawer.$entry").fetchSemanticsNodes().size)
        }
        rule.onNodeWithTag("fst.nav.drawer.leaderboards").performClick()
        rule.onNodeWithTag("fst.nav.drawer.shop").performClick()
        rule.onNodeWithTag("fst.nav.drawer.select-profile").performClick()
        rule.onNodeWithTag("fst.nav.drawer.settings").performClick()
        assertEquals(listOf(FestivalSection.Leaderboards, FestivalSection.Settings), sections)
        assertEquals(listOf<AppRoute>(ShopRoute), routes)
        assertTrue(profileOpened)
    }

    @Test
    fun playerOnPhonePushesLeaderboardsAndDeselects() {
        val routes = mutableListOf<AppRoute>()
        var deselected = false
        rule.setContent {
            DrawerContent(
                visible = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false),
                selected = FestivalSection.Compete,
                profile = ProfileKind.Player,
                player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
                onSection = {},
                onRoute = { routes += it },
                onOpenProfile = {},
                onDeselect = { deselected = true },
                showShop = false,
            )
        }
        rule.onNodeWithTag("fst.nav.drawer.rivals").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.drawer.shop").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.nav.drawer.leaderboards").performClick()
        rule.onNodeWithTag("fst.nav.drawer.deselect").performClick()
        assertEquals(listOf<AppRoute>(LeaderboardsRoute), routes)
        assertTrue(deselected)
    }

    /**
     * Issue #162 (Android check of Apple #16): the player row shows only the name, no
     * "Selected Player" caption, with the same Tab role, height, icon column and label metrics
     * as the other rows, and TalkBack reads it as "Profile: <name>".
     */
    @Test
    fun playerRowShowsOnlyTheNameStyledLikeTheOtherRows() {
        var opened = 0
        rule.setContent {
            DrawerContent(
                visible = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false),
                selected = FestivalSection.Songs,
                profile = ProfileKind.Player,
                player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
                onSection = { opened++ },
                onRoute = { opened++ },
                onOpenProfile = {},
                onDeselect = {},
            )
        }
        val inDrawer = hasAnyAncestor(hasTestTag("fst.nav.drawer-sheet"))
        assertEquals(0, rule.onAllNodes(inDrawer and hasText("Selected", substring = true, ignoreCase = true), useUnmergedTree = true).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodes(inDrawer and hasContentDescription("Selected", substring = true, ignoreCase = true), useUnmergedTree = true).fetchSemanticsNodes().size)

        val row = rule.onNodeWithTag("fst.nav.drawer.player")
        row.assert(hasContentDescriptionExactly("Profile: Synthetic Player"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Text))
        rule.onNodeWithTag("fst.nav.drawer.songs").assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
        // The name is the row's only semantics child (the icon is decorative): no second line.
        val playerParts = rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.nav.drawer.player")), useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals(1, playerParts.size)

        val name = playerParts.single().boundsInRoot
        val songs = rule.onNode(hasText("Songs") and hasAnyAncestor(hasTestTag("fst.nav.drawer.songs")), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val settings = rule.onNode(hasText("Settings") and hasAnyAncestor(hasTestTag("fst.nav.drawer.settings")), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals("label column", songs.left, name.left, 0.5f)
        assertEquals("label column", settings.left, name.left, 0.5f)
        assertEquals("label line height", songs.height, name.height, 0.5f)
        val playerRow = row.fetchSemanticsNode().boundsInRoot
        val songsRow = rule.onNodeWithTag("fst.nav.drawer.songs").fetchSemanticsNode().boundsInRoot
        assertEquals("row start", songsRow.left, playerRow.left, 0.5f)
        assertEquals("row height", songsRow.height, playerRow.height, 0.5f)

        row.performClick()
        assertEquals(1, opened)
    }

    /**
     * Issue #162: on a short window at 2.0× (phone landscape) the whole sheet scrolls, so the
     * destinations keep their full rows instead of a sliver above a pinned footer; on a tall
     * window the footer still sits at the bottom of the sheet.
     */
    @Test
    fun shortLargeTextSheetScrollsAsOneListAndTallSheetKeepsTheFooterAtTheBottom() {
        var tall by mutableStateOf(false)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = if (tall) 1f else 2f)) {
                Box(Modifier.width(360.dp).height(if (tall) 800.dp else 340.dp)) {
                    DrawerContent(
                        visible = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false),
                        selected = FestivalSection.Songs,
                        profile = ProfileKind.Player,
                        player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
                        onSection = {},
                        onRoute = {},
                        onOpenProfile = {},
                        onDeselect = {},
                    )
                }
            }
        }
        val sheet = rule.onNodeWithTag("fst.nav.drawer-sheet")
        val range = sheet.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        assertTrue("short sheet scrolls", range.maxValue() > 0f)
        val songs = rule.onNodeWithTag("fst.nav.drawer.songs").fetchSemanticsNode().boundsInRoot
        val sheetBounds = sheet.fetchSemanticsNode().boundsInRoot
        assertTrue("Songs row fully visible", songs.bottom <= sheetBounds.bottom)
        rule.onNodeWithTag("fst.nav.drawer.settings").performScrollTo().assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.drawer.player").assertIsDisplayed()

        tall = true
        rule.waitForIdle()
        val settings = rule.onNodeWithTag("fst.nav.drawer.settings").fetchSemanticsNode().boundsInRoot
        val tallSheet = sheet.fetchSemanticsNode().boundsInRoot
        assertEquals("footer at the bottom", tallSheet.bottom, settings.bottom, 1f)
        assertEquals(0f, sheet.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].maxValue(), 0.5f)
    }

    @Test
    fun railPinsProfileAndSettingsToTheBottom() {
        var profile = false
        val picked = mutableListOf<FestivalSection>()
        rule.setContent {
            FestivalRail(
                sections = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = true),
                selected = FestivalSection.Songs,
                player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
                onSection = { picked += it },
                onOpenDrawer = {},
                onOpenProfile = { profile = true },
            )
        }
        val rivals = rule.onNodeWithTag("fst.nav.tab.rivals").fetchSemanticsNode().boundsInRoot
        val settings = rule.onNodeWithTag("fst.nav.tab.settings").fetchSemanticsNode().boundsInRoot
        val rail = rule.onNodeWithTag("fst.nav.rail").fetchSemanticsNode().boundsInRoot
        assertTrue(settings.bottom > rail.bottom - 100f)
        assertTrue(settings.top - rivals.bottom > 100f)
        rule.onNodeWithTag("fst.nav.rail.profile").performClick()
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        assertTrue(profile)
        assertEquals(listOf(FestivalSection.Settings), picked)
    }
}
