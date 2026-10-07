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
    public void Suggestions_SongsThenPlayersThenViewAll()
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
        Assert.False(song.IsPlayer || song.IsViewAll);
        Assert.Equal(("T0", "Song · Art", "Song, T0 by Art"), (song.Title, song.Subtitle, song.ToString()));
        Assert.Equal(new AppRoute.SongDetail("s0"), song.Route);
        Assert.True(after[5].IsPlayer);
        Assert.Equal("Player, N0", after[5].AccessibleName);
        Assert.Equal("Player, N1, selected, opens Statistics", after[6].AccessibleName);
        Assert.Equal(new AppRoute.Statistics(), after[6].Route);
        var viewAll = after[^1];
        Assert.True(viewAll.IsViewAll);
        Assert.False(viewAll.HasSubtitle);
        Assert.True(song.HasSubtitle);
        Assert.Equal("View All Results for “ab”", viewAll.Title); // owner #321: never See All
        Assert.Equal(new AppRoute.Search("ab"), viewAll.Route);
    }

    [Fact]
    public void Suggestions_BandsAfterPlayersBeforeViewAll_AndBandRetention()
    {
        var songs = Enumerable.Range(0, 2).Select(i => new GlobalSongResult($"s{i}", $"T{i}", "Art", null)).ToList();
        var players = Enumerable.Range(0, 2).Select(i => new GlobalPlayerResult($"p{i}", $"N{i}", false)).ToList();
        var bands = Enumerable.Range(0, 5).Select(i => GlobalSearchBand.Entry($"b{i}", "Band_Duets", "Abba", $"Mate {i}")).ToList();
        var list = GlobalSearchResults.Suggestions("ab", songs, players, bands);
        Assert.Equal(2 + 2 + GlobalSearchResults.SuggestedBands + 1, list.Count);
        var band = list[4];
        Assert.True(band.IsBand);
        Assert.False(band.IsSong || band.IsPlayer || band.IsViewAll);
        Assert.Equal(("Abba + Mate 0", "Band · Duos", "Band, Abba + Mate 0, Duos"), (band.Title, band.Subtitle, band.AccessibleName));
        Assert.Equal(new AppRoute.Band("b0", "Band_Duets", "acc_a:b0mate"), band.Route);
        Assert.Equal(GlobalSearchResults.BandRoute(bands[0]), band.Route);
        Assert.True(list[^1].IsViewAll);
        // Earlier band matches stay while the next search runs only when a member name still matches.
        Assert.True(GlobalSearchResults.BandStillMatches(bands[0], " abb "));
        Assert.True(GlobalSearchResults.BandStillMatches(bands[0], "mate 0"));
        Assert.False(GlobalSearchResults.BandStillMatches(bands[0], "zz"));
        Assert.False(GlobalSearchResults.BandStillMatches(bands[0], "a"));
    }

    [Fact]
    public void CloseSearchBelowTop_DropsOnlyTheSearchUnderTheResult()
    {
        // Songs root → Search → Band: Back must return to the root, not to Search (close, then push).
        var band = new AppRoute.Band("b0", "Band_Duets", "acc_a:b0mate");
        var routes = new Stack<AppRoute?>([null, new AppRoute.Search("ab"), band]);
        Assert.True(GlobalSearchResults.CloseSearchBelowTop(routes));
        Assert.Equal(new AppRoute?[] { band, null }, routes.ToArray());
        // Nothing to close: the destination was not pushed over Search, or the stack is the bare root.
        var detail = new AppRoute.SongDetail("s0");
        var noSearch = new Stack<AppRoute?>([null, detail, band]);
        Assert.False(GlobalSearchResults.CloseSearchBelowTop(noSearch));
        Assert.Equal(new AppRoute?[] { band, detail, null }, noSearch.ToArray());
        var root = new Stack<AppRoute?>([null]);
        Assert.False(GlobalSearchResults.CloseSearchBelowTop(root));
        Assert.Single(root);
        // A Search page replacing its own query is not a result.
        var twice = new Stack<AppRoute?>([null, new AppRoute.Search("ab"), new AppRoute.Search("abc")]);
        Assert.False(GlobalSearchResults.CloseSearchBelowTop(twice));
        Assert.Equal(3, twice.Count);
    }

    [Fact]
    public void Announcement_Counts()
    {
        Assert.Equal("No results found.", GlobalSearchResults.Announcement(0, 0, 0));
        Assert.Equal("1 song, 1 player, 1 band", GlobalSearchResults.Announcement(1, 1, 1));
        Assert.Equal("3 songs, 10 players, 2 bands", GlobalSearchResults.Announcement(3, 10, 2));
        Assert.Equal("0 songs, player search failed, 0 bands", GlobalSearchResults.Announcement(0, null, 0));
        Assert.Equal("song search failed, 2 players, band search failed", GlobalSearchResults.Announcement(null, 2, null));
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
    }
}

