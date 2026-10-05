package com.festivalscoretracker.android.core.nav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DialogHingeTest {
    private val safe = DialogHinge.Area(0f, 50f, 2000f, 1550f)

    private fun area(
        hinge: DialogHinge.Area = DialogHinge.Area(990f, 0f, 1010f, 1600f),
        vertical: Boolean = true,
        separating: Boolean = true,
        rtl: Boolean = false,
    ) = DialogHinge.area(safe, hinge, vertical, separating, rtl)

    @Test
    fun flatFoldKeepsTheCentredDialog() {
        assertNull(area(separating = false))
        assertNull(area(vertical = false, separating = false))
    }

    @Test
    fun verticalHingeKeepsTheLeadingSideOnATie() {
        assertEquals(DialogHinge.Area(0f, 50f, 990f, 1550f), area(hinge = DialogHinge.Area(990f, 0f, 1010f, 1600f)))
        assertEquals(DialogHinge.Area(1010f, 50f, 2000f, 1550f), area(hinge = DialogHinge.Area(990f, 0f, 1010f, 1600f), rtl = true))
    }

    @Test
    fun verticalHingeKeepsTheWiderSide() {
        assertEquals(DialogHinge.Area(800f, 50f, 2000f, 1550f), area(hinge = DialogHinge.Area(800f, 0f, 800f, 1600f)))
        assertEquals(DialogHinge.Area(0f, 50f, 1200f, 1550f), area(hinge = DialogHinge.Area(1200f, 0f, 1200f, 1600f), rtl = true))
    }

    @Test
    fun hingeOutsideTheSafeAreaIsIgnored() {
        assertNull(area(hinge = DialogHinge.Area(0f, 0f, 0f, 1600f)))
        assertNull(area(hinge = DialogHinge.Area(2000f, 0f, 2000f, 1600f)))
        assertNull(area(hinge = DialogHinge.Area(0f, 20f, 2000f, 40f), vertical = false))
        assertNull(area(hinge = DialogHinge.Area(0f, 1560f, 2000f, 1580f), vertical = false))
    }

    @Test
    fun horizontalHingeKeepsTheLowerHalf() {
        assertEquals(DialogHinge.Area(0f, 820f, 2000f, 1550f), area(hinge = DialogHinge.Area(0f, 800f, 2000f, 820f), vertical = false))
    }

    @Test
    fun placeCentresTheDialogInTheArea() {
        val side = DialogHinge.Area(1010f, 50f, 2000f, 1550f)
        assertEquals(1205f to 500f, DialogHinge.place(side, 600f, 600f))
        assertEquals(990f, side.width)
        assertEquals(1500f, side.height)
        assertEquals(0f, DialogHinge.Area(10f, 10f, 0f, 0f).width)
        assertEquals(0f, DialogHinge.Area(10f, 10f, 0f, 0f).height)
    }
}
