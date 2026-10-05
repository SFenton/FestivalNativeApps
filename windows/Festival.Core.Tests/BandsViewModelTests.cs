using System.Globalization;
using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class BandsPagerTests
{
    [Fact]
    public async Task Pager_CommandsReportTargetsAndGateOnBounds()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var requested = new List<int>();
        var pager = new BandsPagerViewModel(p => { requested.Add(p); return Task.CompletedTask; });
        Assert.False(pager.IsVisible);
        Assert.False(pager.FirstCommand.CanExecute(null));
        Assert.False(pager.NextCommand.CanExecute(null));
        pager.PageCount = 4;
        pager.Page = 2;
        Assert.True(pager.IsVisible && pager.CanGoBack && pager.CanGoForward);
        Assert.Equal("2 / 4", pager.PageText);
        Assert.Equal("Page 2 of 4", pager.PageAnnouncement);
        await pager.FirstCommand.ExecuteAsync(null);
        await pager.PreviousCommand.ExecuteAsync(null);
        await pager.NextCommand.ExecuteAsync(null);
        await pager.LastCommand.ExecuteAsync(null);
        Assert.Equal([1, 1, 3, 4], requested);
        pager.Page = 4;
        Assert.False(pager.LastCommand.CanExecute(null));
    }
}

public class PlayerBandsViewModelTests
{
    [Fact]
    public async Task Loads_PagesAndSwitchesGroups()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var bands = new BandService();
        var vm = new PlayerBandsViewModel(bands.Service.Session(), new AppRoute.PlayerBands("acc"));
        Assert.True(vm.IsLoading);
        Assert.Equal("Player Bands", vm.Title);
        Assert.Equal("All Bands", vm.Subtitle);
        await vm.LoadAsync();
        Assert.True(vm.ShowRows);
        Assert.Equal("Player One's Bands", vm.Title);
        Assert.Equal("All Bands · 30 bands", vm.Subtitle);
        Assert.Equal(25, vm.Entries.Count);
        Assert.Equal("1 / 2", vm.Pager.PageText);
        var card = vm.Entries[0];
        Assert.Equal("Player One + Unknown User", card.Title);
        Assert.Equal(2, card.Members.Count);
        Assert.Equal("Duos", card.BandTypeLabel);
        Assert.Equal("1 appearance", card.AppearancesText);
        Assert.Equal("2 appearances", vm.Entries[1].AppearancesText);
        Assert.Equal(new AppRoute.Band("b1", "Band_Duets", "acc:mate1"), card.Route);
        Assert.Equal("fst.player-bands.row.b1", card.AutomationId);
        Assert.Equal("View band: Player One, Lead; Unknown User, Drums. Duos, 1 appearance", card.Announcement);
        var lead = card.Members[0];
        Assert.Equal("Lead", lead.InstrumentsText);
        Assert.Equal("instrument_guitar.png", lead.Icons.Single().File);
        Assert.Equal("Lead", lead.Icons.Single().Label);
        Assert.Equal(new AppRoute.Player("acc", "Player One"), lead.Route);
        Assert.Equal(new AppRoute.Player("mate1"), card.Members[1].Route);
        Assert.Equal("No observed instrument", new BandMemberRow(new BandMember { AccountId = "bad id" }).InstrumentsText);
        Assert.Null(new BandMemberRow(new BandMember { AccountId = "bad id" }).Route);
        Assert.Equal("fst.band.member.acc", lead.AutomationId);
        Assert.Equal("Player One, Lead", lead.Announcement);

