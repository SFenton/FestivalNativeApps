using System.Globalization;

namespace Festival.Core.Domain;

#region Demo kinds
/// <summary>The live mini-demo a first-run slide shows (web per-slide <c>render()</c>, Apple <c>FirstRunDemoContent</c>).</summary>
public enum FirstRunDemoKind
{
    /// <summary>Song rows (art, title, artist · year).</summary>
    SongRows,
    /// <summary>Song rows whose order flips between ascending and descending, with a sort label.</summary>
    Sort,
    /// <summary>Song rows narrowed by an instrument/difficulty filter chip.</summary>
    Filter,
    /// <summary>A section letter strip beside song rows.</summary>
    Navigation,
    /// <summary>Song rows with instrument status chips.</summary>
    Chips,
    /// <summary>Song rows with metadata pills.</summary>
    Metadata,
    /// <summary>Song rows with an in-Shop pulse.</summary>
    ShopPulse,
    /// <summary>Song rows with a new-in-Shop pulse.</summary>
    NewPulse,
    /// <summary>Song rows with a leaving-tomorrow pulse.</summary>
    LeavingPulse,
    /// <summary>Score history bars.</summary>
    Chart,
    /// <summary>Leaderboard rows.</summary>
    Leaderboard,
    /// <summary>Leaderboard rows with the selected player's rank highlighted below.</summary>
    YourRank,
    /// <summary>A Song Detail action button.</summary>
    ActionButton,
    /// <summary>Statistic tiles.</summary>
    Tiles,
    /// <summary>Head-to-head rival rows.</summary>
    Rivals,
    /// <summary>Item Shop album-art tiles.</summary>
    ShopTiles,
}

/// <summary>The twelve web demos that rotate data on an interval.</summary>
public enum FirstRunDemoRotationKind
{
    /// <summary><c>songs-song-list</c>.</summary>
    SongsSongList,
    /// <summary><c>songs-icons</c>.</summary>
    SongsIcons,
    /// <summary><c>songs-metadata</c>.</summary>
    SongsMetadata,
    /// <summary><c>statistics-top-songs</c>.</summary>
    StatisticsTopSongs,
    /// <summary><c>songinfo-bar-select</c>.</summary>
    SongInfoBarSelect,
    /// <summary><c>suggestions-category-card</c>.</summary>
    SuggestionsCategoryCard,
    /// <summary><c>leaderboards-experimental-metrics</c>.</summary>
    LeaderboardsExperimentalMetrics,
    /// <summary><c>compete-hub</c>.</summary>
    CompeteHub,
    /// <summary><c>compete-rivals</c>.</summary>
    CompeteRivals,
    /// <summary><c>rivals-overview</c>.</summary>
    RivalsOverview,
    /// <summary><c>rivals-instruments</c>.</summary>
    RivalsInstruments,
    /// <summary><c>rivals-detail</c>.</summary>
    RivalsDetail,
}

/// <summary>One sample row of a demo.</summary>
/// <param name="Title">Primary text.</param>
/// <param name="Detail">Secondary text.</param>
/// <param name="Value">Trailing value (score, accuracy, rank…), or empty.</param>
public sealed record FirstRunDemoRow(string Title, string Detail, string Value = "");

/// <summary>Pool item that can be rotated without showing duplicate visible IDs.</summary>
public interface IFirstRunDemoPoolItem
{
    /// <summary>Stable identity used to avoid duplicates.</summary>
    string Id { get; }
}

/// <summary>One song a song demo shows: a real catalogue song, or a placeholder drawn redacted.</summary>
/// <param name="SongId">Catalogue song ID, or <see langword="null"/> for a placeholder.</param>
/// <param name="Row">Title and "artist · year" (empty for a placeholder).</param>
/// <param name="Art">Album-art reference, or <see langword="null"/>.</param>
public sealed record FirstRunDemoSong(string? SongId, FirstRunDemoRow Row, string? Art) : IFirstRunDemoPoolItem
{
    /// <summary>Whether this stands in for a song while the catalogue loads or is unavailable.</summary>
    public bool IsPlaceholder => SongId is null;

    /// <summary>Rotation identity: the song ID, or empty for every placeholder (so placeholders never rotate).</summary>
    public string Id => SongId ?? "";

    /// <summary>A placeholder: no title, artist or art (never an invented song).</summary>
    public static FirstRunDemoSong Placeholder { get; } = new(null, new FirstRunDemoRow("", ""), null);
}
#endregion

