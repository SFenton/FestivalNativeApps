using System.Globalization;
using System.Text.Json;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongsHasFcSortTests
{
    private static Song S(string id, string title) =>
        JsonSerializer.Deserialize<Song>($$$"""{"songId":"{{{id}}}","title":"{{{title}}}","artist":"A","year":2020,"difficulty":{"guitar":2}}""")!;

    private static readonly IReadOnlyList<Song> Songs = [S("fc", "Delta"), S("nofc", "Charlie"), S("none", "Alpha"), S("zero", "Bravo")];

    private static ChartScoreFacts? Facts(string id, Instrument chart) => (id, chart) switch
    {
        ("fc", Instrument.Lead) => new ChartScoreFacts(100, true),
        ("nofc", Instrument.Lead) => new ChartScoreFacts(90, false),
        ("zero", Instrument.Lead) => new ChartScoreFacts(0, true),
        _ => null,
    };

    private static SongListInputs Input(bool ascending = true, Instrument? chart = Instrument.Lead, bool hasPlayer = true) => new()
    {
        Songs = Songs,
        Sort = SongSortMode.HasFC,
        Ascending = ascending,
        Filter = new SongFilter(chart),
        HasPlayer = hasPlayer,
        Scores = Facts,
    };

    [Fact]
    public void HasFc_IsInTheMenuAfterItemShop()
    {
        Assert.Equal([SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration, SongSortMode.Shop, SongSortMode.HasFC],
            SongSortModeInfo.ModesFor(hasPlayer: false, hasChart: true, hideShop: false));
        // Web Sort modal: Last Played with a player; the instrument modes only with a player and one chart.
        Assert.Equal([SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration, SongSortMode.HasFC, SongSortMode.LastPlayed],
            SongSortModeInfo.ModesFor(hasPlayer: true, hasChart: false, hideShop: true));
        var full = SongSortModeInfo.ModesFor(hasPlayer: true, hasChart: true, hideShop: false);
        Assert.Equal(SongSortModeInfo.InstrumentModes, full.Skip(7));
        Assert.True(SongSortMode.MaxScoreDiff.IsInstrumentMode());
        Assert.False(SongSortMode.LastPlayed.IsInstrumentMode());
        Assert.Equal("Has FC", SongSortMode.HasFC.Label());
    }

    [Theory]
    [InlineData(SongSortMode.Score)]
    [InlineData(SongSortMode.Stars)]
    [InlineData(SongSortMode.Percentile)]
    public void MetricSorts_FollowTheWebComparator(SongSortMode mode)
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var songs = new List<Song>
        {
            new() { SongId = "a", Title = "Alpha", Artist = "x", Difficulty = new SongDifficulty { Guitar = 3 }, MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 } },
            new() { SongId = "b", Title = "Beta", Artist = "x", Difficulty = new SongDifficulty { Guitar = 5 }, MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 } },
            new() { SongId = "c", Title = "Gamma", Artist = "x", Difficulty = new SongDifficulty { Guitar = 1 } },
        };
        var details = new Dictionary<string, SongScoreDetail>
        {
            ["a"] = new(900, Stars: 5, Rank: 50, TotalEntries: 100, LastPlayedAt: "2026-09-01"),
            ["b"] = new(500, Stars: 3, Rank: 1, TotalEntries: 100, LastPlayedAt: "2026-09-20"),
        };
        SongListInputs Inputs(SongSortMode sort, bool ascending, Instrument? chart = Instrument.Lead) => new()
        {
            Songs = songs, Sort = sort, Ascending = ascending, HasPlayer = true, Filter = new SongFilter(chart),
            Details = (id, _) => details.GetValueOrDefault(id),
        };
        var ascending = SongListPipeline.Run(Inputs(mode, true)).Sections.Single().Songs.Select(r => r.SongId).ToList();
        var expected = mode == SongSortMode.Percentile ? new[] { "b", "a", "c" } : ["b", "a", "c"];
        Assert.Equal(expected, ascending);
        // Descending reverses everything, so the unscored row comes first (web cmp * dir).
        Assert.Equal(Enumerable.Reverse(expected), SongListPipeline.Run(Inputs(mode, false)).Sections.Single().Songs.Select(r => r.SongId));
        // Without a chart filter an instrument sort falls back to title order with sections.
        var noChart = SongListPipeline.Run(Inputs(mode, true, chart: null));
        Assert.Equal(SongSortMode.Title, noChart.EffectiveSort);
    }

    [Fact]
    public void MaxScoreSorts_KeepScoredRowsFirstAndLastPlayedUsesTheLatestChart()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var songs = new List<Song>
        {
            new() { SongId = "a", Title = "Alpha", Artist = "x", Difficulty = new SongDifficulty { Guitar = 3 }, MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 } },
            new() { SongId = "b", Title = "Beta", Artist = "x", Difficulty = new SongDifficulty { Guitar = 5 }, MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 } },
            new() { SongId = "c", Title = "Gamma", Artist = "x", Difficulty = new SongDifficulty { Guitar = 1 } },
        };
        var details = new Dictionary<(string, Instrument), SongScoreDetail>
        {
            [("a", Instrument.Lead)] = new(900, LastPlayedAt: "2026-09-01"),
            [("b", Instrument.Lead)] = new(500, LastPlayedAt: "2026-09-02"),
            [("c", Instrument.Bass)] = new(10, LastPlayedAt: "2026-09-30"),
        };
        SongListInputs Inputs(SongSortMode sort, bool ascending, Instrument? chart) => new()
        {
            Songs = songs, Sort = sort, Ascending = ascending, HasPlayer = true, Filter = new SongFilter(chart),
            Details = (id, i) => details.GetValueOrDefault((id, i)),
        };
        string[] Order(SongSortMode sort, bool ascending, Instrument? chart = Instrument.Lead) =>
            [.. SongListPipeline.Run(Inputs(sort, ascending, chart)).Sections.SelectMany(x => x.Songs).Select(r => r.SongId)];
        Assert.Equal(["b", "a", "c"], Order(SongSortMode.MaxScorePercent, true));
        Assert.Equal(["a", "b", "c"], Order(SongSortMode.MaxScorePercent, false));
        Assert.Equal(["b", "a", "c"], Order(SongSortMode.MaxScoreDiff, true));
        Assert.Equal(["c", "a", "b"], Order(SongSortMode.Intensity, true));
        Assert.Equal(["b", "a", "c"], Order(SongSortMode.Intensity, false));
        // Last Played without a chart takes each song's latest play across visible charts (Gamma's Bass play).
        Assert.Equal(["a", "b", "c"], Order(SongSortMode.LastPlayed, true, chart: null));
        Assert.Equal(["c", "b", "a"], Order(SongSortMode.LastPlayed, false, chart: null));
        // Without a player the player sorts pause to title order.
        Assert.Equal(SongSortMode.Title, SongListPipeline.Run(Inputs(SongSortMode.Score, true, Instrument.Lead) with { HasPlayer = false }).EffectiveSort);
    }

    [Fact]
    public void HasFc_ScoredFirstThenNonFcBeforeFc()
    {
        var result = SongListPipeline.Run(Input());
        Assert.Equal(SongSortMode.HasFC, result.EffectiveSort);
        Assert.Equal(["No FC", "FC", "No Score"], result.Sections.Select(s => s.Label));
        Assert.Equal(["nofc", "fc", "none", "zero"], result.Sections.SelectMany(s => s.Songs).Select(s => s.SongId));
    }

    [Fact]
    public void HasFc_DescendingReversesEverything()
    {
        var ids = SongListPipeline.Run(Input(ascending: false)).Sections.SelectMany(s => s.Songs).Select(s => s.SongId);
        Assert.Equal(["zero", "none", "fc", "nofc"], ids);
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void HasFc_WithoutChartOrPlayer_IsTitleOrderInOneUnlabeledSection(bool hasChart, bool hasPlayer)
    {
        var result = SongListPipeline.Run(Input(chart: hasChart ? Instrument.Lead : null, hasPlayer: hasPlayer));
        Assert.Equal([""], result.Sections.Select(s => s.Label));
        Assert.Equal(["none", "zero", "nofc", "fc"], result.Sections[0].Songs.Select(s => s.SongId));
    }

    [Fact]
    public void HasFc_HiddenChartFallsBackToTitleOrder()
    {
        var result = SongListPipeline.Run(Input() with { Visible = [Instrument.Bass] });
        Assert.Equal(["none", "zero", "nofc", "fc"], result.Sections.SelectMany(s => s.Songs).Select(s => s.SongId));
    }
}

