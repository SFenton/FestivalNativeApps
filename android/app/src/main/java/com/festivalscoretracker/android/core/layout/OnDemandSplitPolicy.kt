package com.festivalscoretracker.android.core.layout

import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.shell.PxSpan
import kotlin.reflect.KClass

// region List pages

/**
 * A page that opens some of its sub-pages in a trailing pane beside itself when the window
 * allows a split: Android's form of the iPhone Duo's `OnDemandSplitPolicy.ListPage`
 * (owner-approved Android variant of `split-panes`, issue #583). Every other page (Songs, the
 * boards themselves, Shop, Suggestions, Statistics, profiles, Rivalry) stays one full-width page.
 * Settings keeps its own list/detail split (#371).
 */
enum class SplitListPage {
    /** Rivals hub and All Rivals: Rival Detail opens beside the list. */
    Rivals,

    /** Compete: only Rival Detail opens beside it (#369); View All and rankings push full width. */
    Compete,

    /** Leaderboards overview: Full Rankings and Band Rankings ("View all rankings", #352). */
    Leaderboards,

    /** Song Detail: the song's instrument board, band board (#367) and Score History (#342). */
    SongDetail,
    ;

    /**
     * Whether a route pushed from this page opens in the trailing pane.
     *
     * @param route Route the page navigates to.
     * @return True for this page's detail routes.
     */
    fun accepts(route: AppRoute): Boolean = when (this) {
        Rivals, Compete -> route is RivalDetailRoute
        Leaderboards -> route is FullRankingsRoute || route is BandRankingsRoute
        SongDetail -> route is SongLeaderboardRoute || route is SongBandLeaderboardRoute || route is PlayerHistoryRoute
    }
}

// endregion

// region Policy

/**
 * The trailing pane's geometry in the split container, in pixels.
 *
 * @property leadingPx Width of the leading (list) pane.
 * @property bandPx Width of the band between the panes: the fold's own width in book posture,
 *   0 at a midpoint. Nothing is drawn in it (`split-panes` R1: no divider line).
 * @property trailingPx Width of the trailing (detail) pane.
 * @property hinge Whether the band is a separating vertical fold (book posture).
 */
data class SplitGeometry(val leadingPx: Int, val bandPx: Int, val trailingPx: Int, val hinge: Boolean)

/**
 * What the split needs to know about its window and container.
 *
 * @property windowWidthPx Window width.
 * @property windowHeightPx Window height.
 * @property density Pixels per dp.
 * @property fontScale User font scale.
 * @property container The split container (the shell's content area) in window pixels.
 * @property safe The window's safe horizontal span (between side system bars and cutouts), or
 *   null to use the whole container.
 * @property hinge A separating vertical fold (book posture) in window pixels, if any.
 * @property rtl Right-to-left layout: the leading pane is the right one.
 */
data class SplitContext(
    val windowWidthPx: Int,
    val windowHeightPx: Int,
    val density: Float,
    val fontScale: Float,
    val container: PxSpan,
    val safe: PxSpan? = null,
    val hinge: PxSpan? = null,
    val rtl: Boolean = false,
)

/**
 * One back-stack entry as the split sees it.
 *
 * @property page The list page this entry shows, or null.
 * @property route The entry's route when it can sit in a trailing pane ([OnDemandSplitPolicy.opensInPane]), else null.
 */
data class SplitStackItem(val page: SplitListPage?, val route: AppRoute?)

/**
 * Where and when a list page opens its sub-pages in a trailing pane (Android's form of Apple's
 * `OnDemandSplitPolicy`, issue #583), kept pure for unit tests.
 *
 * - **When:** the window is landscape, regular width (≥ 600 dp) and height (≥ 480 dp), and each
 *   pane is at least [MIN_PANE_WIDTH_DP] wide; or a separating vertical fold (book posture) leaves
 *   at least [MIN_HINGE_PANE_WIDTH_DP] on each side, whatever the window's aspect. Portrait,
 *   compact and narrow flat windows push full width.
 * - **Where:** at the fold in book posture, else at the midpoint of the container's free width.
 * - **Large text:** from [LARGE_TEXT_SCALE] each pane must be
 *   [MIN_PANE_WIDTH_DP] wide in text-scaled dp, the rule Android's Settings split uses (#371).
 */
object OnDemandSplitPolicy {
    /** Narrowest pane, in dp (Apple `minimumPaneWidth`). */
    const val MIN_PANE_WIDTH_DP = 360

    /**
     * Narrowest pane beside a fold, in dp: in book posture each half is its own screen (beside
     * the navigation rail it is under 360 dp on most foldables), so the split follows the fold
     * down to the narrowest fold pane Android's fold layouts already support (Shop
     * `SHOP_MIN_PANE`; boards stack their rows below it, #115).
     */
    const val MIN_HINGE_PANE_WIDTH_DP = 240

    /** Material compact/medium width boundary. */
    const val REGULAR_WIDTH_DP = 600

    /** Material compact/medium height boundary. */
    const val REGULAR_HEIGHT_DP = 480