#region Timing
/// <summary>Web first-run demo timing constants.</summary>
public static class FirstRunDemoTiming
{
    /// <summary>Data-swap interval (<c>DEMO_SWAP_INTERVAL_MS</c>).</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromSeconds(5);

    /// <summary>Fade-out duration before swapping content.</summary>
    public static readonly TimeSpan FadeOut = TimeSpan.FromMilliseconds(400);

    /// <summary>Fade-in duration after swapping content.</summary>
    public static readonly TimeSpan FadeIn = TimeSpan.FromMilliseconds(400);

    /// <summary>Entrance stagger between rows.</summary>
    public static readonly TimeSpan Stagger = TimeSpan.FromMilliseconds(125);

    /// <summary>Song Info bar-select interval.</summary>
    public static readonly TimeSpan BarSelect = TimeSpan.FromMilliseconds(2500);

    /// <summary>Song Info bar-select detail fade.</summary>
    public static readonly TimeSpan BarSelectFade = TimeSpan.FromMilliseconds(300);

    /// <summary>Backward-compatible alias for the data-swap interval.</summary>
    public static TimeSpan Cycle => Interval;

    /// <summary>Backward-compatible alias for each opacity fade.</summary>
    public static TimeSpan Fade => FadeOut;
}
#endregion

#region Fit
/// <summary>Fits a decorative demo into its fixed illustration frame (issue #241).</summary>
public static class FirstRunDemoFit
{
    /// <summary>
    /// Uniform scale that fits a demo laid out at <paramref name="naturalHeight"/> into <paramref name="availableHeight"/>:
    /// 1 when it already fits or the frame is unbounded, otherwise the shrink factor. Large text sizes grow the demo's
    /// sample rows past the 210 epx frame; shrinking the decorative picture keeps every row whole while the slide's
    /// title and description keep the full text scale.
    /// </summary>
    /// <param name="naturalHeight">Demo height at the frame's width.</param>
    /// <param name="availableHeight">Frame height.</param>
    /// <returns>Scale in (0, 1].</returns>
    public static double Scale(double naturalHeight, double availableHeight)
    {
        if (!double.IsFinite(availableHeight) || availableHeight <= 0 || !double.IsFinite(naturalHeight)) return 1;
        return naturalHeight > availableHeight ? availableHeight / naturalHeight : 1;
    }
}
#endregion

#region Swap selection
/// <summary>Deterministic native equivalent of the web demo row-selection rules.</summary>
public static class FirstRunDemoRotation
{
    /// <summary>Returns how many visible rows swap on a tick.</summary>
    /// <param name="rows">Visible row count.</param>
    /// <returns>0 for no rows, 1 for up to 3, 2 for up to 6, otherwise 3.</returns>
    public static int SwapCount(int rows)
    {
        if (rows <= 0) return 0;
        if (rows <= 3) return 1;
        if (rows <= 6) return 2;
        return 3;
    }

    /// <summary>Picks deterministic, distinct row indices for a swap tick.</summary>
    /// <param name="tick">Zero-based tick.</param>
    /// <param name="rows">Visible row count.</param>
    /// <param name="previous">Previous selected set, avoided when another set is possible.</param>
    /// <returns>Sorted row indices.</returns>
    public static IReadOnlyList<int> SwapIndices(int tick, int rows, IReadOnlySet<int>? previous = null)
    {
        var count = SwapCount(rows);
        if (count == 0) return [];
        var prior = previous ?? new HashSet<int>();
        var picked = Array.Empty<int>();
        for (var attempt = 0; attempt < 10; attempt++)
        {
            var order = Enumerable.Range(0, rows).ToArray();
            var rng = new SplitMix64(unchecked((ulong)tick * 0x9E3779B9UL + (ulong)attempt));
            for (var i = order.Length - 1; i > 0; i--)
            {
                var j = (int)(rng.Next() % (ulong)(i + 1));
                (order[i], order[j]) = (order[j], order[i]);
            }
            picked = [.. order.Take(count).Order()];
            if (count == rows || !picked.ToHashSet().SetEquals(prior)) break;
        }
        return picked;
    }

    private struct SplitMix64
    {
        private ulong state;

        public SplitMix64(ulong seed) => state = seed;

        public ulong Next()
        {
            unchecked
            {
                state += 0x9E3779B97F4A7C15UL;
                var z = state;
                z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                return z ^ (z >> 31);
            }
        }
    }
}