public class SongsFilterButtonTests
{
    private static async Task<(FestivalSession Session, SongsViewModel Vm)> Loaded(AppSettings settings)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var session = service.Session(settings: settings);
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        return (session, vm);
    }

    [Fact]
    public async Task Filter_AlwaysAvailableWithGeneralAnonymous()
    {
        var (session, vm) = await Loaded(new AppSettings());
        Assert.True(vm.ShowFilterButton);
        Assert.False(vm.IsFilterActive);
        session.UpdateSettings(s => s with { GeneralFilter = new SongGeneralFilter { ExcludedDurationBuckets = [0] } });
        Assert.True(vm.ShowFilterButton);
        Assert.True(vm.IsFilterActive);
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Bass) });
        Assert.True(vm.ShowFilterButton);
        Assert.True(vm.IsFilterActive);
        session.UpdateSettings(s => s with { SongFilter = SongFilter.None, SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        Assert.True(vm.ShowFilterButton);
    }
}

public class SongsShopPulseTests
{
    [Fact]
    public void Pulse_ColoursAndPrecedence()
    {
        Assert.Null(SongRowShopPulse.For(false, null));
        Assert.Equal(new SongRowShopPulse(0xFF2ECC71, 0.7f), SongRowShopPulse.For(true, null));
        Assert.Equal(new SongRowShopPulse(0xFFFFD700, 0.75f), SongRowShopPulse.For(true, ShopHighlight.New));
        Assert.Same(SongRowShopPulse.Leaving, SongRowShopPulse.For(true, ShopHighlight.LeavingTomorrow));
        Assert.Equal(TimeSpan.FromSeconds(2), SongRowShopPulse.Cycle);
    }

