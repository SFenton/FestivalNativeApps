using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Wire
/// <summary>One enriched offer from the public Item Shop feed (<c>GET /api/shop</c>).</summary>
public sealed record ShopSong
{
    /// <summary>Catalogue song identifier.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Displayed title.</summary>
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    /// <summary>Displayed artist.</summary>
    [JsonPropertyName("artist")] public string Artist { get; init; } = "";
    /// <summary>Release year.</summary>
    [JsonPropertyName("year")] public int? Year { get; init; }
    /// <summary>CDN-relative or absolute art reference.</summary>
    [JsonPropertyName("albumArt")] public string? AlbumArt { get; init; }
    /// <summary>Official outbound Item Shop link (validated to <c>https://www.fortnite.com/item-shop/jam-tracks/…</c>).</summary>
    [JsonPropertyName("shopUrl")] public string ShopUrl { get; init; } = "";
    /// <summary>Whether the offer rotates out tomorrow.</summary>
    [JsonPropertyName("leavingTomorrow")] public bool LeavingTomorrow { get; init; }
    /// <summary>Whether the offer is new in this rotation.</summary>
    [JsonPropertyName("isNew")] public bool IsNew { get; init; }

    /// <summary><c>artist · year</c> line shown under the title.</summary>
    [JsonIgnore]
    public string Subtitle => Year is { } year ? $"{Artist} · {year.ToString(CultureInfo.InvariantCulture)}" : Artist;

    /// <summary>The validated official link as a URI.</summary>
    [JsonIgnore]
    public Uri? ShopUri => ShopResponse.IsOfficialShopUrl(ShopUrl, out var uri) ? uri : null;
}

/// <summary>Complete, publication-scoped Item Shop envelope.</summary>
public sealed record ShopResponse
{
    /// <summary>Declared offer count.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Offers.</summary>
    [JsonPropertyName("songs")] public IReadOnlyList<ShopSong> Songs { get; init; } = [];
    /// <summary>IDs newly added this rotation (informational; the per-offer flag wins).</summary>
    [JsonPropertyName("newSongs")] public IReadOnlyList<string>? NewSongs { get; init; }
    /// <summary>Service update timestamp (informational).</summary>
    [JsonPropertyName("lastUpdated")] public string? LastUpdated { get; init; }

    /// <summary>Rejects contradictory counts, duplicate or unsafe IDs and untrusted outbound links.</summary>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate()
    {
        if (Songs is null || Count is < 0 or > 10_000 || Count != Songs.Count)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var song in Songs)
        {
            if (song is null || string.IsNullOrEmpty(song.SongId) || song.SongId.Contains('/') ||
                ProfileText.ContainsUnsafeCharacter(song.SongId) || string.IsNullOrEmpty(song.Title) ||
                string.IsNullOrEmpty(song.Artist) || !ids.Add(song.SongId) || !IsOfficialShopUrl(song.ShopUrl, out _))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
    }

    /// <summary>Offers in the source's title-first order (ties by ID), independent of service iteration.</summary>
    /// <returns>New sorted list.</returns>
    public List<ShopSong> SortedSongs() => ShopOfferSort.Sort(Songs, SongSortMode.Title, ascending: true);

    /// <summary>Whether a link is an official HTTPS Jam Track page with no credentials, port, query or fragment.</summary>
    /// <param name="raw">Wire value.</param>
    /// <param name="uri">Parsed link when valid.</param>
    /// <returns><see langword="true"/> for <c>https://www.fortnite.com/item-shop/jam-tracks/&lt;slug&gt;</c>.</returns>
    public static bool IsOfficialShopUrl(string? raw, out Uri? uri)
    {
        uri = null;
        if (string.IsNullOrEmpty(raw) || raw.Length > 2_000 || !Uri.TryCreate(raw, UriKind.Absolute, out var parsed)) return false;
        const string prefix = "/item-shop/jam-tracks/";
        var path = parsed.AbsolutePath;
        if (parsed.Scheme != Uri.UriSchemeHttps || !string.Equals(parsed.Host, "www.fortnite.com", StringComparison.OrdinalIgnoreCase) ||
            !parsed.IsDefaultPort || parsed.UserInfo.Length != 0 || parsed.Query.Length != 0 || parsed.Fragment.Length != 0 ||
            raw.Contains('@') || !path.StartsWith(prefix, StringComparison.Ordinal) || path.Length == prefix.Length)
            return false;
        uri = parsed;
        return true;
    }
}
#endregion

#region Presentation policy
/// <summary>One real Shop availability accent (never a fallback for missing feed data).</summary>
public enum ShopHighlight
{
    /// <summary>New in this rotation (gold).</summary>
    New,
    /// <summary>Leaving tomorrow (red).</summary>
    LeavingTomorrow,
}

