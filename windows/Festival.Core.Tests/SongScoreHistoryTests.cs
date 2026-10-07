using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongScoreHistoryDomainTests
{
    private static ScoreHistoryEntry Entry(string ins = "Solo_Guitar", long score = 1000, double? acc = 950000, bool? fc = false,
        string? achieved = "2026-03-01T10:00:00Z", string changed = "2026-03-02T10:00:00Z", int? season = 9) =>
        new() { SongId = "s1", Instrument = ins, NewScore = score, Accuracy = acc, IsFullCombo = fc, ScoreAchievedAt = achieved, ChangedAt = changed, Season = season };

    [Fact]
    public void Point_ProjectsAccuracyGoldAndLabels()
    {
        var gold = new ScoreHistoryPoint(Entry(acc: 1000000, fc: true), new DateTimeOffset(2026, 3, 30, 12, 0, 0, TimeSpan.Zero));
        Assert.Equal(100, gold.AccuracyPercent);
        Assert.True(gold.IsGold);
        Assert.Equal(1000, gold.Score);
        Assert.Matches(@"^3/3\d/26$", gold.DateLabel);
        Assert.Matches(@"^Mar 3\d, 2026$", gold.LongDate);
        var plain = new ScoreHistoryPoint(Entry(acc: 1000000, fc: false), DateTimeOffset.UnixEpoch);
        Assert.False(plain.IsGold);
        Assert.Equal(0, new ScoreHistoryPoint(Entry(acc: null), DateTimeOffset.UnixEpoch).AccuracyPercent);
        Assert.Equal(0, new ScoreHistoryPoint(Entry(acc: double.NaN), DateTimeOffset.UnixEpoch).AccuracyPercent);
    }

    [Fact]
    public void FilterInvalid_UsesMaxScoreTimesLeeway()
    {
        var song = new Song { SongId = "s1", MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 } };
        List<ScoreHistoryEntry> rows = [Entry(score: 1000), Entry(score: 1010), Entry(score: 1011), Entry("Solo_Bass", 5000), Entry("Weird", 9000)];
        Assert.Equal(5, SongScoreHistory.FilterInvalid(rows, song, false, 1).Count);
        Assert.Equal(5, SongScoreHistory.FilterInvalid(rows, null, true, 1).Count);
        Assert.Equal([1000, 1010, 5000, 9000], SongScoreHistory.FilterInvalid(rows, song, true, 1).Select(r => r.NewScore));
        Assert.Equal([1000, 5000, 9000], SongScoreHistory.FilterInvalid(rows, song, true, 0).Select(r => r.NewScore));
    }

    [Fact]
    public void Counts_DefaultInstrument_PointsAndTopScores()
    {
        List<ScoreHistoryEntry> rows =
        [
            Entry("Solo_Bass", 10, achieved: "2026-01-03T00:00:00Z"), Entry("Solo_Bass", 30, achieved: "2026-01-01T00:00:00Z"),
            Entry("Solo_Bass", 20, achieved: null, changed: "2026-01-02T00:00:00Z"), Entry("Solo_Drums", 5), Entry("Nope", 1),
            Entry("Solo_Bass", 40, achieved: "garbage", changed: "garbage"),
        ];
        var counts = SongScoreHistory.Counts(rows);
        Assert.Equal(4, counts[Instrument.Bass]);
        Assert.Equal(1, counts[Instrument.Drums]);
        Instrument[] pool = [Instrument.Lead, Instrument.Bass, Instrument.Drums];
        Assert.Equal(Instrument.Drums, SongScoreHistory.DefaultInstrument(pool, counts, Instrument.Drums));
        Assert.Equal(Instrument.Bass, SongScoreHistory.DefaultInstrument(pool, counts, Instrument.Vocals));
        Assert.Equal(Instrument.Bass, SongScoreHistory.DefaultInstrument(pool, counts, null));
        counts[Instrument.Lead] = 1;
        Assert.Equal(Instrument.Lead, SongScoreHistory.DefaultInstrument(pool, counts, null));
        Assert.Null(SongScoreHistory.DefaultInstrument([Instrument.Vocals], counts, null));

        var points = SongScoreHistory.Points(rows, Instrument.Bass);
        Assert.Equal([30, 20, 10], points.Select(p => p.Score)); // oldest first; undated dropped
        Assert.Equal([30, 20, 10], SongScoreHistory.TopScores(points).Select(p => p.Score));
        var many = Enumerable.Range(1, 7).Select(i => new ScoreHistoryPoint(Entry(score: i), DateTimeOffset.UnixEpoch.AddDays(i))).ToList();
        Assert.Equal([7, 6, 5, 4, 3], SongScoreHistory.TopScores(many).Select(p => p.Score));
        Assert.Equal(7, SongScoreHistory.TopScores(many, all: true).Count);
    }

    [Theory]
    [InlineData(0, 220, 40, 40)]
    [InlineData(100, 46, 204, 113)]
    [InlineData(50, 133, 122, 77)]
    [InlineData(-50, 220, 40, 40)]
    [InlineData(150, 46, 204, 113)]
    [InlineData(double.NaN, 220, 40, 40)]
    public void AccuracyColor_MatchesWeb(double percent, byte r, byte g, byte b) =>
        Assert.Equal((r, g, b), SongScoreHistory.AccuracyColor(percent));

    [Theory]
    [InlineData(0, 4)]
    [InlineData(3, 4)]
    [InlineData(20, 20)]
    [InlineData(90923, 100000)]
    [InlineData(176616, 200000)]
    [InlineData(1000, 1000)]
    [InlineData(1001, 1200)]
    public void NiceMax_RoundsUpToFourSteps(long max, long expected) => Assert.Equal(expected, ScoreHistoryChartScale.NiceMax(max));

    [Theory]
    [InlineData(26, 19, 64)]       // 100% text: the original 64 epx gutter
    [InlineData(0, 0, 64)]
    [InlineData(-5, -5, 64)]
    [InlineData(52, 38, 106)]      // 200% text: 4 + 38 + 4 + 52 + 8
    [InlineData(52.2, 38.1, 107)]  // rounds up so the title never touches the ticks
    [InlineData(double.PositiveInfinity, 20, 64)]
    public void AxisGutter_FitsTitleAndTicks(double tickWidth, double titleHeight, double expected) =>
        Assert.Equal(expected, ScoreHistoryChartScale.AxisGutter(tickWidth, titleHeight));

    [Fact]
    public void Scale_TicksAndBars()
    {
        Assert.Equal("25k", ScoreHistoryChartScale.Tick(25000));
        Assert.Equal("500", ScoreHistoryChartScale.Tick(500));
        Assert.Equal(int.MaxValue, ScoreHistoryChartScale.MaxBars(0));
        Assert.Equal(int.MaxValue, ScoreHistoryChartScale.MaxBars(double.NaN));
        Assert.Equal(1, ScoreHistoryChartScale.MaxBars(50));
        Assert.Equal(2, ScoreHistoryChartScale.MaxBars(200));
        Assert.Equal(1, ScoreHistoryChartScale.MaxBars(199));
    }

    [Fact]
    public void Pager_PagesFromNewestAndFollowsSelection()
    {
        var pager = new ScoreHistoryPager();
        pager.Reset(10);
        Assert.False(pager.NeedsPagination);
        pager.SetMaxBars(4);
        Assert.True(pager.NeedsPagination);
        Assert.True(pager.ShowPageJumps);
        Assert.Equal((6, 10), (pager.PageStart, pager.PageEnd));
        Assert.True(pager.ForwardDisabled);
        Assert.False(pager.BackDisabled);
        pager.BackEntry();
        Assert.Equal((5, 9), (pager.PageStart, pager.PageEnd));
        pager.BackPage();
        pager.BackPage();
        Assert.Equal((0, 4), (pager.PageStart, pager.PageEnd));
        Assert.True(pager.BackDisabled);
        pager.ForwardPage();
        Assert.Equal((4, 8), (pager.PageStart, pager.PageEnd));

        pager.Toggle(4);
        Assert.Equal(4, pager.SelectedIndex);
        pager.BackEntry(); // 3 is off the page → the page starts at 3
        Assert.Equal(3, pager.SelectedIndex);
        Assert.Equal((3, 7), (pager.PageStart, pager.PageEnd));
        pager.ForwardPage(); // 7 → the page ends at 7
        Assert.Equal(7, pager.SelectedIndex);
        Assert.Equal((4, 8), (pager.PageStart, pager.PageEnd));
        pager.ForwardEntry(); // 8 → page includes 8
        Assert.Equal((5, 9), (pager.PageStart, pager.PageEnd));
        pager.ForwardPage();
        Assert.Equal(9, pager.SelectedIndex);
        Assert.True(pager.ForwardDisabled);
        pager.Toggle(9);
        Assert.Equal(-1, pager.SelectedIndex);
        pager.Toggle(99);
        Assert.Equal(-1, pager.SelectedIndex);
        pager.Toggle(0);
        Assert.True(pager.BackDisabled);
        pager.ClearSelection();
        Assert.Equal(-1, pager.SelectedIndex);

        pager.SetMaxBars(1);
        Assert.False(pager.ShowPageJumps);
        pager.Reset(0);
        pager.BackEntry();
        Assert.Equal(0, pager.Offset);
    }

    [Fact]
    public void Reveal_FollowsTheWebSchedule()
    {
        Assert.False(SongDetailReveal.Animates(TimeSpan.FromMilliseconds(100), true));
        Assert.True(SongDetailReveal.Animates(TimeSpan.FromMilliseconds(400), true));
        Assert.False(SongDetailReveal.Animates(TimeSpan.FromSeconds(2), false));
        Assert.Equal(TimeSpan.FromMilliseconds(300), SongDetailReveal.Card(1, 2));
        Assert.Equal(TimeSpan.FromMilliseconds(450), SongDetailReveal.Card(2, 2));
        Assert.Equal(TimeSpan.FromMilliseconds(600), SongDetailReveal.Card(2, 1));
        Assert.Equal(TimeSpan.FromMilliseconds(300), SongDetailReveal.Card(-3, 0));
    }

    [Fact]
    public void Swap_PlansFadeInstantAndSettle()
    {
        Assert.Equal(ScoreHistorySwapPlan.None, ScoreHistorySwap.Plan(Instrument.Lead, null, false));
        Assert.Equal(ScoreHistorySwapPlan.Instant, ScoreHistorySwap.Plan(null, Instrument.Lead, false));
        Assert.Equal(ScoreHistorySwapPlan.Settle, ScoreHistorySwap.Plan(Instrument.Lead, Instrument.Lead, false));
        Assert.Equal(ScoreHistorySwapPlan.Settle, ScoreHistorySwap.Plan(Instrument.Lead, Instrument.Lead, true));
        Assert.Equal(ScoreHistorySwapPlan.Fade, ScoreHistorySwap.Plan(Instrument.Lead, Instrument.Bass, false));
        Assert.Equal(ScoreHistorySwapPlan.Instant, ScoreHistorySwap.Plan(Instrument.Lead, Instrument.Bass, true));
        Assert.True(ScoreHistorySwap.FadeOut < ScoreHistorySwap.FadeIn);
    }

    [Fact]
    public void Swap_ReservesPagerWhenAnySelectableChartPages()
    {
        var counts = new Dictionary<Instrument, int> { [Instrument.Lead] = 8, [Instrument.Bass] = 2 };
        Assert.True(ScoreHistorySwap.ReservesPager(counts, [Instrument.Lead, Instrument.Bass], 3));
        Assert.False(ScoreHistorySwap.ReservesPager(counts, [Instrument.Lead, Instrument.Bass], 8));
        Assert.False(ScoreHistorySwap.ReservesPager(counts, [Instrument.Bass], 1 + 1));
        Assert.False(ScoreHistorySwap.ReservesPager(counts, [Instrument.Drums], 1));
        Assert.False(ScoreHistorySwap.ReservesPager(counts, [Instrument.Lead], int.MaxValue));
    }

    /// <summary>A swapper over a fake view: fades wait on <see cref="Steps"/> until released.</summary>
    private sealed class FakeSwapView
    {
        public Instrument? Shown = Instrument.Lead;
        public double Opacity = 1;
        public bool Held;
        public List<string> Log = [];
        public Queue<TaskCompletionSource> Steps = [];

        public ScoreHistorySwapper Swapper()
        {
            // No test sync context: completing a step runs the swap's continuation inline, like the UI thread would next.
            SynchronizationContext.SetSynchronizationContext(null);
            return new(
            () => Shown,
            chart => { Shown = chart; Log.Add("show " + chart); },
            async (to, duration, token) =>
            {
                Log.Add($"fade {to} {duration.TotalMilliseconds}");
                if (duration > TimeSpan.Zero)
                {
                    var step = new TaskCompletionSource();
                    Steps.Enqueue(step);
                    using var cancel = token.Register(() => step.TrySetCanceled(token));
                    await step.Task;
                }
                Opacity = to;
            },
            hold => { Held = hold; Log.Add(hold ? "hold" : "release"); });
        }

        public void Finish() => Steps.Dequeue().SetResult();
    }

    [Fact]
    public async Task Swapper_FadesOutSwapsAndFadesInWhileHoldingTheCard()
    {
        var view = new FakeSwapView();
        var swapper = view.Swapper();
        var swap = swapper.RequestAsync(Instrument.Bass, reduceMotion: false);
        Assert.True(view.Held);
        Assert.True(swapper.IsRunning);
        Assert.Equal(Instrument.Lead, view.Shown); // still fading the old chart out
        view.Finish();
        Assert.Equal(Instrument.Bass, view.Shown);
        Assert.Equal(0, view.Opacity);
        view.Finish();
        Assert.Equal(ScoreHistorySwapPlan.Fade, await swap);
        Assert.Equal(["hold", "fade 0 150", "show Bass", "fade 1 250", "release"], view.Log);
        Assert.Equal(1, view.Opacity);
        Assert.False(view.Held || swapper.IsRunning);
    }

    [Fact]
    public async Task Swapper_NewerRequestCancelsAndEndsOnTheLastChoice()
    {
        var view = new FakeSwapView();
        var swapper = view.Swapper();
        var first = swapper.RequestAsync(Instrument.Bass, false);
        var second = swapper.RequestAsync(Instrument.Drums, false); // cancels the Bass fade-out
        Assert.Equal(ScoreHistorySwapPlan.Fade, await first);
        Assert.DoesNotContain("show Bass", view.Log);
        view.Steps.Dequeue(); // the cancelled fade's step
        view.Finish();
        view.Finish();
        await second;
        Assert.Equal(Instrument.Drums, view.Shown);
        Assert.False(view.Held);

        // Back to the shown chart mid-swap: it just fades back in.
        view.Log.Clear();
        var away = swapper.RequestAsync(Instrument.Bass, false);
        var back = swapper.RequestAsync(Instrument.Drums, false);
        await away;
        view.Steps.Dequeue();
        view.Finish();
        Assert.Equal(ScoreHistorySwapPlan.Settle, await back);
        Assert.Equal(Instrument.Drums, view.Shown);
        Assert.Equal(["hold", "fade 0 150", "fade 1 250", "release"], view.Log);
    }

    [Fact]
    public async Task Swapper_ReducedMotionSwapsAtOnce()
    {
        var view = new FakeSwapView();
        var swapper = view.Swapper();
        Assert.Equal(ScoreHistorySwapPlan.Instant, await swapper.RequestAsync(Instrument.Bass, reduceMotion: true));
        Assert.Equal(["show Bass", "fade 1 0", "release"], view.Log);
        Assert.Equal(ScoreHistorySwapPlan.Settle, await swapper.RequestAsync(Instrument.Bass, reduceMotion: true));
        Assert.Equal(ScoreHistorySwapPlan.None, await swapper.RequestAsync(null, reduceMotion: false));
        Assert.Empty(view.Steps);
        Assert.Equal(1, view.Opacity);
        Assert.False(view.Held);
    }
}

