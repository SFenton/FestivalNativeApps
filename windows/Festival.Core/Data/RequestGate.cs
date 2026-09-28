using System.Net.Http.Headers;

namespace Festival.Core.Data;

#region Gate response
/// <summary>Raw status, bytes and case-insensitive headers returned through the gate.</summary>
public sealed class GateResponse
{
    private readonly Dictionary<string, string> headers;

    /// <summary>Creates a response.</summary>
    /// <param name="status">HTTP status.</param>
    /// <param name="body">Unmodified body bytes.</param>
    /// <param name="headers">Headers in any capitalization; later duplicates win.</param>
    public GateResponse(int status, byte[] body, IEnumerable<KeyValuePair<string, string>>? headers = null)
    {
        Status = status;
        Body = body;
        this.headers = new(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in headers ?? []) this.headers[key] = value;
    }

    /// <summary>HTTP status.</summary>
    public int Status { get; }

    /// <summary>Body bytes.</summary>
    public byte[] Body { get; }

    /// <summary>Reads a header regardless of the server's capitalization.</summary>
    /// <param name="name">Header name.</param>
    /// <returns>The value, or <see langword="null"/>.</returns>
    public string? Header(string name) => headers.GetValueOrDefault(name);
}

/// <summary>How a successful status should be interpreted.</summary>
public enum GateStatus
{
    /// <summary>2xx other than an accepted 202: decode the body.</summary>
    Success,
    /// <summary>Accepted HTTP 202 syncing envelope.</summary>
    Syncing,
}
#endregion

#region Request gate
/// <summary>
/// The single keyless request path: every service and artwork GET passes here. It enforces GET-only,
/// rejects <c>X-API-Key</c> and <c>x-fst-selected-*</c> headers, applies a 30-second deadline and maps
/// failures onto <see cref="FestivalApiException"/>.
/// </summary>
public sealed class RequestGate
{
    /// <summary>Default deadline for every request.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);

    /// <summary>Header names that must never leave the app.</summary>
    public static IReadOnlySet<string> ForbiddenHeaderNames { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "x-api-key" };

    /// <summary>Header prefixes that must never leave the app (selected-profile headers register activity).</summary>
    public static IReadOnlyList<string> ForbiddenHeaderPrefixes { get; } = ["x-fst-selected-"];

    private readonly HttpClient http;
    private readonly TimeSpan timeout;

    /// <summary>Creates the gate over a caller-owned client.</summary>
    /// <param name="http">Client without a disk cache (SocketsHttpHandler or a test handler).</param>
    /// <param name="timeout">Per-request deadline; defaults to 30 seconds.</param>
    public RequestGate(HttpClient http, TimeSpan? timeout = null)
    {
        this.http = http;
        this.timeout = timeout ?? DefaultTimeout;
        http.Timeout = Timeout.InfiniteTimeSpan;
    }

    /// <summary>Builds the one keyless GET shape every read uses.</summary>
    /// <param name="url">Allowlisted endpoint URL.</param>
    /// <returns>A no-cache GET without credentials.</returns>
    public static HttpRequestMessage CreateGet(Uri url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
        return request;
    }

    /// <summary>Rejects a non-GET request or one carrying a privileged or selected-profile header.</summary>
    /// <param name="request">Request about to be sent.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.ForbiddenRequest"/>.</exception>
    public static void ValidateKeyless(HttpRequestMessage request)
    {
        if (request.Method != HttpMethod.Get || request.Content is not null)
            throw new FestivalApiException(FestivalApiErrorKind.ForbiddenRequest);
        foreach (var header in request.Headers)
        {
            if (ForbiddenHeaderNames.Contains(header.Key) ||
                ForbiddenHeaderPrefixes.Any(p => header.Key.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
                throw new FestivalApiException(FestivalApiErrorKind.ForbiddenRequest);
        }
    }

    /// <summary>Maps a status onto the shared vocabulary.</summary>
    /// <param name="response">Raw response.</param>
    /// <param name="acceptsSyncing">Whether the endpoint documents a 202 syncing envelope.</param>
    /// <returns>Success or accepted syncing.</returns>
    /// <exception cref="FestivalApiException">For 202 (unaccepted), 304, 503 and other non-2xx statuses.</exception>
    public static GateStatus MapStatus(GateResponse response, bool acceptsSyncing)
    {
        switch (response.Status)
        {
            case 202:
                return acceptsSyncing ? GateStatus.Syncing : throw new FestivalApiException(FestivalApiErrorKind.Syncing, 202);
            case >= 200 and <= 299:
                return GateStatus.Success;
            case 304:
                throw new FestivalApiException(FestivalApiErrorKind.UnexpectedNotModified, 304);
            case 503:
                var retryAfter = response.Header("Retry-After");
                var reason = response.Header(ServiceFreezeReason.Header);
                throw string.IsNullOrEmpty(reason)
                    ? new FestivalApiException(FestivalApiErrorKind.Unavailable, 503, retryAfter)
                    : new FestivalApiException(FestivalApiErrorKind.PublicReadFrozen, 503, retryAfter, reason);
            default:
                throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, response.Status);
        }
    }

    /// <summary>Sends one validated GET under the deadline and reads a bounded body.</summary>
    /// <param name="request">Request from <see cref="CreateGet"/>, optionally with pin or ETag headers.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="cancellationToken">Caller cancellation.</param>
    /// <returns>Raw status, body and headers (no status mapping).</returns>
    /// <exception cref="FestivalApiException">Forbidden request, timeout, offline or oversized body.</exception>
    /// <exception cref="OperationCanceledException">The caller cancelled.</exception>
    public async Task<GateResponse> SendAsync(
        HttpRequestMessage request, int maxBytes = 32_000_000, CancellationToken cancellationToken = default)
    {
        ValidateKeyless(request);
        cancellationToken.ThrowIfCancellationRequested();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout);
        try
        {
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token)
                .ConfigureAwait(false);
            if (response.Content.Headers.ContentLength > maxBytes)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, (int)response.StatusCode);
            var body = await response.Content.ReadAsByteArrayAsync(deadline.Token).ConfigureAwait(false);
            if (body.Length > maxBytes)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, (int)response.StatusCode);
            var headers = response.Headers.Concat(response.Content.Headers)
                .Select(h => KeyValuePair.Create(h.Key, string.Join(", ", h.Value)));
            cancellationToken.ThrowIfCancellationRequested();
            return new GateResponse((int)response.StatusCode, body, headers);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new FestivalApiException(FestivalApiErrorKind.Timeout);
        }
        catch (HttpRequestException error)
        {
            throw new FestivalApiException(
                error.HttpRequestError is HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError
                    or HttpRequestError.Unknown
                    ? FestivalApiErrorKind.Offline
                    : FestivalApiErrorKind.InvalidResponse,
                inner: error);
        }
    }
}
#endregion