/// <summary>Visible rows that walk through a larger pool without duplicate visible IDs.</summary>
/// <typeparam name="T">Pool item type.</typeparam>
public sealed class FirstRunRowRotation<T> where T : IFirstRunDemoPoolItem
{
    private int cursor;
    private int tick;
    private HashSet<int> lastSwapped = [];

    /// <summary>Creates a row rotator with the first visible pool items shown.</summary>
    /// <param name="pool">Full pool.</param>
    /// <param name="visible">Visible slot count.</param>
    public FirstRunRowRotation(IReadOnlyList<T> pool, int visible)
    {
        Pool = pool;
        Rows = [.. pool.Take(Math.Max(0, visible))];
        cursor = Rows.Count;
    }

    /// <summary>All items that may appear.</summary>
    public IReadOnlyList<T> Pool { get; }

    /// <summary>Visible rows in stable slots.</summary>
    public List<T> Rows { get; }

    /// <summary>Whether a tick can reveal an item not already visible.</summary>
    public bool CanRotate => Rows.Count > 0 && Pool.Select(p => p.Id).Distinct(StringComparer.Ordinal).Count() > Rows.Select(r => r.Id).Distinct(StringComparer.Ordinal).Count();

    /// <summary>Chooses the next slots to replace and advances the tick.</summary>
    /// <returns>Sorted slot indices, or empty when the pool cannot rotate.</returns>
    public IReadOnlyList<int> NextSwap()
    {
        if (!CanRotate) return [];
        var indices = FirstRunDemoRotation.SwapIndices(tick, Rows.Count, lastSwapped);
        tick++;
        lastSwapped = [.. indices];
        return indices;
    }

    /// <summary>Replaces slots with the next unseen pool entries.</summary>
    /// <param name="indices">Slots returned by <see cref="NextSwap"/>.</param>
    public void Replace(IEnumerable<int> indices)
    {
        if (Pool.Count == 0) return;
        foreach (var index in indices)
        {
            if (index < 0 || index >= Rows.Count) continue;
            for (var attempts = 0; attempts < Pool.Count; attempts++)
            {
                var candidate = Pool[cursor % Pool.Count];
                cursor = (cursor + 1) % Pool.Count;
                var visible = Rows.Where((_, i) => i != index).Select(r => r.Id).ToHashSet(StringComparer.Ordinal);
                if (!visible.Contains(candidate.Id))
                {
                    Rows[index] = candidate;
                    break;
                }
            }
        }
    }
}

/// <summary>A fixed-size window over a pool that advances by the visible count and wraps.</summary>
/// <typeparam name="T">Item type.</typeparam>
public sealed class FirstRunWindowRotation<T>
{
    private int start;

    /// <summary>Creates a window rotator.</summary>
    /// <param name="pool">Items to page through.</param>
    /// <param name="visible">Requested visible count.</param>
    public FirstRunWindowRotation(IReadOnlyList<T> pool, int visible)
    {
        Pool = pool;
        Count = Math.Min(Math.Max(0, visible), pool.Count);
    }

    /// <summary>Items to page through.</summary>
    public IReadOnlyList<T> Pool { get; }

    /// <summary>Visible item count.</summary>
    public int Count { get; }

    /// <summary>Current wrapped window.</summary>
    public IReadOnlyList<T> Rows => Pool.Count == 0 ? [] : [.. Enumerable.Range(0, Count).Select(i => Pool[(start + i) % Pool.Count])];

    /// <summary>Advances to the next wrapped window.</summary>
    public void Advance()
    {
        if (Pool.Count == 0) return;
        start = (start + Count) % Pool.Count;
    }
}
#endregion

#region Song icon pattern
/// <summary>Per-title score/FC pattern used by the Songs icons demo.</summary>
public static class FirstRunDemoScorePattern
{
    /// <summary>One instrument chip's state.</summary>
    public enum State
    {
        /// <summary>No score.</summary>
        NoScore,
        /// <summary>Has a score.</summary>
        Scored,
        /// <summary>Has a full combo.</summary>
        FullCombo,
    }

    /// <summary>Web <c>hashString</c>: 32-bit wrap over UTF-16 code units.</summary>
    /// <param name="title">Song title.</param>
    /// <returns>Signed 32-bit hash.</returns>
    public static int Hash(string title)
    {
        var hash = 0;
        foreach (var codeUnit in title.AsSpan())
        {
            unchecked { hash = ((hash << 5) - hash) + codeUnit; }
        }
        return hash;
    }

