using System.Net;
using System.Text.Json;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Synthetic Item Shop and CHOpt path payloads (captured shapes, no production data).</summary>
public static class SongsWire
{
    public const string ShopBase = "https://www.fortnite.com/item-shop/jam-tracks/";

    public static string Offer(string id, string title, bool leaving = false, bool isNew = false, string? url = null, int? year = 2020) =>
        $$"""{"songId":"{{id}}","title":"{{title}}","artist":"Artist {{id}}","year":{{(year is null ? "null" : year.ToString())}},"albumArt":"art-{{id}}.jpg","shopUrl":"{{url ?? ShopBase + id}}","leavingTomorrow":{{(leaving ? "true" : "false")}},"isNew":{{(isNew ? "true" : "false")}}}""";

    public static string Shop(params string[] offers) =>
        $$"""{"count":{{offers.Length}},"songs":[{{string.Join(",", offers)}}],"newSongs":[],"lastUpdated":"2026-09-28T00:00:00Z"}""";

    public static string DefaultShop() => Shop(Offer("s2", "Beta", isNew: true), Offer("s3", "Électrique", leaving: true));

    public static string PathData(string difficulty = "expert", string activations = "", string notes = "") =>
        $$"""{"schemaVersion":2,"songName":"Alpha","artist":"Zed Band","charter":"c","difficulty":"{{difficulty}}","totalScore":123456,"pathSummary":"2-1-1","activations":[{{activations}}],"notes":[{{notes}}]}""";

    public static byte[] Png(int width = 100, int height = 400)
    {
        var bytes = new byte[40];
        new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, (byte)'I', (byte)'H', (byte)'D', (byte)'R' }.CopyTo(bytes, 0);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(bytes.AsSpan(16), width);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(bytes.AsSpan(20), height);
        return bytes;
    }

    /// <summary>Routes Shop, path and (optionally) player endpoints; unknown paths fall through to the standard fake.</summary>
    public static void Install(FakeService service, Func<string>? shop = null, HttpStatusCode shopStatus = HttpStatusCode.OK,
        bool player = false, Dictionary<string, (HttpStatusCode, string)>? profiles = null)
    {
        Func<HttpRequestMessage, HttpResponseMessage?>? inner = null;
        if (player)
        {
            PlayerWire.Install(service, profiles);
            inner = service.Override;
        }
        service.Override = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            var pub = ("X-FST-Publication-Id", service.PublicationId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (path == "/api/shop")
                return shopStatus == HttpStatusCode.OK ? Wire.Ok((shop ?? DefaultShop)(), pub) : Wire.Response(shopStatus, "{}", pub);
            if (path.StartsWith("/api/paths/", StringComparison.Ordinal))
            {
                var parts = path.Split('/');
                if (path.EndsWith("/data", StringComparison.Ordinal)) return Wire.Ok(PathData(parts[5]), pub);
                var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Png()) };
                response.Headers.TryAddWithoutValidation(pub.Item1, pub.Item2);
                return response;
            }
            return inner?.Invoke(request);
        };
    }
}

