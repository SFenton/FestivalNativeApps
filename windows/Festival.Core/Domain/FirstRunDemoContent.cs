using System.Globalization;
using Festival.Core.ViewModels;

namespace Festival.Core.Domain;

#region Entrance
/// <summary>
/// A slide's entrance timing (web <c>FirstRunCarousel</c> and each demo's <c>FadeIn</c> delays): demo items fade up one
/// step apart, then the title after <see cref="StaggerCount"/> steps of 125 ms and the description one step later.
/// </summary>
/// <param name="StaggerCount">Web <c>contentStaggerCount</c>: how many 125 ms steps the title waits.</param>
/// <param name="Step">Gap between demo items (web per-demo stagger; zero fades every item together).</param>
/// <param name="Offset">Steps before the first item (web demos that start at <c>(i + 1) × step</c>).</param>
public sealed record FirstRunEntrance(int StaggerCount, TimeSpan Step, int Offset = 0)
{
    /// <summary>Web <c>STAGGER_INTERVAL</c>: the carousel's title/description step and most demos' item step.</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(125);

    /// <summary>Web <c>FadeIn</c> duration (opacity 0→1, 12 epx rise, ease-out).</summary>
    public static readonly TimeSpan Duration = TimeSpan.FromMilliseconds(400);

    /// <summary>Web <c>FadeIn</c> rise in epx.</summary>
    public const float Rise = 12;

    /// <summary>Web <c>TRANSITION_MS</c>: the second block of the Sort/Filter/Navigation demos.</summary>
    public static readonly TimeSpan SecondBlock = TimeSpan.FromMilliseconds(300);

    private static readonly TimeSpan Fast = TimeSpan.FromMilliseconds(80);

    private static readonly Dictionary<string, FirstRunEntrance> Table = new(StringComparer.Ordinal)
    {
        ["songs-song-list"] = new(4, Interval),
        ["songs-sort"] = new(3, SecondBlock),
        ["songs-navigation"] = new(3, SecondBlock),
        ["songs-filter"] = new(3, SecondBlock),
        ["songs-icons"] = new(4, Interval),
        ["songs-metadata"] = new(4, Interval),
        ["songs-shop-highlight"] = new(3, Interval),
        ["songs-new-in-shop"] = new(3, Interval),
        ["songs-leaving-tomorrow"] = new(3, Interval),
        ["songinfo-chart"] = new(3, TimeSpan.Zero),
        ["songinfo-bar-select"] = new(3, TimeSpan.Zero),
        ["songinfo-view-all"] = new(5, Interval),
        ["songinfo-top-scores"] = new(6, Interval, 1),
        ["songinfo-paths"] = new(3, Interval),
        ["songinfo-shop-button"] = new(3, Interval),
        ["songinfo-new-in-shop"] = new(3, Interval),
        ["songinfo-leaving-tomorrow"] = new(3, Interval),
        ["playerhistory-score-list"] = new(5, Interval),
        ["playerhistory-sort"] = new(3, SecondBlock),
        ["statistics-select-profile"] = new(1, TimeSpan.Zero),
        ["statistics-drill-down"] = new(2, Interval),
        ["statistics-overview"] = new(3, Fast),
        ["statistics-instrument-breakdown"] = new(3, Fast),
        ["statistics-percentiles"] = new(2, Interval),
        ["statistics-top-songs"] = new(3, Interval),
        ["suggestions-category-card"] = new(2, Interval),
        ["suggestions-global-filter"] = new(3, Interval),
        ["suggestions-instrument-filter"] = new(3, Interval),
        ["suggestions-infinite-scroll"] = new(1, Interval),
        ["leaderboards-overview"] = new(4, Fast),
        ["leaderboards-experimental-metrics"] = new(6, Interval),
        ["leaderboards-your-rank"] = new(7, Fast),
        ["compete-hub"] = new(1, TimeSpan.Zero),
        ["compete-leaderboards"] = new(6, Fast),
        ["compete-rivals"] = new(4, Fast),
        ["rivals-overview"] = new(4, Fast),
        ["rivals-instruments"] = new(6, Fast),
        ["rivals-detail"] = new(4, TimeSpan.FromMilliseconds(100), 1),
        ["shop-overview"] = new(6, TimeSpan.FromMilliseconds(60)),
        ["shop-highlighting"] = new(5, Fast),
        ["shop-new-items"] = new(5, Fast),
        ["shop-leaving-tomorrow"] = new(5, Fast),
    };