    /// <summary>States for instruments in display order.</summary>
    /// <param name="title">Song title.</param>
    /// <param name="count">Instrument count.</param>
    /// <returns>One state per requested instrument.</returns>
    public static IReadOnlyList<State> States(string title, int count)
    {
        var hash = Hash(title);
        var bits = hash == int.MinValue ? 2147483648L : Math.Abs((long)hash);
        return [.. Enumerable.Range(0, Math.Max(0, count)).Select(i =>
        {
            var scored = ((bits >> (i * 2)) & 1L) == 1L;
            var fc = scored && ((bits >> (i * 2 + 1)) & 1L) == 1L;
            return fc ? State.FullCombo : scored ? State.Scored : State.NoScore;
        })];
    }
}
#endregion

#region Data pools
/// <summary>One leaderboard demo entry.</summary>
/// <param name="Rank">Rank number.</param>
/// <param name="DisplayName">Player name.</param>
/// <param name="RatingLabel">Score/rating label.</param>
/// <param name="IsPlayer">Whether this is the selected player.</param>
public sealed record FirstRunDemoRanking(int Rank, string DisplayName, string RatingLabel, bool IsPlayer = false);

/// <summary>One rival demo entry.</summary>
/// <param name="AccountId">Stable demo ID.</param>
/// <param name="DisplayName">Rival name.</param>
/// <param name="RivalScore">Rivalry score.</param>
/// <param name="SharedSongCount">Shared song count.</param>
/// <param name="AheadCount">Songs where the rival is ahead.</param>
/// <param name="BehindCount">Songs where the rival is behind.</param>
/// <param name="AvgSignedDelta">Average signed score delta.</param>
public sealed record FirstRunDemoRival(string AccountId, string DisplayName, int RivalScore, int SharedSongCount, int AheadCount, int BehindCount, int AvgSignedDelta) : IFirstRunDemoPoolItem
{
    /// <summary>Stable pool identity.</summary>
    public string Id => AccountId;
}

/// <summary>One metadata sample row.</summary>
/// <param name="Score">Score.</param>
/// <param name="Accuracy">Accuracy in parts per million.</param>
/// <param name="FullCombo">Full-combo flag.</param>
/// <param name="Stars">Stars.</param>
/// <param name="Percentile">Percentile label.</param>
/// <param name="Season">Season.</param>
/// <param name="Difficulty">Game difficulty index.</param>
public sealed record FirstRunDemoMetadata(long Score, int Accuracy, bool FullCombo, int Stars, string Percentile, int Season, int Difficulty);

/// <summary>Two-pill metadata layouts.</summary>
public enum FirstRunDemoMetadataLayout
{
    /// <summary>Score and accuracy.</summary>
    ScoreAccuracy,
    /// <summary>Stars and difficulty.</summary>
    StarsDifficulty,
    /// <summary>Percentile and season.</summary>
    PercentileSeason,
    /// <summary>Score and stars.</summary>
    ScoreStars,
    /// <summary>Accuracy and difficulty.</summary>
    AccuracyDifficulty,
    /// <summary>Percentile and score.</summary>
    PercentileScore,
}

/// <summary>Song Info bar-select sample.</summary>
/// <param name="Accuracy">Accuracy percent.</param>
/// <param name="Score">Score.</param>
/// <param name="When">Relative date.</param>
/// <param name="FullCombo">Whether the score is an FC.</param>
public sealed record FirstRunDemoBar(int Accuracy, int Score, string When, bool FullCombo = false);

/// <summary>Suggestion-card template.</summary>
/// <param name="Key">Stable key.</param>
/// <param name="Title">Title.</param>
/// <param name="Description">Description.</param>
/// <param name="Instrument">Primary instrument label.</param>
public sealed record FirstRunSuggestionTemplate(string Key, string Title, string Description, string Instrument);

/// <summary>Experimental metric option.</summary>
/// <param name="Title">Metric title.</param>
/// <param name="Description">Metric description.</param>
public sealed record FirstRunExperimentalMetric(string Title, string Description);

/// <summary>Rival-detail rank sample.</summary>
/// <param name="UserRank">User rank.</param>
/// <param name="RivalRank">Rival rank.</param>
/// <param name="UserScore">User score.</param>
/// <param name="RivalScore">Rival score.</param>
public sealed record FirstRunRivalRankData(int UserRank, int RivalRank, int UserScore, int RivalScore);

