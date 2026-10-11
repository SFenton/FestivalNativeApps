package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.shell.DrawerEntry
import com.festivalscoretracker.android.core.shell.DrawerPolicy
import com.festivalscoretracker.android.core.shell.DrawerTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Web sidebar parity for the Android drawer. */
class DrawerPolicyTest {
    @Test
    fun entriesFollowTheWebSidebar() {
        assertEquals(listOf(DrawerEntry.Songs, DrawerEntry.Leaderboards, DrawerEntry.Shop), DrawerPolicy.entries(ProfileKind.None, showShop = true))
        assertEquals(
            listOf(DrawerEntry.Songs, DrawerEntry.Suggestions, DrawerEntry.Statistics, DrawerEntry.Rivals, DrawerEntry.Leaderboards),
            DrawerPolicy.entries(ProfileKind.Player, showShop = false),
        )
        assertEquals(
            listOf(DrawerEntry.Songs, DrawerEntry.Suggestions, DrawerEntry.Statistics, DrawerEntry.Leaderboards, DrawerEntry.Shop),
            DrawerPolicy.entries(ProfileKind.Band, showShop = true),
        )
    }

    @Test
    fun visibleTabsSwitchOthersPush() {
        val phone = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false)
        val rail = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = true)
        // #610: on a phone Rivals and Leaderboards open under Compete; on a rail they are tabs.
        assertEquals(DrawerTarget.Child(FestivalSection.Compete, RivalsRoute), DrawerPolicy.target(DrawerEntry.Rivals, phone))
        assertEquals(DrawerTarget.Child(FestivalSection.Compete, LeaderboardsRoute), DrawerPolicy.target(DrawerEntry.Leaderboards, phone))
        assertEquals(DrawerTarget.Section(FestivalSection.Rivals), DrawerPolicy.target(DrawerEntry.Rivals, rail))
        assertEquals(DrawerTarget.Section(FestivalSection.Leaderboards), DrawerPolicy.target(DrawerEntry.Leaderboards, rail))
        // Without a visible parent tab the page still pushes on the current tab.
        assertEquals(DrawerTarget.Push(RivalsRoute), DrawerPolicy.target(DrawerEntry.Rivals, listOf(FestivalSection.Songs, FestivalSection.Settings)))
        assertEquals(DrawerTarget.Push(StatisticsRoute), DrawerPolicy.target(DrawerEntry.Statistics, emptyList()))
        // #601: Item Shop is a tab with a profile, so its row switches to it; otherwise it pushes.
        assertEquals(DrawerTarget.Section(FestivalSection.Shop), DrawerPolicy.target(DrawerEntry.Shop, phone))
        assertEquals(DrawerTarget.Section(FestivalSection.Shop), DrawerPolicy.target(DrawerEntry.Shop, rail))
        assertEquals(DrawerTarget.Push(ShopRoute), DrawerPolicy.target(DrawerEntry.Shop, FestivalTabPolicy.sections(ProfileKind.None, regularWidth = false)))
        assertEquals(DrawerTarget.Push(StatisticsRoute), DrawerPolicy.target(DrawerEntry.Statistics, phone))
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Shop, FestivalSection.Shop))
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Songs, FestivalSection.Songs))
        assertFalse(DrawerPolicy.isSelected(DrawerEntry.Shop, FestivalSection.Songs))
        assertEquals(rail - FestivalSection.Settings, DrawerPolicy.railMain(rail))
    }

    /** Debug launches and search results naming a section open its tab, or its pushed page (#601). */
    @Test
    fun sectionRequestsFallBackToThePushedPage() {
        val phone = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false)
        val hidden = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false, showShop = false)
        assertEquals(DrawerTarget.Push(StatisticsRoute), DrawerPolicy.sectionTarget(FestivalSection.Statistics, phone))
        assertEquals(DrawerTarget.Section(FestivalSection.Shop), DrawerPolicy.sectionTarget(FestivalSection.Shop, phone))
        assertEquals(DrawerTarget.Push(ShopRoute), DrawerPolicy.sectionTarget(FestivalSection.Shop, hidden))
        assertEquals(DrawerTarget.Child(FestivalSection.Compete, RivalsRoute), DrawerPolicy.sectionTarget(FestivalSection.Rivals, phone))
        assertEquals(DrawerTarget.Child(FestivalSection.Compete, LeaderboardsRoute), DrawerPolicy.sectionTarget(FestivalSection.Leaderboards, phone))
        assertEquals(DrawerTarget.Section(FestivalSection.Settings), DrawerPolicy.sectionTarget(FestivalSection.Settings, phone))
        assertEquals(null, DrawerPolicy.sectionTarget(FestivalSection.Compete, FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = true)))
    }
}

