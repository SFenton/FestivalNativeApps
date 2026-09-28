package com.festivalscoretracker.android.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.shell.DrawerPolicy
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Rail

/**
 * Collapsed navigation rail (M3 `WideNavigationRail` items): the menu button on the top app
 * bar row, the main tabs centred, and Profile + Settings pinned to the bottom edge like the
 * web sidebar footer. Built as a plain column because Material's rail content cannot split
 * its destinations between the centre and the bottom.
 *
 * @param sections Visible tabs.
 * @param selected Selected tab.
 * @param player Selected player (initials avatar), or null.
 * @param onSection Select a tab.
 * @param onOpenDrawer Open the modal drawer.
 * @param onOpenProfile Open profile selection.
 * @param modifier Modifier.
 */
@Composable
fun FestivalRail(
    sections: List<FestivalSection>,
    selected: FestivalSection,
    player: SelectedPlayer?,
    onSection: (FestivalSection) -> Unit,
    onOpenDrawer: () -> Unit,
    onOpenProfile: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(color = BrandTokens.surfaceFrosted, contentColor = BrandTokens.textPrimary, modifier = modifier.fillMaxHeight()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier
                .fillMaxHeight()
                .width(RAIL_WIDTH_DP.dp)
                .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Start + WindowInsetsSides.Vertical))
                .testTag("fst.nav.rail"),
        ) {
            // Same row as the top app bar's navigation icon (64 dp bar, 48 dp button).
            Spacer(Modifier.height(4.dp))
            IconButton(onClick = onOpenDrawer, modifier = Modifier.testTag("fst.nav.drawer")) {
                Icon(Icons.Filled.Menu, contentDescription = "Open menu", tint = BrandTokens.textPrimary)
            }
            Spacer(Modifier.weight(1f))
            DrawerPolicy.railMain(sections).forEach { RailItem(it, selected, onSection) }
            Spacer(Modifier.weight(1f))
            NavigationSuiteItem(
                selected = false,
                onClick = onOpenProfile,
                icon = { RailAvatar(player) },
                label = { Text("Profile", maxLines = 1) },
                navigationSuiteType = NavigationSuiteType.WideNavigationRailCollapsed,
                modifier = Modifier.testTag("fst.nav.rail.profile"),
            )
            if (FestivalSection.Settings in sections) RailItem(FestivalSection.Settings, selected, onSection)
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun RailItem(section: FestivalSection, selected: FestivalSection, onSection: (FestivalSection) -> Unit) {
    NavigationSuiteItem(
        selected = section == selected,
        onClick = { onSection(section) },
        icon = { Icon(section.icon(), contentDescription = null) },
        label = { Text(section.title, maxLines = 1) },
        navigationSuiteType = NavigationSuiteType.WideNavigationRailCollapsed,
        modifier = Modifier.testTag("fst.nav.tab.${section.name.lowercase()}"),
    )
}

/** Initials when a player is selected, otherwise the person glyph (matches the top-bar avatar). */
@Composable
private fun RailAvatar(player: SelectedPlayer?) {
    if (player == null) {
        Icon(Icons.Outlined.AccountCircle, contentDescription = null)
    } else {
        Box(
            Modifier
                .size(24.dp)
                .background(BrandTokens.accentPurple, CircleShape)
                .semantics { contentDescription = "Profile: ${player.displayName}" },
            contentAlignment = Alignment.Center,
        ) {
            Text(player.initials, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        }
    }
}

/** Material collapsed wide-rail width (`NavigationRailCollapsedTokens.ContainerWidth`). */
private const val RAIL_WIDTH_DP = 96

// endregion