public class SongDetailApiTests
{
    [Fact]
    public void Endpoints_ValidateArguments()
    {
        var baseUri = new Uri(Wire.BaseUrl);
        Assert.EndsWith("/api/leaderboard/s1/all?top=10", ServiceEndpoints.AllLeaderboards(baseUri, "s1").AbsoluteUri);
        Assert.EndsWith("top=5&leeway=1.5", ServiceEndpoints.AllLeaderboards(baseUri, "s1", 5, 1.5).AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.AllLeaderboards(baseUri, "s1", 26));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.AllLeaderboards(baseUri, "s1", 10, 9));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.AllLeaderboards(baseUri, "s1", 10, double.NaN));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.AllLeaderboards(baseUri, "a/b"));
        Assert.EndsWith($"/api/player/{PlayerWire.Id}/history?songId=s1", ServiceEndpoints.PlayerSongHistory(baseUri, PlayerWire.Id, "s1").AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.PlayerSongHistory(baseUri, PlayerWire.Id, ""));
    }

    [Fact]
    public async Task AllLeaderboards_ValidatesAndSplitsPerChart()
    {
        var service = new FakeService();
        var all = await service.Client().GetAllLeaderboardsAsync("s1");
        Assert.Equal(9, all.Instruments.Count);
        var lead = all.For(Instrument.Lead);
        Assert.Equal(("s1", "Solo_Guitar", 10, 100, 90), (lead.SongId, lead.Instrument, lead.Count, lead.TotalEntries, lead.LocalEntries));
        var missing = new AllLeaderboardsResponse { SongId = "s1", ShowLeaderboardEntryTotals = true }.For(Instrument.Bass);
        Assert.Equal(("Solo_Bass", 0, true), (missing.Instrument, missing.Entries.Count, missing.ShowLeaderboardEntryTotals));
    }

    [Theory]
    [InlineData("""{"songId":"other","instruments":[]}""")]
    [InlineData("""{"songId":"s1","instruments":[{"instrument":"Solo_Guitar","count":2,"totalEntries":1,"entries":[]}]}""")]
    [InlineData("""{"songId":"s1","instruments":[{"instrument":"Solo_Guitar","count":0,"totalEntries":-1,"entries":[]}]}""")]
    [InlineData("""{"songId":"s1","instruments":[{"instrument":"Solo_Guitar","count":0,"totalEntries":1,"localEntries":-1,"entries":[]}]}""")]
    [InlineData("""{"songId":"s1","instruments":[{"instrument":"Solo_Guitar","count":0,"entries":[]},{"instrument":"Solo_Guitar","count":0,"entries":[]}]}""")]
    [InlineData("""{"songId":"s1","instruments":[null]}""")]
    public async Task AllLeaderboards_RejectsInconsistentBodies(string body)
    {
        var service = new FakeService { Override = r => r.RequestUri!.AbsolutePath.EndsWith("/all", StringComparison.Ordinal) ? Wire.Ok(body, ("X-FST-Publication-Id", "7")) : null };
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetAllLeaderboardsAsync("s1"));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, error.Kind);
    }

    [Fact]
    public async Task SongHistory_MapsSyncingAndUnregistered()
    {
        var status = HttpStatusCode.OK;
        var service = new FakeService
        {
            Override = r => r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)
                ? Wire.Response(status, PlayerWire.History(PlayerWire.Id, PlayerWire.HistoryEntry()), ("X-FST-Publication-Id", "7"))
                : null,
        };
        var client = service.Client();
        var read = await client.GetPlayerSongHistoryAsync(PlayerWire.Id, "s1");
        Assert.Equal(PlayerHistoryState.Available, read.State);
        Assert.Single(read.Response.History);
        status = HttpStatusCode.Accepted;
        Assert.Equal(PlayerHistoryState.Syncing, (await client.GetPlayerSongHistoryAsync(PlayerWire.Id, "s1")).State);
        status = HttpStatusCode.NotFound;
        Assert.Equal(PlayerHistoryState.Unregistered, (await client.GetPlayerSongHistoryAsync(PlayerWire.Id, "s1")).State);
        status = HttpStatusCode.InternalServerError;
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerSongHistoryAsync(PlayerWire.Id, "s1"));
    }
}

