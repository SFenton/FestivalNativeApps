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

    /// <summary>
    /// Content of the whole section this row sits in (every row plus the pinned row; web <c>computeRankWidth</c> and the
    /// score <c>ch</c> width), from which <see cref="LeaderboardColumnLayout.Fit"/> decides the same columns and widths for
    /// every row (issue #37). <see langword="null"/> = the row's own content only.
    /// </summary>
    LeaderboardSection? Section { get; }

    /// <summary>Destination (profile, Statistics, Band Detail, a full board page), or <see langword="null"/> for none.</summary>
    AppRoute? Route { get; }

    /// <summary>UIA automation ID.</summary>
    string AutomationId { get; }

    /// <summary>UIA name: the whole row is one stop that reads everything (Android one-stop-per-row learning).</summary>
    string Announcement { get; }
}

/// <summary>
/// Geometry every leaderboard row shares (web <c>Layout.entryRowHeight</c>, issue #90): loaded rows, pinned rows, the
/// spotlight's loading row and the overview cards' loading skeleton, so rows match across pages and don't jump when data
/// arrives. <see cref="MinHeight"/> is a minimum: text scaling still grows rows.
/// </summary>
public static class LeaderboardRowMetrics
{
    /// <summary>Minimum row height in epx (web <c>entryRowHeight</c>).</summary>
    public const double MinHeight = 48;

    /// <summary>Gap between stacked rows in epx (each row is its own frosted surface, no card around them).</summary>
    public const double Spacing = 4;

    /// <summary>Height of <paramref name="rows"/> stacked rows at the minimum height.</summary>
    /// <param name="rows">Row count; zero or less is an empty block.</param>
    /// <returns>Block height in epx.</returns>
    public static double BlockHeight(int rows) => rows <= 0 ? 0 : rows * MinHeight + (rows - 1) * Spacing;
}

/// <summary>A score row (web <c>LeaderboardEntry</c>): season, score, accuracy badge and stars.</summary>
public interface ILeaderboardScoreRow : ILeaderboardEntryRow
{
    /// <summary><c>S15</c>, or empty (column hidden).</summary>
    string Season { get; }

    /// <summary>Grouped score.</summary>
    string Score { get; }


    /// <summary>Accuracy text (<c>98.2%</c>), or empty.</summary>
    string Accuracy { get; }

    /// <summary>Whether <see cref="Accuracy"/> is shown.</summary>
    bool HasAccuracy { get; }

    /// <summary>Accuracy in ten-thousandths of a percent, for the badge tint.</summary>
    double AccuracyValue { get; }

    /// <summary>Explicit full combo (gold skewed badge).</summary>
    bool IsFullCombo { get; }

    /// <summary>
    /// Badge text (score-accuracy control): the accuracy, <c>FC</c> for a full combo without accuracy, or empty for no
    /// badge (<see cref="ScoreFormatting.BadgeText"/>).
    /// </summary>
    string BadgeText => ScoreFormatting.BadgeText(Accuracy, IsFullCombo);

    /// <summary>UIA automation ID of the badge (<c>fst.score.accuracy.…</c>), kept in the raw view under the row's one stop.</summary>
    string BadgeAutomationId { get; }

    /// <summary>Stars, or 0 when the board does not show them.</summary>
    int StarCount { get; }

    /// <summary>
    /// Whether the season shows at any row width (the Score History tapped-bar detail row, web <c>renderDetailCard</c>).
    /// Other score rows show it from a 520 epx row (<see cref="LeaderboardColumnLayout.SeasonBreakpoint"/>).
    /// </summary>
    bool PinsSeason => false;

    /// <summary>
    /// UIA name while the row shows its season column: the season is on screen, so Narrator reads it too (issue #262).
    /// Rows whose <see cref="ILeaderboardEntryRow.Announcement"/> already reads the season at every width return it unchanged.
    /// </summary>
    string SeasonShownAnnouncement => Announcement;
}

/// <summary>
/// UIA IDs of a score row's raw-view parts, which sit under the row's one stop so Narrator reads the row once but tests
/// can still find them.
/// </summary>
public static class LeaderboardScoreRowIds
{
    /// <summary>Accuracy badge ID prefix (score-accuracy control).</summary>
    public const string AccuracyPrefix = "fst.score.accuracy.";

    /// <summary>Season text ID prefix (issue #262).</summary>
    public const string SeasonPrefix = "fst.score.season.";

    /// <summary>
    /// The season text's ID, paired with the row's badge ID: <c>fst.score.accuracy.&lt;key&gt;</c> becomes
    /// <c>fst.score.season.&lt;key&gt;</c>.
    /// </summary>
    /// <param name="badgeAutomationId">The row's badge ID.</param>
    /// <returns>Season ID.</returns>
    public static string Season(string badgeAutomationId) => SeasonPrefix +
        (badgeAutomationId.StartsWith(AccuracyPrefix, StringComparison.Ordinal) ? badgeAutomationId[AccuracyPrefix.Length..] : badgeAutomationId);
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

/// <summary>Measures a section's shared content (web <c>computeRankWidth</c>, the score <c>ch</c> width; issue #37).</summary>
public static class LeaderboardColumns
{
    /// <summary>Longest text among the rows and an optional pinned row (0 when there are none).</summary>
    /// <param name="texts">Texts.</param>
    /// <returns>Characters.</returns>
    public static int Widest(IEnumerable<string> texts) => texts.Select(r => r.Length).DefaultIfEmpty(0).Max();

    /// <summary>
    /// Measures every row of a section, including its pinned selected-player row, so all of them get one
    /// <see cref="LeaderboardColumnLayout.Fit"/> plan. Score rows measure seasons, scores, accuracy and stars; rankings
    /// rows their songs labels and ratings. The chevron column is reserved when any row opens a destination.
    /// </summary>
    /// <param name="rows">Section rows (score or rankings rows; the first decides the kind).</param>
    /// <returns>Section content.</returns>
    public static LeaderboardSection Measure(IEnumerable<ILeaderboardEntryRow> rows)
    {
        var all = rows.ToList();
        var rank = Widest(all.Select(r => r.RankText));
        var routes = all.Count == 0 || all.Any(r => r.Route is not null);
        if (all.FirstOrDefault() is ILeaderboardRankingRow)
        {
            var rankings = all.OfType<ILeaderboardRankingRow>().ToList();
            return new LeaderboardSection(LeaderboardRowKind.Ranking, rank, Widest(rankings.Select(r => r.SongsText)),
                Widest(rankings.Select(r => r.RatingText)), false, false, routes);
        }
        var scores = all.OfType<ILeaderboardScoreRow>().ToList();
        return new LeaderboardSection(LeaderboardRowKind.Score, rank, Widest(scores.Select(r => r.Season)),
            Widest(scores.Select(r => r.Score)), scores.Any(r => r.BadgeText.Length > 0), scores.Any(r => StarRating.From(r.StarCount) is not null),
            routes);
    }
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
