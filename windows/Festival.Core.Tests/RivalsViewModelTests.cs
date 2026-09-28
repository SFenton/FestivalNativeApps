using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>A fake service that answers the Rivals endpoints from the shared fixtures, with per-path overrides.</summary>
public sealed class RivalsFakeService
{
    public const string Me = "fixture-me";
    public const string Rival = "408abb67d81446f0ac714506950ce178";

    public FakeService Service { get; } = new();
    public FakeTimeProvider Time { get; } = new();
    public Dictionary<string, Func<HttpResponseMessage>> Paths { get; } = new(StringComparer.Ordinal);
    public Func<string, HttpResponseMessage?>? Fallback { get; set; }

    public RivalsFakeService()
    {
        Service.Override = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            if (!path.StartsWith("/api/player/", StringComparison.Ordinal)) return null;
            if (Paths.TryGetValue(path, out var custom)) return custom();
            if (Fallback?.Invoke(path) is { } fallback) return fallback;
            var depth = path.Count(c => c == '/');
            if (path.Contains("/leaderboard-rivals/", StringComparison.Ordinal))
                return Wire.Ok(depth == 6
                    ? RivalsCoreTests.Fixture("leaderboard-rival-detail-demo").Replace("75a76ce7304d49c0ab76ea7ff5c3288e", Rival)
                    : RivalsCoreTests.Fixture("leaderboard-rivals-demo"));
            return Wire.Ok(RivalsCoreTests.Fixture(depth == 6 ? "rival-detail-demo" : "rivals-list-demo"));
        };
    }

    public FestivalSession Session(AppSettings? settings = null) =>
        Service.Session(Time, settings ?? Settings());

    public static AppSettings Settings(params Instrument[] visible) => new AppSettings
    {
        SelectedPlayer = new SelectedPlayer(Me, "Me Player"),
        VisibleInstruments = visible.Length == 0 ? [Instrument.Lead, Instrument.Bass] : visible,
    }.Sanitized();

    public int Count(string path) => Service.Handler.To(path).Count();

    public static HttpResponseMessage Frozen() => Wire.Response(HttpStatusCode.ServiceUnavailable, "",
        ("Retry-After", "30"), (ServiceFreezeReason.Header, "scrape"));
}

public class RivalsViewModelTests
{
    private const string Me = RivalsFakeService.Me;
    private const string Rival = RivalsFakeService.Rival;

    #region Hub
    [Fact]
    public void Hub_WithoutPlayerShowsChooseProfile()
    {
        var fake = new RivalsFakeService();
        var hub = new RivalsHubViewModel(fake.Session(new AppSettings()));
        hub.Activate();
        Assert.Equal(RivalsHubState.NoPlayer, hub.State);
        Assert.True(hub.ShowNoPlayer);
        Assert.Empty(hub.Sections);
        hub.Deactivate();
        hub.Deactivate();
    }

