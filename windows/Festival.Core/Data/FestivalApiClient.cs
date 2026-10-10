using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

namespace Festival.Core.Data;

#region Client
/// <summary>
/// Publication-aware, read-only client for the public service. Online-only: the in-process
/// ETag cache only speeds up conditional GETs within one publication (and keeps those bodies showing through a
/// scrape-lifecycle freeze miss, issue #554) and is cleared when it changes.
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Keyless public production origin.</summary>
    public static readonly Uri ProductionBaseUri = new("https://festivalscoretracker.com/");

    /// <summary>Response header carrying the served publication.</summary>
    public const string PublicationHeader = "X-FST-Publication-Id";

    private static readonly Uri ArtworkCdn = new("https://cdn2.unrealengine.com/");
    private readonly RequestGate gate;
    private readonly ResponseCache cache;
    private readonly SemaphoreSlim publicationLock = new(1, 1);
    private Publication? current;

    /// <summary>Creates a client for HTTPS production or a loopback HTTP fixture origin.</summary>
    /// <param name="gate">The single request gate.</param>
    /// <param name="baseUri">Origin; defaults to <see cref="ProductionBaseUri"/>.</param>
    /// <param name="cache">Optional in-process response cache.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InsecureBaseUrl"/>.</exception>
    public FestivalApiClient(RequestGate gate, Uri? baseUri = null, ResponseCache? cache = null)
    {
        baseUri ??= ProductionBaseUri;
        if (!baseUri.IsAbsoluteUri || baseUri.UserInfo.Length != 0 ||
            !(baseUri.Scheme == Uri.UriSchemeHttps || (baseUri.Scheme == Uri.UriSchemeHttp && baseUri.IsLoopback)))
            throw new FestivalApiException(FestivalApiErrorKind.InsecureBaseUrl);
        this.gate = gate;
        BaseUri = baseUri;
        this.cache = cache ?? new ResponseCache();
    }

    /// <summary>Raised after the observed publication advances (caches have been cleared).</summary>
    public event EventHandler<long>? PublicationChanged;

    /// <summary>Configured origin.</summary>
    public Uri BaseUri { get; }

    /// <summary>Last validated publication.</summary>
    public Publication? CurrentPublication => current;

    #region Publication
    /// <summary>Bootstraps or refreshes the current published generation.</summary>
    /// <param name="force">Ignore the last generation (after a conflict).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated publication.</returns>
    public async Task<Publication> GetPublicationAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        if (!force && current is { } known) return known;
        await publicationLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!force && current is { } raced) return raced;
            using var request = RequestGate.CreateGet(ServiceEndpoints.Publication(BaseUri));
            var response = await gate.SendAsync(request, 1_000_000, cancellationToken).ConfigureAwait(false);
            RequestGate.MapStatus(response, acceptsSyncing: false);
            if (response.Status != 200) throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, response.Status);
            var next = Decode(response.Body, FestivalJsonContext.Default.Publication);
            next.Validate();
            if (current is { } previous && next.PublicationId < previous.PublicationId)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidPublication);
            var changed = current is { } old && old.PublicationId != next.PublicationId;
            current = next;
            if (changed)
            {
                cache.Clear();
                PublicationChanged?.Invoke(this, next.PublicationId);
            }
            return next;
        }
        finally
        {
            publicationLock.Release();
        }
    }
    #endregion

    #region Public reads
    /// <summary>Reads and validates the song catalogue.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated catalogue.</returns>
    public async Task<SongsResponse> GetSongsAsync(CancellationToken cancellationToken = default)
    {
        var bytes = await ReadPinnedAsync(ServiceEndpoints.Songs(BaseUri), 40_000_000, cancellationToken).ConfigureAwait(false);
        var songs = Decode(bytes, FestivalJsonContext.Default.SongsResponse);
        songs.Validate();
        return songs;
    }

    /// <summary>Reads one solo chart page.</summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="instrument">Solo chart.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="top">Rows per page, 1–25 (10 for a Detail preview).</param>
    /// <param name="leeway">Optional invalid-score leeway.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated rows.</returns>
    public async Task<LeaderboardResponse> GetLeaderboardAsync(
        string songId, Instrument instrument, int page = 1, int top = 25, double? leeway = null,
        CancellationToken cancellationToken = default)
    {
        if (page < 1 || page - 1 > int.MaxValue / Math.Max(top, 1))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var url = ServiceEndpoints.Leaderboard(BaseUri, songId, instrument, top, (page - 1) * top, leeway);
        var bytes = await ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false);
        var board = Decode(bytes, FestivalJsonContext.Default.LeaderboardResponse);
        board.Validate(songId, instrument, top);
        return board;
    }

    /// <summary>Searches public accounts (unpinned operational read).</summary>
    /// <param name="query">User text, trimmed here.</param>
    /// <param name="limit">Results, 1–10.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated, de-duplicated results.</returns>
    public async Task<PlayerSearchResponse> SearchPlayersAsync(string query, int limit = 10, CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(ServiceEndpoints.AccountSearch(BaseUri, query.Trim(), limit));
        var response = await gate.SendAsync(request, 64_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        var decoded = Decode(response.Body, FestivalJsonContext.Default.PlayerSearchResponse);
        if (decoded.Results is null || decoded.Results.Count > limit)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var results = new List<PlayerSearchResult>(decoded.Results.Count);
        foreach (var result in decoded.Results)
        {
            var name = result.DisplayName?.Trim() ?? "";
            if (!ProfileText.IsValidAccountId(result.AccountId) || name.Length is 0 or > 200 ||
                ProfileText.ContainsUnsafeCharacter(name) || !seen.Add(result.AccountId))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            results.Add(result with { DisplayName = name });
        }
        return new PlayerSearchResponse(results);
    }
    #endregion

    #region Artwork
    /// <summary>Resolves a CDN-relative, absolute or loopback-fixture art reference.</summary>
    /// <param name="raw">Song <c>albumArt</c> value.</param>
    /// <returns>HTTPS (or loopback) URL, or <see langword="null"/> when absent or unsafe.</returns>
    public Uri? ArtworkUri(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        Uri? url;
        if (raw.StartsWith("/__fixture__/", StringComparison.Ordinal))
            url = BaseUri.IsLoopback ? new Uri(BaseUri, raw) : null;
        else if (raw.Contains("://", StringComparison.Ordinal))
            url = Uri.TryCreate(raw, UriKind.Absolute, out var absolute) ? absolute : null;
        else
            url = raw.StartsWith('/') || raw.Contains("..", StringComparison.Ordinal) ? null : new Uri(ArtworkCdn, raw);
        return url is not null && (url.Scheme == Uri.UriSchemeHttps || (url.Scheme == Uri.UriSchemeHttp && url.IsLoopback))
            ? url : null;
    }

    /// <summary>Downloads artwork bytes through the gate (no process cache; see <see cref="ArtworkByteCache"/>).</summary>
    /// <param name="url">URL from <see cref="ArtworkUri"/>.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Image bytes (≤8 MB, <c>image/*</c>).</returns>
    public async Task<byte[]> GetArtworkBytesAsync(Uri url, CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(url);
        var response = await gate.SendAsync(request, 8_000_000, cancellationToken).ConfigureAwait(false);
        if (response.Status != 200) throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, response.Status);
        if (response.Header("Content-Type")?.StartsWith("image/", StringComparison.OrdinalIgnoreCase) != true ||
            response.Body.Length == 0)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, 200);
        return response.Body;
    }
    #endregion

    #region Pinned read
    /// <summary>
    /// Reads a publication-bound resource: optional pin header, ETag reuse only within the same
    /// publication, one retry after a <c>publication_changed</c> 409, and response-publication checks. A 503 during
    /// the scrape → publish lifecycle returns this publication's already-verified body when there is one, like the
    /// service's own published-cache reads; without one it throws so the page shows "Scores are updating".
    /// </summary>
    /// <param name="url">Allowlisted URL.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Verified body bytes.</returns>
    internal async Task<byte[]> ReadPinnedAsync(Uri url, int maxBytes, CancellationToken cancellationToken) =>
        (await ReadPinnedResponseAsync(url, maxBytes, acceptsSyncing: false, cancellationToken).ConfigureAwait(false)).Body;

    /// <summary>
    /// <see cref="ReadPinnedAsync"/> that also reports the status and served publication, and optionally
    /// accepts a documented HTTP 202 syncing envelope (returned uncached, without publication checks).
    /// </summary>
    /// <param name="url">Allowlisted URL.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="acceptsSyncing">Whether the endpoint documents a 202 syncing envelope.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Verified body, status and the header-verified publication (if any).</returns>
    internal async Task<PinnedRead> ReadPinnedResponseAsync(Uri url, int maxBytes, bool acceptsSyncing, CancellationToken cancellationToken)
    {
        var publication = await GetPublicationAsync(false, cancellationToken).ConfigureAwait(false);
        var key = url.AbsoluteUri;
        var cached = cache.Get(key, publication.PublicationId);
        var response = await SendPinnedAsync(url, publication, cached?.ETag, maxBytes, cancellationToken).ConfigureAwait(false);

        if (response.Status == 409 && IsPublicationConflict(response.Body))
        {
            publication = await GetPublicationAsync(true, cancellationToken).ConfigureAwait(false);
            cached = cache.Get(key, publication.PublicationId);
            response = await SendPinnedAsync(url, publication, cached?.ETag, maxBytes, cancellationToken).ConfigureAwait(false);
        }

        var responseId = ParsePublication(response.Header(PublicationHeader));
        if (response.Status == 304)
        {
            if (cached is not null && responseId == publication.PublicationId)
                return new PinnedRead(cached.Body, 200, responseId, publication.PublicationId);
            response = await SendPinnedAsync(url, publication, null, maxBytes, cancellationToken).ConfigureAwait(false);
            responseId = ParsePublication(response.Header(PublicationHeader));
        }

        if (IsScoreUpdateFreeze(response) && cached is not null && current?.PublicationId == publication.PublicationId
            && (responseId is null || responseId == publication.PublicationId))
            return new PinnedRead(cached.Body, 200, publication.PublicationId, publication.PublicationId);

        if (RequestGate.MapStatus(response, acceptsSyncing) == GateStatus.Syncing)
            return new PinnedRead(response.Body, 202, responseId, publication.PublicationId);
        if (responseId is { } served && served != publication.PublicationId)
        {
            if (publication.PinningEnabled || served < publication.PublicationId)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidPublication);
            publication = await GetPublicationAsync(true, cancellationToken).ConfigureAwait(false);
            if (publication.PublicationId != served)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidPublication);
        }
        else if (responseId is null && publication.PinsRequests)
        {
            throw new FestivalApiException(FestivalApiErrorKind.InvalidPublication);
        }

        if (responseId is not null)
            cache.Store(key, new ResponseCache.Entry(response.Body, publication.PublicationId, response.Header("ETag")));
        return new PinnedRead(response.Body, response.Status, responseId, publication.PublicationId);
    }

    /// <summary>Sends one pinned GET.</summary>
    /// <param name="url">Resource URL.</param>
    /// <param name="publication">Generation observed before this request.</param>
    /// <param name="etag">Entity tag of a same-publication cached body.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Raw response.</returns>
    private Task<GateResponse> SendPinnedAsync(Uri url, Publication publication, string? etag, int maxBytes, CancellationToken cancellationToken)
    {
        var request = RequestGate.CreateGet(url);
        if (publication.PinsRequests)
            request.Headers.TryAddWithoutValidation(PublicationHeader, publication.PublicationId.ToString(CultureInfo.InvariantCulture));
        if (etag is not null) request.Headers.TryAddWithoutValidation("If-None-Match", etag);
        return SendAndDispose(request, maxBytes, cancellationToken);
    }

    /// <summary>Sends a request and disposes it afterwards.</summary>
    /// <param name="request">Owned request.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Raw response.</returns>
    private async Task<GateResponse> SendAndDispose(HttpRequestMessage request, int maxBytes, CancellationToken cancellationToken)
    {
        using (request) return await gate.SendAsync(request, maxBytes, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Whether a 409 body is the service's <c>publication_changed</c> conflict.</summary>
    /// <param name="body">Response body.</param>
    /// <returns><see langword="true"/> for a retryable conflict.</returns>
    private static bool IsPublicationConflict(byte[] body)
    {
        try
        {
            return JsonSerializer.Deserialize(body, FestivalJsonContext.Default.ConflictBody)?.Status == "publication_changed";
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>
    /// Whether a response is the service's scrape-lifecycle freeze miss (503 stamped with a score-update
    /// <see cref="ServiceFreezeReason"/>). The service then still serves its last published generation, so a body this
    /// client verified for the same publication is that data (issue #554); an unstamped 503 or any other freeze reason
    /// stays an outage.
    /// </summary>
    /// <param name="response">Raw response.</param>
    /// <returns><see langword="true"/> for a 503 during scrape, post-process, publish or publication commit.</returns>
    private static bool IsScoreUpdateFreeze(GateResponse response) =>
        response.Status == 503 && ServiceFreezeReason.IsScoreUpdate(response.Header(ServiceFreezeReason.Header));

    /// <summary>Parses a positive publication header.</summary>
    /// <param name="value">Header value.</param>
    /// <returns>ID, or <see langword="null"/>.</returns>
    private static long? ParsePublication(string? value) =>
        long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0 ? id : null;

    /// <summary>Decodes with source-generated metadata, mapping failures to <see cref="FestivalApiErrorKind.InvalidResponse"/>.</summary>
    /// <typeparam name="T">Wire model.</typeparam>
    /// <param name="body">JSON bytes.</param>
    /// <param name="type">Generated metadata.</param>
    /// <returns>Decoded value.</returns>
    internal static T Decode<T>(byte[] body, JsonTypeInfo<T> type)
    {
        try
        {
            return JsonSerializer.Deserialize(body, type) ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
        catch (JsonException error)
        {
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, inner: error);
        }
    }
    #endregion
}
#endregion

#region Pinned read result
/// <summary>A verified publication-bound response.</summary>
/// <param name="Body">Body bytes.</param>
/// <param name="Status">HTTP status (200 for a reused 304 body; 202 for an accepted syncing envelope).</param>
/// <param name="PublicationId">Header-verified <c>X-FST-Publication-Id</c>, or <see langword="null"/> when headerless.</param>
/// <param name="ObservedPublicationId">Generation the client observed for this read.</param>
internal sealed record PinnedRead(byte[] Body, int Status, long? PublicationId, long ObservedPublicationId);
#endregion

#region Response cache
/// <summary>Bounded in-process LRU of publication-scoped response bodies for ETag reuse and scrape-freeze misses.</summary>
/// <param name="maxEntries">Entry limit.</param>
/// <param name="maxBytes">Total body byte limit.</param>
public sealed class ResponseCache(int maxEntries = 48, long maxBytes = 64_000_000)
{
    /// <summary>A cached body.</summary>
    /// <param name="Body">Bytes.</param>
    /// <param name="PublicationId">Publication that served them.</param>
    /// <param name="ETag">Entity tag, if any.</param>
    public sealed record Entry(byte[] Body, long PublicationId, string? ETag);

    private readonly LinkedList<(string Key, Entry Value)> order = new();
    private readonly Dictionary<string, LinkedListNode<(string Key, Entry Value)>> map = [];
    private readonly Lock gate = new();
    private long bytes;

    /// <summary>Number of cached entries.</summary>
    public int Count
    {
        get { lock (gate) return map.Count; }
    }

    /// <summary>Returns an entry only when it belongs to the given publication.</summary>
    /// <param name="key">Absolute URL.</param>
    /// <param name="publicationId">Current publication.</param>
    /// <returns>Entry or <see langword="null"/>.</returns>
    public Entry? Get(string key, long publicationId)
    {
        lock (gate)
        {
            if (!map.TryGetValue(key, out var node) || node.Value.Value.PublicationId != publicationId) return null;
            order.Remove(node);
            order.AddLast(node);
            return node.Value.Value;
        }
    }

    /// <summary>Stores an entry, evicting least-recently-used entries over the limits.</summary>
    /// <param name="key">Absolute URL.</param>
    /// <param name="entry">Body and provenance.</param>
    public void Store(string key, Entry entry)
    {
        lock (gate)
        {
            if (map.Remove(key, out var old))
            {
                order.Remove(old);
                bytes -= old.Value.Value.Body.Length;
            }
            if (entry.Body.Length > maxBytes) return;
            map[key] = order.AddLast((key, entry));
            bytes += entry.Body.Length;
            while (map.Count > maxEntries || bytes > maxBytes)
            {
                var oldest = order.First!;
                order.RemoveFirst();
                map.Remove(oldest.Value.Key);
                bytes -= oldest.Value.Value.Body.Length;
            }
        }
    }

    /// <summary>Drops everything (publication change).</summary>
    public void Clear()
    {
        lock (gate)
        {
            map.Clear();
            order.Clear();
            bytes = 0;
        }
    }
}
#endregion
