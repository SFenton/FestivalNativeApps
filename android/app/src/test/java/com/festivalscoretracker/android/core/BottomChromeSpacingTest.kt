package com.festivalscoretracker.android.core

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import com.festivalscoretracker.android.core.shell.BottomChromeSpacing
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pages end one standard gap above the bottom chrome actually shown: the floating toolbar while it
 * shows tools, else the bottom bar, never a band kept for an absent toolbar (issue #578).
 */
class BottomChromeSpacingTest {
    @Test
    fun withoutToolsAPageEndsOneGapAboveTheBottomBar() {
        // The song leaderboard without a profile: its pager rests 16 dp above the bottom bar.
        assertEquals(16f, BottomChromeSpacing.contentBottomDp(0f, 0f))
    }

    @Test
    fun withToolsAPageEndsOneGapAboveTheToolbar() {
        // Toolbar 16 dp above the bar, 64 dp tall, then one gap: the former fixed 96 dp band.
        assertEquals(96f, BottomChromeSpacing.contentBottomDp(0f, 64f))
        // A taller toolbar (large text) moves the end with it.
        assertEquals(16f + 80f + 16f, BottomChromeSpacing.contentBottomDp(0f, 80f))
    }

    @Test
    fun besideARailTheSystemNavigationBarIsClearedFirst() {
        assertEquals(48f + 16f, BottomChromeSpacing.contentBottomDp(48f, 0f))
        assertEquals(48f + 96f, BottomChromeSpacing.contentBottomDp(48f, 64f))
    }

    @Test
    fun aRegistrationStartsFromItsExpectedHeightAndKeepsItsLastDrawnOne() {
        val host = FloatingToolbarHost()
        val content = mutableStateOf<@Composable RowScope.() -> Unit>({})
        val unknown = host.register(content)
        assertNull(unknown.heightDp)
        val none = host.register(content, initialHeightDp = 0f)
        assertEquals(0f, none.heightDp)
        val tools = host.register(content, initialHeightDp = 64f)
        assertTrue(host.currentRegistration === tools)
        tools.heightDp = 72f
        // A covered page keeps its own height; the shell measures only the current owner.
        tools()
        assertTrue(host.currentRegistration === none)
        assertEquals(72f, tools.heightDp)
        assertEquals(0f, none.heightDp)
        none()
        unknown()
        assertNull(host.currentRegistration)
    }
}
