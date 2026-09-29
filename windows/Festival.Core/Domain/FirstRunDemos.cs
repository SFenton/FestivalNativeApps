namespace Festival.Core.Domain;

#region Demo kinds
/// <summary>The live mini-demo a first-run slide shows (web per-slide <c>render()</c>, Apple <c>FirstRunDemoContent</c>).</summary>
public enum FirstRunDemoKind
{
    /// <summary>Song rows (art, title, artist · year).</summary>
    SongRows,
    /// <summary>Song rows whose order flips between ascending and descending, with a sort label.</summary>
    Sort,
    /// <summary>Song rows narrowed by a rotating instrument/difficulty filter chip.</summary>
    Filter,
    /// <summary>A section letter strip whose highlight moves, beside song rows.</summary>
    Navigation,
    /// <summary>Song rows with instrument status chips.</summary>
    Chips,
    /// <summary>Song rows with rotating metadata pills (score, accuracy, stars, percentile).</summary>
    Metadata,
    /// <summary>Song rows, one pulsing green (in the Shop).</summary>
    ShopPulse,
    /// <summary>Song rows, one pulsing gold (new in the Shop).</summary>
    NewPulse,
    /// <summary>Song rows, one pulsing red with a Leaving Tomorrow pill.</summary>
    LeavingPulse,
    /// <summary>Score history bars whose selection moves.</summary>
    Chart,
    /// <summary>Leaderboard rows (rank, player, score, accuracy).</summary>
    Leaderboard,
    /// <summary>Leaderboard rows with the selected player's rank highlighted below.</summary>
    YourRank,
    /// <summary>A Song Detail action button (Item Shop / Paths) in its status colour.</summary>
    ActionButton,
    /// <summary>Statistic tiles with rotating values.</summary>
    Tiles,
    /// <summary>Head-to-head rival rows.</summary>
    Rivals,
    /// <summary>Item Shop album-art tiles.</summary>
    ShopTiles,
}

/// <summary>One sample row of a demo (web demo pools: fictional players, real catalogue songs).</summary>
/// <param name="Title">Primary text.</param>
/// <param name="Detail">Secondary text.</param>
/// <param name="Value">Trailing value (score, accuracy, rank…), or empty.</param>
public sealed record FirstRunDemoRow(string Title, string Detail, string Value = "");
#endregion

#region Catalogue
/// <summary>Slide → demo mapping and the shared sample data and rotation timing.</summary>
public static class FirstRunDemos
{
    /// <summary>One row swaps (or the demo's state advances) this often, the PWA's measured 6 s loop.</summary>
    public static readonly TimeSpan Cycle = TimeSpan.FromSeconds(6);

    /// <summary>Fade out/in of a swapping row (web <c>FADE_DURATION</c>).</summary>
    public static readonly TimeSpan Fade = TimeSpan.FromMilliseconds(400);

    /// <summary>Rows a demo shows.</summary>
    public const int RowCount = 3;

    private static readonly Dictionary<string, FirstRunDemoKind> Kinds = new(StringComparer.Ordinal)
    {
        ["songs-song-list"] = FirstRunDemoKind.SongRows,
        ["songs-sort"] = FirstRunDemoKind.Sort,
        ["songs-navigation"] = FirstRunDemoKind.Navigation,
        ["songs-filter"] = FirstRunDemoKind.Filter,
        ["songs-icons"] = FirstRunDemoKind.Chips,
        ["songs-metadata"] = FirstRunDemoKind.Metadata,
        ["songs-shop-highlight"] = FirstRunDemoKind.ShopPulse,
        ["songs-new-in-shop"] = FirstRunDemoKind.NewPulse,
        ["songs-leaving-tomorrow"] = FirstRunDemoKind.LeavingPulse,
        ["songinfo-chart"] = FirstRunDemoKind.Chart,
        ["songinfo-bar-select"] = FirstRunDemoKind.Chart,
        ["songinfo-view-all"] = FirstRunDemoKind.Leaderboard,
        ["songinfo-top-scores"] = FirstRunDemoKind.Leaderboard,
        ["songinfo-paths"] = FirstRunDemoKind.ActionButton,
        ["songinfo-shop-button"] = FirstRunDemoKind.ActionButton,
        ["songinfo-new-in-shop"] = FirstRunDemoKind.ActionButton,
        ["songinfo-leaving-tomorrow"] = FirstRunDemoKind.ActionButton,
        ["playerhistory-score-list"] = FirstRunDemoKind.Leaderboard,
        ["playerhistory-sort"] = FirstRunDemoKind.Sort,
        ["statistics-select-profile"] = FirstRunDemoKind.Leaderboard,
        ["statistics-drill-down"] = FirstRunDemoKind.Tiles,
        ["statistics-overview"] = FirstRunDemoKind.Tiles,
        ["statistics-instrument-breakdown"] = FirstRunDemoKind.Chips,
        ["statistics-percentiles"] = FirstRunDemoKind.Chart,
        ["statistics-top-songs"] = FirstRunDemoKind.Metadata,
        ["suggestions-category-card"] = FirstRunDemoKind.SongRows,
        ["suggestions-global-filter"] = FirstRunDemoKind.Filter,
        ["suggestions-instrument-filter"] = FirstRunDemoKind.Filter,
        ["suggestions-infinite-scroll"] = FirstRunDemoKind.SongRows,
        ["leaderboards-overview"] = FirstRunDemoKind.Leaderboard,
        ["leaderboards-experimental-metrics"] = FirstRunDemoKind.Tiles,
        ["leaderboards-your-rank"] = FirstRunDemoKind.YourRank,
        ["compete-hub"] = FirstRunDemoKind.Rivals,
        ["compete-leaderboards"] = FirstRunDemoKind.Leaderboard,
        ["compete-rivals"] = FirstRunDemoKind.Rivals,
        ["rivals-overview"] = FirstRunDemoKind.Rivals,
        ["rivals-instruments"] = FirstRunDemoKind.Chips,
        ["rivals-detail"] = FirstRunDemoKind.Rivals,
        ["shop-overview"] = FirstRunDemoKind.ShopTiles,
        ["shop-highlighting"] = FirstRunDemoKind.ShopPulse,
        ["shop-new-items"] = FirstRunDemoKind.NewPulse,
        ["shop-leaving-tomorrow"] = FirstRunDemoKind.LeavingPulse,
    };

