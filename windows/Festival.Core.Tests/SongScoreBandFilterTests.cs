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
        Assert.False(gold.Matches(null));
        var both = new SongScoreBandFilter(Instrument.Lead, 2, 5);
        Assert.True(both.Matches(new SongScoreDetail(1, Stars: 5, Rank: 2, TotalEntries: 100)));
        Assert.False(both.Matches(new SongScoreDetail(1, Stars: 6, Rank: 2, TotalEntries: 100)));
        Assert.False(new SongScoreBandFilter(Instrument.Lead).IsActive);
    }

    [Fact]
    public void Validity_LabelsAndSanitize()
    {
        Assert.True(new SongScoreBandFilter(Instrument.Bass, 15, 1).IsValid);
        Assert.False(new SongScoreBandFilter(Instrument.Bass, 7).IsValid);
        Assert.False(new SongScoreBandFilter(Instrument.Bass, Stars: 7).IsValid);
        Assert.False(new SongScoreBandFilter((Instrument)42, 1).IsValid);
        Assert.Equal("Top 5%", SongScoreBandFilter.BandLabel(5));
        Assert.Equal(["Gold Stars", "5 Stars", "1 Star"], new[] { 6, 5, 1 }.Select(SongScoreBandFilter.StarsLabel));
        Assert.Null(new AppSettings { ScoreBandFilter = new SongScoreBandFilter(Instrument.Bass, 7) }.Sanitized().ScoreBandFilter);
        Assert.Null(new AppSettings { ScoreBandFilter = new SongScoreBandFilter(Instrument.Bass) }.Sanitized().ScoreBandFilter);
        var kept = new SongScoreBandFilter(Instrument.Bass, 5);
        Assert.Equal(kept, new AppSettings { ScoreBandFilter = kept }.Sanitized().ScoreBandFilter);
        Assert.NotEqual(new AppSettings(), new AppSettings { ScoreBandFilter = kept });
    }

    [Fact]
    public void Presets_BandAndStars()
    {
        var settings = new AppSettings { SongSort = SongSortMode.Year, SongSortAscending = false };
        var pct = new SongsStatPreset(Instrument.Lead, null, TopPercent: 5).ApplyTo(settings);
        Assert.Equal(new SongScoreBandFilter(Instrument.Lead, 5), pct.ScoreBandFilter);
        Assert.Equal(SongSortMode.Year, pct.SongSort);
        Assert.True(pct.SongSortAscending);
        Assert.False(pct.PlayerScoreFilter.IsActive);
        var stars = new SongsStatPreset(Instrument.Lead, null, Stars: 6).ApplyTo(pct);
        Assert.Equal(new SongScoreBandFilter(Instrument.Lead, Stars: 6), stars.ScoreBandFilter);
        // Web instStarsUpdater sorts by Stars; score checks sort by Score (instSongsPlayedUpdater / instFCsUpdater).
        Assert.Equal(SongSortMode.Stars, stars.SongSort);
        Assert.Equal(SongSortMode.Score, new SongsStatPreset(Instrument.Lead, SongScoreFilterKind.HasFCs).ApplyTo(settings).SongSort);
        Assert.Equal(SongSortMode.Title, new SongsStatPreset(null, SongScoreFilterKind.HasFCs).ApplyTo(settings).SongSort);
        Assert.Null(new SongsStatPreset(null, SongScoreFilterKind.HasScores).ApplyTo(stars).ScoreBandFilter);
        Assert.Null(new SongsStatPreset(Instrument.Lead, SongScoreFilterKind.HasScores).ApplyTo(stars).ScoreBandFilter);
        Assert.False(new SongsStatPreset(null, null).ApplyTo(stars).PlayerScoreFilter.IsActive);
        Assert.Equal("Opens Lead songs in the Top 5%", new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Lead, null, TopPercent: 5)).Hint);
        Assert.Equal("Opens Lead songs with Gold Stars", new PlayerStatLink.Songs(new SongsStatPreset(Instrument.Lead, null, Stars: 6)).Hint);
    }
}

