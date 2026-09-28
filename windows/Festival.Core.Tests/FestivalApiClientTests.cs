using System.Net;

namespace Festival.Core.Tests;

public class FestivalApiClientTests
{
    private static RequestGate Gate(FakeHandler handler) => new(new HttpClient(handler));

    [Theory]
    [InlineData("http://festivalscoretracker.com/")]
    [InlineData("ftp://127.0.0.1/")]
    [InlineData("https://user:pw@festivalscoretracker.com/")]
    public void Constructor_RejectsInsecureOrigins(string url)
    {
        var error = Assert.Throws<FestivalApiException>(() => new FestivalApiClient(Gate(new FakeHandler()), new Uri(url)));
        Assert.Equal(FestivalApiErrorKind.InsecureBaseUrl, error.Kind);
    }

    [Fact]
    public void Constructor_AllowsProductionAndLoopback()
    {
        Assert.Equal(FestivalApiClient.ProductionBaseUri, new FestivalApiClient(Gate(new FakeHandler())).BaseUri);
        Assert.Equal(8765, new FestivalApiClient(Gate(new FakeHandler()), new Uri("http://127.0.0.1:8765/")).BaseUri.Port);
    }

    [Fact]
    public async Task Publication_IsCachedUntilForced()
    {
        var service = new FakeService();
        var client = service.Client();
        Assert.Null(client.CurrentPublication);
        Assert.Equal(7, (await client.GetPublicationAsync()).PublicationId);
        await client.GetPublicationAsync();
        Assert.Single(service.Handler.To("/api/publication"));
        await client.GetPublicationAsync(force: true);
        Assert.Equal(2, service.Handler.To("/api/publication").Count());
        Assert.Equal(7, client.CurrentPublication!.PublicationId);
    }