    /// <summary>Default for a slide without a demo: the title and description follow at once.</summary>
    public static FirstRunEntrance None { get; } = new(0, TimeSpan.Zero);

    /// <summary>A slide's entrance.</summary>
    /// <param name="slideId">Catalogue slide ID.</param>
    /// <returns>Entrance (<see cref="None"/> for an unknown slide).</returns>
    public static FirstRunEntrance For(string? slideId) =>
        slideId is not null && Table.TryGetValue(slideId, out var entrance) ? entrance : None;

    /// <summary>Slide IDs with an entrance (every demo slide).</summary>
    public static IReadOnlyCollection<string> SlideIds => Table.Keys;

    /// <summary>Delay of demo item <paramref name="index"/>.</summary>
    /// <param name="index">Zero-based item.</param>
    /// <returns>Delay.</returns>
    public TimeSpan ItemDelay(int index) => Step * (Math.Max(0, index) + Offset);

    /// <summary>Title delay (web <c>contentStaggerCount × STAGGER_INTERVAL</c>).</summary>
    public TimeSpan TitleDelay => Interval * StaggerCount;

    /// <summary>Description delay, one step after the title.</summary>
    public TimeSpan DescriptionDelay => Interval * (StaggerCount + 1);
}
#endregion

#region Shop demo pattern
/// <summary>
/// Which demo rows pulse and how (web <c>ShopHighlightDemo</c>, <c>NewInShopDemo</c>, <c>LeavingTomorrowDemo</c> and the
/// Shop page's <c>HighlightingDemo</c>/<c>NewItemsDemo</c>/<c>LeavingTomorrowDemo</c>).
/// </summary>
public static class FirstRunShopPattern
{
    /// <summary>A row's pulse.</summary>
    /// <param name="slideId">Slide.</param>
    /// <param name="row">Zero-based row.</param>
    /// <param name="rows">Visible rows.</param>
    /// <returns>Pulse, or <see langword="null"/> for a quiet row.</returns>
    public static SongRowShopPulse? Pulse(string? slideId, int row, int rows) => slideId switch
    {
        "songs-shop-highlight" or "shop-highlighting" => row % 2 == 0 ? SongRowShopPulse.InShop : null,
        "songs-new-in-shop" or "shop-new-items" => (row % 3) switch { 0 => SongRowShopPulse.New, 1 => SongRowShopPulse.InShop, _ => null },
        "shop-leaving-tomorrow" => (row % 3) switch { 0 => SongRowShopPulse.Leaving, 1 => SongRowShopPulse.InShop, _ => null },
        "songs-leaving-tomorrow" => row < (rows + 1) / 2 ? SongRowShopPulse.Leaving : null,
        _ => null,
    };

    /// <summary>The Item Shop list badge a Shop-page demo row carries (Songs rows carry the bag instead).</summary>
    /// <param name="slideId">Slide.</param>
    /// <param name="row">Zero-based row.</param>
    /// <param name="rows">Visible rows.</param>
    /// <returns>Highlight, or <see langword="null"/> without a badge.</returns>
    public static ShopHighlight? Badge(string? slideId, int row, int rows)
    {
        if (slideId is null || !slideId.StartsWith("shop-", StringComparison.Ordinal)) return null;
        var pulse = Pulse(slideId, row, rows);
        return pulse == SongRowShopPulse.New ? ShopHighlight.New : pulse == SongRowShopPulse.Leaving ? ShopHighlight.LeavingTomorrow : null;
    }

    /// <summary>The Shop overview tiles' highlights (web <c>ShopOverviewDemo</c>: one New, one plain, one Leaving).</summary>
    /// <param name="tile">Zero-based tile.</param>
    /// <returns>Highlight.</returns>
    public static ShopHighlight? Tile(int tile) => (tile % 3) switch { 0 => ShopHighlight.New, 2 => ShopHighlight.LeavingTomorrow, _ => null };
}
#endregion

#region Auto-scroll
/// <summary>
/// The Suggestions infinite-scroll demo's motion (web <c>InfiniteScrollDemo</c>): the card list scrolls down at
/// 30 epx/s after 100 ms, jumps back to the top at the end, and fades 36 epx at an edge only while content lies past it.
/// </summary>
public static class FirstRunAutoScroll
{
    /// <summary>Speed in epx per second.</summary>
    public const double Speed = 30;

    /// <summary>Delay before scrolling starts.</summary>
    public static readonly TimeSpan StartDelay = TimeSpan.FromMilliseconds(100);

    /// <summary>Edge fade height in epx (web <c>MASK_FADE</c>).</summary>
    public const double EdgeFade = 36;

