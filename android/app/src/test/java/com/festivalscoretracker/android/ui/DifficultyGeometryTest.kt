package com.festivalscoretracker.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Host-side seven-bar frame and bounds checks. */
class DifficultyGeometryTest {
    @Test fun sevenBarsFitExactlyInTheBrandedFrame() {
        assertEquals(7, DifficultyGeometry.heights.size)
        assertEquals(5f, DifficultyGeometry.bar(0).second.height)
        assertEquals(20f, DifficultyGeometry.bar(6).second.height)
        val (lastOffset, lastSize) = DifficultyGeometry.bar(6)
        assertEquals(62f, lastOffset.x + lastSize.width, 0.0001f)
        assertEquals(20f, lastOffset.y + lastSize.height, 0.0001f)
    }

    @Test fun invalidIndexIsRejected() {
        assertThrows(IllegalArgumentException::class.java) { DifficultyGeometry.bar(7) }
    }
}
