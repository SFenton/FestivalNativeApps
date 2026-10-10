package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fitInside
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.WindowInsetsRulers
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchPresentation
import com.festivalscoretracker.android.core.shell.PxSpan
import com.festivalscoretracker.android.ui.search.GlobalSearchEntry
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Shell actions

/**
 * Shell hooks every screen can use without constructing other screens.
 *
 * @property navigate Push a route on the current tab.
 * @property back Pop the current tab stack.
 * @property openDrawer Open the modal drawer from the top bar (phone layout only), else null.
 * @property openProfile Open profile selection.
 * @property profileChip The profile chip's action: the selected profile's page (Statistics), or
 *   profile selection when none is selected ([com.festivalscoretracker.android.core.shell.ProfileChipPolicy]).
 * @property selectedPlayer Current selected player.
 * @property bottomPadding Space reserved by the bottom bar / system navigation.
 * @property search Global search entry point (`.agents/controls/global-search/android.md`).
 * @property notifications Bell slot between search and the avatar, when notifications exist.
 * @property floatingToolbar The shell's floating toolbar that takes screen actions at every window
 *   size ([FloatingToolbar], `page-tools-and-nav-chrome` R4, #576); null only outside the shell
 *   (previews, isolated tests), where the actions fall back to the top app bar.
 */
@Immutable
data class ShellActions(
    val navigate: (AppRoute) -> Unit = {},
    val back: () -> Unit = {},
    val openDrawer: (() -> Unit)? = null,
    val openProfile: () -> Unit = {},
    val profileChip: () -> Unit = openProfile,
    val selectedPlayer: SelectedPlayer? = null,
    val bottomPadding: PaddingValues = PaddingValues(),
    val search: SearchChrome = SearchChrome(),
    val notifications: (@Composable () -> Unit)? = null,
    val floatingToolbar: FloatingToolbarHost? = null,
)

/**
 * How screens show the one global search entry point.
 *
 * @property presentation Surface for the current window (full screen, docked, persistent bar).
 * @property open Open the surface, anchored to the requester's window bounds when known.
 * @property report Remember the latest entry bounds (keyboard shortcuts anchor to it).
 */
@Immutable
data class SearchChrome(
    val presentation: SearchPresentation = SearchPresentation.FullScreen,
    val open: (requester: PxRect?) -> Unit = {},
    val report: (PxRect) -> Unit = {},
)

/** Shell hooks for the current screen. */
val LocalShellActions = staticCompositionLocalOf { ShellActions() }

// endregion

// region Screen scaffold

