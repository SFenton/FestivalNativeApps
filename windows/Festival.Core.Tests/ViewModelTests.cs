using System.Net;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public class SessionTests
{
    [Fact]
    public async Task Catalog_LoadsOnceAndShares()
    {
        var service = new FakeService();
        var session = service.Session();
        var first = session.LoadCatalogAsync();
        var second = session.LoadCatalogAsync();
        await Task.WhenAll(first, second);
        await session.LoadCatalogAsync();
        Assert.Single(service.Handler.To("/api/songs"));
        Assert.Equal("Alpha", session.FindSong("s1")!.Title);
        Assert.Null(session.FindSong("zzz"));
        await session.LoadCatalogAsync(force: true);
        Assert.Equal(2, service.Handler.To("/api/songs").Count());
    }

    [Fact]
    public async Task Catalog_FailureIsNotCachedAndCallerCancellationIsLocal()
    {
        var service = new FakeService();
        var fail = true;
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" && fail ? Wire.Response(HttpStatusCode.InternalServerError) : null;
        var session = service.Session();
        await Assert.ThrowsAsync<FestivalApiException>(() => session.LoadCatalogAsync());
        fail = false;
        Assert.Equal(3, (await session.LoadCatalogAsync()).Songs.Count);
        Assert.Null(new FakeService().Session().FindSong("s1"));

        var slow = new FakeService();
        var release = new TaskCompletionSource();
        slow.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/songs") await release.Task;
            return request.RequestUri.AbsolutePath == "/api/publication" ? Wire.Ok(Wire.Publication()) : Wire.Ok(Wire.DefaultSongs(), ("X-FST-Publication-Id", "7"));
        };
        var slowSession = slow.Session();
        using var cts = new CancellationTokenSource();
        var cancelled = slowSession.LoadCatalogAsync(cancellationToken: cts.Token);
        var shared = slowSession.LoadCatalogAsync();
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cancelled);
        release.SetResult();
        Assert.Equal(3, (await shared).Songs.Count);
    }

    [Fact]
    public void Settings_UpdateSelectDeselectPersist()
    {
        var store = new InMemorySettingsStore(new AppSettings { SelectedPlayer = new SelectedPlayer("acc", "Restored") });
        var session = new FestivalSession(new FakeService().Client(), store);
        Assert.True(session.HasPlayer);
        Assert.Equal("Restored", session.SelectedPlayer!.DisplayName);
        Assert.False(session.SettingsRecovered);
        var changes = new List<string?>();
        session.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        session.DeselectPlayer();
        Assert.False(session.HasPlayer);
        Assert.Contains(nameof(FestivalSession.HasPlayer), changes);
        Assert.Equal(1, store.SaveCount);
        session.DeselectPlayer();
        Assert.Equal(1, store.SaveCount);
        Assert.False(session.SelectPlayer(new PlayerSearchResult("bad id", "x")));
        Assert.True(session.SelectPlayer(new PlayerSearchResult("good", " Name ")));
        Assert.Equal("Name", store.Current.SelectedPlayer!.DisplayName);
    }

    [Fact]
    public async Task PublicationChange_ClearsArtwork()
    {
        var service = new FakeService();
        var session = service.Session();
        await session.Artwork.GetAsync(new Uri("https://cdn2.unrealengine.com/a.jpg"));
        Assert.True(session.Artwork.Bytes > 0);
        await session.Api.GetPublicationAsync();
        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        Assert.Equal(0, session.Artwork.Bytes);
        Assert.Same(TimeProvider.System, new FestivalSession(service.Client(), new InMemorySettingsStore()).Time);
    }
}

public class ServiceStatusTests
{
    [Fact]
    public async Task ScrapeFreeze_CountsDownAndRetries()
    {
        var time = new FakeTimeProvider();
        var retries = 0;
        var status = new ServiceStatusViewModel("s", "Songs unavailable", () => { retries++; return Task.CompletedTask; }, time);
        Assert.False(status.HasIssue);
        Assert.Equal("Songs unavailable", status.Title);
        Assert.Equal("", status.Message);
        Assert.Equal("Retry", status.RetryLabel);
        status.Report(new FestivalApiException(FestivalApiErrorKind.PublicReadFrozen, 503, "3", "scrape"));
        await Async.Settle();
        Assert.Equal("Scores are updating", status.Title);
        Assert.Equal(3, status.SecondsRemaining);
        Assert.Equal("0:03", status.CountdownText);
        Assert.Equal("Trying again automatically in 3 seconds", status.CountdownAnnouncement);
        await Async.Advance(time, TimeSpan.FromSeconds(3));
        await Async.Until(() => retries == 1);
        Assert.Equal("", status.CountdownText);
        Assert.Equal("", status.CountdownAnnouncement);
    }

