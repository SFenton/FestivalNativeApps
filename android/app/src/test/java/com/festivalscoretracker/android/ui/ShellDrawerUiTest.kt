package com.festivalscoretracker.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
