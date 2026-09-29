using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public class GlobalSearchResultsTests
{
    private static Song S(string id, string title, string artist) => new() { SongId = id, Title = title, Artist = artist, AlbumArt = "a-" + id };

    [Fact]
    public void Scope_TokensRoundTrip()
    {
        foreach (var scope in Enum.GetValues<SearchScope>()) Assert.Equal(scope, SearchScopes.Parse(scope.Token()));
        Assert.Equal(SearchScope.Players, SearchScopes.Parse("PLAYERS"));
        Assert.Equal(SearchScope.All, SearchScopes.Parse(null));
        Assert.Equal(SearchScope.All, SearchScopes.Parse("nope"));
        Assert.Equal(SearchScope.All, SearchScopes.Parse("2"));
        Assert.Equal(SearchScope.All, SearchScopes.Parse("99"));
    }

    [Fact]
    public void Query_TrimAndLimits()
    {
        Assert.Equal("ab", GlobalSearchResults.Normalize("  ab "));
        Assert.Equal("", GlobalSearchResults.Normalize(null));
        Assert.False(GlobalSearchResults.IsSearchable(" a "));
        Assert.True(GlobalSearchResults.IsSearchable(" ab"));
        Assert.True(GlobalSearchResults.CanSearchPlayers("a+b"));
        Assert.False(GlobalSearchResults.CanSearchPlayers("a"));
        Assert.False(GlobalSearchResults.CanSearchPlayers(new string('x', 201)));
        Assert.True(GlobalSearchResults.CanSearchPlayers(new string('x', 200)));
        Assert.False(GlobalSearchResults.CanSearchPlayers("ab‮"));
    }

    [Fact]
    public void MatchSongs_LocalAccentInsensitiveCatalogueOrderCapped()
    {
        var catalog = new List<Song> { S("1", "Électrique", "Mid"), S("2", "Other", "Nobody"), S("3", "Don't Stop", "Band"), S("4", "Electric Avenue", "Eddy") };
        Assert.Equal(["1", "4"], GlobalSearchResults.MatchSongs(catalog, "electri").Select(s => s.SongId));
        Assert.Equal(["3"], GlobalSearchResults.MatchSongs(catalog, "dont").Select(s => s.SongId));
        Assert.Equal(["2"], GlobalSearchResults.MatchSongs(catalog, "NOBODY").Select(s => s.SongId));
        Assert.Empty(GlobalSearchResults.MatchSongs(catalog, "e"));
        var many = Enumerable.Range(0, 30).Select(i => S($"m{i}", $"Song {i}", "X")).ToList();
        var capped = GlobalSearchResults.MatchSongs(many, "song");
        Assert.Equal(20, capped.Count);
        Assert.Equal("m0", capped[0].SongId);
        var row = capped[1];
        Assert.Equal(new AppRoute.SongDetail("m1"), row.Route);
        Assert.Equal("Song 1 by X", row.AccessibleName);
        Assert.Equal("a-m1", row.Art);
    }

    [Fact]
    public void Players_MarkSelectedAndRoute()
    {
        var rows = GlobalSearchResults.Players(
            Enumerable.Range(0, 12).Select(i => new PlayerSearchResult($"acc{i}", $"P{i}")), "ACC1");
        Assert.Equal(10, rows.Count);
        Assert.False(rows[0].IsSelected);
        Assert.Equal(new AppRoute.Player("acc0", "P0"), rows[0].Route);
        Assert.Equal(("Player", "P0"), (rows[0].Subtitle, rows[0].AccessibleName));
        Assert.True(rows[1].IsSelected);
        Assert.Equal(new AppRoute.Statistics(), rows[1].Route);
        Assert.Equal("Selected player · Statistics", rows[1].Subtitle);
        Assert.Equal("P1, selected player, opens Statistics", rows[1].AccessibleName);
        Assert.All(GlobalSearchResults.Players([new("a", "b")], null), r => Assert.False(r.IsSelected));
    }

    [Fact]
    public void RetainMatching_KeepsOnlyNamesThatStillMatch()
    {
        var players = new List<GlobalPlayerResult> { new("a", "FireStarter", false), new("b", "Firefly", false), new("c", "Fiona", false) };
        Assert.Equal(["a", "b"], GlobalSearchResults.RetainMatching(players, " FIRE ").Select(p => p.AccountId));
        Assert.Equal(["b"], GlobalSearchResults.RetainMatching(players, "refl").Select(p => p.AccountId));
        Assert.Empty(GlobalSearchResults.RetainMatching(players, "f"));
        Assert.Empty(GlobalSearchResults.RetainMatching(players, "zz"));
    }

    [Fact]
    public void Suggestions_SongsThenPlayersThenSeeAll()
    {
        Assert.Empty(GlobalSearchResults.Suggestions("a", [], []));
        var songs = Enumerable.Range(0, 7).Select(i => new GlobalSongResult($"s{i}", $"T{i}", "Art", null)).ToList();
        var players = Enumerable.Range(0, 7).Select(i => new GlobalPlayerResult($"p{i}", $"N{i}", i == 1)).ToList();
        var before = GlobalSearchResults.Suggestions(" ab ", songs, []);
        Assert.Equal(6, before.Count);
        var after = GlobalSearchResults.Suggestions("ab", songs, players);
        Assert.Equal(11, after.Count);
        Assert.Equal(before.Take(5), after.Take(5));
        var song = after[0];
        Assert.True(song.IsSong);
        Assert.False(song.IsPlayer || song.IsSeeAll);
        Assert.Equal(("T0", "Song · Art", "Song, T0 by Art"), (song.Title, song.Subtitle, song.ToString()));
        Assert.Equal(new AppRoute.SongDetail("s0"), song.Route);
        Assert.True(after[5].IsPlayer);
        Assert.Equal("Player, N0", after[5].AccessibleName);
        Assert.Equal("Player, N1, selected, opens Statistics", after[6].AccessibleName);
        Assert.Equal(new AppRoute.Statistics(), after[6].Route);
        var seeAll = after[^1];
        Assert.True(seeAll.IsSeeAll);
        Assert.False(seeAll.HasSubtitle);
        Assert.True(song.HasSubtitle);
        Assert.Equal("See all results for “ab”", seeAll.Title);
        Assert.Equal(new AppRoute.Search("ab"), seeAll.Route);
    }

    [Fact]
    public void Announcement_Counts()
    {
        Assert.Equal("No results found.", GlobalSearchResults.Announcement(0, 0));
        Assert.Equal("1 song, 1 player", GlobalSearchResults.Announcement(1, 1));
        Assert.Equal("3 songs, 10 players", GlobalSearchResults.Announcement(3, 10));
        Assert.Equal("0 songs, player search failed", GlobalSearchResults.Announcement(0, null));
        Assert.Equal("song search failed, 2 players", GlobalSearchResults.Announcement(null, 2));
    }

    [Fact]
    public void Route_SearchPathRoundTrips()
    {
        Assert.Equal("/search", new AppRoute.Search().ToPath());
        Assert.Equal(AppSection.Songs, new AppRoute.Search().Section);
        var route = new AppRoute.Search("a b+c", SearchScope.Players);
        Assert.Equal("/search?q=a%20b%2Bc&scope=players", route.ToPath());
        Assert.True(AppRouteParser.TryParse(route.ToPath(), out var parsed, out var section));
        Assert.Equal(route, parsed);
        Assert.Equal(AppSection.Songs, section);
        Assert.True(AppRouteParser.TryParse("/search", out parsed, out _));
        Assert.Equal(new AppRoute.Search(), parsed);
        Assert.True(AppRouteParser.TryParse("/search?q=x&scope=bogus", out parsed, out _));
        Assert.Equal(new AppRoute.Search("x"), parsed);
        Assert.Equal(new AppRoute.BandRankings("Band_Duets"), GlobalSearchResults.BandRankingsRoute);
    }
}