    [Fact]
    public async Task ManualRetryAndClear_StopCountdown()
    {
        var time = new FakeTimeProvider();
        var retries = 0;
        var status = new ServiceStatusViewModel("s", "X", () => { retries++; return Task.CompletedTask; }, time);
        status.Report(new FestivalApiException(FestivalApiErrorKind.PublicReadFrozen, 503, null, "publish"));
        await Async.Settle();
        Assert.Equal(30, status.SecondsRemaining);
        await status.RetryCommand.ExecuteAsync(null);
        Assert.Equal(1, retries);
        Assert.Equal(0, status.SecondsRemaining);
        await Async.Advance(time, TimeSpan.FromSeconds(31), TimeSpan.FromSeconds(31));
        Assert.Equal(1, retries);

        status.Report(new FestivalApiException(FestivalApiErrorKind.Offline));
        Assert.Equal(0, status.SecondsRemaining);
        Assert.Equal("You're offline", status.Title);
        status.Clear();
        Assert.False(status.HasIssue);
    }
}

public class SongsViewModelTests
{
    [Fact]
    public async Task Load_BuildsSectionsAndCounts()
    {
        var service = new FakeService();
        var vm = new SongsViewModel(service.Session());
        Assert.Equal(LoadState.Idle, vm.State);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Equal(LoadState.Loaded, vm.State);
        Assert.True(vm.ShowList);
        Assert.False(vm.IsLoading || vm.ShowEmpty || vm.ShowError);
        Assert.Equal(3, vm.ResultCount);
        Assert.Equal("3 songs", vm.CountText);
        Assert.Equal(["A", "B", "E"], vm.Sections.Select(s => s.Label));
        Assert.False(vm.IsSortChanged);
        Assert.False(vm.IsFilterActive);
        Assert.Equal("Title ↑", vm.SortSummary);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Single(service.Handler.To("/api/songs"));
        await vm.RefreshCommand.ExecuteAsync(null);
        Assert.Equal(2, service.Handler.To("/api/songs").Count());
    }

    [Fact]
    public async Task Failure_ShowsStatusThenRetrySucceeds()
    {
        var service = new FakeService();
        var fail = true;
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" && fail
            ? Wire.Response(HttpStatusCode.ServiceUnavailable, "", ("Retry-After", "30"), (ServiceFreezeReason.Header, "scrape")) : null;
        var vm = new SongsViewModel(service.Session());
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.True(vm.ShowError);
        Assert.Equal("Scores are updating", vm.Status.Title);
        fail = false;
        await vm.Status.RetryCommand.ExecuteAsync(null);
        Assert.Equal(LoadState.Loaded, vm.State);
        Assert.False(vm.Status.HasIssue);
    }

    [Fact]
    public async Task Search_DebouncesAndSubmitAppliesImmediately()
    {
        var time = new FakeTimeProvider();
        var vm = new SongsViewModel(new FakeService().Session(time));
        await vm.AppearCommand.ExecuteAsync(null);
        vm.SearchText = "al";
        vm.SearchText = "alp";
        await Async.Settle();
        Assert.Equal(3, vm.ResultCount);
        time.Advance(SongsViewModel.SearchDebounce);
        await Async.Until(() => vm.ResultCount == 1);
        vm.SearchText = "zzzz";
        vm.SubmitSearchCommand.Execute(null);
        Assert.True(vm.ShowEmpty);
        Assert.Equal("0 songs", vm.CountText);
        Assert.Equal("No songs match your search.", vm.EmptyMessage);
        time.Advance(SongsViewModel.SearchDebounce);
        await Async.Settle();
        Assert.True(vm.ShowEmpty);
    }

