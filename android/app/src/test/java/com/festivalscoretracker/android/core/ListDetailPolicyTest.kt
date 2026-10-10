package com.festivalscoretracker.android.core

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import com.festivalscoretracker.android.core.shell.ListDetailLayout
import com.festivalscoretracker.android.core.shell.ListDetailPolicy
import com.festivalscoretracker.android.core.shell.ListHead
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Two populated columns (operator 2026-09-28) and the floating toolbar's registrations. */
class ListDetailPolicyTest {
    private val loaded = ListHead(loaded = true, firstId = "first")

    @Test
    fun compactWindowsKeepOneList() {
        assertEquals(ListDetailLayout.SingleList, ListDetailPolicy.layout(twoPane = false, hingeSplit = false, selectedId = "x", head = loaded))
    }

    @Test
    fun splitShowsTheLastPickElseTheFirstRow() {
        assertEquals(ListDetailLayout.Split("x"), ListDetailPolicy.layout(true, false, "x", loaded))
        assertEquals(ListDetailLayout.Split("first"), ListDetailPolicy.layout(true, false, null, loaded))
        // Still loading: split with a spinner in the detail pane, never a prompt.
        assertEquals(ListDetailLayout.Split(null), ListDetailPolicy.layout(true, false, null, ListHead()))
    }

    @Test
    fun emptyListCollapsesExceptAcrossAHinge() {
        val empty = ListHead(loaded = true, firstId = null)
        assertEquals(ListDetailLayout.SingleList, ListDetailPolicy.layout(true, false, null, empty))
        assertEquals(ListDetailLayout.Split(null), ListDetailPolicy.layout(true, true, null, empty))
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