    [Fact]
    public async Task Publication_RejectsRegressionInvalidAndNon200()
    {
        var service = new FakeService();
        var client = service.Client();
        await client.GetPublicationAsync();
        service.PublicationId = 6;
        Assert.Equal(FestivalApiErrorKind.InvalidPublication,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPublicationAsync(true))).Kind);

        service.Override = r => Wire.Ok("""{"contractVersion":0,"publicationId":1,"publishedScrapeId":1,"readyForPinning":false,"pinningEnabled":false}""");
        Assert.Equal(FestivalApiErrorKind.InvalidPublication,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPublicationAsync())).Kind);

        service.Override = r => Wire.Response(HttpStatusCode.NoContent);
        Assert.Equal(FestivalApiErrorKind.HttpStatus,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPublicationAsync())).Kind);

        service.Override = r => Wire.Ok("not json");
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPublicationAsync())).Kind);

        service.Override = r => Wire.Ok("null");
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPublicationAsync())).Kind);
    }

    [Fact]
    public async Task Publication_ChangeClearsCacheAndRaisesEvent()
    {
        var service = new FakeService();
        var client = service.Client();
        long? changed = null;
        client.PublicationChanged += (_, id) => changed = id;
        await client.GetSongsAsync();
        service.PublicationId = 8;
        await client.GetPublicationAsync(true);
        Assert.Equal(8, changed);
        await client.GetSongsAsync();
        Assert.DoesNotContain(service.Handler.To("/api/songs").Last().Headers.Keys, k => k == "If-None-Match");
    }

    [Fact]
    public async Task Songs_DecodesSharedFixture()
    {
        var bytes = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "fixtures", "songs-demo.json"));
        var service = new FakeService { SongsBody = bytes };
        var songs = await service.Client().GetSongsAsync();
        Assert.Equal(2, songs.Songs.Count);
        Assert.StartsWith("fixture-", songs.Songs[0].SongId);
        var publication = await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory, "fixtures", "publication.json"));
        Assert.True(FestivalApiClient.Decode(publication, FestivalJsonContext.Default.Publication).PinsRequests);
    }

    [Fact]
    public async Task Songs_ReadIsKeylessAndReusesSamePublicationETag()
    {
        var service = new FakeService();
        var client = service.Client();
        var first = await client.GetSongsAsync();
        Assert.Equal(3, first.Songs.Count);
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" && r.Headers.TryGetValues("If-None-Match", out _)
            ? Wire.Response(HttpStatusCode.NotModified, "", ("X-FST-Publication-Id", "7"))
            : null;
        var second = await client.GetSongsAsync();
        Assert.Equal(first.Songs.Select(s => s.SongId), second.Songs.Select(s => s.SongId));
        var sent = service.Handler.To("/api/songs").ToList();
        Assert.Equal("W/\"songs\"", sent[1].Headers["If-None-Match"]);
        Assert.All(service.Handler.Requests, r =>
        {
            Assert.Equal(HttpMethod.Get, r.Method);
            Assert.DoesNotContain(r.Headers.Keys, k => k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase) ||
                                                      k.StartsWith("x-fst-selected-", StringComparison.OrdinalIgnoreCase));
            Assert.DoesNotContain(r.Headers.Keys, k => k == FestivalApiClient.PublicationHeader);
        });
    }

    [Fact]
    public async Task Pinned_SendsPublicationHeaderAndRequiresResponseId()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/publication" ? Wire.Ok(Wire.Publication(7, pinning: true)) : null;
        var client = service.Client();
        await client.GetSongsAsync();
        Assert.Equal("7", service.Handler.To("/api/songs").Single().Headers[FestivalApiClient.PublicationHeader]);

        service.Override = r => r.RequestUri!.AbsolutePath == "/api/publication" ? Wire.Ok(Wire.Publication(7, pinning: true))
            : r.RequestUri.AbsolutePath == "/api/songs" ? Wire.Ok(Wire.DefaultSongs()) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidPublication,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync())).Kind);
    }

    [Fact]
    public async Task Pinned_UnexpectedNotModifiedRefetchesWithoutETag()
    {
        var service = new FakeService();
        var client = service.Client();
        await client.GetSongsAsync();
        var calls = 0;
        service.Override = r =>
        {
            if (r.RequestUri!.AbsolutePath != "/api/songs") return null;
            calls++;
            return calls == 1 ? Wire.Response(HttpStatusCode.NotModified, "", ("X-FST-Publication-Id", "99")) : null;
        };
        var songs = await client.GetSongsAsync();
        Assert.Equal(3, songs.Songs.Count);
        Assert.DoesNotContain("If-None-Match", service.Handler.To("/api/songs").Last().Headers.Keys);
    }

    [Fact]
    public async Task Pinned_RetriesOncePublicationConflict()
    {
        var service = new FakeService();
        var client = service.Client();
        await client.GetPublicationAsync();
        var conflicts = 0;
        service.Override = r =>
        {
            if (r.RequestUri!.AbsolutePath != "/api/songs" || conflicts++ > 0) return null;
            service.PublicationId = 8;
            return Wire.Response(HttpStatusCode.Conflict, """{"status":"publication_changed"}""");
        };
        var songs = await client.GetSongsAsync();
        Assert.Equal(3, songs.Songs.Count);
        Assert.Equal(8, client.CurrentPublication!.PublicationId);
    }

    [Fact]
    public async Task Pinned_OtherConflictsAreErrors()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.Conflict, "nope") : null;
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync());
        Assert.Equal((FestivalApiErrorKind.HttpStatus, 409), (error.Kind, error.StatusCode));
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.Conflict, """{"status":"other"}""") : null;
        await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync());
    }

    [Fact]
    public async Task Pinned_AdvancesToNewerUnpinnedResponsePublication()
    {
        var service = new FakeService();
        var client = service.Client();
        await client.GetPublicationAsync();
        service.PublicationId = 9;
        await client.GetSongsAsync();
        Assert.Equal(9, client.CurrentPublication!.PublicationId);
    }

    [Fact]
    public async Task Pinned_RejectsOlderOrUnconfirmedResponsePublication()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Ok(Wire.DefaultSongs(), ("X-FST-Publication-Id", "3")) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidPublication,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync())).Kind);

        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Ok(Wire.DefaultSongs(), ("X-FST-Publication-Id", "12")) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidPublication,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync())).Kind);
    }

    [Fact]
    public async Task Pinned_UnpinnedHeaderlessReadIsNotCached()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Ok(Wire.DefaultSongs()) : null;
        var client = service.Client();
        await client.GetSongsAsync();
        await client.GetSongsAsync();
        Assert.All(service.Handler.To("/api/songs"), r => Assert.DoesNotContain("If-None-Match", r.Headers.Keys));
    }

    [Fact]
    public async Task Pinned_MapsFreeze()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/songs"
            ? Wire.Response(HttpStatusCode.ServiceUnavailable, "", ("Retry-After", "30"), (ServiceFreezeReason.Header, "scrape"))
            : null;
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync());
        Assert.Equal(ServiceIssueKind.ScrapeInProgress, ServiceIssue.From(error).Kind);
    }

    [Fact]
    public async Task Songs_RejectsInconsistentCatalogue()
    {
        var service = new FakeService { SongsBody = """{"count":5,"songs":[]}""" };
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetSongsAsync())).Kind);
    }

    [Fact]
    public async Task Leaderboard_BuildsUrlAndValidates()
    {
        var service = new FakeService();
        var board = await service.Client().GetLeaderboardAsync("s1", Instrument.Bass, page: 2, top: 10);
        Assert.Equal(10, board.Entries.Count);
        var sent = service.Handler.To("/api/leaderboard/s1/Solo_Bass").Single();
        Assert.Equal("?top=10&offset=10", sent.Uri.Query);
        await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetLeaderboardAsync("s1", Instrument.Bass, page: 0));

        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("other", "Solo_Bass", 1), ("X-FST-Publication-Id", "7")) : null;
        await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetLeaderboardAsync("s1", Instrument.Bass));
    }

    [Fact]
    public async Task Search_ValidatesAndTrims()
    {
        var handler = new FakeHandler
        {
            Responder = (_, _) => Task.FromResult(Wire.Ok("""{"results":[{"accountId":"abc_1","displayName":"  Name One "}]}""")),
        };
        var client = new FestivalApiClient(Gate(handler));
        var results = await client.SearchPlayersAsync("  na+me ");
        Assert.Equal("Name One", results.Results.Single().DisplayName);
        Assert.Equal("?q=na%2Bme&limit=10", handler.Requests.Single().Uri.Query);

        foreach (var body in new[]
                 {
                     """{"results":[{"accountId":"bad id","displayName":"x"}]}""",
                     """{"results":[{"accountId":"a","displayName":"x"},{"accountId":"A","displayName":"y"}]}""",
                     """{"results":[{"accountId":"a","displayName":"   "}]}""",
                     """{"results":null}""",
                 })
        {
            handler.Responder = (_, _) => Task.FromResult(Wire.Ok(body));
            await Assert.ThrowsAsync<FestivalApiException>(() => client.SearchPlayersAsync("name"));
        }
        handler.Responder = (_, _) => Task.FromResult(Wire.Ok("""{"results":[{"accountId":"a","displayName":"x"},{"accountId":"b","displayName":"y"}]}"""));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.SearchPlayersAsync("name", limit: 1));
    }

    [Theory]
    [InlineData("art.jpg", "https://cdn2.unrealengine.com/art.jpg")]
    [InlineData("https://cdn.example/a.png", "https://cdn.example/a.png")]
    [InlineData("http://evil.example/a.png", null)]
    [InlineData("/abs.png", null)]
    [InlineData("../up.png", null)]
    [InlineData("/__fixture__/art/a.png", null)]
    [InlineData("", null)]
    [InlineData(null, null)]
    [InlineData("ht tp://bad", null)]
    public void ArtworkUri_ResolvesProduction(string? raw, string? expected) =>
        Assert.Equal(expected, new FestivalApiClient(Gate(new FakeHandler())).ArtworkUri(raw)?.AbsoluteUri);

    [Fact]
    public void ArtworkUri_AllowsFixtureOnLoopback() =>
        Assert.Equal("http://127.0.0.1:8765/__fixture__/art/a.png",
            new FestivalApiClient(Gate(new FakeHandler()), new Uri("http://127.0.0.1:8765/")).ArtworkUri("/__fixture__/art/a.png")!.AbsoluteUri);

    [Fact]
    public async Task ArtworkBytes_RequireImageContent()
    {
        var service = new FakeService();
        var client = service.Client();
        Assert.Equal([1, 2, 3], await client.GetArtworkBytesAsync(new Uri("https://cdn2.unrealengine.com/a.jpg")));
        service.Override = r => Wire.Ok("{}");
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetArtworkBytesAsync(new Uri("https://cdn2.unrealengine.com/a.jpg")));
        service.Override = r => Wire.Response(HttpStatusCode.NotFound);
        Assert.Equal(404, (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetArtworkBytesAsync(new Uri("https://cdn2.unrealengine.com/a.jpg")))).StatusCode);
    }
}