    [Fact]
    public async Task SortDraft_AppliesLiveAndPersists()
    {
        var store = new InMemorySettingsStore();
        var session = new FestivalSession(new FakeService().Client(), store, new FakeTimeProvider());
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.False(vm.SortDraft.IsLive);
        vm.SortDraft.Begin();
        Assert.True(vm.SortDraft.IsLive);
        Assert.False(vm.SortDraft.CanApply);
        vm.SortDraft.ModeIndex = (int)SongSortMode.Year;
        Assert.Equal(SongSortMode.Year, store.Current.SongSort);
        vm.SortDraft.ModeIndex = 99;
        vm.SortDraft.Ascending = false;
        Assert.False(store.Current.SongSortAscending);
        Assert.False(vm.SortDraft.CanApply);
        Assert.True(vm.IsSortChanged);
        Assert.Equal("Year ↓", vm.SortSummary);
        Assert.Equal(["2020s", "Unknown Year"], vm.Sections.Select(s => s.Label));
        Assert.False(vm.HasJumpIndex); // Year sort has no quick-jump
        vm.SortDraft.Begin();
        Assert.Equal(SongSortMode.Year, vm.SortDraft.Mode);
        vm.SortDraft.ResetCommand.Execute(null);
        Assert.Equal((SongSortMode.Title, true, 0), (vm.SortDraft.Mode, vm.SortDraft.Ascending, vm.SortDraft.ModeIndex));
        Assert.Equal((SongSortMode.Title, true), (store.Current.SongSort, store.Current.SongSortAscending));
        Assert.False(vm.IsSortChanged);
    }

    [Fact]
    public async Task FilterDraft_AppliesLiveResetsAndClears()
    {
        var session = new FakeService().Session();
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        vm.FilterDraft.Begin();
        Assert.Equal(10, vm.FilterDraft.InstrumentChoices.Count);
        Assert.False(vm.FilterDraft.CanApply);
        vm.FilterDraft.InstrumentIndex = 1 + InstrumentInfo.All.ToList().IndexOf(Instrument.Karaoke);
        Assert.False(vm.FilterDraft.CanApply);
        Assert.Equal(["s3"], vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId));
        Assert.True(vm.IsFilterActive);
        vm.FilterDraft.Begin();
        Assert.Equal(Instrument.Karaoke, vm.FilterDraft.ToFilter().Instrument);
        vm.FilterDraft.MinDifficulty = 7;
        vm.FilterDraft.MaxDifficulty = 2;
        Assert.False(vm.FilterDraft.IsRangeValid);
        Assert.False(vm.FilterDraft.CanApply);
        // An inverted range is never applied: the last valid filter stays until the range is valid again.
        Assert.Equal(new SongFilter(Instrument.Karaoke, 7, 7), session.Settings.SongFilter);
        vm.FilterDraft.ResetCommand.Execute(null);
        Assert.Equal(SongFilter.None, vm.FilterDraft.ToFilter());
        Assert.Equal(SongFilter.None, session.Settings.SongFilter);
        vm.FilterDraft.InstrumentIndex = 2;
        vm.FilterDraft.MinDifficulty = 7;
        Assert.True(vm.ShowEmpty);
        Assert.Equal("No songs match the filters.", vm.EmptyMessage);
        vm.ClearFilterCommand.Execute(null);
        Assert.Equal(3, vm.ResultCount);
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Bass), VisibleInstruments = [Instrument.Lead] });
        vm.FilterDraft.Begin();
        Assert.Equal(0, vm.FilterDraft.InstrumentIndex);
    }

    [Fact]
    public async Task FilterDraft_BeginSelectsAppliedVisibleChart()
    {
        var session = new FakeService().Session(settings: new AppSettings { SongFilter = new SongFilter(Instrument.Karaoke) });
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Equal("1 song", vm.CountText);
        vm.FilterDraft.Begin();
        Assert.Equal(7, vm.FilterDraft.InstrumentIndex);
    }
}

