package com.festivalscoretracker.android.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ShoppingBag
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
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.common.oneLineUnlessLarge
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics

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
 * @param permanent Permanent (tablet) drawer: no app title, and the first entry starts where
 *   the page's first content row (e.g. the Songs search field) sits below the top app bar
 *   (operator 2026-09-28).
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
    permanent: Boolean = false,
) {
    fun open(target: DrawerTarget) = when (target) {
        is DrawerTarget.Section -> onSection(target.section)
        is DrawerTarget.Push -> onRoute(target.route)
    }
    Column(
        Modifier
            .fillMaxHeight()
            .padding(start = 12.dp, end = 12.dp, bottom = 16.dp)
            .testTag("fst.nav.drawer-sheet"),
    ) {
        // Header row the height of the top app bar, so the first entry lines up with the page's
        // first content row and with the rail's first destination (the drawer extends the rail).
        // Large text wraps the title, so the row grows (a fixed 64 dp let "Songs" overlap the
        // title's second line at 2.0×, issue #132) and scrolls with the entries on short windows.
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().heightIn(min = PAGE_CONTENT_TOP_DP.dp).testTag("fst.nav.drawer-header"), contentAlignment = Alignment.CenterStart) {
                if (!permanent) {
                    Text(
                        "Festival Score Tracker",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).semantics { heading() },
                    )
                }
            }
            DrawerPolicy.entries(profile, showShop).forEach { entry ->
                val active = DrawerPolicy.isSelected(entry, selected)
                DrawerItem(entry.title, entry.icon(active), selected = active, tag = entry.tag(tabTags)) {
                    open(DrawerPolicy.target(entry, visible))
                }
            }
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp), color = BrandTokens.glassBorder)
        if (player != null) {
            val profileItem = @Composable {
                DrawerItem(player.displayName, Icons.Outlined.Person, tag = "fst.nav.drawer.player", spokenLabel = "Profile: ${player.displayName}") {
                    open(DrawerPolicy.target(DrawerEntry.Statistics, visible))
                }
            }
            val deselect = @Composable { modifier: Modifier ->
                TextButton(
                    onClick = onDeselect,
                    modifier = modifier.heightIn(min = 48.dp).testTag("fst.nav.drawer.deselect").semantics { contentDescription = "Deselect profile" },
                ) { Text("Deselect", Modifier.clearAndSetSemantics { }) }
            }
            // Large text: the name keeps the row's width and Deselect drops below it (beside it,
            // a 200% "SFentonX" broke a few letters per line, issue #101).
            if (isLargeText()) {
                Column {
                    profileItem()
                    deselect(Modifier.align(Alignment.End))
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { profileItem() }
                    deselect(Modifier)
                }
            }
        } else {
            DrawerItem("Select Profile", Icons.Outlined.PersonAdd, tag = "fst.nav.drawer.select-profile", onClick = onOpenProfile)
        }
        DrawerItem(
            FestivalSection.Settings.title,
            FestivalSection.Settings.icon(selected == FestivalSection.Settings),
            selected = selected == FestivalSection.Settings,
            tag = if (tabTags) "fst.nav.tab.settings" else "fst.nav.drawer.settings",
        ) { onSection(FestivalSection.Settings) }
    }
}

/**
 * Top of a page's first content row below the status bar: the 64 dp M3 small top app bar.
 * Drawer sheets and the rail already clear the status bar themselves.
 */
internal const val PAGE_CONTENT_TOP_DP = 64

/** Drawer row icon (web sidebar icons, Material equivalents): filled while [active]. */
private fun DrawerEntry.icon(active: Boolean): ImageVector =
    section?.icon(active) ?: if (active) Icons.Filled.ShoppingBag else Icons.Outlined.ShoppingBag

/** Test tag: `fst.nav.tab.<section>` for tab rows of the permanent drawer, else `fst.nav.drawer.<entry>`. */
private fun DrawerEntry.tag(tabTags: Boolean): String =
    section?.takeIf { tabTags }?.let { "fst.nav.tab.${it.name.lowercase()}" } ?: "fst.nav.drawer.${name.lowercase()}"

/**
 * One drawer row.
 *
 * @param label Visible text (wraps at large font scales).
 * @param spokenLabel TalkBack label replacing [label] ("Profile: <name>"), or null to read [label].
 */
@Composable
private fun DrawerItem(label: String, icon: ImageVector, selected: Boolean = false, tag: String, spokenLabel: String? = null, onClick: () -> Unit) {
    NavigationDrawerItem(
        label = {
            Text(
                label,
                maxLines = oneLineUnlessLarge(),
                overflow = TextOverflow.Ellipsis,
                modifier = if (spokenLabel != null) Modifier.clearAndSetSemantics { contentDescription = spokenLabel } else Modifier,
            )
        },
        icon = { Icon(icon, contentDescription = null) },
        selected = selected,
        onClick = onClick,
        colors = NavigationDrawerItemDefaults.colors(unselectedContainerColor = Color.Transparent),
        modifier = Modifier.testTag(tag),
    )
}

// endregion
