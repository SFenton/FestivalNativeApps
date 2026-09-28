using System.Globalization;
using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>Rankings routes on a <see cref="FakeService"/> with scripted populations and failures.</summary>
public sealed class RankingsFake
{
    public FakeService Service { get; } = new();
    public int TotalAccounts { get; set; } = 60;
    public int TotalTeams { get; set; } = 30;
    public HashSet<string> Failing { get; } = [];
    public Func<HttpRequestMessage, HttpResponseMessage?>? Extra { get; set; }

    public RankingsFake()
    {
        Service.Override = request =>
        {
            if (Extra?.Invoke(request) is { } extra) return extra;
            var uri = request.RequestUri!;
            var path = uri.AbsolutePath;
            var pub = ("X-FST-Publication-Id", "7");
            if (!path.StartsWith("/api/rankings/", StringComparison.Ordinal)) return null;
            if (Failing.Contains(path)) return Wire.Response(HttpStatusCode.ServiceUnavailable);
            var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
            var page = int.Parse(query["page"]!, CultureInfo.InvariantCulture);
            var size = int.Parse(query["pageSize"]!, CultureInfo.InvariantCulture);
            var parts = path.Split('/');
            if (parts[3] == "bands")
            {
                var ranks = Enumerable.Range((page - 1) * size + 1, Math.Max(0, Math.Min(size, TotalTeams - (page - 1) * size)));
                return Wire.Ok(RankingsWire.BandBoard(parts[4], page, size, TotalTeams, ranks), pub);
            }
            var accountRanks = Enumerable.Range((page - 1) * size + 1, Math.Max(0, Math.Min(size, TotalAccounts - (page - 1) * size)));
            return Wire.Ok(RankingsWire.Board(parts[3], page, size, TotalAccounts, accountRanks, query["rankBy"]!), pub);
        };
    }

    public FestivalSession Session(AppSettings? settings = null, FakeTimeProvider? time = null) => Service.Session(time, settings);

    public static AppSettings Selected(string accountId = "acct3", IReadOnlyList<Instrument>? visible = null) => new()
    {
        SelectedPlayer = new SelectedPlayer(accountId, "Me"),
        VisibleInstruments = visible ?? InstrumentInfo.All,
    };
}

/// <summary>Scriptable own-row reader.</summary>
public sealed class FakeReader
{
    public List<(Instrument, string)> Calls { get; } = [];
    public Func<Instrument, string, AccountRankingEntry?> Result { get; set; } = (_, id) => RankingsWire.Account(120, id);
    public bool Fail { get; set; }
    public TaskCompletionSource? Gate { get; set; }

    public async Task<AccountRankingEntry?> Read(Instrument instrument, string accountId, CancellationToken token)
    {
        Calls.Add((instrument, accountId));
        if (Gate is { } gate) await gate.Task.WaitAsync(token);
        if (Fail) throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 500);
        return Result(instrument, accountId);
    }
}

