package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.rankings.SelectedRowAction
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.rankings.SelectedRowReveal
import com.festivalscoretracker.android.core.rankings.SelectedRowSubject
import com.festivalscoretracker.android.core.rankings.label
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** `leaderboard-row` R7 (issue #307): one rule for the selected player's and band's own rows. */
class SelectedRowNavigationTest {
    @Test
    fun footerJumpsOnlyWhileTheRowIsOnAnotherPage() {
        // Rank 30 is on page 2 of 25-row pages.
        assertEquals(SelectedRowAction.Jump(2), SelectedRowAction.footer(rank = 30, isVisible = false, currentPage = 1))
        assertEquals(SelectedRowAction.Jump(2), SelectedRowAction.footer(rank = 30, isVisible = false, currentPage = 7))
        // Shown on screen: open the profile.
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.footer(rank = 30, isVisible = true, currentPage = 2))
        // Its page is already shown (e.g. filtered out of the rows): never a no-op jump.
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.footer(rank = 30, isVisible = false, currentPage = 2))
        // Unusable ranks open the profile.
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.footer(rank = 0, isVisible = false, currentPage = 1))
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.footer(rank = -4, isVisible = false, currentPage = 1))
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.footer(rank = 30, isVisible = false, currentPage = 1, pageSize = 0))
        assertEquals(SelectedRowAction.Jump(3), SelectedRowAction.footer(rank = 30, isVisible = false, currentPage = 1, pageSize = 10))
    }

    @Test
    fun previewRowsAlwaysJumpToTheirPage() {
        assertEquals(SelectedRowAction.Jump(1), SelectedRowAction.preview(11))
        assertEquals(SelectedRowAction.Jump(1), SelectedRowAction.preview(25))
        assertEquals(SelectedRowAction.Jump(2), SelectedRowAction.preview(26))
        assertEquals(SelectedRowAction.Jump(4_001), SelectedRowAction.preview(100_001))
        assertEquals(SelectedRowAction.OpenProfile, SelectedRowAction.preview(0))
    }

    @Test
    fun labelsNameTheDestination() {
        assertEquals("Jump to your position", SelectedRowAction.Jump(2).label(SelectedRowSubject.Player))
        assertEquals("Open your statistics", SelectedRowAction.OpenProfile.label(SelectedRowSubject.Player))
        assertEquals("Jump to your band's position", SelectedRowAction.Jump(2).label(SelectedRowSubject.Band))
        assertEquals("Open band", SelectedRowAction.OpenProfile.label(SelectedRowSubject.Band))
        assertEquals(SelectedRowLabels.OPEN_BAND, SelectedRowAction.OpenProfile.label(SelectedRowSubject.Band))
    }

    @Test
    fun revealCentresTheRowAboveTheFooter() {
        // Viewport 0–1000 with the footer covering 800–1000: centre is 400.
        assertEquals(1_250f, SelectedRowReveal.centerDelta(rowTop = 1_600, rowHeight = 100, visibleStart = 0, visibleEnd = 800))
        assertEquals(-350f, SelectedRowReveal.centerDelta(rowTop = 0, rowHeight = 100, visibleStart = 0, visibleEnd = 800))
        assertEquals(0f, SelectedRowReveal.centerDelta(rowTop = 350, rowHeight = 100, visibleStart = 0, visibleEnd = 800))
        // Before-content padding shifts the visible start negative.
        assertEquals(0f, SelectedRowReveal.centerDelta(rowTop = 342, rowHeight = 100, visibleStart = -16, visibleEnd = 800))
        // A collapsed region never yields a negative span.
        assertEquals(50f, SelectedRowReveal.centerDelta(rowTop = 0, rowHeight = 100, visibleStart = 0, visibleEnd = -20))
    }

    @Test
    fun revealWaitsForTheRowsOwnEntrance() {
        // Web navToPlayer waits out the row's stagger; native waits for its whole fade (#323).
        assertEquals(400, SelectedRowReveal.entranceWaitMillis(rowDelayMillis = 0, fadeMillis = 400, reduceMotion = false))
        assertEquals(1_900, SelectedRowReveal.entranceWaitMillis(rowDelayMillis = 1_500, fadeMillis = 400, reduceMotion = false))
        // Reduce Motion: nothing fades, so the reveal scrolls at once.
        assertEquals(0, SelectedRowReveal.entranceWaitMillis(rowDelayMillis = 1_500, fadeMillis = 400, reduceMotion = true))
    }

    @Test
    fun bandFooterEntryReadsAsTheBand() {
        val band = SongBandLeaderboardEntry(
            bandId = "b1", bandType = "Band_Duets", teamKey = "t1",
            members = listOf(BandMember(accountId = "a", displayName = "Alpha"), BandMember(accountId = "b", displayName = "Beta")),
            score = 3_000_000_000L, rank = 42, accuracy = 0.0, isFullCombo = true, stars = 6,
        )
        val row = band.footerLeaderboardEntry
        assertEquals("band-b1", row.accountId)
        assertEquals(band.membersLabel, row.displayName)
        assertEquals(Int.MAX_VALUE, row.score)
        assertEquals(42, row.rank)
        assertNull(row.accuracy)
        assertEquals(true, row.isFullCombo)
        assertEquals(6, row.stars)
        val anonymous = band.copy(bandId = "", members = emptyList(), score = 1_234, accuracy = 98.5).footerLeaderboardEntry
        assertEquals("band-t1", anonymous.accountId)
        assertEquals("Band", anonymous.displayName)
        assertEquals(1_234, anonymous.score)
        assertEquals(98.5, anonymous.accuracy!!, 0.0)
    }
}