        await vm.Pager.NextCommand.ExecuteAsync(null);
        Assert.Equal(2, vm.Pager.Page);
        Assert.Equal(5, vm.Entries.Count);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.Query == "?group=all&page=2&pageSize=25");

        vm.GroupIndex = 2;
        await Async.Until(() => vm.ShowRows && vm.Pager.Page == 1);
        Assert.Equal(PlayerBandGroup.Trios, vm.Group);
        Assert.Equal(2, vm.GroupIndex);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.Query == "?group=trios&page=1&pageSize=25");
        vm.GroupIndex = 9;
        Assert.Equal(PlayerBandGroup.Trios, vm.Group);
        Assert.Equal(4, vm.Groups.Count);
        var memberless = new PlayerBandCardViewModel(new PlayerBandEntry { BandType = "x", TeamKey = "a:b" });
        Assert.Equal("Band", memberless.BandTypeLabel);
        Assert.Equal("View band: Band. Band, 0 appearances", memberless.Announcement);
    }

    [Fact]
    public async Task SelectedPlayerNameEmptyFailureAndClamp()
    {
        var bands = new BandService();
        var session = bands.Service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer("acc", "Me") });
        bands.Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok(BandWire.PlayerBands("acc", 0, 0)) : null;
        var vm = new PlayerBandsViewModel(session, new AppRoute.PlayerBands("acc"));
        Assert.Equal("Me's Bands", vm.Title);
        await vm.LoadAsync();
        Assert.True(vm.ShowEmpty);
        Assert.Equal("No bands have been recorded for this player yet.", vm.EmptyMessage);
        vm.Group = PlayerBandGroup.Quads;
        Assert.Equal("No Quads have been recorded for this player yet.", vm.EmptyMessage);
        await Async.Until(() => vm.ShowEmpty);

        bands.Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.InternalServerError) : null;
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.True(vm.Status.HasIssue);

        // A page past the end (list shrank) reloads the last page.
        bands.Band = null;
        vm.Pager.PageCount = 9;
        vm.Pager.Page = 9;
        await vm.LoadAsync();
        Assert.Equal(2, vm.Pager.Page);
        Assert.True(vm.ShowRows);
        Assert.False(vm.Status.HasIssue);
    }

    [Fact]
    public async Task DiscardsLateResponses()
    {
        var bands = new BandService();
        var gate = new TaskCompletionSource();
        var fail = false;
        bands.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.Query.Contains("group=all", StringComparison.Ordinal)) await gate.Task;
            if (fail && request.RequestUri.Query.Contains("group=all", StringComparison.Ordinal)) return Wire.Response(HttpStatusCode.InternalServerError);
            return bands.Service.Override!(request) ?? Wire.Ok(Wire.Publication());
        };
        var vm = new PlayerBandsViewModel(bands.Service.Session(), new AppRoute.PlayerBands("acc"));
        var slow = vm.LoadAsync();
        vm.Group = PlayerBandGroup.Duos;
        await Async.Until(() => vm.ShowRows);
        var duoEntries = vm.Entries;
        gate.SetResult();
        await slow;
        Assert.Same(duoEntries, vm.Entries);

        fail = true;
        var gate2 = new TaskCompletionSource();
        bands.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.Query.Contains("group=all", StringComparison.Ordinal))
            {
                await gate2.Task;
                return Wire.Response(HttpStatusCode.InternalServerError);
            }
            return bands.Service.Override!(request) ?? Wire.Ok(Wire.Publication());
        };
        vm.Group = PlayerBandGroup.All;
        vm.Group = PlayerBandGroup.Trios;
        await Async.Until(() => vm.ShowRows && vm.Group == PlayerBandGroup.Trios);
        gate2.SetResult();
        await Async.Settle();
        Assert.True(vm.ShowRows);
    }
}

public class BandDetailViewModelTests
{
    private static AppRoute.Band Route(string? type = "Band_Duets", string? key = BandWire.Team) => new("fixture-band-1", type, key);

    [Fact]
    public async Task BareBandIdIsUnresolvedAndMakesNoRequest()
    {
        var bands = new BandService();
        foreach (var route in new[] { Route(null, null), Route("Band_Nope"), Route(key: "a:b:c:d:e") })
        {
            var vm = new BandDetailViewModel(bands.Service.Session(), route);
            Assert.False(vm.IsResolvable);
            Assert.True(vm.ShowUnresolved);
            Assert.False(vm.IsLoading);
            await vm.LoadAsync();
            Assert.Equal(LoadState.Idle, vm.State);
        }
        Assert.Empty(bands.Service.Handler.Requests);
    }

