using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongScoreBandFilterTests
{
    [Theory]
    [InlineData(1, 100, 1)]
    [InlineData(30, 100, 30)]
    [InlineData(31, 100, 40)]
    [InlineData(4, 200, 2)]
    [InlineData(500, 100, 100)]
    public void Band_FirstThresholdAtOrAbove(int rank, int total, int expected) =>
        Assert.Equal(expected, SongScoreBandFilter.Band(rank, total));

    [Fact]
    public void Band_NoPlacement()
    {
        Assert.Null(SongScoreBandFilter.Band(null, 100));
        Assert.Null(SongScoreBandFilter.Band(0, 100));
        Assert.Null(SongScoreBandFilter.Band(3, null));
    }

    [Fact]
    public void Matches_BandAndStars()
    {
        var top1 = new SongScoreBandFilter(Instrument.Lead, TopPercent: 1);
        Assert.True(top1.IsActive);
        Assert.True(top1.Matches(new SongScoreDetail(100, Rank: 1, TotalEntries: 100)));
        Assert.False(top1.Matches(new SongScoreDetail(100, Rank: 2, TotalEntries: 100)));
        Assert.False(top1.Matches(null));
        var gold = new SongScoreBandFilter(Instrument.Lead, Stars: 6);
        Assert.True(gold.Matches(new SongScoreDetail(1, Stars: 6)));
        Assert.False(gold.Matches(new SongScoreDetail(1, Stars: 5)));
        Assert.False(new SongScoreBandFilter(Instrument.Lead).IsActive);
    }

    [Fact]
    public void Validity_AndLabels()
    {
        Assert.True(new SongScoreBandFilter(Instrument.Bass, 15, 1).IsValid);
        Assert.False(new SongScoreBandFilter(Instrument.Bass, 7).IsValid);
        Assert.False(new SongScoreBandFilter(Instrument.Bass, Stars: 7).IsValid);
        Assert.False(new SongScoreBandFilter((Instrument)42, 1).IsValid);
        Assert.Equal("Top 5%", SongScoreBandFilter.BandLabel(5));
        Assert.Equal(["Gold Stars", "5 Stars", "1 Star"], new[] { 6, 5, 1 }.Select(SongScoreBandFilter.StarsLabel));
    }

    [Fact]
    public void Presets_SortsAndHints()
    {
        var settings = new AppSettings { SongSort = SongSortMode.Year, SongSortAscending = false };
        var pct = new SongsStatPreset(Instrument.Lead, null, TopPercent: 5).ApplyTo(settings);
        Assert.Equal(SongSortMode.Year, pct.SongSort);
        Assert.True(pct.SongSortAscending);
        Assert.False(pct.PlayerScoreFilter.HasChecks);
        var stars = new SongsStatPreset(Instrument.Lead, null, Stars: 6).ApplyTo(pct);
        // A later preset cleans the earlier bucket choice first (web cleanFilters).
        Assert.Empty(stars.PlayerScoreFilter.ExcludedPercentiles);
        // Web instStarsUpdater sorts by Stars; score checks sort by Score (instSongsPlayedUpdater / instFCsUpdater).
        Assert.Equal(SongSortMode.Stars, stars.SongSort);
        Assert.Equal(SongSortMode.Score, new SongsStatPreset(Instrument.Lead, SongScoreFilterKind.HasFCs).ApplyTo(settings).SongSort);
        Assert.Equal(SongSortMode.Title, new SongsStatPreset(null, SongScoreFilterKind.HasFCs).ApplyTo(settings).SongSort);
        Assert.False(new SongsStatPreset(null, SongScoreFilterKind.HasScores).ApplyTo(stars).PlayerScoreFilter.HasBucketChecks);
        Assert.False(new SongsStatPreset(null, null).ApplyTo(stars).PlayerScoreFilter.IsActive);
        Assert.Equal("Opens Lead songs in the Top 5%", new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Lead, null, TopPercent: 5)).Hint);
        Assert.Equal("Opens Lead songs with Gold Stars", new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Lead, null, Stars: 6)).Hint);
    }
}

public class SongsScoreBandTests
{
    internal static async Task<(FestivalSession Session, SongsViewModel Vm)> Loaded(bool player = true, AppSettings? settings = null)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var initial = settings ?? new AppSettings();
        if (player) initial = initial with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") };
        var session = service.Session(settings: initial);
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        return (session, vm);
    }

    internal static List<string> Ids(SongsViewModel vm) => [.. vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId)];

    [Fact]
    public async Task Pipeline_BucketsApplyOnTheSelectedChartOnly()
    {
        var (session, vm) = await Loaded();
        session.UpdateSettings(new SongsStatPreset(Instrument.Lead, null, TopPercent: 1).ApplyTo);
        Assert.Equal(["s1"], Ids(vm));
        Assert.True(vm.IsFilterActive);
        session.UpdateSettings(new SongsStatPreset(Instrument.Lead, null, Stars: 5).ApplyTo);
        Assert.Equal(["s2"], Ids(vm));
        // Buckets stay saved but inert without an instrument (web: instrument-specific filters skip with none).
        session.UpdateSettings(s => s with { SongFilter = SongFilter.None });
        Assert.False(vm.IsFilterActive);
        Assert.Equal(3, vm.ResultCount);

        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Lead), FilterInvalidScores = true });
        // Filter Invalid Scores no longer pauses player filters: scores resolve to valid fallbacks (web substitution).
        Assert.DoesNotContain(vm.Notices, n => n.StartsWith("Player score filters paused", StringComparison.Ordinal));
        session.UpdateSettings(s => s with { FilterInvalidScores = false });
        session.DeselectPlayer();
        Assert.False(session.Settings.PlayerScoreFilter.IsActive);
    }

    [Fact]
    public async Task Pipeline_IgnoresPlayerFiltersWithoutPlayer()
    {
        var (session, vm) = await Loaded(player: false);
        session.UpdateSettings(s => s with
        {
            SongFilter = new SongFilter(Instrument.Lead),
            PlayerScoreFilter = SongPlayerScoreFilter.None.Only(SongBucketKind.Percentile, 1),
        });
        Assert.DoesNotContain(vm.Notices, n => n.Contains("Player score filters", StringComparison.Ordinal));
        Assert.True(vm.ResultCount > 1);
        Assert.False(vm.IsFilterActive);
    }

    [Fact]
    public async Task Pipeline_SeasonAndIntensityBuckets()
    {
        var (session, vm) = await Loaded();
        session.UpdateSettings(s => s with
        {
            SongFilter = new SongFilter(Instrument.Lead),
            PlayerScoreFilter = SongPlayerScoreFilter.None.WithExcluded(SongBucketKind.Season, [9]),
        });
        // Every fixture score is Season 9; hiding it leaves only Lead charts without a score (No Score = 0).
        Assert.DoesNotContain("s1", Ids(vm));
        Assert.DoesNotContain("s2", Ids(vm));
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None.WithExcluded(SongBucketKind.Season, [0]) });
        Assert.Equal(["s1", "s2"], Ids(vm).Order());
        var all = Ids(vm).Count;
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None, SongFilter = new SongFilter(Instrument.Lead, SongBuckets.IntensityKeys) });
        Assert.True(vm.ShowEmpty);
        Assert.Equal("No songs match the filters.", vm.EmptyMessage);
        Assert.True(all > 0);
    }
}
