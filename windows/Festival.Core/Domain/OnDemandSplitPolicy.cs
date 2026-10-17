namespace Festival.Core.Domain;

#region List pages
/// <summary>
/// A page that opens its trailing pane on demand (split-panes R7 Windows variant, issue #652): the same pages as the iPhone
/// Duo's and iPad's <c>OnDemandSplitPolicy.ListPage</c> and Android's <c>SplitListPage</c>. Windows has no Compete page
/// (/compete opens Rivals), so Rivals covers it.
/// </summary>
public enum SplitListPage
{
    /// <summary>Rivals and All Rivals: Rival Detail opens beside the list.</summary>
    Rivals,
    /// <summary>Leaderboards: Full Rankings and Band Rankings open beside the cards.</summary>
    Leaderboards,
    /// <summary>Song Detail: the song's instrument board, band board and Score History open beside it.</summary>
    SongDetail,
}

/// <summary>Where a navigation lands while a section can split.</summary>
public enum SplitAction
{
    /// <summary>A full-width page pushed on the section's stack (over the split when one is open).</summary>
    PushFull,
    /// <summary>Opens (or replaces) the trailing pane beside the list page.</summary>
    OpenPane,
    /// <summary>Pushes onto the open pane's own stack.</summary>
    PushInPane,
}
#endregion

#region Policy
/// <summary>
/// Windows on-demand split rules (split-panes R7 owner-approved Windows variant, issue #652): which pages split, when the
/// window allows it and where each navigation lands. Pages split at the content area's midpoint, so both panes grow and
/// shrink with the window; every other page (Songs included) pushes full width.
/// </summary>
public static class OnDemandSplitPolicy
{
    /// <summary>
    /// Narrowest pane in epx. Windows pages switch to their compact layouts below 760 epx windows and are designed for the
    /// 500 epx compact preset, so each half keeps 480 epx: the default 1280 epx window with the expanded navigation pane
    /// (1040 epx of content) splits, the 1008 epx Expanded threshold (768 epx) does not.
    /// </summary>
    public const double MinimumPaneWidth = 480;

    /// <summary>Text scale from which the pane minimum grows with the text (the #371 rule shared with Apple and Android).</summary>
    public const double LargeTextScale = 1.3;

    /// <summary>The narrowest pane at a text scale.</summary>
    /// <param name="textScale">Windows text scale factor (1 = 100%).</param>
    /// <returns><see cref="MinimumPaneWidth"/>, times the scale from <see cref="LargeTextScale"/>.</returns>
    public static double PaneMinimum(double textScale) =>
        textScale >= LargeTextScale ? MinimumPaneWidth * textScale : MinimumPaneWidth;

    /// <summary>Whether a content area is wide enough for two equal panes.</summary>
    /// <param name="contentWidth">Width of the area the panes share, in epx.</param>
    /// <param name="textScale">Windows text scale factor.</param>
    /// <returns><see langword="true"/> when each half keeps at least <see cref="PaneMinimum"/>.</returns>
    public static bool AllowsSplit(double contentWidth, double textScale) => contentWidth / 2 >= PaneMinimum(textScale);

    /// <summary>The list page a section root or pushed page shows.</summary>
    /// <param name="parameter">Navigation parameter: an <see cref="AppSection"/> for a section root, else its <see cref="AppRoute"/>.</param>
    /// <returns>List page, or <see langword="null"/> for a page that never splits.</returns>
    public static SplitListPage? PageOf(object? parameter) => parameter switch
    {
        AppSection.Rivals or AppRoute.Rivals or AppRoute.Compete or AppRoute.AllRivals => SplitListPage.Rivals,
        AppSection.Leaderboards or AppRoute.Leaderboards => SplitListPage.Leaderboards,
        AppRoute.SongDetail => SplitListPage.SongDetail,
        _ => null,
    };

    /// <summary>Whether a list page opens a route in its trailing pane.</summary>
    /// <param name="page">List page.</param>
    /// <param name="route">Destination.</param>
    /// <returns><see langword="true"/> for the page's sub-pages.</returns>
    public static bool Accepts(SplitListPage page, AppRoute route) => page switch
    {
        SplitListPage.Rivals => route is AppRoute.RivalDetail,
        SplitListPage.Leaderboards => route is AppRoute.FullRankings or AppRoute.BandRankings,
        SplitListPage.SongDetail => route is AppRoute.SongLeaderboard or AppRoute.SongBandLeaderboard or AppRoute.PlayerHistory,
        _ => false,
    };

    /// <summary>Whether a route stays inside an open pane when opened from it (the open item's own sub-pages).</summary>
    /// <param name="route">Destination.</param>
    /// <returns><see langword="true"/> for boards, rankings, Score History, Rival Detail and Rivalry.</returns>
    public static bool OpensInPane(AppRoute route) => route is AppRoute.FullRankings or AppRoute.BandRankings
        or AppRoute.SongLeaderboard or AppRoute.SongBandLeaderboard or AppRoute.PlayerHistory
        or AppRoute.RivalDetail or AppRoute.Rivalry;

    /// <summary>
    /// Whether a page draws the split-pane board title instead of the song header (song-leaderboard-header Variants,
    /// owner-approved #342; Windows #667): a song board or Score History at the root of the trailing pane, shown side by
    /// side with Song Detail. A stacked pane (window too narrow), a page pushed deeper in the pane and every full-width
    /// push keep the song header (R1).
    /// </summary>
    /// <param name="list">List page the pane belongs to.</param>
    /// <param name="sideBySide">Whether the list and the pane show side by side now (not stacked).</param>
    /// <param name="paneDepth">The page's depth in the pane's own stack (0 = the pane's root).</param>
    /// <param name="route">The page's route.</param>
    /// <returns><see langword="true"/> when the page is titled by its board beside Song Detail.</returns>
    public static bool TitlesBoardBesideList(SplitListPage? list, bool sideBySide, int paneDepth, AppRoute? route) =>
        sideBySide && paneDepth == 0 && list == SplitListPage.SongDetail
        && route is AppRoute.SongLeaderboard or AppRoute.SongBandLeaderboard or AppRoute.PlayerHistory;

    /// <summary>Where a navigation lands.</summary>
    /// <param name="page">List page on top of the section's stack, or <see langword="null"/>.</param>
    /// <param name="allowsSplit">Whether the window allows two panes now.</param>
    /// <param name="paneOpen">Whether the top page has an open pane.</param>
    /// <param name="fromPane">Whether the navigation started inside that pane.</param>
    /// <param name="route">Destination.</param>
    /// <returns>
    /// From an open pane, its own sub-pages push inside it and everything else (profiles, songs) full width over the split;
    /// otherwise a list page's sub-page opens (or replaces) the pane while the window allows a split, and everything else
    /// pushes full width.
    /// </returns>
    public static SplitAction Decide(SplitListPage? page, bool allowsSplit, bool paneOpen, bool fromPane, AppRoute route)
    {
        if (paneOpen && fromPane) return OpensInPane(route) ? SplitAction.PushInPane : SplitAction.PushFull;
        if (!allowsSplit || page is not { } list) return SplitAction.PushFull;
        return Accepts(list, route) ? SplitAction.OpenPane : SplitAction.PushFull;
    }
}
#endregion
