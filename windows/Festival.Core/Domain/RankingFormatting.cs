using System.Globalization;

namespace Festival.Core.Domain;

#region Ranking formatting
/// <summary>
/// Value formatting shared by every rankings surface, mirroring the web's <c>rankingHelpers.ts</c>
/// (<c>formatRating</c>, <c>formatPercentileTopExact</c>, <c>formatRatingValue</c>) and Apple's
/// <c>RankingFormatting</c>. Uses the current culture for grouping and decimals.
/// </summary>
public static class RankingFormatting
{
    /// <summary>Formats a metric's primary rating value as the cards show it.</summary>
    /// <param name="value">Raw value from <c>RatingValue</c>.</param>
    /// <param name="metric">Selected metric.</param>
    /// <returns>A percentile ("Top 3%"), percentage ("97.3%") or grouped integer.</returns>
    public static string Rating(double value, RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted or RankingMetric.Weighted => Percentile(value),
        RankingMetric.FcRate or RankingMetric.MaxScore => Percentage(value),
        _ => WholeNumber(value),
    };

    /// <summary>Formats a raw 0–1 percentile (0 is best) as "Top N%".</summary>
    /// <param name="rawPercentile">Fraction.</param>
    /// <returns>"Top 0.03%" below one percent, otherwise a whole "Top N%"; "N/A" when not finite.</returns>
    public static string Percentile(double rawPercentile)
    {
        if (!double.IsFinite(rawPercentile)) return "N/A";
        var top = Math.Clamp(rawPercentile * 100, 0.01, 100);
        return "Top " + top.ToString(top < 1 ? "0.00" : "0", CultureInfo.CurrentCulture) + "%";
    }

    /// <summary>Formats a raw 0–1 fraction as a one-decimal percentage.</summary>
    /// <param name="fraction">FC Rate or Max Score fraction.</param>
    /// <returns>Text such as "97.3%"; "N/A" when not finite.</returns>
    public static string Percentage(double fraction) =>
        double.IsFinite(fraction) ? (fraction * 100).ToString("0.0", CultureInfo.CurrentCulture) + "%" : "N/A";

    /// <summary>Formats a whole score total with grouping.</summary>
    /// <param name="value">Total score.</param>
    /// <returns>Text such as "12,345,678"; "N/A" when not finite.</returns>
    public static string WholeNumber(double value) =>
        double.IsFinite(value) ? Math.Round(value, MidpointRounding.AwayFromZero).ToString("N0", CultureInfo.CurrentCulture) : "N/A";

    /// <summary>Formats the Bayesian-adjusted rating shown beside a percentile, like <c>formatRatingValue</c>.</summary>
    /// <param name="value">Adjusted or weighted rating.</param>
    /// <returns>1–4 fraction digits depending on magnitude; "N/A" when not finite.</returns>
    public static string Bayesian(double value)
    {
        if (!double.IsFinite(value)) return "N/A";
        var magnitude = Math.Abs(value);
        if (magnitude < 0.1)
        {
            var text = value.ToString("0.0000", CultureInfo.CurrentCulture);
            var separator = CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator;
            text = text.TrimEnd('0');
            return text.EndsWith(separator, StringComparison.Ordinal) ? text + "0" : text;
        }
        return value.ToString(magnitude < 1 ? "0.00" : "0.0", CultureInfo.CurrentCulture);
    }

    /// <summary>Formats a rank as an English ordinal for screen readers, e.g. "1,234th".</summary>
    /// <param name="rank">One-based rank.</param>
    /// <returns>Grouped ordinal.</returns>
    public static string Ordinal(int rank)
    {
        var lastTwo = Math.Abs(rank) % 100;
        var suffix = lastTwo is >= 11 and <= 13 ? "th" : (Math.Abs(rank) % 10) switch
        {
            1 => "st",
            2 => "nd",
            3 => "rd",
            _ => "th",
        };
        return rank.ToString("N0", CultureInfo.CurrentCulture) + suffix;
    }

    /// <summary>Formats the "X / Y" row subtitle (web <c>getSongsLabel</c>; screen readers add "songs").</summary>
    /// <param name="count">Played (or full-combo) songs.</param>
    /// <param name="total">Charted songs.</param>
    /// <returns>Text such as "728 / 729".</returns>
    public static string Songs(int count, int total) =>
        string.Create(CultureInfo.CurrentCulture, $"{count:N0} / {total:N0}");
}
#endregion