public class ShopModelTests
{
    private static ShopResponse Decode(string json) => FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(json), SongsJsonContext.Default.ShopResponse);

    [Fact]
    public void Validate_AcceptsOfficialLinksAndSortsByTitle()
    {
        var shop = Decode(SongsWire.Shop(SongsWire.Offer("b", "Zulu"), SongsWire.Offer("a", "alpha", year: null), SongsWire.Offer("c", "Alpha")));
        shop.Validate();
        Assert.Equal(["a", "c", "b"], shop.SortedSongs().Select(s => s.SongId));
        Assert.Equal("Artist a", shop.Songs[1].Subtitle);
        Assert.Equal("Artist b · 2020", shop.Songs[0].Subtitle);
        Assert.Equal(new Uri(SongsWire.ShopBase + "b"), shop.Songs[0].ShopUri);
    }

    private static ShopResponse SortFixture() => Decode(SongsWire.Shop(
        SongsWire.Offer("s2", "Beta", year: 2021), SongsWire.Offer("s3", "Électrique", year: null),
        SongsWire.Offer("x9", "Absent", year: 2020), SongsWire.Offer("s1", "Alpha", year: 2019)));

    [Theory]
    [InlineData(SongSortMode.Title, true, "x9,s1,s2,s3")]
    [InlineData(SongSortMode.Title, false, "s3,s2,s1,x9")]
    [InlineData(SongSortMode.Artist, true, "s1,s2,s3,x9")]
    [InlineData(SongSortMode.Artist, false, "x9,s3,s2,s1")]
    [InlineData(SongSortMode.Year, true, "s3,s1,x9,s2")]
    [InlineData(SongSortMode.Year, false, "s2,x9,s1,s3")]
    [InlineData(SongSortMode.Duration, true, "x9,s3,s1,s2")]
    [InlineData(SongSortMode.Duration, false, "s2,s1,s3,x9")]
    [InlineData(SongSortMode.HasFC, true, "x9,s1,s2,s3")]
    public void OfferSort_MatchesSongsOrdering(SongSortMode mode, bool ascending, string expected)
    {
        // Issue #379: the Songs comparison (missing year/duration sorts as zero; ties by title, then ID; direction flips
        // everything). Duration comes from the catalogue: s1 100 s, s2 250 s; s3 has none and x9 isn't catalogued.
        var durations = new Dictionary<string, int?> { ["s1"] = 100, ["s2"] = 250, ["s3"] = null };
        var sorted = ShopOfferSort.Sort(SortFixture().Songs, mode, ascending, id => durations.GetValueOrDefault(id));
        Assert.Equal(expected, string.Join(",", sorted.Select(s => s.SongId)));
    }

    [Theory]
    [InlineData(SongSortMode.Title, false, false, null)]
    [InlineData(SongSortMode.Year, false, false, null)]
    [InlineData(SongSortMode.Duration, true, true, null)]
    [InlineData(SongSortMode.Duration, false, false, "Duration sort paused until song details load. Showing title order; your choice is saved.")]
    [InlineData(SongSortMode.Duration, true, false, "Duration sort paused until Item Shop and song details update together. Showing title order; your choice is saved.")]
    public void OfferSort_DurationPausesWithoutSamePublicationCatalogue(SongSortMode mode, bool loaded, bool matches, string? expected) =>
        // catalogue-sort R7: only Duration needs catalogue data; never guess zero lengths from a missing/mismatched catalogue.
        Assert.Equal(expected, ShopOfferSort.DurationPause(mode, loaded, matches));

    [Fact]
    public void OfferSort_ModesAreTheSongsBaseModes()
    {
        Assert.Equal([SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration], ShopOfferSort.Modes);
        Assert.Equal(SongSortMode.Year, ShopOfferSort.Normalize(SongSortMode.Year));
        Assert.Equal(SongSortMode.Title, ShopOfferSort.Normalize(SongSortMode.Shop));
        Assert.Equal(SongSortMode.Title, ShopOfferSort.Normalize((SongSortMode)99));
        // Without catalogue durations every offer ties at zero and falls back to title order.
        Assert.Equal(["x9", "s1", "s2", "s3"], ShopOfferSort.Sort(SortFixture().Songs, SongSortMode.Duration, true).Select(s => s.SongId));
    }

    [Fact]
    public void Settings_ShopSortPersistsSanitizesAndSurvivesResets()
    {
        var settings = new AppSettings { ShopSort = SongSortMode.Duration, ShopSortAscending = false };
        var json = JsonSerializer.Serialize(settings, FestivalJsonContext.Default.AppSettings);
        Assert.Contains("\"shopSort\": \"Duration\"", json);
        Assert.Contains("\"shopSortAscending\": false", json);
        var back = JsonSerializer.Deserialize(json, FestivalJsonContext.Default.AppSettings)!.Sanitized();
        Assert.Equal((SongSortMode.Duration, false), (back.ShopSort, back.ShopSortAscending));
        Assert.Equal(settings.Sanitized(), back);
        Assert.NotEqual(back, back with { ShopSort = SongSortMode.Title });
        Assert.NotEqual(back, back with { ShopSortAscending = true });
        Assert.Equal((SongSortMode.Duration, false), (back.ResetAppSettings().ShopSort, back.ResetAppSettings().ShopSortAscending));
        var deselected = (back with { SelectedPlayer = new SelectedPlayer("acc", "Name") }).ResetSongSettingsForDeselect();
        Assert.Equal((SongSortMode.Duration, false), (deselected.ShopSort, deselected.ShopSortAscending));
        Assert.Equal(SongSortMode.Title, (back with { ShopSort = SongSortMode.HasFC }).Sanitized().ShopSort);
        var legacy = JsonSerializer.Deserialize("{}", FestivalJsonContext.Default.AppSettings)!.Sanitized();
        Assert.Equal((SongSortMode.Title, true), (legacy.ShopSort, legacy.ShopSortAscending));
    }

    [Theory]
    [InlineData("http://www.fortnite.com/item-shop/jam-tracks/x")]
    [InlineData("https://evil.example/item-shop/jam-tracks/x")]
    [InlineData("https://www.fortnite.com/item-shop/jam-tracks/")]
    [InlineData("https://www.fortnite.com/other/x")]
    [InlineData("https://www.fortnite.com/item-shop/jam-tracks/x?y=1")]
    [InlineData("https://www.fortnite.com/item-shop/jam-tracks/x#f")]
    [InlineData("https://www.fortnite.com:8443/item-shop/jam-tracks/x")]
    [InlineData("https://u:p@www.fortnite.com/item-shop/jam-tracks/x")]
    [InlineData("not a url")]
    public void Validate_RejectsUntrustedLinks(string url)
    {
        var shop = Decode(SongsWire.Shop(SongsWire.Offer("a", "A", url: url)));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, Assert.Throws<FestivalApiException>(shop.Validate).Kind);
        Assert.False(ShopResponse.IsOfficialShopUrl(url, out _));
    }

    [Fact]
    public void Validate_RejectsBadCountsAndIds()
    {
        Assert.Throws<FestivalApiException>(() => Decode("""{"count":2,"songs":[]}""").Validate());
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.Shop(SongsWire.Offer("a", "A"), SongsWire.Offer("A", "B"))).Validate());
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.Shop(SongsWire.Offer("a/b", "A"))).Validate());
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.Shop(SongsWire.Offer("a", ""))).Validate());
        Assert.False(ShopResponse.IsOfficialShopUrl(null, out _));
        Assert.False(ShopResponse.IsOfficialShopUrl(SongsWire.ShopBase + new string('x', 2_001), out _));
        Decode(SongsWire.Shop()).Validate();
    }

    [Fact]
    public void Highlight_LeavingWinsAndHiddenSuppresses()
    {
        var both = new ShopSong { LeavingTomorrow = true, IsNew = true };
        Assert.Equal(ShopHighlight.LeavingTomorrow, ShopPresentationPolicy.Highlight(both, false, false));
        Assert.Equal(ShopHighlight.New, ShopPresentationPolicy.Highlight(new ShopSong { IsNew = true }, false, false));
        Assert.Null(ShopPresentationPolicy.Highlight(new ShopSong(), false, false));
        Assert.Null(ShopPresentationPolicy.Highlight(both, true, false));
        Assert.Null(ShopPresentationPolicy.Highlight(both, false, true));
        Assert.Null(ShopPresentationPolicy.Highlight(null, false, false));
        Assert.Equal(("New", "Leaving Tomorrow"), (ShopHighlight.New.Label(), ShopHighlight.LeavingTomorrow.Label()));
    }

    [Fact]
    public void PublicationPolicy_RequiresThreeEqualObservations()
    {
        Assert.True(SongRelatedPublicationPolicy.Matches(7, 7, 7));
        Assert.False(SongRelatedPublicationPolicy.Matches(7, 8, 8));
        Assert.False(SongRelatedPublicationPolicy.Matches(7, 7, 8));
        Assert.False(SongRelatedPublicationPolicy.Matches(null, 7, 7));
        Assert.False(SongRelatedPublicationPolicy.Matches(7, null, 7));
        Assert.False(SongRelatedPublicationPolicy.Matches(7, 7, null));
    }
}