public sealed class LeaderboardsOverviewTests
{
    [Fact]
    public async Task BuildsCardsForVisibleInstrumentsAndEveryBandSize()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Bass, Instrument.Lead] });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        await vm.ActivateAsync();

        Assert.Equal([Instrument.Lead, Instrument.Bass], vm.InstrumentCards.Select(c => c.Instrument));
        Assert.Equal(BandTypeInfo.All, vm.BandCards.Select(c => c.BandType));
        var lead = vm.InstrumentCards[0];
        Assert.True(lead.ShowRows);
        Assert.Equal(10, lead.Rows.Count);
        Assert.Equal("Lead", lead.Title);
        Assert.Equal("Total Score", lead.Subtitle);
        Assert.Equal("instrument_guitar.png", lead.IconFile);
        Assert.Equal("fst.leaderboards.card.Solo_Guitar", lead.AutomationId);
        Assert.Equal("fst.leaderboards.card.Solo_Guitar.view-all", lead.ViewAllAutomationId);
        Assert.Equal(new AppRoute.FullRankings(Instrument.Lead, "totalscore"), lead.ViewAllRoute);
        Assert.Equal("View all Lead rankings", lead.ViewAllName);
        Assert.False(lead.Spotlight.IsVisible);
        var band = vm.BandCards[2];
        Assert.True(band.ShowRows);
        Assert.Equal("Quads", band.Title);
        Assert.Equal("Total Score", band.Subtitle);
        Assert.Equal("fst.leaderboards.band-card.Band_Quad", band.AutomationId);
        Assert.Equal("fst.leaderboards.band-card.Band_Quad.view-all", band.ViewAllAutomationId);
        Assert.Equal(new AppRoute.BandRankings("Band_Quad"), band.ViewAllRoute);
        Assert.Equal("View all Quads rankings", band.ViewAllName);
        Assert.Equal("Leaderboards Quick Links", vm.QuickLinks.Title);
        Assert.Equal(["instrument:Solo_Guitar", "instrument:Solo_Bass", "band:Band_Duets", "band:Band_Trios", "band:Band_Quad"],
            vm.QuickLinks.Items.Select(i => i.Section.Id));
        Assert.Equal(Instrument.Lead, vm.QuickLinks.Items[0].Section.Instrument);
        Assert.Equal(LeaderboardsViewModel.BandQuickLinkGlyph, vm.QuickLinks.Items[4].Glyph);
        Assert.All(fake.Service.Handler.Requests.Where(r => r.Uri.AbsolutePath.StartsWith("/api/rankings", StringComparison.Ordinal)),
            r => Assert.Contains("pageSize=10", r.Uri.Query, StringComparison.Ordinal));

        // Activating again with nothing changed does not reload.
        var before = fake.Service.Handler.Requests.Count;
        await vm.ActivateAsync();
        Assert.Equal(before, fake.Service.Handler.Requests.Count);
        vm.Deactivate();
    }

    [Fact]
    public async Task MetricSelectionPersistsNarrowsBandsAndReloads()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Drums] });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        await vm.ActivateAsync();
        Assert.Equal("Total Score", vm.MetricLabel);
        Assert.Equal(RankingMetricInfo.All, vm.MetricOptions);

        await vm.SelectMetricCommand.ExecuteAsync(RankingMetric.MaxScore);
        Assert.Equal("maxscore", session.Settings.LeaderboardRankBy);
        Assert.Equal("Rank by: Max Score", vm.MetricButtonName);
        Assert.Equal(RankingMetric.MaxScore, vm.InstrumentCards[0].Metric);
        Assert.Equal(BandRankingMetric.TotalScore, vm.BandCards[0].Metric);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("rankBy=maxscore", StringComparison.Ordinal));

        // A new overview picks up the persisted metric.
        Assert.Equal(RankingMetric.MaxScore, new LeaderboardsViewModel(session).Metric);

        // Same metric, same key: no reload.
        var count = fake.Service.Handler.Requests.Count;
        await vm.SelectMetricAsync(RankingMetric.MaxScore);
        Assert.Equal(count, fake.Service.Handler.Requests.Count);
    }

    [Fact]
    public async Task EmptyAndFailedCardsAreIndependent()
    {
        var fake = new RankingsFake { TotalAccounts = 0, TotalTeams = 0 };
        fake.Failing.Add("/api/rankings/Solo_Bass");
        fake.Failing.Add("/api/rankings/bands/Band_Trios");
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Lead, Instrument.Bass] });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        await vm.LoadAsync();

        Assert.True(vm.InstrumentCards[0].ShowEmpty);
        Assert.Equal("No ranked Lead players yet.", vm.InstrumentCards[0].EmptyText);
        var bass = vm.InstrumentCards[1];
        Assert.True(bass.ShowError);
        Assert.False(bass.IsLoading);
        Assert.True(bass.Status.HasIssue);
        Assert.True(vm.BandCards[0].ShowEmpty);
        Assert.Equal("No ranked duos yet.", vm.BandCards[0].EmptyText);
        Assert.True(vm.BandCards[1].ShowError);

        fake.Failing.Clear();
        fake.TotalAccounts = 5;
        fake.TotalTeams = 5;
        await bass.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(bass.ShowRows);
        Assert.False(bass.Status.HasIssue);
        await vm.BandCards[1].Status.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.BandCards[1].ShowRows);
        Assert.Equal(new AppRoute.Band("band1", "Band_Trios", "team1"), vm.BandCards[1].Rows[0].Route);
    }

    [Fact]
    public async Task SelectedPlayerInTopTenIsHighlightedWithoutAnExtraRead()
    {
        var fake = new RankingsFake();
        var reader = new FakeReader();
        var session = fake.Session(RankingsFake.Selected("ACCT3", [Instrument.Lead]));
        var vm = new LeaderboardsViewModel(session, reader.Read);
        await vm.ActivateAsync();

        var card = vm.InstrumentCards[0];
        Assert.True(card.Rows[2].IsSelected);
        Assert.StartsWith("Your rank, 3rd. Player 3.", card.Rows[2].Announcement, StringComparison.Ordinal);
        Assert.Equal(SpotlightPlacementKind.Inline, card.Spotlight.Kind);
        Assert.False(card.Spotlight.IsVisible);
        Assert.Empty(reader.Calls);
    }

    [Fact]
    public async Task SelectedPlayerOutsideTopTenGetsSpotlightRowOrUnrankedText()
    {
        var fake = new RankingsFake();
        var reader = new FakeReader { Result = (i, id) => i == Instrument.Bass ? null : RankingsWire.Account(120, id) };
        var session = fake.Session(RankingsFake.Selected("me", [Instrument.Lead, Instrument.Bass]));
        var vm = new LeaderboardsViewModel(session, reader.Read);
        await vm.ActivateAsync();

        var lead = vm.InstrumentCards[0].Spotlight;
        Assert.True(lead.ShowRow);
        Assert.True(lead.IsVisible);
        Assert.Equal("#120", lead.Row!.RankText);
        Assert.True(lead.Row.IsSelected);
        Assert.False(lead.CanJump);
        var bass = vm.InstrumentCards[1].Spotlight;
        Assert.True(bass.ShowUnranked);
        Assert.Equal("Not yet ranked on Bass.", bass.UnrankedText);
        Assert.Equal(2, reader.Calls.Count);
    }

    [Fact]
    public async Task SpotlightFailureRetriesInline()
    {
        var fake = new RankingsFake();
        var reader = new FakeReader { Fail = true };
        var session = fake.Session(RankingsFake.Selected("me", [Instrument.Lead]));
        var vm = new LeaderboardsViewModel(session, reader.Read);
        await vm.ActivateAsync();

        var spotlight = vm.InstrumentCards[0].Spotlight;
        Assert.True(spotlight.ShowFailed);
        Assert.False(spotlight.ShowLoading);
        Assert.True(spotlight.Status.HasIssue);

        reader.Fail = false;
        await spotlight.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(spotlight.ShowRow);
        Assert.False(spotlight.Status.HasIssue);
    }

    [Fact]
    public async Task PendingSpotlightShowsLoadingUntilTheReadCompletes()
    {
        var fake = new RankingsFake();
        var reader = new FakeReader { Gate = new TaskCompletionSource() };
        var session = fake.Session(RankingsFake.Selected("me", [Instrument.Lead]));
        var vm = new LeaderboardsViewModel(session, reader.Read);
        var load = vm.ActivateAsync();
        await Async.Until(() => reader.Calls.Count == 1);
        Assert.True(vm.InstrumentCards[0].Spotlight.ShowLoading);
        reader.Gate.SetResult();
        await load;
        Assert.True(vm.InstrumentCards[0].Spotlight.ShowRow);
    }

    [Fact]
    public async Task SelectionChangeReloadsAndDeactivateStopsFollowing()
    {
        var fake = new RankingsFake();
        var reader = new FakeReader();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Lead] });
        var vm = new LeaderboardsViewModel(session, reader.Read);
        await vm.ActivateAsync();
        Assert.False(vm.InstrumentCards[0].Spotlight.IsVisible);

        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer("me", "Me") });
        await Async.Until(() => vm.InstrumentCards[0].Spotlight.ShowRow);
        Assert.Single(reader.Calls);

        vm.Deactivate();
        var count = fake.Service.Handler.Requests.Count;
        session.UpdateSettings(s => s with { VisibleInstruments = [Instrument.Bass] });
        await Async.Settle();
        Assert.Equal(count, fake.Service.Handler.Requests.Count);
        Assert.Equal(Instrument.Lead, vm.InstrumentCards[0].Instrument);
    }

    [Fact]
    public async Task DeactivatingMidLoadCancelsAndReloadsOnReturn()
    {
        var fake = new RankingsFake();
        var gate = new TaskCompletionSource();
        fake.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.StartsWith("/api/rankings/", StringComparison.Ordinal)) await gate.Task.WaitAsync(token);
            return fake.Service.Override!(request) ?? (request.RequestUri.AbsolutePath == "/api/publication"
                ? Wire.Ok(Wire.Publication()) : Wire.Response(HttpStatusCode.NotFound));
        };
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Lead] });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        var first = vm.ActivateAsync();
        await Async.Until(() => fake.Service.Handler.Requests.Any(r => r.Uri.AbsolutePath.StartsWith("/api/rankings/", StringComparison.Ordinal)));
        vm.Deactivate();
        await first;
        Assert.True(vm.InstrumentCards[0].IsLoading);
        gate.SetResult();
        await vm.ActivateAsync();
        Assert.True(vm.InstrumentCards[0].ShowRows);
    }

    [Fact]
    public async Task DefaultReaderMapsUnrankedToNull()
    {
        var fake = new RankingsFake
        {
            Extra = r => r.RequestUri!.AbsolutePath switch
            {
                "/api/rankings/Solo_Guitar/me" => Wire.Ok(PlayerWire.Ranking("me", "Solo_Guitar", 77), ("X-FST-Publication-Id", "7")),
                "/api/rankings/Solo_Bass/me" => Wire.Response(HttpStatusCode.NotFound, "{}", ("X-FST-Publication-Id", "7")),
                _ => null,
            },
        };
        var session = fake.Session(RankingsFake.Selected("me", [Instrument.Lead, Instrument.Bass]));
        var vm = new LeaderboardsViewModel(session);
        await vm.ActivateAsync();
        Assert.Equal("#77", vm.InstrumentCards[0].Spotlight.Row!.RankText);
        Assert.True(vm.InstrumentCards[1].Spotlight.ShowUnranked);
    }

    [Fact]
    public async Task SpotlightWithoutReaderStaysPending()
    {
        var spotlight = new RankingSpotlightViewModel(Instrument.Lead, null, new FakeTimeProvider(), "t");
        spotlight.Apply("me", [], RankingMetric.TotalScore);
        await spotlight.EnsureLoadedAsync("me", true);
        Assert.True(spotlight.ShowLoading);
        await spotlight.JumpCommand.ExecuteAsync(null);
    }

    [Fact]
    public async Task SpotlightDropsReadForSupersededAccountAndCancellation()
    {
        var reader = new FakeReader { Gate = new TaskCompletionSource() };
        var spotlight = new RankingSpotlightViewModel(Instrument.Lead, reader.Read, new FakeTimeProvider(), "t");
        spotlight.Apply("one", [], RankingMetric.TotalScore);
        var first = spotlight.EnsureLoadedAsync("one", true);
        spotlight.Apply("two", [], RankingMetric.TotalScore);
        reader.Gate.SetResult();
        await first;
        Assert.True(spotlight.ShowLoading);

        using var cancelled = new CancellationTokenSource();
        reader.Gate = new TaskCompletionSource();
        var second = spotlight.EnsureLoadedAsync("two", true, cancelled.Token);
        cancelled.Cancel();
        await second;
        Assert.True(spotlight.ShowLoading);

        // Not needed (visible) or no selection: no read.
        var calls = reader.Calls.Count;
        await spotlight.EnsureLoadedAsync("two", false);
        await spotlight.EnsureLoadedAsync(null, true);
        Assert.Equal(calls, reader.Calls.Count);
    }
}

