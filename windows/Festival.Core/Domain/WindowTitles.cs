namespace Festival.Core.Domain;

#region Window titles
/// <summary>
/// Window (taskbar, Alt+Tab) titles: "Festival Score Tracker - &lt;page&gt;", the installed PWA's Edge title without the
/// repeated brand suffix. Page names follow the web's <c>routeMetadata.ts</c> resolved through <c>en.json</c>.
/// </summary>
public static class WindowTitles
{
    /// <summary>Brand name (web <c>common.brandName</c>).</summary>
    public const string Brand = "Festival Score Tracker";

    /// <summary>Title for the visible page.</summary>
    /// <param name="section">Visible section.</param>
    /// <param name="route">Top route of the section's stack, or <see langword="null"/> at its root.</param>
    /// <returns>Window title.</returns>
    public static string For(AppSection section, AppRoute? route) => $"{Brand} - {PageName(section, route)}";

    /// <summary>Web page name for a route or section root.</summary>
    /// <param name="section">Visible section.</param>
    /// <param name="route">Top route, or <see langword="null"/> at the section root.</param>
    /// <returns>Page name such as "Song Info".</returns>
    public static string PageName(AppSection section, AppRoute? route) => route switch
    {
        null => section.Label(),
        AppRoute.SongDetail => "Song Info",
        AppRoute.SongLeaderboard or AppRoute.SongBandLeaderboard or AppRoute.Leaderboards
            or AppRoute.FullRankings or AppRoute.BandRankings => "Leaderboards",
        AppRoute.PlayerHistory => "Score History",
        AppRoute.Player => "Player Profile",
        AppRoute.PlayerBands or AppRoute.Bands or AppRoute.Band => "Player Bands",
        AppRoute.Rivals => "Rivals",
        AppRoute.AllRivals => "All Rivals",
        AppRoute.RivalDetail => "Rival Details",
        AppRoute.Rivalry => "Rivalry",
        AppRoute.Compete => "Compete",
        AppRoute.Statistics => "Statistics",
        AppRoute.Suggestions => "Suggestions",
        AppRoute.Shop => "Item Shop",
        AppRoute.Licenses => "Licenses",
        AppRoute.Search => "Search",
        _ => section.Label(),
    };
}
#endregion
