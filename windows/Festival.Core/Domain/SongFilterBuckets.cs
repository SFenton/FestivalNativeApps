using System.Globalization;

namespace Festival.Core.Domain;

#region Bucket kinds
/// <summary>
/// The web Songs Filter's "Selected Instrument Filters" sections (<c>FilterModal</c> <c>SeasonToggles</c>,
/// <c>PercentileToggles</c>, <c>StarsToggles</c>, <c>DifficultyToggles</c>): each is a set of on/off buckets that apply
/// only while one instrument is selected. Season, Percentile and Stars read the selected player's score on that chart;
/// Song Intensity reads public chart data.
/// </summary>
public enum SongBucketKind
{
    /// <summary>Season the score was set (web <c>seasonFilter</c>; 0 = no score).</summary>
    Season,
    /// <summary>Leaderboard placement band (web <c>percentileFilter</c>; 0 = no score or no rank).</summary>
    Percentile,
    /// <summary>Stars on the score (web <c>starsFilter</c>; 6 = gold, 0 = no score).</summary>
    Stars,
    /// <summary>Chart intensity 1–7 (web <c>difficultyFilter</c>; 0 = no chart value).</summary>
    Intensity,
}

/// <summary>Keys, labels and bucketing for <see cref="SongBucketKind"/>.</summary>
public static class SongBuckets
{
    /// <summary>Kinds in web section order.</summary>
    public static IReadOnlyList<SongBucketKind> All { get; } = Enum.GetValues<SongBucketKind>();

    /// <summary>Web <c>PERCENTILE_THRESHOLDS</c>.</summary>
    public static IReadOnlyList<int> PercentileThresholds => PlayerStatistics.PercentileThresholds;

    /// <summary>Percentile keys in menu order: No Score, then Top 1% … Top 100%.</summary>
    public static IReadOnlyList<int> PercentileKeys { get; } = [0, .. PlayerStatistics.PercentileThresholds];

    /// <summary>Star keys in menu order: gold, 5 … 1, No Score.</summary>
    public static IReadOnlyList<int> StarKeys { get; } = [6, 5, 4, 3, 2, 1, 0];

    /// <summary>Intensity keys in menu order: 1 … 7 bars, then No Score.</summary>
    public static IReadOnlyList<int> IntensityKeys { get; } = [1, 2, 3, 4, 5, 6, 7, 0];

    /// <summary>Highest accepted season key (bounds saved data).</summary>
    public const int MaxSeason = 999;

    /// <summary>Whether a bucket kind reads the selected player's scores.</summary>
    /// <param name="kind">Kind.</param>
    /// <returns><see langword="true"/> for Season, Percentile and Stars.</returns>
    public static bool IsPlayerScoped(this SongBucketKind kind) => kind != SongBucketKind.Intensity;

    /// <summary>Section title (web <c>filter.*Title</c>).</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Title Case title.</returns>
    public static string Title(this SongBucketKind kind) => kind switch
    {
        SongBucketKind.Season => "Season",
        SongBucketKind.Percentile => "Percentile",
        SongBucketKind.Stars => "Stars",
        _ => "Song Intensity",
    };

    /// <summary>Section hint (web <c>filter.*Hint</c>).</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Sentence.</returns>
    public static string Hint(this SongBucketKind kind) => kind switch
    {
        SongBucketKind.Season => "Filter by the season in which the score was achieved.",
        SongBucketKind.Percentile => "Show or hide songs based on their leaderboard ranking bracket.",
        SongBucketKind.Stars => "Filter songs by the number of stars on your high score.",
        _ => "Filter by the song's difficulty rating for the selected instrument.",
    };

    /// <summary>Stable AutomationId segment.</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Lowercase ID.</returns>
    public static string Id(this SongBucketKind kind) => kind.ToString().ToLowerInvariant();

    /// <summary>Keys a section offers, in menu order.</summary>
    /// <param name="kind">Kind.</param>
    /// <param name="seasons">Seasons in the player's scores (Season only).</param>
    /// <returns>Keys.</returns>
    public static IReadOnlyList<int> Keys(this SongBucketKind kind, IEnumerable<int>? seasons = null) => kind switch
    {
        SongBucketKind.Season => SeasonKeys(seasons ?? []),
        SongBucketKind.Percentile => PercentileKeys,
        SongBucketKind.Stars => StarKeys,
        _ => IntensityKeys,
    };