/**
 * Standard screen chrome: transparent top app bar over the shared backdrop, the
 * drawer button on tab roots, back on pushed screens, global search, the notifications slot and
 * the profile avatar as the rightmost action; screen actions float in the shell's toolbar at
 * every window size (`page-tools-and-nav-chrome` R4, owner-approved #576).
 *
 * @param title Title Case title.
 * @param isRoot Whether this is a tab root.
 * @param modifier Modifier.
 * @param actions Screen actions, placed before search and the avatar.
 * @param pinActions Keep the floating toolbar holding [actions] on screen while the page scrolls
 *   instead of hiding it (Songs, Suggestions: issue #52).
 * @param actionsReadFirst TalkBack and keyboard focus reach the floating toolbar
 *   holding [actions] right after the top app bar instead of after the content: an endless feed
 *   (Suggestions) never ends, so a toolbar read last is unreachable by swiping (issue #112); a
 *   ~700-row list (Songs) is effectively the same (issue #160).
 * @param scrolled Content sits under the bar. No visual effect since batch 6.20 (the bar stays
 *   transparent); kept so screens can still report it without churn.
 * @param titleIcon Decorative icon drawn before the title (Instrument Leaderboards, issue #294),
 *   given the title's line height so it scales with the font size. It must not add its own
 *   accessibility label: the title already names what it shows.
 * @param marqueeTitle The title is a song title pinned once the page's song header scrolls away:
 *   it scrolls through the bar's available width when it overflows ([FestivalMarqueeText], one
 *   line at every text size) instead of tail-truncating (`song-header` R3, issue #315).
 * @param fadeInWindow The page's fade window ([rememberPageFadeInWindow]), provided to [content]
 *   as [LocalFadeInWindow] and rushed when the content scrolls (load-transition R5, issue #323).
 *   Pass one created in the page body when the body itself scrolls (a selected-row reveal,
 *   Quick Links); by default the screen creates its own.
 * @param content Content given padding that clears the top bar and bottom chrome.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FestivalScreen(
    title: String,
    isRoot: Boolean,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    pinActions: Boolean = false,
    actionsReadFirst: Boolean = false,
    scrolled: Boolean = false,
    titleIcon: (@Composable (size: Dp) -> Unit)? = null,
    marqueeTitle: Boolean = false,
    fadeInWindow: FadeInWindow? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    val shell = LocalShellActions.current
    val ownFadeInWindow = rememberPageFadeInWindow()
    val pageFadeIn = fadeInWindow ?: ownFadeInWindow
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    // Page actions move to a ⋮ overflow menu when the title would truncate at this pane width
    // (a list pane can be far narrower than the window), and return once the pane is wider.
    var widthPx by remember { mutableIntStateOf(0) }
    // Gaps between this screen and the window's left/right edges (a list pane beside a detail pane).
    var leftGapPx by remember { mutableIntStateOf(0) }
    var rightGapPx by remember { mutableIntStateOf(0) }
    var collapsedAtPx by remember(title) { mutableStateOf<Int?>(null) }
    var pageActionsWidth by remember { mutableIntStateOf(0) }
    var titleTruncated by remember { mutableStateOf(false) }
    val inlineActions = TopBarActionFit.inline(widthPx, collapsedAtPx)
    LaunchedEffect(titleTruncated, pageActionsWidth, widthPx) {
        collapsedAtPx = TopBarActionFit.afterTitleLayout(titleTruncated, inlineActions, pageActionsWidth > 0, widthPx, collapsedAtPx)
    }
    // Page actions float in the shell's toolbar at every window size (owner, #576), over this
    // screen's pane; global search stays in the top app bar (operator 2026-09-28).
    val pane = remember { mutableStateOf<PxSpan?>(null) }
    val toolbarReadsFirst = shell.floatingToolbar != null && actionsReadFirst
    if (shell.floatingToolbar != null) {
        FloatingToolbarContent(pinned = pinActions, readFirst = actionsReadFirst, pane = pane) { actions() }
    }
    Scaffold(
        modifier = modifier
            .onSizeChanged { widthPx = it.width }
            .onGloballyPositioned {
                val left = it.positionInWindow().x.toInt()
                leftGapPx = left
                rightGapPx = it.findRootCoordinates().size.width - left - it.size.width
                val span = PxSpan(left, left + it.size.width)
                if (pane.value != span) pane.value = span
            }
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                // A read-first toolbar (traversal index -1) would otherwise precede the bar's
                // ungrouped items (index 0), so the bar becomes one group read before it.
                modifier = Modifier
                    .testTag("fst.nav.top-bar")
                    .then(if (toolbarReadsFirst) Modifier.semantics { isTraversalGroup = true; traversalIndex = TOP_BAR_TRAVERSAL_INDEX } else Modifier),
                // Only the cutout / system-bar insets this pane actually reaches (issue #101).
                windowInsets = PaneInsets(TopAppBarDefaults.windowInsets, leftGapPx, rightGapPx),
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (titleIcon != null) {
                            // The bar's title style (M3 Title Large, 28 sp line), so the icon follows the font scale.
                            val iconSize = with(LocalDensity.current) { LocalTextStyle.current.lineHeight.toDp() }
                            Box(Modifier.padding(end = 12.dp).testTag("fst.nav.title-icon")) { titleIcon(iconSize) }
                        }
                        if (marqueeTitle) {
                            // `song-header` R3: the pinned song title scrolls in the bar's full width.
                            FestivalMarqueeText(
                                title,
                                Modifier.weight(1f, fill = false).testTag("fst.nav.title"),
                                fontWeight = FontWeight.Bold,
                                wrapAtLargeText = false,
                                onOverflowChange = { titleTruncated = it },
                            )
                        } else {
                            Text(
                                title,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                onTextLayout = { titleTruncated = it.hasVisualOverflow || (it.lineCount > 0 && it.isLineEllipsized(0)) },
                                modifier = Modifier.weight(1f, fill = false).testTag("fst.nav.title"),
                            )
                        }
                    }
                },
                navigationIcon = {
                    when {
                        !isRoot -> IconButton(onClick = shell.back, modifier = Modifier.testTag("fst.nav.back")) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                        shell.openDrawer != null -> IconButton(onClick = shell.openDrawer, modifier = Modifier.testTag("fst.nav.drawer")) {
                            Icon(Icons.Filled.Menu, contentDescription = "Open menu")
                        }
                    }
                },
                actions = {
                    val global: @Composable RowScope.() -> Unit = {
                        GlobalSearchEntry(shell.search)
                        shell.notifications?.invoke()
                        // Every page, pushed pages included (operator batch 7.12).
                        ProfileAvatarButton(shell.selectedPlayer, shell.profileChip)
                    }
                    // Outside the shell (previews, isolated tests) there is no toolbar to float in.
                    if (shell.floatingToolbar == null) {
                        AdaptiveTopBarActions(inlineActions, onPageWidth = { pageActionsWidth = it }, page = actions, global = global)
                    } else {
                        global()
                    }
                },
                // Transparent in every scroll state (batch 6.20: no translucent slab appears behind
                // the header on scroll). Content is clipped below the bar, so nothing shows through.
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = Color.Transparent,
                    titleContentColor = BrandTokens.textPrimary,
                    navigationIconContentColor = BrandTokens.textPrimary,
                    actionIconContentColor = BrandTokens.textPrimary,
                ),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { inner ->
        val direction = LocalLayoutDirection.current
        val bottom = shell.bottomPadding
        // Content starts (and is clipped) below the top app bar, whose own window insets
        // already cover the status bar / cutout, so scrolled rows never draw under the
        // transparent bar or the status bar on any width class, including after a
        // programmatic scroll that no nested-scroll event reports. Content also stays clear
        // of a landscape camera cutout, only where this pane actually overlaps it (issue #101).
        Box(
            Modifier
                .fillMaxSize()
                .padding(top = inner.calculateTopPadding())
                .fitInside(WindowInsetsRulers.DisplayCutout.current)
                .clipToBounds()
                .fadeInRushOnScroll(pageFadeIn)
                .testTag("fst.nav.content"),
        ) {
            CompositionLocalProvider(LocalFadeInWindow provides pageFadeIn) {
                content(
                    PaddingValues(
                        start = inner.calculateStartPadding(direction) + bottom.calculateStartPadding(direction),
                        top = 0.dp,
                        end = inner.calculateEndPadding(direction) + bottom.calculateEndPadding(direction),
                        bottom = inner.calculateBottomPadding() + bottom.calculateBottomPadding(),
                    ),
                )
            }
        }
    }
}

/**
 * Top-right profile avatar: initials when a player is selected, otherwise a person glyph.
 *
 * @param player Selected player.
 * @param onClick The profile chip action ([ShellActions.profileChip]).
 */
@Composable
fun ProfileAvatarButton(player: SelectedPlayer?, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .testTag("fst.nav.profile")
            .semantics { contentDescription = player?.let { "Profile: ${it.displayName}" } ?: "Choose profile" },
    ) {
        if (player == null) {
            Icon(Icons.Outlined.AccountCircle, contentDescription = null)
        } else {
            Box(
                Modifier
                    .size(32.dp)
                    .background(BrandTokens.accentPurple, CircleShape)
                    // The button's description names the player; the initials are decoration.
                    .clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) {
                Text(player.initials, style = MaterialTheme.typography.labelLarge, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold)
            }
        }
    }
}

// endregion

// region Placeholder

/**
 * Placeholder for a route whose screen has not been ported to Android yet.
 *
 * @param title Screen title.
 * @param isRoot Whether it is a tab root.
 * @param detail Route summary.
 */
@Composable
fun ComingSoonScreen(title: String, isRoot: Boolean, detail: String? = null) {
    FestivalScreen(title = title, isRoot = isRoot) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(24.dp).testTag("fst.coming-soon"),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("$title is coming to Android soon", style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary)
            if (detail != null) {
                Text(detail, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textMuted, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

// endregion
