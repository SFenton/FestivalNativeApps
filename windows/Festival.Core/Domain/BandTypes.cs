namespace Festival.Core.Domain;

#region Band type
/// <summary>The three ranked band sizes (<c>FortniteFestivalWeb/src/utils/bandTypes.ts</c>).</summary>
public enum BandType
{
    /// <summary>Two players (<c>Band_Duets</c>).</summary>
    Duets,
    /// <summary>Three players (<c>Band_Trios</c>).</summary>
    Trios,
    /// <summary>Four players (<c>Band_Quad</c>).</summary>
    Quad,
}

/// <summary>Service identifiers and labels for <see cref="BandType"/>.</summary>
public static class BandTypeInfo
{
    /// <summary>All band sizes, smallest first.</summary>
    public static IReadOnlyList<BandType> All { get; } = Enum.GetValues<BandType>();

    /// <summary>Returns the exact service identifier used in URLs and payloads.</summary>
    /// <param name="bandType">Band size.</param>
    /// <returns><c>Band_Duets</c>, <c>Band_Trios</c> or <c>Band_Quad</c>.</returns>
    public static string ServiceId(this BandType bandType) => bandType switch
    {
        BandType.Duets => "Band_Duets",
        BandType.Trios => "Band_Trios",
        _ => "Band_Quad",
    };

    /// <summary>Returns the same band-size name as the web client.</summary>
    /// <param name="bandType">Band size.</param>
    /// <returns><c>Duos</c>, <c>Trios</c> or <c>Quads</c>.</returns>
    public static string Label(this BandType bandType) => bandType switch
    {
        BandType.Duets => "Duos",
        BandType.Trios => "Trios",
        _ => "Quads",
    };

    /// <summary>Number of players in a band of this size.</summary>
    /// <param name="bandType">Band size.</param>
    /// <returns>2, 3 or 4.</returns>
    public static int MemberCount(this BandType bandType) => (int)bandType + 2;

    /// <summary>Parses an exact service identifier.</summary>
    /// <param name="serviceId">Identifier such as <c>Band_Trios</c>.</param>
    /// <param name="bandType">Parsed size when successful.</param>
    /// <returns><see langword="true"/> for one of the three known identifiers.</returns>
    public static bool TryParse(string? serviceId, out BandType bandType)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(candidate.ServiceId(), serviceId, StringComparison.Ordinal))
            {
                bandType = candidate;
                return true;
            }
        }
        bandType = default;
        return false;
    }
}
#endregion

#region Band ranking metric
/// <summary>Band rank-by metrics (<c>rankBy</c> query values); bands have no max-score metric.</summary>
public enum BandRankingMetric
{
    /// <summary>Adjusted percentile (<c>adjusted</c>).</summary>
    Adjusted,
    /// <summary>Weighted percentile (<c>weighted</c>).</summary>
    Weighted,
    /// <summary>Full-combo rate (<c>fcrate</c>).</summary>
    FcRate,
    /// <summary>Total score (<c>totalscore</c>).</summary>
    TotalScore,
}

/// <summary>Service identifiers and labels for <see cref="BandRankingMetric"/>.</summary>
public static class BandRankingMetricInfo
{
    /// <summary>All metrics in the web picker's order.</summary>
    public static IReadOnlyList<BandRankingMetric> All { get; } = Enum.GetValues<BandRankingMetric>();

    /// <summary>The band Rank By options Settings allows (web <c>getEnabledBandRankingMetrics</c>).</summary>
    /// <param name="experimentalRanks">Settings' Experimental Ranks toggle.</param>
    /// <returns><see cref="All"/> when on; only Total Score when off.</returns>
    public static IReadOnlyList<BandRankingMetric> Enabled(bool experimentalRanks) =>
        experimentalRanks ? All : [BandRankingMetric.TotalScore];

    /// <summary>Falls back to Total Score for an experimental band metric while the toggle is off
    /// (web <c>coerceBandRankingMetric</c>).</summary>
    /// <param name="metric">Requested metric.</param>
    /// <param name="experimentalRanks">Settings' Experimental Ranks toggle.</param>
    /// <returns>The metric, or Total Score when Settings hides it.</returns>
    public static BandRankingMetric Gate(this BandRankingMetric metric, bool experimentalRanks) =>
        experimentalRanks ? metric : BandRankingMetric.TotalScore;

    /// <summary>Returns the <c>rankBy</c> query value.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns><c>adjusted</c>, <c>weighted</c>, <c>fcrate</c> or <c>totalscore</c>.</returns>
    public static string ServiceId(this BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => "adjusted",
        BandRankingMetric.Weighted => "weighted",
        BandRankingMetric.FcRate => "fcrate",
        _ => "totalscore",
    };

    /// <summary>Returns the picker label.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => "Adjusted Skill",
        BandRankingMetric.Weighted => "Weighted",
        BandRankingMetric.FcRate => "FC Rate",
        _ => "Total Score",
    };

    /// <summary>Parses a <c>rankBy</c> value.</summary>
    /// <param name="serviceId">Value such as <c>fcrate</c>.</param>
    /// <param name="metric">Parsed metric when successful.</param>
    /// <returns><see langword="true"/> for one of the four known values.</returns>
    public static bool TryParse(string? serviceId, out BandRankingMetric metric)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(candidate.ServiceId(), serviceId, StringComparison.Ordinal))
            {
                metric = candidate;
                return true;
            }
        }
        metric = default;
        return false;
    }
}
#endregion