    /// <summary>Cards in the demo list (web <c>CATEGORY_TEMPLATES</c>).</summary>
    public const int Cards = 6;

    /// <summary>Songs per card (web <c>SONGS_PER_CARD</c>).</summary>
    public const int SongsPerCard = 2;

    /// <summary>Scroll range: content past the viewport, never negative.</summary>
    /// <param name="content">Content height.</param>
    /// <param name="viewport">Viewport height.</param>
    /// <returns>Maximum offset.</returns>
    public static double Range(double content, double viewport) => Math.Max(0, content - viewport);

    /// <summary>One pass from the top to the end.</summary>
    /// <param name="range">Scroll range.</param>
    /// <returns>Duration (zero without a range).</returns>
    public static TimeSpan Pass(double range) => range <= 0 ? TimeSpan.Zero : TimeSpan.FromSeconds(range / Speed);

    /// <summary>Offset after <paramref name="elapsed"/> (the web's per-frame <c>scrollTop</c> wrapping to 0).</summary>
    /// <param name="elapsed">Time since scrolling started.</param>
    /// <param name="range">Scroll range.</param>
    /// <returns>Offset in [0, range).</returns>
    public static double Offset(TimeSpan elapsed, double range) =>
        range <= 0 || elapsed <= TimeSpan.Zero ? 0 : elapsed.TotalSeconds * Speed % range;

    /// <summary>Top and bottom fade heights at an offset (web <c>updateMask</c>: no fade at the matching end).</summary>
    /// <param name="offset">Scroll offset.</param>
    /// <param name="range">Scroll range.</param>
    /// <returns>Fade heights in epx.</returns>
    public static (double Top, double Bottom) Fades(double offset, double range) =>
        (Math.Clamp(offset, 0, EdgeFade), Math.Clamp(range - offset, 0, EdgeFade));

    /// <summary>
    /// The demo's UIA ItemStatus token for UI tests, appended after its data status, e.g.
    /// <c>scroll=running pos=mid wraps=1 fade=top+bottom</c> (space-separated: UI test steps split on semicolons).
    /// </summary>
    /// <param name="state">Whether the list scrolls, is held at the top (motion off) or paused (inactive or hidden).</param>
    /// <param name="offset">Scroll offset.</param>
    /// <param name="range">Scroll range.</param>
    /// <param name="wraps">Jumps back to the top observed since the demo was built.</param>
    /// <param name="fadeDrawn">Whether the edge-fade mask is drawn (off: contrast themes, transparency off and similar).</param>
    /// <param name="topFaded">Whether the drawn mask fades the top edge.</param>
    /// <param name="bottomFaded">Whether the drawn mask fades the bottom edge.</param>
    /// <returns>Token.</returns>
    public static string Status(FirstRunAutoScrollState state, double offset, double range, int wraps, bool fadeDrawn, bool topFaded, bool bottomFaded)
    {
        var name = state switch
        {
            FirstRunAutoScrollState.Running => "running",
            FirstRunAutoScrollState.Held => "held",
            _ => "paused",
        };
        var position = offset < 1 ? "top" : offset >= range - 1 ? "end" : "mid";
        var fade = !fadeDrawn ? "off" : topFaded && bottomFaded ? "top+bottom" : topFaded ? "top" : bottomFaded ? "bottom" : "none";
        return string.Create(CultureInfo.InvariantCulture, $"scroll={name} pos={position} wraps={wraps} fade={fade}");
    }

    /// <summary>Whether a new offset is the jump back to the top (the list wrapped) rather than forward motion.</summary>
    /// <param name="previous">Offset before the tick.</param>
    /// <param name="next">Offset after the tick.</param>
    /// <returns>Whether it wrapped.</returns>
    public static bool Wrapped(double previous, double next) => next < previous - 1;
}

/// <summary>The infinite-scroll demo's clock state (<see cref="FirstRunAutoScroll.Status"/>).</summary>
public enum FirstRunAutoScrollState
{
    /// <summary>Scrolling: the visible, loaded, foreground slide with motion allowed.</summary>
    Running,
    /// <summary>Held at the top: animations are off (Windows Animation effects or in-app Reduce Motion).</summary>
    Held,
    /// <summary>Stopped where it is: the slide isn't the visible one, or the window is hidden or in the background.</summary>
    Paused,
}
#endregion

