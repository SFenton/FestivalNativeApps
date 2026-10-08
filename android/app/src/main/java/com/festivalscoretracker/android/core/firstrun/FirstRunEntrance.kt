package com.festivalscoretracker.android.core.firstrun

import com.festivalscoretracker.android.core.shop.ShopPulse
import kotlin.math.ceil
import kotlin.math.floor

// region Entrance timing

/**
 * The web first-run entrance (issue #380): every slide visit replays the demo's `fadeInUp`
 * cascade, then the title and description fade in after it (web `FirstRunCarousel`
 * `contentStaggerCount`). Pure rules, so the stagger, row fitting and pulse patterns are
 * unit-tested; drawing goes through the shared `festivalFadeIn` (`load-transition`).
 */
object FirstRunEntrance {
    /** Web `FADE_DURATION`: one item's fade (Material "Medium 4", 400 ms enter). */
    const val FADE_MS: Int = 400

    /** Web `STAGGER_INTERVAL`: the default cascade step. */
    const val STAGGER_MS: Int = 125

    /** Web Shop, Statistics and Leaderboards demo rows (`delay={i * 80}`). */
    const val ROW_MS: Int = 80

    /** Web `ShopOverviewDemo` grid tiles (`delay={i * 60}`). */
    const val GRID_MS: Int = 60

    /** Web controls demos: the second group (sort direction, filter toggles, nav bar) at 300 ms. */
    const val SECOND_GROUP_MS: Int = 300

    /** Web `InfiniteScrollDemo` speed, px (dp) per second. */
    const val SCROLL_DP_PER_SECOND: Float = 30f

    /** Web `InfiniteScrollDemo` start delay before the list moves. */
    const val SCROLL_START_MS: Long = 100

    /** Slides without an entry in [STAGGER_COUNTS] (web default `contentStaggerCount`). */
    private const val DEFAULT_STAGGER_COUNT = 3

    /**
     * Web `contentStaggerCount` per slide: how many cascade steps the demo takes before the
     * title fades in.
     */
    val STAGGER_COUNTS: Map<String, Int> = mapOf(
        "compete-hub" to 1, "compete-leaderboards" to 6, "compete-rivals" to 4,
        "playerhistory-score-list" to 5, "playerhistory-sort" to 3,
        "leaderboards-overview" to 4, "leaderboards-experimental-metrics" to 6, "leaderboards-your-rank" to 7,
        "statistics-drill-down" to 2, "statistics-instrument-breakdown" to 3, "statistics-overview" to 3,
        "statistics-percentiles" to 2, "statistics-select-profile" to 1, "statistics-top-songs" to 3,
        "rivals-overview" to 4, "rivals-instruments" to 6, "rivals-detail" to 4,
        "shop-overview" to 6, "shop-highlighting" to 5, "shop-new-items" to 5, "shop-leaving-tomorrow" to 5,
        "songinfo-top-scores" to 6, "songinfo-view-all" to 5,
        "songs-metadata" to 4, "songs-icons" to 4, "songs-song-list" to 4,
        "suggestions-category-card" to 2, "suggestions-global-filter" to 3,
        "suggestions-infinite-scroll" to 1, "suggestions-instrument-filter" to 3,
    )

    /** Slides whose demo rows cascade every [ROW_MS] rather than [STAGGER_MS]. */
    private val ROW_SLIDES = setOf(
        "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow",
        "statistics-overview", "statistics-instrument-breakdown",
        "leaderboards-overview", "compete-leaderboards", "leaderboards-your-rank",
    )

    /**
     * Cascade steps before a slide's title.
     *
     * @param id Slide ID.
     * @return Step count.
     */
    fun staggerCount(id: String): Int = STAGGER_COUNTS[id] ?: DEFAULT_STAGGER_COUNT

    /**
     * Title fade delay (web `count * STAGGER_INTERVAL`).
     *
     * @param id Slide ID.
     * @return Delay in ms.
     */
    fun titleDelay(id: String): Int = staggerCount(id) * STAGGER_MS

    /**
     * Description fade delay, one step after the title.
     *
     * @param id Slide ID.
     * @return Delay in ms.
     */
    fun descriptionDelay(id: String): Int = (staggerCount(id) + 1) * STAGGER_MS

    /**
     * The cascade step between a slide's demo rows.
     *
     * @param id Slide ID.
     * @return Step in ms.
     */
    fun rowInterval(id: String): Int = when (id) {
        "shop-overview" -> GRID_MS
        in ROW_SLIDES -> ROW_MS
        else -> STAGGER_MS
    }

    /**
     * One demo row's fade delay.
     *
     * @param id Slide ID.
     * @param index Row index.
     * @param lead Steps before the first row (a header takes step 0, rows then start at 1).
     * @return Delay in ms.
     */
    fun rowDelay(id: String, index: Int, lead: Int = 0): Int = (index + lead).coerceAtLeast(0) * rowInterval(id)
}

// endregion

// region Fitting

/**
 * Fitting demos to the 220 dp frame (web `useSlideHeight`): demos draw only whole rows, never a
 * clipped or squashed one. The UI measures the real rows for each candidate
 * (`DemoFitFirst`); these are the pure candidate orders and window rules.
 */
object FirstRunDemoFit {
    /** Designed demo frame height (the carousel's `DEMO_HEIGHT_DP`). */
    const val FRAME_DP: Float = 220f

    /**
     * Row counts to try, most first (web `useSlideHeight` shows as many whole rows as fit).
     *
     * @param max Most rows the demo has.
     * @param min Fewest rows it shows even when they don't fit.
     * @return `max` down to `min`.
     */
    fun rowCandidates(max: Int, min: Int = 1): List<Int> = if (max < min) listOf(min) else (max downTo min).toList()

