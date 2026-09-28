package com.festivalscoretracker.android.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf
import com.festivalscoretracker.android.core.search.ShellShortcut

// region Shortcut bridge

/**
 * Hands activity-level key shortcuts (`MainActivity.dispatchKeyEvent`, which sees keys even
 * when nothing in Compose has focus) to the shell that is currently composed.
 */
class ShellShortcutBridge {
    /** Current handler; returns true when it consumed the shortcut. */
    var handler: ((ShellShortcut) -> Boolean)? = null

    /**
     * Dispatch a shortcut.
     *
     * @param shortcut Resolved shortcut.
     * @return True when the shell handled it.
     */
    fun dispatch(shortcut: ShellShortcut): Boolean = handler?.invoke(shortcut) ?: false
}

// endregion

// region Page find

/**
 * Page-local find handlers for Ctrl+F (Songs filter, Find Rival…). The most recently
 * registered handler wins; with none, Ctrl+F falls back to global search.
 */
class PageFindRegistry {
    private val handlers = mutableListOf<() -> Unit>()

    /**
     * Register a handler.
     *
     * @param handler Focuses the page's own find field.
     * @return Unregister callback.
     */
    fun register(handler: () -> Unit): () -> Unit {
        handlers += handler
        return { handlers.remove(handler) }
    }

    /**
     * Run the current page's find.
     *
     * @return False when no page registered one.
     */
    fun find(): Boolean {
        val handler = handlers.lastOrNull() ?: return false
        handler()
        return true
    }
}

/** Page-find registry for the current shell. */
val LocalPageFind = staticCompositionLocalOf { PageFindRegistry() }

/**
 * Register this screen's own find (Ctrl+F) while it is composed, e.g.
 * `RegisterPageFind { focusRequester.requestFocus() }` in the Songs filter.
 *
 * @param onFind Focus the page's find field.
 */
@Composable
fun RegisterPageFind(onFind: () -> Unit) {
    val registry = LocalPageFind.current
    val current = rememberUpdatedState(onFind)
    DisposableEffect(registry) {
        val unregister = registry.register { current.value() }
        onDispose { unregister() }
    }
}

// endregion