    /** Font scale from which the minimum pane width is measured in text-scaled dp. */
    const val LARGE_TEXT_SCALE = 1.3f

    private val listPages: Map<KClass<out AppRoute>, SplitListPage> = mapOf(
        RivalsTab::class to SplitListPage.Rivals,
        RivalsRoute::class to SplitListPage.Rivals,
        AllRivalsRoute::class to SplitListPage.Rivals,
        CompeteTab::class to SplitListPage.Compete,
        CompeteRoute::class to SplitListPage.Compete,
        LeaderboardsTab::class to SplitListPage.Leaderboards,
        LeaderboardsRoute::class to SplitListPage.Leaderboards,
        SongDetailRoute::class to SplitListPage.SongDetail,
    )

    /** Route classes that are list pages (their destinations host a split). */
    val listPageRoutes: Set<KClass<out AppRoute>> get() = listPages.keys

    /** Route classes that may sit in a trailing pane. */
    val paneRoutes: Set<KClass<out AppRoute>> = setOf(
        FullRankingsRoute::class,
        BandRankingsRoute::class,
        SongLeaderboardRoute::class,
        SongBandLeaderboardRoute::class,
        PlayerHistoryRoute::class,
        RivalDetailRoute::class,
        RivalryRoute::class,
    )

    /**
     * The list page a destination shows.
     *
     * @param route The destination's route class.
     * @return The list page, or null for a page that never splits.
     */
    fun page(route: KClass<out AppRoute>): SplitListPage? = listPages[route]

    /**
     * Whether a route pushed from inside the trailing pane stays in it: the open item's own
     * sub-pages (Rivalry, another board or page of a board). Profiles, songs, tabs and every
     * other page open full width over the split, and Back returns to the split (#352).
     *
     * @param route Route pushed from a page in the trailing pane.
     * @return True to push it inside the pane.
     */
    fun opensInPane(route: AppRoute): Boolean = route::class in paneRoutes

    /**
     * The panes for a window, or null when the split does not apply (one full-width page).
     *
     * @param context Window, container, fold and text scale.
     * @return The geometry, or null.
     */
    fun geometry(context: SplitContext): SplitGeometry? {
        val box = context.container
        val width = box.right - box.left
        if (width <= 0 || context.density <= 0f) return null
        val heightDp = context.windowHeightPx / context.density
        if (heightDp < REGULAR_HEIGHT_DP) return null
        val largeText = context.fontScale >= LARGE_TEXT_SCALE
        val hinge = context.hinge?.takeIf { (it.left + it.right) / 2 in (box.left + 1) until box.right }
        val minPaneDp = when {
            largeText -> MIN_PANE_WIDTH_DP * context.fontScale
            hinge != null -> MIN_HINGE_PANE_WIDTH_DP.toFloat()
            else -> MIN_PANE_WIDTH_DP.toFloat()
        }
        val minPanePx = minPaneDp * context.density
        val bandLeft: Int
        val bandRight: Int
        if (hinge != null) {
            bandLeft = hinge.left.coerceAtLeast(box.left)
            bandRight = hinge.right.coerceAtMost(box.right)
        } else {
            val landscape = context.windowWidthPx > context.windowHeightPx
            val regularWidth = context.windowWidthPx / context.density >= REGULAR_WIDTH_DP
            if (!landscape || !regularWidth) return null
            val mid = freeMid(box, context.safe)
            bandLeft = mid
            bandRight = mid
        }
        val left = bandLeft - box.left
        val right = box.right - bandRight
        if (left < minPanePx || right < minPanePx) return null
        return SplitGeometry(
            leadingPx = if (context.rtl) right else left,
            bandPx = bandRight - bandLeft,
            trailingPx = if (context.rtl) left else right,
            hinge = hinge != null,
        )
    }

    /**
     * The midpoint of the part of [container] inside [safe], or of the whole container when
     * there is no safe span or it misses the container (Apple `freeMidX`).
     *
     * @param container The split container.
     * @param safe The window's safe horizontal span.
     * @return The x of the free space's midpoint.
     */
    fun freeMid(container: PxSpan, safe: PxSpan?): Int {
        val lower = maxOf(container.left, safe?.left ?: container.left)
        val upper = minOf(container.right, safe?.right ?: container.right)
        return if (upper > lower) (lower + upper) / 2 else (container.left + container.right) / 2
    }

    /**
     * Where a full-width back stack moves into a split when the window starts allowing one
     * (rotation, unfolding, resizing): the topmost list page directly followed by a route it
     * accepts, with only pane routes above that.
     *
     * @param stack The back stack, bottom first.
     * @return The list page's index (the routes above it move into its pane), or null.
     */
    fun expandCut(stack: List<SplitStackItem>): Int? {
        for (index in stack.indices.reversed()) {
            val page = stack[index].page ?: continue
            if (index == stack.lastIndex) return null
            val first = stack[index + 1].route ?: return null
            if (!page.accepts(first)) return null
            if (stack.drop(index + 1).any { it.route == null }) return null
            return index
        }
        return null
    }
}

// endregion
