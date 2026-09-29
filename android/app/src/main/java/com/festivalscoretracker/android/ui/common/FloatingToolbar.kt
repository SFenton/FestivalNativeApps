package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Slot

/**
 * The shell's floating-toolbar slot (M3 Expressive floating toolbar; Material 3 1.4 stable has
 * no public `HorizontalFloatingToolbar`, so this is the equivalent pill: 64 dp, fully rounded,
 * elevated, floating 16 dp above the bottom bar).
 *
 * Pages do **not** call this directly: on compact windows [FestivalScreen] moves its `actions`
 * (Quick Links, Sort, Filter, …) plus global search here; on medium and wider windows the same
 * actions stay in the top app bar. A screen outside [FestivalScreen] can use [FloatingToolbarContent].
 * The most recently composed registration wins, so the entering screen owns the toolbar during a
 * navigation transition and the previous screen takes it back when it returns.
 */
@Stable
class FloatingToolbarHost {
    private class Entry(val content: State<@Composable RowScope.() -> Unit>)

    private val entries = mutableStateListOf<Entry>()

    /** Content to show, or null when no screen registered actions. */
    val current: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.content?.value

    /**
     * Register toolbar content.
     *
     * @param content Latest content (read on every recomposition).
     * @return Unregister callback.
     */
    fun register(content: State<@Composable RowScope.() -> Unit>): () -> Unit {
        val entry = Entry(content)
        entries += entry
        return { entries.remove(entry) }
    }
}

/**
 * Put [content] in the shell's floating toolbar while this composable is composed (no-op when
 * the window uses top-app-bar actions, i.e. `LocalShellActions.current.floatingToolbar == null`).
 *
 * @param content Toolbar items, typically `IconButton`s; global search is not added automatically here.
 */
@Composable
fun FloatingToolbarContent(content: @Composable RowScope.() -> Unit) {
    val host = LocalShellActions.current.floatingToolbar ?: return
    val latest = rememberUpdatedState(content)
    DisposableEffect(host) {
        val unregister = host.register(latest)
        onDispose { unregister() }
    }
}

// endregion

// region Toolbar

/** Floating toolbar height (M3 Expressive). */
const val FLOATING_TOOLBAR_HEIGHT_DP = 64

/** Gap between the toolbar and the bottom bar. */
const val FLOATING_TOOLBAR_MARGIN_DP = 16

/**
 * The floating toolbar surface the shell draws over the bottom bar.
 *
 * @param host Registered content.
 * @param modifier Placement (bottom centre of the content area).
 */
@Composable
fun FloatingToolbar(host: FloatingToolbarHost, modifier: Modifier = Modifier) {
    val content = host.current ?: return
    // A page whose actions are all conditional (or none) registers empty content: measure it but
    // place nothing, so no empty pill draws or blocks touches.
    var hasContent by remember { mutableStateOf(true) }
    Surface(
        shape = CircleShape,
        color = BrandTokens.cardBackground.copy(alpha = 0.97f),
        contentColor = BrandTokens.textPrimary,
        border = BorderStroke(1.dp, BrandTokens.glassBorder),
        shadowElevation = 6.dp,
        modifier = modifier
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                if (hasContent) layout(placeable.width, placeable.height) { placeable.place(0, 0) } else layout(0, 0) {}
            }
            .heightIn(min = FLOATING_TOOLBAR_HEIGHT_DP.dp)
            .testTag("fst.nav.floating-toolbar")
            // Read after the page content, before the bottom bar.
            .semantics { isTraversalGroup = true; traversalIndex = 1f },
    ) {
        CompositionLocalProvider(LocalContentColor provides BrandTokens.textPrimary) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.onSizeChanged { hasContent = it.width > 0 },
                    content = content,
                )
            }
        }
    }
}

// endregion
