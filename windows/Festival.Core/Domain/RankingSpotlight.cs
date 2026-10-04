namespace Festival.Core.Domain;

#region Paging
/// <summary>One-based paging math shared by every paginated rankings or leaderboard board.</summary>
public static class LeaderboardPaging
{
    /// <summary>Rows per full page (web <c>LEADERBOARD_PAGE_SIZE</c>).</summary>
    public const int PageSize = 25;

    /// <summary>Rows per overview card.</summary>
    public const int CardSize = 10;

    /// <summary>Number of pages, at least one even for an empty board.</summary>
    /// <param name="total">Population.</param>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Page count.</returns>
    public static int PageCount(long total, int pageSize = PageSize)
    {
        var size = Math.Max(1, pageSize);
        return total <= 0 ? 1 : (int)Math.Min(int.MaxValue, (total - 1) / size + 1);
    }

    /// <summary>The page containing a rank, like the web's <c>getLeaderboardPageForRank</c>.</summary>
    /// <param name="rank">One-based rank.</param>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Page, or 1 for a non-positive rank.</returns>
    public static int PageForRank(int rank, int pageSize = PageSize) => rank <= 0 ? 1 : (rank - 1) / Math.Max(1, pageSize) + 1;

    /// <summary>Clamps a requested page into the loaded board's bounds.</summary>
    /// <param name="requested">Requested page.</param>
    /// <param name="totalPages">Board page count.</param>
    /// <returns>Page in <c>1…totalPages</c>.</returns>
    public static int Corrected(int requested, int totalPages) => Math.Clamp(requested, 1, Math.Max(1, totalPages));

    /// <summary>
    /// Grows a bring-into-view target downwards by the floating footer's height (WCAG 2.4.11, focus not obscured): the
    /// pinned row and pager overlay the bottom of the rows, so a row scrolled only to the bottom edge would sit under them.
    /// </summary>
    /// <param name="height">Target height.</param>
    /// <param name="footerHeight">Footer's measured height plus its gap (0 while collapsed or unknown).</param>
    /// <returns>Expanded height.</returns>
    public static double RevealAboveFooter(double height, double footerHeight) =>
        Math.Max(0, double.IsFinite(height) ? height : 0) + Math.Max(0, double.IsFinite(footerHeight) ? footerHeight : 0);
}
#endregion

#region Spotlight
/// <summary>How the selected player's own row is presented on a loaded board.</summary>
public enum SpotlightPlacementKind
{
    /// <summary>No player is selected.</summary>
    None,
    /// <summary>Their row is already visible; highlight it in place.</summary>
    Inline,
    /// <summary>Not visible and their own rank is still loading (or failed).</summary>
    Pending,
    /// <summary>Not visible and they have no rank on this board.</summary>
    Unranked,
    /// <summary>Not visible; show their row separately below the board.</summary>
    Footer,
}

/// <summary>A spotlight decision and, for <see cref="SpotlightPlacementKind.Footer"/>, the row to show.</summary>
/// <param name="Kind">Placement.</param>
/// <param name="Entry">Selected player's row (footer only).</param>
public readonly record struct RankingSpotlightPlacement(SpotlightPlacementKind Kind, AccountRankingEntry? Entry = null);

/// <summary>
/// Pure selected-player spotlight decision for overview cards and Full Rankings, mirroring the web's
/// <c>RankingCard</c> (<c>spotlightFooterRows</c> drops a ranking already in the top rows) and Apple's
/// <c>RankingSpotlight.placement</c>.
/// </summary>
public static class RankingSpotlight
{
    /// <summary>Whether two account IDs match (the wire's casing varies).</summary>
    /// <param name="a">First ID.</param>
    /// <param name="b">Second ID.</param>
    /// <returns><see langword="true"/> when equal ignoring case.</returns>
    public static bool SameAccount(string? a, string? b) =>
        a is not null && b is not null && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    /// <summary>Decides where the selected player's row goes relative to one loaded board.</summary>
    /// <param name="selectedAccountId">Selected player, or <see langword="null"/>/blank.</param>
    /// <param name="visibleEntries">Rows already shown (top ten or the current page).</param>
    /// <param name="ownLoaded">Whether the per-account read has completed successfully.</param>
    /// <param name="own">The player's own row when ranked (ignored until <paramref name="ownLoaded"/>).</param>
    /// <returns>Placement.</returns>
    public static RankingSpotlightPlacement Place(
        string? selectedAccountId, IEnumerable<AccountRankingEntry> visibleEntries, bool ownLoaded, AccountRankingEntry? own)
    {
        if (string.IsNullOrWhiteSpace(selectedAccountId)) return new(SpotlightPlacementKind.None);
        if (visibleEntries.Any(e => SameAccount(e.AccountId, selectedAccountId))) return new(SpotlightPlacementKind.Inline);
        if (!ownLoaded) return new(SpotlightPlacementKind.Pending);
        if (own is null) return new(SpotlightPlacementKind.Unranked);
        // A stale read racing a new selection never surfaces someone else's row.
        return SameAccount(own.AccountId, selectedAccountId)
            ? new(SpotlightPlacementKind.Footer, own)
            : new(SpotlightPlacementKind.Pending);
    }
}
#endregion
