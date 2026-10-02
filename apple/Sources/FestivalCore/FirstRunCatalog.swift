import Foundation

// MARK: - Page keys

/// One first-run-eligible page, matching the web's `pageKey` strings registered from
/// `SettingsPage.tsx` (`useRegisterFirstRun('songs', …)`, etc.). Used both to key seen-state
/// (indirectly, via each slide's own id) and to drive the Settings "First-Run Guides" replay
/// list.
public enum FirstRunPageKey: String, CaseIterable, Sendable, Identifiable {
    case songs
    case songInfo = "songinfo"
    case playerHistory = "playerhistory"
    case statistics
    case suggestions
    case leaderboards
    case compete
    case rivals
    case shop

    public var id: String { rawValue }

    /// Settings "First-Run Guides" row label, matching the web's `registeredPages[].label`
    /// (each page's nav title).
    public var label: String {
        switch self {
        case .songs: "Songs"
        case .songInfo: "Song Info"
        case .playerHistory: "Player History"
        case .statistics: "Statistics"
        case .suggestions: "Suggestions"
        case .leaderboards: "Leaderboards"
        case .compete: "Compete"
        case .rivals: "Rivals"
        case .shop: "Item Shop"
        }
    }

    /// Title of the page's first-run guide: its navigation-bar title and the Settings "First
    /// Run Guides" row label (issue #24). The web's nav titles, where Player History is titled
    /// "Score History" (`history.title`); every title stays under 15 characters (HIG Toolbars).
    public var guideTitle: String {
        self == .playerHistory ? "Score History" : label
    }
}

// MARK: - Catalog

/// The full, hand-ported first-run slide catalog for every page, mirroring each page's
/// `pages/<page>/firstRun/index.ts` barrel in the web app. Kept as pure data (no rendering) so
/// it is fully unit-testable; `FestivalUI` maps `FirstRunSlide.id` to a native demo view.
///
/// Only the mobile copy variant is ported for slides that differ by `isMobile` on the web
/// (this lane targets iPhone only); each such slide keeps the web's `contentKey` so its
/// seen-state would still line up with a future desktop variant sharing the same key.
public enum FirstRunCatalog {
    /// All slides for one page, in the same order the web page registers them.
    ///
    /// - Parameter page: Page to look up.
    /// - Returns: The page's full slide catalog.
    public static func slides(for page: FirstRunPageKey) -> [FirstRunSlide] {
        switch page {
        case .songs: songs
        case .songInfo: songInfo
        case .playerHistory: playerHistory
        case .statistics: statistics
        case .suggestions: suggestions
        case .leaderboards: leaderboards
        case .compete: compete
        case .rivals: rivals
        case .shop: shop
        }
    }

    // MARK: Songs (9 slides — ported from `pages/songs/firstRun/`)

    static let songs: [FirstRunSlide] = [
        FirstRunSlide(
            id: "songs-song-list", version: 3, title: "Song List",
            description: "Browse and search the entire Festival library. Tap a song to see "
                + "leaderboards and more details."
        ),
        FirstRunSlide(
            id: "songs-sort", version: 5, title: "Sort Songs",
            description: "Tap the sort button to reorder by default song data. Select a player "
                + "profile to narrow it down even more."
        ),
        FirstRunSlide(
            id: "songs-navigation", version: 5, title: "Navigation",
            description: "Use the bottom tabs to navigate the app. Select a player profile to "
                + "see even more options.",
            contentKey: "songs-navigation"
        ),
        FirstRunSlide(
            id: "songs-filter", version: 4, title: "Filter Songs",
            description: "Filter down the song list by global data, and refine it with "
                + "per-instrument filters.",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songs-icons", version: 3, title: "Instrument Icons",
            description: "When showing all instruments, quickly identify songs you've FC'd "
                + "(gold), played (green), or haven't played (red).",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songs-metadata", version: 3, title: "Song Metadata",
            description: "When filtering to a single instrument, see more details about your "
                + "best score. Customize the order, and what appears, in Settings.",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songs-shop-highlight", version: 1, title: "Item Shop Highlights",
            description: "Songs currently available in the Item Shop are highlighted with a "
                + "pulsing glow so you can spot them at a glance.",
            gate: .shopHighlightEnabled
        ),
        FirstRunSlide(
            id: "songs-new-in-shop", version: 1, title: "New in the Item Shop",
            description: "New songs in Festival that are in the item shop for the first time "
                + "pulse gold, while regular shop songs keep the green highlight.",
            gate: .shopHighlightEnabled
        ),
        FirstRunSlide(
            id: "songs-leaving-tomorrow", version: 1, title: "Leaving Tomorrow",
            description: "Songs about to leave the Item Shop pulse red so you know which ones "
                + "to grab before they're gone.",
            gate: .shopHighlightEnabled
        ),
    ]

    // MARK: Song Info (8 slides — ported from `pages/songinfo/firstRun/`)

