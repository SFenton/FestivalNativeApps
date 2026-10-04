using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>A fake service answering every player-page read; tweak the public fields per test.</summary>
public sealed class PlayerFakeService
{
    public FakeService Service { get; } = new();
    public Dictionary<string, (HttpStatusCode Status, string Body)> Profiles { get; } = new()
    {
        [PlayerWire.Id] = (HttpStatusCode.OK, PlayerWire.DefaultProfile()),
        [PlayerWire.Other] = (HttpStatusCode.OK, PlayerWire.DefaultProfile(PlayerWire.Other)),
    };
    public HttpStatusCode RankStatus { get; set; } = HttpStatusCode.OK;
    public HttpStatusCode RankHistoryStatus { get; set; } = HttpStatusCode.OK;
    public HttpStatusCode HistoryStatus { get; set; } = HttpStatusCode.OK;
    public string HistoryBody { get; set; } = PlayerWire.History(PlayerWire.Id,
        PlayerWire.HistoryEntry("s1", score: 900, acc: 950000, achieved: "2026-09-01T10:00:00Z"),
        PlayerWire.HistoryEntry("s1", score: 1200, acc: 990000, fc: true, achieved: "2026-09-05T10:00:00Z"),
        PlayerWire.HistoryEntry("s1", score: 1000, acc: 970000, season: 10, achieved: "2026-09-03T10:00:00Z"));
    public bool Header { get; set; } = true;

    public PlayerFakeService()
    {
        Service.Override = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            var pub = ("X-FST-Publication-Id", Service.PublicationId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            (string, string)[] headers = Header ? [pub] : [];
            var parts = path.Split('/');
            if (path.StartsWith("/api/rankings/", StringComparison.Ordinal))
            {
                if (path.EndsWith("/history", StringComparison.Ordinal))
                    return Wire.Response(RankHistoryStatus, PlayerWire.RankHistory(parts[4], parts[3],
                        PlayerWire.Snapshot("2026-09-01", 10), PlayerWire.Snapshot("2026-09-02", 7)), pub);
                return Wire.Response(RankStatus, RankStatus == HttpStatusCode.OK ? PlayerWire.Ranking(parts[4]) : "{}", pub);
            }
            if (path.EndsWith("/history", StringComparison.Ordinal))
                return Wire.Response(HistoryStatus, HistoryBody, pub);
            if (path.StartsWith("/api/player/", StringComparison.Ordinal))
                return Profiles.TryGetValue(parts[3], out var r) ? Wire.Response(r.Status, r.Body, headers) : Wire.Response(HttpStatusCode.NotFound, "{}", headers);
            return null;
        };
    }

    public FestivalSession Session(SelectedPlayer? player = null, AppSettings? settings = null) =>
        Service.Session(settings: (settings ?? new AppSettings()) with { SelectedPlayer = player });
}

public class PlayerProfileViewModelTests
{
    private static readonly SelectedPlayer One = new(PlayerWire.Id, "Fixture One");

