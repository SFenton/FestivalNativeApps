package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.RivalBarTitle
import com.festivalscoretracker.android.core.rivals.RivalPageTitles
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalSettingsScope
import org.junit.Assert.assertEquals
import org.junit.Test

/** Issue #604: rival pages name the rival and section in the bar title and subtitle. */
class RivalPageTitlesTest {
    @Test
    fun detailNamesTheRivalOverRivals() {
        assertEquals(RivalBarTitle("Synthetic Rival", "Rivals"), RivalPageTitles.detail("Synthetic Rival", null))
        assertEquals(RivalBarTitle("Synthetic Rival", "Rivals"), RivalPageTitles.detail("Synthetic Rival", RivalScope.FromSettings(RivalSettingsScope.All)))
    }

    @Test
    fun singleChartDetailNamesTheChartsRivalsWithItsIcon() {
        assertEquals(RivalBarTitle("Synthetic Rival", "Lead Rivals", Instrument.Lead), RivalPageTitles.detail("Synthetic Rival", RivalScopes.song(listOf(Instrument.Lead))))
        assertEquals(RivalBarTitle("Synthetic Rival", "Bass Rivals", Instrument.Bass), RivalPageTitles.detail("Synthetic Rival", RivalScope.Leaderboard(Instrument.Bass)))
    }

    @Test
    fun multiChartDetailKeepsPlainRivals() {
        assertEquals(RivalBarTitle("Synthetic Rival", "Rivals"), RivalPageTitles.detail("Synthetic Rival", RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))))
        assertEquals(RivalBarTitle("Synthetic Rival", "Rivals"), RivalPageTitles.detail("Synthetic Rival", RivalScope.Combo("03")))
        assertEquals(RivalBarTitle("Synthetic Rival", "Rivals"), RivalPageTitles.detail("Synthetic Rival", RivalScope.FromSettings(RivalSettingsScope.Common)))
    }

    @Test
    fun rivalryNamesTheSectionOverTheRival() {
        assertEquals(RivalBarTitle("Closest Battles", "Synthetic Rival"), RivalPageTitles.rivalry("closest_battles", "Synthetic Rival"))
        assertEquals(RivalBarTitle("Dominating Them", "Synthetic Rival"), RivalPageTitles.rivalry("dominating_them", "Synthetic Rival"))
        // Unknown modes show their key, as on the web.
        assertEquals("weird", RivalPageTitles.rivalry("weird", "Synthetic Rival").title)
    }

    @Test
    fun anUnnamedRivalReadsRival() {
        assertEquals("Rival", RivalPageTitles.detail(null, null).title)
        assertEquals("Rival", RivalPageTitles.detail("  ", null).title)
        assertEquals("Rival", RivalPageTitles.rivalry("closest_battles", null).subtitle)
    }
}