/// <summary>Slide → demo mapping plus shared first-run demo data.</summary>
public static class FirstRunDemos
{
    /// <summary>Backward-compatible interval alias.</summary>
    public static TimeSpan Cycle => FirstRunDemoTiming.Interval;

    /// <summary>Backward-compatible fade alias.</summary>
    public static TimeSpan Fade => FirstRunDemoTiming.FadeOut;

    /// <summary>Default Windows visible song-row count.</summary>
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

    private static readonly Dictionary<string, FirstRunDemoRotationKind> RotatingKinds = new(StringComparer.Ordinal)
    {
        ["songs-song-list"] = FirstRunDemoRotationKind.SongsSongList,
        ["songs-icons"] = FirstRunDemoRotationKind.SongsIcons,
        ["songs-metadata"] = FirstRunDemoRotationKind.SongsMetadata,
        ["statistics-top-songs"] = FirstRunDemoRotationKind.StatisticsTopSongs,
        ["songinfo-bar-select"] = FirstRunDemoRotationKind.SongInfoBarSelect,
        ["suggestions-category-card"] = FirstRunDemoRotationKind.SuggestionsCategoryCard,
        ["leaderboards-experimental-metrics"] = FirstRunDemoRotationKind.LeaderboardsExperimentalMetrics,
        ["compete-hub"] = FirstRunDemoRotationKind.CompeteHub,
        ["compete-rivals"] = FirstRunDemoRotationKind.CompeteRivals,
        ["rivals-overview"] = FirstRunDemoRotationKind.RivalsOverview,
        ["rivals-instruments"] = FirstRunDemoRotationKind.RivalsInstruments,
        ["rivals-detail"] = FirstRunDemoRotationKind.RivalsDetail,
    };

    /// <summary>Demo for a slide.</summary>
    /// <param name="slideId">Catalogue slide ID.</param>
    /// <returns>Kind, or <see langword="null"/> for an unknown ID.</returns>
    public static FirstRunDemoKind? KindFor(string? slideId) =>
        slideId is not null && Kinds.TryGetValue(slideId, out var kind) ? kind : null;

    /// <summary>Rotating data demo for a slide.</summary>
    /// <param name="slideId">Catalogue slide ID.</param>
    /// <returns>Rotating kind, or <see langword="null"/> when the web keeps its data static.</returns>
    public static FirstRunDemoRotationKind? RotationKindFor(string? slideId) =>
        slideId is not null && RotatingKinds.TryGetValue(slideId, out var kind) ? kind : null;

    /// <summary>Whether a slide rotates data on the web.</summary>
    /// <param name="slideId">Catalogue slide ID.</param>
    /// <returns><see langword="true"/> for the twelve rotating demos.</returns>
    public static bool Rotates(string? slideId) => RotationKindFor(slideId) is not null;

    /// <summary>The twelve rotating slide IDs.</summary>
    public static IReadOnlyList<string> RotatingSlideIds { get; } = [.. RotatingKinds.Keys.Order(StringComparer.Ordinal)];

    /// <summary>Artist marker the web uses to pick neutral, first-party demo songs.</summary>
    public const string PreferredArtistMarker = "Epic Games";

    /// <summary>Most songs a demo rotates through.</summary>
    public const int PoolSize = 12;

    /// <summary>
    /// Most song rows any demo shows at once (the Suggestions card lists five; Statistics' top songs and Rival detail
    /// four). <see cref="SongPool"/> pads to this so a short catalogue shows placeholders, never a wrapped duplicate.
    /// </summary>
    public const int MaxVisibleSongs = 5;

    /// <summary>Whether a demo shows Item Shop songs, so it prefers the current Shop (web <c>useItemShopDemoSongs</c>).</summary>
    /// <param name="kind">Demo kind.</param>
    /// <returns><see langword="true"/> for the Shop pulse rows and Shop tiles.</returns>
    public static bool UsesShopSongs(FirstRunDemoKind kind) =>
        kind is FirstRunDemoKind.ShopPulse or FirstRunDemoKind.NewPulse or FirstRunDemoKind.LeavingPulse or FirstRunDemoKind.ShopTiles;