    [Fact]
    public async Task Viewed_LoadsOverviewSectionsAndSelects()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id, "Route Name");
        Assert.True(vm.IsLoading);
        Assert.Empty(vm.QuickLinkSections);
        Assert.Equal("Route Name", vm.DisplayName);
        Assert.Equal(PlayerIdentityAction.None, vm.IdentityAction);
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.False(vm.IsSelected);
        Assert.Equal("Fixture One", vm.DisplayName);
        Assert.Equal(PlayerIdentityAction.Select, vm.IdentityAction);
        Assert.True(vm.CanSelect);
        Assert.False(vm.SelectNeedsConfirmation);
        Assert.Equal("Select Profile", vm.SelectLabel);
        Assert.False(vm.HasIdentityNotice);
        Assert.Equal(5, vm.Overview.Count);
        Assert.Equal(9, vm.Instruments.Count);
        Assert.Equal(11, vm.QuickLinkSections.Count);
        Assert.Equal(("global", "Global Statistics"), (vm.QuickLinkSections[0].Id, vm.QuickLinkSections[0].Title));
        Assert.Equal("instrument:" + vm.Instruments[0].Instrument.ServiceId(), vm.QuickLinkSections[1].Id);
        Assert.Equal(vm.Instruments[0].QuickLinkId, vm.QuickLinkSections[1].Id);
        Assert.Equal("bands", vm.QuickLinkSections[^1].Id);
        Assert.Equal(new AppRoute.PlayerBands(PlayerWire.Id), vm.BandsRoute);
        Assert.Equal("View Fixture One's Bands", vm.BandsLabel);
        Assert.Contains("Fixture One", vm.SwitchMessage);
        Assert.Contains("Fixture One", vm.SyncingMessage);
        Assert.Equal("Songs Played: 3", vm.Overview[0].Announcement);

        vm.Select();
        Assert.True(vm.IsSelected);
        Assert.Equal(PlayerIdentityAction.Deselect, vm.IdentityAction);
        Assert.True(vm.CanDeselect);
        Assert.Equal(SelectedProfileStatus.Available, session.SelectedProfileStatus);
        Assert.True(vm.ShowContent);

        vm.Deselect();
        Assert.False(session.HasPlayer);
        Assert.True(vm.ShowContent);
        Assert.Equal(PlayerIdentityAction.Select, vm.IdentityAction);
    }

    [Fact]
    public async Task Viewed_SwitchUnverifiedChangedAndActionError()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(new SelectedPlayer(PlayerWire.Other, "Two"));
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        Assert.Equal(PlayerIdentityAction.Switch, vm.IdentityAction);
        Assert.True(vm.SelectNeedsConfirmation);
        Assert.Equal("Switch to This Profile", vm.SelectLabel);

        fake.Service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        Assert.Equal(PlayerIdentityAction.Changed, vm.IdentityAction);
        Assert.Contains("changed", vm.IdentityNotice);
        vm.Select();
        Assert.Equal(PlayerWire.Other, session.SelectedPlayer!.AccountId);

        fake.Header = false;
        using var unverified = new PlayerProfileViewModel(session, PlayerWire.Id);
        await unverified.LoadAsync();
        Assert.Equal(PlayerIdentityAction.Unverified, unverified.IdentityAction);
        Assert.True(unverified.HasIdentityNotice);
        Assert.False(unverified.CanSelect);
        unverified.Deselect();
        Assert.True(session.HasPlayer);

        // A read that became unselectable between display and click reports an error instead of selecting.
        fake.Header = true;
        using var raced = new PlayerProfileViewModel(session, PlayerWire.Id);
        await raced.LoadAsync();
        Assert.True(raced.CanSelect);
        raced.Payload = raced.Payload! with { Profile = raced.Payload.Profile with { AccountId = "bad id" } };
        raced.Select();
        Assert.True(raced.HasActionError);
    }

    [Fact]
    public async Task Viewed_SyncingFailedAndRetry()
    {
        var fake = new PlayerFakeService();
        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing());
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        Assert.True(vm.IsSyncing);
        Assert.Empty(vm.Instruments);
        Assert.Equal(PlayerIdentityAction.None, vm.IdentityAction);

        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.InternalServerError, "{}");
        await vm.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.ShowError);
        Assert.True(vm.Status.HasIssue);

        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.OK, PlayerWire.DefaultProfile());
        await vm.Status.RetryCommand.ExecuteAsync(null);
        Assert.True(vm.ShowContent);
        Assert.False(vm.Status.HasIssue);
    }

    [Fact]
    public async Task Statistics_FollowsSelectionAndResetsOnSwitch()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(One);
        using var vm = new PlayerProfileViewModel(session, null);
        Assert.True(vm.FollowsSelection);
        await vm.LoadAsync();
        await Async.Until(() => vm.ShowContent);
        Assert.True(vm.IsSelected);
        Assert.Equal("Fixture One", vm.DisplayName);
        var reads = fake.Service.Handler.To($"/api/player/{PlayerWire.Id}").Count();
        await vm.LoadAsync();
        Assert.Equal(reads, fake.Service.Handler.To($"/api/player/{PlayerWire.Id}").Count());

        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer(PlayerWire.Other, "Two") });
        Assert.Equal(PlayerWire.Other, vm.AccountId);
        await Async.Until(() => vm.ShowContent && vm.Payload?.Profile.AccountId == PlayerWire.Other);
        Assert.True(vm.IsSelected);

        session.DeselectPlayer();
        Assert.False(vm.HasAccount);
        await Async.Settle();
        Assert.False(vm.IsLoading);
        Assert.False(vm.ShowContent);
    }

    [Fact]
    public async Task Statistics_MirrorsSessionFailureAndRetriesSelectedRead()
    {
        var fake = new PlayerFakeService();
        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.ServiceUnavailable, "{}");
        var session = fake.Session(One);
        using var vm = new PlayerProfileViewModel(session, null);
        await vm.LoadAsync();
        await Async.Until(() => vm.ShowError);
        Assert.Equal(ServiceIssueKind.Unavailable, vm.Status.Issue!.Kind);

        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing());
        await vm.Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => vm.IsSyncing);

        fake.Profiles[PlayerWire.Id] = (HttpStatusCode.OK, PlayerWire.DefaultProfile());
        await vm.Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => vm.ShowContent);
    }

    [Fact]
    public async Task VisibleInstrumentsRebuildSectionsWithoutReload()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        var reads = fake.Service.Handler.Requests.Count;
        session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Drums, false));
        Assert.Equal(8, vm.Instruments.Count);
        Assert.DoesNotContain(vm.Instruments, i => i.Instrument == Instrument.Drums);
        Assert.Equal(reads, fake.Service.Handler.Requests.Count);
        session.UpdateSettings(s => s with { ReduceMotion = true });
        Assert.Equal(8, vm.Instruments.Count);
    }

    [Fact]
    public async Task Dispose_StopsFollowingSession()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(One);
        var vm = new PlayerProfileViewModel(session, null);
        vm.Dispose();
        session.DeselectPlayer();
        Assert.Equal(PlayerWire.Id, vm.AccountId);
        await Async.Settle();
    }

    [Fact]
    public async Task NoAccount_IsIdle()
    {
        var fake = new PlayerFakeService();
        using var vm = new PlayerProfileViewModel(fake.Session(), null);
        await vm.LoadAsync();
        Assert.False(vm.HasAccount);
        Assert.False(vm.IsLoading);
        Assert.Equal(PlayerIdentityAction.None, vm.IdentityAction);
    }

    [Fact]
    public async Task Instrument_RankAndHistoryStates()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        var lead = vm.Instruments.Single(i => i.Instrument == Instrument.Lead);
        Assert.True(lead.HasScores);
        Assert.False(lead.IsEmpty);
        Assert.Equal("Lead", lead.Label);
        Assert.Equal("Solo_Guitar", lead.AutomationKey);
        Assert.Equal("instrument_guitar.png", lead.IconFile);
        Assert.Equal(["songs-played", "full-combos", "gold-stars", "stars-5", "avg-accuracy", "avg-stars", "best-rank",
            "global-rank", "total-score", "percentile"], lead.Stats.Select(t => t.Key));
        Assert.Equal("fst.player.stat.Solo_Guitar.best-rank", lead.Stats[6].AutomationId);
        Assert.Equal(new PlayerStatLink.SongDetail("s1", Instrument.Lead), lead.Stats[6].Link);
        Assert.All(lead.RankTiles, t => Assert.True(t.IsPending));
        Assert.False(lead.RankTiles[0].IsLinked);
        Assert.True(lead.RankHistoryLoading);
        Assert.True(lead.ShowRankHistoryCard);
        var avgStars = lead.Stats.Single(t => t.Label == "Avg Stars");
        Assert.Equal(5.5.ToString("0.##", System.Globalization.CultureInfo.CurrentCulture), avgStars.Value);
        Assert.True(avgStars.ShowValue);
        Assert.False(avgStars.GoldStars);
        Assert.True(lead.HasPercentiles);
        Assert.True(lead.RankLoading);
        await lead.EnsureLoadedAsync();
        await lead.EnsureLoadedAsync();
        Assert.Single(fake.Service.Handler.To($"/api/rankings/Solo_Guitar/{PlayerWire.Id}"));
        Assert.True(lead.RankAvailable);
        Assert.Equal("#12", lead.RankTiles[0].Value);
        Assert.True(lead.RankTiles[0].IsLinked);
        Assert.Equal("Opens Lead rankings", lead.RankTiles[0].Hint);
        Assert.False(lead.RankTiles[0].IsPending);
        Assert.False(lead.RankHistoryLoading);
        Assert.True(lead.HasRankHistory);
        Assert.False(lead.RankHistoryFailed);
        Assert.Equal("#7 of 500", lead.RankHistory!.Headline);

        fake.RankStatus = HttpStatusCode.NotFound;
        fake.RankHistoryStatus = HttpStatusCode.InternalServerError;
        await lead.LoadRankCommand.ExecuteAsync(null);
        await lead.LoadRankHistoryCommand.ExecuteAsync(null);
        Assert.True(lead.RankUnranked);
        Assert.Equal("Unranked", lead.RankTiles[0].Value);
        Assert.False(lead.RankTiles[0].IsLinked);
        Assert.True(lead.ShowRankHistoryCard);
        Assert.Contains("Lead", lead.UnrankedText);
        Assert.True(lead.RankHistoryFailed);
        Assert.StartsWith("Rank history unavailable", lead.RankHistoryError);
        Assert.False(lead.HasRankHistory);

        fake.RankStatus = HttpStatusCode.ServiceUnavailable;
        await lead.LoadRankCommand.ExecuteAsync(null);
        Assert.True(lead.RankFailed);
        Assert.StartsWith("Global rank unavailable", lead.RankError);

        var drums = vm.Instruments.Single(i => i.Instrument == Instrument.Drums);
        Assert.True(drums.IsEmpty);
        Assert.False(drums.ShowRankHistoryCard);
        Assert.Equal(4, drums.Stats.Count);
        Assert.False(drums.RankLoading);
        Assert.Contains("Drums", drums.EmptyText);
        await drums.EnsureLoadedAsync();
        Assert.Empty(fake.Service.Handler.To($"/api/rankings/Solo_Drums/{PlayerWire.Id}"));
    }

    [Fact]
    public async Task Instrument_CancelledReadsLeaveStateAlone()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session();
        using var vm = new PlayerProfileViewModel(session, PlayerWire.Id);
        await vm.LoadAsync();
        var release = new TaskCompletionSource();
        var inner = fake.Service.Override!;
        fake.Service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.StartsWith("/api/rankings/", StringComparison.Ordinal)) await release.Task;
            return inner(request) ?? Wire.Response(HttpStatusCode.NotFound);
        };
        var lead = vm.Instruments.Single(i => i.Instrument == Instrument.Lead);
        var loading = lead.EnsureLoadedAsync();
        lead.Cancel();
        release.SetResult();
        await loading;
        Assert.True(lead.RankLoading);
        Assert.False(lead.HasRankHistory);
    }
}

