namespace Festival.Core.Domain;

#region Page keys
/// <summary>First-run pages, matching the web's registered <c>pageKey</c> strings.</summary>
public enum FirstRunPageKey
{
    /// <summary><c>songs</c>.</summary>
    Songs,
    /// <summary><c>songinfo</c> (Song Detail).</summary>
    SongInfo,
    /// <summary><c>playerhistory</c>.</summary>
    PlayerHistory,
    /// <summary><c>statistics</c>.</summary>
    Statistics,
    /// <summary><c>suggestions</c>.</summary>
    Suggestions,
    /// <summary><c>leaderboards</c>.</summary>
    Leaderboards,
    /// <summary><c>compete</c>.</summary>
    Compete,
    /// <summary><c>rivals</c>.</summary>
    Rivals,
    /// <summary><c>shop</c>.</summary>
    Shop,
}

/// <summary>Page-key strings, labels and route mapping.</summary>
public static class FirstRunPages
{
    /// <summary>Web <c>pageKey</c>.</summary>
    /// <param name="page">Page.</param>
    /// <returns>Lowercase key such as <c>songinfo</c>.</returns>
    public static string Key(this FirstRunPageKey page) => page.ToString().ToLowerInvariant();

    /// <summary>Settings "First Run Guides" row label (the page's nav title).</summary>
    /// <param name="page">Page.</param>
    /// <returns>Label.</returns>
    public static string Label(this FirstRunPageKey page) => page switch
    {
        FirstRunPageKey.SongInfo => "Song Info",
        FirstRunPageKey.PlayerHistory => "Player History",
        FirstRunPageKey.Shop => "Item Shop",
        _ => page.ToString(),
    };

    /// <summary>
    /// The first-run page shown for a navigation state: a pushed route when present, else the section root.
    /// Matches the web registrations (Apple <c>AppRouteDestination</c>/<c>FestivalRootView</c> seams).
    /// </summary>
    /// <param name="section">Current section.</param>
    /// <param name="route">Top route on the section stack, or <see langword="null"/> at the root.</param>
    /// <returns>Page key, or <see langword="null"/> for pages without first-run slides.</returns>
    public static FirstRunPageKey? For(AppSection section, AppRoute? route) => route switch
    {
        null => section switch
        {
            AppSection.Songs => FirstRunPageKey.Songs,
            AppSection.Suggestions => FirstRunPageKey.Suggestions,
            AppSection.Leaderboards => FirstRunPageKey.Leaderboards,
            AppSection.Rivals => FirstRunPageKey.Rivals,
            AppSection.Statistics => FirstRunPageKey.Statistics,
            AppSection.Shop => FirstRunPageKey.Shop,
            _ => null,
        },
        AppRoute.SongDetail => FirstRunPageKey.SongInfo,
        AppRoute.PlayerHistory => FirstRunPageKey.PlayerHistory,
        AppRoute.Statistics => FirstRunPageKey.Statistics,
        AppRoute.Suggestions => FirstRunPageKey.Suggestions,
        AppRoute.Leaderboards => FirstRunPageKey.Leaderboards,
        AppRoute.Compete => FirstRunPageKey.Compete,
        AppRoute.Rivals => FirstRunPageKey.Rivals,
        AppRoute.Shop => FirstRunPageKey.Shop,
        _ => null,
    };
}
#endregion

#region Catalog
/// <summary>
/// Every page's slides, in web registration order (<c>pages/&lt;page&gt;/firstRun/index.ts</c>). Windows uses the web's
/// <b>desktop</b> copy variants; each variant keeps the web <c>contentKey</c>, so seen-state matches the mobile variant.
/// Copy is verbatim from <c>i18n/firstRun.en.json</c>. <c>shop-views</c> is omitted until the Shop page has a
/// grid/list toggle (the web includes it only when <c>viewToggleAvailable</c>).
/// </summary>
public static class FirstRunCatalog
{
    /// <summary>A page's slides.</summary>
    /// <param name="page">Page.</param>
    /// <returns>Catalogue in display order.</returns>
    public static IReadOnlyList<FirstRunSlide> Slides(FirstRunPageKey page) => page switch
    {
        FirstRunPageKey.Songs => Songs,
        FirstRunPageKey.SongInfo => SongInfo,
        FirstRunPageKey.PlayerHistory => PlayerHistory,
        FirstRunPageKey.Statistics => Statistics,
        FirstRunPageKey.Suggestions => Suggestions,
        FirstRunPageKey.Leaderboards => Leaderboards,
        FirstRunPageKey.Compete => Compete,
        FirstRunPageKey.Rivals => Rivals,
        _ => Shop,
    };