    /// <summary>Web demo rankings.</summary>
    public static IReadOnlyList<FirstRunDemoRanking> Rankings { get; } =
    [
        new(1, "GoldStreak", "2,480,000"), new(2, "NoteHunter", "2,310,500"), new(3, "BeatLegend", "2,275,100"),
        new(4, "VocalStorm", "2,198,000"), new(5, "BassRuler", "2,112,800"), new(6, "TopClutch", "2,045,300"),
        new(7, "StageKnight", "1,998,700"), new(8, "RhythmEdge", "1,922,400"), new(9, "FretBlaze", "1,874,600"),
        new(10, "ComboKing", "1,801,200"),
    ];

    /// <summary>Selected player's demo ranking row.</summary>
    public static FirstRunDemoRanking PlayerRanking { get; } = new(42, "You", "1,250,000", true);

    /// <summary>Backward-compatible row projection of the top demo players.</summary>
    public static IReadOnlyList<FirstRunDemoRow> Players { get; } = [.. Rankings.Take(5).Select(r => new FirstRunDemoRow($"#{r.Rank} · {r.DisplayName}", "", r.RatingLabel))];

    /// <summary>Metadata demo samples.</summary>
    public static IReadOnlyList<FirstRunDemoMetadata> MetaData { get; } =
    [
        new(198942, 1000000, true, 6, "Top 1%", 12, 4), new(157320, 980000, false, 5, "Top 5%", 10, 3),
        new(142800, 960000, false, 5, "Top 8%", 11, 5), new(185600, 1000000, true, 6, "Top 2%", 9, 2),
        new(123400, 940000, false, 4, "Top 15%", 8, 4), new(176100, 1000000, true, 6, "Top 3%", 12, 3),
        new(110250, 910000, false, 4, "Top 20%", 7, 5), new(168900, 970000, false, 5, "Top 6%", 11, 2),
        new(191200, 1000000, true, 6, "Top 1%", 10, 4), new(135700, 950000, false, 5, "Top 10%", 9, 3),
    ];

    /// <summary>Metadata two-pill layouts.</summary>
    public static IReadOnlyList<FirstRunDemoMetadataLayout> MetadataLayouts { get; } = Enum.GetValues<FirstRunDemoMetadataLayout>();

    /// <summary>Top-songs percentile samples.</summary>
    public static IReadOnlyList<double> TopSongPercentiles { get; } = [1.2, 3.5, 7.8, 14.2, 22.6, 35.1, 48.9];

    /// <summary>
    /// The percentile pill of top-songs row <paramref name="row"/>: fixed per row, like the web's
    /// <c>DEMO_PERCENTILES[i % length]</c>, so the pills stay in rank order while the songs rotate.
    /// </summary>
    /// <param name="row">Zero-based visible row.</param>
    /// <returns>Percentile sample.</returns>
    public static double TopSongPercentile(int row) => TopSongPercentiles[row % TopSongPercentiles.Count];

    /// <summary>Song Info bar-select samples.</summary>
    public static IReadOnlyList<FirstRunDemoBar> BarSelectBars { get; } =
    [
        new(62, 218400, "2 days ago"), new(78, 347100, "Yesterday"), new(100, 486500, "Today", true),
    ];

    /// <summary>Suggestion templates.</summary>
    public static IReadOnlyList<FirstRunSuggestionTemplate> SuggestionTemplates { get; } =
    [
        new("unfc_guitar", "Finish the Lead FCs", "Play these songs again on Lead and grab an FC!", "Lead"),
        new("pct_push_bass", "Percentile Push: Bass", "Replay these Bass songs to jump to the next percentile bracket.", "Bass"),
        new("near_fc_any", "FC These Next!", "If you can get gold stars, you can FC it!", "Lead"),
        new("unplayed_drums", "New on Drums", "Songs you haven't played on Drums yet.", "Drums"),
    ];

    /// <summary>Experimental metric options.</summary>
    public static IReadOnlyList<FirstRunExperimentalMetric> ExperimentalMetrics { get; } =
    [
        new("Adjusted Percentile", "Estimated skill from your rank position."),
        new("Popularity-Weighted Percentile", "Adjusts for how many players know this song."),
        new("FC Rate", "Share of your tracked scores that were full combos."),
        new("Max Score %", "How close your best score is to the song's ceiling."),
    ];