    [Theory]
    [InlineData(0f, 0f)]
    [InlineData(0.25f, 0.5f)]
    [InlineData(0.5f, 1f)]
    [InlineData(0.75f, 0.5f)]
    [InlineData(1f, 0f)]
    [InlineData(-1f, 0f)]
    public void Level_BreathesSymmetrically(float t, float expected) =>
        Assert.Equal(expected, SongRowShopPulse.Level(t), 3);

    [Fact]
    public void EaseInOut_IsSlowAtTheEnds()
    {
        Assert.True(SongRowShopPulse.EaseInOut(0.1f) < 0.05f);
        Assert.True(SongRowShopPulse.EaseInOut(0.9f) > 0.95f);
    }

    [Fact]
    public async Task Rows_PulseGreenGoldRed_OffWhenHighlightingDisabledOrShopHidden()
    {
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(SongsWire.Offer("s1", "Alpha"), SongsWire.Offer("s2", "Beta", isNew: true),
            SongsWire.Offer("s3", "Électrique", leaving: true)));
        var session = service.Session();
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        SongRowItem Row(string id) => vm.Sections.SelectMany(s => s.Rows).Single(r => r.Song.SongId == id);
        Assert.Equal([SongRowShopPulse.InShop, SongRowShopPulse.New, SongRowShopPulse.Leaving], new[] { "s1", "s2", "s3" }.Select(id => Row(id).Pulse));
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        Assert.All(vm.Sections.SelectMany(s => s.Rows), r => Assert.Null(r.Pulse));
        session.UpdateSettings(s => s with { DisableShopHighlighting = false, HideShop = true });
        Assert.All(vm.Sections.SelectMany(s => s.Rows), r => Assert.Null(r.Pulse));
    }
}

public class ShopGridMetricsTests
{
    [Theory]
    [InlineData(480, 2, 235)]
    [InlineData(599, 2, 294)]
    [InlineData(600, 3, 193)]
    [InlineData(860, 4, 207)]
    [InlineData(1100, 5, 200)]
    [InlineData(2400, 5, 200)]
    [InlineData(0, 2, 1)]
    public void Columns_AndSquareTiles(double width, int columns, double tile)
    {
        Assert.Equal(columns, ShopGridMetrics.Columns(width));
        Assert.Equal(tile, ShopGridMetrics.TileSize(width));
        Assert.Equal(Math.Min(width, 1040), ShopGridMetrics.ContentWidth(width));
    }
}