#region Demo rows
/// <summary>A demo rankings row for the real leaderboard row control (inert: no destination).</summary>
/// <param name="Ranking">Sample.</param>
/// <param name="SlideId">Slide (for the raw automation ID).</param>
public sealed record FirstRunDemoRankingRow(FirstRunDemoRanking Ranking, string SlideId) : ILeaderboardRankingRow
{
    /// <inheritdoc />
    public string RankText => ScoreFormatting.Rank(Ranking.Rank);
    /// <inheritdoc />
    public string Name => Ranking.DisplayName;
    /// <inheritdoc />
    public bool IsSelected => Ranking.IsPlayer;
    /// <inheritdoc />
    public LeaderboardSection? Section { get; init; }
    /// <inheritdoc />
    public AppRoute? Route => null;
    /// <inheritdoc />
    public string AutomationId => $"fst.first-run.demo.{SlideId}.row.{Ranking.Rank}";
    /// <inheritdoc />
    public string Announcement => $"{RankText}, {Name}, {RatingText}";
    /// <inheritdoc />
    public string SongsText => "";
    /// <inheritdoc />
    public string RatingText => Ranking.RatingLabel;
    /// <inheritdoc />
    public string BayesianText => "";
}

/// <summary>A demo score row for the real leaderboard row control (inert: no destination).</summary>
/// <param name="Rank">Rank.</param>
/// <param name="DisplayName">Player (empty for Score History rows, which show a date instead).</param>
/// <param name="ScoreValue">Score.</param>
/// <param name="AccuracyExpanded">Accuracy in ten-thousandths of a percent.</param>
/// <param name="IsFullCombo">Full combo.</param>
/// <param name="StarCount">Stars (6 = gold).</param>
/// <param name="SeasonNumber">Season.</param>
/// <param name="SlideId">Slide (for raw automation IDs).</param>
public sealed record FirstRunDemoScoreRow(int Rank, string DisplayName, long ScoreValue, double AccuracyExpanded, bool IsFullCombo,
    int StarCount, int SeasonNumber, string SlideId) : ILeaderboardScoreRow
{
    /// <inheritdoc />
    public string RankText => ScoreFormatting.Rank(Rank);
    /// <inheritdoc />
    public string Name => DisplayName;
    /// <inheritdoc />
    public bool IsSelected { get; init; }
    /// <inheritdoc />
    public LeaderboardSection? Section { get; init; }
    /// <inheritdoc />
    public AppRoute? Route => null;
    /// <inheritdoc />
    public string AutomationId => $"fst.first-run.demo.{SlideId}.row.{Rank}";
    /// <inheritdoc />
    public string Announcement => $"{RankText}, {Name}, {Score}";
    /// <inheritdoc />
    public string Season => "S" + SeasonNumber.ToString(CultureInfo.CurrentCulture);
    /// <inheritdoc />
    public string Score => ScoreFormatting.Score(ScoreValue);
    /// <inheritdoc />
    public string Accuracy => ScoreFormatting.Accuracy(AccuracyExpanded);
    /// <inheritdoc />
    public bool HasAccuracy => true;
    /// <inheritdoc />
    public double AccuracyValue => AccuracyExpanded;
    /// <inheritdoc />
    public string BadgeAutomationId => $"fst.first-run.demo.{SlideId}.accuracy.{Rank}";
}
#endregion

#region Demo content
/// <summary>Real-control content for the first-run demos (data the shared page controls render).</summary>
public static class FirstRunDemoContent
{
    /// <summary>Web <c>TopScoresDemo</c> entries (rank, name, score, accuracy, FC, stars).</summary>
    public static IReadOnlyList<FirstRunDemoScoreRow> TopScores(string slideId) => Measure(
    [
        new(1, "AceSolo", 486500, 1000000, true, 6, 12, slideId), new(2, "RiffMaster", 412300, 980000, false, 5, 12, slideId),
        new(3, "ChordKing", 347100, 970000, false, 5, 11, slideId), new(4, "PickSlayer", 289600, 960000, false, 5, 11, slideId),
    ]);