    /**
     * Sort demo candidates (web `SortDemo`/`SortControlsDemo`): the direction section shows only
     * when it and at least one mode fit, so every count with it comes first, then without it.
     *
     * @param modes Modes available.
     * @return Mode counts with whether the direction shows.
     */
    fun sortCandidates(modes: Int): List<SortFit> =
        rowCandidates(modes).map { SortFit(it, showDirection = true) } + rowCandidates(modes).map { SortFit(it, showDirection = false) }

    /**
     * Uniform scale that fits [contentPx] into [limitPx]; 1 when it already fits.
     *
     * @param contentPx Content height.
     * @param limitPx Frame height.
     * @return Scale in `(0, 1]`.
     */
    fun scale(contentPx: Float, limitPx: Float): Float =
        if (contentPx <= limitPx || contentPx <= 0f || limitPx <= 0f) 1f else limitPx / contentPx

    /**
     * Web `YourRankDemo` window: the player's row always shows; the other slots split
     * `ceil(n/2)` above and the rest below, clamped to the neighbourhood.
     *
     * @param size Neighbourhood size.
     * @param player Player's index in it.
     * @param slots Rows that fit, including the player's.
     * @return Indices to show, in order.
     */
    fun around(size: Int, player: Int, slots: Int): IntRange {
        if (size <= 0) return IntRange.EMPTY
        val shown = slots.coerceIn(1, size)
        val others = shown - 1
        var start = player - ceil(others / 2.0).toInt()
        start = start.coerceIn(0, size - shown)
        return start until start + shown
    }

    /**
     * Web `ShopOverviewDemo` grid: the most columns (5 down to 2) whose square tiles still fit
     * at least two rows in the frame; otherwise one row of two.
     *
     * @param widthDp Frame width.
     * @param heightDp Frame height.
     * @param gapDp Gap between tiles.
     * @return Columns, rows and the tile side in dp.
     */
    fun squareGrid(widthDp: Float, heightDp: Float = FRAME_DP, gapDp: Float = 8f): SquareGrid {
        for (cols in MAX_GRID_COLUMNS downTo MIN_GRID_COLUMNS) {
            val side = (widthDp - (cols - 1) * gapDp) / cols
            if (side <= 0f) continue
            val rows = floor((heightDp + gapDp) / (side + gapDp)).toInt()
            if (rows >= 2) return SquareGrid(cols, rows, side)
        }
        val side = (widthDp - gapDp) / MIN_GRID_COLUMNS
        return SquareGrid(MIN_GRID_COLUMNS, 1, minOf(side, heightDp).coerceAtLeast(0f))
    }

    private const val MAX_GRID_COLUMNS = 5
    private const val MIN_GRID_COLUMNS = 2
}

/**
 * A sort demo candidate.
 *
 * @property modes Mode rows shown.
 * @property showDirection Whether the direction control shows.
 */
data class SortFit(val modes: Int, val showDirection: Boolean)

/**
 * A square-tile grid.
 *
 * @property columns Columns.
 * @property rows Rows.
 * @property sideDp Tile side.
 */
data class SquareGrid(val columns: Int, val rows: Int, val sideDp: Float) {
    /** Tiles shown. */
    val count: Int get() = columns * rows
}

// endregion

// region Shop pulse patterns

/** Which demo rows pulse, and in which Shop color (web Shop demos' row patterns). */
object FirstRunShopPattern {
    /**
     * Pulse of one demo row.
     *
     * - Shop highlight (Songs and Shop): every other row, green.
     * - New items: gold, green, none, repeating (web `i % 3`).
     * - Songs Leaving Tomorrow: red for the first half (rounded up), green after.
     * - Shop Leaving Tomorrow: red, green, none, repeating.
     *
     * @param id Slide ID.
     * @param index Row index.
     * @param count Rows shown.
     * @return Pulse, or null for a plain row.
     */
    fun pulse(id: String, index: Int, count: Int): ShopPulse? = when (id) {
        "songs-shop-highlight", "shop-highlighting" -> if (index % 2 == 0) ShopPulse.InShop else null
        "songs-new-in-shop", "shop-new-items" -> when (index % 3) {
            0 -> ShopPulse.New
            1 -> ShopPulse.InShop
            else -> null
        }
        "songs-leaving-tomorrow" -> if (index < (count + 1) / 2) ShopPulse.LeavingTomorrow else ShopPulse.InShop
        "shop-leaving-tomorrow" -> when (index % 3) {
            0 -> ShopPulse.LeavingTomorrow
            1 -> ShopPulse.InShop
            else -> null
        }
        else -> null
    }
}

// endregion

// region Infinite scroll

/** Web `InfiniteScrollDemo` loop: a constant-speed scroll that wraps every copy of the list. */
object FirstRunInfiniteScroll {
    /**
     * Scroll offset of a looping list.
     *
     * @param elapsedMs Time since the scroll started (after [FirstRunEntrance.SCROLL_START_MS]).
     * @param loopDp Height of one copy of the list, including its trailing gap.
     * @param dpPerSecond Speed.
     * @return Offset in `[0, loopDp)`.
     */
    fun offset(elapsedMs: Long, loopDp: Float, dpPerSecond: Float = FirstRunEntrance.SCROLL_DP_PER_SECOND): Float {
        if (loopDp <= 0f || elapsedMs <= 0L) return 0f
        val travelled = elapsedMs / 1_000f * dpPerSecond
        return travelled % loopDp
    }
}

// endregion
