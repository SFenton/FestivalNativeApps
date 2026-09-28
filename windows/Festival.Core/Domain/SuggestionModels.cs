namespace Festival.Core.Domain;

#region Category type
/// <summary>
/// Broad family a generated <see cref="SuggestionCategory"/> belongs to, used only by the
/// Suggestions filter (web <c>SuggestionTypeId</c>). Band-driven families and the web's dead
/// <c>lb_rival_*</c> type are not represented (see <c>.agents/pages/suggestions/windows.md</c>).
/// </summary>
public enum SuggestionCategoryType
{
    /// <summary>Near full combo.</summary>
    NearFC,
    /// <summary>Star progress.</summary>
    StarProgress,
    /// <summary>Unplayed charts.</summary>
    Unplayed,
    /// <summary>Variety pack.</summary>
    VarietyPack,
    /// <summary>Single-artist selection.</summary>
    ArtistEssentials,
    /// <summary>Unplayed songs by one artist.</summary>
    ArtistDiscover,
    /// <summary>Different tracks sharing one title.</summary>
    SameName,
    /// <summary>Top 5% close to top 1%.</summary>
    AlmostElite,
    /// <summary>Close to the next percentile bracket.</summary>
    PercentilePush,
    /// <summary>Not played for several seasons.</summary>
    Stale,
    /// <summary>Room for percentile improvement.</summary>
    PctImprove,
    /// <summary>Close to the CHOpt theoretical max score.</summary>
    NearMax,
    /// <summary>Per-song rival suggestions.</summary>
    SongRivals,
}

/// <summary>Persisted keys, labels and descriptions for <see cref="SuggestionCategoryType"/>.</summary>
public static class SuggestionCategoryTypeInfo
{
    /// <summary>Every type in filter display order.</summary>
    public static IReadOnlyList<SuggestionCategoryType> All { get; } = Enum.GetValues<SuggestionCategoryType>();

    /// <summary>Stable persisted key, identical to the Apple raw value (e.g. <c>nearFC</c>).</summary>
    /// <param name="type">Category family.</param>
    /// <returns>Camel-case key.</returns>
    public static string Key(this SuggestionCategoryType type) => type switch
    {
        SuggestionCategoryType.NearFC => "nearFC",
        SuggestionCategoryType.StarProgress => "starProgress",
        SuggestionCategoryType.Unplayed => "unplayed",
        SuggestionCategoryType.VarietyPack => "varietyPack",
        SuggestionCategoryType.ArtistEssentials => "artistEssentials",
        SuggestionCategoryType.ArtistDiscover => "artistDiscover",
        SuggestionCategoryType.SameName => "sameName",
        SuggestionCategoryType.AlmostElite => "almostElite",
        SuggestionCategoryType.PercentilePush => "percentilePush",
        SuggestionCategoryType.Stale => "stale",
        SuggestionCategoryType.PctImprove => "pctImprove",
        SuggestionCategoryType.NearMax => "nearMax",
        _ => "songRivals",
    };

    /// <summary>Title Case filter label.</summary>
    /// <param name="type">Category family.</param>
    /// <returns>Label such as <c>Near FC</c>.</returns>
    public static string Label(this SuggestionCategoryType type) => type switch
    {
        SuggestionCategoryType.NearFC => "Near FC",
        SuggestionCategoryType.StarProgress => "Star Progress",
        SuggestionCategoryType.Unplayed => "Unplayed",
        SuggestionCategoryType.VarietyPack => "Variety Pack",
        SuggestionCategoryType.ArtistEssentials => "Artist Essentials",
        SuggestionCategoryType.ArtistDiscover => "Artist Discover",
        SuggestionCategoryType.SameName => "Same Name",
        SuggestionCategoryType.AlmostElite => "Almost Elite",
        SuggestionCategoryType.PercentilePush => "Percentile Push",
        SuggestionCategoryType.Stale => "Stale Songs",
        SuggestionCategoryType.PctImprove => "Percentile Improve",
        SuggestionCategoryType.NearMax => "Near Max Score",
        _ => "Song Rivals",
    };

    /// <summary>One-line explanation shown under the filter row's label.</summary>
    /// <param name="type">Category family.</param>
    /// <returns>Sentence.</returns>
    public static string FilterDescription(this SuggestionCategoryType type) => type switch
    {
        SuggestionCategoryType.NearFC => "Songs you're close to full-comboing.",
        SuggestionCategoryType.StarProgress => "Push five-star runs to gold, or gain more stars.",
        SuggestionCategoryType.Unplayed => "Songs you haven't played yet.",
        SuggestionCategoryType.VarietyPack => "A mix of songs from different artists.",
        SuggestionCategoryType.ArtistEssentials => "A selection of songs by a single artist.",
        SuggestionCategoryType.ArtistDiscover => "Unplayed songs from a single artist.",
        SuggestionCategoryType.SameName => "Different tracks that share the same title.",
        SuggestionCategoryType.AlmostElite => "Top 5% — one good run could crack the top 1%.",
        SuggestionCategoryType.PercentilePush => "Close to the next percentile bracket.",
        SuggestionCategoryType.Stale => "Songs you haven't played in a while.",
        SuggestionCategoryType.PctImprove => "Songs with room for percentile improvement.",
        SuggestionCategoryType.NearMax => "Songs close to the CHOpt theoretical max score.",
        _ => "Suggestions based on per-song rivals.",
    };
}
#endregion