public class SongScoreHistoryViewModelTests
{
    private static readonly string[] SixLead =
    [
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 100, achieved: "2026-01-01T00:00:00Z", season: 1),
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 600, achieved: "2026-01-02T00:00:00Z", fc: true, acc: 1000000),
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 300, achieved: "2026-01-03T00:00:00Z", season: null),
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 400, achieved: "2026-01-04T00:00:00Z", acc: null),
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 500, achieved: "2026-01-05T00:00:00Z"),
        PlayerWire.HistoryEntry("s1", "Solo_Guitar", 200, achieved: "2026-01-06T00:00:00Z"),
        PlayerWire.HistoryEntry("s1", "Solo_Bass", 50),
        PlayerWire.HistoryEntry("other", "Solo_Bass", 70),
        PlayerWire.HistoryEntry("s1", "Solo_Vocals", 70),
    ];

    /// <summary>A session with a selected player whose <c>/history</c> answers <paramref name="status"/> + rows.</summary>
    private static (FakeService Service, FestivalSession Session, Func<HttpStatusCode> Status, Action<HttpStatusCode> SetStatus) Setup(
        HttpStatusCode status = HttpStatusCode.OK, string[]? rows = null, AppSettings? settings = null)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var inner = service.Override!;
        var current = status;
        service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)
            ? Wire.Response(current, PlayerWire.History(PlayerWire.Id, rows ?? SixLead), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var initial = (settings ?? new AppSettings()) with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") };
        return (service, service.Session(settings: initial), () => current, s => current = s);
    }

    private static Song Song(string id = "s1") => new() { SongId = id };

    [Fact]
    public async Task NoPlayer_HidesWithoutReading()
    {
        var service = new FakeService();
        var vm = new SongScoreHistoryViewModel(service.Session(), "s1", null);
        await vm.LoadAsync(Song(), [Instrument.Lead]);
        Assert.False(vm.IsVisible);
        Assert.Empty(service.Handler.Requests);
        Assert.Equal("No score history for this instrument", vm.EmptyMessage);
    }

    [Fact]
    public async Task Loaded_PicksLeadAndBuildsChartAndTopFive()
    {
        var (service, session, _, _) = Setup();
        var vm = new SongScoreHistoryViewModel(session, "s1", null);
        await vm.LoadAsync(Song(), [Instrument.Lead, Instrument.Bass, Instrument.Drums]);
        Assert.Single(service.Handler.To($"/api/player/{PlayerWire.Id}/history"));
        Assert.True(vm.ShowChart);
        Assert.True(vm.IsVisible);
        Assert.False(vm.ShowSyncing || vm.ShowError);
        Assert.Equal([Instrument.Lead, Instrument.Bass], vm.Instruments);
        Assert.Equal(Instrument.Lead, vm.Selected);
        Assert.Equal(6, vm.Points.Count);
        Assert.Equal(6, vm.Bars.Count);
        Assert.False(vm.ShowPaging);
        Assert.Equal([600, 500, 400, 300, 200], vm.Rows.Select(r => r.Point.Score));
        Assert.True(vm.Rows[0].IsBest);
        Assert.True(vm.CanViewAll);
        Assert.Contains("Lead score history, 6 of 6 scores", vm.ChartSummary);
        Assert.Equal("No score history for Lead", vm.EmptyMessage);
        Assert.Equal(("Score History", "View All Scores"), (vm.Title, vm.ViewAllText));
        Assert.Equal(("View All Scores, Lead", "fst.history.view-all"), (vm.ViewAllName, vm.ViewAllAutomationId));
        Assert.StartsWith("Select a bar", vm.Subtitle);
        Assert.False(vm.KeyboardLead);

        // View All Scores opens the chart's Player History page; the card never grows in place (view-all-cta R8, #324).
        Assert.Equal(new AppRoute.PlayerHistory("s1", Instrument.Lead), vm.ViewAllRoute);
        Assert.Equal(5, vm.Rows.Count);
        Assert.All(vm.Rows, r => Assert.StartsWith("fst.song-detail.history.row.", r.AutomationId, StringComparison.Ordinal));

        var named = new List<string?>();
        vm.PropertyChanged += (_, e) => named.Add(e.PropertyName);
        vm.SelectInstrument(Instrument.Bass);
        Assert.Contains(nameof(vm.ViewAllName), named); // View All Scores' UIA name follows the chart (view-all-cta R4)
        Assert.Contains(nameof(vm.ViewAllRoute), named);
        Assert.Equal("View All Scores, Bass", vm.ViewAllName);
        Assert.Equal(new AppRoute.PlayerHistory("s1", Instrument.Bass), vm.ViewAllRoute);
        Assert.Single(vm.Points);
        Assert.False(vm.CanViewAll);
        vm.SelectInstrument(Instrument.Drums); // not in the selector
        Assert.Equal(Instrument.Bass, vm.Selected);
    }

    [Fact]
    public async Task Bars_PageAndSelectDetailRow()
    {
        var (_, session, _, _) = Setup();
        var vm = new SongScoreHistoryViewModel(session, "s1", Instrument.Lead);
        await vm.LoadAsync(Song(), [Instrument.Lead]);
        vm.SetPlotWidth(2 * 96 + 8 + 50); // two bars
        vm.SetPlotWidth(2 * 96 + 8 + 50); // unchanged: no rebuild
        Assert.Equal([4, 5], vm.Bars.Select(b => b.Index));
        Assert.True(vm.ShowPaging);
        Assert.True(vm.ShowPageJumps);
        Assert.True(vm.CanGoBack);
        Assert.False(vm.CanGoForward);
        vm.BackEntry();
        Assert.Equal([3, 4], vm.Bars.Select(b => b.Index));
        vm.BackPage();
        vm.ForwardPage();
        vm.ForwardEntry();
        Assert.Equal([4, 5], vm.Bars.Select(b => b.Index));
        vm.ToggleBar(5);
        Assert.True(vm.HasSelectedPoint);
        Assert.True(vm.Bars[1].IsSelected);
        var row = vm.SelectedRow!;
        Assert.Equal(("200", "S9", true, false), (row.Score, row.Season, row.HasSeason, row.IsBest));
        Assert.True(row.HasAccuracy);
        Assert.Equal(950000, row.AccuracyValue);
        Assert.Contains("score 200", row.Announcement);
        Assert.True(row.PinsSeason); // issue #62: the detail row always shows the season
        Assert.All(vm.Rows, r => Assert.False(r.PinsSeason));
        vm.ToggleBar(5);
        Assert.False(vm.HasSelectedPoint);

        var fc = vm.Rows[0];
        Assert.True(fc.IsFullCombo);
        Assert.Contains("full combo", fc.Announcement);
        Assert.Contains("personal best", fc.Announcement);
        var noAccuracy = vm.Rows.Single(r => r.Point.Score == 400);
        Assert.False(noAccuracy.HasAccuracy);
        Assert.Equal(0, noAccuracy.AccuracyValue);
        Assert.False(vm.Rows.Single(r => r.Point.Score == 300).HasSeason);
    }

    [Fact]
    public async Task PagerSlot_StaysReservedWhileAnyChartPages()
    {
        var (_, session, _, _) = Setup();
        var vm = new SongScoreHistoryViewModel(session, "s1", null);
        await vm.LoadAsync(Song(), [Instrument.Lead, Instrument.Bass]);
        Assert.False(vm.ShowPagerSlot); // not measured yet: every bar fits
        vm.SetPlotWidth(2 * 96 + 8 + 50); // two bars: six Lead rows page
        Assert.True(vm.ShowPaging && vm.ShowPagerSlot);
        vm.SelectInstrument(Instrument.Bass); // one row: no pager, but its row keeps its space
        Assert.False(vm.ShowPaging);
        Assert.True(vm.ShowPagerSlot);
        vm.SetPlotWidth(10 * 104); // everything fits
        Assert.False(vm.ShowPagerSlot);
    }

    [Fact]
    public async Task DetailSlot_StaysReservedAfterASwitchUntilABarIsToggled()
    {
        var (_, session, _, _) = Setup();
        var vm = new SongScoreHistoryViewModel(session, "s1", null);
        await vm.LoadAsync(Song(), [Instrument.Lead, Instrument.Bass]);
        Assert.False(vm.ShowDetailSlot);
        vm.SelectInstrument(Instrument.Bass); // no bar open: nothing to reserve
        Assert.False(vm.ReservesDetail || vm.ShowDetailSlot);
        vm.SelectInstrument(Instrument.Lead);
        vm.ToggleBar(vm.Bars[^1].Index);
        Assert.True(vm.HasSelectedPoint && vm.ShowDetailSlot);
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        vm.SelectInstrument(Instrument.Bass); // web: the new chart opens with no bar selected; the row's space stays
        Assert.False(vm.HasSelectedPoint);
        Assert.True(vm.ReservesDetail && vm.ShowDetailSlot);
        // The view reads the closed row's height when the reservation starts, so it must come before the row clears.
        Assert.True(changed.IndexOf(nameof(vm.ReservesDetail)) < changed.IndexOf(nameof(vm.SelectedRow)));
        vm.SelectInstrument(Instrument.Lead); // rapid switches keep it
        vm.SelectInstrument(Instrument.Bass);
        Assert.True(vm.ShowDetailSlot);
        vm.ToggleBar(vm.Bars[0].Index); // picking a bar fills the slot
        Assert.True(vm.HasSelectedPoint && vm.ShowDetailSlot);
        Assert.False(vm.ReservesDetail);
        vm.ToggleBar(vm.Bars[0].Index); // clearing it closes the row, as with no switch
        Assert.False(vm.ShowDetailSlot);
        vm.ToggleBar(vm.Bars[0].Index);
        vm.SelectInstrument(Instrument.Lead);
        Assert.True(vm.ReservesDetail);
        await vm.LoadAsync(Song(), [Instrument.Lead, Instrument.Bass]); // a reload starts clean
        Assert.False(vm.ReservesDetail || vm.ShowDetailSlot);
    }

    [Fact]
    public async Task InvalidScoresAreFiltered_AndNoVisibleChartHides()
    {
        var (_, session, _, _) = Setup(settings: new AppSettings { FilterInvalidScores = true, Leeway = 0 });
        var vm = new SongScoreHistoryViewModel(session, "s1", null);
        var song = new Song { SongId = "s1", MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 350 } };
        await vm.LoadAsync(song, [Instrument.Lead]);
        Assert.Equal([100, 300, 200], vm.Points.Select(p => p.Score));
        await vm.LoadAsync(song, [Instrument.Drums]);
        Assert.False(vm.IsVisible);
    }

    [Fact]
    public async Task Syncing_ThenRetryLoads_AndFailureReportsStatus()
    {
        var (_, session, _, set) = Setup(HttpStatusCode.Accepted);
        var vm = new SongScoreHistoryViewModel(session, "s1", null);
        await vm.LoadAsync(Song(), [Instrument.Lead]);
        Assert.True(vm.ShowSyncing);
        Assert.True(vm.IsVisible);
        set(HttpStatusCode.OK);
        await vm.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.ShowChart);
        set(HttpStatusCode.InternalServerError);
        await vm.RetryAsync();
        Assert.True(vm.ShowError);
        Assert.Equal("Score history unavailable", vm.Status.Title);
        set(HttpStatusCode.NotFound);
        await vm.RetryAsync();
        Assert.False(vm.IsVisible);
    }
}

