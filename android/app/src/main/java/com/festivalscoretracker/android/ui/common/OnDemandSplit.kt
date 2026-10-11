package com.festivalscoretracker.android.ui.common

import androidx.activity.OnBackPressedDispatcher
import androidx.activity.OnBackPressedDispatcherOwner
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.festivalscoretracker.android.core.layout.OnDemandSplitPolicy
import com.festivalscoretracker.android.core.layout.SplitGeometry
import com.festivalscoretracker.android.core.layout.SplitListPage
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.serialization.Serializable

// region Environment

/** The trailing pane's start destination while nothing is open. */
@Serializable
data object EmptyPaneRoute

/**
 * List pages waiting to reopen sub-pages in their trailing pane: when the window starts
 * allowing a split, the shell pops the full-width sub-pages and leaves their routes here, keyed
 * by the list page's back-stack entry ID.
 */
class SplitHandoffs {
    private val pending = mutableMapOf<String, List<AppRoute>>()

    /**
     * Leave routes for a list page.
     *
     * @param entryId The list page's back-stack entry ID.
     * @param routes Routes to open in its trailing pane, bottom first.
     */
    fun put(entryId: String, routes: List<AppRoute>) {
        pending[entryId] = routes
    }

    /**
     * Take (and forget) the routes left for a list page.
     *
     * @param entryId The list page's back-stack entry ID.
     * @return The routes, or null when none are waiting.
     */
    fun take(entryId: String): List<AppRoute>? = pending.remove(entryId)
}

/**
 * System Back for open trailing panes. The shell registers one `BackHandler` for it right after
 * its `NavHost`, so an open pane closes before the page is popped while the modal drawer and
 * global search, registered later, still close first.
 */
@Stable
class SplitBackRegistry {
    private class Entry(val enabled: State<Boolean>, val onBack: () -> Unit)

    private val entries = mutableStateListOf<Entry>()

    /** Whether some list page on top has its pane open. */
    val enabled: Boolean get() = entries.any { it.enabled.value }

    /**
     * Close or pop the topmost enabled pane.
     *
     * @return False when no pane took Back.
     */
    fun back(): Boolean {
        val entry = entries.lastOrNull { it.enabled.value } ?: return false
        entry.onBack()
        return true
    }

    /**
     * Register a list page's pane.
     *
     * @param enabled Whether the pane is open and its page is on top.
     * @param onBack Pop the pane's top page, or close it at its root.
     * @return Unregister callback.
     */
    fun register(enabled: State<Boolean>, onBack: () -> Unit): () -> Unit {
        val entry = Entry(enabled, onBack)
        entries += entry
        return { entries.remove(entry) }
    }
}

/**
 * What the shell gives list pages for their on-demand split.
 *
 * @property geometry The panes for the current window, or null when the window doesn't allow a split.
 * @property paneGraph Registers the app's destinations in a trailing pane's own `NavHost`.
 * @property handoffs Sub-pages moving into a pane after a window change.
 * @property back Back for open panes.
 * @property toolbarLift How far the floating toolbar rises above the content bottom (beside a rail
 *   or drawer: the system navigation bar).
 */
@Stable
class OnDemandSplitEnvironment(
    val geometry: SplitGeometry?,
    val paneGraph: NavGraphBuilder.() -> Unit,
    val handoffs: SplitHandoffs,
    val back: SplitBackRegistry,
    val toolbarLift: Dp,
)

/** The shell's split environment; null outside the shell (previews, isolated tests). */
val LocalOnDemandSplit = compositionLocalOf<OnDemandSplitEnvironment?> { null }

/**
 * The trailing pane around the pages in it: [FestivalScreen] shows Close instead of Back on the
 * pane's first page and leaves global search, the bell and the avatar to the list page's bar.
 *
 * @property close Close the pane.
 */
@Stable
class SplitPaneScope(private val rootId: State<String?>, val close: () -> Unit) {
    /**
     * Whether a page is the pane's first page.
     *
     * @param entryId The page's back-stack entry ID.
     * @return True for the pane's root.
     */
    fun isRoot(entryId: String?): Boolean = entryId != null && entryId == rootId.value
}

/** The trailing pane the current page sits in, or null. */
val LocalSplitPane = compositionLocalOf<SplitPaneScope?> { null }

/**
 * Whether the current page is the first page of a trailing pane, beside its list page: a song
 * board there is titled by its instrument or band size instead of the song header
 * (`song-leaderboard-header` variant #342, adopted on Android by #583).
 *
 * @return True for a trailing pane's root page.
 */
@Composable
fun isSplitPaneRoot(): Boolean {
    val pane = LocalSplitPane.current ?: return false
    return pane.isRoot((LocalViewModelStoreOwner.current as? NavBackStackEntry)?.id)
}