public class GlobalSearchViewModelTests
{
    private const string SearchPath = "/api/account/search";

    private static (FakeService Service, FakeTimeProvider Time, FestivalSession Session) Create(
        Func<HttpRequestMessage, HttpResponseMessage?>? players = null, AppSettings? settings = null)
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == SearchPath
            ? players?.Invoke(r) ?? Wire.Ok("""{"results":[{"accountId":"acc1","displayName":"Alphonse"}]}""") : null;
        var time = new FakeTimeProvider();
        return (service, time, service.Session(time, settings));
    }

    private static async Task Type(GlobalSearchViewModel vm, FakeTimeProvider time, string text)
    {
        vm.Query = text;
        await Async.Settle();
        time.Advance(GlobalSearchViewModel.Debounce);
        await Async.Until(() => vm.IsSettled);
    }

    [Fact]
    public async Task ShortQuery_ShowsHintAndSendsNothing()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        Assert.Equal(GlobalSearchResults.EnterQueryHint, vm.Hint);
        Assert.True(vm.HasHint && vm.IsShortQuery);
        Assert.False(vm.IsBusy);
        vm.Query = " a ";
        await Async.Settle();
        time.Advance(TimeSpan.FromSeconds(1));
        await Async.Settle();
        Assert.Empty(service.Handler.To(SearchPath));
        Assert.Empty(service.Handler.To("/api/songs"));
        Assert.False(vm.ShowSongsSection || vm.ShowPlayersSection);
    }

    [Fact]
    public async Task Debounce_FastTypingSendsOneRequest_SongsBeforePlayers()
    {
        var release = new TaskCompletionSource();
        var (service, time, session) = Create();
        await session.LoadCatalogAsync();
        var inner = service.Handler.Responder;
        service.Handler.Responder = async (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath == SearchPath) await release.Task;
            return await inner(r, t);
        };
        var vm = new GlobalSearchViewModel(session);
        string? announced = null;
        vm.ResultsAnnounced += (_, text) => announced = text;
        vm.Query = "al";
        await Async.Settle();
        Assert.True(vm.IsDebouncing && vm.IsBusy);
        vm.Query = "alp";
        await Async.Settle();
        vm.Query = "alph";
        await Async.Settle();
        Assert.Empty(service.Handler.To(SearchPath));
        time.Advance(GlobalSearchViewModel.Debounce);
        await Async.Until(() => vm.PlayersLoading);
        // Songs are shown at once; players have their own progress.
        Assert.Equal(["s1"], vm.Songs.Select(s => s.SongId));
        Assert.True(vm.ShowSongsSection && vm.ShowPlayersSection);
        Assert.False(vm.IsSettled || vm.IsBusy);
        Assert.Equal(2, vm.Suggestions.Count);
        release.SetResult();
        await Async.Until(() => vm.IsSettled);
        Assert.Single(service.Handler.To(SearchPath));
        var request = service.Handler.To(SearchPath).Single();
        Assert.Contains("q=alph", request.Uri.Query, StringComparison.Ordinal);
        Assert.Contains("limit=10", request.Uri.Query, StringComparison.Ordinal);
        Assert.DoesNotContain(request.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) ||
                                                          k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase));
        Assert.Equal(["acc1"], vm.Players.Select(p => p.AccountId));
        Assert.Equal(3, vm.Suggestions.Count);
        Assert.True(vm.HasSongRows && vm.HasPlayerRows);
        Assert.Equal("1 song, 1 player", announced);
        Assert.Equal(announced, vm.LastAnnouncement);
        Assert.Equal("", vm.Hint);
        Assert.Empty(service.Handler.To("/api/bands/search"));
    }

    [Fact]
    public async Task LateResultsAreDropped()
    {
        var first = new TaskCompletionSource<HttpResponseMessage>();
        var calls = 0;
        var (service, time, session) = Create();
        var inner = service.Handler.Responder;
        service.Handler.Responder = (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath != SearchPath) return inner(r, t);
            return ++calls == 1 ? first.Task : Task.FromResult(Wire.Ok("""{"results":[{"accountId":"acc2","displayName":"Beta Fan"}]}"""));
        };
        var vm = new GlobalSearchViewModel(session);
        vm.Query = "alpha";
        await Async.Settle();
        time.Advance(GlobalSearchViewModel.Debounce);
        await Async.Until(() => calls == 1);
        await Type(vm, time, "beta");
        Assert.Equal(["acc2"], vm.Players.Select(p => p.AccountId));
        first.SetResult(Wire.Ok("""{"results":[{"accountId":"acc1","displayName":"Alpha"}]}"""));
        await Async.Settle();
        Assert.Equal(["acc2"], vm.Players.Select(p => p.AccountId));
        Assert.Equal("beta", vm.SettledQuery);
        first.TrySetCanceled();
    }

    [Fact]
    public async Task MatchingPlayersStayWhileTheNextSearchRuns()
    {
        var pending = new TaskCompletionSource<HttpResponseMessage>();
        var calls = 0;
        var (service, time, session) = Create();
        var inner = service.Handler.Responder;
        service.Handler.Responder = (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath != SearchPath) return inner(r, t);
            return ++calls == 1
                ? Task.FromResult(Wire.Ok("""{"results":[{"accountId":"acc1","displayName":"Alphabet"},{"accountId":"acc2","displayName":"Alpine"}]}"""))
                : pending.Task;
        };
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alp");
        Assert.Equal(["acc1", "acc2"], vm.Players.Select(p => p.AccountId));
        vm.Query = "alpha";
        await Async.Settle();
        time.Advance(GlobalSearchViewModel.Debounce);
        await Async.Until(() => calls == 2);
        // While "alpha" is searched, "Alphabet" (still a match) stays and "Alpine" (no longer one) goes.
        Assert.True(vm.PlayersLoading);
        Assert.Equal(["acc1"], vm.Players.Select(p => p.AccountId));
        pending.SetResult(Wire.Ok("""{"results":[{"accountId":"acc3","displayName":"Alpha"}]}"""));
        await Async.Until(() => vm.IsSettled);
        Assert.Equal(["acc3"], vm.Players.Select(p => p.AccountId));
    }

    [Fact]
    public async Task ShortQueryAfterResultsClears()
    {
        var (_, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        Assert.NotEmpty(vm.Suggestions);
        vm.Query = "a";
        Assert.Empty(vm.Songs);
        Assert.Empty(vm.Players);
        Assert.Empty(vm.Suggestions);
        Assert.Equal(LoadState.Idle, vm.PlayersState);
        Assert.Equal(GlobalSearchResults.EnterQueryHint, vm.Hint);
        Assert.False(vm.IsSettled);
    }

    [Fact]
    public async Task SameTrimmedTextDoesNotSearchAgain()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        vm.Query = "alpha  ";
        Assert.False(vm.IsDebouncing);
        time.Advance(TimeSpan.FromSeconds(1));
        await Async.Settle();
        Assert.Single(service.Handler.To(SearchPath));
    }

    [Fact]
    public async Task PlayersEmptyEnvelope_OffersRetry()
    {
        var body = """{"results":[]}""";
        var (service, time, session) = Create(_ => Wire.Ok(body));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "zzz");
        Assert.True(vm.PlayersEmpty);
        Assert.Equal(LoadState.Empty, vm.SongsState);
        // All scope: both empty → one "No results found." with Retry.
        Assert.Equal(GlobalSearchResults.NoResults, vm.Hint);
        Assert.True(vm.CanRetryAll);
        Assert.False(vm.ShowPlayersSection || vm.ShowSongsSection);
        Assert.Equal("No results found.", vm.LastAnnouncement);
        vm.Scope = SearchScope.Players;
        Assert.True(vm.ShowPlayersSection);
        Assert.Equal("", vm.Hint);
        Assert.Equal(GlobalSearchResults.NoPlayers, vm.NoPlayersText);
        Assert.False(vm.CanRetryAll);
        vm.Scope = SearchScope.Songs;
        Assert.Equal(GlobalSearchResults.NoSongs, vm.Hint);
        body = """{"results":[{"accountId":"acc9","displayName":"Zzz Top"}]}""";
        vm.Scope = SearchScope.All;
        await vm.RetryCommand.ExecuteAsync(null);
        Assert.Equal(2, service.Handler.To(SearchPath).Count());
        Assert.Equal(["acc9"], vm.Players.Select(p => p.AccountId));
        Assert.True(vm.ShowPlayersSection);
        Assert.False(vm.ShowSongsSection);
    }

    [Fact]
    public async Task PlayersEmpty_WithSongs_KeepsPlayersSectionWithRetry()
    {
        var (_, time, session) = Create(_ => Wire.Ok("""{"results":[]}"""));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "beta");
        Assert.True(vm.ShowSongsSection && vm.ShowPlayersSection && vm.PlayersEmpty);
        Assert.Equal("", vm.Hint);
        Assert.Equal("1 song, 0 players", vm.LastAnnouncement);
    }

    [Fact]
    public async Task PlayersFreeze_ShowsScoresUpdatingAndSongsStillShown()
    {
        var (_, time, session) = Create(_ => Wire.Response(HttpStatusCode.ServiceUnavailable, "",
            ("Retry-After", "5"), (ServiceFreezeReason.Header, "scrape")));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        Assert.True(vm.PlayersFailed && vm.ShowPlayersSection && vm.ShowSongsSection);
        Assert.Equal("Scores are updating", vm.PlayersStatus.Title);
        Assert.True(vm.PlayersStatus.SecondsRemaining > 0);
        Assert.Equal("1 song, player search failed", vm.LastAnnouncement);
        Assert.Equal(["s1"], vm.Songs.Select(s => s.SongId));
    }

    [Fact]
    public async Task PlayersTransportError_Retry_Succeeds()
    {
        var fail = true;
        var (service, time, session) = Create(_ => fail ? Wire.Response(HttpStatusCode.InternalServerError) : null);
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        Assert.True(vm.PlayersFailed);
        Assert.True(vm.PlayersStatus.HasIssue);
        fail = false;
        await vm.PlayersStatus.RetryCommand.ExecuteAsync(null);
        Assert.False(vm.PlayersStatus.HasIssue);
        Assert.Equal(["acc1"], vm.Players.Select(p => p.AccountId));
        Assert.Equal(2, service.Handler.To(SearchPath).Count());
    }

    [Fact]
    public async Task CatalogueFailure_ShowsSongsErrorWithPlayers()
    {
        var (service, time, session) = Create();
        service.SongsBody = "not json";
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        Assert.True(vm.SongsFailed && vm.ShowSongsSection);
        Assert.False(vm.HasSongRows);
        Assert.Equal(GlobalSearchResults.SongsFailed, vm.SongsFailedText);
        Assert.True(vm.ShowPlayersSection);
        Assert.Equal("song search failed, 1 player", vm.LastAnnouncement);
    }

    [Fact]
    public async Task LongQuery_SkipsPlayerRequest()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, new string('q', 201));
        Assert.Empty(service.Handler.To(SearchPath));
        Assert.True(vm.PlayersEmpty);
    }

    [Fact]
    public async Task BandsScope_NoRequestAndExplanation()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session) { Scope = SearchScope.Bands };
        Assert.True(vm.IsBandsScope);
        Assert.Equal("", vm.Hint);
        Assert.False(vm.IsBusy);
        Assert.Contains("band search can change stored band data", vm.BandsExplanation, StringComparison.Ordinal);
        await Type(vm, time, "alpha");
        Assert.False(vm.ShowSongsSection || vm.ShowPlayersSection || vm.HasHint);
        Assert.DoesNotContain(service.Handler.Requests, r => r.Uri.AbsolutePath.StartsWith("/api/bands", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SelectedPlayer_RoutesToStatistics()
    {
        var (_, time, session) = Create(settings: new AppSettings { SelectedPlayer = new SelectedPlayer("acc1", "Alphonse") });
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpho");
        Assert.True(vm.Players[0].IsSelected);
        Assert.Equal(new AppRoute.Statistics(), vm.Players[0].Route);
    }

    [Fact]
    public async Task Submit_SkipsDebounce_AndShortSubmitIsIgnored()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        vm.Query = "a";
        vm.SubmitCommand.Execute(null);
        await Async.Settle();
        Assert.Empty(service.Handler.To(SearchPath));
        await vm.RetryCommand.ExecuteAsync(null);
        Assert.Empty(service.Handler.To(SearchPath));
        vm.Query = "alpha";
        vm.SubmitCommand.Execute(null);
        await Async.Until(() => vm.IsSettled);
        Assert.Single(service.Handler.To(SearchPath));
        time.Advance(GlobalSearchViewModel.Debounce);
        await Async.Settle();
        Assert.Single(service.Handler.To(SearchPath));
    }

    [Fact]
    public async Task Reset_ClearsEverything()
    {
        var (_, time, session) = Create();
        var vm = new GlobalSearchViewModel(session) { Scope = SearchScope.Players };
        await Type(vm, time, "alpha");
        vm.Reset();
        Assert.Equal("", vm.Query);
        Assert.Equal(SearchScope.All, vm.Scope);
        Assert.Empty(vm.Players);
        Assert.Equal("", vm.SettledQuery);
    }

    [Fact]
    public async Task Deactivate_StopsPendingSearchAndCountdown()
    {
        var (service, time, session) = Create(_ => Wire.Response(HttpStatusCode.ServiceUnavailable, "",
            ("Retry-After", "5"), (ServiceFreezeReason.Header, "scrape")));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "alpha");
        Assert.True(vm.PlayersStatus.SecondsRemaining > 0);
        vm.Query = "alphabet";
        await Async.Settle();
        vm.Deactivate();
        Assert.False(vm.IsDebouncing);
        Assert.False(vm.PlayersStatus.HasIssue);
        await Async.Advance(time, TimeSpan.FromSeconds(10));
        Assert.Single(service.Handler.To(SearchPath));
    }

    [Fact]
    public async Task PageRoute_RunsImmediately()
    {
        var (service, _, session) = Create();
        var vm = new GlobalSearchViewModel(session, new AppRoute.Search(" alpha ", SearchScope.Songs));
        Assert.Equal(SearchScope.Songs, vm.Scope);
        Assert.Equal(" alpha ", vm.Query);
        await Async.Until(() => vm.IsSettled);
        Assert.Single(service.Handler.To(SearchPath));
        Assert.True(vm.ShowSongsSection);
        Assert.False(vm.ShowPlayersSection);
        var empty = new GlobalSearchViewModel(session, new AppRoute.Search());
        Assert.Equal(GlobalSearchResults.EnterQueryHint, empty.Hint);
    }

    [Fact]
    public async Task PageRoute_ReusesSettledTitleBarResults()
    {
        var (service, time, session) = Create();
        var bar = new GlobalSearchViewModel(session);
        await Type(bar, time, "alpha");
        var page = new GlobalSearchViewModel(session, new AppRoute.Search("alpha"), bar);
        Assert.True(page.IsSettled);
        Assert.Equal(bar.Players, page.Players);
        Assert.Equal(bar.Songs, page.Songs);
        Assert.Single(service.Handler.To(SearchPath));
        // A different query or an unsettled seed searches again.
        var other = new GlobalSearchViewModel(session, new AppRoute.Search("beta"), bar);
        await Async.Until(() => other.IsSettled);
        Assert.Equal(2, service.Handler.To(SearchPath).Count());
        // Typing on the page after seeding searches normally.
        await Type(page, time, "beta");
        Assert.Equal(["s2"], page.Songs.Select(s => s.SongId));
    }

    [Fact]
    public async Task PageRoute_DoesNotReuseFailedPlayers()
    {
        var fail = true;
        var (service, time, session) = Create(_ => fail ? Wire.Response(HttpStatusCode.InternalServerError) : null);
        var bar = new GlobalSearchViewModel(session);
        await Type(bar, time, "alpha");
        fail = false;
        var page = new GlobalSearchViewModel(session, new AppRoute.Search("alpha"), bar);
        await Async.Until(() => page.IsSettled);
        Assert.Equal(2, service.Handler.To(SearchPath).Count());
        Assert.True(page.ShowPlayersSection && !page.PlayersFailed);
    }
}