    [Fact]
    public async Task AverageStarsOfSix_DrawGoldStars()
    {
        var bands = new BandService();
        bands.Band = (path, _) => path.StartsWith("/api/rankings/bands/", StringComparison.Ordinal) && !path.EndsWith("/history", StringComparison.Ordinal)
                                  && !path.EndsWith("/songs", StringComparison.Ordinal)
            ? BandService.Ok(BandWire.Fixture("band-detail-demo").Replace("\"avgStars\": 4.9", "\"avgStars\": 6", StringComparison.Ordinal))
            : null;
        var vm = new BandDetailViewModel(bands.Service.Session(), Route());
        await vm.LoadAsync();
        var stars = vm.Statistics.Single(c => c.Id == "avg-stars");
        Assert.True(stars.GoldStars);
        Assert.False(stars.ShowValue);
        Assert.Equal("Avg Stars, 5 gold stars", stars.Announcement);
        Assert.True(vm.Statistics.Single(c => c.Id == "fc-rate").ShowValue);
    }

    [Fact]
    public async Task LoadsAllSections()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var bands = new BandService();
        var vm = new BandDetailViewModel(bands.Service.Session(), Route());
        Assert.True(vm.IsLoading);
        Assert.Equal("fixture-band-1", vm.BandId);
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.Equal("Fixture Rank One + Unknown User", vm.Title);
        Assert.Equal("Duos · 40 appearances", vm.Subtitle);
        Assert.Equal(["Fixture Rank One", "Unknown User"], vm.Members.Select(m => m.Name));
        Assert.Equal(["Duos", "40", "2"], vm.Summary.Select(c => c.Value));
        Assert.Equal("fst.band.stat.type", vm.Summary[0].AutomationId);
        Assert.Equal("Type, Duos", vm.Summary[0].Announcement);

        var stats = vm.Statistics.ToDictionary(c => c.Id);
        Assert.Equal("Total Score Rank", stats["rank"].Label);
        Assert.Equal("#1", stats["rank"].Value);
        Assert.Equal(new AppRoute.BandRankings("Band_Duets"), stats["rank"].Route);
        Assert.True(stats["rank"].IsLink);
        Assert.Equal("40 / 40", stats["songs-played"].Value);
        Assert.Equal("36 / 40", stats["full-combos"].Value);
        Assert.Equal("222,222,222", stats["total-score"].Value);
        Assert.Equal("90.0%", stats["fc-rate"].Value);
        Assert.Equal("99.2%", stats["avg-accuracy"].Value);
        Assert.Equal("4.9", stats["avg-stars"].Value);
        Assert.Equal("#1", stats["best-rank"].Value);
        Assert.Equal(new AppRoute.SongDetail("fixture-pulse"), stats["best-rank"].Route);
        Assert.Equal("#1.5", stats["avg-rank"].Value);
        Assert.False(stats["avg-rank"].IsLink);

        Assert.True(vm.ShowHistory);
        Assert.Null(vm.HistoryNote);
        Assert.Equal("Any-combo ranking progression over the past 30 days.", vm.HistoryHint);
        Assert.Equal([1, 2], vm.HistoryPoints.Select(p => p.Rank).Reverse());
        Assert.Equal((0.0, 1.0), (vm.HistoryPoints[0].X, vm.HistoryPoints[0].Y));
        Assert.Equal((1.0, 0.0), (vm.HistoryPoints[1].X, vm.HistoryPoints[1].Y));
        Assert.Equal(vm.HistoryPoints.Count, vm.HistoryChart!.Points.Count);
        Assert.Equal(vm.HistoryPoints.Select(p => p.Rank), vm.HistoryChart.Points.Select(p => p.Rank));
        Assert.Equal(["Sep 27", "Sep 26"], vm.HistoryRows.Select(r => r.Date));
        Assert.Equal("222,222,222", vm.HistoryRows[0].Value);
        Assert.Equal("fst.band.history-row.2026-09-27", vm.HistoryRows[0].AutomationId);
        Assert.Equal("Sep 27, rank #1, 222,222,222", vm.HistoryRows[0].Announcement);

