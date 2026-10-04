package com.festivalscoretracker.android.ui.shell

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fitInside
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.statusBars
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
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuite
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldLayout
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.rememberSearchBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.WindowInsetsRulers
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.NavigationLayout
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SettingsTab
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.search.GlobalSearchLayout
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.ShellShortcut
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.shell.FloatingToolbarLift
import com.festivalscoretracker.android.core.shell.ListDetailLayout
import com.festivalscoretracker.android.core.shell.ListDetailPolicy
import com.festivalscoretracker.android.core.shell.ListHead
import com.festivalscoretracker.android.core.shell.ProfileRoutePolicy
import com.festivalscoretracker.android.data.notifications.playerNotifications
import com.festivalscoretracker.android.data.serviceinfo.serviceInfo
import com.festivalscoretracker.android.data.serviceinfo.serviceVersion
import com.festivalscoretracker.android.data.songs.watchDeselection
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.presentation.settings.SettingsViewModel
import com.festivalscoretracker.android.ui.background.ArtworkBackground
import com.festivalscoretracker.android.ui.bands.bandsDestinations
import com.festivalscoretracker.android.ui.common.ComingSoonScreen
import com.festivalscoretracker.android.ui.common.FLOATING_TOOLBAR_HEIGHT_DP
import com.festivalscoretracker.android.ui.common.FLOATING_TOOLBAR_MARGIN_DP
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FloatingToolbar
import com.festivalscoretracker.android.ui.common.FloatingToolbarHost
import com.festivalscoretracker.android.ui.common.FloatingToolbarScrollState
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.SearchChrome
import com.festivalscoretracker.android.ui.common.ShellActions
import com.festivalscoretracker.android.ui.common.rememberScreenReaderOn
import com.festivalscoretracker.android.ui.compete.competeDestinations
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoSongsSource
import com.festivalscoretracker.android.ui.firstrun.FirstRunHost
import com.festivalscoretracker.android.ui.firstrun.firstRunPage
import com.festivalscoretracker.android.ui.leaderboards.leaderboardsGraph
import com.festivalscoretracker.android.ui.notifications.NotificationsBell
import com.festivalscoretracker.android.ui.notifications.NotificationsSheet
import com.festivalscoretracker.android.ui.profile.PlayerHistoryScreen
import com.festivalscoretracker.android.ui.profile.PlayerProfileScreen
import com.festivalscoretracker.android.ui.profile.ProfileSheet
import com.festivalscoretracker.android.ui.profile.StatisticsScreen
import com.festivalscoretracker.android.ui.profile.playerHistoryViewModel
import com.festivalscoretracker.android.ui.profile.profileViewModel
import com.festivalscoretracker.android.ui.rivals.rivalsDestinations
import com.festivalscoretracker.android.ui.search.GlobalSearchHost
import com.festivalscoretracker.android.ui.settings.LicensesScreen
import com.festivalscoretracker.android.ui.settings.SettingsScreen
import com.festivalscoretracker.android.ui.settings.rememberFeedbackViewModel
import com.festivalscoretracker.android.ui.shop.ShopRouteScreen
import com.festivalscoretracker.android.ui.songdetail.SongDetailRouteScreen
import com.festivalscoretracker.android.ui.songdetail.SongLeaderboardRouteScreen
import com.festivalscoretracker.android.ui.songs.SongsRoute
import com.festivalscoretracker.android.ui.suggestions.suggestionsDestinations
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewHost
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import com.festivalscoretracker.android.ui.common.isLargeText

// region Root

