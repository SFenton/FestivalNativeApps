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
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
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
import com.festivalscoretracker.android.ui.leaderboards.leaderboardsGraph
import com.festivalscoretracker.android.ui.settings.SettingsScreen
import com.festivalscoretracker.android.ui.songdetail.SongDetailScreen
import com.festivalscoretracker.android.ui.songdetail.SongLeaderboardScreen
import com.festivalscoretracker.android.ui.songs.SongsScreen
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.statusBars
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.WideNavigationRailDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuite
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldLayout
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.rememberSearchBarState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.material3.adaptive.HingeInfo
import androidx.lifecycle.createSavedStateHandle
import com.festivalscoretracker.android.core.search.GlobalSearchLayout
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.ShellShortcut
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.ui.common.SearchChrome
import com.festivalscoretracker.android.ui.search.GlobalSearchHost

// region Root

/**
 * App root: theme, the single shared backdrop and the adaptive shell.
 *
 * @param container Process dependencies.
 * @param launch Debug launch extras for this activity creation.
 * @param shortcuts Activity key shortcuts (Ctrl+K, Search key, Ctrl+F) routed to the shell.
 */
@Composable
fun FestivalApp(container: AppContainer, launch: DebugLaunch, shortcuts: ShellShortcutBridge = remember { ShellShortcutBridge() }) {
    val shellViewModel: ShellViewModel = viewModel { ShellViewModel(container.settings, launch) }
    val settings by shellViewModel.settings.collectAsStateWithLifecycle()
    FestivalTheme(appIncreaseContrast = settings?.increaseContrast == true, appReduceMotion = settings?.reduceMotion == true) {
        LaunchedEffect(Unit) { container.background.start(this) }
        LaunchedEffect(Unit) { container.selectedProfile.start(this, shellViewModel.settings.map { it?.selectedPlayer }) }
        Box(Modifier.fillMaxSize()) {
            ArtworkBackground(container.background, forceStill = launch.stillBackground)
            settings?.let { FestivalShell(container, shellViewModel, it, launch, shortcuts) }
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
 * Material 3 navigation suite type for the pure [NavigationLayout] policy.
 *
 * @param layout Policy result.
 * @param widthDp Window width (bars show inline labels from 600 dp).
 * @return Suite type.
 */
internal fun suiteType(layout: NavigationLayout, widthDp: Int): NavigationSuiteType = when (layout) {
    NavigationLayout.BottomBar ->
        if (AdaptiveLayoutPolicy.isRegularWidth(widthDp)) NavigationSuiteType.ShortNavigationBarMedium else NavigationSuiteType.ShortNavigationBarCompact
    NavigationLayout.Rail -> NavigationSuiteType.WideNavigationRailCollapsed
    NavigationLayout.PermanentDrawer -> NavigationSuiteType.NavigationDrawer
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

/** Hinge bounds in window pixels. */
private fun HingeInfo.pxRect(): PxRect = PxRect(bounds.left.toInt(), bounds.top.toInt(), bounds.right.toInt(), bounds.bottom.toInt())

/** Latest reported search-entry bounds (non-snapshot, so layout reports never recompose the shell). */
private class SearchAnchorHolder {
    var last: PxRect? = null
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FestivalShell(
    container: AppContainer,
    shellViewModel: ShellViewModel,
    settings: AppSettings,
    launch: DebugLaunch,
    shortcuts: ShellShortcutBridge,
) {
    val density = LocalDensity.current
    val windowSize = currentWindowSize()
    val widthDp = with(density) { windowSize.width.toDp().value.toInt() }
    val heightDp = with(density) { windowSize.height.toDp().value.toInt() }
    val posture = currentWindowAdaptiveInfo().windowPosture
    val verticalHinge = posture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    val horizontalHinge = posture.hingeList.firstOrNull { it.isSeparating && !it.isVertical }
    val layout = AdaptiveLayoutPolicy.navigationLayout(widthDp, heightDp, posture.isTabletop)
    val navigationType = suiteType(layout, widthDp)
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

    // region Global search

    val searchViewModel: GlobalSearchViewModel = viewModel {
        GlobalSearchViewModel(
            loadCatalog = { container.api.catalog().catalog.songs },
            searchPlayers = { query, limit -> container.api.searchPlayers(query, limit) },
            selectedAccountId = { shellViewModel.settings.value?.selectedPlayer?.accountId },
            backoff = container.backoff,
            savedState = createSavedStateHandle(),
        )
    }
    val searchState = rememberSearchBarState()
    val presentation = GlobalSearchLayout.presentation(widthDp)
    val anchors = remember { SearchAnchorHolder() }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val fallbackRequester = with(density) {
        // Where the top bar's search action sits (before the avatar) when nothing reported yet.
        val top = (statusTop + 8.dp).roundToPx()
        PxRect(windowSize.width - 104.dp.roundToPx(), top, windowSize.width - 56.dp.roundToPx(), top + 48.dp.roundToPx())
    }
    var requester by remember { mutableStateOf<PxRect?>(null) }
    val anchor = remember(presentation, requester, windowSize, verticalHinge, horizontalHinge, fallbackRequester) {
        GlobalSearchLayout.anchor(
            presentation = presentation,
            requester = requester ?: fallbackRequester,
            windowWidth = windowSize.width,
            windowHeight = windowSize.height,
            density = density.density,
            verticalHinge = verticalHinge?.pxRect(),
            horizontalHinge = horizontalHinge?.pxRect(),
        )
    }
    val openSearch: (PxRect?) -> Unit = { rect ->
        requester = rect ?: anchors.last
        searchViewModel.open()
    }
    // Folding, rotating or resizing while open re-anchors to the entry the new layout reports.
    LaunchedEffect(presentation, windowSize) {
        if (searchViewModel.state.value.expanded) {
            withFrameNanos {}
            requester = anchors.last
        }
    }
    val pageFind = remember { PageFindRegistry() }
    val latestOpen by rememberUpdatedState(openSearch)
    DisposableEffect(shortcuts, pageFind) {
        shortcuts.handler = { shortcut ->
            when (shortcut) {
                ShellShortcut.OpenSearch -> latestOpen(null)
                ShellShortcut.FindInPage -> if (!pageFind.find()) latestOpen(null)
            }
            true
        }
        onDispose { shortcuts.handler = null }
    }
    LaunchedEffect(Unit) {
        launch.searchQuery?.let { query ->
            withFrameNanos {}
            requester = anchors.last
            searchViewModel.open(query)
            launch.searchScope?.let(searchViewModel::toggleScope)
        }
    }

    // endregion

    val navBars = WindowInsets.navigationBars.asPaddingValues()
    val safeEnd = WindowInsets.safeDrawing.asPaddingValues().calculateEndPadding(LocalLayoutDirection.current)
    // Bars sit below the content (they pad the gesture area themselves); rails and the
    // drawer leave the content edge-to-edge, so it clears the system navigation itself.
    val bottomPadding = PaddingValues(
        end = safeEnd,
        bottom = if (layout == NavigationLayout.BottomBar) 0.dp else navBars.calculateBottomPadding(),
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
        search = SearchChrome(presentation = presentation, open = openSearch, report = { anchors.last = it }),
    )
    val openDestination: (SearchDestination) -> Unit = { destination ->
        when (destination) {
            is SearchDestination.Push -> navController.navigate(destination.route)
            is SearchDestination.Section ->
                if (destination.section in sections) navController.selectSection(destination.section, selected) else navController.navigate(StatisticsRoute)
        }
    }

    var contentLeftPx by remember { mutableIntStateOf(0) }
    var contentWidthPx by remember { mutableIntStateOf(windowSize.width) }
    val contentWidthDp = with(density) { contentWidthPx.toDp().value.toInt() }
    val navigationSuite = @Composable {
        NavigationSuite(
            navigationSuiteType = navigationType,
            colors = NavigationSuiteDefaults.colors(
                shortNavigationBarContainerColor = BrandTokens.cardBackground.copy(alpha = 0.96f),
                shortNavigationBarContentColor = BrandTokens.textSecondary,
                wideNavigationRailColors = WideNavigationRailDefaults.colors(containerColor = BrandTokens.surfaceFrosted),
                navigationDrawerContainerColor = BrandTokens.surfaceFrosted,
            ),
            primaryActionContent = {
                if (layout == NavigationLayout.Rail) {
                    IconButton(onClick = { scope.launch { drawerState.open() } }, modifier = Modifier.testTag("fst.nav.drawer")) {
                        Icon(Icons.Filled.Menu, contentDescription = "Open menu")
                    }
                }
            },
            modifier = when (layout) {
                NavigationLayout.BottomBar -> Modifier.testTag("fst.nav.bar")
                NavigationLayout.Rail -> Modifier.testTag("fst.nav.rail")
                NavigationLayout.PermanentDrawer -> Modifier.width(PERMANENT_DRAWER_WIDTH_DP.dp).testTag("fst.nav.permanent-drawer")
            },
        ) {
            if (layout == NavigationLayout.PermanentDrawer) {
                DrawerContent(
                    sections = sections,
                    selected = selected,
                    player = settings.selectedPlayer,
                    onSection = { navController.selectSection(it, selected) },
                    onRoute = actions.navigate,
                )
            } else {
                sections.forEach { section ->
                    NavigationSuiteItem(
                        selected = section == selected,
                        onClick = { navController.selectSection(section, selected) },
                        icon = { Icon(section.icon(), contentDescription = null) },
                        label = { Text(section.title, maxLines = 1) },
                        navigationSuiteType = navigationType,
                        modifier = Modifier.testTag("fst.nav.tab.${section.name.lowercase()}"),
                    )
                }
            }
        }
    }
    val content = @Composable {
        CompositionLocalProvider(LocalShellActions provides actions, LocalPageFind provides pageFind) {
            NavigationSuiteScaffoldLayout(navigationSuite = navigationSuite, navigationSuiteType = navigationType) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .onGloballyPositioned {
                            contentLeftPx = it.positionInWindow().x.toInt()
                            contentWidthPx = it.size.width
                        },
                ) {
                    FestivalNavHost(
                        navController = navController,
                        container = container,
                        shellViewModel = shellViewModel,
                        settings = settings,
                        twoPane = AdaptiveLayoutPolicy.showsTwoPanes(widthDp, verticalHinge != null),
                        listPaneWidth = AdaptiveLayoutPolicy.listPaneWidth(
                            contentWidthDp,
                            verticalHinge?.let { with(density) { (it.bounds.left - contentLeftPx).toDp().value.toInt() } },
                        ),
                    )
                }
            }
        }
    }
    if (layout == NavigationLayout.PermanentDrawer) {
        content()
    } else {
        ModalNavigationDrawer(
            drawerState = drawerState,
            // Edge swipes belong to system back; the drawer opens from the menu button only.
            gesturesEnabled = drawerState.isOpen,
            drawerContent = { ModalDrawerSheet(drawerContainerColor = BrandTokens.cardBackground) { DrawerContent(emptyList(), selected, settings.selectedPlayer, { navController.selectSection(it, selected) }, actions.navigate) } },
        ) { content() }
    }
    GlobalSearchHost(
        viewModel = searchViewModel,
        searchState = searchState,
        presentation = presentation,
        anchor = anchor,
        artworkUrl = container.api::artworkUrl,
        onOpen = openDestination,
        onBandRankings = { navController.navigate(GlobalSearchResults.bandRankings) },
    )
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

/** Permanent drawer width on large windows. */
private const val PERMANENT_DRAWER_WIDTH_DP = 280

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
            SongLeaderboardScreen(boardViewModel, settings.selectedPlayer?.accountId)
        }
        leaderboardsGraph(container, shellViewModel, container.leaderboardPreferences)
        composable<SettingsTab> {
            SettingsScreen(settings = settings, shellViewModel = shellViewModel, serviceOrigin = api.origin)
        }
        placeholder<SuggestionsTab>("Suggestions", isRoot = true)
        placeholder<CompeteTab>("Compete", isRoot = true)
        placeholder<RivalsTab>("Rivals", isRoot = true)
        placeholder<StatisticsTab>("Statistics", isRoot = true)
        bandsDestinations(container)
        placeholder<PlayerHistoryRoute>("Score History")
        placeholder<PlayerRoute>("Player")
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