// endregion

// region Back-stack entries

/**
 * The route of an entry that can sit in a trailing pane, read from its saved state so a board's
 * current page and filters move with it.
 *
 * @return The route, or null for other destinations.
 */
fun NavBackStackEntry.paneRoute(): AppRoute? {
    val handle = savedStateHandle
    return with(destination) {
        when {
            hasRoute(FullRankingsRoute::class) -> handle.toRoute<FullRankingsRoute>()
            hasRoute(BandRankingsRoute::class) -> handle.toRoute<BandRankingsRoute>()
            hasRoute(SongLeaderboardRoute::class) -> handle.toRoute<SongLeaderboardRoute>()
            hasRoute(SongBandLeaderboardRoute::class) -> handle.toRoute<SongBandLeaderboardRoute>()
            hasRoute(PlayerHistoryRoute::class) -> handle.toRoute<PlayerHistoryRoute>()
            hasRoute(RivalDetailRoute::class) -> handle.toRoute<RivalDetailRoute>()
            hasRoute(RivalryRoute::class) -> handle.toRoute<RivalryRoute>()
            else -> null
        }
    }
}

/**
 * The list page an entry shows.
 *
 * @return The page, or null for a page that never splits.
 */
fun NavBackStackEntry.splitListPage(): SplitListPage? =
    OnDemandSplitPolicy.listPageRoutes.firstOrNull { destination.hasRoute(it) }?.let(OnDemandSplitPolicy::page)

// endregion

// region Host

/** Hairline colour under Increase Contrast at a midpoint (`split-panes` R2, Apple `white.opacity(0.16)`). */
private val ContrastHairline = Color.White.copy(alpha = 0.16f)

/** Duration of the leading pane's width change as the trailing pane opens or closes. */
private const val SPLIT_RESIZE_MS = 300

/**
 * A list page that opens its sub-pages in a trailing pane when the window allows a split
 * (owner-approved Android variant of `split-panes`, issue #583; Apple `OnDemandSplitStack`).
 *
 * With nothing open the page fills the width. A route the page accepts ([SplitListPage.accepts])
 * opens in the trailing pane, which has its own back stack: the open item's sub-pages
 * ([OnDemandSplitPolicy.opensInPane]) push inside it, everything else opens full width over the
 * split. Back closes the pane first (system Back and the page's top-bar Back), then leaves the
 * page. The panes meet at the fold in book posture, else at the free-space midpoint, with no
 * drawn divider. When the window stops allowing a split the open sub-pages become ordinary pushed
 * pages. Outside the shell, or inside another pane, the page is shown as is.
 *
 * @param page Which list page this is.
 * @param content The list page.
 */