public class PlayerHistoryViewModelTests
{
    private static readonly AppRoute.PlayerHistory Route = new("s1", Instrument.Lead);

    [Fact]
    public async Task NoPlayer_MakesNoRequest()
    {
        var fake = new PlayerFakeService();
        using var vm = new PlayerHistoryViewModel(fake.Session(), Route);
        await vm.LoadAsync();
        Assert.Equal(PlayerHistoryPhase.NoPlayer, vm.Phase);
        Assert.True(vm.ShowMessage);
        Assert.Equal("No Player Selected", vm.MessageTitle);
        Assert.Contains("Select a player", vm.Message);
        Assert.Empty(fake.Service.Handler.To($"/api/player/{PlayerWire.Id}/history"));
    }

    [Fact]
    public async Task Loaded_SortsTracksBestAndCharts()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(new SelectedPlayer(PlayerWire.Id, "One"));
        using var vm = new PlayerHistoryViewModel(session, Route);
        Assert.Equal("Score History", vm.Title);
        await vm.LoadAsync();
        Assert.True(vm.ShowRows);
        Assert.Equal("Alpha · Lead", vm.Subtitle);
        Assert.Equal("instrument_guitar.png", vm.IconFile);
        Assert.Equal([1200L, 1000, 900], vm.Rows.Select(r => r.Entry.NewScore));
        Assert.True(vm.Rows[0].IsHighScore);
        Assert.Contains("↓", vm.SortLabel);
        Assert.Equal("Sort by Score, descending", vm.SortAnnouncement);
        Assert.True(vm.HasChart);
        Assert.Equal(3, vm.Chart!.Points.Count);

