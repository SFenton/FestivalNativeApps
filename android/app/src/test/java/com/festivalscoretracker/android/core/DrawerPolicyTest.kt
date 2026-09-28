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