    /// <summary>
    /// The selected player's own scores as the real Score History rows (web <c>ViewAllDemo</c>/<c>ScoreListDemo</c>: plays
    /// today and 7, 21, 35 and 56 days ago, best first and highlighted). They show the play date instead of a rank.
    /// </summary>
    /// <param name="slideId">Slide (row automation IDs).</param>
    /// <param name="count">Rows (at most five).</param>
    /// <param name="today">Date of the newest play.</param>
    /// <param name="currentSeason">Catalogue season (the two newest plays; older plays fall in earlier seasons).</param>
    /// <returns>Rows sharing one column plan.</returns>
    public static IReadOnlyList<ScoreHistoryListRow> History(string slideId, int count, DateTimeOffset today, int currentSeason)
    {
        int[] days = [0, 7, 21, 35, 56];
        long[] scores = [486500, 412300, 347100, 289600, 218400];
        int[] accuracy = [1000000, 990000, 970000, 950000, 880000];
        int[] stars = [6, 5, 5, 5, 4];
        var season = Math.Max(1, currentSeason);
        var rows = Enumerable.Range(0, Math.Clamp(count, 0, scores.Length)).Select(i => new ScoreHistoryListRow(
            Point(today.AddDays(-days[i]), scores[i], accuracy[i], i == 0, stars[i], i < 2 ? season : Math.Max(1, season - 1 - (i % 2))), i == 0)
        {
            RowIdPrefix = $"fst.first-run.demo.{slideId}.row.",
        }).ToList();
        var section = LeaderboardColumns.Measure(rows);
        return [.. rows.Select(r => r with { Section = section })];
    }