/// <summary>Band-search wire rows for the global search tests (the <c>BandSearchResponseDto</c> shape).</summary>
public static class GlobalSearchBand
{
    public const string Path = "/api/bands/search";
    public const string Empty = """{"page":1,"pageSize":10,"totalCount":0,"results":[]}""";

    public static string Row(string bandId, string bandType, string first, string second) =>
        $$"""{"bandId":"{{bandId}}","bandType":"{{bandType}}","teamKey":"acc_a:{{bandId}}mate","appearanceCount":12,"members":[{"accountId":"acc_a","displayName":"{{first}}","instruments":["Solo_Guitar"]},{"accountId":"{{bandId}}mate","displayName":"{{second}}","instruments":["Solo_Drums"]}]}""";

    public static string Page(params string[] rows) =>
        $$"""{"page":1,"pageSize":10,"totalCount":{{rows.Length}},"results":[{{string.Join(",", rows)}}]}""";

    public static PlayerBandEntry Entry(string bandId, string bandType, string first, string second) =>
        System.Text.Json.JsonSerializer.Deserialize(Page(Row(bandId, bandType, first, second)), BandsJsonContext.Default.BandSearchResponse)!.Results[0];
}

public class GlobalSearchViewModelTests
{
    private const string SearchPath = "/api/account/search";