/**
 * App root: theme, the single shared backdrop and the adaptive shell.
 *
 * @param container Process dependencies.
 * @param launch Debug launch extras for this activity creation.
 * @param shortcuts Activity key shortcuts (Ctrl+K, Search key, Ctrl+F) routed to the shell.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun FestivalApp(container: AppContainer, launch: DebugLaunch, shortcuts: ShellShortcutBridge = remember { ShellShortcutBridge() }) {
    val shellViewModel: ShellViewModel = viewModel { ShellViewModel(container.settings, launch) }
    val settings by shellViewModel.settings.collectAsStateWithLifecycle()
    FestivalTheme(
        appIncreaseContrast = settings?.increaseContrast == true,
        appReduceMotion = settings?.reduceMotion == true,
        appReduceTransparency = settings?.reduceTransparency == true,
    ) {
        LaunchedEffect(Unit) { container.background.start(this) }
        LaunchedEffect(Unit) { container.selectedProfile.start(this, shellViewModel.settings.map { it?.selectedPlayer }) }
        LaunchedEffect(Unit) { container.songsPreferences.watchDeselection(this, shellViewModel.settings.map { it?.selectedPlayer }) }
        // Compose test tags double as UIAutomator resource ids for `device.py drive` journeys.
        Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
            ArtworkBackground(container.background, forceStill = launch.stillBackground || settings?.disableAnimatedArtwork == true)
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
    var showNotifications by rememberSaveable { mutableStateOf(launch.opensNotifications) }
    val notificationsViewModel: NotificationsViewModel = viewModel {
        NotificationsViewModel(
            player = shellViewModel.settings.map { it?.selectedPlayer },
            load = { container.api.playerNotifications(it) },
            seenStore = container.notificationSeen,
            songTitle = { id -> runCatching { container.api.catalog().catalog.songs.firstOrNull { it.songId == id }?.title }.getOrNull() },
            artwork = { item ->
                val art = item.songId?.let { id -> runCatching { container.api.catalog().catalog.songs.firstOrNull { it.songId == id }?.albumArt }.getOrNull() }
                container.api.artworkUrl(art ?: item.payload?.albumArt)
            },
        )
    }

    LaunchedEffect(sections) {
        val resolved = FestivalTabPolicy.resolve(selected, sections)
        if (resolved != selected) navController.selectSection(resolved, selected)
    }
    // Web parity: profile-only pages (Rivals, Statistics, Suggestions, Compete, Player History)
    // redirect to Songs while no profile is selected — deep links and a deselect included.
    val topDestination = stack.lastOrNull()?.destination
    val hasProfile = settings.selectedPlayer != null
    LaunchedEffect(topDestination, hasProfile) {
        val destination = topDestination ?: return@LaunchedEffect
        if (ProfileRoutePolicy.requiresProfile.any { destination.hasRoute(it) && ProfileRoutePolicy.redirectsToSongs(it, hasProfile) }) {
            navController.navigate(SongsTab) {
                popUpTo(navController.graph.findStartDestination().id) { inclusive = true }
                launchSingleTop = true
            }
        }
    }
    LaunchedEffect(Unit) {
        launch.section?.takeIf { it in sections }?.let { navController.selectSection(it, FestivalSection.Songs) }
        launch.route?.let { navController.navigate(it) }
        launch.songQuery?.let { navController.navigate(SongDetailRoute(it, launch.songInstrument)) }
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
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val fallbackRequester = with(density) {
        // Where the top bar's search action sits (before the avatar) when nothing reported yet.
        val top = (statusTop + 8.dp).roundToPx()
        PxRect(windowSize.width - 104.dp.roundToPx(), top, windowSize.width - 56.dp.roundToPx(), top + 48.dp.roundToPx())
    }
    // Live bounds of the one search entry in the window. Structural equality means an
    // unchanged layout report is a no-op; a fold, rotation or resize re-anchors an open surface.
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
        if (rect != null) requester = rect
        searchViewModel.open()
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
            searchViewModel.open(query)
            launch.searchScope?.let(searchViewModel::toggleScope)
        }
    }

    // endregion

    val navBars = WindowInsets.navigationBars.asPaddingValues()
    val safeEnd = WindowInsets.safeDrawing.asPaddingValues().calculateEndPadding(LocalLayoutDirection.current)
    // Bars sit below the content (they pad the gesture area themselves); rails and the
    // drawer leave the content edge-to-edge, so it clears the system navigation itself.
    // Compact windows float screen actions + search over the bottom bar (M3 Expressive
    // floating toolbar, web bottom dock); wider windows keep them in the top app bar.
    val floatingToolbar = remember { FloatingToolbarHost() }
    val usesFloatingToolbar = !AdaptiveLayoutPolicy.isRegularWidth(widthDp)
    // M3 "exit always": the toolbar slides away while content scrolls toward its end and back
    // when it scrolls back; never hidden under TalkBack or on pages that pin it (Songs and
    // Suggestions keep Sort/Filter/Quick Links reachable while scrolled, issue #52); shown
    // again on every navigation.
    val toolbarScroll = remember { FloatingToolbarScrollState() }
    val touchExploration = rememberScreenReaderOn()
    val toolbarPinned = floatingToolbar.pinned
    toolbarScroll.hiddenOffsetPx = with(density) { (FLOATING_TOOLBAR_HEIGHT_DP + FLOATING_TOOLBAR_MARGIN_DP).dp.toPx() }
    toolbarScroll.enabled = !touchExploration && !toolbarPinned
    LaunchedEffect(stack.lastOrNull()?.id, touchExploration, toolbarPinned) { toolbarScroll.reset() }
    val bottomPadding = PaddingValues(
        end = safeEnd,
        bottom = when {
            usesFloatingToolbar -> (FLOATING_TOOLBAR_HEIGHT_DP + 2 * FLOATING_TOOLBAR_MARGIN_DP).dp
            layout == NavigationLayout.BottomBar -> 0.dp
            else -> navBars.calculateBottomPadding()
        },
    )
    // Only the phone top bar shows a hamburger; the rail header owns it on medium widths.
    val openDrawer: (() -> Unit)? = if (layout == NavigationLayout.BottomBar) ({ scope.launch { drawerState.open() } }) else null
    val actions = ShellActions(
        navigate = { route ->
            scope.launch { drawerState.close() }
            // A tab root (e.g. Songs after a profile tile saved its filter) switches tabs rather than pushing a copy.
            val section = FestivalSection.entries.firstOrNull { it.root == route }
            if (section != null && section in sections) navController.selectSection(section, selected) else navController.navigate(route)
        },
        back = { navController.popBackStack() },
        openDrawer = openDrawer,
        openProfile = { showProfile = true },
        selectedPlayer = settings.selectedPlayer,
        bottomPadding = bottomPadding,
        search = SearchChrome(presentation = presentation, open = openSearch, report = { requester = it }),
        // Web: the bell only exists while a profile is selected (operator 2026-09-28).
        notifications = if (settings.selectedPlayer != null) ({ NotificationsBell(notificationsViewModel) { showNotifications = true } }) else null,
        floatingToolbar = if (usesFloatingToolbar) floatingToolbar else null,
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
    // Content bottom to window bottom (bottom bar + system navigation): the keyboard covers that
    // strip before it reaches the floating toolbar (FloatingToolbarLift).
    var gapBelowContentPx by remember { mutableIntStateOf(0) }
    val imeInsets = WindowInsets.ime
    val contentWidthDp = with(density) { contentWidthPx.toDp().value.toInt() }
    // The Songs list pane leads the content row: the part of a start-side camera inset it covers.
    val direction = LocalLayoutDirection.current
    val cutout = WindowInsets.displayCutout
    val leadingCutoutPx = if (direction == LayoutDirection.Ltr) {
        cutout.getLeft(density, direction) - contentLeftPx
    } else {
        cutout.getRight(density, direction) - (windowSize.width - contentLeftPx - contentWidthPx)
    }
    val leadingCutoutDp = with(density) { leadingCutoutPx.coerceAtLeast(0).toDp().value.toInt() }
    val profileKind = shellViewModel.profileKind(settings)
    val drawer = @Composable { tabTags: Boolean ->
        DrawerContent(
            visible = sections,
            selected = selected,
            profile = profileKind,
            player = settings.selectedPlayer,
            onSection = {
                scope.launch { drawerState.close() }
                navController.selectSection(it, selected)
            },
            onRoute = actions.navigate,
            onOpenProfile = {
                scope.launch { drawerState.close() }
                showProfile = true
            },
            onDeselect = shellViewModel::deselectPlayer,
            showShop = !settings.hideShop,
            tabTags = tabTags,
            permanent = tabTags,
        )
    }
    val navigationSuite = @Composable {
        ChromeColors {
            if (layout == NavigationLayout.Rail) {
                FestivalRail(
                    sections = sections,
                    selected = selected,
                    player = settings.selectedPlayer,
                    onSection = { navController.selectSection(it, selected) },
                    onOpenDrawer = { scope.launch { drawerState.open() } },
                    onOpenProfile = { showProfile = true },
                )
            } else {
                NavigationSuite(
                    navigationSuiteType = navigationType,
                    colors = NavigationSuiteDefaults.colors(
                        shortNavigationBarContainerColor = BrandTokens.cardBackground.copy(alpha = 0.96f),
                        shortNavigationBarContentColor = BrandTokens.textPrimary,
                        // Transparent so the animated/song backdrop shows through (operator 2026-09-28).
                        navigationDrawerContainerColor = Color.Transparent,
                    ),
                    modifier = when (layout) {
                        NavigationLayout.PermanentDrawer -> Modifier.width(AdaptiveLayoutPolicy.permanentDrawerWidth(density.fontScale).dp).testTag("fst.nav.permanent-drawer")
                        else -> Modifier.testTag("fst.nav.bar")
                    },
                ) {
                    if (layout == NavigationLayout.PermanentDrawer) {
                        drawer(true)
                    } else {
                        // Large text: five labels cannot fit a phone's bar (they cut to "Sugg",
                        // "Stati"), so the bar shows icons only and each icon carries its name.
                        val iconOnly = isLargeText()
                        sections.forEach { section ->
                            NavigationSuiteItem(
                                selected = section == selected,
                                onClick = { navController.selectSection(section, selected) },
                                icon = { Icon(section.icon(), contentDescription = if (iconOnly) section.title else null) },
                                label = if (iconOnly) null else ({ Text(section.title, maxLines = 1) }),
                                navigationSuiteType = navigationType,
                                modifier = Modifier.testTag("fst.nav.tab.${section.name.lowercase()}"),
                            )
                        }
                    }
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
                        .then(if (usesFloatingToolbar) Modifier.nestedScroll(toolbarScroll.connection) else Modifier)
                        .onGloballyPositioned {
                            contentLeftPx = it.positionInWindow().x.toInt()
                            contentWidthPx = it.size.width
                            gapBelowContentPx = it.findRootCoordinates().size.height - (it.positionInWindow().y.toInt() + it.size.height)
                        },
                ) {
                    FestivalNavHost(
                        navController = navController,
                        container = container,
                        shellViewModel = shellViewModel,
                        settings = settings,
                        twoPane = AdaptiveLayoutPolicy.showsTwoPanes(widthDp, verticalHinge != null, density.fontScale),
                        hingeSplit = verticalHinge != null,
                        listPaneWidth = AdaptiveLayoutPolicy.listPaneWidth(
                            contentWidthDp,
                            verticalHinge?.let { with(density) { (it.bounds.left - contentLeftPx).toDp().value.toInt() } },
                            leadingInsetDp = leadingCutoutDp,
                        ),
                    )
                    if (usesFloatingToolbar) {
                        // Clipped to the content area: hidden on scroll it slides behind the bottom
                        // bar's edge instead of ghosting through the translucent bar (issue #102).
                        // The clip layer has no input or semantics, so touches and TalkBack pass through.
                        Box(Modifier.matchParentSize().clipToBounds()) {
                            // End-aligned (M3 Expressive floating toolbars may sit at the edge), where
                            // the web's mobile FAB dock sits; one shared toolbar per screen. The start
                            // margin bounds a toolbar that fills the width (Songs search, issue #84),
                            // and a toolbar holding a focused field rides above the keyboard (read in
                            // the layout phase, so the keyboard animation never recomposes the shell).
                            FloatingToolbar(
                                floatingToolbar,
                                Modifier
                                    .align(Alignment.BottomEnd)
                                    .offset {
                                        val lift = if (floatingToolbar.aboveKeyboard) FloatingToolbarLift.liftPx(imeInsets.getBottom(this), gapBelowContentPx) else 0
                                        IntOffset(0, -lift)
                                    }
                                    .padding(start = FLOATING_TOOLBAR_MARGIN_DP.dp, end = FLOATING_TOOLBAR_MARGIN_DP.dp, bottom = FLOATING_TOOLBAR_MARGIN_DP.dp),
                                scroll = toolbarScroll,
                            )
                        }
                    }
                }
            }
        }
    }
    // One movable page tree for both chrome branches: rotating a tablet between the rail and
    // the permanent drawer moves the NavHost instead of rebuilding it, so page state (an open
    // license, list scroll, picked filters) survives the change (issue #122).
    val latestContent = rememberUpdatedState(content)
    val pages = remember { movableContentOf { latestContent.value() } }
    if (layout == NavigationLayout.PermanentDrawer) {
        pages()
    } else {
        ModalNavigationDrawer(
            drawerState = drawerState,
            // Edge swipes belong to system back; the drawer opens from the menu button only.
            gesturesEnabled = drawerState.isOpen,
            // The drawerState overload adds M3's predictive back handling: system back closes
            // the open drawer instead of leaving the app. Its corners follow the display corners
            // (issue #55); without reported corners the shape is Material's default.
            drawerContent = {
                ChromeColors {
                    ModalDrawerSheet(
                        drawerState = drawerState,
                        drawerShape = rememberConcentricDrawerShape(),
                        drawerContainerColor = BrandTokens.cardBackground,
                    ) { drawer(false) }
                }
            },
        ) { pages() }
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
            onViewPlayer = { accountId, name -> actions.navigate(PlayerRoute(accountId, name)) },
            onDeselect = shellViewModel::deselectPlayer,
            onDismiss = { showProfile = false },
        )
    }
    if (showNotifications) {
        NotificationsSheet(
            viewModel = notificationsViewModel,
            onDismiss = { showNotifications = false },
            onNavigate = actions.navigate,
            onChooseProfile = { showProfile = true },
        )
    }
    val firstRunActive by container.firstRun.active.collectAsStateWithLifecycle()
    val whatsNewShown by container.whatsNew.shown.collectAsStateWithLifecycle()
    val firstRunDemoSongs = remember(container) {
        FirstRunDemoSongsSource({ container.api.catalog() }, container.shop.state, container.api.publicationChanges, container.api::artworkUrl)
    }
    FirstRunHost(
        center = container.firstRun,
        page = firstRunPage(stack.lastOrNull()),
        settings = settings,
        compact = !AdaptiveLayoutPolicy.isRegularWidth(widthDp),
        blocked = showProfile || showNotifications || whatsNewShown != null,
        demoSongs = firstRunDemoSongs,
    )
    // After the launch page's carousel (web order); Settings replays it.
    WhatsNewHost(
        controller = container.whatsNew,
        blocked = showProfile || showNotifications || firstRunActive != null,
        compact = !AdaptiveLayoutPolicy.isRegularWidth(widthDp),
    )
}

/**
 * Navigation chrome (bar, rail, drawers) with white text and icons: Material's unselected
 * items use `onSurfaceVariant` and bar labels `secondary`, which read gray/purple against the
 * backdrop; the web and the operator want white chrome text (batch 6.6).
 *
 * @param content Chrome content.
 */