    /// <summary>Songs (9).</summary>
    internal static readonly FirstRunSlide[] Songs =
    [
        new("songs-song-list", 3, "Song List", "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."),
        new("songs-sort", 5, "Sort Songs", "Tap the sort button to reorder by default song data. Select a player profile to narrow it down even more."),
        new("songs-navigation", 5, "Navigation", "Use the sidebar to navigate the app. Select a player profile to see even more options.", "songs-navigation"),
        new("songs-filter", 4, "Filter Songs", "Filter down the song list by global data, and refine it with per-instrument filters.", Gate: FirstRunGate.HasPlayer),
        new("songs-icons", 3, "Instrument Icons", "When showing all instruments, quickly identify songs you've FC'd (gold), played (green), or haven't played (red).", Gate: FirstRunGate.HasPlayer),
        new("songs-metadata", 3, "Song Metadata", "When filtering to a single instrument, see more details about your best score. Customize the order, and what appears, in Settings.", Gate: FirstRunGate.HasPlayer),
        new("songs-shop-highlight", 1, "Item Shop Highlights", "Songs currently available in the Item Shop are highlighted with a pulsing glow so you can spot them at a glance.", Gate: FirstRunGate.ShopHighlightEnabled),
        new("songs-new-in-shop", 1, "New in the Item Shop", "New songs in Festival that are in the item shop for the first time pulse gold, while regular shop songs keep the green highlight.", Gate: FirstRunGate.ShopHighlightEnabled),
        new("songs-leaving-tomorrow", 1, "Leaving Tomorrow", "Songs about to leave the Item Shop pulse red so you know which ones to grab before they're gone.", Gate: FirstRunGate.ShopHighlightEnabled),
    ];

    /// <summary>Song Info (8).</summary>
    internal static readonly FirstRunSlide[] SongInfo =
    [
        new("songinfo-chart", 2, "Score History Chart", "When you have a player selected, their score history for this song appears at the top — charting accuracy and score over time. Change instruments to see more data!", Gate: FirstRunGate.HasPlayer),
        new("songinfo-bar-select", 2, "Select a Bar for Details", "Tap any bar on the chart to see the details for that score — date, season, score, and accuracy.", Gate: FirstRunGate.HasPlayer),
        new("songinfo-view-all", 2, "View Player Scores", "Below the chart, the player's top scores are listed for quick reference. If there's more than five, tapping View all scores will take you to the player history page, where you can see all tracked history for that user, score, and instrument.", Gate: FirstRunGate.HasPlayer),
        new("songinfo-top-scores", 2, "Top Scores Per Instrument", "Each instrument shows the top leaderboard entries for this song. Tap any player to go to their page, or \"View full leaderboard\" to go to the instrument leaderboard for the selected song."),
        new("songinfo-paths", 2, "Optimal Paths", "Tap \"View Paths\" in the header to see the optimal score path for any instrument and difficulty.", "songinfo-paths"),
        new("songinfo-shop-button", 1, "Item Shop Link", "When a song is in the Item Shop, an Item Shop button appears in the header. Tap it to go straight to the store.", "songinfo-shop-button"),
        new("songinfo-new-in-shop", 1, "New Shop Songs", "When a shop song is newly added, the Item Shop button pulses gold instead of green.", "songinfo-new-in-shop"),
        new("songinfo-leaving-tomorrow", 1, "Leaving Tomorrow", "When a song is about to leave the Item Shop, the Item Shop button turns red so you know to act fast.", "songinfo-leaving-tomorrow"),
    ];

    /// <summary>Player History (2).</summary>
    internal static readonly FirstRunSlide[] PlayerHistory =
    [
        new("playerhistory-score-list", 1, "Score History", "Every tracked score change for this song and instrument is listed here. Your personal best is highlighted so you can spot it at a glance."),
        new("playerhistory-sort", 1, "Sort Scores", "Tap the sort button in the header to reorder by date, score, accuracy, or season — ascending or descending.", "playerhistory-sort"),
    ];

