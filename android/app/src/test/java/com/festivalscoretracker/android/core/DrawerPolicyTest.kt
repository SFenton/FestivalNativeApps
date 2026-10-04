package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.nav.RivalsRoute
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
        assertEquals(DrawerTarget.Push(RivalsRoute), DrawerPolicy.target(DrawerEntry.Rivals, phone))
        assertEquals(DrawerTarget.Section(FestivalSection.Rivals), DrawerPolicy.target(DrawerEntry.Rivals, rail))
        assertEquals(DrawerTarget.Push(StatisticsRoute), DrawerPolicy.target(DrawerEntry.Statistics, emptyList()))
        assertTrue(DrawerPolicy.isSelected(DrawerEntry.Songs, FestivalSection.Songs))
        assertFalse(DrawerPolicy.isSelected(DrawerEntry.Shop, FestivalSection.Songs))
        assertEquals(rail - FestivalSection.Settings, DrawerPolicy.railMain(rail))
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
        val statisticsTab = open(DrawerTarget.Section(FestivalSection.Statistics))
        listOf(false, true).forEach { regular ->
            assertEquals(statisticsTab, policy.action(ProfileKind.Player, FestivalTabPolicy.sections(ProfileKind.Player, regular)))
            assertEquals(statisticsTab, policy.action(ProfileKind.Band, FestivalTabPolicy.sections(ProfileKind.Band, regular)))
        }
        // Statistics is pushed where it is not a visible tab.
        assertEquals(open(DrawerTarget.Push(StatisticsRoute)), policy.action(ProfileKind.Player, listOf(FestivalSection.Songs, FestivalSection.Settings)))
    }
}