public class SongDetailHistoryPageTests
{
    [Fact]
    public async Task InitialChart_SelectsHistory_WithQuickLink()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)
            ? Wire.Ok(PlayerWire.History(PlayerWire.Id, PlayerWire.HistoryEntry("s1", "Solo_Bass", 50)), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1", Instrument.Bass));
        Assert.Equal(Instrument.Bass, vm.InitialInstrument);
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.Equal(Instrument.Bass, vm.History.Selected);
        Assert.Equal(["intensity", SongDetailViewModel.HistoryQuickLinkId, "instrument-Solo_Guitar"], vm.QuickLinkSections.Take(3).Select(s => s.Id));

        // Another player: history re-reads (per-entity reset); none selected hides it.
        session.SelectPlayer(new PlayerSearchResult(PlayerWire.Other, "Fixture Two"));
        await Async.Until(() => service.Handler.To($"/api/player/{PlayerWire.Other}/history").Any());
        session.DeselectPlayer();
        await Async.Until(() => !vm.History.IsVisible);
        Assert.DoesNotContain(SongDetailViewModel.HistoryQuickLinkId, vm.QuickLinkSections.Select(s => s.Id));
        vm.Detach();
    }

    [Fact]
    public async Task AllLeaderboardsFailure_FailsEachCardWithRetry()
    {
        var service = new FakeService();
        var fail = true;
        service.Override = r => fail && r.RequestUri!.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
            ? Wire.Response(HttpStatusCode.InternalServerError)
            : null;
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.All(vm.Leaderboards, c => Assert.True(c.ShowError));
        Assert.False(vm.History.IsVisible);
        fail = false;
        await vm.Leaderboards[0].Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => vm.Leaderboards[0].ShowRows);
    }

    [Fact]
    public async Task AllLeaderboardsMissing_FallsBackToPerChartReads()
    {
        var service = new FakeService
        {
            Override = r => r.RequestUri!.AbsolutePath.EndsWith("/all", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.NotFound) : null,
        };
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.All(vm.Leaderboards, c => Assert.True(c.ShowRows));
        Assert.Single(service.Handler.To("/api/leaderboard/s1/Solo_Bass"));
    }

    [Fact]
    public async Task RowWithoutAccount_HasNoRoute()
    {
        var service = new FakeService
        {
            Override = r => r.RequestUri!.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
                ? Wire.Ok(Wire.AllLeaderboards("s1", 1).Replace("\"accountId\":\"a1\"", "\"accountId\":\"\""), ("X-FST-Publication-Id", "7"))
                : null,
        };
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.Null(vm.Leaderboards[0].Rows[0].Route);
    }

    [Fact]
    public async Task NoVisibleChartedInstrument_SkipsTheBoardsRead()
    {
        var service = new FakeService();
        var vm = new SongDetailViewModel(service.Session(settings: new AppSettings { VisibleInstruments = [Instrument.ProDrums] }),
            new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.Empty(vm.Leaderboards);
        // Band previews don't depend on visible instruments: Intensity and the band sizes stay in Quick Links.
        Assert.Equal(["intensity", "band-Band_Duets", "band-Band_Trios", "band-Band_Quad"], vm.QuickLinkSections.Select(s => s.Id));
        Assert.Empty(service.Handler.To("/api/leaderboard/s1/all"));
    }
}
