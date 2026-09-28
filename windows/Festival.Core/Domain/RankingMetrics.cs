namespace Festival.Core.Domain;

#region Ranking metric
/// <summary>
/// Sort metric for <c>/api/rankings/{instrument}</c>, mirroring the web client's <c>RankingMetric</c>
/// (<c>packages/core/src/api/serverTypes.ts:1137</c>) and Apple's <c>RankingMetric</c>.
/// </summary>
public enum RankingMetric
{
    /// <summary>Bayesian-adjusted skill percentile (<c>adjusted</c>).</summary>
    Adjusted,
    /// <summary>Weighted percentile (<c>weighted</c>).</summary>
    Weighted,
    /// <summary>Full-combo rate (<c>fcrate</c>).</summary>
    FcRate,
    /// <summary>Summed score (<c>totalscore</c>, the web default).</summary>
    TotalScore,
    /// <summary>Percent of engine maximum (<c>maxscore</c>; accounts only).</summary>
    MaxScore,
}

/// <summary>Service identifiers, labels and band narrowing for <see cref="RankingMetric"/>.</summary>
public static class RankingMetricInfo
{
    /// <summary>Every metric in the web picker's order (Total Score first, then the experimental ones).</summary>
    public static IReadOnlyList<RankingMetric> All { get; } =
        [RankingMetric.TotalScore, RankingMetric.Adjusted, RankingMetric.Weighted, RankingMetric.FcRate, RankingMetric.MaxScore];

    /// <summary>The metric used when nothing (or something unknown) is requested.</summary>
    public const RankingMetric Default = RankingMetric.TotalScore;

    /// <summary>Returns the <c>rankBy</c> query value.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>A value such as <c>totalscore</c>.</returns>
    public static string ServiceId(this RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => "adjusted",
        RankingMetric.Weighted => "weighted",
        RankingMetric.FcRate => "fcrate",
        RankingMetric.TotalScore => "totalscore",
        _ => "maxscore",
    };

    /// <summary>Returns the same metric name as the web rank-by picker.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => "Adjusted",
        RankingMetric.Weighted => "Weighted",
        RankingMetric.FcRate => "FC Rate",
        RankingMetric.TotalScore => "Total Score",
        _ => "Max Score",
    };

    /// <summary>Whether the metric ranks by a raw percentile shown as a "Top N%" value.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns><see langword="true"/> for Adjusted and Weighted.</returns>
    public static bool IsPercentile(this RankingMetric metric) => metric is RankingMetric.Adjusted or RankingMetric.Weighted;

    /// <summary>
    /// Narrows to a band metric the way the web's <c>coerceBandRankingMetric</c> does: bands have no Max Score,
    /// so it falls back to Total Score.
    /// </summary>
    /// <param name="metric">Shared picker metric.</param>
    /// <returns>Band-safe metric.</returns>
    public static BandRankingMetric ToBandMetric(this RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => BandRankingMetric.Adjusted,
        RankingMetric.Weighted => BandRankingMetric.Weighted,
        RankingMetric.FcRate => BandRankingMetric.FcRate,
        _ => BandRankingMetric.TotalScore,
    };

    /// <summary>Widens a band metric back to the shared account metric (for formatting).</summary>
    /// <param name="metric">Band metric.</param>
    /// <returns>Matching account metric.</returns>
    public static RankingMetric ToRankingMetric(this BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => RankingMetric.Adjusted,
        BandRankingMetric.Weighted => RankingMetric.Weighted,
        BandRankingMetric.FcRate => RankingMetric.FcRate,
        _ => RankingMetric.TotalScore,
    };

    /// <summary>Parses an exact <c>rankBy</c> value.</summary>
    /// <param name="serviceId">Value such as <c>fcrate</c>.</param>
    /// <param name="metric">Parsed metric when successful.</param>
    /// <returns><see langword="true"/> for one of the five known values.</returns>
    public static bool TryParse(string? serviceId, out RankingMetric metric)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(candidate.ServiceId(), serviceId, StringComparison.Ordinal))
            {
                metric = candidate;
                return true;
            }
        }
        metric = Default;
        return false;
    }

    /// <summary>Parses a route or saved value, falling back to <see cref="Default"/> like <c>coerceRankingMetric</c>.</summary>
    /// <param name="serviceId">Candidate value.</param>
    /// <returns>Known metric or Total Score.</returns>
    public static RankingMetric Coerce(string? serviceId) => TryParse(serviceId, out var metric) ? metric : Default;
}
#endregion
