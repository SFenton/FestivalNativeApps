package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchPresentation
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
 * @property selectedPlayer Current selected player.
 * @property bottomPadding Space reserved by the bottom bar / system navigation.
 * @property search Global search entry point (`.agents/controls/global-search/android.md`).
 * @property notifications Bell slot between search and the avatar, when notifications exist.
 * @property floatingToolbar Compact windows: the floating toolbar that takes screen actions and
 *   search ([FloatingToolbar]); null when actions belong in the top app bar.
 */
@Immutable
data class ShellActions(
    val navigate: (AppRoute) -> Unit = {},
    val back: () -> Unit = {},
    val openDrawer: (() -> Unit)? = null,
    val openProfile: () -> Unit = {},
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
 * drawer button on tab roots, back on pushed screens, then screen actions, global
 * search (in the floating toolbar on compact windows), the notifications slot and the
 * profile avatar as the rightmost action on tab roots.
 *
 * @param title Title Case title.
 * @param isRoot Whether this is a tab root.
 * @param modifier Modifier.
 * @param actions Screen actions, placed before search and the avatar.
 * @param scrolled Content sits under the bar even without a nested-scroll event
 *   (e.g. after a programmatic Quick Links jump), so the bar shows its scrolled color.
 * @param content Content given padding that clears the top bar and bottom chrome.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FestivalScreen(
    title: String,
    isRoot: Boolean,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    scrolled: Boolean = false,
    content: @Composable (PaddingValues) -> Unit,
) {
    val shell = LocalShellActions.current
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    // Page actions move to a ⋮ overflow menu when the title would truncate at this pane width
    // (a list pane can be far narrower than the window), and return once the pane is wider.
    var widthPx by remember { mutableIntStateOf(0) }
    var collapsedAtPx by remember(title) { mutableStateOf<Int?>(null) }
    var pageActionsWidth by remember { mutableIntStateOf(0) }
    var titleTruncated by remember { mutableStateOf(false) }
    val inlineActions = TopBarActionFit.inline(widthPx, collapsedAtPx)
    LaunchedEffect(titleTruncated, pageActionsWidth, widthPx) {
        collapsedAtPx = TopBarActionFit.afterTitleLayout(titleTruncated, inlineActions, pageActionsWidth > 0, widthPx, collapsedAtPx)
    }
    // Compact windows: page actions float over the bottom bar (web bottom dock); global search
    // stays in the top app bar on every window size (operator 2026-09-28).
    if (shell.floatingToolbar != null) {
        FloatingToolbarContent { actions() }
    }
    Scaffold(
        modifier = modifier
            .onSizeChanged { widthPx = it.width }
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                modifier = Modifier.testTag("fst.nav.top-bar"),
                title = {
                    Text(
                        title,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        onTextLayout = { titleTruncated = it.hasVisualOverflow || (it.lineCount > 0 && it.isLineEllipsized(0)) },
                    )
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
                        if (isRoot) ProfileAvatarButton(shell.selectedPlayer, shell.openProfile)
                    }
                    if (shell.floatingToolbar == null) {
                        AdaptiveTopBarActions(inlineActions, onPageWidth = { pageActionsWidth = it }, page = actions, global = global)
                    } else {
                        global()
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = if (scrolled) BrandTokens.surfaceFrosted else Color.Transparent,
                    scrolledContainerColor = BrandTokens.surfaceFrosted,
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
        // programmatic scroll that no nested-scroll event reports.
        Box(
            Modifier
                .fillMaxSize()
                .padding(top = inner.calculateTopPadding())
                .clipToBounds()
                .testTag("fst.nav.content"),
        ) {
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

/**
 * Top-right profile avatar: initials when a player is selected, otherwise a person glyph.
 *
 * @param player Selected player.
 * @param onClick Opens profile selection.
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
                    .background(BrandTokens.accentPurple, CircleShape),
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
