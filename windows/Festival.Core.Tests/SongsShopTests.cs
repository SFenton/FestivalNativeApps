using System.Net;
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
        var beta = vm.Offers[1];
        Assert.True(beta.HasSongDetail);
        Assert.True(beta.HasBadge);
        Assert.Equal(new AppRoute.SongDetail("s2"), beta.DetailRoute);
        Assert.False(vm.HasSongDetailsIssue);
        Assert.True(vm.ShowGrid);
        Assert.False(vm.ShowList);
        // Appear again: no re-read.
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.Single(service.Handler.To("/api/shop"));
    }

    [Fact]
    public async Task ViewToggle_PersistsAndCompactForcesList()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        var vm = new ShopViewModel(session);
        await vm.LoadAsync();
        Assert.Equal("List View", vm.ToggleLabel);
        vm.ToggleViewCommand.Execute(null);
        Assert.Equal(ShopViewMode.List, session.Settings.ShopViewMode);
        Assert.True(vm.ShowList);
        Assert.Equal("Grid View", vm.ToggleLabel);
        vm.ToggleViewCommand.Execute(null);
        vm.IsCompact = true;
        Assert.True(vm.ShowList);
        Assert.False(vm.CanToggleView);
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
        Assert.Equal("0 songs", vm.CountText);

        var failing = new FakeService();
        SongsWire.Install(failing, shopStatus: HttpStatusCode.InternalServerError);
        var failed = new ShopViewModel(failing.Session());
        await failed.LoadAsync();
        Assert.True(failed.ShowError);
        Assert.False(failed.ShowEmpty);

        body = SongsWire.Shop(SongsWire.Offer("s2", "Beta", isNew: true));
        await vm.LoadAsync(force: true);
        Assert.Equal("1 song", vm.CountText);
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        Assert.False(vm.Offers[0].HasBadge);
        session.UpdateSettings(s => s with { HideShop = true });
        Assert.True(vm.IsHidden);
        Assert.False(vm.ShowOffers);
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
