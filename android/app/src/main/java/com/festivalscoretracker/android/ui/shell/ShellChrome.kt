package com.festivalscoretracker.android.ui.shell

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandsRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Drawer

/**
 * Navigation drawer content: tabs (permanent drawer only), then Browse, Player and More.
 *
 * @param sections Tabs to list (empty in the modal drawer, which accompanies a bar/rail).
 * @param selected Selected tab.
 * @param player Selected player.
 * @param onSection Select a tab.
 * @param onRoute Push a route.
 */
@Composable
fun DrawerContent(
    sections: List<FestivalSection>,
    selected: FestivalSection,
    player: SelectedPlayer?,
    onSection: (FestivalSection) -> Unit,
    onRoute: (AppRoute) -> Unit,
) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 16.dp).testTag("fst.nav.drawer-sheet")) {
        Text(
            "Festival Score Tracker",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        if (sections.isNotEmpty()) {
            sections.forEach { section ->
                DrawerItem(section.title, section.icon(), selected = section == selected, tag = "fst.nav.tab.${section.name.lowercase()}") { onSection(section) }
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp), color = BrandTokens.glassBorder)
        }
        DrawerLabel("Browse")
        DrawerItem("Item Shop", Icons.Outlined.ShoppingBag, tag = "fst.nav.drawer.shop") { onRoute(ShopRoute) }
        DrawerItem("Bands", Icons.Outlined.Groups, tag = "fst.nav.drawer.bands") { onRoute(BandsRoute) }
        if (player != null) {
            DrawerLabel(player.displayName)
            DrawerItem("Player Profile", Icons.Outlined.Person, tag = "fst.nav.drawer.player") { onRoute(PlayerRoute(player.accountId, player.displayName)) }
            DrawerItem("Rivals", Icons.Outlined.People, tag = "fst.nav.drawer.rivals") { onRoute(RivalsRoute) }
            DrawerItem("Player Bands", Icons.Outlined.Groups, tag = "fst.nav.drawer.player-bands") { onRoute(PlayerBandsRoute(player.accountId, player.displayName)) }
        }
        DrawerLabel("More")
        DrawerItem("Licenses", Icons.Outlined.Description, tag = "fst.nav.drawer.licenses") { onRoute(LicensesRoute) }
    }
}

@Composable
private fun DrawerLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = BrandTokens.textMuted,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun DrawerItem(label: String, icon: ImageVector, selected: Boolean = false, tag: String, onClick: () -> Unit) {
    NavigationDrawerItem(
        label = { Text(label) },
        icon = { Icon(icon, contentDescription = null) },
        selected = selected,
        onClick = onClick,
        colors = NavigationDrawerItemDefaults.colors(unselectedContainerColor = Color.Transparent),
        modifier = Modifier.testTag(tag),
    )
}

// endregion
