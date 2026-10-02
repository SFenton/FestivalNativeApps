using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Publication
/// <summary>A public data surface that has not yet reached the published generation.</summary>
/// <param name="Surface">Surface name.</param>
/// <param name="Reasons">Machine-readable reasons.</param>
public sealed record UnreadySurface(
    [property: JsonPropertyName("surface")] string Surface,
    [property: JsonPropertyName("reasons")] IReadOnlyList<string> Reasons);

/// <summary>The service generation that makes public reads mutually consistent (<c>GET /api/publication</c>).</summary>
/// <param name="ContractVersion">Positive publication contract version.</param>
/// <param name="PublicationId">Monotonic generation identifier.</param>
/// <param name="PublishedScrapeId">Positive scrape identifier.</param>
/// <param name="ReadyForPinning">Whether the service can honour a pinned read.</param>
/// <param name="PinningEnabled">Whether clients should send <c>X-FST-Publication-Id</c>.</param>
/// <param name="UnreadySurfaces">Surfaces still catching up.</param>
public sealed record Publication(
    [property: JsonPropertyName("contractVersion")] int ContractVersion,
    [property: JsonPropertyName("publicationId")] long PublicationId,
    [property: JsonPropertyName("publishedScrapeId")] long PublishedScrapeId,
    [property: JsonPropertyName("readyForPinning")] bool ReadyForPinning,
    [property: JsonPropertyName("pinningEnabled")] bool PinningEnabled,
    [property: JsonPropertyName("unreadySurfaces")] IReadOnlyList<UnreadySurface>? UnreadySurfaces)
{
    /// <summary>Whether requests should carry the publication pin header.</summary>
    public bool PinsRequests => ReadyForPinning && PinningEnabled;

    /// <summary>Rejects a malformed generation before it is used for requests.</summary>
    /// <exception cref="FestivalApiException">A required identifier is not positive.</exception>
    public void Validate()
    {
        if (ContractVersion <= 0 || PublicationId <= 0 || PublishedScrapeId <= 0)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidPublication);
    }
}
#endregion

#region Songs
/// <summary>Per-chart raw difficulty (0–6), keyed by ordinary instrument names; 99 means uncharted.</summary>
public sealed record SongDifficulty
{
    /// <summary>Lead.</summary>
    [JsonPropertyName("guitar")] public double? Guitar { get; init; }
    /// <summary>Bass.</summary>
    [JsonPropertyName("bass")] public double? Bass { get; init; }
    /// <summary>Drums.</summary>
    [JsonPropertyName("drums")] public double? Drums { get; init; }
    /// <summary>Tap Vocals.</summary>
    [JsonPropertyName("vocals")] public double? Vocals { get; init; }
    /// <summary>Pro Lead.</summary>
    [JsonPropertyName("proGuitar")] public double? ProGuitar { get; init; }
    /// <summary>Pro Bass.</summary>
    [JsonPropertyName("proBass")] public double? ProBass { get; init; }
    /// <summary>Pro Drums.</summary>
    [JsonPropertyName("proDrums")] public double? ProDrums { get; init; }
    /// <summary>Pro Drums + Cymbals.</summary>
    [JsonPropertyName("proCymbals")] public double? ProCymbals { get; init; }
    /// <summary>Karaoke.</summary>
    [JsonPropertyName("proVocals")] public double? ProVocals { get; init; }

    /// <summary>Returns the finite raw difficulty for a charted instrument.</summary>
    /// <param name="instrument">Chart to inspect.</param>
    /// <returns>The raw value, or <see langword="null"/> when absent, negative, non-finite or the 99 sentinel.</returns>
    public double? ChartedValue(Instrument instrument)
    {
        var value = instrument switch
        {
            Instrument.Lead => Guitar,
            Instrument.Bass => Bass,
            Instrument.Drums => Drums,
            Instrument.Vocals => Vocals,
            Instrument.ProLead => ProGuitar,
            Instrument.ProBass => ProBass,
            Instrument.Karaoke => ProVocals,
            Instrument.ProCymbals => ProCymbals,
            _ => ProDrums,
        };
        return value is { } v && double.IsFinite(v) && v >= 0 && v != 99 ? v : null;
    }
}