        vm.SortBy(PlayerScoreSortMode.Date);
        Assert.Equal([900L, 1000, 1200], vm.Rows.Select(r => r.Entry.NewScore).Reverse());
        vm.ToggleDirection();
        Assert.True(vm.SortAscending);
        Assert.Equal([900L, 1000, 1200], vm.Rows.Select(r => r.Entry.NewScore));
        Assert.True(vm.Rows[2].IsHighScore);
        vm.ResetSort();
        Assert.Equal(PlayerScoreSortMode.Score, vm.SortMode);
        Assert.False(vm.SortAscending);

        var best = vm.Rows[0];
        Assert.True(best.IsFullCombo);
        Assert.Equal("99%", best.Accuracy);
        Assert.True(best.HasAccuracy);
        Assert.Equal("Season 9", best.Season);
        Assert.EndsWith(" · Season 9", best.Detail);
        Assert.Equal(new StarRating(5, false), StarRating.From(best.StarCount));
        Assert.Contains("personal best", best.Announcement);
        Assert.Contains("full combo", best.Announcement);
        Assert.NotEmpty(best.Date);
        Assert.NotEmpty(best.Score);
    }

    [Fact]
    public async Task States_UnregisteredSyncingEmptyFailed()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(new SelectedPlayer(PlayerWire.Id, "One"));
        using var vm = new PlayerHistoryViewModel(session, new AppRoute.PlayerHistory("zz", Instrument.Bass));
        fake.HistoryStatus = HttpStatusCode.NotFound;
        await vm.LoadAsync();
        Assert.Equal(PlayerHistoryPhase.Unregistered, vm.Phase);
        Assert.Contains("registered users", vm.Message);
        Assert.Equal("Bass", vm.Subtitle);

        fake.HistoryStatus = HttpStatusCode.Accepted;
        fake.HistoryBody = """{"accountId":"fixtureplayer1","status":"syncing","notYetPublished":true,"count":0,"history":[]}""";
        await vm.LoadAsync();
        Assert.Equal(PlayerHistoryPhase.Syncing, vm.Phase);
        Assert.True(vm.CanRetryMessage);
        Assert.Equal("Still Syncing", vm.MessageTitle);
        Assert.NotEmpty(vm.Message);

        fake.HistoryStatus = HttpStatusCode.OK;
        fake.HistoryBody = PlayerWire.History(PlayerWire.Id);
        await vm.LoadAsync();
        Assert.Equal(PlayerHistoryPhase.Empty, vm.Phase);
        Assert.Contains("Bass", vm.Message);
        Assert.Equal("No History Yet", vm.MessageTitle);
        Assert.False(vm.HasChart);

        fake.HistoryStatus = HttpStatusCode.InternalServerError;
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.Equal("", vm.Message);
        Assert.False(vm.IsLoading);
    }

    [Fact]
    public async Task SelectionChange_Reloads()
    {
        var fake = new PlayerFakeService();
        var session = fake.Session(new SelectedPlayer(PlayerWire.Id, "One"));
        using var vm = new PlayerHistoryViewModel(session, Route);
        await vm.LoadAsync();
        session.UpdateSettings(s => s with { ReduceMotion = true });
        Assert.Single(fake.Service.Handler.To($"/api/player/{PlayerWire.Id}/history"));
        session.DeselectPlayer();
        await Async.Until(() => vm.Phase == PlayerHistoryPhase.NoPlayer);
        vm.Dispose();
        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "One") });
        await Async.Settle();
        Assert.Equal(PlayerHistoryPhase.NoPlayer, vm.Phase);
    }

    [Fact]
    public void Row_OptionalFields()
    {
        var row = new ScoreHistoryRow(new ScoreHistoryEntry { NewScore = 5, Stars = 6, ChangedAt = "x" }, false);
        Assert.Equal("", row.Accuracy);
        Assert.False(row.HasAccuracy);
        Assert.Equal("", row.Season);
        Assert.Equal(row.Date, row.Detail);
        Assert.Equal(new StarRating(5, true), StarRating.From(row.StarCount));
        Assert.Equal(0, new ScoreHistoryRow(new ScoreHistoryEntry { ChangedAt = "x" }, false).StarCount);
        Assert.DoesNotContain("personal best", row.Announcement);
        // Six stars read as the five gold images drawn (issue #221), and 0 / missing read nothing (no star images).
        Assert.Contains(", 5 gold stars", row.Announcement, StringComparison.Ordinal);
        Assert.DoesNotContain("6 stars", row.Announcement, StringComparison.Ordinal);
        Assert.Contains(", 1 star", new ScoreHistoryRow(new ScoreHistoryEntry { NewScore = 5, Stars = 1, ChangedAt = "x" }, false).Announcement, StringComparison.Ordinal);
        Assert.DoesNotContain("star", new ScoreHistoryRow(new ScoreHistoryEntry { NewScore = 5, Stars = 0, ChangedAt = "x" }, false).Announcement, StringComparison.Ordinal);
        Assert.DoesNotContain("star", new ScoreHistoryRow(new ScoreHistoryEntry { NewScore = 5, ChangedAt = "x" }, false).Announcement, StringComparison.Ordinal);
    }
}