        Assert.True(vm.ShowSongs);
        var best = vm.Best.Single();
        Assert.Equal("Pulse", best.Title);
        Assert.Equal("Fixture Artist · 2024", best.Subtitle);
        Assert.Equal("art-fixture-pulse.jpg", best.AlbumArt);
        Assert.Equal("Top 4%", best.PercentileText);
        Assert.Equal("#1 of 26", best.RankText);
        Assert.True(best.IsLink);
        Assert.Equal("fst.band.song-row.fixture-pulse", best.AutomationId);
        Assert.Equal("Pulse, Top 4%, rank #1 of 26", best.Announcement);
        var worst = vm.Worst.Single();
        Assert.Equal("Unknown Song", worst.Title);
        Assert.Equal("", worst.Subtitle);
        Assert.False(worst.IsLink);
        Assert.False(vm.BestEmpty || vm.WorstEmpty);
        Assert.Equal("Fixture Rank One + Unknown User's highest-ranked band songs, sorted by percentile.", vm.BestDescription);
        Assert.StartsWith("Fixture Rank One + Unknown User's lowest", vm.WorstDescription);

        vm.MetricIndex = 2;
        Assert.Equal(BandRankingMetric.FcRate, vm.Metric);
        Assert.Equal("FC Rate Rank", vm.Statistics[0].Label);
        Assert.Equal("#2", vm.Statistics[0].Value);
        Assert.Equal(["85.0%", "90.0%"], vm.HistoryRows.Select(r => r.Value).Reverse());
        vm.MetricIndex = 12;
        Assert.Equal(2, vm.MetricIndex);
        Assert.Equal(4, vm.Metrics.Count);
    }

    [Fact]
    public async Task SectionFailuresAreIndependentAndRetry()
    {
        var bands = new BandService();
        var failHistory = true;
        var failSongs = true;
        bands.Band = (p, _) =>
            failHistory && p.EndsWith("/history", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.InternalServerError)
            : failSongs && p.EndsWith("/songs", StringComparison.Ordinal) && p.StartsWith("/api/rankings", StringComparison.Ordinal) ? BandService.Unavailable()
            : null;
        var vm = new BandDetailViewModel(bands.Service.Session(), Route());
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.True(vm.HistoryFailed);
        Assert.True(vm.SongsFailed);
        Assert.Equal("Rank history unavailable", vm.HistoryStatus.Title);
        failHistory = failSongs = false;
        await vm.HistoryStatus.RetryCommand.ExecuteAsync(null);
        await vm.SongsStatus.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.ShowHistory);
        Assert.True(vm.ShowSongs);
    }

    [Fact]
    public async Task EmptyHistoryNotesMissingCatalogueAndMissingBand()
    {
        var bands = new BandService();
        bands.Band = (p, _) =>
            p.EndsWith("/history", StringComparison.Ordinal)
                ? BandService.Ok($$"""{"bandType":"Band_Duets","teamKey":"{{BandWire.Team}}","days":30,"history":[{"snapshotDate":"2026-09-01","adjustedSkillRank":0,"weightedRank":0,"fcRateRank":0,"totalScoreRank":0}],"historyStatus":"catching_up"}""")
            : p == "/api/songs" ? Wire.Response(HttpStatusCode.InternalServerError)
            : p.EndsWith("/songs", StringComparison.Ordinal)
                ? BandService.Ok($$"""{"bandType":"Band_Duets","teamKey":"{{BandWire.Team}}","limit":5,"best":[],"worst":[]}""")
            : null;
        var vm = new BandDetailViewModel(bands.Service.Session(), Route());
        await vm.LoadAsync();
        Assert.True(vm.HistoryEmpty);
        Assert.Empty(vm.HistoryPoints);
        Assert.Equal("History is catching up. Current rankings are already fresh.", vm.HistoryNote);
        Assert.EndsWith("fresh.", vm.HistoryHint);
        Assert.True(vm.ShowSongs);
        Assert.True(vm.BestEmpty && vm.WorstEmpty);
        Assert.Null(vm.Statistics.Single(c => c.Id == "best-rank").Route);

        bands.Band = (p, _) => p == "/api/rankings/bands/Band_Duets" ? BandService.Ok("""{"bandType":"Band_Duets","selectedBandEntry":null}""") : null;
        var missing = new BandDetailViewModel(bands.Service.Session(), Route());
        await missing.LoadAsync();
        Assert.True(missing.ShowError);
        Assert.Equal("This content is no longer available.", missing.Status.Message);
        Assert.Equal("Band not found", missing.Status.Title);
    }

    [Theory]
    [InlineData("failed", null, "Rank history is temporarily unavailable.")]
    [InlineData("ready", " Custom note ", "Custom note")]
    [InlineData("stale", null, "Rank history is behind the latest current rankings.")]
    [InlineData("disabled", "", "Rank history is disabled while current rankings remain available.")]
    [InlineData("current", null, null)]
    [InlineData(null, null, null)]
    public void HistoryNotes(string? status, string? message, string? expected) =>
        Assert.Equal(expected, BandDetailViewModel.HistoryNoteFor(new BandRankHistoryResponse { HistoryStatus = status, HistoryMessage = message }));

    [Fact]
    public void HistoryPoints_SingleAndFlat()
    {
        var one = BandHistoryPoint.Normalize([new BandRankHistoryEntry { TotalScoreRank = 3 }], BandRankingMetric.TotalScore);
        Assert.Equal((0.5, 0.5), (one[0].X, one[0].Y));
        var flat = BandHistoryPoint.Normalize(
            [new BandRankHistoryEntry { TotalScoreRank = 3 }, new BandRankHistoryEntry { TotalScoreRank = 3 }], BandRankingMetric.TotalScore);
        Assert.All(flat, p => Assert.Equal(0.5, p.Y));
        Assert.Empty(BandHistoryPoint.Normalize([], BandRankingMetric.Adjusted));
    }

    [Fact]
    public async Task StaleBandRowIsDiscarded()
    {
        var bands = new BandService();
        var gate = new TaskCompletionSource();
        var calls = 0;
        bands.Band = (p, _) =>
        {
            if (p != "/api/rankings/bands/Band_Duets") return null;
            if (Interlocked.Increment(ref calls) == 1) gate.Task.Wait();
            return null;
        };
        var vm = new BandDetailViewModel(bands.Service.Session(), Route());
        var first = Task.Run(vm.LoadAsync);
        await Async.Until(() => calls == 1);
        bands.Band = (p, _) => p == "/api/rankings/bands/Band_Duets" ? Wire.Response(HttpStatusCode.InternalServerError) : null;
        var second = vm.LoadAsync();
        await second;
        Assert.True(vm.ShowError);
        gate.SetResult();
        await first;
        Assert.True(vm.ShowError);
    }
}