public sealed class RankingRowTests
{
    public RankingRowTests() => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");

    [Fact]
    public void AccountRowProjectsMetricValues()
    {
        var row = new RankingRowViewModel(RankingsWire.Account(2, "abc"), RankingMetric.Adjusted, false);
        Assert.Equal("#2", row.RankText);
        Assert.Equal("Player 2", row.Name);
        Assert.Equal("Top 2%", row.RatingText);
        Assert.True(row.HasBayesian);
        Assert.Equal("0.12", row.BayesianText);
        Assert.Equal("38 / 50 songs", row.SongsText);
        Assert.Equal(new AppRoute.Player("abc", "Player 2"), row.Route);
        Assert.Equal("fst.rankings.row.abc", row.AutomationId);
        Assert.Equal("Rank #2, Player 2. Adjusted Top 2% (0.12), 38 / 50 songs", row.Announcement);
        var anonymous = new RankingRowViewModel(RankingsWire.Account(15, ""), RankingMetric.TotalScore, false);
        Assert.Null(anonymous.Route);
        Assert.Equal("fst.rankings.row.rank-15", anonymous.AutomationId);
        var total = new RankingRowViewModel(RankingsWire.Account(2), RankingMetric.TotalScore, true);
        Assert.False(total.HasBayesian);
        Assert.Equal("Your rank, 2nd. Player 2. Total Score 89,999,998, 38 / 50 songs", total.Announcement);
    }