    /// <summary>Rivals above the player.</summary>
    public static IReadOnlyList<FirstRunDemoRival> RivalsAbove { get; } =
    [
        new("demo-above-1", "KeyDrifter", 920, 148, 82, 66, 12), new("demo-above-2", "DeepGroove", 870, 135, 75, 60, 8),
        new("demo-above-3", "SonicRush", 840, 120, 68, 52, 5), new("demo-above-4", "FretPhenom", 900, 155, 88, 67, 10),
        new("demo-above-5", "NeonPick", 855, 122, 70, 52, 7), new("demo-above-6", "BeatForge", 830, 118, 65, 53, 4),
    ];

    /// <summary>Rivals below the player.</summary>
    public static IReadOnlyList<FirstRunDemoRival> RivalsBelow { get; } =
    [
        new("demo-below-1", "DrumSurge", 790, 142, 58, 84, -10), new("demo-below-2", "ShredLord", 750, 130, 50, 80, -14),
        new("demo-below-3", "NoteCrush", 710, 118, 44, 74, -18), new("demo-below-4", "AxelStrike", 770, 138, 54, 84, -12),
        new("demo-below-5", "LowTide", 730, 126, 46, 80, -16), new("demo-below-6", "OffBeat", 695, 112, 40, 72, -20),
    ];

    /// <summary>Instrument rival pools keyed by instrument label and side.</summary>
    public static IReadOnlyDictionary<string, (IReadOnlyList<FirstRunDemoRival> Above, IReadOnlyList<FirstRunDemoRival> Below)> InstrumentRivals { get; } =
        new Dictionary<string, (IReadOnlyList<FirstRunDemoRival>, IReadOnlyList<FirstRunDemoRival>)>(StringComparer.Ordinal)
        {
            ["Guitar"] = ([new("ig-1", "StageKnight", 860, 140, 78, 62, 6), new("ig-3", "FretPhenom", 890, 145, 82, 63, 9), new("ig-5", "NeonPick", 845, 130, 72, 58, 5)],
                         [new("ig-2", "FretBlaze", 720, 125, 48, 77, -12), new("ig-4", "AxelStrike", 700, 118, 42, 76, -15), new("ig-6", "LowTide", 680, 110, 38, 72, -18)]),
            ["Drums"] = ([new("id-1", "BeatLegend", 910, 132, 80, 52, 14), new("id-3", "BeatForge", 875, 128, 74, 54, 10), new("id-5", "DoubleSnare", 850, 120, 70, 50, 8)],
                         [new("id-2", "RhythmEdge", 680, 115, 40, 75, -20), new("id-4", "OffBeat", 660, 108, 36, 72, -22), new("id-6", "DrumSurge", 640, 100, 32, 68, -24)]),
            ["Vocals"] = ([new("iv-1", "VocalStorm", 880, 128, 74, 54, 10), new("iv-3", "SonicRush", 860, 122, 70, 52, 8), new("iv-5", "NoteHunter", 840, 116, 66, 50, 6)],
                          [new("iv-2", "TopClutch", 700, 110, 42, 68, -16), new("iv-4", "NoteCrush", 680, 104, 38, 66, -18), new("iv-6", "KeyDrifter", 660, 98, 34, 64, -20)]),
        };

    /// <summary>Rival-detail category rank samples.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<FirstRunRivalRankData>> RivalDetailCategories { get; } =
        new Dictionary<string, IReadOnlyList<FirstRunRivalRankData>>(StringComparer.Ordinal)
        {
            ["Closest Battles"] = [new(14, 15, 988000, 987500), new(23, 22, 965000, 965800), new(8, 9, 995200, 994900), new(31, 30, 942000, 942600)],
            ["Almost Passed"] = [new(18, 15, 971000, 978000), new(12, 9, 986000, 992000), new(26, 22, 950000, 958000), new(35, 31, 930000, 938000)],
            ["Slipping Away"] = [new(28, 12, 945000, 985000), new(40, 18, 910000, 970000), new(35, 15, 930000, 978000), new(48, 22, 890000, 960000)],
            ["Barely Winning"] = [new(15, 18, 978000, 971000), new(9, 12, 992000, 986000), new(22, 26, 958000, 950000), new(31, 35, 938000, 930000)],
            ["Pulling Forward"] = [new(8, 22, 994000, 960000), new(5, 18, 998000, 970000), new(12, 30, 986000, 940000), new(10, 26, 990000, 952000)],
            ["Dominating Them"] = [new(3, 45, 999000, 895000), new(2, 38, 999500, 915000), new(5, 52, 998000, 880000), new(4, 60, 998500, 860000)],
        };

