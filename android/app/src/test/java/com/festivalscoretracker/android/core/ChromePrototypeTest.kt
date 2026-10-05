package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.shell.ChromePrototype
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #309 compact page-tool/search placement prototype switch. */
class ChromePrototypeTest {
    @Test
    fun unsetOrUnknownIsTheShippedPlacement() {
        assertEquals(ChromePrototype.A, ChromePrototype.parse(null))
        assertEquals(ChromePrototype.A, ChromePrototype.parse("z"))
        assertEquals(ChromePrototype.B, ChromePrototype.parse(" b "))
        assertEquals(ChromePrototype.D, DebugLaunch.parse(mapOf("FST_DEBUG_CHROME_PROTO" to "D")).chromePrototype.let(ChromePrototype::parse))
    }

    @Test
    fun aKeepsToolbarSearchAndEveryOtherOptionPinsTheInlineFilter() {
        assertTrue(ChromePrototype.A.songsFilterInToolbar)
        ChromePrototype.entries.filter { it != ChromePrototype.A }.forEach { assertFalse(it.name, it.songsFilterInToolbar) }
    }

    @Test
    fun exactlyOneGlobalSearchEntryPerOption() {
        ChromePrototype.entries.forEach { assertTrue(it.name, it.searchTab != it.searchInTopBar) }
    }

    @Test
    fun aSearchTabDropsStatisticsToStayWithinFiveItems() {
        val player = FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false)
        val bar = ChromePrototype.B.barSections(player)
        assertEquals(listOf(FestivalSection.Songs, FestivalSection.Suggestions, FestivalSection.Compete, FestivalSection.Settings), bar)
        assertTrue(bar.size + 1 <= ChromePrototype.MAX_BAR_ITEMS)
        assertEquals(player, ChromePrototype.C.barSections(player))
        val anonymous = FestivalTabPolicy.sections(ProfileKind.None, regularWidth = false)
        assertEquals(anonymous, ChromePrototype.D.barSections(anonymous))
    }
}