    [Fact]
    public void BandRowProjectsMetricValues()
    {
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.BandBoard("Band_Duets", 1, 25, 1, [1])),
            RankingsJsonContext.Default.BandRankingsResponse);
        var row = new BandRankingRowViewModel(board.Entries[0], BandType.Duets, BandRankingMetric.Weighted);
        Assert.Equal("#2", row.RankText);
        Assert.Equal("Member A, Unknown User", row.Name);
        Assert.Equal("Top 5%", row.RatingText);
        Assert.Equal("0.05", row.BayesianText);
        Assert.Equal("fst.band-rankings.row.team1", row.AutomationId);
        Assert.Equal("Rank #2, Member A, Unknown User. Weighted Top 5% (0.05), 29 / 50 songs", row.Announcement);
        Assert.False(new BandRankingRowViewModel(board.Entries[0], BandType.Duets, BandRankingMetric.FcRate).HasBayesian);
        Assert.Null(new BandRankingRowViewModel(board.Entries[0] with { TeamKey = "" }, BandType.Duets, BandRankingMetric.FcRate).Route);
    }

    [Fact]
    public async Task PagerEnablesByBoundaryAndMoves()
    {
        var moves = new List<int>();
        var pager = new RankingsPagerViewModel("fst.x", p => { moves.Add(p); return Task.CompletedTask; });
        Assert.False(pager.IsPaged);
        pager.Update(1, 1200);
        Assert.Equal("1 / 1,200", pager.InfoText);
        Assert.Equal("Page 1 of 1,200", pager.InfoAnnouncement);
        Assert.False(pager.FirstCommand.CanExecute(null));
        Assert.False(pager.PreviousCommand.CanExecute(null));
        Assert.True(pager.NextCommand.CanExecute(null));
        await pager.NextCommand.ExecuteAsync(null);
        await pager.LastCommand.ExecuteAsync(null);
        pager.Update(9999, 0);
        Assert.Equal(1, pager.Page);
        Assert.Equal(1, pager.TotalPages);
        pager.Update(5, 10);
        await pager.PreviousCommand.ExecuteAsync(null);
        await pager.FirstCommand.ExecuteAsync(null);
        Assert.Equal([2, 1200, 4, 1], moves);
        Assert.Equal("fst.x", pager.IdPrefix);
    }
}

