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
import androidx.compose.ui.unit.offset
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
        val leading: State<(@Composable RowScope.() -> Unit)?>,
    )

    private val entries = mutableStateListOf<Entry>()

    /** Content to show, or null when no screen registered actions. */
    val current: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.content?.value

    /**
     * The current owner's leading control (Songs search, issue #89), drawn as its own pill before
     * the actions, or null when the owner has none.
     */
    val currentLeading: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.leading?.value

    /** Whether the current owner keeps the toolbar on screen while its content scrolls. */
    val pinned: Boolean get() = entries.lastOrNull()?.pinned == true

    /** Whether the current owner holds a focused text field, so the toolbar rides above the keyboard. */
    val aboveKeyboard: Boolean get() = entries.lastOrNull()?.aboveKeyboard?.value == true

    /**
     * Register toolbar content.
     *
     * @param content Latest content (read on every recomposition).
     * @param pinned Keep the toolbar visible while content scrolls (no hide on scroll).
     * @param aboveKeyboard Latest "content holds a focused text field" flag (Songs search, issue #84).
     * @param leading Latest leading control drawn in its own pill before [content] (Songs search,
     *   issue #89), or a state holding null for none.
     * @return Unregister callback.
     */
    fun register(
        content: State<@Composable RowScope.() -> Unit>,
        pinned: Boolean = false,
        aboveKeyboard: State<Boolean> = NOT_ABOVE_KEYBOARD,
        leading: State<(@Composable RowScope.() -> Unit)?> = NO_LEADING,
    ): () -> Unit {
        val entry = Entry(content, pinned, aboveKeyboard, leading)
        entries += entry
        return { entries.remove(entry) }
    }

    private companion object {
        val NOT_ABOVE_KEYBOARD: State<Boolean> = mutableStateOf(false)
        val NO_LEADING: State<(@Composable RowScope.() -> Unit)?> = mutableStateOf(null)
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
 * @param leading A page control that is not one of its actions (Songs search, issue #89): drawn
 *   in its own pill before the actions, so the actions never read as part of it.
 * @param content Toolbar items, typically `IconButton`s; global search is not added automatically here.
 */
@Composable
fun FloatingToolbarContent(
    pinned: Boolean = false,
    aboveKeyboard: Boolean = false,
    leading: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val host = LocalShellActions.current.floatingToolbar ?: return
    val latest = rememberUpdatedState(content)
    val keyboard = rememberUpdatedState(aboveKeyboard)
    val latestLeading = rememberUpdatedState(leading)
    DisposableEffect(host, pinned) {
        val unregister = host.register(latest, pinned, keyboard, latestLeading)
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

/** Gap between a page's leading pill (Songs search) and its actions pill (issue #89). */
const val FLOATING_TOOLBAR_GAP_DP = 12

/** Test tags of the floating toolbar's parts. */
object FloatingToolbarTags {
    /** The whole floating toolbar (every pill). */
    const val TOOLBAR = "fst.nav.floating-toolbar"

    /** The leading pill holding a page control such as Songs search (issue #89). */
    const val LEADING = "fst.nav.floating-toolbar.leading"

    /** The pill holding the page's actions (Quick Links, Sort, Filter, …). */
    const val ACTIONS = "fst.nav.floating-toolbar.actions"
}

/**
 * The floating toolbar the shell draws over the bottom bar: the page's actions in one pill and,
 * when the page registered one, a leading control (Songs search) in its own pill
 * [FLOATING_TOOLBAR_GAP_DP] before it (issue #89: Sort and Filter must not read as part of the
 * search bar). The leading pill takes the free width when its content asks for it (a weighted
 * child, like the field-shaped search) and wraps otherwise (the minimized search icon).
 *
 * @param host Registered content.
 * @param modifier Placement (bottom end of the content area).
 * @param scroll Hide-on-scroll state; null keeps the toolbar fixed.
 */
@Composable
fun FloatingToolbar(host: FloatingToolbarHost, modifier: Modifier = Modifier, scroll: FloatingToolbarScrollState? = null) {
    val content = host.current ?: return
    val leading = host.currentLeading
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .then(if (scroll != null) Modifier.graphicsLayer { translationY = scroll.offsetPx } else Modifier)
            .testTag(FloatingToolbarTags.TOOLBAR)
            // Read after the page content, before the bottom bar; the leading pill first.
            .semantics { isTraversalGroup = true; traversalIndex = 1f },
    ) {
        if (leading != null) {
            ToolbarPill(leading, gapBeforeDp = 0, modifier = Modifier.weight(1f, fill = false).testTag(FloatingToolbarTags.LEADING))
        }
        ToolbarPill(content, gapBeforeDp = if (leading != null) FLOATING_TOOLBAR_GAP_DP else 0, modifier = Modifier.testTag(FloatingToolbarTags.ACTIONS))
    }
}

/**
 * One elevated, fully rounded toolbar pill (a 64 dp circle around a single 48 dp icon button).
 *
 * @param content Pill items.
 * @param gapBeforeDp Leading gap, kept only while the pill shows something.
 * @param modifier Tags and weight.
 */
@Composable
private fun ToolbarPill(content: @Composable RowScope.() -> Unit, gapBeforeDp: Int, modifier: Modifier) {
    // Content that renders nothing (a page whose actions are all conditional, or Songs' tools while
    // its search field is open) is measured but placed with no size or gap, so no empty pill draws
    // or blocks touches.
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
        modifier = Modifier
            .layout { measurable, constraints ->
                val gap = gapBeforeDp.dp.roundToPx()
                val placeable = measurable.measure(constraints.offset(horizontal = -gap))
                if (hasContent) layout(placeable.width + gap, placeable.height) { placeable.place(gap, 0) } else layout(0, 0) {}
            }
            // Tags inside the gap, so they bound the pill itself.
            .then(modifier)
            .heightIn(min = FLOATING_TOOLBAR_HEIGHT_DP.dp),
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
