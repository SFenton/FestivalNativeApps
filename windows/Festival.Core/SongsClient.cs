using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Festival.Core;

#region Transport
/// <summary>Read-only HTTP client that pins each response to one publication and validates cache responses.</summary>
public sealed class SongsClient
{
    private readonly HttpClient http;
    private readonly Uri endpoint;
    private readonly JsonSerializerOptions json = new(JsonSerializerDefaults.Web);
    private SongsSnapshot? cached;
    private string? etag;

    /// <summary>Creates a client for an explicitly selected read-only endpoint.</summary>
    /// <param name="http">Injectable HTTP transport; the caller owns its lifetime.</param>
    /// <param name="endpoint">Absolute fixture or HTTPS release URL.</param>
    /// <param name="fixtureMode">Allows HTTP only on loopback for local fixtures.</param>
    /// <exception cref="ArgumentException">The URL is not an allowed read-only endpoint.</exception>
    public SongsClient(HttpClient http, Uri endpoint, bool fixtureMode)
    {
        if (!endpoint.IsAbsoluteUri || endpoint.UserInfo.Length != 0 ||
            endpoint.Fragment.Length != 0 || endpoint.Query.Length != 0 ||
            !endpoint.AbsolutePath.Equals("/api/songs", StringComparison.Ordinal) ||
            (fixtureMode
                ? endpoint.Host != "127.0.0.1" || endpoint.Port != 8765 ||
                  endpoint.Scheme != Uri.UriSchemeHttp
                : endpoint.Scheme != Uri.UriSchemeHttps))
        {
            throw new ArgumentException("Expected the read-only songs endpoint on the selected transport.", nameof(endpoint));
        }

        this.http = http;
        this.endpoint = endpoint;
    }

    /// <summary>Fetches one snapshot, reusing an ETag only with its associated publication.</summary>
    /// <param name="cancellationToken">Cancellation of the GET request.</param>
    /// <returns>A validated snapshot; on 304, the previously validated snapshot.</returns>
    /// <exception cref="HttpRequestException">The request failed or returned a conflicting publication.</exception>
    /// <exception cref="JsonException">The payload is malformed or invalid.</exception>
    public async Task<SongsSnapshot> GetAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
        if (cached is not null)
        {
            request.Headers.TryAddWithoutValidation("X-Publication-Id", cached.PublicationId);
            if (etag is not null)
                request.Headers.IfNoneMatch.Add(EntityTagHeaderValue.Parse(etag));
        }

        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotModified)
        {
            if (cached is null || etag is null)
                throw new HttpRequestException("304 without a matching cached publication.");
            if ((response.Headers.ETag is not null && response.Headers.ETag.ToString() != etag) ||
                (response.Headers.TryGetValues("X-Publication-Id", out var ids) &&
                 !ids.SequenceEqual([cached.PublicationId])))
            {
                Invalidate();
                throw new HttpRequestException("304 conflicts with the cached publication.");
            }
            return cached;
        }

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            Invalidate();
            throw new HttpRequestException("Publication changed; reload the songs list.", null, response.StatusCode);
        }

        response.EnsureSuccessStatusCode();
        var snapshot = await JsonSerializer.DeserializeAsync<SongsSnapshot>(
            await response.Content.ReadAsStreamAsync(cancellationToken), json, cancellationToken);
        if (snapshot is null || string.IsNullOrWhiteSpace(snapshot.PublicationId) || snapshot.Songs is null ||
            snapshot.Songs.Any(song => string.IsNullOrWhiteSpace(song.Id) ||
                                       string.IsNullOrWhiteSpace(song.Title) ||
                                       song.Difficulty is < 1 or > 7) ||
            snapshot.Songs.Select(song => song.Id).Distinct(StringComparer.Ordinal).Count() != snapshot.Songs.Count)
            throw new JsonException("Invalid songs snapshot.");

        // A new publication replaces the previous ETag and snapshot atomically.
        cached = snapshot;
        etag = response.Headers.ETag?.ToString();
        return snapshot;
    }

    /// <summary>Discards publication-scoped data before the next fetch.</summary>
    public void Invalidate()
    {
        cached = null;
        etag = null;
    }
#endregion
}