public sealed class FullRankingsViewModelTests
{
    [Fact]
    public async Task LoadsPageWithPagerAndInstrumentOptions()
    {
        var fake = new RankingsFake { TotalAccounts = 60 };
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Lead, Instrument.Bass] });
        var vm = new FullRankingsViewModel(session, new AppRoute.FullRankings(Instrument.Drums, "fcrate"), new FakeReader().Read);
        await vm.LoadAsync();

        Assert.True(vm.ShowRows);
        Assert.True(vm.ShowContent);
        Assert.Equal(25, vm.Rows.Count);
        Assert.Equal(3, vm.Pager.TotalPages);
        Assert.Equal("Drums Rankings", vm.Title);
        Assert.Equal("FC Rate", vm.MetricLabel);
        Assert.Equal("Rank by: FC Rate", vm.MetricButtonName);
        Assert.Equal("Instrument: Drums", vm.InstrumentButtonName);
        Assert.Equal("instrument_drums.png", vm.IconFile);
        Assert.Equal("60 ranked players", vm.TotalText);
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Drums], vm.InstrumentOptions);
        Assert.Equal(RankingMetricInfo.All, vm.MetricOptions);

        await vm.Pager.NextCommand.ExecuteAsync(null);
        Assert.Equal(2, vm.Page);
        Assert.Equal("#28", vm.Rows[0].RankText); // FC Rate rank column
        await vm.Pager.LastCommand.ExecuteAsync(null);
        Assert.Equal(10, vm.Rows.Count);

        await vm.SelectMetricCommand.ExecuteAsync(RankingMetric.Weighted);
        Assert.Equal(1, vm.Page);
        await vm.SelectMetricAsync(RankingMetric.Weighted);
        await vm.Pager.NextCommand.ExecuteAsync(null);
        await vm.SelectInstrumentCommand.ExecuteAsync(Instrument.Bass);
        Assert.Equal(1, vm.Page);
        Assert.Equal("Bass Rankings", vm.Title);
        await vm.SelectInstrumentAsync(Instrument.Bass);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.AbsolutePath == "/api/rankings/Solo_Bass" &&
                                                            r.Uri.Query == "?rankBy=weighted&page=1&pageSize=25");
    }

    [Fact]
    public async Task OutOfRangePageIsCorrectedAndEmptyBoardShowsEmpty()
    {
        var fake = new RankingsFake { TotalAccounts = 30 };
        var vm = new FullRankingsViewModel(fake.Session(), new AppRoute.FullRankings(Instrument.Lead, "bogus"), new FakeReader().Read);
        Assert.Equal(RankingMetric.TotalScore, vm.Metric);
        await vm.GoToPageAsync(9);
        Assert.Equal(2, vm.Page);
        Assert.Equal(5, vm.Rows.Count);

        fake.TotalAccounts = 0;
        await vm.GoToPageAsync(1);
        Assert.True(vm.ShowEmpty);
        Assert.True(vm.ShowContent);
    }

    [Fact]
    public async Task FailureShowsStatusAndRetryRecovers()
    {
        var fake = new RankingsFake();
        fake.Failing.Add("/api/rankings/Solo_Guitar");
        var vm = new FullRankingsViewModel(fake.Session(), new AppRoute.FullRankings(Instrument.Lead, "totalscore"), new FakeReader().Read);
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.False(vm.IsRefreshing);
        fake.Failing.Clear();
        await vm.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.ShowRows);
    }

    [Fact]
    public async Task SupersededResponsesAreDropped()
    {
        var fake = new RankingsFake();
        var gate = new TaskCompletionSource();
        var first = true;
        fake.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/rankings/Solo_Guitar" && first)
            {
                first = false;
                await gate.Task;
                return Wire.Ok(RankingsWire.Board("Solo_Guitar", 1, 25, 60, Enumerable.Range(1, 25)), ("X-FST-Publication-Id", "7"));
            }
            return fake.Service.Override!(request) ?? (request.RequestUri.AbsolutePath == "/api/publication"
                ? Wire.Ok(Wire.Publication()) : Wire.Response(HttpStatusCode.NotFound));
        };
        var vm = new FullRankingsViewModel(fake.Session(), new AppRoute.FullRankings(Instrument.Lead, "totalscore"), new FakeReader().Read);
        var stale = vm.LoadAsync();
        await Async.Until(() => fake.Service.Handler.To("/api/rankings/Solo_Guitar").Any());
        await vm.GoToPageAsync(2);
        gate.SetResult();
        await stale;
        Assert.Equal(2, vm.Page);
        Assert.Equal("#26", vm.Rows[0].RankText);
    }

    [Fact]
    public async Task SpotlightPinsSelectedPlayerAndJumpsToTheirPage()
    {
        var fake = new RankingsFake { TotalAccounts = 60 };
        var reader = new FakeReader { Result = (_, _) => RankingsWire.Account(30, "acct30") };
        var session = fake.Session(RankingsFake.Selected("acct30"));
        var vm = new FullRankingsViewModel(session, new AppRoute.FullRankings(Instrument.Lead, "totalscore"), reader.Read);
        await vm.LoadAsync();

        Assert.True(vm.Spotlight.ShowRow);
        Assert.True(vm.Spotlight.CanJump);
        Assert.True(vm.Spotlight.JumpCommand.CanExecute(null));
        await vm.Spotlight.JumpCommand.ExecuteAsync(null);
        Assert.Equal(2, vm.Page);
        Assert.True(vm.Rows.Single(r => r.Entry.AccountId == "acct30").IsSelected);
        Assert.Equal(SpotlightPlacementKind.Inline, vm.Spotlight.Kind);
        Assert.False(vm.Spotlight.CanJump);

        // Switching instrument builds a fresh spotlight for that board.
        var old = vm.Spotlight;
        await vm.SelectInstrumentAsync(Instrument.Bass);
        Assert.NotSame(old, vm.Spotlight);
        Assert.Equal(2, reader.Calls.Count);
    }

    [Fact]
    public async Task RefreshSelectionFollowsDeselection()
    {
        var fake = new RankingsFake();
        var session = fake.Session(RankingsFake.Selected("acct2"));
        var vm = new FullRankingsViewModel(session, new AppRoute.FullRankings(Instrument.Lead, "totalscore"), new FakeReader().Read);
        vm.RefreshSelection();
        await vm.LoadAsync();
        Assert.True(vm.Rows[1].IsSelected);
        session.DeselectPlayer();
        vm.RefreshSelection();
        Assert.False(vm.Rows[1].IsSelected);
        Assert.Equal(SpotlightPlacementKind.None, vm.Spotlight.Kind);
    }
}

