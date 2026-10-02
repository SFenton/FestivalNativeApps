package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.CornerRadii
import com.festivalscoretracker.android.core.shell.DisplayCorner
import com.festivalscoretracker.android.core.shell.DisplayCorners
import com.festivalscoretracker.android.core.shell.DrawerCornerPolicy
import com.festivalscoretracker.android.core.shell.WindowRect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Modal drawer corners concentric with the display corners (issue #55). */
class DrawerCornerPolicyTest {
    // FST_Phone (Pixel 9 profile): 1080×2424 px, 132 px display corners (dumpsys window, 2026-10-01).
    private val width = 1080f
    private val height = 2424f
    private val radius = 132f
    private val phone = DisplayCorners(
        topLeft = DisplayCorner(radius, radius, radius),
        topRight = DisplayCorner(radius, width - radius, radius),
        bottomRight = DisplayCorner(radius, width - radius, height - radius),
        bottomLeft = DisplayCorner(radius, radius, height - radius),
    )
    private val window = WindowRect(0f, 0f, width, height)

    // Material's DrawerDefaults.shape at 2.625 px/dp: square start, 16 dp (42 px) end.
    private val ltrDefaults = CornerRadii(topLeft = 0f, topRight = 42f, bottomRight = 42f, bottomLeft = 0f)
    private val rtlDefaults = CornerRadii(topLeft = 42f, topRight = 0f, bottomRight = 0f, bottomLeft = 42f)

    @Test
    fun edgeAttachedStartCornersTakeTheDisplayRadiusAndEndCornersKeepMaterial() {
        val sheet = DrawerCornerPolicy.sheetBounds(window, sheetWidth = 945f, sheetHeight = height, rtl = false)
        assertEquals(WindowRect(0f, 0f, 945f, height), sheet)
        assertEquals(CornerRadii(radius, 42f, 42f, radius), DrawerCornerPolicy.radii(phone, sheet, ltrDefaults))
    }

    @Test
    fun rightToLeftMirrorsTheSheet() {
        val sheet = DrawerCornerPolicy.sheetBounds(window, sheetWidth = 945f, sheetHeight = height, rtl = true)
        assertEquals(WindowRect(135f, 0f, width, height), sheet)
        assertEquals(CornerRadii(42f, radius, radius, 42f), DrawerCornerPolicy.radii(phone, sheet, rtlDefaults))
    }

    @Test
    fun aFullWidthSheetIsConcentricOnEveryCorner() {
        val sheet = DrawerCornerPolicy.sheetBounds(window, sheetWidth = width, sheetHeight = height, rtl = false)
        assertEquals(CornerRadii(radius, radius, radius, radius), DrawerCornerPolicy.radii(phone, sheet, ltrDefaults))
    }

    @Test
    fun anEndCornerJustInsideTheArcGetsTheReducedConcentricRadius() {
        // 30 px from the right edge: concentric radius 132 − 30 = 102 px, above Material's 42 px.
        val sheet = DrawerCornerPolicy.sheetBounds(window, sheetWidth = width - 30f, sheetHeight = height, rtl = false)
        assertEquals(CornerRadii(radius, 102f, 102f, radius), DrawerCornerPolicy.radii(phone, sheet, ltrDefaults))
        // 100 px in: 32 px, below Material's minimum, which wins.
        val narrower = DrawerCornerPolicy.sheetBounds(window, sheetWidth = width - 100f, sheetHeight = height, rtl = false)
        assertEquals(42f, DrawerCornerPolicy.radii(phone, narrower, ltrDefaults).topRight)
    }

    @Test
    fun noReportedCornersKeepsMaterialDefaults() {
        val empty = DisplayCorners()
        assertTrue(empty.isEmpty)
        assertFalse(phone.isEmpty)
        val sheet = DrawerCornerPolicy.sheetBounds(window, 945f, height, rtl = false)
        assertEquals(ltrDefaults, DrawerCornerPolicy.radii(empty, sheet, ltrDefaults))
    }

    @Test
    fun aWindowAwayFromTheDisplayCornerKeepsSquareStartCorners() {
        // Bottom split-screen window: its top corners are not display corners (not reported), its
        // bottom corners are, with centres in this window's coordinates.
        val split = DisplayCorners(
            bottomLeft = DisplayCorner(radius, radius, 1100f - radius),
            bottomRight = DisplayCorner(radius, width - radius, 1100f - radius),
        )
        val sheet = DrawerCornerPolicy.sheetBounds(WindowRect(0f, 0f, width, 1100f), 945f, 1100f, rtl = false)
        assertEquals(CornerRadii(0f, 42f, 42f, radius), DrawerCornerPolicy.radii(split, sheet, ltrDefaults))
    }

    @Test
    fun aContainerOffsetInTheWindowIsInsetFromTheDisplayCorner() {
        // Composition starting 40 px below the window top: top-left inset 40 → 92 px; bottom flush.
        val container = WindowRect(0f, 40f, width, height)
        val sheet = DrawerCornerPolicy.sheetBounds(container, 945f, height - 40f, rtl = false)
        assertEquals(WindowRect(0f, 40f, 945f, height), sheet)
        assertEquals(CornerRadii(92f, 42f, 42f, radius), DrawerCornerPolicy.radii(phone, sheet, ltrDefaults))
    }

    @Test
    fun concentricRadiusIsNullOutsideTheArcAndCappedAtTheDisplayRadius() {
        val corner = DisplayCorner(radius, radius, radius)
        assertNull(DrawerCornerPolicy.concentricRadius(null, 0f, 0f, right = false, bottom = false))
        assertNull(DrawerCornerPolicy.concentricRadius(DisplayCorner(0f, 0f, 0f), 0f, 0f, right = false, bottom = false))
        assertNull(DrawerCornerPolicy.concentricRadius(corner, radius, 0f, right = false, bottom = false))
        assertEquals(radius, DrawerCornerPolicy.concentricRadius(corner, -20f, -20f, right = false, bottom = false))
        assertEquals(122f, DrawerCornerPolicy.concentricRadius(corner, 10f, 4f, right = false, bottom = false))
    }
}