    private static (FakeService Service, FakeTimeProvider Time, FestivalSession Session) Create(
        Func<HttpRequestMessage, HttpResponseMessage?>? players = null, AppSettings? settings = null,
        Func<HttpRequestMessage, HttpResponseMessage?>? bands = null)
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath switch
        {
            SearchPath => players?.Invoke(r) ?? Wire.Ok("""{"results":[{"accountId":"acc1","displayName":"Alphonse"}]}"""),
            GlobalSearchBand.Path => bands?.Invoke(r) ?? Wire.Ok(GlobalSearchBand.Empty),
            _ => null,
        };
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
    public void Hint_NamesTheSelectedScope()
    {
        var (_, _, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        var hints = new List<string>();
        vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(GlobalSearchViewModel.Hint)) hints.Add(vm.Hint);
        };
        foreach (var scope in new[] { SearchScope.Songs, SearchScope.Players, SearchScope.Bands, SearchScope.All })
        {
            vm.Scope = scope;
            Assert.Equal(GlobalSearchResults.EnterQueryHintFor(scope), vm.Hint);
        }
        Assert.Equal([
            "Enter at least two characters to search for songs.",
            "Enter at least two characters to search for players.",
            "Enter at least two characters to search for bands.",
            "Enter at least two characters to search for songs, players, or bands.",
        ], hints);
        // The players-only pickers keep their own wording.
        Assert.Equal(GlobalSearchResults.EnterQueryHint, GlobalSearchViewModel.ForPlayers(session).PlayersHint);
    }

    [Fact]
    public async Task ShortQuery_ShowsHintAndSendsNothing()
    {
        var (service, time, session) = Create();
        var vm = new GlobalSearchViewModel(session);
        Assert.Equal(GlobalSearchResults.EnterQueryHintAll, vm.Hint);
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
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var inner = service.Handler.Responder;
        service.Handler.Responder = async (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath == SearchPath)
            {
                reached.TrySetResult();
                await release.Task;
            }
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
        // Wait for the players request itself: PlayersLoading flips before the song rows are matched.
        await reached.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(vm.PlayersLoading);
        // Issue #299: All shows one spinner until songs and players have both settled (web SearchModal).
        Assert.Equal(["s1"], vm.Songs.Select(s => s.SongId));
        Assert.True(vm.IsBusy);
        Assert.False(vm.IsSettled || vm.ShowSongsSection || vm.ShowPlayersSection || vm.HasEmptyState);
        // The Songs scope never waits for players; the Players scope does.
        vm.Scope = SearchScope.Songs;
        Assert.False(vm.IsBusy);
        Assert.True(vm.ShowSongsSection);
        Assert.False(vm.ShowPlayersSection);
        vm.Scope = SearchScope.Players;
        Assert.True(vm.IsBusy);
        Assert.False(vm.ShowPlayersSection || vm.HasEmptyState);
        vm.Scope = SearchScope.All;
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
        Assert.Equal("1 song, 1 player, 0 bands", announced);
        Assert.Equal(announced, vm.LastAnnouncement);
        Assert.Equal("", vm.Hint);
        // Issue #320: the keyless band search runs with the players (one request, first page of 10, no profile headers).
        var bandRequest = Assert.Single(service.Handler.To(GlobalSearchBand.Path));
        Assert.Equal("?q=alph&page=1&pageSize=10", bandRequest.Uri.Query);
        Assert.DoesNotContain(bandRequest.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) ||
                                                              k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task SectionShown_RaisedWhenEachSectionAppears_NotOnEveryRefresh()
    {
        var release = new TaskCompletionSource();
        var (service, time, session) = Create();
        await session.LoadCatalogAsync();
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var inner = service.Handler.Responder;
        service.Handler.Responder = async (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath == SearchPath)
            {
                reached.TrySetResult();
                await release.Task;
            }
            return await inner(r, t);
        };
        var vm = new GlobalSearchViewModel(session);
        var shown = new List<SearchScope>();
        vm.SectionShown += (_, section) => shown.Add(section);

        // Song rows are ready at once but stay behind the spinner until the delayed players settle (issue #260).
        vm.Query = "alph";
        await Async.Settle();
        time.Advance(GlobalSearchViewModel.Debounce);
        await reached.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(vm.PlayersLoading);
        Assert.NotEmpty(vm.Songs);
        Assert.Empty(shown);
        release.SetResult();
        await Async.Until(() => vm.IsSettled);
        Assert.Equal([SearchScope.Songs, SearchScope.Players], shown);

        // Unrelated refreshes while both stay on screen raise nothing.
        shown.Clear();
        vm.Scope = SearchScope.All;
        Assert.Empty(shown);

        // Each scope switch that reveals a hidden section raises it once.
        vm.Scope = SearchScope.Songs;
        Assert.Empty(shown);
        vm.Scope = SearchScope.Players;
        Assert.Equal([SearchScope.Players], shown);
        vm.Scope = SearchScope.All;
        Assert.Equal([SearchScope.Players, SearchScope.Songs], shown);

        // A new query hides both behind the spinner, then shows them again.
        shown.Clear();
        await Type(vm, time, "alp");
        Assert.Equal([SearchScope.Songs, SearchScope.Players], shown);
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
        Assert.Equal(GlobalSearchResults.EnterQueryHintAll, vm.Hint);
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
    public async Task PlayersEmptyEnvelope_CentredEmptyStateWithoutRetry_EnterRunsAgain()
    {
        var body = """{"results":[]}""";
        var (service, time, session) = Create(_ => Wire.Ok(body));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "zzz");
        Assert.True(vm.PlayersEmpty);
        Assert.Equal(LoadState.Empty, vm.SongsState);
        // All scope: both empty → one centred title and subtitle (no Retry, issue #299).
        Assert.Equal("", vm.Hint);
        Assert.True(vm.HasEmptyState);
        Assert.Equal(GlobalSearchResults.EmptyAllTitle, vm.EmptyTitle);
        Assert.Equal(GlobalSearchResults.EmptyAllSubtitle, vm.EmptySubtitle);
        Assert.False(vm.ShowPlayersSection || vm.ShowSongsSection);
        Assert.Equal("No results found.", vm.LastAnnouncement);
        // Players scope: no section with an inline row, the centred empty state instead.
        vm.Scope = SearchScope.Players;
        Assert.False(vm.ShowPlayersSection);
        Assert.Equal("", vm.Hint);
        Assert.Equal(GlobalSearchResults.EmptyPlayersTitle, vm.EmptyTitle);
        Assert.Equal(GlobalSearchResults.EmptyPlayersSubtitle, vm.EmptySubtitle);
        vm.Scope = SearchScope.Songs;
        Assert.Equal(GlobalSearchResults.EmptySongsTitle, vm.EmptyTitle);
        Assert.Equal(GlobalSearchResults.EmptySongsSubtitle, vm.EmptySubtitle);
        // Bands scope: "No bands found" (issue #320), the same centred state as Players.
        vm.Scope = SearchScope.Bands;
        Assert.True(vm.HasEmptyState && vm.BandsEmpty);
        Assert.False(vm.ShowBandsSection);
        Assert.Equal(GlobalSearchResults.EmptyBandsTitle, vm.EmptyTitle);
        Assert.Equal(GlobalSearchResults.EmptyBandsSubtitle, vm.EmptySubtitle);
        body = """{"results":[{"accountId":"acc9","displayName":"Zzz Top"}]}""";
        vm.Scope = SearchScope.All;
        // An empty envelope may be a server timeout: Enter on the same text searches again.
        vm.SubmitCommand.Execute(null);
        await Async.Until(() => vm.IsSettled && vm.Players.Count > 0);
        Assert.Equal(2, service.Handler.To(SearchPath).Count());
        Assert.Equal(["acc9"], vm.Players.Select(p => p.AccountId));
        Assert.True(vm.ShowPlayersSection);
        Assert.False(vm.ShowSongsSection);
        Assert.False(vm.HasEmptyState);
    }

    [Fact]
    public async Task PlayersEmpty_WithSongs_HidesPlayersSectionInAll()
    {
        var (_, time, session) = Create(_ => Wire.Ok("""{"results":[]}"""));
        var vm = new GlobalSearchViewModel(session);
        await Type(vm, time, "beta");
        // Web parity (shouldRenderGlobalSection): no "Players" section with an inline "No players found." row.
        Assert.True(vm.ShowSongsSection && vm.PlayersEmpty);
        Assert.False(vm.ShowPlayersSection);
        Assert.False(vm.HasEmptyState);
        Assert.Equal("", vm.Hint);
        Assert.Equal("1 song, 0 players, 0 bands", vm.LastAnnouncement);
        vm.Scope = SearchScope.Players;
        Assert.True(vm.HasEmptyState);
        Assert.Equal(GlobalSearchResults.EmptyPlayersTitle, vm.EmptyTitle);
        vm.Scope = SearchScope.Songs;
        Assert.False(vm.HasEmptyState);
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
        Assert.Equal("1 song, player search failed, 0 bands", vm.LastAnnouncement);
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
        Assert.Equal("song search failed, 1 player, 0 bands", vm.LastAnnouncement);
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
    public async Task BandsScope_ShowsBandCardsThatOpenTheBandPage()
    {
        var (service, time, session) = Create(bands: _ => Wire.Ok(GlobalSearchBand.Page(
            GlobalSearchBand.Row("b1", "Band_Duets", "Alpha One", "Beta"),
            GlobalSearchBand.Row("b2", "Band_Trios", "Alphabet", "Gamma"))));
        var vm = new GlobalSearchViewModel(session) { Scope = SearchScope.Bands };
        // Issue #299: a short query shows the Bands hint; no request until two characters.
        Assert.Equal(GlobalSearchResults.EnterQueryHintBands, vm.Hint);
        Assert.False(vm.IsBusy);
        await Type(vm, time, "alpha");
        Assert.True(vm.ShowBandsSection && vm.HasBandRows);
        Assert.False(vm.ShowSongsSection || vm.ShowPlayersSection || vm.HasHint || vm.IsBusy || vm.HasEmptyState || vm.BandsFailed);
        Assert.Equal(["b1", "b2"], vm.Bands.Select(b => b.Entry.Key));
        var card = vm.Bands[0];
        Assert.Equal(GlobalSearchResults.BandResultId, card.AutomationId);
        Assert.Equal(new AppRoute.Band("b1", "Band_Duets", "acc_a:b1mate"), card.Route);
        Assert.Equal(["Alpha One", "Beta"], card.Members.Select(m => m.Name));
        Assert.Equal("1 song, 1 player, 2 bands", vm.LastAnnouncement);
        // All lists Songs → Players → Bands; the title bar suggests up to three bands before See All.
        vm.Scope = SearchScope.All;
        Assert.True(vm.ShowSongsSection && vm.ShowPlayersSection && vm.ShowBandsSection);
        Assert.Equal([false, false, true, true, false], vm.Suggestions.Select(x => x.IsBand));
        Assert.Single(service.Handler.To(GlobalSearchBand.Path));
    }

    [Fact]
    public async Task BandsEmptyAndFailure_FollowThePlayersRules()
    {
        var fail = false;
        var (service, time, session) = Create(_ => Wire.Ok("""{"results":[]}"""), bands: _ => fail
            ? Wire.Response(HttpStatusCode.ServiceUnavailable, "", ("Retry-After", "5"))
            : Wire.Ok(GlobalSearchBand.Empty));
        var vm = new GlobalSearchViewModel(session) { Scope = SearchScope.Bands };
        await Type(vm, time, "zzz");
        // Empty: the centred "No bands found" state, no section and no Retry.
        Assert.True(vm.BandsEmpty && vm.HasEmptyState);
        Assert.False(vm.ShowBandsSection || vm.BandsFailed);
        Assert.Equal("No bands found", vm.EmptyTitle);
        // In All an empty band envelope never renders a section, like Players.
        vm.Scope = SearchScope.All;
        Assert.False(vm.ShowBandsSection);
        // Failure stays distinct from empty: the status card (never "No bands found"), and the other scopes still show.
        fail = true;
        vm.Scope = SearchScope.Bands;
        await Type(vm, time, "zzzz");
        Assert.True(vm.BandsFailed && vm.ShowBandsSection && vm.BandsStatus.HasIssue);
        Assert.False(vm.HasEmptyState || vm.HasBandRows || vm.IsBusy);
        Assert.Equal("0 songs, 0 players, band search failed", vm.LastAnnouncement);
        vm.Scope = SearchScope.Players;
        Assert.True(vm.HasEmptyState);
        Assert.Equal(GlobalSearchResults.EmptyPlayersTitle, vm.EmptyTitle);
        vm.Scope = SearchScope.All;
        Assert.True(vm.ShowBandsSection);
        Assert.False(vm.HasEmptyState);
        // A failed band search is never reused by the Search page: it searches again.
        fail = false;
        var page = new GlobalSearchViewModel(session, new AppRoute.Search("zzzz"), vm);
        await Async.Until(() => page.IsSettled);
        Assert.Equal(3, service.Handler.To(GlobalSearchBand.Path).Count());
        Assert.True(page.BandsEmpty);
    }

    [Fact]
    public async Task BandsScope_WaitsForBands_PlayersScopeDoesNot()
    {
        var release = new TaskCompletionSource<HttpResponseMessage>();
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var (service, time, session) = Create();
        var inner = service.Handler.Responder;
        service.Handler.Responder = (r, t) =>
        {
            if (r.RequestUri!.AbsolutePath != GlobalSearchBand.Path) return inner(r, t);
            reached.TrySetResult();
            return release.Task;
        };
        var vm = new GlobalSearchViewModel(session);
        var shown = new List<SearchScope>();
        vm.SectionShown += (_, section) => shown.Add(section);
        vm.Query = "alpha";
        await Async.Settle();
        time.Advance(GlobalSearchViewModel.Debounce);
        await reached.Task.WaitAsync(TimeSpan.FromSeconds(10));
        await Async.Until(() => vm.PlayersState == LoadState.Loaded);
        // One spinner: All and Bands wait for the band search; Players shows its rows at once.
        Assert.True(vm.BandsLoading && vm.IsBusy && !vm.IsSettled);
        vm.Scope = SearchScope.Players;
        Assert.False(vm.IsBusy);
        Assert.True(vm.ShowPlayersSection);
        vm.Scope = SearchScope.Bands;
        Assert.True(vm.IsBusy);
        Assert.False(vm.HasEmptyState || vm.ShowBandsSection);
        shown.Clear();
        release.SetResult(Wire.Ok(GlobalSearchBand.Page(GlobalSearchBand.Row("b1", "Band_Duets", "Alpha", "Beta"))));
        await Async.Until(() => vm.IsSettled);
        Assert.Equal([SearchScope.Bands], shown);
        Assert.False(vm.IsBusy);
    }

    [Fact]
    public async Task PlayersOnlyPickers_NeverRequestBands()
    {
        var (service, time, session) = Create();
        var vm = GlobalSearchViewModel.ForPlayers(session);
        await Type(vm, time, "alpha");
        Assert.Single(service.Handler.To(SearchPath));
        Assert.Empty(service.Handler.To(GlobalSearchBand.Path));
        Assert.Empty(vm.Bands);
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
        Assert.Equal(GlobalSearchResults.EnterQueryHintAll, empty.Hint);
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
