using System.Globalization;

namespace Festival.Core.Domain;

#region Band formatting
/// <summary>Display text for band statistics, matching the web Band page's formatters (<c>BandPage.tsx</c>).</summary>
public static class BandFormatting
{
    /// <summary>Placeholder for an absent value.</summary>
    public const string None = "—";

    /// <summary>Accuracy scale: expanded accuracy ÷ 10,000 = percent (web <c>ACCURACY_SCALE</c>).</summary>
    public const double AccuracyScale = 10_000;

    /// <summary><c>#1,234</c>, or <see cref="None"/> when unranked.</summary>
    /// <param name="rank">One-based rank.</param>
    /// <returns>Rank text.</returns>
    public static string Rank(int rank) => rank > 0 ? "#" + rank.ToString("N0", CultureInfo.CurrentCulture) : None;

    /// <summary><c>#1.5</c>, or <see cref="None"/>.</summary>
    /// <param name="rank">Mean rank.</param>
    /// <returns>Rank text with one decimal.</returns>
    public static string AverageRank(double rank) =>
        double.IsFinite(rank) && rank > 0 ? "#" + rank.ToString("N1", CultureInfo.CurrentCulture) : None;

    /// <summary><c>99.2%</c> from expanded accuracy, or <see cref="None"/>.</summary>
    /// <param name="expandedAccuracy">Accuracy in ten-thousandths of a percent.</param>
    /// <returns>Percent text with one decimal.</returns>
    public static string Accuracy(double? expandedAccuracy) =>
        expandedAccuracy is { } value && double.IsFinite(value) && value > 0
            ? (value / AccuracyScale).ToString("0.0", CultureInfo.CurrentCulture) + "%" : None;

    /// <summary><c>4.9</c> stars, or <see cref="None"/>.</summary>
    /// <param name="stars">Mean stars.</param>
    /// <returns>Stars with one decimal.</returns>
    public static string Stars(double stars) =>
        double.IsFinite(stars) && stars > 0 ? stars.ToString("0.0", CultureInfo.CurrentCulture) : None;

    /// <summary><c>97.3%</c> from a 0–1 fraction.</summary>
    /// <param name="fraction">Fraction.</param>
    /// <returns>Percent text with one decimal, or <see cref="None"/> when not finite.</returns>
    public static string Percentage(double fraction) =>
        double.IsFinite(fraction) ? (fraction * 100).ToString("0.0", CultureInfo.CurrentCulture) + "%" : None;

    /// <summary><c>Top 3%</c> (two decimals below 1%), matching <c>formatPercentileTopExact</c>.</summary>
    /// <param name="rawPercentile">Fraction where 0 is the best rank.</param>
    /// <returns>Percentile text.</returns>
    public static string Percentile(double rawPercentile)
    {
        if (!double.IsFinite(rawPercentile)) return None;
        var top = Math.Clamp(rawPercentile * 100, 0.01, 100);
        return "Top " + top.ToString(top < 1 ? "0.00" : "0", CultureInfo.CurrentCulture) + "%";
    }

    /// <summary>Grouped count <c>12,345</c>.</summary>
    /// <param name="value">Count.</param>
    /// <returns>Grouped digits.</returns>
    public static string Count(long value) => value.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary><c>36 / 40</c>.</summary>
    /// <param name="part">Numerator.</param>
    /// <param name="total">Denominator.</param>
    /// <returns>Fraction text.</returns>
    public static string Fraction(int part, int total) => $"{Count(part)} / {Count(total)}";

    /// <summary>A metric's value as shown in rank-history rows.</summary>
    /// <param name="value">Rating, fraction or score.</param>
    /// <param name="metric">Metric.</param>
    /// <returns>Percentile, percentage or grouped score.</returns>
    public static string MetricValue(double? value, BandRankingMetric metric)
    {
        if (value is not { } v || !double.IsFinite(v)) return None;
        return metric switch
        {
            BandRankingMetric.Adjusted or BandRankingMetric.Weighted => Percentile(v),
            BandRankingMetric.FcRate => Percentage(v),
            _ => Count((long)Math.Round(v)),
        };
    }

    /// <summary>A snapshot date as <c>Sep 27</c>, or the raw text when not <c>yyyy-MM-dd</c>.</summary>
    /// <param name="snapshotDate">Service date.</param>
    /// <returns>Short date.</returns>
    public static string ShortDate(string snapshotDate) =>
        DateOnly.TryParseExact(snapshotDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            ? date.ToString("MMM d", CultureInfo.CurrentCulture) : snapshotDate;

    /// <summary>A page number for a rank on 25-row boards (web <c>getLeaderboardPageForRank</c>).</summary>
    /// <param name="rank">One-based rank.</param>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>One-based page.</returns>
    public static int PageForRank(int rank, int pageSize = 25) => rank <= 0 ? 1 : (rank - 1) / Math.Max(1, pageSize) + 1;
}
#endregion
