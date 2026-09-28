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
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Shell actions

/**
 * Shell hooks every screen can use without constructing other screens.
 *
 * @property navigate Push a route on the current tab.
 * @property back Pop the current tab stack.
 * @property openDrawer Open the modal drawer, or null when the drawer is permanent.
 * @property openProfile Open profile selection.
 * @property selectedPlayer Current selected player.
 * @property bottomPadding Space reserved by the bottom bar / system navigation.
 */
@Immutable
data class ShellActions(
    val navigate: (AppRoute) -> Unit = {},
    val back: () -> Unit = {},
    val openDrawer: (() -> Unit)? = null,
    val openProfile: () -> Unit = {},
    val selectedPlayer: SelectedPlayer? = null,
    val bottomPadding: PaddingValues = PaddingValues(),
)

/** Shell hooks for the current screen. */
val LocalShellActions = staticCompositionLocalOf { ShellActions() }

// endregion

// region Screen scaffold

/**
 * Standard screen chrome: transparent top app bar over the shared backdrop, the
 * drawer button on tab roots, back on pushed screens, and the profile avatar as
 * the rightmost action on tab roots.
 *
 * @param title Title Case title.
 * @param isRoot Whether this is a tab root.
 * @param modifier Modifier.
 * @param actions Screen actions, placed before the avatar.
 * @param content Content given padding that clears the top bar and bottom chrome.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FestivalScreen(
    title: String,
    isRoot: Boolean,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val shell = LocalShellActions.current
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
                    actions()
                    if (isRoot) ProfileAvatarButton(shell.selectedPlayer, shell.openProfile)
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
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
        content(
            PaddingValues(
                start = inner.calculateStartPadding(direction) + bottom.calculateStartPadding(direction),
                top = inner.calculateTopPadding(),
                end = inner.calculateEndPadding(direction) + bottom.calculateEndPadding(direction),
                bottom = inner.calculateBottomPadding() + bottom.calculateBottomPadding(),
            ),
        )
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
