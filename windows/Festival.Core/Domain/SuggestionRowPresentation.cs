using System.Globalization;

namespace Festival.Core.Domain;

#region Row layout
/// <summary>Right-side metadata a suggestion row shows, chosen by category key (web <c>getRowLayout</c>).</summary>
public enum SuggestionRowLayout
{
    /// <summary>One status chip per visible instrument.</summary>
    InstrumentChips,
    /// <summary>The row's instrument icon, plus stars for star-gain categories.</summary>
    SingleInstrument,
    /// <summary>"Top N%" pill plus the row's instrument icon.</summary>
    Percentile,
    /// <summary>Season the score was set ("S6").</summary>
    Season,
    /// <summary>Accuracy pill for a gold, not-yet-FC run.</summary>
    UnfcAccuracy,
    /// <summary>No right-side metadata.</summary>
    Hidden,
    /// <summary>Rival name, rank delta and instrument icon.</summary>
    Rival,
}

/// <summary>Visual tier of a percentile pill (web <c>PercentilePill</c>).</summary>
public enum PercentileTier
{
    /// <summary>Neutral pill.</summary>
    Default,
    /// <summary>Top 5% (gold outline).</summary>
    Top5,
    /// <summary>Top 1% (filled gold).</summary>
    Top1,
}

/// <summary>One instrument status chip (played / full combo) for the <see cref="SuggestionRowLayout.InstrumentChips"/> layout.</summary>
/// <param name="Instrument">Chart.</param>
/// <param name="HasScore">Whether the player has at least one star on it.</param>
/// <param name="IsFullCombo">Whether that score is a full combo.</param>
public sealed record SuggestionInstrumentChip(Instrument Instrument, bool HasScore, bool IsFullCombo);
#endregion

#region Row presentation
/// <summary>Display-ready values for one suggestion row; pure, so it is unit-tested instead of the XAML.</summary>
public sealed record SuggestionRowPresentation
{
    /// <summary>Which right-side metadata to show.</summary>
    public required SuggestionRowLayout Layout { get; init; }
    /// <summary>Song title.</summary>
    public required string Title { get; init; }
    /// <summary>"Artist · Year".</summary>
    public required string Subtitle { get; init; }
    /// <summary>Instrument icon to show, if any.</summary>
    public Instrument? Instrument { get; init; }
    /// <summary>Stars to draw (1–5; gold means six).</summary>
    public int StarCount { get; init; }
    /// <summary>Whether the drawn stars are gold.</summary>
    public bool GoldStars { get; init; }
    /// <summary>Accuracy pill text (e.g. "97%").</summary>
    public string? AccuracyText { get; init; }
    /// <summary>Expanded accuracy used for the pill tint.</summary>
    public double? AccuracyExpanded { get; init; }
    /// <summary>Season pill text (e.g. "S6").</summary>
    public string? SeasonText { get; init; }
    /// <summary>Percentile pill text (e.g. "Top 3%").</summary>
    public string? PercentileText { get; init; }
    /// <summary>Percentile pill tier.</summary>
    public PercentileTier PercentileTier { get; init; }
    /// <summary>Rival name, truncated to 12 characters.</summary>
    public string? RivalName { get; init; }
    /// <summary>Signed delta text ("+5" / "-3"), or null when zero.</summary>
    public string? RivalDeltaText { get; init; }
    /// <summary>Sign of the rank delta (positive: the player leads).</summary>
    public int RivalDeltaSign { get; init; }
    /// <summary>Instrument chips for <see cref="SuggestionRowLayout.InstrumentChips"/>.</summary>
    public IReadOnlyList<SuggestionInstrumentChip> Chips { get; init; } = [];
    /// <summary>Narrator name for the whole row.</summary>
    public required string AccessibleName { get; init; }

    /// <summary>Chooses the right-side layout for a category key (web <c>getRowLayout</c>, band keys omitted).</summary>
    /// <param name="categoryKey">Generator key.</param>
    /// <returns>Layout.</returns>
    public static SuggestionRowLayout LayoutFor(string categoryKey)
    {
        var k = categoryKey.ToLowerInvariant();
        bool Has(string prefix) => k.StartsWith(prefix, StringComparison.Ordinal);
        if (Has("song_rival_") || Has("lb_rival_")) return SuggestionRowLayout.Rival;
        if (Has("variety_pack") || Has("artist_sampler_") || Has("artist_unplayed_") || Has("unplayed_") ||
            (Has("samename_") && !Has("samename_nearfc_"))) return SuggestionRowLayout.Hidden;
        if (Has("unfc_")) return SuggestionRowLayout.UnfcAccuracy;
        if (Has("stale_")) return SuggestionRowLayout.Season;
        if (Has("almost_elite") || Has("pct_push") || Has("pct_improve") || Has("same_pct") || Has("improve_rankings"))
            return SuggestionRowLayout.Percentile;
        if (Has("near_fc") || Has("almost_six_star") || Has("more_stars") || Has("first_plays_mixed") || Has("star_gains") ||
            Has("samename_nearfc_") || Has("near_max_")) return SuggestionRowLayout.SingleInstrument;
        return SuggestionRowLayout.InstrumentChips;
    }