public sealed class BandRankingsViewModelTests
{
    [Fact]
    public async Task LoadsSwitchesAndPages()
    {
        var fake = new RankingsFake { TotalTeams = 40 };
        var session = fake.Session(new AppSettings { LeaderboardRankBy = "maxscore" });
        var vm = new BandRankingsViewModel(session, new AppRoute.BandRankings("Band_Trios"));
        Assert.Equal(BandRankingMetric.TotalScore, vm.Metric);
        await vm.LoadAsync();

        Assert.True(vm.ShowRows);
        Assert.True(vm.ShowContent);
        Assert.Equal("Trios Rankings", vm.Title);
        Assert.Equal("Band size: Trios", vm.BandTypeButtonName);
        Assert.Equal("Rank by: Total Score", vm.MetricButtonName);
        Assert.Equal("40 ranked bands", vm.TotalText);
        Assert.Equal(BandTypeInfo.All, vm.BandTypeOptions);
        Assert.Equal(BandRankingMetricInfo.All, vm.MetricOptions);
        Assert.Equal(2, vm.Pager.TotalPages);
        await vm.Pager.NextCommand.ExecuteAsync(null);
        Assert.Equal(15, vm.Rows.Count);

        await vm.SelectBandTypeCommand.ExecuteAsync(BandType.Quad);
        Assert.Equal(1, vm.Page);
        await vm.SelectBandTypeAsync(BandType.Quad);
        await vm.SelectMetricCommand.ExecuteAsync(BandRankingMetric.FcRate);
        await vm.SelectMetricAsync(BandRankingMetric.FcRate);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.AbsolutePath == "/api/rankings/bands/Band_Quad" &&
                                                            r.Uri.Query == "?rankBy=fcrate&page=1&pageSize=25");
        await vm.GoToPageAsync(7);
        Assert.Equal(2, vm.Page);
    }

    [Fact]
    public async Task UnknownTypeFallsBackAndEmptyAndFailureStates()
    {
        var fake = new RankingsFake { TotalTeams = 0 };
        var vm = new BandRankingsViewModel(fake.Session(), new AppRoute.BandRankings("Band_Nope"));
        Assert.Equal(BandType.Duets, vm.BandType);
        await vm.LoadAsync();
        Assert.True(vm.ShowEmpty);
        Assert.Equal("No ranked duos yet.", vm.EmptyText);

        fake.Failing.Add("/api/rankings/bands/Band_Duets");
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.False(vm.IsLoading);
    }
}

