using System.Globalization;

namespace Festival.Core.Domain;

#region Chart primitives
/// <summary>A plotted point in unit coordinates: X 0 (left) … 1 (right), Y 0 (top) … 1 (bottom).</summary>
/// <param name="X">Horizontal fraction.</param>
/// <param name="Y">Vertical fraction from the top.</param>
/// <param name="Highlight">Whether to draw the point emphasized (personal best, latest).</param>
public sealed record ChartPoint(double X, double Y, bool Highlight = false);

/// <summary>A horizontal grid line and label.</summary>
/// <param name="Y">Vertical fraction from the top.</param>
/// <param name="Label">Axis text.</param>
public sealed record ChartTick(double Y, string Label);

/// <summary>A vertical bar in unit coordinates.</summary>
/// <param name="X">Centre fraction.</param>
/// <param name="Height">Height fraction from the bottom.</param>
public sealed record ChartBar(double X, double Height);
#endregion

#region Rank history chart
/// <summary>
/// Geometry for the player page's rank-history card (web <c>RankHistoryChart</c>, metric Total Score): a rank line with
/// #1 at the top on a padded axis that never shows "#0", and Total Score bars on the same date axis.
/// </summary>
/// <param name="RankLine">Rank points, oldest first.</param>
/// <param name="RankTicks">Rank grid lines, best first.</param>
/// <param name="ScoreBars">Total Score bars (empty when no snapshot has a score).</param>
/// <param name="Headline">"#8 of 500".</param>
/// <param name="TotalScoreLine">"Total Score 1,234", or <see langword="null"/>.</param>
/// <param name="StartLabel">First day.</param>
/// <param name="EndLabel">Last day.</param>
/// <param name="Summary">Screen-reader trend sentence.</param>
public sealed record RankHistoryChartModel(
    List<ChartPoint> RankLine, List<ChartTick> RankTicks, List<ChartBar> ScoreBars,
    string Headline, string? TotalScoreLine, string StartLabel, string EndLabel, string Summary)
{
    /// <summary>Builds the chart from ranked snapshots.</summary>
    /// <param name="ranked">Chronological snapshots with a positive Total Score rank (at least one).</param>
    /// <returns>Chart geometry, or <see langword="null"/> when empty.</returns>
    public static RankHistoryChartModel? Build(IReadOnlyList<PlayerRankHistorySnapshot> ranked)
    {
        if (ranked.Count == 0) return null;
        var axis = PlayerRankingText.RankAxis(ranked.Select(r => r.TotalScoreRank).ToList());
        double span = axis.Worst - axis.Best;
        double X(int i) => ranked.Count == 1 ? 0.5 : (double)i / (ranked.Count - 1);
        var line = ranked.Select((r, i) => new ChartPoint(X(i), (r.TotalScoreRank - axis.Best) / span, i == ranked.Count - 1)).ToList();
        var ticks = axis.Ticks.Select(t => new ChartTick((t - axis.Best) / span, ScoreFormatting.Rank(t))).ToList();
        var maxScore = ranked.Max(r => r.TotalScore ?? 0);
        var bars = maxScore <= 0
            ? []
            : ranked.Select((r, i) => new ChartBar(X(i), (double)(r.TotalScore ?? 0) / maxScore)).ToList();
        var latest = ranked[^1];
        var field = latest.RankedAccountCount is { } n ? " of " + n.ToString("N0", CultureInfo.CurrentCulture) : "";
        return new RankHistoryChartModel(
            line, ticks, bars,
            ScoreFormatting.Rank(latest.TotalScoreRank) + field,
            latest.TotalScore is { } total ? "Total Score " + ScoreFormatting.Score(total) : null,
            DayLabel(ranked[0]), DayLabel(latest),
            PlayerRankingText.RankTrend(ranked));
    }

    /// <summary>Short month/day label.</summary>
    /// <param name="snapshot">Snapshot.</param>
    /// <returns>Label such as "Sep 21".</returns>
    private static string DayLabel(PlayerRankHistorySnapshot snapshot) =>
        snapshot.Date?.ToString("MMM d", CultureInfo.CurrentCulture) ?? snapshot.SnapshotDate;
}
#endregion

#region Percentile bars
/// <summary>One horizontal bar of the percentile card.</summary>
/// <param name="Label">"Top 5%".</param>
/// <param name="Count">Songs in the band.</param>
/// <param name="Fraction">Bar length relative to the largest band.</param>
/// <param name="Gold">Top-5% band.</param>
public sealed record PercentileBar(string Label, int Count, double Fraction, bool Gold)
{
    /// <summary>Count text.</summary>
    public string CountText => Count.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}: {CountText} {(Count == 1 ? "song" : "songs")}";

    /// <summary>Builds bars from non-empty buckets.</summary>
    /// <param name="buckets">Buckets.</param>
    /// <returns>Bars, best first.</returns>
    public static List<PercentileBar> Build(IReadOnlyList<PlayerPercentileBucket> buckets)
    {
        var max = buckets.Count == 0 ? 1 : buckets.Max(b => b.Count);
        return buckets.Select(b => new PercentileBar(b.Label, b.Count, (double)b.Count / max, b.IsTopFive)).ToList();
    }
}
#endregion

#region Score history chart
/// <summary>Score-over-time line for Player History (native addition; shown for two or more dated rows).</summary>
/// <param name="Points">Chronological points; the personal best is highlighted.</param>
/// <param name="Ticks">Score grid lines, highest first.</param>
/// <param name="StartLabel">First date.</param>
/// <param name="EndLabel">Last date.</param>
/// <param name="Summary">Screen-reader sentence.</param>
public sealed record ScoreHistoryChartModel(List<ChartPoint> Points, List<ChartTick> Ticks, string StartLabel, string EndLabel, string Summary)
{
    /// <summary>Builds the chart from history rows in any order.</summary>
    /// <param name="entries">Rows for one song and chart.</param>
    /// <returns>Geometry, or <see langword="null"/> with fewer than two dated rows.</returns>
    public static ScoreHistoryChartModel? Build(IEnumerable<ScoreHistoryEntry> entries)
    {
        var dated = entries.Where(e => e.DisplayDate is not null).OrderBy(e => e.DisplayDate).ToList();
        if (dated.Count < 2) return null;
        var first = dated[0].DisplayDate!.Value;
        var spanTicks = Math.Max(1, (dated[^1].DisplayDate!.Value - first).Ticks);
        var low = dated.Min(e => e.NewScore);
        var high = dated.Max(e => e.NewScore);
        var pad = Math.Max(1, (high - low) / 8);
        var top = high + pad;
        var bottom = Math.Max(0, low - pad);
        double range = Math.Max(1, top - bottom);
        var bestIndex = dated.IndexOf(dated.MaxBy(e => e.NewScore)!);
        var points = dated.Select((e, i) => new ChartPoint(
            (double)(e.DisplayDate!.Value - first).Ticks / spanTicks, (top - e.NewScore) / range, i == bestIndex)).ToList();
        var ticks = new[] { top, (top + bottom) / 2, bottom }
            .Select(v => new ChartTick((top - v) / range, ScoreFormatting.Score(v))).ToList();
        var best = dated[bestIndex];
        return new ScoreHistoryChartModel(points, ticks,
            dated[0].DateText, dated[^1].DateText,
            $"{dated.Count} score changes from {dated[0].DateText} to {dated[^1].DateText}. Best {ScoreFormatting.Score(best.NewScore)} on {best.DateText}.");
    }
}
#endregion
