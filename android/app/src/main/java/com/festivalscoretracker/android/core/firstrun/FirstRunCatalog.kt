package com.festivalscoretracker.android.core.firstrun

import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsTab

// region Page keys

/**
 * First-run pages, matching the web's registered `pageKey` strings.
 *
 * @property key Web `pageKey`.
 * @property label Settings "First Run Guides" row label (web nav titles).
 */
enum class FirstRunPageKey(val key: String, val label: String) {
    Songs("songs", "Songs"),
    SongInfo("songinfo", "Song Info"),
    Statistics("statistics", "Statistics"),
    Suggestions("suggestions", "Suggestions"),
    PlayerHistory("playerhistory", "Score History"),
    Leaderboards("leaderboards", "Leaderboards"),
    Compete("compete", "Compete"),
    Rivals("rivals", "Rivals"),
    Shop("shop", "Item Shop"),
    ;

    companion object {
        /**
         * The first-run page for a destination (web registrations: `Page.tsx`
         * configs plus `PlayerPage`, which serves both `/player/:id` and `/statistics`).
         *
         * @param route Visible route (tab root or pushed).
         * @return Page, or null for destinations without slides.
         */
        fun forRoute(route: AppRoute?): FirstRunPageKey? = when (route) {
            SongsTab -> Songs
            is SongDetailRoute -> SongInfo
            is PlayerHistoryRoute -> PlayerHistory
            StatisticsTab, StatisticsRoute, is PlayerRoute -> Statistics
            SuggestionsTab, SuggestionsRoute -> Suggestions
            LeaderboardsTab, LeaderboardsRoute -> Leaderboards
            CompeteTab, CompeteRoute -> Compete
            RivalsTab, RivalsRoute -> Rivals
            ShopRoute -> Shop
            else -> null
        }
    }
}

// endregion

// region Catalog

/**
 * Every page's slides in web registration order (`pages/<page>/firstRun/index.ts`),
 * verbatim from `i18n/firstRun.en.json`. Android puts page actions in the top
 * app bar, so it uses the web **desktop** ("header") copy variants, which share
 * the web `contentKey`s with the mobile variants. The one width-dependent slide
 * is `songs-navigation`: bottom tabs on compact widths, the rail/drawer
 * ("sidebar") otherwise. `shop-views` is omitted until Shop has a grid/list
 * toggle (web includes it only when `viewToggleAvailable`).
 */
object FirstRunCatalog {
    /**
     * A page's slides.
     *
     * @param page Page.
     * @param compact Compact window width (bottom navigation bar).
     * @return Catalogue in display order.
     */
    fun slides(page: FirstRunPageKey, compact: Boolean = true): List<FirstRunSlide> = when (page) {
        FirstRunPageKey.Songs -> songs(compact)
        FirstRunPageKey.SongInfo -> songInfo
        FirstRunPageKey.PlayerHistory -> playerHistory
        FirstRunPageKey.Statistics -> statistics
        FirstRunPageKey.Suggestions -> suggestions
        FirstRunPageKey.Leaderboards -> leaderboards
        FirstRunPageKey.Compete -> compete
        FirstRunPageKey.Rivals -> rivals
        FirstRunPageKey.Shop -> shop
    }