    static let songInfo: [FirstRunSlide] = [
        FirstRunSlide(
            id: "songinfo-chart", version: 2, title: "Score History Chart",
            description: "When you have a player selected, their score history for this song "
                + "appears at the top — charting accuracy and score over time. Change "
                + "instruments to see more data!",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songinfo-bar-select", version: 2, title: "Select a Bar for Details",
            description: "Tap any bar on the chart to see the details for that score — date, "
                + "season, score, and accuracy.",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songinfo-view-all", version: 2, title: "View Player Scores",
            description: "Below the chart, the player's top scores are listed for quick "
                + "reference. If there's more than five, tapping View all scores will take you "
                + "to the player history page, where you can see all tracked history for that "
                + "user, score, and instrument.",
            gate: .hasPlayer
        ),
        FirstRunSlide(
            id: "songinfo-top-scores", version: 2, title: "Top Scores Per Instrument",
            description: "Each instrument shows the top leaderboard entries for this song. Tap "
                + "any player to go to their page, or \"View full leaderboard\" to go to the "
                + "instrument leaderboard for the selected song."
        ),
        FirstRunSlide(
            id: "songinfo-paths", version: 2, title: "Optimal Paths",
            description: "Tap \"View Paths\" in the action button to see the optimal score "
                + "path for any instrument and difficulty.",
            contentKey: "songinfo-paths"
        ),
        FirstRunSlide(
            id: "songinfo-shop-button", version: 1, title: "Item Shop Link",
            description: "When a song is in the Item Shop, a shop icon appears on the song "
                + "card. Tap it to go straight to the store.",
            contentKey: "songinfo-shop-button"
        ),
        FirstRunSlide(
            id: "songinfo-new-in-shop", version: 1, title: "New Shop Songs",
            description: "When a shop song is newly added, the Item Shop pill pulses gold "
                + "instead of green.",
            contentKey: "songinfo-new-in-shop"
        ),
        FirstRunSlide(
            id: "songinfo-leaving-tomorrow", version: 1, title: "Leaving Tomorrow",
            description: "When a song is about to leave the Item Shop, the Item Shop pill "
                + "turns red so you know to act fast.",
            contentKey: "songinfo-leaving-tomorrow"
        ),
    ]

    // MARK: Player History (2 slides — ported from `pages/leaderboard/player/firstRun/`)

    static let playerHistory: [FirstRunSlide] = [
        FirstRunSlide(
            id: "playerhistory-score-list", version: 1, title: "Score History",
            description: "Every tracked score change for this song and instrument is listed "
                + "here. Your personal best is highlighted so you can spot it at a glance."
        ),
        FirstRunSlide(
            id: "playerhistory-sort", version: 1, title: "Sort Scores",
            description: "Tap the sort button in the toolbar to reorder by date, score, "
                + "accuracy, or season — ascending or descending.",
            contentKey: "playerhistory-sort"
        ),
    ]

    // MARK: Statistics (6 slides — ported from `pages/player/firstRun/`)
    // Copy is adapted to native chrome: the web's FAB menu, action menu and `?` metric
    // icons don't exist in the app. `contentKey` keeps seen state stable across wording.

    static let statistics: [FirstRunSlide] = [
        FirstRunSlide(
            id: "statistics-select-profile", version: 1, title: "Select Player Profile",
            description: "Tap Select Profile on this page, or the profile button in the top-right "
                + "corner, to make this your selected profile and see all of their tracked data.",
            contentKey: "statistics-select-profile"
        ),
        FirstRunSlide(
            id: "statistics-drill-down", version: 1, title: "Drill Into Your Data",
            description: "Tap any stat card marked with a chevron to jump to the Songs page "
                + "with pre-applied filters, instantly showing you all songs for that category."
        ),
        FirstRunSlide(
            id: "statistics-overview", version: 2, title: "Global Statistics",
            description: "See a player's overall performance at a glance — songs played, full "
                + "combos, gold stars, accuracy, and best rank. Tap any stat with an indicator "
                + "to jump to the relevant songs."
        ),
        FirstRunSlide(
            id: "statistics-instrument-breakdown", version: 1, title: "Per-Instrument Stats",
            description: "Scroll down to see detailed stats for each instrument, and tap to "
                + "immediately be taken to a filtered list of songs for that instrument."
        ),
        FirstRunSlide(
            id: "statistics-percentiles", version: 1, title: "Percentile Rankings",
            description: "See where a player ranks relative to all players. The percentile "
                + "table breaks down how many scores land in each bracket — from Top 1% to Top "
                + "100%."
        ),
        FirstRunSlide(
            id: "statistics-top-songs", version: 1, title: "Highest and Lowest Rank Breakdown",
            description: "Each instrument shows your highest and lowest five songs by "
                + "percentile rank. Tap any song to see its leaderboard and score history."
        ),
    ]

    // MARK: Suggestions (4 slides — ported from `pages/suggestions/firstRun/`)