/** #610: the drawer highlights the page on screen (web sidebar `NavLink`), not the tab under it. */
class DrawerPageTest {
    private fun stack(vararg routes: AppRoute): List<(AppRoute) -> Boolean> = routes.map { shown -> { route: AppRoute -> route == shown } }

    @Test
    fun pageIsTheTopmostDrawerRouteAboveTheTabRoot() {
        assertEquals(null, DrawerPolicy.pageOf(emptyList()))
        assertEquals(null, DrawerPolicy.pageOf(stack(SongDetailRoute("s-alpha"))))
        assertEquals(DrawerEntry.Rivals, DrawerPolicy.pageOf(stack(RivalsRoute)))
        assertEquals(DrawerEntry.Rivals, DrawerPolicy.pageOf(stack(RivalsRoute, SongDetailRoute("s-alpha"))))
        assertEquals(DrawerEntry.Statistics, DrawerPolicy.pageOf(stack(RivalsRoute, StatisticsRoute, SongDetailRoute("s-alpha"))))
    }

    @Test
    fun pushedPageWinsOverTheSelectedTab() {
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Rivals, FestivalSection.Compete, DrawerEntry.Rivals))
        assertFalse(DrawerPolicy.isSelected(DrawerEntry.Songs, FestivalSection.Songs, DrawerEntry.Statistics))
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Statistics, FestivalSection.Songs, DrawerEntry.Statistics))
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Songs, FestivalSection.Songs, null))
    }
}

/** Web parity: profile-only routes redirect to Songs without a profile. */
class ProfileRoutePolicyTest {
    @Test
    fun profileOnlyRoutesRedirectWithoutAProfile() {
        val policy = com.festivalscoretracker.android.core.shell.ProfileRoutePolicy
        assertTrue(policy.redirectsToSongs(com.festivalscoretracker.android.core.nav.RivalsTab::class, hasProfile = false))
        assertTrue(policy.redirectsToSongs(com.festivalscoretracker.android.core.nav.PlayerHistoryRoute::class, hasProfile = false))
        assertFalse(policy.redirectsToSongs(com.festivalscoretracker.android.core.nav.SuggestionsTab::class, hasProfile = true))
        assertFalse(policy.redirectsToSongs(com.festivalscoretracker.android.core.nav.SongsTab::class, hasProfile = false))
        assertFalse(policy.redirectsToSongs(com.festivalscoretracker.android.core.nav.PlayerRoute::class, hasProfile = false))
    }
}

/** Issue #290 (web `getProfileClickDestination`): the profile chip opens the selected profile's page. */
class ProfileChipPolicyTest {
    @Test
    fun withoutAProfileTheChipChoosesOne() {
        val policy = com.festivalscoretracker.android.core.shell.ProfileChipPolicy
        val choose = com.festivalscoretracker.android.core.shell.ProfileChipAction.ChooseProfile
        assertEquals(choose, policy.action(ProfileKind.None, FestivalTabPolicy.sections(ProfileKind.None, regularWidth = false)))
        assertEquals(choose, policy.action(ProfileKind.None, FestivalTabPolicy.sections(ProfileKind.None, regularWidth = true)))
    }

    @Test
    fun aSelectedPlayerOrBandOpensStatistics() {
        val policy = com.festivalscoretracker.android.core.shell.ProfileChipPolicy
        fun open(target: DrawerTarget) = com.festivalscoretracker.android.core.shell.ProfileChipAction.Open(target)
        // Statistics is not a tab (#601), so the chip pushes it at every width, Shop shown or hidden.
        val statistics = open(DrawerTarget.Push(StatisticsRoute))
        listOf(false, true).forEach { regular ->
            listOf(false, true).forEach { shop ->
                assertEquals(statistics, policy.action(ProfileKind.Player, FestivalTabPolicy.sections(ProfileKind.Player, regular, shop)))
                assertEquals(statistics, policy.action(ProfileKind.Band, FestivalTabPolicy.sections(ProfileKind.Band, regular, shop)))
            }
        }
        // A Statistics tab, were one visible, would be selected instead.
        assertEquals(open(DrawerTarget.Section(FestivalSection.Statistics)), policy.action(ProfileKind.Player, listOf(FestivalSection.Songs, FestivalSection.Statistics)))
    }
}
