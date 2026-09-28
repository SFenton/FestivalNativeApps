package com.festivalscoretracker.android.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.NavigationLayout
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.SettingsTab
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsTab
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.presentation.SongLeaderboardViewModel
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.ui.background.ArtworkBackground
import com.festivalscoretracker.android.ui.bands.bandsDestinations
import com.festivalscoretracker.android.ui.common.ComingSoonScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ShellActions
import com.festivalscoretracker.android.ui.settings.SettingsScreen
import com.festivalscoretracker.android.ui.songdetail.SongDetailScreen
import com.festivalscoretracker.android.ui.songdetail.SongLeaderboardScreen
import com.festivalscoretracker.android.ui.songs.SongsScreen
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// region Root

/**
 * App root: theme, the single shared backdrop and the adaptive shell.
 *
 * @param container Process dependencies.
 * @param launch Debug launch extras for this activity creation.
 */
@Composable
fun FestivalApp(container: AppContainer, launch: DebugLaunch) {
    val shellViewModel: ShellViewModel = viewModel { ShellViewModel(container.settings, launch) }
    val settings by shellViewModel.settings.collectAsStateWithLifecycle()
    FestivalTheme(appIncreaseContrast = settings?.increaseContrast == true, appReduceMotion = settings?.reduceMotion == true) {
        LaunchedEffect(Unit) { container.background.start(this) }
        LaunchedEffect(Unit) { container.selectedProfile.start(this, shellViewModel.settings.map { it?.selectedPlayer }) }
        Box(Modifier.fillMaxSize()) {
            ArtworkBackground(container.background, forceStill = launch.stillBackground)
            settings?.let { FestivalShell(container, shellViewModel, it, launch) }
        }
    }
}

// endregion

// region Shell

/** Material icon per section. */
internal fun FestivalSection.icon(): ImageVector = when (this) {
    FestivalSection.Songs -> Icons.Outlined.LibraryMusic
    FestivalSection.Suggestions -> Icons.Outlined.AutoAwesome
    FestivalSection.Leaderboards -> Icons.Outlined.EmojiEvents
    FestivalSection.Compete -> Icons.Outlined.SportsEsports
    FestivalSection.Rivals -> Icons.Outlined.People
    FestivalSection.Statistics -> Icons.Outlined.BarChart
    FestivalSection.Settings -> Icons.Outlined.Settings
}

/**
 * The section whose root is nearest the top of the back stack.
 *
 * @param stack Current back stack.
 * @return Selected section, defaulting to Songs.
 */
private fun sectionFor(stack: List<NavBackStackEntry>): FestivalSection =
    stack.asReversed().firstNotNullOfOrNull { entry ->
        FestivalSection.entries.firstOrNull { entry.destination.hasRoute(it.root::class) }
    } ?: FestivalSection.Songs

/**
 * Switch tabs keeping per-tab history (except Statistics), or pop to the root on re-tap.
 *
 * @param target Section to show.
 * @param current Section shown now.
 */
private fun NavHostController.selectSection(target: FestivalSection, current: FestivalSection) {
    if (target == current) {
        popBackStack(target.root, inclusive = false)
        return
    }
    navigate(target.root) {
        popUpTo(graph.findStartDestination().id) { saveState = !FestivalTabPolicy.resetsPathOnLeave(current) }
        launchSingleTop = true
        restoreState = !FestivalTabPolicy.resetsPathOnLeave(target)
    }
}