public class ShopSessionTests
{
    [Fact]
    public async Task Client_ReadsShopThroughTheGate()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var shop = await service.Client().GetShopAsync();
        Assert.Equal(2, shop.Count);
        var sent = Assert.Single(service.Handler.To("/api/shop"));
        Assert.DoesNotContain(sent.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) || k.Equals("x-api-key", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Session_MatchesShopToCatalogPublication()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        await session.LoadCatalogAsync();
        Assert.Null(session.ShopOffersForCatalog);
        await session.LoadShopAsync();
        Assert.Equal(7, session.CatalogPublicationId);
        Assert.Equal(7, session.ShopPublicationId);
        Assert.NotNull(session.ShopOffersForCatalog);
        Assert.False(session.ShopPublicationMismatch);
        Assert.Equal("Beta", session.FindOffer("s2")!.Title);
        Assert.Null(session.FindOffer("zz"));
        // Cached for the same publication.
        await session.LoadShopAsync();
        Assert.Single(service.Handler.To("/api/shop"));
    }

    [Fact]
    public async Task Session_NewerPublicationPausesShopUntilSongsUpdate()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        var advanced = 0;
        session.PublicationAdvanced += (_, _) => advanced++;
        await session.LoadCatalogAsync();
        await session.LoadShopAsync();
        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        await Async.Until(() => advanced == 1);
        Assert.True(session.ShopPublicationMismatch);
        Assert.Null(session.ShopOffersForCatalog);
        await session.LoadShopAsync();
        await session.LoadCatalogAsync(force: true);
        Assert.NotNull(session.ShopOffersForCatalog);
    }

    [Fact]
    public async Task Session_RecordsShopFailureWithoutThrowingFromTry()
    {
        var service = new FakeService();
        SongsWire.Install(service, shopStatus: HttpStatusCode.ServiceUnavailable);
        var session = service.Session();
        await session.TryLoadShopAsync();
        Assert.NotNull(session.ShopIssue);
        Assert.Null(session.Shop);
        await Assert.ThrowsAsync<FestivalApiException>(() => session.LoadShopAsync());
        session.UpdateSettings(s => s with { HideShop = true });
        var before = service.Handler.To("/api/shop").Count();
        await session.TryLoadShopAsync();
        Assert.Equal(before, service.Handler.To("/api/shop").Count());
    }
}