/// <summary>Effective hide/highlight policy shared by Shop, Songs and Song Detail.</summary>
public static class ShopPresentationPolicy
{
    /// <summary>Leaving Tomorrow wins over New; hidden Shop or disabled highlighting suppresses both.</summary>
    /// <param name="offer">Validated current offer, or <see langword="null"/>.</param>
    /// <param name="hidden">Hide Item Shop setting.</param>
    /// <param name="highlightingDisabled">Disable highlighting setting.</param>
    /// <returns>The accent, or <see langword="null"/>.</returns>
    public static ShopHighlight? Highlight(ShopSong? offer, bool hidden, bool highlightingDisabled)
    {
        if (hidden || highlightingDisabled || offer is null) return null;
        if (offer.LeavingTomorrow) return ShopHighlight.LeavingTomorrow;
        return offer.IsNew ? ShopHighlight.New : null;
    }

    /// <summary>Readable badge text (also its spoken name).</summary>
    /// <param name="highlight">Accent.</param>
    /// <returns>"New" or "Leaving Tomorrow".</returns>
    public static string Label(this ShopHighlight highlight) =>
        highlight == ShopHighlight.New ? "New" : "Leaving Tomorrow";
}

/// <summary>
/// Item Shop page filter (issues #19, #376): three include switches, one per availability group. <b>Available</b> is
/// the offers that are neither New nor Leaving Tomorrow, so the groups cover every offer (one flagged both is in both).
/// Every switch starts on and every offer shows; turning a switch off hides its group, and with every switch off
/// nothing shows (like Songs' <see cref="SongShopFilter"/>). Uses the wire flags, so it still works while Shop
/// highlighting is off.
/// </summary>
/// <param name="New">Show New offers.</param>
/// <param name="Available">Show offers that are neither New nor Leaving Tomorrow.</param>
/// <param name="LeavingTomorrow">Show offers leaving tomorrow.</param>
public sealed record ShopOfferFilter(bool New = true, bool Available = true, bool LeavingTomorrow = true)
{
    /// <summary>Whether any switch is off (gold Filter button).</summary>
    public bool IsActive => !New || !Available || !LeavingTomorrow;

    /// <summary>Whether an offer passes the filter.</summary>
    /// <param name="offer">Validated offer.</param>
    /// <returns><see langword="true"/> when the offer is in a group whose switch is on.</returns>
    public bool Matches(ShopSong offer) =>
        (New && offer.IsNew) ||
        (LeavingTomorrow && offer.LeavingTomorrow) ||
        (Available && !offer.IsNew && !offer.LeavingTomorrow);
}

/// <summary>
/// Item Shop page sort (issue #379): the Songs list's Title, Artist, Year and Duration modes with a direction, ordered
/// by the same comparison as Songs (<see cref="SongCatalogQuery.Compare"/>: ties by title, then ID; a missing year or
/// duration sorts as zero). The feed has no duration, so it comes from the validated catalogue song when one exists.
/// </summary>
public static class ShopOfferSort
{
    /// <summary>Sort fields the Item Shop offers, in menu order.</summary>
    public static IReadOnlyList<SongSortMode> Modes { get; } =
        [SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration];

    /// <summary>Maps a saved mode the Shop doesn't offer (or an undefined value) to Title.</summary>
    /// <param name="mode">Saved mode.</param>
    /// <returns>A member of <see cref="Modes"/>.</returns>
    public static SongSortMode Normalize(SongSortMode mode) => Modes.Contains(mode) ? mode : SongSortMode.Title;

    /// <summary>Sorts offers.</summary>
    /// <param name="offers">Validated offers.</param>
    /// <param name="mode">Sort field (normalized with <see cref="Normalize"/>).</param>
    /// <param name="ascending">Direction.</param>
    /// <param name="duration">Catalogue duration in seconds by song ID, or <see langword="null"/> when unknown.</param>
    /// <returns>New sorted list.</returns>
    public static List<ShopSong> Sort(IEnumerable<ShopSong> offers, SongSortMode mode, bool ascending, Func<string, int?>? duration = null)
    {
        mode = Normalize(mode);
        var keyed = offers.Select(offer => (Offer: offer, Key: new Song
        {
            SongId = offer.SongId,
            Title = offer.Title,
            Artist = offer.Artist,
            Year = offer.Year,
            DurationSeconds = mode == SongSortMode.Duration ? duration?.Invoke(offer.SongId) : null,
        })).ToList();
        keyed.Sort((a, b) => SongCatalogQuery.Compare(a.Key, b.Key, mode, ascending));
        return [.. keyed.Select(k => k.Offer)];
    }
}

/// <summary>Catalogue rows and their related data (Shop, player scores) must share one observed publication.</summary>
public static class SongRelatedPublicationPolicy
{
    /// <summary>True only when all three observations exist and are equal.</summary>
    /// <param name="catalogue">Publication observed when the catalogue was validated.</param>
    /// <param name="related">Publication observed when the related data was validated.</param>
    /// <param name="current">Latest publication observed by the session.</param>
    /// <returns>Whether the related data may decorate, filter or sort the catalogue rows.</returns>
    public static bool Matches(long? catalogue, long? related, long? current) =>
        catalogue is not null && related is not null && current is not null && catalogue == current && related == current;
}
#endregion
