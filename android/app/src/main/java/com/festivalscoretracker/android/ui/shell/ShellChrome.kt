package com.festivalscoretracker.android.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.shell.DrawerEntry
import com.festivalscoretracker.android.core.shell.DrawerPolicy
import com.festivalscoretracker.android.core.shell.DrawerTarget
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Drawer

/**
 * Navigation drawer content, mirroring the web sidebar ([DrawerPolicy]): Songs · Suggestions ·
 * Statistics · Rivals · Leaderboards · Item Shop, then a footer with the profile row (or Select
 * Profile) and Settings last. Used by the modal drawer (bars and rails) and the permanent drawer.
 *
 * @param visible Tabs visible at this width (decides tab switch vs push).
 * @param selected Selected tab.
 * @param profile Selected profile kind.
 * @param player Selected player.
 * @param onSection Select a tab.
 * @param onRoute Push a route.
 * @param onOpenProfile Open profile selection.
 * @param onDeselect Deselect the player.
 * @param showShop False while Settings' Hide Item Shop is on (web/Apple/Windows drop the entry).
 * @param tabTags The permanent drawer is the tab navigation, so its tab rows keep the
 *   `fst.nav.tab.<section>` tags; the modal drawer (alongside a bar/rail that owns those tags)
 *   uses `fst.nav.drawer.<entry>`.
 */
@Composable
fun DrawerContent(
    visible: List<FestivalSection>,
    selected: FestivalSection,
    profile: ProfileKind,
    player: SelectedPlayer?,
    onSection: (FestivalSection) -> Unit,
    onRoute: (AppRoute) -> Unit,
    onOpenProfile: () -> Unit,
    onDeselect: () -> Unit,
    showShop: Boolean = true,
    tabTags: Boolean = false,
) {
    fun open(target: DrawerTarget) = when (target) {
        is DrawerTarget.Section -> onSection(target.section)
        is DrawerTarget.Push -> onRoute(target.route)
    }
    Column(Modifier.fillMaxHeight().padding(horizontal = 12.dp, vertical = 16.dp).testTag("fst.nav.drawer-sheet")) {
        Text(
            "Festival Score Tracker",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            DrawerPolicy.entries(profile, showShop).forEach { entry ->
                DrawerItem(entry.title, entry.icon(), selected = DrawerPolicy.isSelected(entry, selected), tag = entry.tag(tabTags)) {
                    open(DrawerPolicy.target(entry, visible))
                }
            }
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp), color = BrandTokens.glassBorder)
        if (player != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    DrawerItem(player.displayName, Icons.Outlined.Person, tag = "fst.nav.drawer.player") {
                        open(DrawerPolicy.target(DrawerEntry.Statistics, visible))
                    }
                }
                TextButton(onClick = onDeselect, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.nav.drawer.deselect")) { Text("Deselect") }
            }
        } else {
            DrawerItem("Select Profile", Icons.Outlined.PersonAdd, tag = "fst.nav.drawer.select-profile", onClick = onOpenProfile)
        }
        DrawerItem(
            FestivalSection.Settings.title,
            FestivalSection.Settings.icon(),
            selected = selected == FestivalSection.Settings,
            tag = if (tabTags) "fst.nav.tab.settings" else "fst.nav.drawer.settings",
        ) { onSection(FestivalSection.Settings) }
    }
}

/** Drawer row icon (web sidebar icons, Material equivalents). */
private fun DrawerEntry.icon(): ImageVector = section?.icon() ?: Icons.Outlined.ShoppingBag

/** Test tag: `fst.nav.tab.<section>` for tab rows of the permanent drawer, else `fst.nav.drawer.<entry>`. */
private fun DrawerEntry.tag(tabTags: Boolean): String =
    section?.takeIf { tabTags }?.let { "fst.nav.tab.${it.name.lowercase()}" } ?: "fst.nav.drawer.${name.lowercase()}"

@Composable
private fun DrawerItem(label: String, icon: ImageVector, selected: Boolean = false, tag: String, onClick: () -> Unit) {
    NavigationDrawerItem(
        label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        icon = { Icon(icon, contentDescription = null) },
        selected = selected,
        onClick = onClick,
        colors = NavigationDrawerItemDefaults.colors(unselectedContainerColor = Color.Transparent),
        modifier = Modifier.testTag(tag),
    )
}

// endregion