#region Score input
/// <summary>
/// The score fields the generator reads for one (song, chart), decoupled from the wire model so
/// fixtures and parity tests can build them directly.
/// </summary>
/// <param name="Score">Current score.</param>
/// <param name="Stars">Star count (0–6; 6 is gold).</param>
/// <param name="Accuracy">Expanded accuracy: ten-thousandths of a percent (0–1,000,000).</param>
/// <param name="IsFullCombo">Explicit full-combo flag.</param>
/// <param name="Season">Season the score was set in.</param>
/// <param name="Rank">One-based leaderboard rank.</param>
/// <param name="TotalEntries">Chart population.</param>
public sealed record SuggestionScore(
    long Score,
    int? Stars = null,
    double? Accuracy = null,
    bool? IsFullCombo = null,
    int? Season = null,
    int? Rank = null,
    int? TotalEntries = null)
{
    /// <summary>Projects a validated compact-wire score (accuracy already expanded).</summary>
    /// <param name="score">Player score row.</param>
    /// <returns>Generator input.</returns>
    public static SuggestionScore From(PlayerScore score) =>
        new(score.Score, score.Stars, score.Accuracy, score.IsFullCombo, score.Season, score.Rank, score.TotalEntries);

    /// <summary>Projects a session score index (songId → chart → score).</summary>
    /// <param name="index">Selected player's score index.</param>
    /// <returns>Generator score index.</returns>
    public static IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> Index(
        IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>> index) =>
        index.ToDictionary(p => p.Key,
            p => (IReadOnlyDictionary<Instrument, SuggestionScore>)p.Value.ToDictionary(s => s.Key, s => From(s.Value)),
            StringComparer.Ordinal);
}
#endregion

#region Suggested song and category
/// <summary>One song shown inside a <see cref="SuggestionCategory"/> (web <c>SuggestionSongItem</c>).</summary>
public sealed record SuggestionSongItem
{
    /// <summary>Catalogue row being suggested.</summary>
    public required Song Song { get; init; }
    /// <summary>Chart the row is about when the category mixes instruments; otherwise <see langword="null"/>.</summary>
    public Instrument? Instrument { get; init; }
    /// <summary>Current star count for that chart.</summary>
    public int? Stars { get; init; }
    /// <summary>Accuracy as a 0–100 percent.</summary>
    public double? Percent { get; init; }
    /// <summary>Whether the current score is a full combo.</summary>
    public bool? FullCombo { get; init; }
    /// <summary>Precomputed "Top N%" label.</summary>
    public string? PercentileDisplay { get; init; }
    /// <summary>Closest rival's display name on this song/chart.</summary>
    public string? RivalName { get; init; }
    /// <summary>That rival's account ID.</summary>
    public string? RivalAccountId { get; init; }
    /// <summary>Signed rank delta vs. that rival; negative means the rival leads.</summary>
    public int? RivalRankDelta { get; init; }

    /// <summary>Stable row identity: <c>songId</c> or <c>songId|Solo_X</c>.</summary>
    public string Id => Instrument is { } i ? $"{Song.SongId}|{i.ServiceId()}" : Song.SongId;
}

/// <summary>One titled group of suggested songs.</summary>
/// <param name="Key">Generator key, unique within a mix.</param>
/// <param name="Title">Card title.</param>
/// <param name="Description">Card subtitle.</param>
/// <param name="Type">Filter family.</param>
/// <param name="Instrument">The single chart this category is about, or <see langword="null"/> when mixed.</param>
/// <param name="Songs">Rows.</param>
public sealed record SuggestionCategory(
    string Key,
    string Title,
    string Description,
    SuggestionCategoryType Type,
    Instrument? Instrument,
    IReadOnlyList<SuggestionSongItem> Songs);
#endregion

#region Season fallback
/// <summary>Season used by stale categories when the catalogue hasn't reported one.</summary>
public static class SuggestionSeason
{
    /// <summary>Returns the catalogue season, falling back to the highest season in the player's scores.</summary>
    /// <param name="currentSeason">Catalogue-reported season.</param>
    /// <param name="scores">Score index (songId → chart → score).</param>
    /// <returns>A season ≥ 0; 0 disables season-gated categories.</returns>
    public static int Effective(int? currentSeason, IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> scores)
    {
        if (currentSeason is > 0) return currentSeason.Value;
        var highest = 0;
        foreach (var perInstrument in scores.Values)
            foreach (var score in perInstrument.Values)
                if ((score.Season ?? 0) > highest) highest = score.Season ?? 0;
        return highest;
    }
}
#endregion
