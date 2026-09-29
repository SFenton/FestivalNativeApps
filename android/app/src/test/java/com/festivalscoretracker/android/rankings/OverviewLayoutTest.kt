package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.ui.leaderboards.OverviewLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Leaderboards overview rows and Quick Links targets, with and without a hinge. */
class OverviewLayoutTest {
    private val charts = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums)

    @Test
    fun aHingePairsRankHistoryWithTheFirstInstrument() {
        val layout = OverviewLayout(charts, showHistory = true, columns = 2, pairHistory = true)
        assertTrue(layout.historyPaired)
        assertEquals(listOf(Instrument.Bass, Instrument.Drums), layout.gridInstruments)
        assertEquals(0, layout.indexOf(OverviewLayout.HISTORY_ID))
        assertEquals(0, layout.indexOf("instrument:Solo_Guitar"))
        assertEquals(1, layout.indexOf("instrument:Solo_Bass"))
        assertEquals(1, layout.indexOf("instrument:Solo_Drums"))
        // History row, one instrument row, the Bands header, then band rows.
        assertEquals(3, layout.indexOf("band:Band_Duets"))
        assertNull(layout.indexOf("nope"))
    }

    @Test
    fun withoutAHingeTheChartSpansItsOwnRow() {
        val layout = OverviewLayout(charts, showHistory = true, columns = 2)
        assertFalse(layout.historyPaired)
        assertEquals(charts, layout.gridInstruments)
        assertEquals(1, layout.indexOf("instrument:Solo_Guitar"))
        assertEquals(2, layout.indexOf("instrument:Solo_Drums"))
        val anonymous = OverviewLayout(charts, showHistory = false, columns = 1, pairHistory = true)
        assertFalse(anonymous.historyPaired)
        assertNull(anonymous.indexOf(OverviewLayout.HISTORY_ID))
        assertEquals(0, anonymous.indexOf("instrument:Solo_Guitar"))
    }
}
