using Festival.Core.Domain;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Settings' Experimental Ranks gates the experimental Rank By metrics app-wide (issue #541; web
/// <c>getEnabledRankingMetrics</c>, <c>coerceRankingMetric</c> and <c>coerceBandRankingMetric</c>).
/// </summary>
public sealed class ExperimentalRanksTests
{
    #region Gate
    [Fact]
    public void Gate_OffAllowsOnlyTotalScore()
    {
        Assert.Equal([RankingMetric.TotalScore], RankingMetricInfo.Enabled(false));
        Assert.Equal(RankingMetricInfo.All, RankingMetricInfo.Enabled(true));
        Assert.Equal([BandRankingMetric.TotalScore], BandRankingMetricInfo.Enabled(false));
        Assert.Equal(BandRankingMetricInfo.All, BandRankingMetricInfo.Enabled(true));
        // Web getEnabledBandRankingMetrics order: Total Score first, then the experimental metrics.
        Assert.Equal(
            [BandRankingMetric.TotalScore, BandRankingMetric.Adjusted, BandRankingMetric.Weighted, BandRankingMetric.FcRate],
            BandRankingMetricInfo.Enabled(true));
        Assert.Equal(
            [RankingMetric.TotalScore, RankingMetric.Adjusted, RankingMetric.Weighted, RankingMetric.FcRate, RankingMetric.MaxScore],
            RankingMetricInfo.Enabled(true));
        Assert.False(RankingMetric.TotalScore.IsExperimental());
        Assert.All(RankingMetricInfo.All.Where(m => m != RankingMetric.TotalScore), m => Assert.True(m.IsExperimental()));

        foreach (var metric in RankingMetricInfo.All)
        {
            Assert.Equal(RankingMetric.TotalScore, metric.Gate(false));
            Assert.Equal(metric, metric.Gate(true));
        }
        foreach (var metric in BandRankingMetricInfo.All)
        {
            Assert.Equal(BandRankingMetric.TotalScore, metric.Gate(false));
            Assert.Equal(metric, metric.Gate(true));
        }

        Assert.Equal(RankingMetric.TotalScore, RankingMetricInfo.Coerce("fcrate", false));
        Assert.Equal(RankingMetric.FcRate, RankingMetricInfo.Coerce("fcrate", true));
        Assert.Equal(RankingMetric.TotalScore, RankingMetricInfo.Coerce("bogus", true));
        Assert.Equal(RankingMetric.TotalScore, RankingMetricInfo.Coerce(null, false));
    }

    [Fact]
    public void Settings_ToggleIsOffByDefaultPersistsAndResets()
    {
        Assert.False(new AppSettings().ExperimentalRanks);
        var on = new AppSettings { ExperimentalRanks = true }.Sanitized();
        Assert.True(on.ExperimentalRanks);
        Assert.False(on.ResetAppSettings().ExperimentalRanks);
        // The saved Rank By survives while gated, so turning the toggle back on restores it (web keeps the saved value).
        Assert.Equal("fcrate", new AppSettings { LeaderboardRankBy = "fcrate" }.Sanitized().LeaderboardRankBy);
    }
    #endregion

