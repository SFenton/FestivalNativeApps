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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.shell.DrawerPolicy
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.isLargeText

// region Rail

/**
 * Collapsed navigation rail (M3 `WideNavigationRail` items): the menu button on the top app
 * bar row, the main tabs top-aligned below it, and Profile + Settings pinned to the bottom
 * edge like the web sidebar footer. Built as a plain column because Material's rail content cannot split
 * its destinations between the centre and the bottom.
 *
 * @param sections Visible tabs.
 * @param selected Selected tab.
 * @param player Selected player (initials avatar), or null.
 * @param onSection Select a tab.
 * @param onOpenDrawer Open the modal drawer.
 * @param onOpenProfile Profile item action: the selected profile's page (Statistics), or profile
 *   selection when none is selected (`ProfileChipPolicy`).
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
    // No container color: the shared artwork backdrop shows through, like the pages (batch 6.19).
    Surface(color = Color.Transparent, contentColor = BrandTokens.textPrimary, modifier = modifier.fillMaxHeight()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier
                .fillMaxHeight()
                .width(RAIL_WIDTH_DP.dp)
                .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Start + WindowInsetsSides.Vertical))
                .testTag("fst.nav.rail")
                // One TalkBack unit: without it the destinations interleave with the page by
                // vertical position (Songs, then the page, then the other destinations).
                .semantics { isTraversalGroup = true },
        ) {
            // The menu button sits in the top app bar's row (64 dp bar, 48 dp button); the
            // destinations are top-aligned below it, starting where the drawer's first entry
            // starts, so opening the drawer reads as the rail expanding (operator 2026-09-28).
            Box(Modifier.height(PAGE_CONTENT_TOP_DP.dp), contentAlignment = Alignment.Center) {
                IconButton(onClick = onOpenDrawer, modifier = Modifier.testTag("fst.nav.drawer")) {
                    Icon(Icons.Filled.Menu, contentDescription = "Open menu", tint = BrandTokens.textPrimary)
                }
            }
            DrawerPolicy.railMain(sections).forEach { RailItem(it, selected, onSection) }
            Spacer(Modifier.weight(1f))
            // Large text: icon only, like the destinations above, so "Profile" no longer
            // dwarfs their icons; the avatar then carries the spoken label (issue #101).
            val profileIconOnly = isLargeText()
            val profileLabel = player?.let { "Profile: ${it.displayName}" } ?: "Profile"
            NavigationSuiteItem(
                selected = false,
                onClick = onOpenProfile,
                icon = {
                    Box(if (profileIconOnly) Modifier.semantics { contentDescription = profileLabel } else Modifier) { RailAvatar(player) }
                },
                // One stop that says "Profile: <name>" (the avatar itself is silent).
                label = if (profileIconOnly) null else ({
                    Text(
                        "Profile",
                        maxLines = 1,
                        modifier = Modifier.semantics { contentDescription = profileLabel },
                    )
                }),
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
    // Large text: labels no longer fit the 96 dp rail, so icons carry the names (as on the bar).
    val iconOnly = isLargeText()
    NavigationSuiteItem(
        selected = section == selected,
        onClick = { onSection(section) },
        icon = { Icon(section.icon(section == selected), contentDescription = if (iconOnly) section.title else null) },
        label = if (iconOnly) null else ({ Text(section.title, maxLines = 1) }),
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
                .clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            Text(player.initials, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        }
    }
}

/** Material collapsed wide-rail width (`NavigationRailCollapsedTokens.ContainerWidth`). */
private const val RAIL_WIDTH_DP = 96

// endregion
