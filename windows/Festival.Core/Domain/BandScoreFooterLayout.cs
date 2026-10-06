namespace Festival.Core.Domain;

#region Band score footer layout
/// <summary>
/// Line plan for a band row's team score footer (web <c>SongBandScoreFooter</c>: score on the left, FC, accuracy and stars
/// on the right). The score is the row's key value, so it never truncates: when the badges don't fit beside it (half-width
/// Song Detail cards, four-member rows, 200% text) they move to a second line under it (WCAG 1.4.4, issue #264). The plan
/// is decided once per section (<see cref="BandScoreFooterSection{TKey}"/>, leaderboard-row R8): one row that needs two
/// lines stacks every row in its section.
/// </summary>
public static class BandScoreFooterLayout
{
    /// <summary>Rounding slack for layout sizes, so a footer that fits exactly does not stack.</summary>
    private const double Slack = 0.5;

    /// <summary>Whether one row's badges need a second line under the score.</summary>
    /// <param name="available">Footer width in epx.</param>
    /// <param name="scoreWidth">The score's desired width.</param>
    /// <param name="badgesWidth">The badges' desired width (0 when there are none).</param>
    /// <param name="spacing">Gap between the score and the badges.</param>
    /// <returns><see langword="true"/> when score, gap and badges are wider than the footer.</returns>
    public static bool Stacks(double available, double scoreWidth, double badgesWidth, double spacing) =>
        badgesWidth > 0 && !double.IsInfinity(available) && scoreWidth + spacing + badgesWidth > available + Slack;
}

/// <summary>
/// One section's shared footer plan: each realized row reports whether it needs two lines and the section stacks when any
/// does. Rows report from their own measurements only, so the plan converges (no row's need depends on the plan).
/// </summary>
/// <typeparam name="TKey">Row identity (the footer panel).</typeparam>
public sealed class BandScoreFooterSection<TKey> where TKey : notnull
{
    /// <summary>Every row that reported.</summary>
    private readonly HashSet<TKey> members = [];

    /// <summary>Rows that currently need two lines.</summary>
    private readonly HashSet<TKey> stacking = [];

    /// <summary>Whether every row in the section puts its badges under the score.</summary>
    public bool Stacked => stacking.Count > 0;

    /// <summary>Rows sharing this plan (to re-measure when it changes).</summary>
    public IReadOnlyCollection<TKey> Members => members;

    /// <summary>Records a row's own need.</summary>
    /// <param name="row">Row.</param>
    /// <param name="needsTwoLines">Whether the row's badges don't fit beside its score.</param>
    /// <returns><see langword="true"/> when <see cref="Stacked"/> changed, so the other rows must re-measure.</returns>
    public bool Report(TKey row, bool needsTwoLines)
    {
        var before = Stacked;
        members.Add(row);
        if (needsTwoLines) stacking.Add(row);
        else stacking.Remove(row);
        return before != Stacked;
    }

    /// <summary>Forgets a row that left the section (unloaded).</summary>
    /// <param name="row">Row.</param>
    /// <returns><see langword="true"/> when <see cref="Stacked"/> changed.</returns>
    public bool Remove(TKey row)
    {
        var before = Stacked;
        members.Remove(row);
        stacking.Remove(row);
        return before != Stacked;
    }
}
#endregion
