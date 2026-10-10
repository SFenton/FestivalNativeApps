package com.festivalscoretracker.android.bands

import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.BandMemberFit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Band card member-line fit (issue #589, web `PlayerBandCard` `BandMemberRow`). */
class BandMemberFitTest {
    @Test
    fun iconRowCountsIconsAndTheGapsBetweenThem() {
        assertEquals(0f, BandMemberFit.iconRowWidth(0, 20f), 0f)
        assertEquals(20f, BandMemberFit.iconRowWidth(1, 20f), 0f)
        assertEquals(6 * 20f + 5 * BandMemberFit.ICON_GAP, BandMemberFit.iconRowWidth(6, 20f), 0f)
    }

    @Test
    fun nameWidthIsClampedBetweenTheWebBounds() {
        assertEquals(BandLayout.MEMBER_NAME_MIN, BandMemberFit.inlineWidth(BandMemberFit.Member(10f), 20f), 0f)
        assertEquals(BandMemberFit.NAME_MAX, BandMemberFit.inlineWidth(BandMemberFit.Member(600f), 20f), 0f)
        assertEquals(120f, BandMemberFit.inlineWidth(BandMemberFit.Member(120f), 20f), 0f)
    }

    @Test
    fun valueAndIconsEachAddTheirGap() {
        val member = BandMemberFit.Member(nameWidth = 120f, valueWidth = 50f, instruments = 2)
        val expected = 120f + BandMemberFit.INLINE_GAP + 50f + BandMemberFit.INLINE_GAP + (2 * 18f + BandMemberFit.ICON_GAP)
        assertEquals(expected, BandMemberFit.inlineWidth(member, 18f), 0.001f)
    }

    @Test
    fun oneMemberThatDoesNotFitStacksTheWholeCard() {
        val short = BandMemberFit.Member(60f, instruments = 1)
        val wide = BandMemberFit.Member(170f, instruments = 6)
        val width = BandMemberFit.inlineWidth(wide, 20f)
        assertTrue(BandMemberFit.inline(width, listOf(short, wide), 20f, largeText = false))
        assertFalse(BandMemberFit.inline(width - 1f, listOf(short, wide), 20f, largeText = false))
    }

    @Test
    fun largeTextAlwaysStacks() {
        assertFalse(BandMemberFit.inline(10_000f, listOf(BandMemberFit.Member(60f, instruments = 1)), 20f, largeText = true))
    }

    @Test
    fun noMembersIsInline() {
        assertTrue(BandMemberFit.inline(0f, emptyList(), 20f, largeText = false))
    }
}
