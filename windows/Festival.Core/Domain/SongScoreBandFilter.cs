using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Score band filter
/// <summary>
/// Selected-player single-chart Songs filter by leaderboard placement band and/or star count (web <c>FilterModal</c>
/// <c>percentileFilter</c>/<c>starsFilter</c>, which only apply with one instrument selected and player data present;
/// <c>useFilteredSongs.ts</c> <c>checkPct</c>/<c>checkStars</c>). The web keeps a toggle per band; natively one band and
/// one star level can be chosen, which covers the player page's drill-downs (web <c>instPercentileBucketUpdater</c>,
/// <c>instStarsUpdater</c>). Bounded and typed so it persists safely; cleared on confirmed deselection.
/// </summary>
/// <param name="Instrument">Chart the filter belongs to (inactive unless Songs is filtered to it).</param>
/// <param name="TopPercent">Placement band upper bound from <see cref="PlayerStatistics.PercentileThresholds"/>, or none.</param>
/// <param name="Stars">Star level 1–6 (6 = gold), or none.</param>
public sealed record SongScoreBandFilter(
    [property: JsonPropertyName("instrument")] Instrument Instrument,
    [property: JsonPropertyName("topPercent")] int? TopPercent = null,
    [property: JsonPropertyName("stars")] int? Stars = null)
{
    /// <summary>Whether any band is chosen.</summary>
    [JsonIgnore] public bool IsActive => TopPercent is not null || Stars is not null;

    /// <summary>Whether the saved values are known (otherwise the filter is dropped on load).</summary>
    [JsonIgnore]
    public bool IsValid => Enum.IsDefined(Instrument) &&
                           (TopPercent is null || PlayerStatistics.PercentileThresholds.Contains(TopPercent.Value)) &&
                           Stars is null or >= 1 and <= 6;

    /// <summary>Placement band of a score: the first threshold at or above <c>rank / totalEntries × 100</c>.</summary>
    /// <param name="rank">Rank.</param>
    /// <param name="totalEntries">Leaderboard size.</param>
    /// <returns>Band, or <see langword="null"/> when the score has no placement.</returns>
    public static int? Band(int? rank, int? totalEntries)
    {
        if (rank is not > 0 || totalEntries is not > 0) return null;
        var percent = Math.Min((double)rank.Value / totalEntries.Value * 100, 100);
        return PlayerStatistics.PercentileThresholds.First(t => percent <= t);
    }

    /// <summary>Whether a song's score on <see cref="Instrument"/> passes (no score passes neither band nor stars).</summary>
    /// <param name="detail">The selected player's score on the chart, or <see langword="null"/>.</param>
    /// <returns><see langword="true"/> when kept.</returns>
    public bool Matches(SongScoreDetail? detail)
    {
        if (TopPercent is { } top && Band(detail?.Rank, detail?.TotalEntries) != top) return false;
        return Stars is not { } stars || (detail?.Stars ?? 0) == stars;
    }

    /// <summary>"Top 5%" band label.</summary>
    /// <param name="top">Band upper bound.</param>
    /// <returns>Label.</returns>
    public static string BandLabel(int top) => $"Top {top.ToString(CultureInfo.CurrentCulture)}%";

    /// <summary>Web star-card label: "Gold Stars", "5 Stars" … "1 Star".</summary>
    /// <param name="stars">1–6.</param>
    /// <returns>Label.</returns>
    public static string StarsLabel(int stars) => stars switch
    {
        6 => "Gold Stars",
        1 => "1 Star",
        _ => $"{stars.ToString(CultureInfo.CurrentCulture)} Stars",
    };
}
#endregion
