package com.festivalscoretracker.android.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.search.ShellShortcut
import com.festivalscoretracker.android.ui.shell.LocalPageFind
import com.festivalscoretracker.android.ui.shell.PageFindRegistry
import com.festivalscoretracker.android.ui.shell.RegisterPageFind
import com.festivalscoretracker.android.ui.shell.ShellShortcutBridge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Ctrl+F page-find registration and the activity → shell shortcut bridge. */
@RunWith(AndroidJUnit4::class)
class ShellKeyboardTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun latestPageFindWinsAndUnregistersOnDispose() {
        val registry = PageFindRegistry()
        val calls = mutableListOf<String>()
        var showSecond by mutableStateOf(true)
        rule.setContent {
            CompositionLocalProvider(LocalPageFind provides registry) {
                RegisterPageFind { calls += "songs" }
                if (showSecond) RegisterPageFind { calls += "rivals" }
            }
        }
        rule.runOnIdle { assertTrue(registry.find()) }
        rule.runOnIdle { showSecond = false }
        rule.runOnIdle { assertTrue(registry.find()) }
        assertEquals(listOf("rivals", "songs"), calls)
    }

    @Test
    fun emptyRegistryAndBridgeFallBack() {
        assertFalse(PageFindRegistry().find())
        val bridge = ShellShortcutBridge()
        assertFalse(bridge.dispatch(ShellShortcut.OpenSearch))
        bridge.handler = { it == ShellShortcut.FindInPage }
        assertTrue(bridge.dispatch(ShellShortcut.FindInPage))
        assertFalse(bridge.dispatch(ShellShortcut.OpenSearch))
    }
}