@Composable
fun OnDemandSplit(page: SplitListPage, content: @Composable () -> Unit) {
    val split = LocalOnDemandSplit.current
    if (split == null || LocalSplitPane.current != null) {
        content()
        return
    }
    val shell = LocalShellActions.current
    val owner = LocalViewModelStoreOwner.current as? NavBackStackEntry
    val inner = rememberNavController()
    val innerStack by inner.currentBackStack.collectAsState()
    val paneEntries = innerStack.filter { it.destination !is NavGraph && !it.destination.hasRoute(EmptyPaneRoute::class) }
    val open = paneEntries.isNotEmpty()
    val geometry = split.geometry
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val onTop = lifecycleState.isAtLeast(Lifecycle.State.RESUMED)

    val openItem: (AppRoute) -> Unit = { route -> inner.navigate(route) { popUpTo<EmptyPaneRoute>() } }
    val close: () -> Unit = { inner.popBackStack<EmptyPaneRoute>(inclusive = false) }
    val paneBack: () -> Unit = {
        val depth = inner.currentBackStack.value.count { it.destination !is NavGraph && !it.destination.hasRoute(EmptyPaneRoute::class) }
        if (depth > 1) inner.popBackStack() else close()
    }
    val latestPaneBack by rememberUpdatedState(paneBack)
    val backEnabled = rememberUpdatedState(open && onTop)
    DisposableEffect(split.back) {
        val unregister = split.back.register(backEnabled) { latestPaneBack() }
        onDispose { unregister() }
    }
    // Sub-pages pushed full width before the window allowed a split move into the pane.
    LaunchedEffect(owner?.id) {
        val routes = owner?.id?.let(split.handoffs::take) ?: return@LaunchedEffect
        routes.forEachIndexed { index, route -> if (index == 0) openItem(route) else inner.navigate(route) }
    }
    // The window no longer allows a split: the open sub-pages become ordinary pushed pages.
    LaunchedEffect(geometry == null, open, onTop) {
        if (geometry == null && open && onTop) {
            val routes = inner.currentBackStack.value.mapNotNull { it.paneRoute() }
            close()
            routes.forEach(shell.navigate)
        }
    }

    val splitShown = geometry != null && open
    val leadingActions = shell.copy(
        navigate = { route -> if (geometry != null && page.accepts(route)) openItem(route) else shell.navigate(route) },
        back = { if (open) close() else shell.back() },
        // The leading pane's end edge is the band, not a window edge.
        bottomPadding = if (splitShown) PaddingValues(bottom = shell.bottomPadding.calculateBottomPadding()) else shell.bottomPadding,
    )
    val paneToolbar = remember { FloatingToolbarHost() }
    val paneActions = shell.copy(
        navigate = { route -> if (OnDemandSplitPolicy.opensInPane(route)) inner.navigate(route) else shell.navigate(route) },
        back = paneBack,
        notifications = null,
        floatingToolbar = paneToolbar,
    )
    val rootId = remember(inner) { derivedStateOf { inner.currentBackStack.value.firstOrNull { it.destination !is NavGraph && !it.destination.hasRoute(EmptyPaneRoute::class) }?.id } }
    val paneScope = remember(rootId) { SplitPaneScope(rootId) { inner.popBackStack<EmptyPaneRoute>(inclusive = false) } }
    val accessibility = LocalFestivalAccessibility.current
    val density = LocalDensity.current

    BoxWithConstraints(Modifier.fillMaxSize().testTag("fst.split")) {
        val fullPx = constraints.maxWidth
        val targetPx = if (splitShown) geometry!!.leadingPx.coerceAtMost(fullPx) else fullPx
        val leadingPx by animateIntAsState(targetPx, if (accessibility.reduceMotion) snap() else tween(SPLIT_RESIZE_MS), label = "split-leading")
        val bandPx = if (splitShown) geometry!!.bandPx else 0
        Row(Modifier.fillMaxSize()) {
            Box(Modifier.width(with(density) { leadingPx.toDp() }).fillMaxHeight().testTag("fst.split.leading")) {
                CompositionLocalProvider(LocalShellActions provides leadingActions) { content() }
            }
            // The band: the fold in book posture, else nothing at the midpoint (split-panes R1);
            // under Increase Contrast a midpoint draws a hairline (R2), a fold never does.
            if (bandPx > 0) Spacer(Modifier.width(with(density) { bandPx.toDp() }).fillMaxHeight())
            Box(
                Modifier
                    .weight(1f, fill = true)
                    .fillMaxHeight()
                    .then(if (splitShown) Modifier.testTag("fst.split.trailing") else Modifier)
                    // Read after the list page and its floating toolbar (traversal index 1).
                    .semantics { isTraversalGroup = true; traversalIndex = 2f },
            ) {
                TrailingPane(split, inner, paneActions, paneScope, paneToolbar)
                if (splitShown && !geometry!!.hinge && accessibility.increaseContrast) {
                    Box(Modifier.align(Alignment.CenterStart).width(1.dp).fillMaxHeight().background(ContrastHairline).testTag("fst.split.hairline"))
                }
            }
        }
    }
}

@Composable
private fun TrailingPane(
    split: OnDemandSplitEnvironment,
    inner: androidx.navigation.NavHostController,
    actions: ShellActions,
    scope: SplitPaneScope,
    toolbar: FloatingToolbarHost,
) {
    // The pane's NavHost would register its own system-Back callback whenever it composes, ahead
    // of the drawer and global search; the shell's one split Back handler (SplitBackRegistry)
    // drives the pane instead, so the pane's NavHost gets a dispatcher nothing ever invokes.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val isolatedBack = remember(lifecycle) {
        object : OnBackPressedDispatcherOwner {
            override val onBackPressedDispatcher = OnBackPressedDispatcher()
            override val lifecycle: Lifecycle = lifecycle
        }
    }
    // Its floating toolbar never hides on scroll (`page-tools-and-nav-chrome` R7, #577).
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalShellActions provides actions, LocalSplitPane provides scope, LocalOnBackPressedDispatcherOwner provides isolatedBack) {
            NavHost(navController = inner, startDestination = EmptyPaneRoute, modifier = Modifier.fillMaxSize()) {
                composable<EmptyPaneRoute> {}
                split.paneGraph(this)
            }
        }
        FloatingToolbar(
            toolbar,
            Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.End))
                .padding(end = FLOATING_TOOLBAR_MARGIN_DP.dp, bottom = FLOATING_TOOLBAR_MARGIN_DP.dp + split.toolbarLift),
        )
    }
}

// endregion
