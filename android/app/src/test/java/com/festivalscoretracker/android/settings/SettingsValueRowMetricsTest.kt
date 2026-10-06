package com.festivalscoretracker.android.settings

import com.festivalscoretracker.android.ui.settings.SettingsValueRowMetrics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The canonical Settings value row's fit rule and metrics (pattern `settings-value-row`). */
class SettingsValueRowMetricsTest {
    @Test
    fun inlineOnlyWhenTitleGapAndValueFit() {
        assertTrue(SettingsValueRowMetrics.fitsInline(titleWidth = 200, trailingWidth = 100, gap = 12, available = 312))
        assertFalse(SettingsValueRowMetrics.fitsInline(titleWidth = 200, trailingWidth = 100, gap = 12, available = 311))
        // A value wider than the whole row always stacks.
        assertFalse(SettingsValueRowMetrics.fitsInline(titleWidth = 0, trailingWidth = 400, gap = 12, available = 300))
    }

    @Test
    fun metricsMatchThePatternRules() {
        assertEquals(12f, SettingsValueRowMetrics.INLINE_GAP.value)
        assertEquals(4f, SettingsValueRowMetrics.LINE_GAP.value)
        assertEquals(48f, SettingsValueRowMetrics.MIN_HEIGHT.value)
        assertEquals(56f, SettingsValueRowMetrics.MIN_HEIGHT_WITH_SUPPORTING.value)
    }
}