    /// <summary>
    /// A demo's control census for UI tests (UIA HelpText of its raw-view peer): the distinct type names of the controls it
    /// is built from, sorted ordinally, e.g. <c>controls=CardHeader+LeaderboardEntryRow+SongScoreHistoryChart</c>.
    /// </summary>
    /// <param name="types">Control type names (duplicates allowed).</param>
    /// <returns>Census text; <c>controls=</c> when empty.</returns>
    public static string ControlCensus(IEnumerable<string> types) =>
        "controls=" + string.Join('+', types.Where(t => t.Length > 0).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal));

    /// <summary>The Song Detail chart's song (the guide's chart model never reads the service).</summary>
    public const string ChartSongId = "first-run-demo";

    /// <summary>The Song Detail chart's chart (web <c>ChartDemo</c>/<c>BarSelectDemo</c> show Lead).</summary>
    public const Instrument ChartInstrument = Instrument.Lead;

    /// <summary>
    /// The Song Detail chart's sample plays as service history rows (web <c>ChartDemo</c>/<c>BarSelectDemo</c>: two days
    /// ago, yesterday, today), for the real Score History model behind the guide's real chart (issue #380).
    /// </summary>
    /// <param name="today">Date of the newest play.</param>
    /// <returns>Plays, oldest first.</returns>
    public static IReadOnlyList<ScoreHistoryEntry> ChartPlays(DateTimeOffset today) =>
    [
        .. FirstRunDemos.BarSelectBars.Select((bar, i) => new ScoreHistoryEntry
        {
            SongId = ChartSongId,
            Instrument = ChartInstrument.ServiceId(),
            NewScore = bar.Score,
            Accuracy = bar.Accuracy * ScoreHistoryPoint.AccuracyScale,
            IsFullCombo = bar.FullCombo,
            Stars = bar.FullCombo ? 6 : 5,
            ScoreAchievedAt = today.AddDays(i - (FirstRunDemos.BarSelectBars.Count - 1)).ToString("o", CultureInfo.InvariantCulture),
        }),
    ];

    /// <summary>The real Score History model over <see cref="ChartPlays"/> (loaded, no bar selected).</summary>
    /// <param name="today">Date of the newest play.</param>
    /// <param name="time">Clock for the model's status presenter.</param>
    /// <returns>Model.</returns>
    public static SongScoreHistoryViewModel ChartModel(DateTimeOffset today, TimeProvider time) =>
        SongScoreHistoryViewModel.Demo(ChartSongId, ChartInstrument, ChartPlays(today), time);

    /// <summary>A sample play.</summary>
    /// <param name="date">Play date.</param>
    /// <param name="score">Score.</param>
    /// <param name="accuracy">Accuracy in ten-thousandths of a percent.</param>
    /// <param name="fullCombo">Full combo.</param>
    /// <param name="stars">Stars.</param>
    /// <param name="season">Season, if shown.</param>
    /// <returns>Point.</returns>
    private static ScoreHistoryPoint Point(DateTimeOffset date, long score, double accuracy, bool fullCombo, int stars, int? season) =>
        new(new ScoreHistoryEntry { NewScore = score, Accuracy = accuracy, IsFullCombo = fullCombo, Stars = stars, Season = season }, date);

    /// <summary>
    /// The web <c>pulseWrap</c> accent-blue ring (#2D82E6, peak 0.7) around a demo's View All / View Full Leaderboard
    /// button and linked Statistics tiles, drawn by the Shop pulse ring so it shares its clock and motion gating.
    /// </summary>
    public static SongRowShopPulse ViewAllPulse { get; } = new(0xFF2D82E6, 0.7f);

    /// <summary>Ranking rows sharing one column plan.</summary>
    /// <param name="rankings">Samples.</param>
    /// <param name="slideId">Slide.</param>
    /// <returns>Rows.</returns>
    public static IReadOnlyList<FirstRunDemoRankingRow> Rankings(IEnumerable<FirstRunDemoRanking> rankings, string slideId)
    {
        var rows = rankings.Select(r => new FirstRunDemoRankingRow(r, slideId)).ToList();
        var section = LeaderboardColumns.Measure(rows);
        return [.. rows.Select(r => r with { Section = section })];
    }

    /// <summary>Gives score rows one column plan (issue #37).</summary>
    /// <param name="rows">Rows.</param>
    /// <returns>Rows with the shared section.</returns>
    private static IReadOnlyList<FirstRunDemoScoreRow> Measure(IReadOnlyList<FirstRunDemoScoreRow> rows)
    {
        var section = LeaderboardColumns.Measure(rows);
        return [.. rows.Select(r => r with { Section = section })];
    }

    /// <summary>
    /// The real Songs metadata pills for a web <c>MetadataDemo</c> layout (<see cref="SongMetadataPolicy.Fields"/>
    /// formatting: score, accuracy tint or FC, percentile tier, stars, season and intensity).
    /// </summary>
    /// <param name="metadata">Sample.</param>
    /// <param name="layout">Two-pill layout.</param>
    /// <returns>Fields in layout order.</returns>
    public static IReadOnlyList<SongMetadataField> MetadataFields(FirstRunDemoMetadata metadata, FirstRunDemoMetadataLayout layout)
    {
        var scoreText = ScoreFormatting.Score(metadata.Score);
        var score = new SongMetadataField(MetadataField.Score, scoreText, $"Score {scoreText}");
        var accuracyText = ScoreFormatting.Accuracy(metadata.Accuracy);
        var accuracy = metadata.FullCombo
            ? new SongMetadataField(MetadataField.Percentage, $"{accuracyText} FC", $"Full combo, accuracy {accuracyText}") { FullCombo = true }
            : new SongMetadataField(MetadataField.Percentage, accuracyText, $"Accuracy {accuracyText}") { Tint = ScoreFormatting.AccuracyTint(metadata.Accuracy) };
        var top = PercentileTop(metadata.Percentile);
        var percentile = new SongMetadataField(MetadataField.Percentile, metadata.Percentile, metadata.Percentile)
        {
            Percentile = top <= 1 ? SongPercentileTier.TopOne : top <= 5 ? SongPercentileTier.TopFive : SongPercentileTier.Ordinary,
        };
        var gold = metadata.Stars >= 6;
        var count = gold ? 5 : Math.Clamp(metadata.Stars, 1, 5);
        var stars = new SongMetadataField(MetadataField.Stars, new string('★', count), gold ? $"{count} gold stars" : $"{count} stars") { Stars = (count, gold) };
        var seasonNumber = metadata.Season.ToString(CultureInfo.CurrentCulture);
        var season = new SongMetadataField(MetadataField.Season, $"S{seasonNumber}", $"Season {seasonNumber}");
        var intensity = new SongMetadataField(MetadataField.Intensity, "", $"Song intensity {DifficultyScale.BarsForRaw(metadata.Difficulty)} of 7")
        {
            IntensityRaw = metadata.Difficulty,
        };
        return layout switch
        {
            FirstRunDemoMetadataLayout.ScoreAccuracy => [score, accuracy],
            FirstRunDemoMetadataLayout.StarsDifficulty => [stars, intensity],
            FirstRunDemoMetadataLayout.PercentileSeason => [percentile, season],
            FirstRunDemoMetadataLayout.ScoreStars => [score, stars],
            FirstRunDemoMetadataLayout.AccuracyDifficulty => [accuracy, intensity],
            _ => [percentile, score],
        };
    }

    /// <summary>The Statistics top-songs percentile pill (the real Songs percentile pill with its tier).</summary>
    /// <param name="slot">Zero-based slot.</param>
    /// <returns>Field.</returns>
    public static SongMetadataField TopSongPill(int slot)
    {
        var text = FirstRunTopSongsDemo.Pill(slot);
        var value = FirstRunDemos.TopSongPercentile(slot);
        return new SongMetadataField(MetadataField.Percentile, text, text)
        {
            Percentile = value <= 1 ? SongPercentileTier.TopOne : value <= 5 ? SongPercentileTier.TopFive : SongPercentileTier.Ordinary,
        };
    }

    /// <summary>Percent from a "Top N%" label.</summary>
    /// <param name="label">Label.</param>
    /// <returns>Percent, or 100 when unreadable.</returns>
    private static double PercentileTop(string label)
    {
        var digits = new string([.. label.Where(c => char.IsDigit(c) || c == '.')]);
        return double.TryParse(digits, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : 100;
    }

    /// <summary>The infinite-scroll demo's six cards (web <c>InfiniteScrollDemo</c> templates, in order).</summary>
    public static IReadOnlyList<FirstRunSuggestionTemplate> ScrollTemplates { get; } =
    [
        FirstRunDemos.SuggestionTemplates[0], FirstRunDemos.SuggestionTemplates[1],
        new("stale_vocals_1", "Play Tap Vocals This Season", "Songs you haven't played on Tap Vocals this season.", "Tap Vocals"),
        FirstRunDemos.SuggestionTemplates[2], FirstRunDemos.SuggestionTemplates[3],
        new("variety_pack", "Variety Pack", "Two different artists for variety.", ""),
    ];

    /// <summary>A template's header instrument (web <c>InstrumentHeader</c> beside the card title), if any.</summary>
    /// <param name="template">Template.</param>
    /// <returns>Instrument, or <see langword="null"/> for mixed-instrument cards.</returns>
    public static Instrument? HeaderInstrument(FirstRunSuggestionTemplate template) => template.Key switch
    {
        "unfc_guitar" => Instrument.Lead,
        "pct_push_bass" => Instrument.Bass,
        "stale_vocals_1" => Instrument.Vocals,
        "unplayed_drums" => Instrument.Drums,
        _ => null,
    };

    /// <summary>
    /// The real Suggestions row presentation for demo row <paramref name="index"/> of a template (web
    /// <c>CategoryCardDemo</c> <c>songMeta</c>): Lead accuracy, Bass percentile, per-row instrument and so on.
    /// </summary>
    /// <param name="template">Template.</param>
    /// <param name="title">Song title.</param>
    /// <param name="artist">Song subtitle.</param>
    /// <param name="index">Zero-based row.</param>
    /// <returns>Presentation.</returns>
    public static SuggestionRowPresentation Suggestion(FirstRunSuggestionTemplate template, string title, string artist, int index)
    {
        var layout = SuggestionRowPresentation.LayoutFor(template.Key);
        Instrument[] rotation = [Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals];
        var instrument = HeaderInstrument(template) ?? (template.Key == "near_fc_any" ? rotation[index % rotation.Length] : null);
        var percent = 100 - index * 2;
        return new SuggestionRowPresentation
        {
            Layout = layout,
            Title = title,
            Subtitle = artist,
            Instrument = instrument,
            AccuracyText = layout == SuggestionRowLayout.UnfcAccuracy ? $"{percent}%" : null,
            AccuracyExpanded = layout == SuggestionRowLayout.UnfcAccuracy ? percent * 10000.0 : null,
            PercentileText = layout == SuggestionRowLayout.Percentile ? $"Top {3 + index}%" : null,
            PercentileTier = layout == SuggestionRowLayout.Percentile && 3 + index <= 5 ? PercentileTier.Top5 : PercentileTier.Default,
            AccessibleName = title,
        };
    }

    /// <summary>The experimental metrics the demo radio list cycles (the real Leaderboards metric labels).</summary>
    public static IReadOnlyList<RankingMetric> Metrics { get; } =
        [RankingMetric.Adjusted, RankingMetric.Weighted, RankingMetric.FcRate, RankingMetric.MaxScore];

    /// <summary>Web <c>OverviewDemo</c>/<c>DrillDownDemo</c> sample: 142 songs, 38 FCs (26.8%), 12 gold stars, 96.2%, best #4.</summary>
    private static readonly PlayerStats OverallSample = new(142, 38, 26.8, 12, 0, 962000, 4, null, null);

    /// <summary>
    /// Web <c>InstrumentBreakdownDemo</c> Lead sample (98 scored songs: 24 FCs, 8 gold and 15 five-star scores, accuracy
    /// 90.0–99.7%, best rank #1).
    /// </summary>
    private static readonly PlayerStats LeadSample = new(98, 24, 24.4, 8, 15, 948500, 1, null, Instrument.Lead);

    /// <summary>
    /// The real Statistics stat tiles a demo shows (Overview, the drill-down order of web <c>DrillDownDemo</c>, or the Lead
    /// breakdown), with the page's labels, tints and Songs links.
    /// </summary>
    /// <param name="slideId">Slide.</param>
    /// <returns>Tiles (empty for other slides).</returns>
    public static IReadOnlyList<PlayerStatTile> StatTiles(string? slideId)
    {
        static string N(int n) => n.ToString("N0", CultureInfo.CurrentCulture);
        PlayerStatTile Played(PlayerStats s, Instrument? i) => new("songs-played", "Songs Played", N(s.SongsPlayed),
            link: new PlayerStatLink.Songs(new SongsStatPreset(i, SongScoreFilterKind.HasScores)));
        PlayerStatTile Fcs(PlayerStats s, Instrument? i) => new("full-combos", "Full Combos", s.FullComboText,
            link: new PlayerStatLink.Songs(new SongsStatPreset(i, SongScoreFilterKind.HasFCs)));
        PlayerStatTile Gold(PlayerStats s) => new("gold-stars", "Gold Stars", N(s.GoldStarCount), PlayerStatTint.Gold);
        PlayerStatTile Accuracy(PlayerStats s) => new("avg-accuracy", "Avg Accuracy", s.AverageAccuracyText);
        PlayerStatTile Best(PlayerStats s) => new("best-rank", "Best Rank", s.BestRankText);
        var o = OverallSample;
        var l = LeadSample;
        return slideId switch
        {
            "statistics-overview" => [Played(o, null), Fcs(o, null), Gold(o), Accuracy(o), Best(o)],
            "statistics-drill-down" => [Played(o, null), Gold(o), Accuracy(o), Fcs(o, null)],
            "statistics-instrument-breakdown" =>
            [
                Played(l, Instrument.Lead), Fcs(l, Instrument.Lead), Gold(l),
                new("stars-5", SongScoreBandFilter.StarsLabel(5), N(l.FiveStarCount),
                    link: new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Lead, null, Stars: 5))),
                Accuracy(l), Best(l),
            ],
            _ => [],
        };
    }

    /// <summary>Whether a demo tile pulses (web <c>DrillDownDemo</c> wraps only the linked tiles in <c>pulseWrap</c>).</summary>
    /// <param name="slideId">Slide.</param>
    /// <param name="tile">Tile.</param>
    /// <returns><see langword="true"/> for a linked tile on the drill-down slide.</returns>
    public static bool TilePulses(string? slideId, PlayerStatTile tile) => slideId == "statistics-drill-down" && tile.Link is not null;

    /// <summary>Web <c>PercentileDemo</c> buckets (Top 1% … Top 100%).</summary>
    public static IReadOnlyList<PlayerPercentileBucket> PercentileBuckets { get; } =
        [new(1, 3), new(5, 12), new(10, 28), new(25, 55), new(50, 89), new(100, 142)];

    /// <summary>The rivalry category key for a demo category title (<c>"Closest Battles"</c> → <c>closest_battles</c>).</summary>
    /// <param name="title">Demo category title (<see cref="FirstRunDemos.RivalDetailCategories"/> key).</param>
    /// <returns>Category key for <see cref="RivalCategorization"/>.</returns>
    public static string RivalCategoryKey(string title) => title.Trim().ToLowerInvariant().Replace(' ', '_');

    /// <summary>
    /// A demo rival as the real Rivals row (web <c>RivalRow</c>): the row counts the songs the player leads and trails,
    /// which are the rival's behind and ahead counts.
    /// </summary>
    /// <param name="rival">Sample rival.</param>
    /// <param name="direction">List half.</param>
    /// <returns>Row item (inert in the demo).</returns>
    public static RivalRowItem RivalRow(FirstRunDemoRival rival, RivalDirection direction) =>
        new(rival.AccountId, rival.DisplayName, direction, rival.BehindCount, rival.AheadCount, null,
            new AppRoute.RivalDetail(rival.AccountId, rival.DisplayName));

    /// <summary>The Rivals instrument sections the demo shows (web <c>RivalsInstrumentsDemo</c> pools by chart).</summary>
    /// <param name="key">Pool key (<see cref="FirstRunDemos.InstrumentRivals"/>).</param>
    /// <returns>Chart for the section header.</returns>
    public static Instrument RivalInstrument(string key) => key switch
    {
        "Drums" => Instrument.Drums,
        "Vocals" => Instrument.Vocals,
        "Bass" => Instrument.Bass,
        _ => Instrument.Lead,
    };
}
#endregion