public class PlayerChartTests
{
    [Fact]
    public void RankHistory_GeometryAndSingles()
    {
        Assert.Null(RankHistoryChartModel.Build([]));
        var snapshots = new List<PlayerRankHistorySnapshot>
        {
            new() { SnapshotDate = "2026-09-01", TotalScoreRank = 10, TotalScore = 50, RankedAccountCount = 100 },
            new() { SnapshotDate = "2026-09-02", TotalScoreRank = 5, TotalScore = 100, RankedAccountCount = 100 },
        };
        var chart = RankHistoryChartModel.Build(snapshots)!;
        Assert.Equal(0, chart.RankLine[0].X);
        Assert.Equal(1, chart.RankLine[1].X);
        Assert.True(chart.RankLine[1].Y < chart.RankLine[0].Y);
        Assert.True(chart.RankLine[1].Highlight);
        Assert.Equal(0.5, chart.ScoreBars[0].Height);
        Assert.Equal("#5 of 100", chart.Headline);
        Assert.Equal("Total Score 100", chart.TotalScoreLine);
        Assert.StartsWith("#", chart.RankTicks[0].Label);
        Assert.Contains("up 5 places", chart.Summary);
        Assert.NotEqual(chart.StartLabel, chart.EndLabel);

        var single = RankHistoryChartModel.Build([new PlayerRankHistorySnapshot { SnapshotDate = "bad", TotalScoreRank = 3 }])!;
        Assert.Equal(0.5, single.RankLine[0].X);
        Assert.Empty(single.ScoreBars);
        Assert.Null(single.TotalScoreLine);
        Assert.Equal("#3", single.Headline);
        Assert.Equal("bad", single.StartLabel);
    }