    /// <summary>Statistics (6).</summary>
    internal static readonly FirstRunSlide[] Statistics =
    [
        new("statistics-select-profile", 1, "Select Player Profile", "Press the Select Player Profile button at the top of the screen to select this player profile and see all of their tracked data.", "statistics-select-profile"),
        new("statistics-drill-down", 1, "Drill Into Your Data", "Tap any stat card marked with a chevron to jump to the Songs page with pre-applied filters, instantly showing you all songs for that category."),
        new("statistics-overview", 2, "Global Statistics", "See a player's overall performance at a glance — songs played, full combos, gold stars, accuracy, and best rank. Tap any stat with an indicator to jump to the relevant songs."),
        new("statistics-instrument-breakdown", 1, "Per-Instrument Stats", "Scroll down to see detailed stats for each instrument, and tap to immediately be taken to a filtered list of songs for that instrument."),
        new("statistics-percentiles", 1, "Percentile Rankings", "See where a player ranks relative to all players. The percentile table breaks down how many scores land in each bracket — from Top 1% to Top 100%."),
        new("statistics-top-songs", 1, "Highest and Lowest Rank Breakdown", "Each instrument shows your highest and lowest five songs by percentile rank. Tap any song to see its leaderboard and score history."),
    ];

    /// <summary>Suggestions (4).</summary>
    internal static readonly FirstRunSlide[] Suggestions =
    [
        new("suggestions-category-card", 1, "Suggestion Cards", "Each suggestion is a themed card with songs tailored to what you have and haven't played — near FCs, unplayed tracks, percentile pushes, and more."),
        new("suggestions-global-filter", 1, "Filter Suggestions", "Tap the filter button to control which suggestions are visible to you."),
        new("suggestions-instrument-filter", 1, "Per-Instrument Filters", "Select an instrument to fine-tune which suggestion types appear for that specific instrument."),
        new("suggestions-infinite-scroll", 1, "More Suggestions", "Scroll down to keep loading personalized suggestions. Start a new mix when you reach the session limit."),
    ];

    /// <summary>Leaderboards (3).</summary>
    internal static readonly FirstRunSlide[] Leaderboards =
    [
        new("leaderboards-overview", 2, "Global Rankings", "See how players rank across all songs on each instrument. Rankings are computed after every scrape pass."),
        new("leaderboards-experimental-metrics", 1, "Experimental Ranking Metrics", "Sort by Adjusted Percentile, Popularity-Weighted Percentile, FC Rate, or Max Score %. These experimental metrics estimate performance from rank percentiles, score counts, and population weighting — tap the ? icon on any metric for details.", Gate: FirstRunGate.ExperimentalRanksEnabled),
        new("leaderboards-your-rank", 2, "Your Rank", "Your position appears in purple. Tap 'View all rankings' to see the full leaderboard for any instrument.", Gate: FirstRunGate.HasPlayer),
    ];

    /// <summary>Compete (3).</summary>
    internal static readonly FirstRunSlide[] Compete =
    [
        new("compete-hub", 2, "Compete Hub", "Your competitive snapshot — see your leaderboard rankings and closest rivals at a glance."),
        new("compete-leaderboards", 2, "Leaderboards", "The top-ranked players across all instruments. Tap to explore the full global rankings."),
        new("compete-rivals", 2, "Rivals", "See who's just ahead and behind you. Tap to view all your rivals and head-to-head matchups.", Gate: FirstRunGate.HasPlayer),
    ];

    /// <summary>Rivals (3).</summary>
    internal static readonly FirstRunSlide[] Rivals =
    [
        new("rivals-overview", 2, "Your Rivals", "Rivals are players near your skill level on each instrument. See who's just above and below you."),
        new("rivals-instruments", 3, "Per-Instrument Rivals", "Each instrument has its own rival list — plus a common rivals section for players who appear across multiple instruments."),
        new("rivals-detail", 3, "Head-to-Head", "Tap a rival to see a song-by-song comparison, broken down by closest battles, almost passed, and more."),
    ];

    /// <summary>Item Shop (4; <c>shop-views</c> omitted, see class remarks).</summary>
    internal static readonly FirstRunSlide[] Shop =
    [
        new("shop-overview", 2, "Item Shop", "Browse the songs currently available for purchase in the Item Shop."),
        new("shop-highlighting", 2, "Shop Highlighting", "Songs from the Item Shop are highlighted with a pulsing glow on the Songs page so you can spot them at a glance.", Gate: FirstRunGate.ShopHighlightEnabled),
        new("shop-new-items", 1, "New Shop Songs", "New songs in Festival that are in the item shop for the first time pulse gold in shop views and on song rows.", Gate: FirstRunGate.ShopHighlightEnabled),
        new("shop-leaving-tomorrow", 1, "Leaving Tomorrow", "Songs about to leave the Item Shop pulse red — in the grid, list, and on the Songs page — so you never miss a last-chance purchase.", Gate: FirstRunGate.ShopHighlightEnabled),
    ];
}
#endregion