public class SongsScoreBandTests
{
    private static async Task<(FestivalSession Session, SongsViewModel Vm)> Loaded(bool player = true)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var initial = new AppSettings();
        if (player) initial = initial with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") };
        var session = service.Session(settings: initial);
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        return (session, vm);
    }

    private static List<string> Ids(SongsViewModel vm) => [.. vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId)];

    [Fact]
    public async Task Pipeline_FiltersOnTheSelectedChartOnly()
    {
        var (session, vm) = await Loaded();
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Lead), ScoreBandFilter = new SongScoreBandFilter(Instrument.Lead, TopPercent: 1) });
        Assert.Equal(["s1"], Ids(vm));
        Assert.True(vm.IsFilterActive);
        session.UpdateSettings(s => s with { ScoreBandFilter = new SongScoreBandFilter(Instrument.Lead, Stars: 5) });
        Assert.Equal(["s2"], Ids(vm));
        var leadOnly = session.Settings with { ScoreBandFilter = null };
        session.UpdateSettings(s => s with { ScoreBandFilter = new SongScoreBandFilter(Instrument.Bass, Stars: 5) });
        var inactive = Ids(vm);
        session.UpdateSettings(_ => leadOnly);
        Assert.Equal(Ids(vm), inactive);

        session.UpdateSettings(s => s with { ScoreBandFilter = new SongScoreBandFilter(Instrument.Lead, Stars: 5), FilterInvalidScores = true });
        Assert.Contains(vm.Notices, n => n.StartsWith("Percentile and star filters paused while Filter Invalid Scores", StringComparison.Ordinal));
        session.UpdateSettings(s => s with { FilterInvalidScores = false });
        session.DeselectPlayer();
        Assert.Null(session.Settings.ScoreBandFilter);
    }

    [Fact]
    public async Task Pipeline_PausesWithoutPlayer()
    {
        var (session, vm) = await Loaded(player: false);
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Lead), ScoreBandFilter = new SongScoreBandFilter(Instrument.Lead, TopPercent: 1) });
        Assert.Contains(vm.Notices, n => n == "Percentile and star filters paused until a player is selected.");
        Assert.True(vm.ResultCount > 1);
    }

    [Fact]
    public async Task Draft_RoundTripsAndResets()
    {
        var (session, vm) = await Loaded();
        session.UpdateSettings(new SongsStatPreset(Instrument.Lead, null, TopPercent: 30).ApplyTo);
        vm.FilterDraft.Begin();
        Assert.True(vm.FilterDraft.ShowScoreBand);
        Assert.Equal(PlayerStatistics.PercentileThresholds.ToList().IndexOf(30) + 1, vm.FilterDraft.PercentileIndex);
        Assert.Equal(0, vm.FilterDraft.StarsIndex);
        Assert.Equal("Any Percentile", vm.FilterDraft.PercentileChoices[0]);
        Assert.Equal("Gold Stars", vm.FilterDraft.StarsChoices[1]);
        vm.FilterDraft.StarsIndex = 2; // 5 stars, applied live
        Assert.Equal(new SongScoreBandFilter(Instrument.Lead, 30, 5), session.Settings.ScoreBandFilter);
        Assert.Equal(["s2"], Ids(vm));
        vm.FilterDraft.InstrumentIndex = 0;
        Assert.False(vm.FilterDraft.ShowScoreBand);
        Assert.Null(session.Settings.ScoreBandFilter);
        session.UpdateSettings(new SongsStatPreset(Instrument.Lead, null, Stars: 6).ApplyTo);
        vm.FilterDraft.Begin();
        Assert.Equal(1, vm.FilterDraft.StarsIndex);
        vm.FilterDraft.ResetCommand.Execute(null);
        Assert.Null(session.Settings.ScoreBandFilter);
        session.UpdateSettings(new SongsStatPreset(Instrument.Lead, null, Stars: 6).ApplyTo);
        vm.ClearFilterCommand.Execute(null);
        Assert.Null(session.Settings.ScoreBandFilter);
    }
}