    /// <summary>Tier of a "Top N%" label.</summary>
    /// <param name="display">Label.</param>
    /// <returns>Tier (default for an unparsable label).</returns>
    public static PercentileTier TierFor(string? display)
    {
        if (display is null || !display.StartsWith("Top ", StringComparison.Ordinal) || !display.EndsWith('%') ||
            !double.TryParse(display[4..^1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var pct))
            return PercentileTier.Default;
        return pct <= 1 ? PercentileTier.Top1 : pct <= 5 ? PercentileTier.Top5 : PercentileTier.Default;
    }

    /// <summary>Builds the presentation for one row.</summary>
    /// <param name="category">Owning category.</param>
    /// <param name="item">Row.</param>
    /// <param name="scores">Selected player's score index (season pills, instrument chips).</param>
    /// <param name="chipInstruments">Instruments to show chips for (Settings-visible, in display order).</param>
    /// <returns>Presentation.</returns>
    public static SuggestionRowPresentation Create(SuggestionCategory category, SuggestionSongItem item,
        IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>>? scores, IReadOnlyList<Instrument> chipInstruments)
    {
        var layout = LayoutFor(category.Key);
        var song = item.Song;
        var songScores = scores is not null && scores.TryGetValue(song.SongId, out var s) ? s : null;
        var instrument = item.Instrument ?? category.Instrument;
        var subtitle = song.Year is { } year ? $"{song.Artist} · {year.ToString(CultureInfo.InvariantCulture)}" : song.Artist;
        var result = new SuggestionRowPresentation
        {
            Layout = layout, Title = song.Title, Subtitle = subtitle, AccessibleName = "",
        };
        var details = new List<string>();
        switch (layout)
        {
            case SuggestionRowLayout.Rival:
                var delta = item.RivalRankDelta ?? 0;
                var name = item.RivalName is { Length: > 12 } longName ? longName[..11] + "…" : item.RivalName;
                result = result with
                {
                    Instrument = item.Instrument, RivalName = name, RivalDeltaSign = Math.Sign(delta),
                    RivalDeltaText = delta == 0 ? null : delta > 0 ? $"+{delta}" : delta.ToString(CultureInfo.InvariantCulture),
                };
                if (item.RivalName is { } rival) details.Add($"rival {rival}");
                if (delta != 0) details.Add(delta > 0 ? $"ahead by {delta} ranks" : $"behind by {-delta} ranks");
                break;
            case SuggestionRowLayout.UnfcAccuracy when item.Percent is > 0:
                var clamped = Math.Clamp(Math.Floor(item.Percent.Value), 0, 99);
                result = result with { AccuracyExpanded = clamped * 10_000, AccuracyText = ScoreFormatting.Accuracy(clamped * 10_000) };
                details.Add($"{result.AccuracyText} accuracy");
                break;
            case SuggestionRowLayout.Season:
                var season = 0;
                if (songScores is not null)
                {
                    if (item.Instrument is { } rowInstrument)
                        season = songScores.TryGetValue(rowInstrument, out var chart) ? chart.Season ?? 0 : 0;
                    else
                        foreach (var chart2 in songScores.Values) season = Math.Max(season, chart2.Season ?? 0);
                }
                if (season > 0)
                {
                    result = result with { SeasonText = $"S{season.ToString(CultureInfo.InvariantCulture)}" };
                    details.Add($"last played season {season}");
                }
                break;
            case SuggestionRowLayout.Percentile:
                result = result with { Instrument = item.Instrument, PercentileText = item.PercentileDisplay, PercentileTier = TierFor(item.PercentileDisplay) };
                if (item.PercentileDisplay is { } pct) details.Add(pct);
                break;
            case SuggestionRowLayout.SingleInstrument:
                var stars = item.Stars ?? 0;
                var showStars = category.Key.StartsWith("star_gains", StringComparison.Ordinal) && stars > 0;
                result = result with { Instrument = item.Instrument, StarCount = showStars ? (stars >= 6 ? 5 : stars) : 0, GoldStars = showStars && stars >= 6 };
                if (showStars) details.Add(stars >= 6 ? "gold stars" : stars == 1 ? "1 star" : $"{stars} stars");
                break;
            case SuggestionRowLayout.InstrumentChips:
                result = result with
                {
                    Chips = chipInstruments.Select(i =>
                    {
                        var chart = songScores is not null && songScores.TryGetValue(i, out var c) ? c : null;
                        return new SuggestionInstrumentChip(i, (chart?.Stars ?? 0) > 0, chart?.IsFullCombo == true);
                    }).ToList(),
                };
                break;
        }
        if (result.Instrument is { } shown) details.Insert(0, shown.Label());
        var accessible = string.Join(", ", new[] { song.Title, subtitle }.Concat(details));
        return result with { AccessibleName = accessible };
    }

    /// <summary>Song Detail destination for a row: the row's chart when known, else the category's.</summary>
    /// <param name="category">Owning category.</param>
    /// <param name="item">Row.</param>
    /// <returns>Route.</returns>
    public static AppRoute RouteFor(SuggestionCategory category, SuggestionSongItem item) =>
        new AppRoute.SongDetail(item.Song.SongId, item.Instrument ?? category.Instrument);
}
#endregion
