package com.festivalscoretracker.android.core.nav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** [HingeSide]: the one separating-hinge side rule shared by sheets, dialogs and the service status page. */
class HingeSideTest {
    private val page = HingeSide.Rect(0f, 0f, 1000f, 800f)

    private fun book(left: Float, right: Float, rtl: Boolean = false, on: HingeSide.Rect = page) =
        HingeSide.padding(on, HingeSide.Rect(left, on.top - 100f, right, on.bottom + 100f), vertical = true, separating = true, rtl = rtl)

    private fun tabletop(top: Float, bottom: Float, on: HingeSide.Rect = page) =
        HingeSide.padding(on, HingeSide.Rect(on.left - 100f, top, on.right + 100f, bottom), vertical = false, separating = true, rtl = false)

    @Test
    fun aFlatFoldOrEmptyPageKeepsTheOrdinaryPlacement() {
        assertNull(HingeSide.keep(page, HingeSide.Rect(490f, 0f, 510f, 800f), vertical = true, separating = false, rtl = false))
        assertNull(HingeSide.keep(page, HingeSide.Rect(0f, 390f, 1000f, 410f), vertical = false, separating = false, rtl = false))
        assertNull(HingeSide.keep(HingeSide.Rect(0f, 0f, 0f, 800f), HingeSide.Rect(0f, 0f, 10f, 800f), vertical = true, separating = true, rtl = false))
        assertNull(HingeSide.keep(HingeSide.Rect(0f, 0f, 800f, 0f), HingeSide.Rect(0f, 0f, 800f, 10f), vertical = false, separating = true, rtl = false))
        assertEquals(HingeSide.Padding.NONE, HingeSide.padding(page, HingeSide.Rect(490f, 0f, 510f, 800f), vertical = true, separating = false, rtl = false))
    }

    @Test
    fun bookHingeKeepsTheWiderSide() {
        assertEquals(HingeSide.Padding(right = 400f), book(600f, 620f))
        assertEquals(HingeSide.Padding(left = 420f), book(400f, 420f))
    }

    @Test
    fun bookHingeKeepsTheLeadingSideOnATie() {
        assertEquals(HingeSide.Padding(right = 510f), book(490f, 510f))
        assertEquals(HingeSide.Padding(left = 510f), book(490f, 510f, rtl = true))
    }

    @Test
    fun bookHingeOverlappingAnEdgeKeepsTheRestOfThePage() {
        assertEquals(HingeSide.Padding(left = 20f), book(-10f, 20f))
        assertEquals(HingeSide.Padding(right = 20f), book(980f, 1010f))
    }

    @Test
    fun bookHingeMissingThePageIsIgnored() {
        assertEquals(HingeSide.Padding.NONE, book(1100f, 1120f))
        assertEquals(HingeSide.Padding.NONE, book(-40f, -10f))
        assertEquals(HingeSide.Padding.NONE, book(0f, 0f))
        assertEquals(HingeSide.Padding.NONE, book(1000f, 1000f))
    }

    @Test
    fun tabletopHingeAlwaysKeepsTheLowerPart() {
        assertEquals(HingeSide.Padding(top = 410f), tabletop(390f, 410f))
        // Larger upper half and larger lower half: below the hinge either way.
        assertEquals(HingeSide.Padding(top = 620f), tabletop(600f, 620f))
        assertEquals(HingeSide.Padding(top = 220f), tabletop(200f, 220f))
        assertEquals(HingeSide.Padding(top = 20f), tabletop(-10f, 20f))
    }

    @Test
    fun tabletopKeepsTheUpperPartOnlyWhenThePageEndsInsideTheHinge() {
        assertEquals(HingeSide.Padding(bottom = 20f), tabletop(780f, 810f))
        assertEquals(HingeSide.Padding.NONE, tabletop(800f, 820f))
        assertEquals(HingeSide.Padding.NONE, tabletop(-40f, 0f))
    }

    @Test
    fun aPageOffsetInTheWindowUsesItsOwnRectangle() {
        // A page right of an 80 px rail and below a 100 px top bar, hinge in window coordinates.
        val inset = HingeSide.Rect(80f, 100f, 1080f, 900f)
        assertEquals(HingeSide.Rect(80f, 100f, 570f, 900f), HingeSide.keep(inset, HingeSide.Rect(570f, 0f, 590f, 1000f), vertical = true, separating = true, rtl = false))
        assertEquals(HingeSide.Padding(right = 510f), book(570f, 590f, on = inset))
        assertEquals(HingeSide.Padding(left = 400f), book(460f, 480f, on = inset))
        assertEquals(HingeSide.Padding(top = 520f), tabletop(600f, 620f, on = inset))
        assertEquals(HingeSide.Padding.NONE, tabletop(40f, 100f, on = inset))
    }

    @Test
    fun rectSizesNeverGoNegative() {
        assertEquals(990f, HingeSide.Rect(1010f, 50f, 2000f, 1550f).width)
        assertEquals(1500f, HingeSide.Rect(1010f, 50f, 2000f, 1550f).height)
        assertEquals(0f, HingeSide.Rect(10f, 10f, 0f, 0f).width)
        assertEquals(0f, HingeSide.Rect(10f, 10f, 0f, 0f).height)
    }
}
