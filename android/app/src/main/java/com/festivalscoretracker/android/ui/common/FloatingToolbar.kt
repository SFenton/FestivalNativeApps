package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.shell.PxSpan
import com.festivalscoretracker.android.ui.design.festivalDestructiveButtonColors
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Slot

/**
 * The shell's floating-toolbar slot (M3 Expressive floating toolbar; Material 3 1.4 stable has
 * no public `HorizontalFloatingToolbar`, so this is the equivalent pill: 64 dp, fully rounded,
 * elevated, floating 16 dp above the bottom bar). It never hides on scroll, on any page
 * (`page-tools-and-nav-chrome` R7, issues #52, #577), so Quick Links and the other tools stay
 * reachable without scrolling back and the band pages reserve below their last row stays covered.
 *
 * Pages do **not** call this directly: at every window size [FestivalScreen] moves its `actions`
 * (Quick Links, Sort, Filter, …) here (`page-tools-and-nav-chrome` R4, owner-approved #576); global
 * search, the bell and Profile stay in the top app bar. A screen outside [FestivalScreen] can use
 * [FloatingToolbarContent]. A page's primary action ([FloatingToolbarAction]) may sit beside the
 * toolbar as its own pill (owner-approved R6 variant, #590: player page and Statistics only).
 * The most recently composed registration wins, so the entering screen owns the toolbar during a
 * navigation transition and the previous screen takes it back when it returns.
 */
@Stable
class FloatingToolbarHost {
    private class Entry(
        val content: State<@Composable RowScope.() -> Unit>,
        val readFirst: Boolean,
        val pane: State<PxSpan?>?,
        val companion: State<FloatingToolbarAction?>?,
    )

    private val entries = mutableStateListOf<Entry>()

    /** Content to show, or null when no screen registered actions. */
    val current: (@Composable RowScope.() -> Unit)? get() = entries.lastOrNull()?.content?.value

    /**
     * The current owner's primary action, drawn as its own pill beside the toolbar (owner-approved
     * `page-tools-and-nav-chrome` R6 variant, #590: the player page's Select/Switch), or null.
     */
    val companion: FloatingToolbarAction? get() = entries.lastOrNull()?.companion?.value

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
     * @param readFirst Read the toolbar before the page content rather than after it.
     * @param pane The owner's pane in window pixels (read on every layout), so the toolbar floats
     *   over that pane in a split; null for the whole content area.
     * @param companion The owner's primary action (read on every recomposition), drawn as a separate
     *   pill before the toolbar; null for none.
     * @return Unregister callback.
     */
    fun register(
        content: State<@Composable RowScope.() -> Unit>,
        readFirst: Boolean = false,
        pane: State<PxSpan?>? = null,
        companion: State<FloatingToolbarAction?>? = null,
    ): () -> Unit {
        val entry = Entry(content, readFirst, pane, companion)
        entries += entry
        return { entries.remove(entry) }
    }
}

/**
 * Put [content] in the shell's floating toolbar while this composable is composed (no-op outside
 * the shell, i.e. `LocalShellActions.current.floatingToolbar == null`). The toolbar stays on
 * screen while the page scrolls on every page (M3 floating toolbar without the optional hide on
 * scroll; `page-tools-and-nav-chrome` R7, issues #52, #577).
 *
 * @param readFirst TalkBack and keyboard focus reach the toolbar right after the top app bar,
 *   before the page content (for pages whose content is an endless feed, issue #112).
 * @param pane The page's pane in window pixels, so the toolbar floats over it in a split; null for
 *   the whole content area.
 * @param companion The page's primary action as its own pill before the toolbar, in the same row
 *   (owner-approved R6 variant, #590); null for none.
 * @param content Toolbar items, typically `IconButton`s; global search is not added automatically here.
 */
@Composable
fun FloatingToolbarContent(
    readFirst: Boolean = false,
    pane: State<PxSpan?>? = null,
    companion: FloatingToolbarAction? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val host = LocalShellActions.current.floatingToolbar ?: return
    val latest = rememberUpdatedState(content)
    val latestCompanion = rememberUpdatedState(companion)
    DisposableEffect(host, readFirst, pane) {
        val unregister = host.register(latest, readFirst, pane, latestCompanion)
        onDispose { unregister() }
    }
}

// endregion

// region Companion action

/**
 * A page's primary action shown as its own pill beside the floating toolbar, in the same row but
 * never inside the toolbar pill (owner-approved `page-tools-and-nav-chrome` R6 variant, #590;
 * Material 3 Expressive pairs a floating toolbar with one separate primary action the same way).
 * Only the player page and Statistics use it (Select/Switch/Deselect, like the iOS header's own
 * `ProfileIdentityToolbarItem`); every other page keeps one toolbar.
 *
 * @property text Short visible text (iOS `shortTitle`: "Select", "Switch", "Deselect").
 * @property label Full TalkBack label ("Select Profile").
 * @property testTag Test tag of the button.
 * @property destructive Draw the button red (Deselect; web `btnDanger`, iOS `isDestructive`).
 * @property onClick Runs the action.
 */