/// <summary>Fields present in the service's <c>/api/songs</c> wire objects (population tiers are ignored).</summary>
public sealed record Song
{
    /// <summary>Stable song identifier.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Displayed title.</summary>
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    /// <summary>Displayed artist.</summary>
    [JsonPropertyName("artist")] public string Artist { get; init; } = "";
    /// <summary>Optional album.</summary>
    [JsonPropertyName("album")] public string? Album { get; init; }
    /// <summary>Release year.</summary>
    [JsonPropertyName("year")] public int? Year { get; init; }
    /// <summary>Length in seconds.</summary>
    [JsonPropertyName("durationSeconds")] public int? DurationSeconds { get; init; }
    /// <summary>Whether the Pro Drums chart has Double Bass support; absent wire fields stay unknown.</summary>
    [JsonPropertyName("doubleBassSupported")] public bool? DoubleBassSupported { get; init; }
    /// <summary>CDN-relative or absolute art reference.</summary>
    [JsonPropertyName("albumArt")] public string? AlbumArt { get; init; }
    /// <summary>Per-chart difficulty.</summary>
    [JsonPropertyName("difficulty")] public SongDifficulty? Difficulty { get; init; }
    /// <summary>Lead controller signature (<c>Guitar</c> or <c>Keyboard</c>).</summary>
    [JsonPropertyName("sig")] public string? Sig { get; init; }
    /// <summary>CHOpt path artifact revision (sent as <c>generationId</c> on path reads).</summary>
    [JsonPropertyName("pathArtifactGenerationId")] public string? PathArtifactGenerationId { get; init; }
    /// <summary>Per-chart engine maximum score keyed by service instrument ID.</summary>
    [JsonPropertyName("maxScores")] public IReadOnlyDictionary<string, int>? MaxScores { get; init; }

    /// <summary>Whether Lead/Pro Lead should use the keys icon.</summary>
    [JsonIgnore] public bool UsesKeyboardIcon => Sig == "Keyboard";

    /// <summary>Whether an instrument has a playable chart.</summary>
    /// <param name="instrument">Chart to inspect.</param>
    /// <returns><see langword="true"/> when its raw difficulty is charted.</returns>
    public bool Supports(Instrument instrument) => Difficulty?.ChartedValue(instrument) is not null;

    /// <summary>Returns this chart's engine-maximum score.</summary>
    /// <param name="instrument">Chart to look up.</param>
    /// <returns>A positive score, or <see langword="null"/>.</returns>
    public int? MaxScore(Instrument instrument) =>
        MaxScores is not null && MaxScores.TryGetValue(instrument.ServiceId(), out var value) && value > 0 ? value : null;

    /// <summary>Formats a positive duration as <c>m:ss</c> or <c>h:mm:ss</c>.</summary>
    [JsonIgnore]
    public string? FormattedDuration
    {
        get
        {
            if (DurationSeconds is not > 0) return null;
            var total = DurationSeconds.Value;
            var hours = total / 3600;
            var minutes = total % 3600 / 60;
            var seconds = total % 60;
            return hours > 0 ? $"{hours}:{minutes:00}:{seconds:00}" : $"{minutes}:{seconds:00}";
        }
    }