    /**
     * Songs (9).
     *
     * @param compact Bottom-tab copy for `songs-navigation`.
     * @return Slides.
     */
    fun songs(compact: Boolean): List<FirstRunSlide> = listOf(
        FirstRunSlide("songs-song-list", 3, "Song List", "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."),
        FirstRunSlide("songs-sort", 5, "Sort Songs", "Tap the sort button to reorder by default song data. Select a player profile to narrow it down even more."),
        FirstRunSlide(
            "songs-navigation", 5, "Navigation",
            if (compact) {
                "Use the bottom tabs to navigate the app. Select a player profile to see even more options."
            } else {
                "Use the sidebar to navigate the app. Select a player profile to see even more options."
            },
            contentKey = "songs-navigation",
        ),
        FirstRunSlide("songs-filter", 4, "Filter Songs", "Filter down the song list by global data, and refine it with per-instrument filters.", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songs-icons", 3, "Instrument Icons", "When showing all instruments, quickly identify songs you've FC'd (gold), played (green), or haven't played (red).", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songs-metadata", 3, "Song Metadata", "When filtering to a single instrument, see more details about your best score. Customize the order, and what appears, in Settings.", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songs-shop-highlight", 1, "Item Shop Highlights", "Songs currently available in the Item Shop are highlighted with a pulsing glow so you can spot them at a glance.", gate = FirstRunGate.ShopHighlightEnabled),
        FirstRunSlide("songs-new-in-shop", 1, "New in the Item Shop", "New songs in Festival that are in the item shop for the first time pulse gold, while regular shop songs keep the green highlight.", gate = FirstRunGate.ShopHighlightEnabled),
        FirstRunSlide("songs-leaving-tomorrow", 1, "Leaving Tomorrow", "Songs about to leave the Item Shop pulse red so you know which ones to grab before they're gone.", gate = FirstRunGate.ShopHighlightEnabled),
    )

    /** Song Info (8). */
    val songInfo: List<FirstRunSlide> = listOf(
        FirstRunSlide("songinfo-chart", 2, "Score History Chart", "When you have a player selected, their score history for this song appears at the top — charting accuracy and score over time. Change instruments to see more data!", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songinfo-bar-select", 2, "Select a Bar for Details", "Tap any bar on the chart to see the details for that score — date, season, score, and accuracy.", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songinfo-view-all", 2, "View Player Scores", "Below the chart, the player's top scores are listed for quick reference. If there's more than five, tapping View all scores will take you to the player history page, where you can see all tracked history for that user, score, and instrument.", gate = FirstRunGate.HasPlayer),
        FirstRunSlide("songinfo-top-scores", 2, "Top Scores Per Instrument", "Each instrument shows the top leaderboard entries for this song. Tap any player to go to their page, or \"View full leaderboard\" to go to the instrument leaderboard for the selected song."),
        FirstRunSlide("songinfo-paths", 2, "Optimal Paths", "Tap \"View Paths\" in the header to see the optimal score path for any instrument and difficulty.", contentKey = "songinfo-paths"),
        FirstRunSlide("songinfo-shop-button", 1, "Item Shop Link", "When a song is in the Item Shop, an Item Shop button appears in the header. Tap it to go straight to the store.", contentKey = "songinfo-shop-button"),
        FirstRunSlide("songinfo-new-in-shop", 1, "New Shop Songs", "When a shop song is newly added, the Item Shop button pulses gold instead of green.", contentKey = "songinfo-new-in-shop"),
        FirstRunSlide("songinfo-leaving-tomorrow", 1, "Leaving Tomorrow", "When a song is about to leave the Item Shop, the Item Shop button turns red so you know to act fast.", contentKey = "songinfo-leaving-tomorrow"),
    )

    /** Score History (2). */
    val playerHistory: List<FirstRunSlide> = listOf(
        FirstRunSlide("playerhistory-score-list", 1, "Score History", "Every tracked score change for this song and instrument is listed here. Your personal best is highlighted so you can spot it at a glance."),
        FirstRunSlide("playerhistory-sort", 1, "Sort Scores", "Tap the sort button in the header to reorder by date, score, accuracy, or season — ascending or descending.", contentKey = "playerhistory-sort"),
    )

    /** Statistics (6). */
    val statistics: List<FirstRunSlide> = listOf(
        FirstRunSlide("statistics-select-profile", 1, "Select Player Profile", "Press the Select Player Profile button at the top of the screen to select this player profile and see all of their tracked data.", contentKey = "statistics-select-profile"),
        FirstRunSlide("statistics-drill-down", 1, "Drill Into Your Data", "Tap any stat card marked with a chevron to jump to the Songs page with pre-applied filters, instantly showing you all songs for that category."),
        FirstRunSlide("statistics-overview", 2, "Global Statistics", "See a player's overall performance at a glance — songs played, full combos, gold stars, accuracy, and best rank. Tap any stat with an indicator to jump to the relevant songs."),
        FirstRunSlide("statistics-instrument-breakdown", 1, "Per-Instrument Stats", "Scroll down to see detailed stats for each instrument, and tap to immediately be taken to a filtered list of songs for that instrument."),
        FirstRunSlide("statistics-percentiles", 1, "Percentile Rankings", "See where a player ranks relative to all players. The percentile table breaks down how many scores land in each bracket — from Top 1% to Top 100%."),
        FirstRunSlide("statistics-top-songs", 1, "Highest and Lowest Rank Breakdown", "Each instrument shows your highest and lowest five songs by percentile rank. Tap any song to see its leaderboard and score history."),
    )

    /** Suggestions (4). */
    val suggestions: List<FirstRunSlide> = listOf(
        FirstRunSlide("suggestions-category-card", 1, "Suggestion Cards", "Each suggestion is a themed card with songs tailored to what you have and haven't played — near FCs, unplayed tracks, percentile pushes, and more."),
        FirstRunSlide("suggestions-global-filter", 1, "Filter Suggestions", "Tap the filter button to control which suggestions are visible to you."),
        FirstRunSlide("suggestions-instrument-filter", 1, "Per-Instrument Filters", "Select an instrument to fine-tune which suggestion types appear for that specific instrument."),
        FirstRunSlide("suggestions-infinite-scroll", 1, "More Suggestions", "Scroll down to keep loading personalized suggestions. Start a new mix when you reach the session limit."),
    )

    /** Leaderboards (3). */
    val leaderboards: List<FirstRunSlide> = listOf(
        FirstRunSlide("leaderboards-overview", 2, "Global Rankings", "See how players rank across all songs on each instrument. Rankings are computed after every scrape pass."),
        FirstRunSlide("leaderboards-experimental-metrics", 1, "Experimental Ranking Metrics", "Sort by Adjusted Percentile, Popularity-Weighted Percentile, FC Rate, or Max Score %. These experimental metrics estimate performance from rank percentiles, score counts, and population weighting — tap the ? icon on any metric for details.", gate = FirstRunGate.ExperimentalRanksEnabled),
        FirstRunSlide("leaderboards-your-rank", 2, "Your Rank", "Your position appears in purple. Tap 'View all rankings' to see the full leaderboard for any instrument.", gate = FirstRunGate.HasPlayer),
    )

    /** Compete (3). */
    val compete: List<FirstRunSlide> = listOf(
        FirstRunSlide("compete-hub", 2, "Compete Hub", "Your competitive snapshot — see your leaderboard rankings and closest rivals at a glance."),
        FirstRunSlide("compete-leaderboards", 2, "Leaderboards", "The top-ranked players across all instruments. Tap to explore the full global rankings."),
        FirstRunSlide("compete-rivals", 2, "Rivals", "See who's just ahead and behind you. Tap to view all your rivals and head-to-head matchups.", gate = FirstRunGate.HasPlayer),
    )

    /** Rivals (3). */
    val rivals: List<FirstRunSlide> = listOf(
        FirstRunSlide("rivals-overview", 2, "Your Rivals", "Rivals are players near your skill level on each instrument. See who's just above and below you."),
        FirstRunSlide("rivals-instruments", 3, "Per-Instrument Rivals", "Each instrument has its own rival list — plus a common rivals section for players who appear across multiple instruments."),
        FirstRunSlide("rivals-detail", 3, "Head-to-Head", "Tap a rival to see a song-by-song comparison, broken down by closest battles, almost passed, and more."),
    )

    /** Item Shop (4; `shop-views` omitted, see the object docs). */
    val shop: List<FirstRunSlide> = listOf(
        FirstRunSlide("shop-overview", 2, "Item Shop", "Browse the songs currently available for purchase in the Item Shop."),
        FirstRunSlide("shop-highlighting", 2, "Shop Highlighting", "Songs from the Item Shop are highlighted with a pulsing glow on the Songs page so you can spot them at a glance.", gate = FirstRunGate.ShopHighlightEnabled),
        FirstRunSlide("shop-new-items", 1, "New Shop Songs", "New songs in Festival that are in the item shop for the first time pulse gold in shop views and on song rows.", gate = FirstRunGate.ShopHighlightEnabled),
        FirstRunSlide("shop-leaving-tomorrow", 1, "Leaving Tomorrow", "Songs about to leave the Item Shop pulse red — in the grid, list, and on the Songs page — so you never miss a last-chance purchase.", gate = FirstRunGate.ShopHighlightEnabled),
    )
}

// endregion
