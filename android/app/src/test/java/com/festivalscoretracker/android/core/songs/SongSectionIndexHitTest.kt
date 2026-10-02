package com.festivalscoretracker.android.core.songs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Section-index rail hit mapping when labels are sampled (issue #48). */
class SongSectionIndexHitTest {
    /** #, A–Z: the mock service's `--large-catalogue` sections. */
    private val count = 27
    private val p = 16
    private val v = 22

    /** Centre of drawn label [k] on a rail with [labels] equal slots. */
    private fun centre(k: Int, labels: Int) = (k + 0.5f) / labels

    @Test
    fun strideSamplesOnlyWhenLabelsDoNotFit() {
        assertEquals(1, SongSectionIndex.stride(count, 30))
        assertEquals(1, SongSectionIndex.stride(count, 27))
        assertEquals(2, SongSectionIndex.stride(count, 14))
        assertEquals(3, SongSectionIndex.stride(count, 9))
        assertEquals(count, SongSectionIndex.stride(count, 0))
        assertEquals(1, SongSectionIndex.stride(0, 5))
    }

    @Test
    fun everyLabelDrawn_matchesTheProportionalMapping() {
        for (step in 0..1000) {
            val fraction = step / 1000f
            val expected = (fraction * count).toInt().coerceIn(0, count - 1)
            assertEquals("fraction $fraction", expected, SongSectionIndex.sectionAt(fraction, count, 1))
        }
        assertEquals(p, SongSectionIndex.sectionAt(centre(p, count), count, 1))
    }

    @Test
    fun sampledLabels_openTheirOwnSection() {
        // Font scale 2 on a phone drew #, B, D … Z; tapping # opened A, B opened C and V opened U.
        val labels = 14
        for (k in 0 until labels) {
            for (offset in listOf(-0.34f, 0f, 0.34f)) {
                val fraction = (k + 0.5f + offset) / labels
                assertEquals("label $k offset $offset", k * 2, SongSectionIndex.sectionAt(fraction, count, 2, labelHalf = 0.35f))
            }
        }
        assertEquals(0, SongSectionIndex.sectionAt(centre(0, labels), count, 2))
        assertEquals(p, SongSectionIndex.sectionAt(centre(p / 2, labels), count, 2))
        assertEquals(v, SongSectionIndex.sectionAt(centre(v / 2, labels), count, 2))
        assertEquals(count - 1, SongSectionIndex.sectionAt(centre(labels - 1, labels), count, 2))
    }

    @Test
    fun farJump_hashToP_landsOnP_atEveryStride() {
        for (stride in listOf(1, 2, 4, 8)) {
            if (p % stride != 0) continue
            val labels = (count + stride - 1) / stride
            assertEquals("stride $stride", p, SongSectionIndex.sectionAt(centre(p / stride, labels), count, stride))
        }
    }

    @Test
    fun gapsBetweenLabels_reachTheSkippedSections() {
        val labels = 9
        // Between # (0) and C (3) lie A and B.
        assertEquals(1, SongSectionIndex.sectionAt((0.5f + 0.4f) / labels, count, 3))
        assertEquals(2, SongSectionIndex.sectionAt((0.5f + 0.6f) / labels, count, 3))
        // Below the last label (X = 24): Y and Z.
        assertEquals(24, SongSectionIndex.sectionAt(centre(8, labels), count, 3))
        assertEquals(26, SongSectionIndex.sectionAt(1f, count, 3))
        assertEquals(0, SongSectionIndex.sectionAt(0f, count, 3))
    }

    @Test
    fun dragging_reachesEverySectionInOrder() {
        for (stride in 1..6) {
            val seen = sortedSetOf<Int>()
            var previous = 0
            for (step in 0..4000) {
                val index = SongSectionIndex.sectionAt(step / 4000f, count, stride, labelHalf = 0.3f)
                assertTrue("stride $stride monotonic at $step", index >= previous)
                previous = index
                seen += index
            }
            assertEquals("stride $stride", (0 until count).toSet(), seen)
        }
    }

    @Test
    fun edgeCases() {
        assertEquals(0, SongSectionIndex.sectionAt(0.5f, 0, 2))
        assertEquals(0, SongSectionIndex.sectionAt(-1f, count, 2))
        assertEquals(count - 1, SongSectionIndex.sectionAt(2f, count, 2))
        assertEquals(0, SongSectionIndex.sectionAt(0.9f, 1, 1))
        assertEquals(1, SongSectionIndex.sectionAt(0.9f, 2, 0))
    }
}