    /// <summary>Whether a saved key is one this kind can ever offer.</summary>
    /// <param name="kind">Kind.</param>
    /// <param name="key">Key.</param>
    /// <returns><see langword="true"/> when known.</returns>
    public static bool IsKnownKey(this SongBucketKind kind, int key) => kind switch
    {
        SongBucketKind.Season => key is >= 0 and <= MaxSeason,
        SongBucketKind.Percentile => PercentileKeys.Contains(key),
        SongBucketKind.Stars => StarKeys.Contains(key),
        _ => IntensityKeys.Contains(key),
    };

    /// <summary>Season keys (web <c>SeasonToggles</c>): the player's seasons ascending, then 0.</summary>
    /// <param name="seasons">Seasons in the player's scores.</param>
    /// <returns>Keys.</returns>
    public static IReadOnlyList<int> SeasonKeys(IEnumerable<int> seasons) =>
        [.. seasons.Where(s => s is >= 1 and <= MaxSeason).Distinct().Order(), 0];

    /// <summary>Row label; star and intensity rows also draw stars or bars beside it.</summary>
    /// <param name="kind">Kind.</param>
    /// <param name="key">Key.</param>
    /// <returns>"No Score", "Season 5", "Top 5%", "Gold Stars", "3 Stars" or "Intensity 4 of 7".</returns>
    public static string Label(this SongBucketKind kind, int key)
    {
        if (key == 0) return "No Score";
        var n = key.ToString(CultureInfo.CurrentCulture);
        return kind switch
        {
            SongBucketKind.Season => $"Season {n}",
            SongBucketKind.Percentile => $"Top {n}%",
            SongBucketKind.Stars => SongScoreBandFilter.StarsLabel(key),
            _ => $"Intensity {n} of 7",
        };
    }

    /// <summary>A score's percentile key: the first threshold at or above <c>rank / totalEntries × 100</c>.</summary>
    /// <param name="detail">The selected player's score on the chart, or <see langword="null"/>.</param>
    /// <returns>Key (0 = no score or no placement).</returns>
    public static int PercentileOf(SongScoreDetail? detail) =>
        detail is { Score: > 0 } ? SongScoreBandFilter.Band(detail.Rank, detail.TotalEntries) ?? 0 : 0;

    /// <summary>A score's season key (web <c>score?.season ?? 0</c>).</summary>
    /// <param name="detail">Score, or <see langword="null"/>.</param>
    /// <returns>Key (0 = no score).</returns>
    public static int SeasonOf(SongScoreDetail? detail) =>
        detail is { Score: > 0, Season: { } season } ? Math.Clamp(season, 0, MaxSeason) : 0;

    /// <summary>A score's star key (web <c>score?.stars ?? 0</c>).</summary>
    /// <param name="detail">Score, or <see langword="null"/>.</param>
    /// <returns>Key (0 = no score).</returns>
    public static int StarsOf(SongScoreDetail? detail) =>
        detail is { Score: > 0, Stars: { } stars } ? Math.Clamp(stars, 0, 6) : 0;

    /// <summary>A chart's intensity key (web <c>Math.trunc(raw) + 1</c> clamped to 1–7).</summary>
    /// <param name="raw">Raw 0–6 chart difficulty, or <see langword="null"/>.</param>
    /// <returns>Key (0 = no chart value).</returns>
    public static int IntensityOf(double? raw) => raw is { } value ? DifficultyScale.BarsForRaw(value) : 0;

    /// <summary>Validates saved hidden keys: bounded, known and duplicate-free.</summary>
    /// <param name="kind">Kind.</param>
    /// <param name="keys">Saved keys (may be <see langword="null"/> in corrupt JSON).</param>
    /// <returns><see langword="true"/> when safe to apply.</returns>
    public static bool AreValid(SongBucketKind kind, IReadOnlyList<int>? keys) =>
        keys is not null && keys.Count <= 64 && keys.All(k => kind.IsKnownKey(k)) && keys.Distinct().Count() == keys.Count;

    /// <summary>Normalizes a key set for storage: distinct and ascending, so equal filters serialize equally.</summary>
    /// <param name="keys">Keys.</param>
    /// <returns>Sorted distinct list.</returns>
    public static IReadOnlyList<int> Normalize(IEnumerable<int> keys) => [.. keys.Distinct().Order()];
}
#endregion