@Composable
internal fun ChromeColors(content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    MaterialTheme(
        colorScheme = scheme.copy(onSurfaceVariant = BrandTokens.textPrimary, secondary = BrandTokens.textPrimary, onSurface = BrandTokens.textPrimary),
        typography = MaterialTheme.typography,
        shapes = MaterialTheme.shapes,
        content = content,
    )
}

// endregion

// region Nav host

@Composable
private fun FestivalNavHost(
    navController: NavHostController,
    container: AppContainer,
    shellViewModel: ShellViewModel,
    settings: AppSettings,
    twoPane: Boolean,
    hingeSplit: Boolean,
    listPaneWidth: Int,
) {
    val api = container.api
    NavHost(navController = navController, startDestination = SongsTab, modifier = Modifier.fillMaxSize()) {
        composable<SongsTab> {
            // Last song the user picked (on any width), restored whenever the window splits.
            var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
            var head by remember { mutableStateOf(ListHead()) }
            // Two populated columns whenever the width allows (operator 2026-09-28): the last
            // pick, else the list's first row; never an empty "Select a song" pane.
            val layout = ListDetailPolicy.layout(twoPane, hingeSplit, selectedId, head)
            val split = layout as? ListDetailLayout.Split
            // One call site for the list in every state, so its scroll position survives a split.
            Row(Modifier.fillMaxSize()) {
                Box(if (split != null) Modifier.width(listPaneWidth.dp) else Modifier.weight(1f)) {
                    SongsRoute(
                        container, shellViewModel, settings,
                        onSongClick = {
                            selectedId = it.songId
                            if (!twoPane) navController.navigate(SongDetailRoute(it.songId))
                        },
                        selectedSongId = split?.detailId,
                        onListHead = { loaded, first -> head = ListHead(loaded, first) },
                    )
                }
                if (split != null) {
                    VerticalDivider(color = BrandTokens.glassBorder)
                    Box(
                        Modifier.weight(1f).fillMaxHeight().fitInside(WindowInsetsRulers.DisplayCutout.current).testTag("fst.songs.detail-pane"),
                        contentAlignment = Alignment.Center,
                    ) {
                        val id = split.detailId
                        when {
                            id != null -> SongDetailRouteScreen(container, shellViewModel, settings, id, embedded = true)
                            head.loaded -> FestivalEmptyState("No songs", Modifier.fillMaxSize().testTag("fst.songs.detail-empty"))
                            else -> FestivalLoading("Loading songs")
                        }
                    }
                }
            }
        }
        composable<SongDetailRoute> { entry ->
            val route = entry.toRoute<SongDetailRoute>()
            SongDetailRouteScreen(container, shellViewModel, settings, route.songId, embedded = false, instrument = route.instrument)
        }
        composable<SongLeaderboardRoute> { entry ->
            SongLeaderboardRouteScreen(container, settings, entry.savedStateHandle.toRoute<SongLeaderboardRoute>(), entry.savedStateHandle)
        }
        leaderboardsGraph(container, shellViewModel, container.leaderboardPreferences)
        composable<SettingsTab> {
            val settingsViewModel: SettingsViewModel = viewModel {
                SettingsViewModel(container.settings, readServiceInfo = api::serviceInfo, readServiceVersion = api::serviceVersion)
            }
            val replayScope = rememberCoroutineScope()
            val compact = !AdaptiveLayoutPolicy.isRegularWidth(with(LocalDensity.current) { currentWindowSize().width.toDp().value.toInt() })
            SettingsScreen(settings, settingsViewModel, api.origin, onReplayFirstRun = { page ->
                replayScope.launch { container.firstRun.beginReplay(page, compact) }
            }, onShowWhatsNew = { replayScope.launch { container.whatsNew.replay() } }, feedback = rememberFeedbackViewModel(api))
        }
        suggestionsDestinations(container, shellViewModel.settings)
        composable<LicensesRoute> { LicensesScreen() }
        composable<StatisticsTab> {
            StatisticsScreen(profileViewModel(container, shellViewModel, accountId = null, name = null))
        }
        composable<StatisticsRoute> {
            StatisticsScreen(profileViewModel(container, shellViewModel, accountId = null, name = null), isRoot = false)
        }
        composable<PlayerRoute> { entry ->
            val route = entry.toRoute<PlayerRoute>()
            PlayerProfileScreen(profileViewModel(container, shellViewModel, route.accountId, route.displayName))
        }
        composable<PlayerHistoryRoute> { entry ->
            val route = entry.toRoute<PlayerHistoryRoute>()
            PlayerHistoryScreen(playerHistoryViewModel(container, shellViewModel, route))
        }
        bandsDestinations(container)
        rivalsDestinations(container, settings)
        competeDestinations(container, settings)
        composable<ShopRoute> { ShopRouteScreen(container, shellViewModel) }
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
