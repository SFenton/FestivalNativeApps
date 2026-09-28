using System.Net;

namespace Festival.Core.Tests;

public class RequestGateTests
{
    private static RequestGate Gate(FakeHandler handler, TimeSpan? timeout = null) => new(new HttpClient(handler), timeout);

    [Fact]
    public void CreateGet_IsKeylessNoCacheGet()
    {
        using var request = RequestGate.CreateGet(new Uri("https://x.test/api/songs"));
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.True(request.Headers.CacheControl!.NoCache);
        RequestGate.ValidateKeyless(request);
    }

    [Theory]
    [InlineData("X-API-Key")]
    [InlineData("x-api-key")]
    [InlineData("X-FST-Selected-Profile")]
    [InlineData("x-fst-selected-account")]
    public void ValidateKeyless_RejectsForbiddenHeaders(string header)
    {
        using var request = RequestGate.CreateGet(new Uri("https://x.test/"));
        request.Headers.TryAddWithoutValidation(header, "value");
        var error = Assert.Throws<FestivalApiException>(() => RequestGate.ValidateKeyless(request));
        Assert.Equal(FestivalApiErrorKind.ForbiddenRequest, error.Kind);
    }

    [Fact]
    public void ValidateKeyless_RejectsNonGetAndBodies()
    {
        using var post = new HttpRequestMessage(HttpMethod.Post, "https://x.test/");
        Assert.Throws<FestivalApiException>(() => RequestGate.ValidateKeyless(post));
        using var getWithBody = new HttpRequestMessage(HttpMethod.Get, "https://x.test/") { Content = new StringContent("x") };
        Assert.Throws<FestivalApiException>(() => RequestGate.ValidateKeyless(getWithBody));
    }

    [Fact]
    public async Task SendAsync_NeverTransmitsForbiddenRequest()
    {
        var handler = new FakeHandler();
        using var request = RequestGate.CreateGet(new Uri("https://x.test/"));
        request.Headers.TryAddWithoutValidation("X-API-Key", "secret");
        await Assert.ThrowsAsync<FestivalApiException>(() => Gate(handler).SendAsync(request));
        Assert.Empty(handler.Requests);
    }

    [Theory]
    [InlineData(200, GateStatus.Success)]
    [InlineData(204, GateStatus.Success)]
    public void MapStatus_Success(int status, GateStatus expected) =>
        Assert.Equal(expected, RequestGate.MapStatus(new GateResponse(status, []), false));

    [Fact]
    public void MapStatus_Accepted202OnlyWhenDocumented()
    {
        Assert.Equal(GateStatus.Syncing, RequestGate.MapStatus(new GateResponse(202, []), true));
        Assert.Equal(FestivalApiErrorKind.Syncing,
            Assert.Throws<FestivalApiException>(() => RequestGate.MapStatus(new GateResponse(202, []), false)).Kind);
    }

    [Fact]
    public void MapStatus_MapsErrors()
    {
        Assert.Equal(FestivalApiErrorKind.UnexpectedNotModified,
            Assert.Throws<FestivalApiException>(() => RequestGate.MapStatus(new GateResponse(304, []), false)).Kind);
        var frozen = Assert.Throws<FestivalApiException>(() => RequestGate.MapStatus(new GateResponse(503, [],
            [KeyValuePair.Create("retry-after", "30"), KeyValuePair.Create("x-fst-public-read-freeze-reason", "scrape")]), false));
        Assert.Equal(FestivalApiErrorKind.PublicReadFrozen, frozen.Kind);
        Assert.Equal("30", frozen.RetryAfter);
        Assert.Equal("scrape", frozen.FreezeReason);
        var outage = Assert.Throws<FestivalApiException>(() => RequestGate.MapStatus(new GateResponse(503, [], [KeyValuePair.Create("Retry-After", "12")]), false));
        Assert.Equal(FestivalApiErrorKind.Unavailable, outage.Kind);
        Assert.Equal("12", outage.RetryAfter);
        var missing = Assert.Throws<FestivalApiException>(() => RequestGate.MapStatus(new GateResponse(404, []), false));
        Assert.Equal((FestivalApiErrorKind.HttpStatus, 404), (missing.Kind, missing.StatusCode));
    }

