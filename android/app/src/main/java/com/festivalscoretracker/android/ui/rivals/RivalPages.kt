package com.festivalscoretracker.android.ui.rivals

import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.readingGroup
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.core.rivals.RivalrySort
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.rivals.AllRivalsViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalDetailViewModel
import com.festivalscoretracker.android.ui.bands.windowWidthDp
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.foldLaneItem
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region No player

/**
 * Rival pages without a selected player (web guard: "Track a player to see their rivals.").
 *
 * @param title Screen title.
 */
@Composable
fun RivalsNoPlayerScreen(title: String) {
    val shell = LocalShellActions.current
    FestivalScreen(title = title, isRoot = false) { padding ->
        Box(Modifier.padding(padding)) {
            RivalsMessage(RivalText.NO_PLAYER, null, "fst.rivals.chooseProfile", shell.openProfile, "Select Player")
        }
    }
}

// endregion

// region All rivals

/**
 * All Rivals (`/rivals/all`, web `AllRivalsPage`): one scope's full list; rows open
 * Rival Detail with the same scope.
 *
 * @param viewModel List logic.
 */
@Composable
fun AllRivalsScreen(viewModel: AllRivalsViewModel) {
    val shell = LocalShellActions.current
    val state by viewModel.state.collectAsStateWithLifecycle()
    FestivalScreen(title = viewModel.title, isRoot = false) { padding ->
        val scope = viewModel.scope
        if (scope == null) {
            Box(Modifier.padding(padding)) { RivalsMessage("This rivals list could not be identified.", null, "fst.all-rivals.unresolved") }
            return@FestivalScreen
        }
        val revealed = rememberRevealed(state is LoadState.Loaded)
        when (val current = state) {
            LoadState.Loading -> LoadingView("Loading rivals", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(current.issue, "Rivals unavailable", current.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> {
                val content = current.value
                if (content.entries.isEmpty()) {
                    Box(Modifier.padding(padding)) { RivalsMessage(RivalText.NO_RIVALS, null, "fst.all-rivals.empty") }
                    return@FestivalScreen
                }
                AdaptiveCardGrid(
                    contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
                    minColumn = 360.dp,
                    maxColumns = 2,
                    testTag = "fst.all-rivals.list",
                ) {
                    // The top app bar already names the list (M3: the top app bar holds the
                    // screen title), so the header only adds context: the chart icon and the
                    // rank line or chart list. A single-chart song list has neither (issue #108).
                    val icon = RivalScopes.singleInstrument(scope)
                    val subtitle = content.subtitle
                    if (subtitle != null) {
                        foldLaneItem(key = "header") {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.padding(bottom = 4.dp).testTag("fst.all-rivals.subtitle"),
                            ) {
                                icon?.let { InstrumentIcon(it, size = 28.dp, decorative = true) }
                                Text(subtitle, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                    }
                    itemsIndexed(content.entries, key = { index, entry -> entry.key(index) }) { index, entry ->
                        RivalRow(
                            entry,
                            onClick = { shell.navigate(RivalRoutes.detail(entry.rival.accountId, entry.rival.displayName, scope)) },
                            modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1)),
                        )
                    }
                }
            }
        }
    }
}

// endregion

// region Rival detail

/**
 * Rival Detail (`/rivals/:rivalId`, web `RivalDetailPage`): head-to-head summary and
 * the web's six categories as cards of five songs with "View All" into Rivalry.
 *
 * @param viewModel Comparison logic.
 * @param route Originating route (forwarded to Rivalry).
 * @param artworkUrl Artwork resolver.
 */
@Composable
fun RivalDetailScreen(viewModel: RivalDetailViewModel, route: RivalDetailRoute, artworkUrl: (String?) -> String?) {
    val shell = LocalShellActions.current
    val state by viewModel.state.collectAsStateWithLifecycle()
    val name by viewModel.displayName.collectAsStateWithLifecycle()
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val gridState = rememberLazyStaggeredGridState()
    val categories = (state as? LoadState.Loaded)?.value?.categories.orEmpty()
    // Web: one per category once loaded; the grid's first item is the "You vs. Rival" header.
    // The page's fade window, here so Quick Links jumps rush it (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", RivalQuickLinks.rivalDetail(categories), fadeInWindow = fadeIn) { id ->
        categories.indexOfFirst { RivalQuickLinks.categoryId(it.key) == id }.takeIf { it >= 0 }?.plus(1)
    }
    FestivalScreen(
        title = name ?: "Rival",
        isRoot = false,
        fadeInWindow = fadeIn,
        actions = {
            QuickLinksAction(quickLinks, windowWidthDp().toInt())
            ViewProfileButton(route.rivalId, name)
        },
    ) { padding ->
        val revealed = rememberRevealed(state is LoadState.Loaded)
        when (val current = state) {
            LoadState.Loading -> LoadingView("Loading rival", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(current.issue, "Rival unavailable", current.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> {
                val content = current.value
                val player = shell.selectedPlayer?.displayName
                AdaptiveCardGrid(
                    contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
                    state = gridState,
                    testTag = "fst.rival-detail.grid",
                ) {
                    foldLaneItem(key = "header") {
                        Column(Modifier.padding(bottom = 4.dp)) {
                            Text(
                                "${player ?: "You"} vs. ${content.rivalName ?: name ?: "…"}",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = BrandTokens.textPrimary,
                                modifier = Modifier.testTag("fst.rival-detail.title").semantics { heading() },
                            )
                            Text(content.summary, color = BrandTokens.textSecondary, modifier = Modifier.testTag("fst.rival-detail.summary"))
                        }
                    }
                    if (content.categories.isEmpty()) {
                        foldLaneItem(key = "empty") {
                            RivalsMessage(RivalText.NO_SONGS, null, "fst.rival-detail.empty")
                        }
                    }
                    content.categories.forEachIndexed { categoryIndex, category ->
                        item(key = category.key) {
                            Column(
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.testTag("fst.rival-detail.category.${category.key}").festivalFadeIn(revealed, fadeInStagger(categoryIndex + 1)).readingGroup(),
                            ) {
                                val openRivalry = { shell.navigate(RivalRoutes.rivalry(route, category.key, content.rivalName)) }
                                RivalSectionHeader(
                                    title = category.title,
                                    description = category.description,
                                    titleColor = categoryColor(category.sentiment),
                                    onSeeAll = openRivalry,
                                    seeAllTag = "fst.rival-detail.see-all.${category.key}",
                                )
                                category.songs.take(RivalCategorization.PREVIEW_COUNT).forEach { song ->
                                    val catalogSong: Song? = catalog[song.songId]
                                    androidx.compose.runtime.key(song.key) {
                                        RivalSongRow(
                                            song = song,
                                            catalogSong = catalogSong,
                                            artUrl = artworkUrl(catalogSong?.albumArt),
                                            playerName = player,
                                            rivalName = content.rivalName ?: name,
                                            onClick = { shell.navigate(SongDetailRoute(song.songId)) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ViewProfileButton(rivalId: String, name: String?) {
    val shell = LocalShellActions.current
    IconButton(onClick = { shell.navigate(PlayerRoute(rivalId, name)) }, modifier = Modifier.testTag("fst.rival-detail.view-profile")) {
        Icon(Icons.Outlined.Person, contentDescription = name?.let { "View $it's Profile" } ?: "View Profile")
    }
}

// endregion

// region Rivalry

/**
 * Rivalry (`/rivals/:rivalId/rivalry?mode=`, web `RivalryPage`): every song in one
 * category with a native sort menu (the web keeps category order).
 *
 * @param viewModel Comparison logic (shares Rival Detail's cached read).
 * @param rivalId Rival.
 * @param mode Category key.
 * @param artworkUrl Artwork resolver.
 */
@Composable
fun RivalryScreen(viewModel: RivalDetailViewModel, rivalId: String, mode: String, artworkUrl: (String?) -> String?) {
    val shell = LocalShellActions.current
    val state by viewModel.state.collectAsStateWithLifecycle()
    val name by viewModel.displayName.collectAsStateWithLifecycle()
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val sort by viewModel.sort.collectAsStateWithLifecycle()
    var sortOpen by rememberSaveable { mutableStateOf(false) }
    val gridState = rememberLazyStaggeredGridState()
    val songs = (state as? LoadState.Loaded)?.value?.let { viewModel.category(it, mode, sort) }?.songs.orEmpty()
    // Web: one per song in the shown order; the grid's first item is the "vs." header.
    // The page's fade window, here so Quick Links jumps rush it (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", RivalQuickLinks.rivalry(songs), fadeInWindow = fadeIn) { id ->
        songs.indices.firstOrNull { RivalQuickLinks.songId(songs[it], it) == id }?.plus(1)
    }
    FestivalScreen(
        title = RivalCategorization.title(mode),
        isRoot = false,
        fadeInWindow = fadeIn,
        actions = {
            Box {
                IconButton(onClick = { sortOpen = true }, modifier = Modifier.testTag("fst.rivalry.sort")) {
                    Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort: ${sort.label}")
                }
                DropdownMenu(
                    expanded = sortOpen,
                    onDismissRequest = { sortOpen = false },
                    modifier = Modifier.popupTestTags().selectableGroup().testTag("fst.rivalry.sort.menu"),
                ) {
                    RivalrySort.entries.forEach { option ->
                        val isSelected = option == sort
                        DropdownMenuItem(
                            text = { Text(option.label) },
                            leadingIcon = { RadioButton(selected = isSelected, onClick = null) },
                            onClick = {
                                sortOpen = false
                                viewModel.setSort(option)
                            },
                            // A RadioButton without onClick adds no semantics; expose the
                            // choice on the item so TalkBack announces checked/not checked.
                            modifier = Modifier
                                .testTag("fst.rivalry.sort.${option.name.lowercase()}")
                                .semantics {
                                    role = Role.RadioButton
                                    selected = isSelected
                                },
                        )
                    }
                }
            }
            QuickLinksAction(quickLinks, windowWidthDp().toInt())
            ViewProfileButton(rivalId, name)
        },
    ) { padding ->
        val revealed = rememberRevealed(state is LoadState.Loaded)
        when (val current = state) {
            LoadState.Loading -> LoadingView("Loading rivalry", Modifier.padding(padding))
            is LoadState.Failed -> ServiceStatusView(current.issue, "Rivalry unavailable", current.countdown, viewModel::retry, contentPadding = padding)
            is LoadState.Loaded -> {
                val content = current.value
                val category = viewModel.category(content, mode, sort)
                if (category == null || category.songs.isEmpty()) {
                    Box(Modifier.padding(padding)) { RivalsMessage(RivalText.NO_SONGS, null, "fst.rivalry.empty") }
                    return@FestivalScreen
                }
                val player = shell.selectedPlayer?.displayName
                AdaptiveCardGrid(
                    contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
                    maxColumns = 2,
                    state = gridState,
                    testTag = "fst.rivalry.list",
                ) {
                    foldLaneItem(key = "header") {
                        Column(Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                            Text(
                                "vs. ${content.rivalName ?: name ?: "…"}",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                color = categoryColor(category.sentiment),
                                modifier = Modifier.testTag("fst.rivalry.title").semantics { heading() },
                            )
                            Text(category.description, color = BrandTokens.textSecondary)
                        }
                    }
                    itemsIndexed(category.songs, key = { _, song -> song.key }) { index, song ->
                        val catalogSong = catalog[song.songId]
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1))) {
                            RivalSongRow(
                                song = song,
                                catalogSong = catalogSong,
                                artUrl = artworkUrl(catalogSong?.albumArt),
                                playerName = player,
                                rivalName = content.rivalName ?: name,
                                onClick = { shell.navigate(SongDetailRoute(song.songId)) },
                            )
                        }
                    }
                }
            }
        }
    }
}

// endregion
