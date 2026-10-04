package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.animateContentSize
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

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
    private class Entry(
        val content: State<@Composable RowScope.() -> Unit>,
        val pinned: Boolean,
        val aboveKeyboard: State<Boolean>,
        val readFirst: Boolean,
    )

    private val entries = mutableStateListOf<Entry>()

    /** Content to show, or null when no screen registered actions. */
    val current: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.content?.value

    /** Whether the current owner keeps the toolbar on screen while its content scrolls. */
    val pinned: Boolean get() = entries.lastOrNull()?.pinned == true

    /** Whether the current owner holds a focused text field, so the toolbar rides above the keyboard. */
    val aboveKeyboard: Boolean get() = entries.lastOrNull()?.aboveKeyboard?.value == true

    /**
     * Whether the current owner's toolbar is read by TalkBack/keyboard right after the top app bar
     * instead of after the page content (an endless feed would otherwise never reach it, issue #112).
     */
    val readFirst: Boolean get() = entries.lastOrNull()?.readFirst == true

    /**
     * Register toolbar content.
     *
     * @param content Latest content (read on every recomposition).
     * @param pinned Keep the toolbar visible while content scrolls (no hide on scroll).
     * @param aboveKeyboard Latest "content holds a focused text field" flag (Songs search, issue #84).
     * @param readFirst Read the toolbar before the page content rather than after it.
     * @return Unregister callback.
     */
    fun register(
        content: State<@Composable RowScope.() -> Unit>,
        pinned: Boolean = false,
        aboveKeyboard: State<Boolean> = NOT_ABOVE_KEYBOARD,
        readFirst: Boolean = false,
    ): () -> Unit {
        val entry = Entry(content, pinned, aboveKeyboard, readFirst)
        entries += entry
        return { entries.remove(entry) }
    }

    private companion object {
        val NOT_ABOVE_KEYBOARD: State<Boolean> = mutableStateOf(false)
    }
}

/**
 * Put [content] in the shell's floating toolbar while this composable is composed (no-op when
 * the window uses top-app-bar actions, i.e. `LocalShellActions.current.floatingToolbar == null`).
 *
 * @param pinned Keep the toolbar on screen while the page scrolls (M3 "always visible" floating
 *   toolbar) instead of the default hide on scroll.
 * @param aboveKeyboard The content holds a focused text field: the shell lifts the toolbar above
 *   the on-screen keyboard while this is true.
 * @param readFirst TalkBack and keyboard focus reach the toolbar right after the top app bar,
 *   before the page content (for pages whose content is an endless feed, issue #112).
 * @param content Toolbar items, typically `IconButton`s; global search is not added automatically here.
 */
@Composable
fun FloatingToolbarContent(
    pinned: Boolean = false,
    aboveKeyboard: Boolean = false,
    readFirst: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    val host = LocalShellActions.current.floatingToolbar ?: return
    val latest = rememberUpdatedState(content)
    val keyboard = rememberUpdatedState(aboveKeyboard)
    DisposableEffect(host, pinned, readFirst) {
        val unregister = host.register(latest, pinned, keyboard, readFirst)
        onDispose { unregister() }
    }
}

// endregion

// region Hide on scroll

/**
 * M3 floating-toolbar "exit always" scroll behaviour: the toolbar slides off the bottom edge as
 * content scrolls toward its end and slides back as soon as it scrolls back, following the
 * finger. Attach [connection] (a nested-scroll connection) to an ancestor of the scrolling
 * pages; only [offsetPx] changes, and it is read in the toolbar's graphics layer, so scrolling
 * never recomposes the toolbar. Disabled while [enabled] is false (TalkBack: a hidden toolbar
 * would be unreachable by explore-by-touch).
 */
@Stable
class FloatingToolbarScrollState {
    /** Current downward offset in pixels (0 = fully shown). */
    var offsetPx by mutableFloatStateOf(0f)
        private set

    /** Offset that fully hides the toolbar (its height plus the bottom margin). */
    var hiddenOffsetPx by mutableFloatStateOf(0f)

    /** Whether scrolling may hide the toolbar. */
    var enabled by mutableStateOf(true)

    /**
     * Follow one scroll step.
     *
     * @param consumedY Pixels the content scrolled (negative = toward the end of the content).
     */
    fun onScrolled(consumedY: Float) {
        offsetPx = if (!enabled) 0f else (offsetPx - consumedY).coerceIn(0f, hiddenOffsetPx)
    }

    /** Show the toolbar again at once (new page, accessibility on). */
    fun reset() {
        offsetPx = 0f
    }

    /** Nested-scroll connection feeding [onScrolled] with the scroll the content consumed. */
    val connection: NestedScrollConnection = object : NestedScrollConnection {
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            onScrolled(consumed.y)
            return Offset.Zero
        }
    }
}

// endregion

// region Toolbar

/** Floating toolbar height (M3 Expressive). */
const val FLOATING_TOOLBAR_HEIGHT_DP = 64

/** Gap between the toolbar and the bottom bar. */
const val FLOATING_TOOLBAR_MARGIN_DP = 16

/** Traversal index of a read-first toolbar: after the top app bar, before the page content (0). */
const val TOOLBAR_READ_FIRST_TRAVERSAL_INDEX = -1f

/** Traversal index of the top app bar while the page's toolbar reads first, so the bar still leads. */
const val TOP_BAR_TRAVERSAL_INDEX = -2f

/**
 * The floating toolbar surface the shell draws over the bottom bar.
 *
 * @param host Registered content.
 * @param modifier Placement (bottom centre of the content area).
 * @param scroll Hide-on-scroll state; null keeps the toolbar fixed.
 */
@Composable
fun FloatingToolbar(host: FloatingToolbarHost, modifier: Modifier = Modifier, scroll: FloatingToolbarScrollState? = null) {
    val content = host.current ?: return
    // A page whose actions are all conditional (or none) registers empty content: measure it but
    // place nothing, so no empty pill draws or blocks touches.
    var hasContent by remember { mutableStateOf(true) }
    // Content that changes width (Songs search minimizing to an icon, issue #84) resizes smoothly;
    // reduced motion snaps.
    val resize = if (LocalFestivalAccessibility.current.reduceMotion) Modifier else Modifier.animateContentSize()
    Surface(
        shape = CircleShape,
        color = BrandTokens.cardBackground.copy(alpha = 0.97f),
        contentColor = BrandTokens.textPrimary,
        border = BorderStroke(1.dp, BrandTokens.glassBorder),
        shadowElevation = 6.dp,
        modifier = modifier
            .then(if (scroll != null) Modifier.graphicsLayer { translationY = scroll.offsetPx } else Modifier)
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                if (hasContent) layout(placeable.width, placeable.height) { placeable.place(0, 0) } else layout(0, 0) {}
            }
            .heightIn(min = FLOATING_TOOLBAR_HEIGHT_DP.dp)
            .testTag("fst.nav.floating-toolbar")
            // Read after the page content, before the bottom bar; or, for an endless feed, between
            // the top app bar (FestivalScreen gives it TOP_BAR_TRAVERSAL_INDEX) and the content.
            .semantics { isTraversalGroup = true; traversalIndex = if (host.readFirst) TOOLBAR_READ_FIRST_TRAVERSAL_INDEX else 1f },
    ) {
        CompositionLocalProvider(LocalContentColor provides BrandTokens.textPrimary) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = resize.padding(horizontal = 8.dp, vertical = 8.dp),
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