    static let suggestions: [FirstRunSlide] = [
        FirstRunSlide(
            id: "suggestions-category-card", version: 1, title: "Suggestion Cards",
            description: "Each suggestion is a themed card with songs tailored to what you "
                + "have and haven't played — near FCs, unplayed tracks, percentile pushes, and "
                + "more."
        ),
        FirstRunSlide(
            id: "suggestions-global-filter", version: 1, title: "Filter Suggestions",
            description: "Tap the filter button to control which suggestions are visible to "
                + "you."
        ),
        FirstRunSlide(
            id: "suggestions-instrument-filter", version: 1, title: "Per-Instrument Filters",
            description: "Select an instrument to fine-tune which suggestion types appear for "
                + "that specific instrument."
        ),
        FirstRunSlide(
            id: "suggestions-infinite-scroll", version: 1, title: "More Suggestions",
            description: "Scroll down to keep loading personalized suggestions. Start a new "
                + "mix when you reach the session limit."
        ),
    ]

    // MARK: Leaderboards (3 slides — ported from `pages/leaderboards/firstRun/`)

    static let leaderboards: [FirstRunSlide] = [
        FirstRunSlide(
            id: "leaderboards-overview", version: 2, title: "Global Rankings",
            description: "See how players rank across all songs on each instrument. Rankings "
                + "are computed after every scrape pass."
        ),
        FirstRunSlide(
            id: "leaderboards-experimental-metrics", version: 1,
            title: "Experimental Ranking Metrics",
            description: "Sort by Adjusted Percentile, Popularity-Weighted Percentile, FC "
                + "Rate, or Max Score %. These experimental metrics estimate performance from "
                + "rank percentiles, score counts, and population weighting. Choose one from "
                + "the Rank By menu in the toolbar.",
            gate: .experimentalRanksEnabled
        ),
        FirstRunSlide(
            id: "leaderboards-your-rank", version: 2, title: "Your Rank",
            description: "Your position appears in purple. Tap 'View all rankings' to see the "
                + "full leaderboard for any instrument.",
            gate: .hasPlayer
        ),
    ]

    // MARK: Compete (3 slides — ported from `pages/compete/firstRun/`)

    static let compete: [FirstRunSlide] = [
        FirstRunSlide(
            id: "compete-hub", version: 2, title: "Compete Hub",
            description: "Your competitive snapshot — see your leaderboard rankings and "
                + "closest rivals at a glance."
        ),
        FirstRunSlide(
            id: "compete-leaderboards", version: 2, title: "Leaderboards",
            description: "The top-ranked players across all instruments. Tap to explore the "
                + "full global rankings."
        ),
        FirstRunSlide(
            id: "compete-rivals", version: 2, title: "Rivals",
            description: "See who's just ahead and behind you. Tap to view all your rivals "
                + "and head-to-head matchups.",
            gate: .hasPlayer
        ),
    ]

    // MARK: Rivals (3 slides — ported from `pages/rivals/firstRun/`)

    static let rivals: [FirstRunSlide] = [
        FirstRunSlide(
            id: "rivals-overview", version: 2, title: "Your Rivals",
            description: "Rivals are players near your skill level on each instrument. See "
                + "who's just above and below you."
        ),
        FirstRunSlide(
            id: "rivals-instruments", version: 3, title: "Per-Instrument Rivals",
            description: "Each instrument has its own rival list — plus a common rivals "
                + "section for players who appear across multiple instruments."
        ),
        FirstRunSlide(
            id: "rivals-detail", version: 3, title: "Head-to-Head",
            description: "Tap a rival to see a song-by-song comparison, broken down by closest "
                + "battles, almost passed, and more."
        ),
    ]

    // MARK: Item Shop (5 slides — ported from `pages/shop/firstRun/`)
    //
    // The web conditionally includes `shopViewsSlide` only when a grid/list view toggle is
    // available. This lane's Shop screen has no such toggle yet (Lane per PROGRESS.md), so the
    // slide is omitted here; add it back once the view toggle ships.

    static let shop: [FirstRunSlide] = [
        FirstRunSlide(
            id: "shop-overview", version: 2, title: "Item Shop",
            description: "Browse the songs currently available for purchase in the Item Shop."
        ),
        FirstRunSlide(
            id: "shop-highlighting", version: 2, title: "Shop Highlighting",
            description: "Songs from the Item Shop are highlighted with a pulsing glow on the "
                + "Songs page so you can spot them at a glance.",
            gate: .shopHighlightEnabled
        ),
        FirstRunSlide(
            id: "shop-new-items", version: 1, title: "New Shop Songs",
            description: "New songs in Festival that are in the item shop for the first time "
                + "pulse gold in shop views and on song rows.",
            gate: .shopHighlightEnabled
        ),
        FirstRunSlide(
            id: "shop-leaving-tomorrow", version: 1, title: "Leaving Tomorrow",
            description: "Songs about to leave the Item Shop pulse red — in the grid, list, "
                + "and on the Songs page — so you never miss a last-chance purchase.",
            gate: .shopHighlightEnabled
        ),
    ]
}