@Composable
private fun FestivalShell(container: AppContainer, shellViewModel: ShellViewModel, settings: AppSettings, launch: DebugLaunch) {
    val density = LocalDensity.current
    val windowSize = currentWindowSize()
    val widthDp = with(density) { windowSize.width.toDp().value.toInt() }
    val heightDp = with(density) { windowSize.height.toDp().value.toInt() }
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    val layout = AdaptiveLayoutPolicy.navigationLayout(widthDp, heightDp)
    val sections = FestivalTabPolicy.sections(shellViewModel.profileKind(settings), AdaptiveLayoutPolicy.isRegularWidth(widthDp))
    val navController = rememberNavController()
    val stack by navController.currentBackStack.collectAsStateWithLifecycle()
    val selected = sectionFor(stack)
    val drawerState = rememberDrawerState(if (launch.opensDrawer) DrawerValue.Open else DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    var showProfile by rememberSaveable { mutableStateOf(launch.opensProfileSheet) }

    LaunchedEffect(sections) {
        val resolved = FestivalTabPolicy.resolve(selected, sections)
        if (resolved != selected) navController.selectSection(resolved, selected)
    }
    LaunchedEffect(Unit) {
        launch.section?.takeIf { it in sections }?.let { navController.selectSection(it, FestivalSection.Songs) }
        launch.route?.let { navController.navigate(it) }
        launch.songQuery?.let { navController.navigate(SongDetailRoute(it)) }
    }

    val railWidth = if (layout == NavigationLayout.Rail) RAIL_WIDTH_DP else 0
    val navBars = WindowInsets.navigationBars.asPaddingValues()
    val safeEnd = WindowInsets.safeDrawing.asPaddingValues().calculateEndPadding(LocalLayoutDirection.current)
    val bottomPadding = PaddingValues(
        end = safeEnd,
        bottom = navBars.calculateBottomPadding() + if (layout == NavigationLayout.BottomBar) BAR_HEIGHT_DP.dp else 0.dp,
    )
    // Only the phone top bar shows a hamburger; the rail header owns it on medium widths.
    val openDrawer: (() -> Unit)? = if (layout == NavigationLayout.BottomBar) ({ scope.launch { drawerState.open() } }) else null
    val actions = ShellActions(
        navigate = { route -> scope.launch { drawerState.close() }; navController.navigate(route) },
        back = { navController.popBackStack() },
        openDrawer = openDrawer,
        openProfile = { showProfile = true },
        selectedPlayer = settings.selectedPlayer,
        bottomPadding = bottomPadding,
    )
    val drawerItems = @Composable { permanent: Boolean ->
        DrawerContent(
            sections = if (permanent) sections else emptyList(),
            selected = selected,
            player = settings.selectedPlayer,
            onSection = { navController.selectSection(it, selected) },
            onRoute = actions.navigate,
        )
    }
    val content = @Composable {
        CompositionLocalProvider(LocalShellActions provides actions) {
            Row(Modifier.fillMaxSize()) {
                if (layout == NavigationLayout.Rail) {
                    NavigationRail(
                        containerColor = BrandTokens.surfaceFrosted,
                        header = {
                            IconButton(onClick = { scope.launch { drawerState.open() } }, modifier = Modifier.testTag("fst.nav.drawer")) {
                                Icon(Icons.Filled.Menu, contentDescription = "Open menu")
                            }
                        },
                        modifier = Modifier.width(RAIL_WIDTH_DP.dp).testTag("fst.nav.rail"),
                    ) {
                        sections.forEach { section ->
                            NavigationRailItem(
                                selected = section == selected,
                                onClick = { navController.selectSection(section, selected) },
                                icon = { Icon(section.icon(), contentDescription = null) },
                                label = { Text(section.title) },
                                modifier = Modifier.testTag("fst.nav.tab.${section.name.lowercase()}"),
                            )
                        }
                    }
                }
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    FestivalNavHost(
                        navController = navController,
                        container = container,
                        shellViewModel = shellViewModel,
                        settings = settings,
                        twoPane = AdaptiveLayoutPolicy.showsTwoPanes(widthDp, hinge != null),
                        listPaneWidth = AdaptiveLayoutPolicy.listPaneWidth(
                            widthDp - railWidth,
                            hinge?.let { with(density) { it.bounds.left.toDp().value.toInt() } - railWidth },
                        ),
                    )
                    if (layout == NavigationLayout.BottomBar) {
                        NavigationBar(
                            containerColor = BrandTokens.cardBackground.copy(alpha = 0.96f),
                            modifier = Modifier.align(Alignment.BottomCenter).testTag("fst.nav.bar"),
                        ) {
                            sections.forEach { section ->
                                NavigationBarItem(
                                    selected = section == selected,
                                    onClick = { navController.selectSection(section, selected) },
                                    icon = { Icon(section.icon(), contentDescription = null) },
                                    label = { Text(section.title, maxLines = 1) },
                                    modifier = Modifier.testTag("fst.nav.tab.${section.name.lowercase()}"),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    if (layout == NavigationLayout.PermanentDrawer) {
        PermanentNavigationDrawer(drawerContent = {
            PermanentDrawerSheet(drawerContainerColor = BrandTokens.surfaceFrosted, modifier = Modifier.width(280.dp)) { drawerItems(true) }
        }) { content() }
    } else {
        ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = { ModalDrawerSheet(drawerContainerColor = BrandTokens.cardBackground) { drawerItems(false) } },
        ) { content() }
    }
    if (showProfile) {
        val searchViewModel: ProfileSearchViewModel = viewModel { ProfileSearchViewModel { query -> container.api.searchPlayers(query) } }
        ProfileSheet(
            player = settings.selectedPlayer,
            searchViewModel = searchViewModel,
            onSelect = shellViewModel::selectPlayer,
            onDeselect = shellViewModel::deselectPlayer,
            onViewProfile = { player -> actions.navigate(PlayerRoute(player.accountId, player.displayName)) },
            onDismiss = { showProfile = false },
        )
    }
}

/** Rail width used to offset list-detail and hinge math. */
private const val RAIL_WIDTH_DP = 80

/** Material 3 navigation bar height. */
private const val BAR_HEIGHT_DP = 80

// endregion

// region Nav host

@Composable
private fun FestivalNavHost(
    navController: NavHostController,
    container: AppContainer,
    shellViewModel: ShellViewModel,
    settings: AppSettings,
    twoPane: Boolean,
    listPaneWidth: Int,
) {
    val api = container.api
    val openLeaderboard = { songId: String, instrument: Instrument -> navController.navigate(SongLeaderboardRoute(songId, instrument.wireId)) }
    NavHost(navController = navController, startDestination = SongsTab, modifier = Modifier.fillMaxSize()) {
        composable<SongsTab> {
            val songsViewModel: SongsViewModel = viewModel {
                SongsViewModel(loadCatalog = { api.catalog(it) }, settings = shellViewModel.settings, backoff = container.backoff)
            }
            if (twoPane) {
                var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
                Row(Modifier.fillMaxSize()) {
                    Box(Modifier.width(listPaneWidth.dp)) {
                        SongsScreen(
                            viewModel = songsViewModel,
                            visibleInstruments = settings.visibleInstruments,
                            artworkUrl = api::artworkUrl,
                            onSortChange = shellViewModel::setSongSort,
                            onSongClick = { selectedId = it.songId },
                            selectedSongId = selectedId,
                        )
                    }
                    VerticalDivider(color = BrandTokens.glassBorder)
                    Box(Modifier.weight(1f).fillMaxHeight().testTag("fst.songs.detail-pane")) {
                        val id = selectedId
                        if (id == null) {
                            Text(
                                "Select a song",
                                style = MaterialTheme.typography.titleMedium,
                                color = BrandTokens.textSecondary,
                                modifier = Modifier.align(Alignment.Center),
                            )
                        } else {
                            val detailViewModel: SongDetailViewModel = viewModel(key = "detail:$id") {
                                SongDetailViewModel(id, { api.catalog(it) }, api::leaderboard, container.backoff)
                            }
                            SongDetailScreen(detailViewModel, settings.visibleInstruments, api::artworkUrl, container.background, embedded = true) { song, instrument ->
                                openLeaderboard(song.songId, instrument)
                            }
                        }
                    }
                }
            } else {
                SongsScreen(
                    viewModel = songsViewModel,
                    visibleInstruments = settings.visibleInstruments,
                    artworkUrl = api::artworkUrl,
                    onSortChange = shellViewModel::setSongSort,
                    onSongClick = { navController.navigate(SongDetailRoute(it.songId)) },
                )
            }
        }
        composable<SongDetailRoute> { entry ->
            val route = entry.toRoute<SongDetailRoute>()
            val detailViewModel: SongDetailViewModel = viewModel {
                SongDetailViewModel(route.songId, { api.catalog(it) }, api::leaderboard, container.backoff)
            }
            SongDetailScreen(detailViewModel, settings.visibleInstruments, api::artworkUrl, container.background, embedded = false) { song, instrument ->
                openLeaderboard(song.songId, instrument)
            }
        }
        composable<SongLeaderboardRoute> { entry ->
            val route = entry.toRoute<SongLeaderboardRoute>()
            val instrument = Instrument.fromWireId(route.instrument) ?: Instrument.Lead
            val boardViewModel: SongLeaderboardViewModel = viewModel {
                SongLeaderboardViewModel(route.songId, instrument, route.page, { api.catalog(it) }, api::leaderboard, container.backoff)
            }
            SongLeaderboardScreen(boardViewModel)
        }
        composable<SettingsTab> {
            SettingsScreen(settings = settings, shellViewModel = shellViewModel, serviceOrigin = api.origin)
        }
        placeholder<SuggestionsTab>("Suggestions", isRoot = true)
        placeholder<LeaderboardsTab>("Leaderboards", isRoot = true)
        placeholder<CompeteTab>("Compete", isRoot = true)
        placeholder<RivalsTab>("Rivals", isRoot = true)
        placeholder<StatisticsTab>("Statistics", isRoot = true)
        bandsDestinations(container)
        placeholder<PlayerHistoryRoute>("Score History")
        placeholder<PlayerRoute>("Player")
        placeholder<LeaderboardsRoute>("Leaderboards")
        placeholder<FullRankingsRoute>("Full Rankings")
        placeholder<BandRankingsRoute>("Band Rankings")
        placeholder<RivalsRoute>("Rivals")
        placeholder<AllRivalsRoute>("All Rivals")
        placeholder<RivalDetailRoute>("Rival")
        placeholder<RivalryRoute>("Rivalry")
        placeholder<StatisticsRoute>("Statistics")
        placeholder<SuggestionsRoute>("Suggestions")
        placeholder<CompeteRoute>("Compete")
        placeholder<ShopRoute>("Item Shop")
        placeholder<LicensesRoute>("Licenses")
    }
}

/**
 * Register an unported route with a placeholder screen.
 *
 * @param T Route type.
 * @param title Screen title.
 * @param isRoot Whether it is a tab root.
 */
private inline fun <reified T : AppRoute> androidx.navigation.NavGraphBuilder.placeholder(title: String, isRoot: Boolean = false) {
    composable<T> { entry -> ComingSoonScreen(title, isRoot, detail = entry.destination.route?.substringAfterLast('.')) }
}

// endregion
