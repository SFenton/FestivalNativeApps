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
import com.festivalscoretracker.android.core.shell.PxSpan
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Slot

/**
 * The shell's floating-toolbar slot (M3 Expressive floating toolbar; Material 3 1.4 stable has
 * no public `HorizontalFloatingToolbar`, so this is the equivalent pill: 64 dp, fully rounded,
 * elevated, floating 16 dp above the bottom bar).
 *
 * Pages do **not** call this directly: at every window size [FestivalScreen] moves its `actions`
 * (Quick Links, Sort, Filter, …) here (`page-tools-and-nav-chrome` R4, owner-approved #576); global
 * search, the bell and Profile stay in the top app bar. A screen outside [FestivalScreen] can use
 * [FloatingToolbarContent].
 * The most recently composed registration wins, so the entering screen owns the toolbar during a
 * navigation transition and the previous screen takes it back when it returns.
 */
@Stable
class FloatingToolbarHost {
    private class Entry(
        val content: State<@Composable RowScope.() -> Unit>,
        val pinned: Boolean,
        val readFirst: Boolean,
        val pane: State<PxSpan?>?,
    )

    private val entries = mutableStateListOf<Entry>()

    /** Content to show, or null when no screen registered actions. */
    val current: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.content?.value

    /** Whether the current owner keeps the toolbar on screen while its content scrolls. */
    val pinned: Boolean get() = entries.lastOrNull()?.pinned == true

    /**
     * Whether the current owner's toolbar is read by TalkBack/keyboard right after the top app bar
     * instead of after the page content (an endless feed would otherwise never reach it, issue #112).
     */
    val readFirst: Boolean get() = entries.lastOrNull()?.readFirst == true

    /** The current owner's pane in window pixels, or null for the whole content area. */
    val pane: PxSpan? get() = entries.lastOrNull()?.pane?.value

    /**
     * Register toolbar content.
     *
     * @param content Latest content (read on every recomposition).
     * @param pinned Keep the toolbar visible while content scrolls (no hide on scroll).
     * @param readFirst Read the toolbar before the page content rather than after it.
     * @param pane The owner's pane in window pixels (read on every layout), so the toolbar floats
     *   over that pane in a split; null for the whole content area.
     * @return Unregister callback.
     */
    fun register(
        content: State<@Composable RowScope.() -> Unit>,
        pinned: Boolean = false,
        readFirst: Boolean = false,
        pane: State<PxSpan?>? = null,
    ): () -> Unit {
        val entry = Entry(content, pinned, readFirst, pane)
        entries += entry
        return { entries.remove(entry) }
    }
}

/**
 * Put [content] in the shell's floating toolbar while this composable is composed (no-op outside
 * the shell, i.e. `LocalShellActions.current.floatingToolbar == null`).
 *
 * @param pinned Keep the toolbar on screen while the page scrolls (M3 "always visible" floating
 *   toolbar) instead of the default hide on scroll.
 * @param readFirst TalkBack and keyboard focus reach the toolbar right after the top app bar,
 *   before the page content (for pages whose content is an endless feed, issue #112).
 * @param pane The page's pane in window pixels, so the toolbar floats over it in a split; null for
 *   the whole content area.
 * @param content Toolbar items, typically `IconButton`s; global search is not added automatically here.
 */
@Composable
fun FloatingToolbarContent(
    pinned: Boolean = false,
    readFirst: Boolean = false,
    pane: State<PxSpan?>? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val host = LocalShellActions.current.floatingToolbar ?: return
    val latest = rememberUpdatedState(content)
    DisposableEffect(host, pinned, readFirst, pane) {
        val unregister = host.register(latest, pinned, readFirst, pane)
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

/** Gap between the toolbar and the bottom bar (or the window's bottom safe edge beside a rail or drawer). */
const val FLOATING_TOOLBAR_MARGIN_DP = 16

/** Traversal index of a read-first toolbar: after the top app bar, before the page content (0). */
const val TOOLBAR_READ_FIRST_TRAVERSAL_INDEX = -1f

/** Traversal index of the top app bar while the page's toolbar reads first, so the bar still leads. */
const val TOP_BAR_TRAVERSAL_INDEX = -2f

/**
 * The floating toolbar surface the shell draws at the bottom end of the owning page's pane.
 *
 * @param host Registered content.
 * @param modifier Placement (bottom end of the region `core.shell.FloatingToolbarPlacement` bounds).
 * @param scroll Hide-on-scroll state; null keeps the toolbar fixed.
 */
@Composable
fun FloatingToolbar(host: FloatingToolbarHost, modifier: Modifier = Modifier, scroll: FloatingToolbarScrollState? = null) {
    val content = host.current ?: return
    // A page whose actions are all conditional (or none) registers empty content: measure it but
    // place nothing, so no empty pill draws or blocks touches.
    var hasContent by remember { mutableStateOf(true) }
    // Content that changes width (a tool appearing, such as Quick Links once a sort has sections)
    // resizes smoothly; reduced motion snaps.
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