    [Fact]
    public async Task SendAsync_ReturnsBodyAndMergedHeaders()
    {
        var handler = new FakeHandler { Responder = (_, _) => Task.FromResult(Wire.Ok("{}", ("ETag", "W/\"a\""), ("X-FST-Publication-Id", "9"))) };
        using var request = RequestGate.CreateGet(new Uri("https://x.test/a"));
        var response = await Gate(handler).SendAsync(request);
        Assert.Equal(200, response.Status);
        Assert.Equal("{}"u8.ToArray(), response.Body);
        Assert.Equal("W/\"a\"", response.Header("etag"));
        Assert.Equal("9", response.Header("x-fst-publication-id"));
        Assert.StartsWith("application/json", response.Header("Content-Type"));
        Assert.Null(response.Header("missing"));
    }

    [Fact]
    public async Task SendAsync_TimesOutAfterDeadline()
    {
        var handler = new FakeHandler { Responder = async (_, token) => { await Task.Delay(5000, token); return Wire.Ok("{}"); } };
        using var request = RequestGate.CreateGet(new Uri("https://x.test/slow"));
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => Gate(handler, TimeSpan.FromMilliseconds(50)).SendAsync(request));
        Assert.Equal(FestivalApiErrorKind.Timeout, error.Kind);
    }

    [Fact]
    public async Task SendAsync_CallerCancellationIsNotATimeout()
    {
        var handler = new FakeHandler { Responder = async (_, token) => { await Task.Delay(5000, token); return Wire.Ok("{}"); } };
        using var request = RequestGate.CreateGet(new Uri("https://x.test/slow"));
        using var cts = new CancellationTokenSource(30);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Gate(handler).SendAsync(request, cancellationToken: cts.Token));
    }

    [Fact]
    public void DefaultTimeout_IsThirtySeconds() => Assert.Equal(TimeSpan.FromSeconds(30), RequestGate.DefaultTimeout);

    [Theory]
    [InlineData(HttpRequestError.ConnectionError, FestivalApiErrorKind.Offline)]
    [InlineData(HttpRequestError.NameResolutionError, FestivalApiErrorKind.Offline)]
    [InlineData(HttpRequestError.SecureConnectionError, FestivalApiErrorKind.InvalidResponse)]
    public async Task SendAsync_MapsTransportFailures(HttpRequestError kind, FestivalApiErrorKind expected)
    {
        var handler = new FakeHandler { Responder = (_, _) => throw new HttpRequestException(kind, "boom") };
        using var request = RequestGate.CreateGet(new Uri("https://x.test/"));
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => Gate(handler).SendAsync(request));
        Assert.Equal(expected, error.Kind);
        Assert.IsType<HttpRequestException>(error.InnerException);
    }

    [Fact]
    public async Task SendAsync_RejectsOversizedBodies()
    {
        var handler = new FakeHandler { Responder = (_, _) => Task.FromResult(Wire.Ok(new string('x', 100))) };
        using var declared = RequestGate.CreateGet(new Uri("https://x.test/"));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => Gate(handler).SendAsync(declared, maxBytes: 10))).Kind);

        handler.Responder = (_, _) =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new NonSeekableStream(new byte[100])) };
            return Task.FromResult(response);
        };
        using var streamed = RequestGate.CreateGet(new Uri("https://x.test/"));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => Gate(handler).SendAsync(streamed, maxBytes: 10))).Kind);
    }

    private sealed class NonSeekableStream(byte[] data) : MemoryStream(data)
    {
        public override bool CanSeek => false;
    }
}
