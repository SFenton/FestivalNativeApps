package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.ListDetailLayout
import com.festivalscoretracker.android.core.shell.ListDetailPolicy
import com.festivalscoretracker.android.core.shell.ListHead
import com.festivalscoretracker.android.ui.common.FloatingToolbarScrollState
import org.junit.Assert.assertEquals
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
}
