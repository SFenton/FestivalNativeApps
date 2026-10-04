package com.festivalscoretracker.android.ui.shell

import com.festivalscoretracker.android.core.nav.FestivalSection
import org.junit.Assert.assertEquals
import org.junit.Test

/** Navigation icons follow M3: filled for the active destination, outlined otherwise (issue #132). */
class SectionIconTest {
    @Test
    fun activeSectionsUseFilledIconsAndInactiveOnesOutlined() {
        FestivalSection.entries.forEach { section ->
            assertEquals("Filled", section.icon(selected = true).name.substringBefore('.'))
            assertEquals("Outlined", section.icon(selected = false).name.substringBefore('.'))
            assertEquals(section.icon(true).name.substringAfter('.'), section.icon(false).name.substringAfter('.'))
            assertEquals(section.icon(false), section.icon())
        }
    }
}