    [Fact]
    public async Task Hub_SongTabBuildsCommonComboAndInstrumentSections()
    {
        var fake = new RivalsFakeService();
        var hub = new RivalsHubViewModel(fake.Session());
        hub.Activate();
        await Async.Until(() => hub.State == RivalsHubState.Loaded && hub.Sections.All(s => s.State == LoadState.Loaded));

        Assert.Equal(["common", "combo", "Solo_Guitar", "Solo_Bass"], hub.Sections.Select(s => s.Id));
        Assert.True(hub.QuickLinks.IsAvailable);
        Assert.Equal(["common", "combo", "Solo_Guitar", "Solo_Bass"], hub.QuickLinks.Items.Select(i => i.Section.Id));
        Assert.Equal([RivalsHubViewModel.CommonGlyph, RivalsHubViewModel.ComboGlyph, "", ""], hub.QuickLinks.Items.Select(i => i.Glyph));
        Assert.Equal(Instrument.Bass, hub.QuickLinks.Items[3].Section.Instrument);
        Assert.Equal(["Common Rivals", "Combined Rivals", "Lead Rivals", "Bass Rivals"], hub.Sections.Select(s => s.Title));
        var lead = hub.Sections[2];
        Assert.Equal(6, lead.Rows.Count);
        Assert.Equal(RivalDirection.Above, lead.Rows[0].Direction);
        Assert.Equal(RivalDirection.Below, lead.Rows[5].Direction);
        Assert.Equal(new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead])), lead.ViewAllRoute);
        Assert.Equal(new RivalScope.Song([Instrument.Lead]), lead.Rows[0].Route.Scope);
        Assert.True(lead.HasIcon);
        Assert.Equal("instrument_guitar.png", lead.IconFile);
        Assert.Equal("fst.rivals.section.Solo_Guitar", lead.AutomationId);
        Assert.Equal("See all Lead Rivals", lead.SeeAllName);
        Assert.False(hub.Sections[0].HasIcon);
        Assert.Equal("", hub.Sections[0].IconFile);
        Assert.Equal(new RivalScope.Combo("03"), hub.Sections[1].Rows[0].Route.Scope);
        Assert.True(lead.ShowRows);
        Assert.False(lead.IsLoading);
        Assert.False(lead.ShowError);

        // Common Rivals reuses the per-instrument reads through the shared cache.
        Assert.Equal(1, fake.Count($"/api/player/{Me}/rivals/Solo_Guitar"));
        Assert.Equal(1, fake.Count($"/api/player/{Me}/rivals/03"));
        hub.Deactivate();
    }

    [Fact]
    public async Task Hub_RemovesEmptySectionsAndShowsEmptyState()
    {
        var fake = new RivalsFakeService { Fallback = _ => Wire.Response(HttpStatusCode.NotFound, """{"error":"No rivals found."}""") };
        var hub = new RivalsHubViewModel(fake.Session());
        hub.Activate();
        await Async.Until(() => hub.State == RivalsHubState.Empty);
        Assert.Empty(hub.Sections);
        Assert.False(hub.QuickLinks.IsAvailable);
        Assert.True(hub.ShowEmpty);
        Assert.StartsWith("Not enough data", hub.EmptyTitle);
        Assert.Contains("instruments", hub.EmptySubtitle);

        var single = new RivalsHubViewModel(fake.Session(RivalsFakeService.Settings(Instrument.Drums)));
        single.Activate();
        await Async.Until(() => single.State == RivalsHubState.Empty);
        Assert.Contains("instrument to", single.EmptySubtitle);
    }

    [Fact]
    public async Task Hub_SectionFailureShowsInlineStatusAndRetries()
    {
        var fake = new RivalsFakeService();
        var frozen = true;
        fake.Paths[$"/api/player/{Me}/rivals/Solo_Guitar"] = () =>
            frozen ? RivalsFakeService.Frozen() : Wire.Ok(RivalsCoreTests.Fixture("rivals-list-demo"));
        var hub = new RivalsHubViewModel(fake.Session(RivalsFakeService.Settings(Instrument.Lead)));
        hub.Activate();
        var lead = hub.Sections.Single();
        await Async.Until(() => lead.State == LoadState.Failed);
        Assert.Equal(RivalsHubState.Loaded, hub.State);
        Assert.True(lead.ShowError);
        Assert.True(lead.Status.Issue!.RetriesAutomatically);

        frozen = false;
        await lead.Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => lead.State == LoadState.Loaded);
        Assert.Null(lead.Status.Issue);
    }

    [Fact]
    public async Task Hub_CommonReportsFailureWhenFewerThanTwoListsLoad()
    {
        var fake = new RivalsFakeService { Fallback = path => path.EndsWith("/Solo_Bass", StringComparison.Ordinal) ? RivalsFakeService.Frozen() : null };
        var hub = new RivalsHubViewModel(fake.Session());
        hub.Activate();
        await Async.Until(() => hub.Sections.Count == 4 && hub.Sections.All(s => s.State is LoadState.Loaded or LoadState.Failed));
        Assert.Equal(LoadState.Failed, hub.Sections[0].State);
        Assert.Equal(LoadState.Failed, hub.Sections[3].State);
        Assert.Equal(LoadState.Loaded, hub.Sections[2].State);
    }

    [Fact]
    public async Task Hub_LeaderboardTabHonoursExperimentalMetric()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session(RivalsFakeService.Settings(Instrument.Lead));
        var hub = new RivalsHubViewModel(session);
        hub.Activate();
        hub.ToggleTabCommand.Execute(null);
        Assert.True(hub.IsLeaderboardTab);
        Assert.Equal("Leaderboard Rivals", hub.Title);
        Assert.Equal("Song Rivals", hub.ToggleTabLabel);
        Assert.False(hub.ShowMetricPicker);
        await Async.Until(() => hub.Sections.Single().State == LoadState.Loaded);
        var row = hub.Sections.Single().Rows[0];
        Assert.True(row.HasRank);
        Assert.Equal("#2", row.RankText);
        Assert.Contains("rank 2", row.AccessibleName);
        Assert.Equal(new RivalScope.Leaderboard(Instrument.Lead, RankingMetric.TotalScore), row.Route.Scope);
        Assert.Equal("fst.rivals.section.leaderboard.Solo_Guitar", hub.Sections.Single().AutomationId);

        hub.MetricIndex = RankingMetricInfo.All.ToList().IndexOf(RankingMetric.FcRate);
        Assert.Equal(RankingMetric.FcRate, hub.Metric);
        hub.MetricIndex = 99;
        Assert.Equal(RankingMetric.FcRate, hub.Metric);
        Assert.DoesNotContain(fake.Service.Handler.Requests, r => r.Uri.Query.Contains("fcrate", StringComparison.Ordinal));

        // Settings sanitizes experimental ranks off (as in production web), so the picker stays hidden.
        session.UpdateSettings(s => s with { ExperimentalRanks = true });
        Assert.False(hub.ShowMetricPicker);
        Assert.Equal(hub.MetricLabels[hub.MetricIndex], RankingMetric.FcRate.Label());

        hub.IsLeaderboardTab = false;
        Assert.Equal("Song Rivals", hub.Title);
    }

    [Fact]
    public async Task Hub_RebuildsOnSettingsAndRefresh()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session(RivalsFakeService.Settings(Instrument.Lead));
        var hub = new RivalsHubViewModel(session);
        hub.Activate();
        await Async.Until(() => hub.State == RivalsHubState.Loaded);
        session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Bass, true));
        Assert.Equal(4, hub.Sections.Count);

        hub.Deactivate();
        session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Bass, false));
        Assert.Equal(4, hub.Sections.Count);
        hub.Activate();
        Assert.Single(hub.Sections);

        await Async.Until(() => hub.State == RivalsHubState.Loaded);
        var before = fake.Count($"/api/player/{Me}/rivals/Solo_Guitar");
        hub.RefreshCommand.Execute(null);
        await Async.Until(() => fake.Count($"/api/player/{Me}/rivals/Solo_Guitar") == before + 1);

        session.DeselectPlayer();
        Assert.Equal(RivalsHubState.NoPlayer, hub.State);
    }
    #endregion

    #region Find rival
    [Fact]
    public async Task FindRival_DebouncesSearchesAndExcludesSelf()
    {
        var fake = new RivalsFakeService();
        fake.Service.Override = request => request.RequestUri!.AbsolutePath == "/api/account/search"
            ? Wire.Ok($$"""{"results":[{"accountId":"{{Me}}","displayName":"Me Player"},{"accountId":"r2","displayName":"Other"}]}""")
            : null;
        var find = new RivalsHubViewModel(fake.Session()).FindRival;
        Assert.StartsWith("Enter at least", find.PlayersHint);
        find.Query = "Ot";
        Assert.Equal("Searching…", find.PlayersHint);
        await Async.Advance(fake.Time, ShellViewModel.SearchDebounce);
        await Async.Until(() => find.Players.Count == 1);
        Assert.Equal("r2", find.Players[0].AccountId);
        Assert.Equal("", find.PlayersHint);
        Assert.Empty(find.Songs);
        Assert.Empty(find.Suggestions);
        Assert.Empty(fake.Service.Handler.To("/api/songs"));
        Assert.Equal(new AppRoute.RivalDetail("r2", "Other", AllowLiveFallback: true), RivalsHubViewModel.FindRivalRoute(find.Players[0]));

        find.Query = "x";
        await Async.Settle();
        Assert.Empty(find.Players);
        find.Reset();
        Assert.Equal("", find.Query);
        Assert.Equal(SearchScope.Players, find.Scope);
    }

    [Fact]
    public async Task FindRival_ReportsFailures()
    {
        var fake = new RivalsFakeService();
        fake.Service.Override = _ => Wire.Response(HttpStatusCode.TooManyRequests);
        var find = new RivalsHubViewModel(fake.Session()).FindRival;
        find.Query = "Name";
        await Async.Advance(fake.Time, ShellViewModel.SearchDebounce);
        await Async.Until(() => find.PlayersFailed);
        Assert.Equal(find.PlayersStatus.Message, find.PlayersHint);
        Assert.True(find.CanRetryPlayers);
        Assert.False(find.PlayersLoading);
    }

    [Fact]
    public async Task FindRival_ShowsNoResults()
    {
        var fake = new RivalsFakeService();
        fake.Service.Override = _ => Wire.Ok("""{"results":[]}""");
        var find = new RivalsHubViewModel(fake.Session()).FindRival;
        find.Query = "Nobody";
        await Async.Advance(fake.Time, ShellViewModel.SearchDebounce);
        await Async.Until(() => find.PlayersHint == "No players found.");
        Assert.True(find.CanRetryPlayers);
    }
    #endregion

    #region Rows
    [Fact]
    public void RivalRow_UsesRivalPerspectiveCounts()
    {
        var row = RivalRowItem.From(new RivalSummary("a1", null, 1, 1234, 7, 3, 0), RivalDirection.Below, null);
        Assert.Equal(RivalRowItem.UnknownName, row.Name);
        Assert.True(row.IsWinning);
        Assert.Equal("3 songs ahead", row.AheadText);
        Assert.Equal("7 songs behind", row.BehindText);
        Assert.Equal("", row.RankText);
        Assert.Contains("behind you", row.AccessibleName);
        Assert.Equal("fst.rivals.row.a1", row.AutomationId);
        Assert.Contains("ahead of you", (row with { Direction = RivalDirection.Above }).AccessibleName);
    }

    [Fact]
    public void RivalSongItem_EnrichesFromCatalogue()
    {
        var comparison = new RivalSongComparison("s1", null, null, "Solo_PeripheralCymbals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
            3, 9, 6, 1000, null);
        var song = new Song { SongId = "s1", Title = "Catalog", Artist = "Band", Year = 2024, AlbumArt = "art.jpg", Sig = "Keyboard" };
        var item = new RivalSongItem(comparison, song, "Me", "Them");
        Assert.Equal("Catalog", item.Title);
        Assert.Equal("Band · 2024", item.Subtitle);
        Assert.Equal("art.jpg", item.AlbumArt);
        Assert.True(item.IsMixedInstrument);
        Assert.Equal("Pro Drums + Cymbals vs Pro Drums", item.InstrumentLabel);
        Assert.Equal(RivalSongOutcome.Winning, item.Outcome);
        Assert.True(item.IsWinning);
        Assert.False(item.IsLosing);
        Assert.Equal("#3", item.UserRankText);
        Assert.Equal("#9", item.RivalRankText);
        Assert.Equal("1,000", item.UserScoreText);
        Assert.Equal("", item.RivalScoreText);
        Assert.Equal("+6", item.RankDeltaText);
        Assert.Equal("+1,000", item.ScoreDiffText);
        Assert.Contains("you lead", item.AccessibleName);
        Assert.Equal(new AppRoute.SongDetail("s1", Instrument.ProCymbals), item.Route);
        Assert.Equal("fst.rivalry.song.s1.Solo_PeripheralCymbals", item.AutomationId);

        var plain = new RivalSongItem(comparison with { Title = "T", Artist = null, UserInstrument = null, RivalInstrument = null, RankDelta = 0 }, null, "Me", "Them");
        Assert.Equal("T", plain.Title);
        Assert.Equal("", plain.Subtitle);
        Assert.False(plain.IsMixedInstrument);
        Assert.Contains("tied", plain.AccessibleName);
        Assert.Equal(RivalSongOutcome.Losing, new RivalSongItem(comparison with { RankDelta = -1 }, null, "Me", "Them").Outcome);
        Assert.Equal("Band", new RivalSongItem(comparison, song with { Year = null }, "Me", "Them").Subtitle);
    }
    #endregion

    #region Pages
    [Fact]
    public async Task AllRivals_LoadsEachScope()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session();

        var lead = await Loaded(new AllRivalsViewModel(session, new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead]))));
        Assert.Equal("Lead Rivals", lead.Title);
        Assert.True(lead.HasIcon);
        Assert.Equal(6, lead.Rows.Count);

        var board = await Loaded(new AllRivalsViewModel(session, new AppRoute.AllRivals(new RivalScope.Leaderboard(Instrument.Bass, RankingMetric.TotalScore))));
        Assert.Equal("Ranked by Total Score · You are #1", board.Subtitle);
        Assert.Equal("instrument_bass.png", board.IconFile);

        var common = await Loaded(new AllRivalsViewModel(session, new AppRoute.AllRivals(new RivalScope.FromSettings(RivalSettingsScope.Common))));
        Assert.Equal("Common Rivals", common.Title);
        Assert.Equal("Lead, Bass", common.Subtitle);
        Assert.False(common.HasIcon);

        var combo = await Loaded(new AllRivalsViewModel(session, new AppRoute.AllRivals(new RivalScope.Combo("pro_drums"))));
        Assert.Equal("Pro Drums Family Rivals", combo.Title);
        Assert.Equal("Pro Drums + Cymbals, Pro Drums", combo.Subtitle);

        var unknown = new AllRivalsViewModel(fake.Session(RivalsFakeService.Settings(Instrument.Lead)),
            new AppRoute.AllRivals(new RivalScope.FromSettings(RivalSettingsScope.Combo)));
        await unknown.LoadAsync();
        Assert.Equal(RivalPageState.Unknown, unknown.State);
        Assert.True(unknown.ShowEmpty);
        Assert.StartsWith("This rivals list", unknown.EmptyTitle);
        Assert.Equal("Combined Rivals", unknown.Title);
    }

    [Fact]
    public async Task AllRivals_EmptyAndFailureStates()
    {
        var fake = new RivalsFakeService { Fallback = _ => Wire.Response(HttpStatusCode.NotFound) };
        var empty = new AllRivalsViewModel(fake.Session(), new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead])));
        await empty.LoadAsync();
        Assert.Equal(RivalPageState.Empty, empty.State);
        Assert.StartsWith("Not enough data", empty.EmptyTitle);

        fake.Fallback = _ => RivalsFakeService.Frozen();
        var failed = new AllRivalsViewModel(fake.Session(), new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead])));
        await failed.LoadAsync();
        Assert.Equal(RivalPageState.Failed, failed.State);
        Assert.True(failed.ShowError);
        Assert.Equal("Scores are updating", failed.Status.Title);

        var noPlayer = new AllRivalsViewModel(fake.Session(new AppSettings()), new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead])));
        await noPlayer.LoadAsync();
        Assert.True(noPlayer.ShowNoPlayer);
    }

    [Fact]
    public async Task RivalDetail_CategorizesAndLinksRivalry()
    {
        var fake = new RivalsFakeService();
        var scope = new RivalScope.Song([Instrument.Lead]);
        var detail = await Loaded(new RivalDetailViewModel(fake.Session(), new AppRoute.RivalDetail(Rival, null, scope)));
        Assert.Equal("uwphe", detail.Title);
        Assert.Equal("View uwphe's Profile", detail.ViewProfileLabel);
        Assert.Equal(new AppRoute.Player(Rival), detail.ProfileRoute);
        Assert.Equal("Lead", detail.ScopeLabel);
        Assert.Equal("4 shared songs · 2 ahead / 1 behind", detail.Summary);
        Assert.Equal(["closest_battles", "almost_passed", "barely_winning", "pulling_forward"], detail.Categories.Select(c => c.Category.Key));
        Assert.Equal(["rival-category:closest_battles", "rival-category:almost_passed", "rival-category:barely_winning", "rival-category:pulling_forward"],
            detail.QuickLinkSections.Select(s => s.Id));
        Assert.Equal(detail.Categories[0].Title, detail.QuickLinkSections[0].Title);
        var closest = detail.Categories[0];
        Assert.Equal("View all 4 songs", closest.SeeAllText);
        Assert.Equal("View 1 song", detail.Categories[1].SeeAllText);
        Assert.Equal(new AppRoute.Rivalry(Rival, "closest_battles", "uwphe", scope), closest.SeeAllRoute);
        Assert.Equal("fst.rival-detail.category.closest_battles", closest.AutomationId);
        Assert.Equal(RivalCategorySentiment.Neutral, closest.Sentiment);
        Assert.NotEmpty(closest.Title + closest.Subtitle);
        Assert.Equal("Me Player", closest.Preview[0].PlayerName);
    }

    [Fact]
    public async Task RivalDetail_LiveFallbackOnlyForFindRivalRoutes()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session(RivalsFakeService.Settings(Instrument.Lead, Instrument.Bass));
        bool Live(SentRequest r) => r.Uri.Query.Contains("allowLiveFallback=true", StringComparison.Ordinal);

        await Loaded(new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival, "Hint")));
        Assert.DoesNotContain(fake.Service.Handler.Requests, Live);

        var found = await Loaded(new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival, "Hint", AllowLiveFallback: true)));
        Assert.Equal(2, fake.Service.Handler.Requests.Count(Live));
        Assert.NotEmpty(found.Categories);
        Assert.All(found.Categories, c => Assert.True(c.SeeAllRoute.AllowLiveFallback));
        // A deep link can never ask for it: the flag is navigation state, not part of the path.
        Assert.Equal($"/rivals/{Rival}?name=Hint", new AppRoute.RivalDetail(Rival, "Hint", AllowLiveFallback: true).ToPath());

        var before = fake.Service.Handler.Requests.Count(Live);
        await Loaded(new RivalryViewModel(session, new AppRoute.Rivalry(Rival, "closest_battles", "Hint", null, AllowLiveFallback: true)));
        Assert.Equal(before, fake.Service.Handler.Requests.Count(Live)); // served from the live-keyed cache

        await Loaded(new RivalDetailViewModel(session,
            new AppRoute.RivalDetail(Rival, null, new RivalScope.Leaderboard(Instrument.Lead, RankingMetric.TotalScore), AllowLiveFallback: true)));
        Assert.DoesNotContain(fake.Service.Handler.To($"/api/player/{Me}/leaderboard-rivals/Solo_Guitar/{Rival}"), Live);
    }

    [Fact]
    public async Task RivalDetail_MergesVisibleChartsWithoutScope()
    {
        var fake = new RivalsFakeService();
        var detail = await Loaded(new RivalDetailViewModel(fake.Session(), new AppRoute.RivalDetail(Rival, "Hint")));
        Assert.Equal("All visible instruments", detail.ScopeLabel);
        Assert.Equal(1, fake.Count($"/api/player/{Me}/rivals/Solo_Guitar/{Rival}"));
        Assert.Equal(1, fake.Count($"/api/player/{Me}/rivals/Solo_Bass/{Rival}"));
        Assert.Equal("4 shared songs · 2 ahead / 1 behind", detail.Summary);

        // One failed chart still merges the rest; all failing reports the failure.
        fake.Paths[$"/api/player/{Me}/rivals/Solo_Bass/{Rival}"] = RivalsFakeService.Frozen;
        var session = fake.Session(RivalsFakeService.Settings(Instrument.Lead, Instrument.Bass));
        var partial = await Loaded(new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival)));
        Assert.Equal(RivalPageState.Loaded, partial.State);

        fake.Paths[$"/api/player/{Me}/rivals/Solo_Guitar/{Rival}"] = RivalsFakeService.Frozen;
        session.RivalsCache.Clear();
        var failed = new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival, "Hint"));
        await failed.LoadAsync();
        Assert.Equal(RivalPageState.Failed, failed.State);
        Assert.Equal("Hint", failed.Title);
        Assert.Equal("No song data for this rival.", failed.EmptyTitle);
    }

    [Fact]
    public async Task RivalDetail_UsesLeaderboardAndComboEndpoints()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session();
        var board = await Loaded(new RivalDetailViewModel(session,
            new AppRoute.RivalDetail(Rival, null, new RivalScope.Leaderboard(Instrument.Lead, RankingMetric.Weighted))));
        Assert.Equal("Lead · Leaderboard (Weighted)", board.ScopeLabel);
        Assert.Single(fake.Service.Handler.Requests, r => r.Uri.AbsolutePath == $"/api/player/{Me}/leaderboard-rivals/Solo_Guitar/{Rival}");

        var combo = await Loaded(new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival, null, new RivalScope.Combo("03"))));
        Assert.Equal("Combined: Lead, Bass", combo.ScopeLabel);
        Assert.Equal(1, fake.Count($"/api/player/{Me}/rivals/03/{Rival}"));

        var common = new RivalDetailViewModel(session, new AppRoute.RivalDetail(Rival, null, new RivalScope.FromSettings(RivalSettingsScope.Common)));
        Assert.Equal("Common Rivals · all visible instruments", common.ScopeLabel);
    }

    [Fact]
    public async Task RivalDetail_EmptyWhenNoSharedSongs()
    {
        var fake = new RivalsFakeService { Fallback = _ => Wire.Response(HttpStatusCode.NotFound) };
        var detail = new RivalDetailViewModel(fake.Session(), new AppRoute.RivalDetail(Rival, "Named", new RivalScope.Song([Instrument.Lead])));
        await detail.LoadAsync();
        Assert.Equal(RivalPageState.Empty, detail.State);
        Assert.Equal("Named", detail.Title);
    }

    [Fact]
    public async Task Rivalry_ShowsCategorySortedAndReloadsOnPlayerChange()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session();
        var rivalry = new RivalryViewModel(session, new AppRoute.Rivalry(Rival, "closest_battles", null, new RivalScope.Song([Instrument.Lead])));
        rivalry.Activate();
        await Async.Until(() => rivalry.State == RivalPageState.Loaded);
        Assert.Equal("Closest Battles", rivalry.Title);
        Assert.StartsWith("vs. uwphe · Songs where", rivalry.Subtitle);
        Assert.Equal("View uwphe's Profile", rivalry.ViewProfileLabel);
        Assert.Equal(new AppRoute.Player(Rival), rivalry.ProfileRoute);
        Assert.Equal(4, rivalry.Rows.Count);
        Assert.Equal(RivalHeadToHead.Label(RivalrySort.Category), rivalry.SortLabels[rivalry.SortIndex]);

        rivalry.SortIndex = (int)RivalrySort.YouLead;
        Assert.Equal(RivalrySort.YouLead, rivalry.Sort);
        Assert.Equal("fixture-echo", rivalry.Rows[0].Comparison.SongId);
        rivalry.SortIndex = 42;
        Assert.Equal(RivalrySort.YouLead, rivalry.Sort);

        rivalry.RefreshCommand.Execute(null);
        await Async.Until(() => fake.Count($"/api/player/{Me}/rivals/Solo_Guitar/{Rival}") == 2);

        session.DeselectPlayer();
        await Async.Until(() => rivalry.State == RivalPageState.NoPlayer);
        rivalry.Deactivate();
        rivalry.Deactivate();
    }

    [Fact]
    public async Task Rivalry_UnknownModeIsEmpty()
    {
        var fake = new RivalsFakeService();
        var rivalry = new RivalryViewModel(fake.Session(), new AppRoute.Rivalry(Rival, "mystery"));
        await rivalry.LoadAsync();
        Assert.Equal(RivalPageState.Empty, rivalry.State);
        Assert.Equal("mystery", rivalry.Title);
        Assert.Equal("vs. uwphe", rivalry.Subtitle);
        Assert.Equal("No song data for this rival.", rivalry.EmptyTitle);
        Assert.Equal("View Profile", new RivalryViewModel(fake.Session(), new AppRoute.Rivalry(Rival, "x")).ViewProfileLabel);
        Assert.Equal("View Profile", new RivalDetailViewModel(fake.Session(), new AppRoute.RivalDetail(Rival)).ViewProfileLabel);
    }

    private static async Task<T> Loaded<T>(T page) where T : RivalPageViewModel
    {
        await page.LoadAsync();
        Assert.Equal(RivalPageState.Loaded, page.State);
        Assert.True(page.ShowContent);
        Assert.False(page.IsLoading);
        return page;
    }
    #endregion

    #region Session and cache
    [Fact]
    public async Task Session_RequiresPlayerAndCoercesMetric()
    {
        var fake = new RivalsFakeService();
        var session = fake.Session(new AppSettings());
        Assert.Equal(FestivalApiErrorKind.InvalidResource,
            (await Assert.ThrowsAsync<FestivalApiException>(() => session.GetRivalsListAsync("Solo_Guitar"))).Kind);
        Assert.Equal(RankingMetric.TotalScore, session.EffectiveRivalMetric(RankingMetric.MaxScore));
        var ok = fake.Session();
        Assert.Empty((await ok.GetCommonRivalsAsync([Instrument.Lead])).Above);
    }

    [Fact]
    public async Task Session_LimitsConcurrentRivalReads()
    {
        var fake = new RivalsFakeService();
        var inFlight = 0;
        var peak = 0;
        var release = new TaskCompletionSource();
        fake.Service.Handler.Responder = async (request, _) =>
        {
            if (!request.RequestUri!.AbsolutePath.StartsWith("/api/player/", StringComparison.Ordinal))
                return Wire.Ok(Wire.Publication());
            var now = Interlocked.Increment(ref inFlight);
            InterlockedMax(ref peak, now);
            await release.Task;
            Interlocked.Decrement(ref inFlight);
            return Wire.Ok(RivalsCoreTests.Fixture("rivals-list-demo"));
        };
        var session = fake.Session();
        var reads = InstrumentInfo.All.Select(i => session.GetRivalsListAsync(i.ServiceId())).ToList();
        await Async.Until(() => Volatile.Read(ref inFlight) == FestivalSession.RivalsConcurrency);
        await Async.Settle();
        Assert.Equal(FestivalSession.RivalsConcurrency, Volatile.Read(ref peak));
        release.SetResult();
        await Task.WhenAll(reads);
        Assert.Equal(FestivalSession.RivalsConcurrency, peak);
    }

    private static void InterlockedMax(ref int target, int value)
    {
        int current;
        while ((current = Volatile.Read(ref target)) < value && Interlocked.CompareExchange(ref target, value, current) != current)
        {
        }
    }

    [Fact]
    public async Task Cache_SharesInFlightReadsAndExpires()
    {
        var time = new FakeTimeProvider();
        var cache = new RivalsReadCache(time, TimeSpan.FromSeconds(10), capacity: 2);
        var gate = new TaskCompletionSource<int>();
        var loads = 0;
        Task<int> Load()
        {
            loads++;
            return gate.Task;
        }
        var first = cache.GetAsync("a", Load);
        var second = cache.GetAsync("a", Load);
        gate.SetResult(5);
        Assert.Equal(5, await first);
        Assert.Equal(5, await second);
        Assert.Equal(1, loads);

        time.Advance(TimeSpan.FromSeconds(11));
        Assert.Equal(5, await cache.GetAsync("a", Load));
        Assert.Equal(2, loads);

        await cache.GetAsync("b", () => Task.FromResult(1));
        await cache.GetAsync("c", () => Task.FromResult(2));
        Assert.Equal(2, cache.Count);
        cache.Clear();
        Assert.Equal(0, cache.Count);
    }

    [Fact]
    public async Task Cache_ForgetsFailuresAndHonoursCallerCancellation()
    {
        var cache = new RivalsReadCache(new FakeTimeProvider());
        await Assert.ThrowsAsync<FestivalApiException>(() =>
            cache.GetAsync<int>("x", () => Task.FromException<int>(new FestivalApiException(FestivalApiErrorKind.Offline))));
        Assert.Equal(0, cache.Count);
        Assert.Equal(3, await cache.GetAsync("x", () => Task.FromResult(3)));

        using var cts = new CancellationTokenSource();
        var pending = new TaskCompletionSource<int>();
        var wait = cache.GetAsync("slow", () => pending.Task, cts.Token);
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => wait);
        Assert.Equal(2, cache.Count);
        pending.SetResult(9);
        Assert.Equal(9, await cache.GetAsync("slow", () => Task.FromResult(0)));
    }
    #endregion
}