public class SongBandLeaderboardViewModelTests
{
    private static AppSettings Player(string accountId) => new() { SelectedPlayer = new SelectedPlayer(accountId, "Me") };

    [Fact]
    public async Task PinsSelectedPlayersBand_OnEveryPage_WithJumpAndInPlaceHighlight()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var bands = new BandService();
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("t30a")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await vm.LoadAsync();
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.Query == "?top=25&offset=0&accountId=t30a");
        Assert.DoesNotContain(bands.Service.Handler.Requests, r => r.Headers.Keys.Any(k => k.StartsWith("X-FST-Selected", StringComparison.OrdinalIgnoreCase)));
        Assert.True(vm.ShowSpotlight);
        var pin = vm.Spotlight!;
        Assert.Equal("#30", pin.RankText);
        Assert.Equal("Lead 30 + Unknown User", pin.Name);
        Assert.True(pin.IsSelected);
        Assert.Equal("99,970", pin.Score);
        Assert.Equal("S9", pin.Season);
        Assert.False(pin.HasAccuracy || pin.IsFullCombo);
        Assert.Equal(0, pin.StarCount);
        Assert.Null(pin.Section);
        Assert.Equal(new AppRoute.Band("sb30", "Band_Duets", "t30a:t30b"), pin.Route);
        Assert.Equal("fst.song-band-leaderboard.spotlight-footer", pin.AutomationId);
        Assert.Equal("fst.score.accuracy.band-spotlight", pin.BadgeAutomationId);
        Assert.Equal("Your band's rank, 30th. Lead 30 + Unknown User, 99,970 points", pin.Announcement);
        Assert.DoesNotContain(vm.Rows, r => r.IsSelected);
        Assert.True(vm.CanJump);
        Assert.True(vm.JumpCommand.CanExecute(null));

        await vm.JumpCommand.ExecuteAsync(null);
        Assert.Equal(2, vm.Pager.Page);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.Query == "?top=25&offset=25&accountId=t30a");
        var own = Assert.Single(vm.Rows, r => r.IsSelected);
        Assert.Equal(30, own.Entry.Rank);
        Assert.All(own.Members, m => Assert.True(m.OnPlayerRow));
        Assert.All(vm.Rows.Where(r => !r.IsSelected).SelectMany(r => r.Members), m => Assert.False(m.OnPlayerRow));
        Assert.StartsWith("Your band. Rank 30. ", own.PageAnnouncement, StringComparison.Ordinal);
        Assert.True(vm.ShowSpotlight); // Still pinned on the band's own page (web hasSelectedFooter).
        Assert.False(vm.CanJump);
        Assert.False(vm.JumpCommand.CanExecute(null));
        await vm.JumpCommand.ExecuteAsync(null); // A no-op when it doesn't apply.
        Assert.Equal(2, vm.Pager.Page);

        await vm.Pager.LastCommand.ExecuteAsync(null);
        Assert.True(vm.ShowSpotlight && vm.CanJump);

        vm.BandTypeIndex = 1;
        await Async.Until(() => vm.ShowRows && vm.BandType == BandType.Trios && vm.Pager.Page == 1);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.AbsolutePath.EndsWith("/Band_Trios", StringComparison.Ordinal) && r.Uri.Query == "?top=25&offset=0&accountId=t30a");
        Assert.Equal(new AppRoute.Band("sb30", "Band_Trios", "t30a:t30b"), vm.Spotlight!.Route);

        var first = new SongBandSpotlightRow(new SongBandLeaderboardEntry
        {
            BandType = "Band_Duets", TeamKey = "a:b", Rank = 1, Score = 1234, Accuracy = 990000, IsFullCombo = true, Stars = 6,
            Members = [new BandMember { AccountId = "a", DisplayName = "Ann" }, new BandMember { AccountId = "b", DisplayName = "Bo" }],
        });
        Assert.Equal("Your band's rank, 1st. Ann + Bo, 1,234 points, 99% accuracy, full combo, 5 gold stars", first.Announcement);
        Assert.Equal(new AppRoute.Band("a:b", "Band_Duets", "a:b"), first.Route);
        Assert.Equal("", first.Season);
        Assert.Equal(990000, first.AccuracyValue);
        var unranked = first with { Entry = first.Entry with { Rank = 0 } };
        Assert.Equal("—", unranked.RankText);
        Assert.StartsWith("Your band. Ann + Bo", unranked.Announcement, StringComparison.Ordinal);
    }

    [Fact]
    public async Task NoPin_WithoutPlayer_WithoutBandScore_ForAnotherPlayer_OrOnFailure()
    {
        var bands = new BandService();
        var anonymous = new SongBandLeaderboardViewModel(bands.Service.Session(), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await anonymous.LoadAsync();
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.Query == "?top=25&offset=0");
        Assert.False(anonymous.ShowSpotlight || anonymous.CanJump);
        Assert.DoesNotContain(anonymous.Rows, r => r.IsSelected);

        var unsafeId = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("bad id")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await unsafeId.LoadAsync();
        Assert.True(unsafeId.ShowRows);
        Assert.DoesNotContain(bands.Service.Handler.Requests, r => r.Uri.Query.Contains("accountId=bad", StringComparison.Ordinal));

        var noScore = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("nobody")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await noScore.LoadAsync();
        Assert.True(noScore.ShowRows);
        Assert.False(noScore.ShowSpotlight);

        // A selected entry that doesn't include the requested player is not pinned.
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? BandService.Ok(BandWire.SongBands("s1", "Band_Duets", 25, 60, 0, 40)) : null;
        var other = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("t30a")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await other.LoadAsync();
        Assert.False(other.ShowSpotlight);

        bands.Band = null;
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("t3a")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await vm.LoadAsync();
        Assert.True(vm.ShowSpotlight);
        Assert.False(vm.CanJump);
        Assert.Single(vm.Rows, r => r.IsSelected);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.InternalServerError) : null;
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.False(vm.ShowSpotlight);
    }

    [Fact]
    public async Task SelectedEntryOfAnotherSize_IsRejected()
    {
        var bands = new BandService();
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(BandWire.SongBands("s1", "Band_Duets", 25, 60, 0, 3, "Band_Trios")) : null;
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(settings: Player("t3a")), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.False(vm.ShowSpotlight);
    }

    [Fact]
    public async Task FollowsSelectedPlayerWhileActive()
    {
        var bands = new BandService();
        var session = bands.Service.Session(settings: Player("t30a"));
        var vm = new SongBandLeaderboardViewModel(session, new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        vm.Activate();
        vm.Activate();
        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer("t5a", "Five") }); // Idle: nothing loaded yet.
        Assert.Empty(bands.Service.Handler.To("/api/leaderboard/s1/bands/Band_Duets"));
        await vm.LoadAsync();
        Assert.Equal("#5", vm.Spotlight!.RankText);

        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer("t7a", "Seven") });
        await Async.Until(() => vm.Spotlight?.RankText == "#7");
        session.UpdateSettings(s => s with { SelectedPlayer = null });
        await Async.Until(() => !vm.ShowSpotlight && vm.ShowRows);
        var reads = bands.Service.Handler.To("/api/leaderboard/s1/bands/Band_Duets").Count();
        session.UpdateSettings(s => s with { SelectedPlayer = null }); // Unchanged player: no re-read.
        vm.Deactivate();
        vm.Deactivate();
        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer("t9a", "Nine") });
        await Async.Settle();
        Assert.Equal(reads, bands.Service.Handler.To("/api/leaderboard/s1/bands/Band_Duets").Count());
        Assert.False(vm.ShowSpotlight);
    }

    [Fact]
    public async Task LoadsSwitchesAndPages()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var bands = new BandService();
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(), new AppRoute.SongBandLeaderboard("fixture-pulse", "Band_Trios"));
        Assert.Equal(BandType.Trios, vm.BandType);
        Assert.Equal("Trios Leaderboard", vm.Title);
        Assert.Equal("Trios", vm.Subtitle);
        Assert.Equal("", vm.SongTitle);
        await vm.LoadAsync();
        Assert.True(vm.ShowRows);
        Assert.Equal("Pulse", vm.SongTitle);
        Assert.Equal("Fixture Artist · 2024 · 3:20", vm.SongSubtitle);
        Assert.Equal("Trios · 60 entries", vm.Subtitle);
        Assert.Equal("1 / 3", vm.Pager.PageText);
        var row = vm.Rows[0];
        Assert.Equal("#1", row.Rank);
        Assert.Equal("Lead 1 + Unknown User", row.Names);
        Assert.Equal("99,999", row.Score);
        Assert.Equal("99.0%", row.Accuracy);
        Assert.True(row.HasAccuracy && row.IsFullCombo);
        Assert.Equal(6, row.StarCount);
        Assert.Equal(2, row.Members.Count);
        Assert.Equal("500", row.Members[0].ScoreText);
        Assert.True(row.Members[0].HasScore);
        Assert.False(row.Members[1].HasScore);
        Assert.Equal(new AppRoute.Band("sb1", "Band_Trios", "t1a:t1b"), row.Route);
        Assert.Equal("fst.song-band-leaderboard.row.sb1:1", row.AutomationId);
        Assert.Equal("Rank 1, Lead 1 + Unknown User, 99,999 points, 99.0% accuracy, full combo, 5 gold stars", row.Announcement);
        Assert.Equal("Rank 1. Lead 1, Lead, 500 points. Unknown User, Bass. " +
                     "Team score 99,999 points, full combo, 99.0% accuracy, 5 gold stars", row.PageAnnouncement);
        var plain = vm.Rows[1];
        Assert.False(plain.HasAccuracy || plain.IsFullCombo);
        Assert.Equal(0, plain.StarCount);
        Assert.Equal("Rank 2, Lead 2 + Unknown User, 99,998 points", plain.Announcement);
        Assert.EndsWith(". Team score 99,998 points", plain.PageAnnouncement, StringComparison.Ordinal);
        var keyless = new SongBandRow(new SongBandLeaderboardEntry { TeamKey = "x:y", BandType = "Band_Duets", Rank = 4 });
        Assert.Equal(new AppRoute.Band("x:y", "Band_Duets", "x:y"), keyless.Route);
        Assert.Equal("fst.song-band-leaderboard.row.x:y:4", keyless.AutomationId);

        await vm.Pager.LastCommand.ExecuteAsync(null);
        Assert.Equal(3, vm.Pager.Page);
        Assert.Equal(10, vm.Rows.Count);

        vm.BandTypeIndex = 2;
        await Async.Until(() => vm.ShowRows && vm.Pager.Page == 1);
        Assert.Equal(BandType.Quad, vm.BandType);
        Assert.Equal(2, vm.BandTypeIndex);
        Assert.Equal("Band size: Quads", vm.SwitcherName);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.AbsolutePath.EndsWith("/Band_Quad", StringComparison.Ordinal) && r.Uri.Query == "?top=25&offset=0");
        vm.BandTypeIndex = -1;
        Assert.Equal(BandType.Quad, vm.BandType);
        Assert.Equal(3, vm.BandTypes.Count);
        Assert.Single(bands.Service.Handler.To("/api/songs"));
    }

    [Fact]
    public async Task EmptyFailureUnknownTypeAndMissingCatalogue()
    {
        var bands = new BandService();
        bands.Band = (p, _) => p == "/api/songs" ? Wire.Response(HttpStatusCode.InternalServerError)
            : p.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? BandService.Ok(BandWire.SongBands("s1", "Band_Duets", 0, 0)) : null;
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(), new AppRoute.SongBandLeaderboard("s1", "Solo_Guitar"));
        Assert.Equal(BandType.Duets, vm.BandType);
        await vm.LoadAsync();
        Assert.True(vm.ShowEmpty);
        Assert.Equal("", vm.SongTitle);
        Assert.Equal("Duos · 0 entries", vm.Subtitle);
        Assert.Equal("No Duos scores have been recorded for this song yet.", vm.EmptyMessage);
        Assert.False(vm.Pager.IsVisible);

        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? BandService.Ok(BandWire.SongBands("s1", "Band_Duets", 1, 1)) : null;
        vm.Pager.PageCount = 5;
        vm.Pager.Page = 5;
        await vm.LoadAsync();
        Assert.Equal(1, vm.Pager.Page);
        Assert.True(vm.ShowRows);
        Assert.Equal("Duos · 1 entry", vm.Subtitle);

        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.NotFound) : null;
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.Equal("Failed to load band leaderboard", vm.Status.FallbackTitle);
    }

    [Fact]
    public async Task DiscardsLateBoards()
    {
        var bands = new BandService();
        var gate = new TaskCompletionSource();
        bands.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/Band_Duets", StringComparison.Ordinal)) await gate.Task;
            return bands.Service.Override!(request) ?? Wire.Ok(Wire.Publication());
        };
        var vm = new SongBandLeaderboardViewModel(bands.Service.Session(), new AppRoute.SongBandLeaderboard("s1", "Band_Duets"));
        var slow = vm.LoadAsync();
        vm.BandType = BandType.Trios;
        await Async.Until(() => vm.ShowRows);
        var trios = vm.Rows;
        gate.SetResult();
        await slow;
        Assert.Same(trios, vm.Rows);

        var gate2 = new TaskCompletionSource();
        bands.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/Band_Duets", StringComparison.Ordinal))
            {
                await gate2.Task;
                return Wire.Response(HttpStatusCode.InternalServerError);
            }
            return bands.Service.Override!(request) ?? Wire.Ok(Wire.Publication());
        };
        vm.BandType = BandType.Duets;
        vm.BandType = BandType.Quad;
        await Async.Until(() => vm.ShowRows && vm.BandType == BandType.Quad);
        gate2.SetResult();
        await Async.Settle();
        Assert.True(vm.ShowRows);
    }
}
