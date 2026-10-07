namespace Festival.Core.Domain;

#region Selected-row navigation
/// <summary>Whose row a song board's selected row shows.</summary>
public enum SelectedRowSubject
{
    /// <summary>The selected player's own score (solo board).</summary>
    Player,

    /// <summary>The selected player's band (band board).</summary>
    Band,
}

/// <summary>
/// What activating the selected profile's own row does, one rule for the solo and band song boards and Full Rankings
/// (pattern <c>leaderboard-row</c> R7, issues #307 and #318; web <c>getLeaderboardPageForRank</c> +
/// <c>navToPlayer</c>/<c>navToBand</c>, Apple <c>SelectedRowAction</c>). A row shown apart from its page (Song Detail's
/// appended row, a pinned footer while the row is on another page) jumps to the page containing its rank; a row already
/// on screen, or one without a rank, opens the profile (Statistics for a player, Band Detail for a band).
/// </summary>
/// <param name="JumpPage">Page to jump to, or <see langword="null"/> to open the profile.</param>
public readonly record struct SelectedRowAction(int? JumpPage)
{
    /// <summary>Whether the row jumps to its page rather than opening the profile.</summary>
    public bool Jumps => JumpPage is not null;

    /// <summary>The action of a full board's pinned footer row.</summary>
    /// <param name="rank">The row's one-based rank on this board (0 or less when unranked).</param>
    /// <param name="isVisible">Whether the row is on the page being shown.</param>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Open the profile when visible or unranked, else jump to the rank's page.</returns>
    public static SelectedRowAction Footer(int rank, bool isVisible, int pageSize = LeaderboardPaging.PageSize) =>
        new(!isVisible && rank > 0 ? LeaderboardPaging.PageForRank(rank, pageSize) : null);

    /// <summary>The action of a Song Detail preview's selected row.</summary>
    /// <param name="rank">The row's one-based rank on the full board.</param>
    /// <param name="isAppended">Whether it is appended after the preview's top rows (they don't include it).</param>
    /// <param name="pageSize">Rows per page of the full board.</param>
    /// <returns>Jump for an appended ranked row, else open the profile.</returns>
    public static SelectedRowAction Preview(int rank, bool isAppended, int pageSize = LeaderboardPaging.PageSize) =>
        Footer(rank, !isAppended, pageSize);

    /// <summary>The destination as Narrator reads it: "Jump to your position", "Open your statistics", "Jump to your
    /// band's position" or "Open band".</summary>
    /// <param name="subject">Player or band row.</param>
    /// <returns>Destination phrase.</returns>
    public string Destination(SelectedRowSubject subject) => (subject, Jumps) switch
    {
        (SelectedRowSubject.Player, true) => "Jump to your position",
        (SelectedRowSubject.Player, false) => "Open your statistics",
        (SelectedRowSubject.Band, true) => "Jump to your band's position",
        _ => "Open band",
    };
}
#endregion
