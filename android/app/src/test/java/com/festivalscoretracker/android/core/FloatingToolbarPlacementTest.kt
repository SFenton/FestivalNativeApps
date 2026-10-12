package com.festivalscoretracker.android.core

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import com.festivalscoretracker.android.core.shell.FloatingToolbarPlacement
import com.festivalscoretracker.android.core.shell.PxSpan
import com.festivalscoretracker.android.core.shell.ToolbarInsets
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The floating toolbar stays in its page's pane, off the side system bars and on one side of a
 * hinge (#576), and the latest page to register it owns its tools and reading order.
 */
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
        // A list pane is 80..440 of the content 80..1280; the detail pane has no tools.
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

    @Test
    fun latestToolbarOwnerShowsItsToolsAndTheEarlierOwnerTakesThemBack() {
        val host = FloatingToolbarHost()
        val songsTools: @Composable RowScope.() -> Unit = {}
        val detailTools: @Composable RowScope.() -> Unit = {}
        assertNull(host.current)
        // Every page's toolbar stays on screen while it scrolls (R7, issues #52, #577); the entering
        // page owns the one toolbar and the previous page takes it back when it returns.
        val songs = host.register(mutableStateOf(songsTools))
        assertTrue(host.current === songsTools)
        val detail = host.register(mutableStateOf(detailTools))
        assertTrue(host.current === detailTools)
        detail()
        assertTrue(host.current === songsTools)
        songs()
        assertNull(host.current)
    }

    @Test
    fun latestToolbarOwnerDecidesWhetherItReadsFirst() {
        val host = FloatingToolbarHost()
        val content = mutableStateOf<@Composable RowScope.() -> Unit>({})
        assertFalse(host.readFirst)
        // Suggestions' endless feed reads its toolbar first (issue #112); a pushed page does not.
        val suggestions = host.register(content, readFirst = true)
        assertTrue(host.readFirst)
        val detail = host.register(content)
        assertFalse(host.readFirst)
        detail()
        assertTrue(host.readFirst)
        suggestions()
        assertFalse(host.readFirst)
    }
}
