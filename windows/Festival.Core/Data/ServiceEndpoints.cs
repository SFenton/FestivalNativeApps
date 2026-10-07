using System.Globalization;
using System.Text;

namespace Festival.Core.Data;

#region Endpoint URLs
/// <summary>
/// Builds allowlisted keyless GET URLs from individually validated segments. Blocked routes
/// (<c>/api/bands/{id}</c>, player stats, band sync-status) have no builder here; band search
/// (<see cref="BandEndpoints.BandSearch"/>) is allowed since the #320 read-only service fix.
/// </summary>
public static partial class ServiceEndpoints
{
    /// <summary><c>GET /api/publication</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri Publication(Uri baseUri) => Build(baseUri, ["api", "publication"]);

    /// <summary><c>GET /api/songs</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri Songs(Uri baseUri) => Build(baseUri, ["api", "songs"]);

    /// <summary><c>GET /api/leaderboard/{song}/{instrument}?top=&amp;offset=[&amp;leeway=]</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="songId">Catalogue song ID.</param>
    /// <param name="instrument">Solo chart.</param>
    /// <param name="top">Rows, 1–25.</param>
    /// <param name="offset">Non-negative row offset.</param>
    /// <param name="leeway">Optional invalid-score leeway, −5…+5.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri Leaderboard(Uri baseUri, string songId, Instrument instrument, int top, int offset, double? leeway = null)
    {
        RequireSegment(songId);
        if (top is < 1 or > 25 || offset < 0 || (leeway is { } l && (!double.IsFinite(l) || l is < -5 or > 5)))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var query = new List<(string, string)>
        {
            ("top", top.ToString(CultureInfo.InvariantCulture)),
            ("offset", offset.ToString(CultureInfo.InvariantCulture)),
        };
        if (leeway is { } value) query.Add(("leeway", value.ToString(CultureInfo.InvariantCulture)));
        return Build(baseUri, ["api", "leaderboard", songId, instrument.ServiceId()], query);
    }

    /// <summary><c>GET /api/account/search?q=&amp;limit=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="query">Trimmed 2–200 character query without control characters.</param>
    /// <param name="limit">Results, 1–10.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri AccountSearch(Uri baseUri, string query, int limit)
    {
        if (query.Length is < 2 or > 200 || query != query.Trim() || ProfileText.ContainsUnsafeCharacter(query) ||
            limit is < 1 or > 10)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return Build(baseUri, ["api", "account", "search"],
            [("q", query), ("limit", limit.ToString(CultureInfo.InvariantCulture))]);
    }

    /// <summary>Rejects an empty or path-breaking segment.</summary>
    /// <param name="segment">Caller-supplied segment.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    internal static void RequireSegment(string? segment)
    {
        if (string.IsNullOrEmpty(segment) || segment.Length > 200 || segment.Contains('/') || segment.Contains('\\') ||
            segment.Contains("..", StringComparison.Ordinal) || ProfileText.ContainsUnsafeCharacter(segment))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
    }

    /// <summary>Joins escaped segments and query items onto the origin.</summary>
    /// <param name="baseUri">Origin.</param>
    /// <param name="segments">Unescaped path segments.</param>
    /// <param name="query">Unescaped query pairs.</param>
    /// <returns>Absolute URL.</returns>
    internal static Uri Build(Uri baseUri, string[] segments, IReadOnlyList<(string Key, string Value)>? query = null)
    {
        var builder = new StringBuilder(baseUri.GetLeftPart(UriPartial.Authority));
        foreach (var segment in segments) builder.Append('/').Append(Uri.EscapeDataString(segment));
        if (query is { Count: > 0 })
        {
            builder.Append('?');
            builder.AppendJoin('&', query.Select(q => $"{Uri.EscapeDataString(q.Key)}={Uri.EscapeDataString(q.Value)}"));
        }
        return new Uri(builder.ToString());
    }
}
#endregion

#region Profile text
/// <summary>Account ID and display-name safety checks shared by search, selection and routes.</summary>
public static class ProfileText
{
    /// <summary>Whether an account ID is 1–128 characters of <c>[A-Za-z0-9_-]</c>.</summary>
    /// <param name="accountId">Candidate ID.</param>
    /// <returns><see langword="true"/> when safe for a URL segment.</returns>
    public static bool IsValidAccountId(string? accountId) =>
        accountId is { Length: >= 1 and <= 128 } && accountId.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-');

    /// <summary>Whether text contains control, line-separator or bidi-override characters.</summary>
    /// <param name="text">Text to inspect.</param>
    /// <returns><see langword="true"/> when unsafe.</returns>
    public static bool ContainsUnsafeCharacter(string text) =>
        text.Any(c => c < 0x20 || c is >= (char)0x7F and <= (char)0x9F or >= (char)0x2028 and <= (char)0x202E
            or >= (char)0x2066 and <= (char)0x2069);
}
#endregion
