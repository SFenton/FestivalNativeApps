using System.Net;
using System.Net.Http.Headers;
using System.Text;
using Festival.Core;
using Xunit;

namespace Festival.Core.Tests;

#region Fixture transport
/// <summary>Fixture-backed transport, publication, and cache behavior tests.</summary>
public sealed class SongsClientTests
{
    private static readonly Uri FixtureEndpoint = new("http://127.0.0.1:8765/api/songs");

    /// <summary>Verifies both build modes reject unintended transport destinations.</summary>
    [Fact]
    public void EndpointPolicyRejectsNonFixtureAndInsecureReleaseUrls()
    {
        using var http = new HttpClient(new StubHandler(_ => throw new InvalidOperationException()));
        Assert.Throws<ArgumentException>(() => new SongsClient(http, new Uri("https://example.com/api/songs"), true));
        Assert.Throws<ArgumentException>(() => new SongsClient(http, FixtureEndpoint, false));
        Assert.Throws<ArgumentException>(() => new SongsClient(http, new Uri("http://localhost:8765/api/songs"), true));
        Assert.Throws<ArgumentException>(() => new SongsClient(http, new Uri("https://example.com/api/admin"), false));
        _ = new SongsClient(http, new Uri("https://example.com/api/songs"), false);
    }

    /// <summary>Verifies a conditional GET reuses only a previously validated publication.</summary>
    [Fact]
    public async Task ValidatedSnapshotCanBeReusedOn304()
    {
        var calls = 0;
        using var http = new HttpClient(new StubHandler(request =>
        {
            calls++;
            Assert.Equal(HttpMethod.Get, request.Method);
            if (calls == 1)
            {
                Assert.False(request.Headers.Contains("X-Publication-Id"));
                Assert.Empty(request.Headers.IfNoneMatch);
                return FixtureResponse();
            }
            Assert.Equal("fixture-publication-001", request.Headers.GetValues("X-Publication-Id").Single());
            Assert.Equal("\"fixture-etag\"", request.Headers.IfNoneMatch.Single().ToString());
            return new HttpResponseMessage(HttpStatusCode.NotModified);
        }));
        var client = new SongsClient(http, FixtureEndpoint, true);
        var snapshot = await client.GetAsync();
        Assert.Equal(2, snapshot.Songs.Count);
        Assert.Equal(7, snapshot.Songs[1].Difficulty);
        Assert.Same(snapshot, await client.GetAsync());
        Assert.Equal(2, calls);
    }

    /// <summary>Verifies a conflict discards conditional headers on the next request.</summary>
    [Fact]
    public async Task ConflictInvalidatesPublicationAndEtag()
    {
        var calls = 0;
        using var http = new HttpClient(new StubHandler(request =>
        {
            calls++;
            if (calls == 1) return FixtureResponse();
            if (calls == 2) return new HttpResponseMessage(HttpStatusCode.Conflict);
            Assert.False(request.Headers.Contains("X-Publication-Id"));
            Assert.Empty(request.Headers.IfNoneMatch);
            return FixtureResponse();
        }));
        var client = new SongsClient(http, FixtureEndpoint, true);
        await client.GetAsync();
        await Assert.ThrowsAsync<HttpRequestException>(() => client.GetAsync());
        Assert.Equal("fixture-publication-001", (await client.GetAsync()).PublicationId);
    }

    /// <summary>Verifies a 304 without matching cached data is an error rather than an empty success.</summary>
    [Fact]
    public async Task Unsolicited304IsRejected()
    {
        using var http = new HttpClient(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.NotModified)));
        await Assert.ThrowsAsync<HttpRequestException>(() =>
            new SongsClient(http, FixtureEndpoint, true).GetAsync());
    }

    /// <summary>Verifies a mismatched publication in a 304 invalidates conditional cache state.</summary>
    [Fact]
    public async Task Conflicting304InvalidatesCache()
    {
        var calls = 0;
        using var http = new HttpClient(new StubHandler(request =>
        {
            calls++;
            if (calls == 1) return FixtureResponse();
            if (calls == 2)
            {
                var response = new HttpResponseMessage(HttpStatusCode.NotModified);
                response.Headers.TryAddWithoutValidation("X-Publication-Id", "other-publication");
                return response;
            }
            Assert.Empty(request.Headers.IfNoneMatch);
            return FixtureResponse();
        }));
        var client = new SongsClient(http, FixtureEndpoint, true);
        await client.GetAsync();
        await Assert.ThrowsAsync<HttpRequestException>(() => client.GetAsync());
        await client.GetAsync();
        Assert.Equal(3, calls);
    }

    /// <summary>Verifies invalid values do not become cached or displayed.</summary>
    [Theory]
    [InlineData(0)]
    [InlineData(8)]
    public async Task InvalidDifficultyIsRejected(int difficulty)
    {
        using var http = new HttpClient(new StubHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    $$"""{"publicationId":"p","songs":[{"id":"s","title":"t","artist":"a","difficulty":{{difficulty}}}]}""",
                    Encoding.UTF8, "application/json")
            }));
        await Assert.ThrowsAsync<System.Text.Json.JsonException>(() =>
            new SongsClient(http, FixtureEndpoint, true).GetAsync());
    }

    /// <summary>Verifies display state and explicit offline errors use only injected fixture transport.</summary>
    [Fact]
    public async Task ScreenStateRetainsSongsAndReportsOfflineFailure()
    {
        var calls = 0;
        using var http = new HttpClient(new StubHandler(_ =>
        {
            if (++calls == 1) return FixtureResponse();
            throw new HttpRequestException("Fixture unavailable");
        }));
        var state = new SongsState(new SongsClient(http, FixtureEndpoint, true));
        await state.RefreshAsync();
        Assert.Equal("fixture-publication-001", state.Publication);
        Assert.Equal(2, state.Songs.Count);
        await state.RefreshAsync();
        Assert.Equal(2, state.Songs.Count);
        Assert.Contains("Fixture unavailable", state.Status);
        Assert.False(state.IsLoading);
    }

    /// <summary>Creates a response using the checked-in local-only wire fixture.</summary>
    /// <returns>A valid response with an ETag.</returns>
    private static HttpResponseMessage FixtureResponse()
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(File.ReadAllText("songs.json"), Encoding.UTF8, "application/json")
        };
        response.Headers.ETag = new EntityTagHeaderValue("\"fixture-etag\"");
        return response;
    }

    /// <summary>HTTP handler that runs an assertion-only local responder without opening a socket.</summary>
    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        /// <summary>Runs the supplied fixture response factory.</summary>
        /// <param name="request">Intercepted HTTP request.</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>A task containing the fixture response.</returns>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(respond(request));
    }
#endregion
}