public class SongDetailViewModelTests
{
    [Fact]
    public async Task Load_BuildsIntensityAndVisiblePreviews()
    {
        var service = new FakeService();
        var session = service.Session(settings: new AppSettings { VisibleInstruments = [Instrument.Lead, Instrument.Drums, Instrument.ProLead] });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s2", Instrument.Lead));
        Assert.Equal(Instrument.Lead, vm.InitialInstrument);
        Assert.Equal("s2", vm.SongId);
        await vm.LoadCommand.ExecuteAsync(null);
        Assert.True(vm.ShowContent);
        Assert.False(vm.IsLoading || vm.ShowError);
        Assert.Equal("Beta", vm.Song!.Title);
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Vocals], vm.Intensity.Select(r => r.Instrument));
        var lead = vm.Intensity[0];
        Assert.Equal((3, "Lead", "instrument_keys.png", "Lead, Difficulty 3 of 7"), (lead.Bars, lead.Label, lead.IconFile, lead.Announcement));
        var card = Assert.Single(vm.Leaderboards);
        Assert.Equal(("Lead", "instrument_keys.png"), (card.Title, card.IconFile));
        Assert.Equal(new AppRoute.SongLeaderboard("s2", Instrument.Lead), card.FullRoute);
        Assert.True(card.IsLoading);
        await card.EnsureLoadedAsync();
        await card.EnsureLoadedAsync();
        Assert.Single(service.Handler.To("/api/leaderboard/s2/Solo_Guitar"));
        Assert.True(card.ShowRows);
        Assert.Equal(10, card.Rows.Count);
        var row = card.Rows[0];
        Assert.Equal(("#1", "Player 1", true), (row.Rank, row.Name, row.IsFullCombo));
        Assert.Contains("full combo", row.Announcement);
        Assert.Contains("accuracy", row.Announcement);
        Assert.Equal("Unknown player", new LeaderboardRow(new LeaderboardEntry { DisplayName = " " }).Name);
        Assert.DoesNotContain("accuracy", new LeaderboardRow(new LeaderboardEntry()).Announcement);
        Assert.False(new LeaderboardRow(new LeaderboardEntry()).HasAccuracy);
        Assert.True(row.HasAccuracy);
    }

    [Fact]
    public async Task Load_MissingSongIsNotFound()
    {
        var vm = new SongDetailViewModel(new FakeService().Session(), new AppRoute.SongDetail("missing"));
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.Equal("This content is no longer available.", vm.Status.Message);
    }

    [Fact]
    public async Task Preview_EmptyAndFailureStates()
    {
        var service = new FakeService();
        var session = service.Session();
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Vocals], vm.Leaderboards.Select(c => c.Instrument));
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/s1/Solo_Guitar", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Guitar", 0), ("X-FST-Publication-Id", "7"))
            : r.RequestUri.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal) ? Wire.Response(HttpStatusCode.InternalServerError) : null;
        await vm.Leaderboards[0].LoadAsync();
        Assert.True(vm.Leaderboards[0].ShowEmpty);
        await vm.Leaderboards[1].EnsureLoadedAsync();
        Assert.True(vm.Leaderboards[1].ShowError);
        Assert.Equal("Bass unavailable", vm.Leaderboards[1].Status.Title);
    }
}

public class ShellViewModelTests
{
    [Fact]
    public void Sections_FollowPlayerSelection()
    {
        var session = new FakeService().Session();
        var shell = new ShellViewModel(session);
        Assert.Equal(4, shell.Sections.Count);
        Assert.False(shell.HasPlayer);
        Assert.Equal(("Select Player", "", "Select a player profile"), (shell.ProfileName, shell.ProfileInitials, shell.ProfileButtonName));
        session.SelectPlayer(new PlayerSearchResult("acc", "Jane Doe"));
        Assert.Equal(7, shell.Sections.Count);
        Assert.Equal(("Jane Doe", "JD", "Profile: Jane Doe"), (shell.ProfileName, shell.ProfileInitials, shell.ProfileButtonName));
        session.UpdateSettings(s => s with { SaveData = true });
        Assert.Equal(7, shell.Sections.Count);
        session.UpdateSettings(s => s with { HideShop = true });
        Assert.DoesNotContain(AppSection.Shop, shell.Sections);
        session.UpdateSettings(s => s with { HideShop = false });
        shell.ViewProfileCommand.Execute(null);
        shell.DeselectProfileCommand.Execute(null);
        Assert.Equal(4, shell.Sections.Count);
    }