    /// <summary>Demo for a slide.</summary>
    /// <param name="slideId">Catalogue slide ID.</param>
    /// <returns>Kind, or <see langword="null"/> for an unknown ID (the static illustration stands in).</returns>
    public static FirstRunDemoKind? KindFor(string? slideId) =>
        slideId is not null && Kinds.TryGetValue(slideId, out var kind) ? kind : null;

    /// <summary>Fallback songs when the catalogue isn't loaded (web fallback pool style: Epic Games tracks, no art).</summary>
    public static IReadOnlyList<FirstRunDemoRow> FallbackSongs { get; } =
    [
        new("Festival Anthem", "Epic Games · 2023"),
        new("Main Stage", "Epic Games · 2024"),
        new("Encore", "Epic Games · 2023"),
        new("Soundcheck", "Epic Games · 2024"),
        new("Headliner", "Epic Games · 2025"),
    ];

    /// <summary>Fictional leaderboard rows (the web's demo players).</summary>
    public static IReadOnlyList<FirstRunDemoRow> Players { get; } =
    [
        new("#1 · StageDiver", "100% · FC", "412,880"),
        new("#2 · NeonRiff", "99.8% · FC", "409,215"),
        new("#3 · BassDropper", "99.4%", "402,760"),
        new("#4 · Encore", "98.9%", "398,104"),
        new("#5 · LightShow", "98.1%", "391,552"),
    ];

    /// <summary>Metadata pills cycled by the Metadata demo.</summary>
    public static IReadOnlyList<string> MetadataPills { get; } = ["142,800", "96%", "Top 8%", "Season 11", "FC"];

    /// <summary>Statistic tiles (label, value) cycled by the Tiles demo.</summary>
    public static IReadOnlyList<FirstRunDemoRow> Tiles { get; } =
    [
        new("Songs Played", "", "612"),
        new("Full Combos", "", "248"),
        new("Avg Accuracy", "", "97.4%"),
        new("Top 1%", "", "31"),
        new("Gold Stars", "", "189"),
        new("Best Rank", "", "#42"),
    ];

    /// <summary>Filter chips cycled by the Filter demo.</summary>
    public static IReadOnlyList<string> FilterChips { get; } = ["Lead · Expert", "Bass · Hard", "Drums · Expert", "Vocals · Medium"];

    /// <summary>Bar heights (0–1) cycled by the Chart demo.</summary>
    public static IReadOnlyList<double> Bars { get; } = [0.42, 0.55, 0.61, 0.58, 0.74, 0.83, 0.9];

    /// <summary>Picks demo songs from the catalogue (web: artist contains "Epic Games" and has art), else the fallback pool.</summary>
    /// <param name="catalog">Loaded catalogue songs, or <see langword="null"/>.</param>
    /// <returns>Rows plus their art references (empty art for the fallback pool).</returns>
    public static IReadOnlyList<(FirstRunDemoRow Row, string? Art)> SongPool(IEnumerable<Song>? catalog)
    {
        var epic = (catalog ?? [])
            .Where(s => s.Artist.Contains("Epic Games", StringComparison.Ordinal) && !string.IsNullOrEmpty(s.AlbumArt))
            .OrderBy(s => s.SongId, StringComparer.Ordinal)
            .Take(12)
            .Select(s => (new FirstRunDemoRow(s.Title, s.Year is { } y ? $"{s.Artist} · {y}" : s.Artist), (string?)s.AlbumArt))
            .ToList();
        return epic.Count >= RowCount ? epic : [.. FallbackSongs.Select(r => (r, (string?)null))];
    }

    /// <summary>
    /// The row that swaps on a step and the pool index it receives: rows swap in turn (0, 1, 2, 0 …) and the pool is
    /// walked in order past the rows first shown, like the web's deterministic rotation.
    /// </summary>
    /// <param name="step">Swap number, 0-based.</param>
    /// <param name="rows">Visible rows.</param>
    /// <param name="poolSize">Pool size.</param>
    /// <returns>Row index and pool index.</returns>
    public static (int Row, int PoolIndex) Swap(int step, int rows, int poolSize)
    {
        if (rows <= 0 || poolSize <= 0) return (0, 0);
        return (step % rows, (rows + step) % poolSize);
    }
}
#endregion
