package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/** [PaneInsets]: a pane only keeps the horizontal insets that reach into it. */
class PaneInsetsTest {
    private val density = Density(2.625f)
    private val camera = WindowInsets(left = 142, top = 63, right = 0, bottom = 48)

    @Test
    fun fullWindowPaneKeepsEveryInset() {
        val insets = PaneInsets(camera, leftGapPx = 0, rightGapPx = 0)
        assertEquals(142, insets.getLeft(density, LayoutDirection.Ltr))
        assertEquals(0, insets.getRight(density, LayoutDirection.Ltr))
        assertEquals(63, insets.getTop(density))
        assertEquals(48, insets.getBottom(density))
    }

    @Test
    fun paneAwayFromTheCutoutDropsIt() {
        // Detail pane starting 1050 px from the left: the left camera never reaches it.
        assertEquals(0, PaneInsets(camera, leftGapPx = 1050, rightGapPx = 0).getLeft(density, LayoutDirection.Ltr))
        // Cutout on the right, list pane on the left with the detail pane beyond it.
        val right = WindowInsets(left = 0, top = 63, right = 142, bottom = 0)
        assertEquals(0, PaneInsets(right, leftGapPx = 0, rightGapPx = 1300).getRight(density, LayoutDirection.Rtl))
    }

    @Test
    fun partlyCoveredPaneKeepsTheOverlap() {
        // A 100 px rail covers part of a 142 px inset.
        assertEquals(42, PaneInsets(camera, leftGapPx = 100, rightGapPx = 0).getLeft(density, LayoutDirection.Ltr))
    }

    @Test
    fun valueSemantics() {
        val a = PaneInsets(camera, 1, 2)
        assertEquals(a, PaneInsets(camera, 1, 2))
        assertEquals(a.hashCode(), PaneInsets(camera, 1, 2).hashCode())
        assertNotEquals(a, PaneInsets(camera, 2, 1))
        assertNotEquals(a, camera)
        assertEquals(true, a.toString().contains("left gap=1"))
    }
}
