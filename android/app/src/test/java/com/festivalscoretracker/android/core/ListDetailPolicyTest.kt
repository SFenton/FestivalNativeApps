package com.festivalscoretracker.android.core

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import com.festivalscoretracker.android.core.shell.ListDetailLayout
import com.festivalscoretracker.android.core.shell.ListDetailPolicy
import com.festivalscoretracker.android.core.shell.ListHead
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import com.festivalscoretracker.android.ui.common.FloatingToolbarScrollState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Two populated columns (operator 2026-09-28) and the floating toolbar's hide-on-scroll. */
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
    fun toolbarFollowsTheScrollAndResets() {
        val state = FloatingToolbarScrollState().apply { hiddenOffsetPx = 100f }
        state.onScrolled(-40f)
        assertEquals(40f, state.offsetPx)
        state.onScrolled(-500f)
        assertEquals(100f, state.offsetPx)
        state.onScrolled(30f)
        assertEquals(70f, state.offsetPx)
        state.reset()
        assertEquals(0f, state.offsetPx)
        // Disabled (TalkBack): never hides.
        state.enabled = false
        state.onScrolled(-50f)
        assertEquals(0f, state.offsetPx)
    }

    @Test
    fun latestToolbarOwnerDecidesWhetherItIsPinned() {
        val host = FloatingToolbarHost()
        val content = mutableStateOf<@Composable RowScope.() -> Unit>({})
        assertFalse(host.pinned)
        // Songs pins its toolbar (issue #52); a pushed detail page does not.
        val songs = host.register(content, pinned = true)
        assertTrue(host.pinned)
        val detail = host.register(content)
        assertFalse(host.pinned)
        detail()
        assertTrue(host.pinned)
        songs()
        assertFalse(host.pinned)
        assertNull(host.current)
    }

    @Test
    fun leadingPillFollowsTheLatestToolbarOwner() {
        // Issue #89: Songs registers its search as a separate leading pill; a page pushed over it
        // with only actions shows no leading pill, and Songs gets its search back on return.
        val host = FloatingToolbarHost()
        val content = mutableStateOf<@Composable RowScope.() -> Unit>({})
        val search: @Composable RowScope.() -> Unit = {}
        val leading = mutableStateOf<(@Composable RowScope.() -> Unit)?>(search)
        assertNull(host.currentLeading)
        val songs = host.register(content, pinned = true, leading = leading)
        assertSame(search, host.currentLeading)
        val detail = host.register(content)
        assertNull(host.currentLeading)
        detail()
        assertSame(search, host.currentLeading)
        // A wider window drops the leading control without re-registering.
        leading.value = null
        assertNull(host.currentLeading)
        songs()
        assertNull(host.currentLeading)
    }
}