public sealed class SongLeaderboardViewModelTests
{
    private static FestivalSession Session(FakeService service, AppSettings? settings = null) => service.Session(null, settings);

    [Fact]
    public async Task LoadsSongAndPageWithLocalEntriesPaging()
    {
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");
        var service = new FakeService();
        var vm = new SongLeaderboardViewModel(Session(service), new AppRoute.SongLeaderboard("s2", Instrument.Lead, 2));
        await vm.ActivateAsync();

        Assert.True(vm.ShowRows);
        Assert.Equal("Beta", vm.Title);
        Assert.Equal("Ann Artist", vm.Subtitle);
        Assert.Equal("instrument_keys.png", vm.IconFile);
        Assert.Equal("Lead", vm.InstrumentLabel);
        Assert.Equal(4, vm.Pager.TotalPages);
        Assert.Equal(2, vm.Pager.Page);
        Assert.Equal("", vm.TotalText);
        Assert.False(vm.ShowSpotlight);
        var sent = service.Handler.To("/api/leaderboard/s2/Solo_Guitar").Single();
        Assert.Equal("?top=25&offset=25", sent.Uri.Query);

        var row = vm.Rows[0];
        Assert.Equal("#1", row.RankText);
        Assert.Equal("FC 98.5%", row.AccuracyPill);
        Assert.Equal("★★★★★", row.Stars);
        Assert.Equal("S15", row.Season);
        Assert.Equal(new AppRoute.Player("a1", "Player 1"), row.Route);
        Assert.Equal("fst.song-leaderboard.row.a1", row.AutomationId);
        Assert.Equal("Rank #1, Player 1, 99,999 points, 98.5% accuracy, full combo, 6 stars", row.Announcement);
        Assert.Equal("98.5%", vm.Rows[1].AccuracyPill);

        // Active again: no reload.
        var count = service.Handler.Requests.Count;
        await vm.ActivateAsync();
        Assert.Equal(count, service.Handler.Requests.Count);
        vm.Deactivate();
    }

