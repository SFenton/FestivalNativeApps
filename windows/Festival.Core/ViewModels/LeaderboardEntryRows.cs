using System.ComponentModel;
using System.Windows.Input;

namespace Festival.Core.ViewModels;

#region Shared leaderboard row contract
/// <summary>
/// One row of any leaderboard (operator batch 7.7, one leaderboard design): Song Detail previews, song boards, their
/// pinned "your score" rows, Full/Band Rankings, the Leaderboards overview and its spotlight. The App's single
/// <c>LeaderboardEntryRow</c> control draws every implementation as the web's <c>entryRow</c>: its own frosted 48 epx
/// row, the selected player's row in <c>purpleHighlight</c> with bold rank and name (web <c>isPlayer</c>).
/// </summary>
public interface ILeaderboardEntryRow
{
    /// <summary><c>#1,234</c> (or an em dash for an unranked pinned row).</summary>
    string RankText { get; }

    /// <summary>Display name or band roster.</summary>
    string Name { get; }

    /// <summary>Whether this is the selected player's own row (accent fill, bold).</summary>
    bool IsSelected { get; }

    /// <summary>Rank characters every row of the board reserves (web <c>computeRankWidth</c>); 0 = own width.</summary>
    int RankChars { get; }

    /// <summary>Destination (profile, Statistics, Band Detail, a full board page), or <see langword="null"/> for none.</summary>
    AppRoute? Route { get; }

    /// <summary>UIA automation ID.</summary>
    string AutomationId { get; }

    /// <summary>UIA name: the whole row is one stop that reads everything (Android one-stop-per-row learning).</summary>
    string Announcement { get; }
}

/// <summary>A score row (web <c>LeaderboardEntry</c>): season, score, accuracy badge and stars.</summary>
public interface ILeaderboardScoreRow : ILeaderboardEntryRow
{
    /// <summary><c>S15</c>, or empty (column hidden).</summary>
    string Season { get; }

    /// <summary>Grouped score.</summary>
    string Score { get; }

    /// <summary>Score characters every row of the board reserves (web <c>scoreWidth</c> in <c>ch</c>); 0 = own width.</summary>
    int ScoreChars { get; }

    /// <summary>Accuracy text (<c>98.2%</c>), or empty.</summary>
    string Accuracy { get; }

    /// <summary>Whether <see cref="Accuracy"/> is shown.</summary>
    bool HasAccuracy { get; }

    /// <summary>Accuracy in ten-thousandths of a percent, for the badge tint.</summary>
    double AccuracyValue { get; }

    /// <summary>Explicit full combo (gold skewed badge).</summary>
    bool IsFullCombo { get; }

    /// <summary>Stars, or 0 when the board does not show them.</summary>
    int StarCount { get; }
}

/// <summary>A rankings row (web <c>RankingEntry</c>): songs label, then the rating with an optional Bayesian value.</summary>
public interface ILeaderboardRankingRow : ILeaderboardEntryRow
{
    /// <summary>"X / Y" songs (or full combos).</summary>
    string SongsText { get; }

    /// <summary>Primary rating.</summary>
    string RatingText { get; }

    /// <summary>Bayesian value, or empty.</summary>
    string BayesianText { get; }
}

/// <summary>Shared column widths for a board (web <c>computeRankWidth</c> and the score <c>ch</c> width).</summary>
public static class LeaderboardColumns
{
    /// <summary>Longest rank text among the rows and an optional pinned row (0 when there are none).</summary>
    /// <param name="ranks">Rank texts.</param>
    /// <returns>Characters.</returns>
    public static int Widest(IEnumerable<string> ranks) => ranks.Select(r => r.Length).DefaultIfEmpty(0).Max();
}
#endregion

#region Board pager contract
/// <summary>
/// Paging state every paginated board exposes to the one shared pager control (web <c>Paginator</c> in
/// <c>FixedLeaderboardPagination</c>; operator batch 7.4): « ‹ "page / total" › », shown only when there is more than one page.
/// </summary>
public interface IBoardPager : INotifyPropertyChanged
{
    /// <summary>"3 / 120" with grouping (web <c>leaderboard-page-info</c>).</summary>
    string InfoText { get; }

    /// <summary>Spoken page position ("Page 3 of 120").</summary>
    string InfoAnnouncement { get; }

    /// <summary>Whether there is more than one page (the web hides the pager otherwise).</summary>
    bool IsPaged { get; }

    /// <summary>Whether First/Previous are enabled.</summary>
    bool CanGoBack { get; }

    /// <summary>Whether Next/Last are enabled.</summary>
    bool CanGoForward { get; }

    /// <summary>Page 1.</summary>
    ICommand FirstCommand { get; }

    /// <summary>Previous page.</summary>
    ICommand PreviousCommand { get; }

    /// <summary>Next page.</summary>
    ICommand NextCommand { get; }

    /// <summary>Last page.</summary>
    ICommand LastCommand { get; }
}
#endregion