    /// <summary>Artist · year · duration line shown under a title.</summary>
    [JsonIgnore]
    public string Subtitle
    {
        get
        {
            var parts = new List<string>(3) { Artist };
            if (Year is { } year) parts.Add(year.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (FormattedDuration is { } duration) parts.Add(duration);
            return string.Join(" · ", parts.Where(p => p.Length > 0));
        }
    }
}

/// <summary>Catalogue envelope from <c>GET /api/songs</c>.</summary>
/// <param name="Count">Declared number of songs.</param>
/// <param name="CurrentSeason">Current season number.</param>
/// <param name="Songs">Catalogue rows.</param>
public sealed record SongsResponse(
    [property: JsonPropertyName("count")] int Count,
    [property: JsonPropertyName("currentSeason")] int? CurrentSeason,
    [property: JsonPropertyName("songs")] IReadOnlyList<Song> Songs)
{
    /// <summary>Rejects contradictory cardinality or rows without identity.</summary>
    /// <exception cref="FestivalApiException">The catalogue is inconsistent.</exception>
    public void Validate()
    {
        if (Songs is null || Count < 0 || Count != Songs.Count ||
            Songs.Any(s => string.IsNullOrEmpty(s.SongId) || string.IsNullOrEmpty(s.Title)) ||
            Songs.Select(s => s.SongId).Distinct(StringComparer.Ordinal).Count() != Songs.Count)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion

#region Leaderboards
/// <summary>One score row in a solo chart response.</summary>
public sealed record LeaderboardEntry
{
    /// <summary>Public account key.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Display name, when known.</summary>
    [JsonPropertyName("displayName")] public string? DisplayName { get; init; }
    /// <summary>Score.</summary>
    [JsonPropertyName("score")] public long Score { get; init; }
    /// <summary>One-based rank.</summary>
    [JsonPropertyName("rank")] public int Rank { get; init; }
    /// <summary>Accuracy in ten-thousandths of a percent.</summary>
    [JsonPropertyName("accuracy")] public double? Accuracy { get; init; }
    /// <summary>Explicit full-combo flag.</summary>
    [JsonPropertyName("isFullCombo")] public bool? IsFullCombo { get; init; }
    /// <summary>Star rating.</summary>
    [JsonPropertyName("stars")] public int? Stars { get; init; }
    /// <summary>Season number.</summary>
    [JsonPropertyName("season")] public int? Season { get; init; }
}

/// <summary>Solo chart page from <c>GET /api/leaderboard/{song}/{instrument}</c>.</summary>
public sealed record LeaderboardResponse
{
    /// <summary>Requested song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Requested service instrument ID.</summary>
    [JsonPropertyName("instrument")] public string Instrument { get; init; } = "";
    /// <summary>Whether totals may be displayed.</summary>
    [JsonPropertyName("showLeaderboardEntryTotals")] public bool? ShowLeaderboardEntryTotals { get; init; }
    /// <summary>Rows in this page.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Chart population.</summary>
    [JsonPropertyName("totalEntries")] public int TotalEntries { get; init; }
    /// <summary>Locally ranked population used for paging.</summary>
    [JsonPropertyName("localEntries")] public int? LocalEntries { get; init; }
    /// <summary>Score rows.</summary>
    [JsonPropertyName("entries")] public IReadOnlyList<LeaderboardEntry> Entries { get; init; } = [];

    /// <summary>Number of pages of the given size, at least one.</summary>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Page count from <c>localEntries ?? totalEntries</c>.</returns>
    public int PageCount(int pageSize = 25)
    {
        var total = Math.Max(0, LocalEntries ?? TotalEntries);
        return total == 0 ? 1 : (total - 1) / pageSize + 1;
    }

    /// <summary>Rejects a response for another chart or with inconsistent counts.</summary>
    /// <param name="songId">Requested song.</param>
    /// <param name="instrument">Requested chart.</param>
    /// <param name="top">Requested page size.</param>
    /// <exception cref="FestivalApiException">The response is inconsistent.</exception>
    public void Validate(string songId, Instrument instrument, int top)
    {
        if (SongId != songId || Instrument != instrument.ServiceId() || Entries is null ||
            Count != Entries.Count || Count < 0 || Count > top || TotalEntries < 0 || LocalEntries is < 0)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion

#region Player search
/// <summary>One public account search result.</summary>
/// <param name="AccountId">Public account key.</param>
/// <param name="DisplayName">Display name.</param>
public sealed record PlayerSearchResult(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string DisplayName);

/// <summary>Envelope from <c>GET /api/account/search</c>.</summary>
/// <param name="Results">Matching accounts.</param>
public sealed record PlayerSearchResponse(
    [property: JsonPropertyName("results")] IReadOnlyList<PlayerSearchResult> Results);
#endregion

#region Conflict
/// <summary>Minimal 409 body; only <c>publication_changed</c> triggers a retry.</summary>
/// <param name="Status">Conflict status string.</param>
internal sealed record ConflictBody([property: JsonPropertyName("status")] string? Status);
#endregion
