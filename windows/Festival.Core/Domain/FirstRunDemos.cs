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

/// <summary>One song a song demo shows: a real catalogue song, or a placeholder drawn redacted.</summary>
/// <param name="SongId">Catalogue song ID, or <see langword="null"/> for a placeholder.</param>
/// <param name="Row">Title and "artist · year" (empty for a placeholder).</param>
/// <param name="Art">Album-art reference, or <see langword="null"/>.</param>
public sealed record FirstRunDemoSong(string? SongId, FirstRunDemoRow Row, string? Art)
{
    /// <summary>Whether this stands in for a song while the catalogue loads or is unavailable.</summary>
    public bool IsPlaceholder => SongId is null;

    /// <summary>A placeholder: no title, artist or art (never an invented song).</summary>
    public static FirstRunDemoSong Placeholder { get; } = new(null, new FirstRunDemoRow("", ""), null);
}
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

    /// <summary>Artist marker the web uses to pick neutral, first-party demo songs.</summary>
    public const string PreferredArtistMarker = "Epic Games";

    /// <summary>Most songs a demo rotates through.</summary>
    public const int PoolSize = 12;

    /// <summary>Whether a demo shows Item Shop songs, so it prefers the current Shop (web <c>useItemShopDemoSongs</c>).</summary>
    /// <param name="kind">Demo kind.</param>
    /// <returns><see langword="true"/> for the Shop pulse rows and Shop tiles.</returns>
    public static bool UsesShopSongs(FirstRunDemoKind kind) =>
        kind is FirstRunDemoKind.ShopPulse or FirstRunDemoKind.NewPulse or FirstRunDemoKind.LeavingPulse or FirstRunDemoKind.ShopTiles;

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

    /// <summary>
    /// Picks up to <paramref name="count"/> distinct catalogue songs with art (web <c>useDemoSongs</c> /
    /// <c>useItemShopDemoSongs</c>, Apple <c>FirstRunDemoSongs.pick</c>): preferred IDs in order, then artists containing
    /// <see cref="PreferredArtistMarker"/>, then any other song. Catalogue order replaces the web's shuffle so captures
    /// and tests are deterministic.
    /// </summary>
    /// <param name="catalog">Loaded catalogue songs, or <see langword="null"/>.</param>
    /// <param name="count">Maximum songs; non-positive returns none.</param>
    /// <param name="preferring">Song IDs to show first (current Shop songs), or <see langword="null"/>.</param>
    /// <returns>Songs, each with art.</returns>
    public static IReadOnlyList<Song> Pick(IEnumerable<Song>? catalog, int count, IEnumerable<string>? preferring = null)
    {
        if (count <= 0) return [];
        var withArt = (catalog ?? []).Where(s => !string.IsNullOrEmpty(s.AlbumArt)).ToList();
        var byId = new Dictionary<string, Song>(StringComparer.Ordinal);
        foreach (var song in withArt) byId.TryAdd(song.SongId, song);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<Song>();
        void Add(Song song)
        {
            if (result.Count < count && seen.Add(song.SongId)) result.Add(song);
        }
        foreach (var id in preferring ?? [])
            if (byId.TryGetValue(id, out var song)) Add(song);
        foreach (var song in withArt.Where(s => s.Artist.Contains(PreferredArtistMarker, StringComparison.Ordinal))) Add(song);
        foreach (var song in withArt) Add(song);
        return result;
    }

    /// <summary>
    /// The songs a demo rotates through: real catalogue songs, padded with <see cref="FirstRunDemoSong.Placeholder"/>s to
    /// <see cref="RowCount"/> (all placeholders while the catalogue loads or is unavailable). Never invents songs.
    /// </summary>
    /// <param name="catalog">Loaded catalogue songs, or <see langword="null"/>.</param>
    /// <param name="preferring">Song IDs to show first, or <see langword="null"/>.</param>
    /// <returns>At least <see cref="RowCount"/> entries.</returns>
    public static IReadOnlyList<FirstRunDemoSong> SongPool(IEnumerable<Song>? catalog, IEnumerable<string>? preferring = null)
    {
        var pool = Pick(catalog, PoolSize, preferring)
            .Select(s => new FirstRunDemoSong(s.SongId, new FirstRunDemoRow(s.Title, s.Year is { } y ? $"{s.Artist} · {y}" : s.Artist), s.AlbumArt))
            .ToList();
        while (pool.Count < RowCount) pool.Add(FirstRunDemoSong.Placeholder);
        return pool;
    }

    /// <summary>
    /// Shop song IDs Shop demos may prefer: the already-loaded feed's order, only when it shares the catalogue's observed
    /// publication and the Shop isn't hidden. Demos never fetch the Shop.
    /// </summary>
    /// <param name="shop">Loaded Shop feed, or <see langword="null"/>.</param>
    /// <param name="offersForCatalog">Session offers for the catalogue's publication (<see langword="null"/> on mismatch).</param>
    /// <param name="hideShop">Settings hide the Shop.</param>
    /// <returns>IDs, or empty.</returns>
    public static IReadOnlyList<string> ShopPreference(ShopResponse? shop, IReadOnlyDictionary<string, ShopSong>? offersForCatalog, bool hideShop) =>
        hideShop || shop is null || offersForCatalog is null ? [] : [.. shop.Songs.Select(s => s.SongId)];

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