    #region Leaderboards
    [Fact]
    public async Task Overview_OffHidesRankByAndFallsBackFromASavedExperimentalMetric()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Drums], LeaderboardRankBy = "fcrate" });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        await vm.ActivateAsync();

        Assert.False(vm.ShowRankBy);
        Assert.Equal([RankingMetric.TotalScore], vm.MetricOptions);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.Equal("Rank by: Total Score", vm.MetricButtonName);
        Assert.Equal(RankingMetric.TotalScore, vm.InstrumentCards[0].Metric);
        Assert.Equal(new AppRoute.FullRankings(Instrument.Drums, "totalscore"), vm.InstrumentCards[0].ViewAllRoute);
        Assert.DoesNotContain(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("rankBy=fcrate", StringComparison.Ordinal));

        // A command for a hidden metric cannot select it.
        await vm.SelectMetricCommand.ExecuteAsync(RankingMetric.MaxScore);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.Equal("fcrate", session.Settings.LeaderboardRankBy);
        vm.Deactivate();
    }

    [Fact]
    public async Task Overview_TogglingReloadsWithoutAStaleExperimentalBoard()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Drums], LeaderboardRankBy = "fcrate", ExperimentalRanks = true });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        var options = 0;
        vm.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(vm.MetricOptions)) options++; };
        await vm.ActivateAsync();
        Assert.True(vm.ShowRankBy);
        Assert.Equal(RankingMetricInfo.All, vm.MetricOptions);
        Assert.Equal(RankingMetric.FcRate, vm.InstrumentCards[0].Metric);

        session.UpdateSettings(s => s with { ExperimentalRanks = false });
        await Async.Until(() => vm.InstrumentCards[0].Metric == RankingMetric.TotalScore && !vm.InstrumentCards[0].IsLoading);
        Assert.False(vm.ShowRankBy);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.Equal(BandRankingMetric.TotalScore, vm.BandCards[0].Metric);
        Assert.True(options > 0);

        session.UpdateSettings(s => s with { ExperimentalRanks = true });
        await Async.Until(() => vm.InstrumentCards[0].Metric == RankingMetric.FcRate && !vm.InstrumentCards[0].IsLoading);
        Assert.Equal(BandRankingMetric.FcRate, vm.BandCards[0].Metric);
        vm.Deactivate();
    }

    [Fact]
    public async Task FullRankings_DeepLinkedExperimentalMetricFallsBackAndRestoresOnRevisit()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings());
        var vm = new FullRankingsViewModel(session, new AppRoute.FullRankings(Instrument.Drums, "fcrate", 2), new FakeReader().Read);
        await vm.LoadAsync();
        Assert.False(vm.ShowRankBy);
        Assert.Equal([RankingMetric.TotalScore], vm.MetricOptions);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.DoesNotContain(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("rankBy=fcrate", StringComparison.Ordinal));
        await vm.SelectMetricCommand.ExecuteAsync(RankingMetric.Weighted);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.Null(vm.SyncExperimentalRanks());

        // Back to the cached page after turning the toggle on: the route's metric applies, from page 1.
        session.UpdateSettings(s => s with { ExperimentalRanks = true });
        var reload = vm.SyncExperimentalRanks();
        Assert.NotNull(reload);
        await reload;
        Assert.True(vm.ShowRankBy);
        Assert.Equal(RankingMetricInfo.All, vm.MetricOptions);
        Assert.Equal(RankingMetric.FcRate, vm.Metric);
        Assert.Equal(1, vm.Page);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("rankBy=fcrate", StringComparison.Ordinal));

        await vm.SelectMetricCommand.ExecuteAsync(RankingMetric.MaxScore);
        session.UpdateSettings(s => s with { ExperimentalRanks = false });
        await vm.SyncExperimentalRanks()!;
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        Assert.Equal("Rank by: Total Score", vm.MetricButtonName);
        Assert.True(vm.ShowRows);
    }

    [Fact]
    public async Task BandRankings_FollowTheToggle()
    {
        var fake = new RankingsFake { TotalTeams = 40 };
        var session = fake.Session(new AppSettings { LeaderboardRankBy = "weighted" });
        var vm = new BandRankingsViewModel(session, new AppRoute.BandRankings("Band_Trios"));
        await vm.LoadAsync();
        Assert.False(vm.ShowRankBy);
        Assert.Equal([BandRankingMetric.TotalScore], vm.MetricOptions);
        Assert.Equal(BandRankingMetric.TotalScore, vm.Metric);
        await vm.SelectMetricCommand.ExecuteAsync(BandRankingMetric.FcRate);
        Assert.Equal(BandRankingMetric.TotalScore, vm.Metric);
        Assert.Null(vm.SyncExperimentalRanks());

        session.UpdateSettings(s => s with { ExperimentalRanks = true });
        await vm.SyncExperimentalRanks()!;
        Assert.True(vm.ShowRankBy);
        Assert.Equal(BandRankingMetricInfo.All, vm.MetricOptions);
        Assert.Equal(BandRankingMetric.Weighted, vm.Metric);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("rankBy=weighted", StringComparison.Ordinal));

        session.UpdateSettings(s => s with { ExperimentalRanks = false });
        await vm.SyncExperimentalRanks()!;
        Assert.Equal(BandRankingMetric.TotalScore, vm.Metric);
        Assert.Equal("Rank by: Total Score", vm.MetricButtonName);
    }
    #endregion
}
