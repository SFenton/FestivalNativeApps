package com.festivalscoretracker.android.core

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import com.festivalscoretracker.android.core.shell.FloatingToolbarPlacement
import com.festivalscoretracker.android.core.shell.PxSpan
import com.festivalscoretracker.android.core.shell.ToolbarInsets
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The floating toolbar stays in its page's pane, off the side system bars and on one side of a hinge (#576). */
class FloatingToolbarPlacementTest {
    private val margin = 16

    private fun insets(content: PxSpan, pane: PxSpan? = null, safe: PxSpan = PxSpan(0, 2000), hinge: PxSpan? = null, rtl: Boolean = false) =
        FloatingToolbarPlacement.insets(content, pane, safe, hinge, rtl, margin)

    @Test
    fun phonePortraitKeepsTheMargins() {
        assertEquals(ToolbarInsets(16, 16), insets(PxSpan(0, 412), pane = PxSpan(0, 412), safe = PxSpan(0, 412)))
    }

    @Test
    fun landscapePhoneClearsTheCutoutAndSideNavigationBar() {
        // Rail on the left (content from 80), camera and three-button navigation on the right (safe to 860).
        assertEquals(ToolbarInsets(16, 40 + 16), insets(PxSpan(80, 900), pane = PxSpan(80, 900), safe = PxSpan(40, 860)))
    }

    @Test
    fun splitKeepsTheToolbarOverTheOwningPane() {
        // Songs' list pane is 80..440 of the content 80..1280; the detail pane has no tools.
        assertEquals(ToolbarInsets(16, 1280 - 440 + 16), insets(PxSpan(80, 1280), pane = PxSpan(80, 440)))
    }

    @Test
    fun aHingeAcrossThePaneMovesTheToolbarToItsEndSide() {
        val hinge = PxSpan(900, 930)
        assertEquals(ToolbarInsets(930 - 80 + 16, 16), insets(PxSpan(80, 1800), pane = PxSpan(80, 1800), hinge = hinge))
        assertEquals(ToolbarInsets(16, 1800 - 900 + 16), insets(PxSpan(80, 1800), pane = PxSpan(80, 1800), hinge = hinge, rtl = true))
        // A zero-width separating fold counts too.
        assertEquals(ToolbarInsets(840 + 16, 16), insets(PxSpan(0, 1800), hinge = PxSpan(840, 840)))
    }

    @Test
    fun aHingeOutsideThePaneChangesNothing() {
        // The list pane ends at the hinge, so its toolbar stays in the pane.
        assertEquals(ToolbarInsets(16, 1800 - 900 + 16), insets(PxSpan(0, 1800), pane = PxSpan(0, 900), hinge = PxSpan(900, 930)))
    }

    @Test
    fun aStalePaneFallsBackToTheContentArea() {
        assertEquals(ToolbarInsets(16, 16), insets(PxSpan(0, 412), pane = PxSpan(500, 900), safe = PxSpan(0, 412)))
        assertEquals(ToolbarInsets(16, 16), insets(PxSpan(0, 412), pane = null, safe = PxSpan(0, 412)))
    }

    @Test
    fun latestOwnerDecidesThePane() {
        val host = FloatingToolbarHost()
        val content = mutableStateOf<@Composable RowScope.() -> Unit>({})
        val songsPane = mutableStateOf<PxSpan?>(PxSpan(0, 400))
        assertNull(host.pane)
        val songs = host.register(content, pane = songsPane)
        assertEquals(PxSpan(0, 400), host.pane)
        songsPane.value = PxSpan(0, 420)
        assertEquals(PxSpan(0, 420), host.pane)
        val detail = host.register(content)
        assertNull(host.pane)
        detail()
        assertEquals(PxSpan(0, 420), host.pane)
        songs()
        assertNull(host.pane)
    }
}
