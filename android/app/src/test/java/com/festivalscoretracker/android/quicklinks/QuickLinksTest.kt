package com.festivalscoretracker.android.quicklinks

import com.festivalscoretracker.android.core.quicklinks.QuickLinkFrame
import com.festivalscoretracker.android.core.quicklinks.QuickLinkPhase
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinkTracker
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickLinksTest {
    private val sections = listOf("a", "b", "c", "d").map { QuickLinkSection(it, it.uppercase()) }
    private fun frames(vararg tops: Pair<String, Float>) = tops.associate { (id, top) -> id to QuickLinkFrame(top, top + 300) }

    @Test
    fun pureRules() {
        assertFalse(QuickLinks.isAvailable(1))
        assertTrue(QuickLinks.isAvailable(2))
        assertTrue(QuickLinks.usesSheet(411))
        assertFalse(QuickLinks.usesSheet(700))
        assertEquals(listOf("a", "b"), QuickLinks.ordered(listOf(QuickLinkSection("a", "A"), QuickLinkSection("b", "B"), QuickLinkSection("a", "Z"))).map { it.id })
        assertTrue(QuickLinks.isVisible(QuickLinkFrame(-10f, 5f), 100f))
        assertFalse(QuickLinks.isVisible(QuickLinkFrame(-10f, 0f), 100f))
        assertFalse(QuickLinks.isVisible(QuickLinkFrame(100f, 200f), 100f))
        assertFalse(QuickLinks.isVisible(null, 100f))
        assertTrue(QuickLinks.isReachable(QuickLinkFrame(-96f, 0f), 16f, 96f))
        assertFalse(QuickLinks.isReachable(QuickLinkFrame(113f, 200f), 16f, 96f))
        assertThrows(IllegalArgumentException::class.java) { QuickLinkFrame(5f, 1f) }
        assertEquals("fst.quick-links.item.a", sections[0].testTag)
        assertEquals("Spoken", QuickLinkSection("x", "X", spokenTitle = "Spoken").accessibleTitle)
        assertEquals("X", QuickLinkSection("x", "X").accessibleTitle)
    }

    @Test
    fun hingeSplitKeepsRowsOffTheFold() {
        assertEquals(938f to 20f, QuickLinks.hingeSplit(100f, 2000f, 1038f, 1058f))
        assertNull(QuickLinks.hingeSplit(1100f, 900f, 1038f, 1058f))
        assertNull(QuickLinks.hingeSplit(0f, 1000f, 1038f, 1058f))
        assertNull(QuickLinks.hingeSplit(0f, 2000f, 1058f, 1038f))
    }

    @Test
    fun naturalActiveSkipsUnknownAndStopsPastTheLine() {
        assertNull(QuickLinks.naturalActive(emptyList(), emptyMap(), 16f))
        assertEquals("a", QuickLinks.naturalActive(sections, frames("a" to 100f, "b" to 400f), 16f))
        assertEquals("b", QuickLinks.naturalActive(sections, frames("b" to -20f, "c" to 17.5f), 16f))
        assertEquals("c", QuickLinks.naturalActive(sections, frames("b" to -500f, "c" to 17f - 0.5f, "d" to 300f), 16f))
    }

    @Test
    fun jumpOwnershipAndRelease() {
        val tracker = QuickLinkTracker()
        tracker.update(sections, frames("a" to 0f, "b" to 300f), 800f)
        assertEquals("a", tracker.activeId)

        tracker.beginJump("c")
        assertEquals(QuickLinkPhase.Scrolling, tracker.phase)
        tracker.update(sections, frames("a" to -200f), 800f)
        assertEquals("c", tracker.activeId)

        // Landed at the top: owned; small drift holds, leaving the band releases.
        tracker.settle(sections, frames("b" to -300f, "c" to 0f, "d" to 300f), 800f)
        assertEquals(QuickLinkPhase.Owned, tracker.phase)
        tracker.update(sections, frames("b" to -300f, "c" to 5f, "d" to 305f), 800f)
        assertEquals("c", tracker.activeId)
        tracker.update(sections, frames("c" to -250f, "d" to 50f), 800f)
        assertEquals(QuickLinkPhase.Idle, tracker.phase)
        assertEquals("c", tracker.activeId)
        tracker.update(sections, frames("d" to 0f), 800f)
        assertEquals("d", tracker.activeId)

        // Near the end: the target cannot reach the top, so it stays active while visible.
        tracker.beginJump("c")
        tracker.settle(sections, frames("c" to 400f, "d" to 700f), 800f)
        tracker.update(sections, frames("c" to 380f, "d" to 680f), 800f)
        assertEquals("c", tracker.activeId)
        tracker.update(sections, frames("d" to -100f), 800f)
        assertEquals(QuickLinkPhase.Idle, tracker.phase)

        // A vanished target releases in every phase.
        tracker.beginJump("x")
        tracker.update(sections, frames("a" to 0f), 800f)
        assertEquals(QuickLinkPhase.Idle, tracker.phase)
        tracker.beginJump("b")
        tracker.settle(sections, frames("a" to 0f), 800f)
        assertEquals(QuickLinkPhase.Idle, tracker.phase)
        assertEquals("a", tracker.activeId)
        tracker.beginJump("b")
        tracker.settle(sections, frames("b" to 0f), 800f)
        tracker.update(sections.take(1), frames("a" to 0f), 800f)
        assertEquals(QuickLinkPhase.Idle, tracker.phase)
        tracker.settle(sections, emptyMap(), 800f) // not scrolling: no-op
        assertEquals(QuickLinkPhase.Idle, tracker.phase)
    }
}