@Immutable
data class FloatingToolbarAction(
    val text: String,
    val label: String,
    val testTag: String,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/**
 * The companion action's button: a prominent filled button (accent blue, the iOS prominent fill;
 * red [BrandTokens.statusRed] for a destructive action) with a 48 dp minimum height that grows with
 * the font scale. TalkBack reads [action]'s full label once, as a button.
 *
 * @param action Action.
 * @param modifier Modifier.
 */
@Composable
fun FloatingToolbarActionButton(action: FloatingToolbarAction, modifier: Modifier = Modifier) {
    Button(
        onClick = action.onClick,
        colors = if (action.destructive) festivalDestructiveButtonColors() else festivalFilledButtonColors(),
        modifier = modifier
            .heightIn(min = 48.dp)
            .testTag(action.testTag)
            .semantics { contentDescription = action.label },
    ) {
        Text(action.text, fontWeight = FontWeight.SemiBold, modifier = Modifier.clearAndSetSemantics {})
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
 * The floating toolbar surface the shell draws at the bottom end of the owning page's pane, with
 * the owner's [FloatingToolbarHost.companion] action as a separate pill before it in the same row
 * (8 dp apart, both 64 dp tall; #590). Both pills stay on screen (R7) and share one traversal
 * index: TalkBack reads the companion, then the toolbar.
 *
 * @param host Registered content.
 * @param modifier Placement (bottom end of the region `core.shell.FloatingToolbarPlacement` bounds).
 */
@Composable
fun FloatingToolbar(host: FloatingToolbarHost, modifier: Modifier = Modifier) {
    val content = host.current ?: return
    val companion = host.companion
    // A page whose actions are all conditional (or none) registers empty content: measure it but
    // place nothing, so no empty pill draws or blocks touches.
    var hasContent by remember { mutableStateOf(true) }
    // Content that changes width (a tool appearing, such as Quick Links once a sort has sections)
    // resizes smoothly; reduced motion snaps.
    val resize = if (LocalFestivalAccessibility.current.reduceMotion) Modifier else Modifier.animateContentSize()
    // Read after the page content, before the bottom bar; or, for an endless feed, between
    // the top app bar (FestivalScreen gives it TOP_BAR_TRAVERSAL_INDEX) and the content.
    val traversal = if (host.readFirst) TOOLBAR_READ_FIRST_TRAVERSAL_INDEX else 1f
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier,
    ) {
        // Each pill is its own traversal group at the same index in the shell's group (the row adds
        // no group, so the toolbar keeps its place beside the top bar); equal indexes read in
        // screen order, so the companion, which comes first, is read before the toolbar.
        if (companion != null) {
            ToolbarPill(Modifier.testTag("fst.nav.floating-toolbar.companion").semantics { isTraversalGroup = true; traversalIndex = traversal }) {
                FloatingToolbarActionButton(companion)
            }
            if (hasContent) Spacer(Modifier.width(FLOATING_TOOLBAR_COMPANION_GAP_DP.dp))
        }
        ToolbarPill(
            Modifier
                .layout { measurable, constraints ->
                    val placeable = measurable.measure(constraints)
                    if (hasContent) layout(placeable.width, placeable.height) { placeable.place(0, 0) } else layout(0, 0) {}
                }
                .testTag("fst.nav.floating-toolbar")
                .semantics { isTraversalGroup = true; traversalIndex = traversal },
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = resize,
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

/** Gap between the companion pill and the toolbar pill (#590). */
const val FLOATING_TOOLBAR_COMPANION_GAP_DP = 8

/** One floating pill: the toolbar's glass surface, 64 dp tall, content inset 8 dp. */
@Composable
private fun ToolbarPill(modifier: Modifier, content: @Composable () -> Unit) {
    Surface(
        shape = CircleShape,
        color = BrandTokens.cardBackground.copy(alpha = 0.97f),
        contentColor = BrandTokens.textPrimary,
        border = BorderStroke(1.dp, BrandTokens.glassBorder),
        shadowElevation = 6.dp,
        modifier = modifier.heightIn(min = FLOATING_TOOLBAR_HEIGHT_DP.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides BrandTokens.textPrimary) {
            Box(Modifier.padding(horizontal = 8.dp, vertical = 8.dp), contentAlignment = Alignment.Center) { content() }
        }
    }
}

// endregion