    [Fact]
    public void PercentileBars_Normalize()
    {
        var bars = PercentileBar.Build([new PlayerPercentileBucket(1, 1), new PlayerPercentileBucket(10, 4)]);
        Assert.Equal(0.25, bars[0].Fraction);
        Assert.True(bars[0].Gold);
        Assert.False(bars[1].Gold);
        Assert.Equal("Top 1%: 1 song", bars[0].Announcement);
        Assert.Equal("Top 10%: 4 songs", bars[1].Announcement);
        Assert.Empty(PercentileBar.Build([]));
    }

    [Fact]
    public void ScoreHistory_NeedsTwoDatedRows()
    {
        Assert.Null(ScoreHistoryChartModel.Build([new ScoreHistoryEntry { NewScore = 1, ChangedAt = "2026-01-01T00:00:00Z" },
            new ScoreHistoryEntry { NewScore = 2, ChangedAt = "nope" }]));
        var chart = ScoreHistoryChartModel.Build([
            new ScoreHistoryEntry { NewScore = 200, ChangedAt = "2026-01-03T00:00:00Z" },
            new ScoreHistoryEntry { NewScore = 100, ChangedAt = "2026-01-01T00:00:00Z" },
        ])!;
        Assert.Equal(0, chart.Points[0].X);
        Assert.Equal(1, chart.Points[1].X);
        Assert.True(chart.Points[1].Highlight);
        Assert.False(chart.Points[0].Highlight);
        Assert.True(chart.Points[1].Y < chart.Points[0].Y);
        Assert.Equal(3, chart.Ticks.Count);
        Assert.Contains("2 score changes", chart.Summary);
    }
}

public class ShellProfileFlyoutTests
{
    [Fact]
    public async Task BandScope_DisablesSearchAndExplains()
    {
        var service = new FakeService();
        var time = new FakeTimeProvider();
        var shell = new ShellViewModel(service.Session(time));
        Assert.True(shell.IsPlayerScope);
        Assert.Equal("Find Player", shell.SearchPlaceholder);
        shell.ProfileQuery = "abc";
        shell.IsBandScope = true;
        Assert.Equal("Find Band", shell.SearchPlaceholder);
        Assert.Equal(ShellViewModel.BandSearchExplanation, shell.ProfileHint);
        Assert.False(shell.CanRetrySearch);
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Settle();
        Assert.Empty(service.Handler.To("/api/account/search"));
        shell.IsBandScope = false;
        Assert.True(shell.IsPlayerScope);
        // Back on Players, the kept text searches again at once.
        await Async.Until(() => service.Handler.To("/api/account/search").Any());
    }