    /// <summary>Filter chips used by static demos.</summary>
    public static IReadOnlyList<string> FilterChips { get; } = ["Lead · Expert", "Bass · Hard", "Drums · Expert", "Vocals · Medium"];

    /// <summary>Bar heights used by static chart demos.</summary>
    public static IReadOnlyList<double> Bars { get; } = [0.42, 0.55, 0.61, 0.58, 0.74, 0.83, 0.9];

    /// <summary>Legacy metadata-pill labels used by static demos.</summary>
    public static IReadOnlyList<string> MetadataPills { get; } = ["142,800", "96%", "Top 8%", "Season 11", "FC"];

    /// <summary>Statistic tiles used by static demos.</summary>
    public static IReadOnlyList<FirstRunDemoRow> Tiles { get; } =
    [
        new("Songs Played", "", "612"), new("Full Combos", "", "248"), new("Avg Accuracy", "", "97.4%"),
        new("Top 1%", "", "31"), new("Gold Stars", "", "189"), new("Best Rank", "", "#42"),
    ];

    /// <summary>Formats score metadata.</summary>
    /// <param name="metadata">Metadata sample.</param>
    /// <param name="layout">Two-pill layout.</param>
    /// <returns>Two display pills.</returns>
    public static IReadOnlyList<string> MetadataPillsFor(FirstRunDemoMetadata metadata, FirstRunDemoMetadataLayout layout)
    {
        var score = metadata.Score.ToString("N0", CultureInfo.InvariantCulture);
        var accuracy = metadata.FullCombo ? "100% FC" : $"{metadata.Accuracy / 10000.0:0.#}%";
        var stars = metadata.Stars == 6 ? "Gold ★" : $"{metadata.Stars}★";
        var difficulty = $"Difficulty {metadata.Difficulty}";
        var season = $"Season {metadata.Season}";
        return layout switch
        {
            FirstRunDemoMetadataLayout.ScoreAccuracy => [score, accuracy],
            FirstRunDemoMetadataLayout.StarsDifficulty => [stars, difficulty],
            FirstRunDemoMetadataLayout.PercentileSeason => [metadata.Percentile, season],
            FirstRunDemoMetadataLayout.ScoreStars => [score, stars],
            FirstRunDemoMetadataLayout.AccuracyDifficulty => [accuracy, difficulty],
            _ => [metadata.Percentile, score],
        };
    }

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
    /// <see cref="MaxVisibleSongs"/> (all placeholders while the catalogue loads or is unavailable). Never invents songs,
    /// and no visible row has to wrap around to repeat a song.
    /// </summary>
    /// <param name="catalog">Loaded catalogue songs, or <see langword="null"/>.</param>
    /// <param name="preferring">Song IDs to show first, or <see langword="null"/>.</param>
    /// <returns>At least <see cref="MaxVisibleSongs"/> entries.</returns>
    public static IReadOnlyList<FirstRunDemoSong> SongPool(IEnumerable<Song>? catalog, IEnumerable<string>? preferring = null)
    {
        var pool = Pick(catalog, PoolSize, preferring)
            .Select(s => new FirstRunDemoSong(s.SongId, new FirstRunDemoRow(s.Title, s.Year is { } y ? $"{s.Artist} · {y}" : s.Artist), s.AlbumArt))
            .ToList();
        while (pool.Count < MaxVisibleSongs) pool.Add(FirstRunDemoSong.Placeholder);
        return pool;
    }

    /// <summary>UIA ItemStatus of a demo showing catalogue songs (issue #240).</summary>
    public const string CatalogueStatus = "catalogue";

    /// <summary>UIA ItemStatus of a demo still showing redacted placeholder rows.</summary>
    public const string PlaceholderStatus = "placeholder";

    /// <summary>
    /// The decorative demo's UIA ItemStatus (read by UI tests only; the demo is Raw, so Narrator never reads it):
    /// whether its rows come from the catalogue or are still placeholders.
    /// </summary>
    /// <param name="pool">Pool from <see cref="SongPool"/>.</param>
    /// <returns><see cref="CatalogueStatus"/> when the first row is a real song, else <see cref="PlaceholderStatus"/>.</returns>
    public static string DataStatus(IReadOnlyList<FirstRunDemoSong> pool) =>
        pool.Count > 0 && !pool[0].IsPlaceholder ? CatalogueStatus : PlaceholderStatus;

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

    /// <summary>Legacy fixed-turn swap retained for callers that have not moved to <see cref="FirstRunRowRotation{T}"/>.</summary>
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