public class ShopViewModelTests
{
    [Fact]
    public async Task Sort_DurationPausesToTitleOrderUntilSamePublicationCatalogue()
    {
        // catalogue-sort R7 (#379): Duration reads catalogue lengths only from the feed's publication. A failed or older
        // catalogue shows title order in the saved direction with a notice and keeps the choice. Lengths: Électrique
        // none (0), Alpha 100 s, Beta 250 s, so Duration and Title orders differ.
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(SongsWire.Offer("s2", "Beta"), SongsWire.Offer("s3", "Électrique"),
            SongsWire.Offer("s1", "Alpha")));
        var inner = service.Override!;
        var failSongs = true;
        service.Override = r => failSongs && r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.InternalServerError) : inner(r);
        var session = service.Session();
        session.UpdateSettings(s => s with { ShopSort = SongSortMode.Duration, ShopSortAscending = false });
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        Assert.Equal(["s3", "s2", "s1"], vm.Offers.Select(o => o.Offer.SongId)); // Title ↓, not zero-length ties
        Assert.True(vm.HasSortPause);
        Assert.StartsWith("Duration sort paused until song details load", vm.SortPaused);
        Assert.Equal(("Duration ↓", true), (vm.SortSummary, vm.IsSortChanged));

        failSongs = false;
        await vm.LoadAsync(force: true);
        Assert.False(vm.HasSortPause);
        Assert.Equal(["s2", "s1", "s3"], vm.Offers.Select(o => o.Offer.SongId));
        vm.SortDraft.Begin();
        vm.SortDraft.DirectionIndex = 0;
        Assert.Equal(["s3", "s1", "s2"], vm.Offers.Select(o => o.Offer.SongId));

        // A newer publication whose catalogue read fails leaves an older catalogue beside the new feed: pause again.
        failSongs = true;
        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        await Async.Until(() => vm.SortPaused?.StartsWith("Duration sort paused until Item Shop and song details update together", StringComparison.Ordinal) == true);
        Assert.Equal(["s1", "s2", "s3"], vm.Offers.Select(o => o.Offer.SongId));
        Assert.True(vm.HasSortPause);
        // Title, Artist and Year never need the catalogue.
        session.UpdateSettings(s => s with { ShopSort = SongSortMode.Year });
        Assert.False(vm.HasSortPause);
        Assert.Equal(SongSortMode.Year, session.Settings.ShopSort);
    }
    [Fact]
    public async Task Sort_AppliesLivePersistsAndOrdersBothLayouts()
    {
        // Issue #379: the Songs Sort draft with the Shop's modes; every change applies at once and is saved.
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(SongsWire.Offer("s2", "Beta", year: 2021, isNew: true),
            SongsWire.Offer("x9", "Absent", year: 2020), SongsWire.Offer("s1", "Alpha", year: 2019, leaving: true)));
        var session = service.Session();
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        Assert.Equal(["x9", "s1", "s2"], vm.Offers.Select(o => o.Offer.SongId));
        Assert.Equal(("Title ↑", "Title, ascending", false), (vm.SortSummary, vm.SortDescription, vm.IsSortChanged));
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);

        vm.SortDraft.ModeIndex = 3; // not live before Begin: nothing applies
        Assert.Equal(SongSortMode.Title, session.Settings.ShopSort);
        vm.SortDraft.Begin();
        Assert.Equal(["Title", "Artist", "Year", "Duration"], vm.SortDraft.ModeLabels);
        Assert.Equal((0, 0, false), (vm.SortDraft.ModeIndex, vm.SortDraft.DirectionIndex, vm.SortDraft.CanApply));
        vm.SortDraft.ModeIndex = 3;
        Assert.Equal((SongSortMode.Duration, true), (session.Settings.ShopSort, session.Settings.ShopSortAscending));
        // Catalogue durations: Alpha 100 s, Beta 250 s; Absent isn't catalogued (zero).
        Assert.Equal(["x9", "s1", "s2"], vm.Offers.Select(o => o.Offer.SongId));
        vm.SortDraft.DirectionIndex = 1;
        Assert.Equal(["s2", "s1", "x9"], vm.Offers.Select(o => o.Offer.SongId));
        Assert.Equal(("Duration ↓", "Duration, descending", true), (vm.SortSummary, vm.SortDescription, vm.IsSortChanged));
        Assert.Contains(nameof(ShopViewModel.SortSummary), changed);
        Assert.Contains(nameof(ShopViewModel.IsSortChanged), changed);
        Assert.Equal((SongSortMode.Title, true), (session.Settings.SongSort, session.Settings.SongSortAscending));

        // The filter and the sort combine; the list layout shows the same order.
        vm.FilterRows[1].IsOn = false;
        Assert.Equal(["s2", "s1"], vm.Offers.Select(o => o.Offer.SongId));
        vm.ToggleViewCommand.Execute(null);
        Assert.True(vm.ShowList);
        Assert.Equal(["s2", "s1"], vm.Offers.Select(o => o.Offer.SongId));

        // A fresh page (relaunch) starts with the saved sort; Reset applies Title ascending at once.
        var reopened = new ShopViewModel(session);
        await reopened.LoadAsync();
        Assert.Equal(["s2", "s1", "x9"], reopened.Offers.Select(o => o.Offer.SongId));
        reopened.SortDraft.Begin();
        Assert.Equal((3, 1), (reopened.SortDraft.ModeIndex, reopened.SortDraft.DirectionIndex));
        reopened.SortDraft.ResetCommand.Execute(null);
        Assert.Equal((SongSortMode.Title, true), (session.Settings.ShopSort, session.Settings.ShopSortAscending));
        Assert.Equal(["x9", "s1", "s2"], reopened.Offers.Select(o => o.Offer.SongId));
        Assert.False(reopened.IsSortChanged);
    }

    [Fact]
    public async Task Load_ProjectsOffersWithBadgesAndDetailLinks()
    {
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(SongsWire.Offer("s2", "Beta", isNew: true), SongsWire.Offer("x9", "Absent", leaving: true)));
        var vm = new ShopViewModel(service.Session());
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.True(vm.ShowOffers);
        Assert.Equal("2 songs", vm.CountText);
        var absent = vm.Offers[0];
        Assert.Equal(("Absent", false, true, "Leaving Tomorrow"), (absent.Title, absent.HasSongDetail, absent.IsLeaving, absent.BadgeText));
        Assert.Equal("Absent, Artist x9 · 2020, Leaving Tomorrow", absent.Announcement);
        Assert.Equal("Absent, Artist x9, Open Official Item Shop", absent.ExternalName);
        Assert.Equal((absent.ExternalName, SongRowShopPulse.Leaving), (absent.TileName, absent.Pulse));
        Assert.Equal(("fst.shop.external.x9", "fst.shop.song.x9"), (absent.ExternalAutomationId, absent.TileAutomationId));
        var beta = vm.Offers[1];
        Assert.True(beta.HasSongDetail);
        // Issue #562: like the web, only Leaving Tomorrow gets a visible pill; New is the gold pulse and the spoken name.
        Assert.True(absent.ShowsPill);
        Assert.False(beta.ShowsPill);
        Assert.Equal(("New", "Beta, Artist s2 · 2020, New"), (beta.BadgeText, beta.Announcement));
        Assert.Equal(new AppRoute.SongDetail("s2"), beta.DetailRoute);
        Assert.Equal((beta.Announcement, SongRowShopPulse.New), (beta.TileName, beta.Pulse));
        Assert.False(vm.HasSongDetailsIssue);
        Assert.True(vm.ShowGrid);
        Assert.False(vm.ShowList);
        // Appear again: no re-read.
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Single(service.Handler.To("/api/shop"));
    }

    [Fact]
    public async Task ViewToggle_PersistsAndCompactForcesGrid()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        var vm = new ShopViewModel(session);
        Assert.False(vm.CanToggleView);
        await vm.LoadAsync();
        Assert.True(vm.CanToggleView);
        Assert.Equal("List View", vm.ToggleLabel);
        vm.ToggleViewCommand.Execute(null);
        Assert.Equal(ShopViewMode.List, session.Settings.ShopViewMode);
        Assert.True(vm.ShowList);
        Assert.Equal("Grid View", vm.ToggleLabel);
        vm.IsCompact = true;
        Assert.True(vm.ShowGrid);
        Assert.False(vm.ShowList);
        Assert.False(vm.CanToggleView);
    }

    [Fact]
    public async Task ViewToggle_OfferedOnlyWithOffersOnScreen()
    {
        var service = new FakeService();
        var body = SongsWire.Shop();
        SongsWire.Install(service, () => body);
        var session = service.Session();
        var vm = new ShopViewModel(session);
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        Assert.False(vm.CanToggleView);
        await vm.LoadAsync();
        Assert.True(vm.ShowEmpty);
        Assert.False(vm.CanToggleView);

        body = SongsWire.Shop(SongsWire.Offer("s2", "Beta", isNew: true));
        await vm.LoadAsync(force: true);
        Assert.True(vm.CanToggleView);
        Assert.Contains(nameof(ShopViewModel.CanToggleView), changed);

        session.UpdateSettings(s => s with { HideShop = true });
        Assert.True(vm.IsHidden);
        Assert.False(vm.CanToggleView);

        var failing = new FakeService();
        SongsWire.Install(failing, shopStatus: HttpStatusCode.ServiceUnavailable);
        var failed = new ShopViewModel(failing.Session());
        await failed.LoadAsync();
        Assert.True(failed.ShowError);
        Assert.False(failed.CanToggleView);
    }

    [Fact]
    public async Task EmptyErrorHiddenAndHighlightStates()
    {
        var service = new FakeService();
        var body = SongsWire.Shop();
        SongsWire.Install(service, () => body);
        var session = service.Session();
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        Assert.True(vm.ShowEmpty);
        Assert.False(vm.CanToggleView);
        Assert.Equal("0 songs", vm.CountText);

        var failing = new FakeService();
        SongsWire.Install(failing, shopStatus: HttpStatusCode.InternalServerError);
        var failed = new ShopViewModel(failing.Session());
        await failed.LoadAsync();
        Assert.True(failed.ShowError);
        Assert.False(failed.ShowEmpty);
        Assert.False(failed.CanToggleView);

        body = SongsWire.Shop(SongsWire.Offer("s2", "Beta", leaving: true));
        await vm.LoadAsync(force: true);
        Assert.Equal("1 song", vm.CountText);
        Assert.True(vm.CanToggleView);
        Assert.True(vm.Offers[0].ShowsPill);
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        Assert.False(vm.Offers[0].ShowsPill);
        Assert.Null(vm.Offers[0].Pulse);
        Assert.Equal("", vm.Offers[0].BadgeText);
        var notified = new List<string?>();
        vm.PropertyChanged += (_, e) => notified.Add(e.PropertyName);
        session.UpdateSettings(s => s with { HideShop = true });
        Assert.True(vm.IsHidden);
        Assert.False(vm.ShowOffers);
        Assert.False(vm.CanToggleView);
        Assert.Contains(nameof(ShopViewModel.CanToggleView), notified);
        await vm.LoadAsync();
        Assert.Equal(LoadState.Idle, vm.State);
        session.UpdateSettings(s => s with { HideShop = false });
        await Async.Until(() => vm.ShowOffers);
    }

    [Fact]
    public async Task CatalogFailure_KeepsOffersWithNotice()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.InternalServerError) : inner(r);
        var vm = new ShopViewModel(service.Session());
        await vm.LoadAsync();
        Assert.True(vm.ShowOffers);
        Assert.True(vm.HasSongDetailsIssue);
        Assert.StartsWith("Song details unavailable", vm.SongDetailsIssue);
        Assert.All(vm.Offers, o => Assert.False(o.HasSongDetail));
    }

    [Fact]
    public async Task Filter_SelectsDisjointGroupsLiveAndResetRestoresEveryOffer()
    {
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(
            SongsWire.Offer("a", "Alpha", isNew: true), SongsWire.Offer("b", "Bravo"),
            SongsWire.Offer("c", "Charlie", leaving: true), SongsWire.Offer("d", "Delta")));
        var session = service.Session();
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        string[] Ids() => [.. vm.Offers.Select(o => o.Offer.SongId)];
        // Issue #376: a fresh filter has every switch on and lists every offer, and is not active.
        Assert.Equal(["a", "b", "c", "d"], Ids());
        Assert.False(vm.IsFilterActive);
        Assert.All(vm.FilterRows, r => Assert.True(r.IsOn));
        Assert.Equal("4 songs", vm.CountText);
        Assert.Equal(["fst.shop.filter.new", "fst.shop.filter.available", "fst.shop.filter.leaving"], vm.FilterRows.Select(r => r.AutomationId));
        Assert.Equal(["New", "Available", "Leaving Tomorrow"], vm.FilterRows.Select(r => r.Label));

        // Turning a switch off hides that group and makes the filter active.
        vm.FilterRows[0].IsOn = false;
        Assert.Equal(["b", "c", "d"], Ids());
        Assert.True(vm.IsFilterActive);
        Assert.Equal("3 of 4 songs", vm.CountText);
        vm.FilterRows[2].IsOn = false;
        Assert.Equal(["b", "d"], Ids());
        vm.FilterRows[0].IsOn = true;
        vm.FilterRows[1].IsOn = false;
        Assert.Equal(["a"], Ids());

        // Wire flags, not badges: filtering still works while Shop highlighting is off.
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        Assert.Equal(["a"], Ids());
        Assert.False(vm.FilterRows[1].IsOn);

        // Turning the last switches back on by hand (not Reset) shows every offer and deactivates the filter.
        vm.FilterRows[1].IsOn = true;
        vm.FilterRows[2].IsOn = true;
        Assert.Equal(["a", "b", "c", "d"], Ids());
        Assert.False(vm.IsFilterActive);

        vm.FilterRows[1].IsOn = false;
        vm.ResetFilterCommand.Execute(null);
        Assert.Equal(["a", "b", "c", "d"], Ids());
        Assert.False(vm.IsFilterActive);
        Assert.All(vm.FilterRows, r => Assert.True(r.IsOn));
        Assert.Equal("4 songs", vm.CountText);
    }

    [Fact]
    public async Task Filter_HidingEveryOfferIsNotTheEmptyShop()
    {
        var service = new FakeService();
        var body = SongsWire.Shop(SongsWire.Offer("b", "Bravo"));
        SongsWire.Install(service, () => body);
        var vm = new ShopViewModel(service.Session());
        await vm.LoadAsync();
        vm.FilterRows[1].IsOn = false;
        Assert.Empty(vm.Offers);
        Assert.True(vm.ShowNoMatches);
        Assert.False(vm.ShowEmpty);
        Assert.True(vm.ShowOffers);
        Assert.Equal("0 of 1 song", vm.CountText);

        body = SongsWire.Shop();
        await vm.LoadAsync(force: true);
        Assert.True(vm.ShowEmpty);
        Assert.False(vm.ShowNoMatches);
        // The filter survives a feed change, so the reopened flyout shows it.
        Assert.False(vm.FilterRows[1].IsOn);
    }

    [Fact]
    public async Task Filter_ReportsAppliedStatusForNarrator()
    {
        var service = new FakeService();
        SongsWire.Install(service, () => SongsWire.Shop(SongsWire.Offer("a", "Alpha", isNew: true), SongsWire.Offer("b", "Bravo")));
        var vm = new ShopViewModel(service.Session());
        await vm.LoadAsync();
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        Assert.Equal("", vm.FilterStatus);

        vm.FilterRows[0].IsOn = false;
        Assert.Equal("Filters applied", vm.FilterStatus);
        Assert.Contains(nameof(ShopViewModel.FilterStatus), changed);

        // Re-setting the same filter is a no-op (no extra notifications); Reset clears the status.
        changed.Clear();
        vm.FilterRows[0].IsOn = false;
        Assert.DoesNotContain(nameof(ShopViewModel.FilterStatus), changed);
        vm.ResetFilterCommand.Execute(null);
        Assert.Equal("", vm.FilterStatus);
        Assert.Contains(nameof(ShopViewModel.FilterStatus), changed);
    }

    [Fact]
    public void ShopOfferFilter_MatchesAnySelectedGroup()
    {
        ShopSong Offer(bool isNew, bool leaving) => new() { SongId = "x", IsNew = isNew, LeavingTomorrow = leaving };
        var fresh = Offer(true, false);
        var plain = Offer(false, false);
        var leaving = Offer(false, true);
        var both = Offer(true, true);
        ShopSong[] all = [fresh, plain, leaving, both];
        // Issue #376: include switches, all on by default, so the default shows every offer and is inactive.
        Assert.All(all, o => Assert.True(new ShopOfferFilter().Matches(o)));
        Assert.False(new ShopOfferFilter().IsActive);
        Assert.Equal(new ShopOfferFilter(true, true, true), new ShopOfferFilter());
        Assert.Equal([true, false, false, true], all.Select(new ShopOfferFilter(New: true, Available: false, LeavingTomorrow: false).Matches));
        Assert.Equal([false, true, false, false], all.Select(new ShopOfferFilter(New: false, Available: true, LeavingTomorrow: false).Matches));
        Assert.Equal([false, false, true, true], all.Select(new ShopOfferFilter(New: false, Available: false, LeavingTomorrow: true).Matches));
        // One switch off hides only that group; an offer flagged both stays while either of its groups is on.
        Assert.Equal([false, true, true, true], all.Select(new ShopOfferFilter(New: false).Matches));
        Assert.Equal([true, true, false, true], all.Select(new ShopOfferFilter(LeavingTomorrow: false).Matches));
        Assert.Equal([true, false, true, true], all.Select(new ShopOfferFilter(Available: false).Matches));
        // Every switch off shows nothing (like Songs' Item Shop filter), and any switch off is active.
        Assert.All(all, o => Assert.False(new ShopOfferFilter(false, false, false).Matches(o)));
        Assert.True(new ShopOfferFilter(New: false).IsActive);
        Assert.True(new ShopOfferFilter(Available: false).IsActive);
        Assert.True(new ShopOfferFilter(LeavingTomorrow: false).IsActive);
    }

    [Fact]
    public async Task PublicationAdvance_Reloads()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        await Async.Until(() => service.Handler.To("/api/shop").Count() == 2);
    }
}
