package com.festivalscoretracker.android.core.nav

import org.junit.Assert.assertEquals
import org.junit.Test

/** [SheetHinge]: modal sheets keep off a separating hinge (Material 3 foldable guidance). */
class SheetHingeTest {
    private fun insets(
        left: Float = 1000f,
        right: Float = 1000f,
        top: Float = 0f,
        bottom: Float = 2000f,
        vertical: Boolean = true,
        separating: Boolean = true,
        rtl: Boolean = false,
    ) = SheetHinge.insets(2000f, left, right, top, bottom, vertical, separating, rtl, sheetTopPx = 100f, gapPx = 20f)

    @Test
    fun flatFoldKeepsTheCentredSheet() {
        assertEquals(SheetHinge.Insets.NONE, insets(separating = false))
        assertEquals(SheetHinge.Insets.NONE, insets(vertical = false, separating = false))
    }

    @Test
    fun bookPostureKeepsTheLeadingHalfOnATie() {
        assertEquals(SheetHinge.Insets(right = 1000f), insets())
        assertEquals(SheetHinge.Insets(left = 1000f), insets(rtl = true))
    }

    @Test
    fun physicalHingeWidthIsExcludedFromTheChosenSide() {
        assertEquals(SheetHinge.Insets(right = 1020f), insets(left = 980f, right = 1020f))
        assertEquals(SheetHinge.Insets(left = 1020f), insets(left = 980f, right = 1020f, rtl = true))
    }

    @Test
    fun unevenHingeKeepsTheWiderSide() {
        assertEquals(SheetHinge.Insets(left = 600f), insets(left = 600f, right = 600f))
        assertEquals(SheetHinge.Insets(right = 600f), insets(left = 1400f, right = 1400f, rtl = true))
    }

    @Test
    fun hingeAtOrBeyondTheWindowEdgeIsIgnored() {
        assertEquals(SheetHinge.Insets.NONE, insets(left = 0f, right = 0f))
        assertEquals(SheetHinge.Insets.NONE, insets(left = 2000f, right = 2000f))
    }

    @Test
    fun tabletopKeepsTheSheetBelowTheHinge() {
        assertEquals(SheetHinge.Insets(top = 1020f), insets(left = 0f, right = 2000f, top = 1080f, bottom = 1100f, vertical = false))
        // A hinge above the sheet's normal top needs no extra padding.
        assertEquals(SheetHinge.Insets(top = 0f), insets(left = 0f, right = 2000f, top = 40f, bottom = 60f, vertical = false))
    }
}