    [Fact]
    public async Task ProfileSearch_DebouncesAndShowsResults()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/account/search"
            ? Wire.Ok("""{"results":[{"accountId":"acc1","displayName":"Found"}]}""") : null;
        var time = new FakeTimeProvider();
        var shell = new ShellViewModel(service.Session(time));
        Assert.Equal("Enter at least two characters to search.", shell.ProfileHint);
        shell.ProfileQuery = "f";
        await Async.Settle();
        Assert.Empty(service.Handler.To("/api/account/search"));
        shell.ProfileQuery = "fo";
        shell.ProfileQuery = "fou";
        await Async.Settle();
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Until(() => shell.ProfileResults.Count == 1);
        Assert.Single(service.Handler.To("/api/account/search"));
        Assert.Equal("", shell.ProfileHint);
        AppRoute? opened = null;
        shell.RouteRequested += (_, route) => opened = route;
        shell.ViewProfileCommand.Execute(shell.ProfileResults[0]);
        Assert.Equal(new AppRoute.Player("acc1", "Found"), opened);
        Assert.False(shell.HasPlayer);
        Assert.Equal("", shell.ProfileQuery);
        Assert.Empty(shell.ProfileResults);
    }

    [Fact]
    public async Task ProfileSearch_ErrorsAndEmpty()
    {
        var service = new FakeService();
        var body = """{"results":[]}""";
        var fail = true;
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/account/search"
            ? fail ? Wire.Response(HttpStatusCode.ServiceUnavailable) : Wire.Ok(body) : null;
        var time = new FakeTimeProvider();
        var shell = new ShellViewModel(service.Session(time));
        shell.ProfileQuery = "abc";
        await Async.Settle();
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Until(() => shell.ProfileSearch.PlayersFailed);
        Assert.Equal("The service is temporarily unavailable. Try again.", shell.ProfileHint);
        Assert.True(shell.CanRetrySearch);
        fail = false;
        shell.ProfileQuery = "abcd";
        await Async.Settle();
        Assert.Equal("Searching…", shell.ProfileHint);
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Until(() => shell.ProfileSearch.PlayersEmpty);
        Assert.Equal("No players found.", shell.ProfileHint);
    }

    [Fact]
    public async Task ProfileSearch_StaleErrorIsIgnored()
    {
        var service = new FakeService();
        var release = new TaskCompletionSource();
        service.Handler.Responder = async (r, _) =>
        {
            await release.Task;
            return Wire.Response(HttpStatusCode.ServiceUnavailable);
        };
        var time = new FakeTimeProvider();
        var shell = new ShellViewModel(service.Session(time));
        shell.ProfileQuery = "abc";
        await Async.Settle();
        time.Advance(ShellViewModel.SearchDebounce);
        await Async.Until(() => shell.ProfileSearch.PlayersLoading);
        Assert.Equal("Searching…", shell.ProfileHint);
        shell.ProfileQuery = "";
        release.SetResult();
        await Async.Settle();
        Assert.False(shell.ProfileSearch.PlayersFailed);
        Assert.Equal("Enter at least two characters to search.", shell.ProfileHint);
    }
}

public class SettingsViewModelTests
{
    [Fact]
    public void InstrumentToggles_KeepLastChartAndPersist()
    {
        var store = new InMemorySettingsStore(new AppSettings { VisibleInstruments = [Instrument.Lead, Instrument.Bass] });
        var session = new FestivalSession(new FakeService().Client(), store);
        var vm = new SettingsViewModel(session);
        var lead = vm.Instruments[0];
        var bass = vm.Instruments[1];
        var drums = vm.Instruments[2];
        Assert.Equal(("Lead", "instrument_guitar.png", "fst.settings.instrument.Solo_Guitar"), (lead.Label, lead.IconFile, lead.AutomationId));
        Assert.Equal(Instrument.Lead, lead.Instrument);
        Assert.True(lead.IsOn && lead.IsEnabled);
        Assert.False(drums.IsOn);
        var changes = new List<string?>();
        bass.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        lead.IsOn = false;
        Assert.Equal([Instrument.Bass], store.Current.VisibleInstruments);
        Assert.False(bass.IsEnabled);
        Assert.Equal("At least one instrument must stay visible.", bass.Description);
        Assert.Contains(nameof(InstrumentToggle.IsEnabled), changes);
        bass.IsOn = false;
        Assert.Equal([Instrument.Bass], store.Current.VisibleInstruments);
        var saves = store.SaveCount;
        bass.IsOn = true;
        Assert.Equal(saves, store.SaveCount);
        drums.IsOn = true;
        Assert.True(bass.IsEnabled);
        Assert.Equal("", bass.Description);
    }

    [Fact]
    public void AccessibilityProfileAndAbout()
    {
        var store = new InMemorySettingsStore(new AppSettings { SelectedPlayer = new SelectedPlayer("acc", "Jane") });
        var session = new FestivalSession(new FakeService().Client(), store);
        var vm = new SettingsViewModel(session);
        Assert.Equal(("Jane", true), (vm.ProfileText, vm.HasPlayer));
        Assert.Equal("https://festivalscoretracker.com", vm.ServiceOrigin);
        var changes = new List<string?>();
        vm.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        vm.ReduceMotion = true;
        vm.DisableAnimatedArtwork = true;
        vm.SaveData = true;
        Assert.True(vm.ReduceMotion && vm.DisableAnimatedArtwork && vm.SaveData);
        Assert.True(store.Current.ReduceMotion && store.Current.DisableAnimatedArtwork && store.Current.SaveData);
        Assert.Contains("", changes);
        vm.DeselectPlayerCommand.Execute(null);
        Assert.Equal(("No player selected", false), (vm.ProfileText, vm.HasPlayer));
        session.Catalog = null;
    }
}