    [Fact]
    public async Task Retry_SearchesImmediatelyAfterEmptyOrError()
    {
        var service = new FakeService();
        var results = "[]";
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/account/search" ? Wire.Ok($$"""{"results":{{results}}}""") : null;
        var time = new FakeTimeProvider();
        var shell = new ShellViewModel(service.Session(time));
        shell.ProfileQuery = "abc";
        await Async.Settle();
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Until(() => !shell.ProfileSearch.PlayersLoading && service.Handler.To("/api/account/search").Any());
        await Async.Until(() => shell.CanRetrySearch);
        results = """[{"accountId":"acc1","displayName":"Found"}]""";
        shell.RetrySearchCommand.Execute(null);
        await Async.Until(() => shell.ProfileResults.Count == 1);
        Assert.False(shell.CanRetrySearch);
    }

    [Fact]
    public void ViewSelected_RaisesRouteAndSelectionLoadsScores()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var session = service.Session();
        var shell = new ShellViewModel(session);
        AppRoute? opened = null;
        shell.RouteRequested += (_, route) => opened = route;
        shell.ViewSelectedProfileCommand.Execute(null);
        Assert.Null(opened);
        shell.ViewProfileCommand.Execute(new GlobalPlayerResult("bad id", "X", false));
        Assert.Null(opened);
        Assert.Equal("", shell.ProfileDisplayName);
        session.SelectPlayer(new PlayerSearchResult(PlayerWire.Id, "Fixture One"));
        Assert.Equal("Fixture One", shell.ProfileDisplayName);
        Assert.NotEqual(SelectedProfileStatus.None, session.SelectedProfileStatus);
        shell.ViewSelectedProfileCommand.Execute(null);
        Assert.Equal(new AppRoute.Player(PlayerWire.Id, "Fixture One"), opened);
    }

    [Fact]
    public async Task RestoredPlayer_LoadsScoresOnStartup()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "One") });
        _ = new ShellViewModel(session);
        await Async.Until(() => session.SelectedProfileStatus == SelectedProfileStatus.Available);
    }

    [Fact]
    public void SelectingKeepsExistingSectionsInPlace()
    {
        var session = new FakeService().Session();
        var shell = new ShellViewModel(session);
        var sawEmpty = false;
        shell.Sections.CollectionChanged += (_, _) => sawEmpty |= shell.Sections.Count == 0 || !shell.Sections.Contains(AppSection.Leaderboards);
        session.SelectPlayer(new PlayerSearchResult("acc", "Jane"));
        Assert.Equal(AppSections.Visible(true), shell.Sections);
        session.DeselectPlayer();
        Assert.Equal(AppSections.Visible(false), shell.Sections);
        Assert.False(sawEmpty);
    }
}

public class ProfileLaunchOptionTests
{
    [Fact]
    public void DebugProfileAnonymousAndSettingsPath()
    {
        var options = LaunchOptions.Parse(["--profile", "acc-1:Jane Doe", "--settings-path", @"C:\x\s.json"], _ => null);
        Assert.Equal(new SelectedPlayer("acc-1", "Jane Doe"), options.DebugProfile);
        Assert.Equal(@"C:\x\s.json", options.SettingsPath);
        Assert.True(options.InMemorySettings);
        Assert.False(options.Anonymous);

        var env = LaunchOptions.Parse([], name => name switch
        {
            "FST_DEBUG_ANONYMOUS" => "1",
            "FST_SETTINGS_PATH" => "p.json",
            _ => null,
        });
        Assert.True(env.Anonymous);
        Assert.True(env.InMemorySettings);
        Assert.Null(env.DebugProfile);
        Assert.Equal("p.json", env.SettingsPath);

        var bad = LaunchOptions.Parse(["--profile=bad id", "--anonymous"], name => name == "FST_DEBUG_PROFILE" ? "x:y" : null);
        Assert.Null(bad.DebugProfile);
        Assert.True(bad.Anonymous);
        Assert.Contains(bad.Warnings, w => w.Contains("Debug profile"));
        Assert.False(LaunchOptions.Parse([], _ => null).InMemorySettings);
    }
}