    [Fact]
    public async Task TotalsLeewayAndOutOfRangeCorrection()
    {
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");
        var service = new FakeService
        {
            Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
                ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Bass", 3, 1234, 30).Replace("\"count\"", "\"showLeaderboardEntryTotals\":true,\"count\"", StringComparison.Ordinal),
                    ("X-FST-Publication-Id", "7"))
                : null,
        };
        var settings = new AppSettings { FilterInvalidScores = true, Leeway = 1.26 };
        var vm = new SongLeaderboardViewModel(Session(service, settings), new AppRoute.SongLeaderboard("s1", Instrument.Bass, 9));
        await vm.LoadAsync();
        Assert.Equal(2, vm.Page);
        Assert.Equal("1,234 Bass entries", vm.TotalText);
        Assert.All(service.Handler.To("/api/leaderboard/s1/Solo_Bass"), r => Assert.Contains("leeway=1.3", r.Uri.Query, StringComparison.Ordinal));
    }

    [Fact]
    public async Task EmptyMissingSongAndFailure()
    {
        var service = new FakeService
        {
            Override = r => r.RequestUri!.AbsolutePath switch
            {
                "/api/leaderboard/s1/Solo_Drums" => Wire.Ok(Wire.Leaderboard("s1", "Solo_Drums", 0, 0, 0), ("X-FST-Publication-Id", "7")),
                "/api/leaderboard/s1/Solo_Vocals" => Wire.Response(HttpStatusCode.ServiceUnavailable),
                _ => null,
            },
        };
        var session = Session(service);
        var empty = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("s1", Instrument.Drums));
        await empty.LoadAsync();
        Assert.True(empty.ShowEmpty);
        Assert.True(empty.ShowContent);

        var missing = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("nope", Instrument.Lead));
        await missing.LoadAsync();
        Assert.True(missing.ShowError);
        Assert.Equal("", missing.Title);

        var failed = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("s1", Instrument.Vocals));
        await failed.ActivateAsync();
        Assert.True(failed.ShowError);
        Assert.False(failed.IsLoading);
        failed.Deactivate();
    }

    [Fact]
    public async Task SelectedPlayerIsHighlightedPinnedAndJumpable()
    {
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");
        var service = new FakeService();
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One", PlayerWire.Score("s1", "01", 5000, 990, true, 6, 60, 100, 1.0));
        PlayerWire.Install(service, new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var inner = service.Override!;
        service.Override = r => inner(r);
        var session = Session(service, new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("s1", Instrument.Lead));
        await vm.ActivateAsync();
        await Async.Until(() => vm.ShowSpotlight);

        var pinned = vm.Spotlight!;
        Assert.True(pinned.IsSelected);
        Assert.Equal("#60", pinned.RankText);
        Assert.Equal(new AppRoute.Statistics(), pinned.Route);
        Assert.StartsWith("Your rank, 60th. Fixture One, 5,000 points", pinned.Announcement, StringComparison.Ordinal);
        Assert.True(vm.CanJump);
        await vm.JumpCommand.ExecuteAsync(null);
        Assert.Equal(3, vm.Page);
        Assert.False(vm.CanJump);

        session.DeselectPlayer();
        await Async.Settle();
        Assert.False(vm.ShowSpotlight);
        await vm.JumpCommand.ExecuteAsync(null);
        vm.Deactivate();
    }

    [Fact]
    public async Task InvalidScoreFallsBackToValidVariantWhenFiltering()
    {
        var service = new FakeService();
        var invalid = PlayerWire.Score("s1", "01", 5000, 990, true, 6, 60, 100, 1.0,
            ",\"isValid\":false,\"validScore\":4000,\"validAccuracy\":950,\"validIsFullCombo\":false");
        var noValid = PlayerWire.Score("s2", "01", 5000, 990, true, 6, 60, 100, 1.0, ",\"isValid\":false");
        PlayerWire.Install(service, new() { [PlayerWire.Id] = (HttpStatusCode.OK, PlayerWire.Profile(PlayerWire.Id, "Fixture One", invalid, noValid)) });
        var session = Session(service, new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true });
        await session.LoadSelectedProfileAsync();

        var vm = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("s1", Instrument.Lead));
        await vm.LoadAsync();
        Assert.Equal("—", vm.Spotlight!.RankText);
        Assert.Equal(4000, vm.Spotlight.Entry.Score);
        Assert.StartsWith("Your score. Fixture One", vm.Spotlight.Announcement, StringComparison.Ordinal);
        Assert.False(vm.CanJump);

        var none = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard("s2", Instrument.Lead));
        await none.LoadAsync();
        Assert.False(none.ShowSpotlight);
    }

    [Fact]
    public void RowPlaceholders()
    {
        var row = new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "x", Score = 1 }, false);
        Assert.Equal("Unknown User", row.Name);
        Assert.False(row.HasAccuracy);
        Assert.Equal("", row.Stars);
        Assert.Equal("", row.Season);
        Assert.Equal("", row.AccuracyPill);
        Assert.Null(new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "" }, false).Route);
    }
}
