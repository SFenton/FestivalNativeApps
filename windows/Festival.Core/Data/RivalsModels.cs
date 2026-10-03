using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Rival lists
/// <summary>One rival's standing against the selected player for a scope (<c>GET …/rivals/{combo}</c>).</summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="DisplayName">Name, if known.</param>
/// <param name="RivalScore">Server-computed closeness score (higher = closer rivalry).</param>
/// <param name="SharedSongCount">Songs both have scored.</param>
/// <param name="AheadCount">Songs where the rival is ahead (rival's perspective).</param>
/// <param name="BehindCount">Songs where the rival is behind.</param>
/// <param name="AvgSignedDelta">Average signed rank delta.</param>
public sealed record RivalSummary(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string? DisplayName,
    [property: JsonPropertyName("rivalScore")] double RivalScore,
    [property: JsonPropertyName("sharedSongCount")] int SharedSongCount,
    [property: JsonPropertyName("aheadCount")] int AheadCount,
    [property: JsonPropertyName("behindCount")] int BehindCount,
    [property: JsonPropertyName("avgSignedDelta")] double AvgSignedDelta);

/// <summary><c>GET /api/player/{accountId}/rivals/{instrument|combo}</c>.</summary>
/// <param name="Combo">Echoed scope.</param>
/// <param name="Above">Rivals ahead of the player.</param>
/// <param name="Below">Rivals behind the player.</param>
public sealed record RivalsListResponse(
    [property: JsonPropertyName("combo")] string? Combo,
    [property: JsonPropertyName("above")] IReadOnlyList<RivalSummary> Above,
    [property: JsonPropertyName("below")] IReadOnlyList<RivalSummary> Below)
{
    /// <summary>The normalized form of the endpoint's "no rivals" 404.</summary>
    /// <param name="combo">Requested scope.</param>
    /// <returns>Empty list.</returns>
    public static RivalsListResponse Empty(string combo) => new(combo, [], []);

    /// <summary>Whether both halves are empty.</summary>
    [JsonIgnore]
    public bool IsEmpty => Above.Count == 0 && Below.Count == 0;

    /// <summary>Rejects missing lists or unsafe account IDs (keeping anonymous empty-ID rows) and drops unsafe names.</summary>
    /// <returns>A sanitized copy.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public RivalsListResponse Validated() => this with
    {
        Above = RivalsValidation.Rivals(Above, r => r.AccountId, r => r.DisplayName, (r, n) => r with { DisplayName = n },
            r => r.SharedSongCount >= 0 && r.AheadCount >= 0 && r.BehindCount >= 0 && double.IsFinite(r.RivalScore), allowAnonymous: true),
        Below = RivalsValidation.Rivals(Below, r => r.AccountId, r => r.DisplayName, (r, n) => r with { DisplayName = n },
            r => r.SharedSongCount >= 0 && r.AheadCount >= 0 && r.BehindCount >= 0 && double.IsFinite(r.RivalScore), allowAnonymous: true),
    };
}

/// <summary>A rival drawn from the global instrument leaderboard.</summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="DisplayName">Name, if known.</param>
/// <param name="SharedSongCount">Songs both have scored.</param>
/// <param name="AheadCount">Songs where the rival is ahead.</param>
/// <param name="BehindCount">Songs where the rival is behind.</param>
/// <param name="AvgSignedDelta">Average signed rank delta.</param>
/// <param name="LeaderboardRank">Rival's global rank.</param>
/// <param name="UserLeaderboardRank">Player's global rank.</param>
public sealed record LeaderboardRivalSummary(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string? DisplayName,
    [property: JsonPropertyName("sharedSongCount")] int SharedSongCount,
    [property: JsonPropertyName("aheadCount")] int AheadCount,
    [property: JsonPropertyName("behindCount")] int BehindCount,
    [property: JsonPropertyName("avgSignedDelta")] double AvgSignedDelta,
    [property: JsonPropertyName("leaderboardRank")] int LeaderboardRank,
    [property: JsonPropertyName("userLeaderboardRank")] int UserLeaderboardRank);

/// <summary><c>GET /api/player/{accountId}/leaderboard-rivals/{instrument}?rankBy=</c>.</summary>
/// <param name="Instrument">Echoed chart.</param>
/// <param name="RankBy">Echoed metric.</param>
/// <param name="UserRank">Player's rank, if ranked.</param>
/// <param name="Above">Rivals ranked above.</param>
/// <param name="Below">Rivals ranked below.</param>
public sealed record LeaderboardRivalsListResponse(
    [property: JsonPropertyName("instrument")] string? Instrument,
    [property: JsonPropertyName("rankBy")] string? RankBy,
    [property: JsonPropertyName("userRank")] int? UserRank,
    [property: JsonPropertyName("above")] IReadOnlyList<LeaderboardRivalSummary> Above,
    [property: JsonPropertyName("below")] IReadOnlyList<LeaderboardRivalSummary> Below)
{
    /// <summary>Whether both halves are empty.</summary>
    [JsonIgnore]
    public bool IsEmpty => Above.Count == 0 && Below.Count == 0;

    /// <summary>Rejects missing lists or unsafe account IDs (keeping anonymous empty-ID rows) and drops unsafe names.</summary>
    /// <returns>A sanitized copy.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public LeaderboardRivalsListResponse Validated() => this with
    {
        Above = RivalsValidation.Rivals(Above, r => r.AccountId, r => r.DisplayName, (r, n) => r with { DisplayName = n },
            r => r.SharedSongCount >= 0 && r.AheadCount >= 0 && r.BehindCount >= 0, allowAnonymous: true),
        Below = RivalsValidation.Rivals(Below, r => r.AccountId, r => r.DisplayName, (r, n) => r with { DisplayName = n },
            r => r.SharedSongCount >= 0 && r.AheadCount >= 0 && r.BehindCount >= 0, allowAnonymous: true),
    };
}
#endregion

#region Rival detail
/// <summary>Rival identity echoed by the detail endpoints.</summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="DisplayName">Name, if known.</param>
public sealed record RivalIdentity(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string? DisplayName);

/// <summary>One shared song's rank and score comparison.</summary>
/// <param name="SongId">Song.</param>
/// <param name="Title">Title, if the service resolved it.</param>
/// <param name="Artist">Artist, if resolved.</param>
/// <param name="Instrument">Chart service ID.</param>
/// <param name="UserInstrument">Player's chart for mixed Pro Drums family comparisons.</param>
/// <param name="RivalInstrument">Rival's chart for mixed comparisons.</param>
/// <param name="UserRank">Player's rank.</param>
/// <param name="RivalRank">Rival's rank.</param>
/// <param name="RankDelta">Positive: the player leads.</param>
/// <param name="UserScore">Player's score.</param>
/// <param name="RivalScore">Rival's score.</param>
public sealed record RivalSongComparison(
    [property: JsonPropertyName("songId")] string SongId,
    [property: JsonPropertyName("title")] string? Title,
    [property: JsonPropertyName("artist")] string? Artist,
    [property: JsonPropertyName("instrument")] string Instrument,
    [property: JsonPropertyName("userInstrument")] string? UserInstrument,
    [property: JsonPropertyName("rivalInstrument")] string? RivalInstrument,
    [property: JsonPropertyName("userRank")] int UserRank,
    [property: JsonPropertyName("rivalRank")] int RivalRank,
    [property: JsonPropertyName("rankDelta")] int RankDelta,
    [property: JsonPropertyName("userScore")] long? UserScore,
    [property: JsonPropertyName("rivalScore")] long? RivalScore)
{
    /// <summary>De-duplication key (web <c>dedupeSongs</c>).</summary>
    [JsonIgnore]
    public string Key => $"{SongId}:{Instrument}:{UserInstrument}:{RivalInstrument}";
}

/// <summary>Response shared by the song-scope and leaderboard rival detail endpoints.</summary>
/// <param name="Rival">Rival identity.</param>
/// <param name="Combo">Song-scope echo.</param>
/// <param name="Instrument">Leaderboard echo.</param>
/// <param name="RankBy">Leaderboard echo.</param>
/// <param name="Source">Computation source.</param>
/// <param name="TotalSongs">Songs before paging.</param>
/// <param name="Sort">Echoed sort.</param>
/// <param name="Songs">Compared songs.</param>
public sealed record RivalDetailResponse(
    [property: JsonPropertyName("rival")] RivalIdentity Rival,
    [property: JsonPropertyName("combo")] string? Combo,
    [property: JsonPropertyName("instrument")] string? Instrument,
    [property: JsonPropertyName("rankBy")] string? RankBy,
    [property: JsonPropertyName("source")] string? Source,
    [property: JsonPropertyName("totalSongs")] int TotalSongs,
    [property: JsonPropertyName("sort")] string? Sort,
    [property: JsonPropertyName("songs")] IReadOnlyList<RivalSongComparison> Songs)
{
    /// <summary>The normalized form of the endpoint's "no precomputed song data" 404.</summary>
    /// <param name="rivalId">Rival account.</param>
    /// <returns>Empty detail.</returns>
    public static RivalDetailResponse Empty(string rivalId) => new(new RivalIdentity(rivalId, null), null, null, null, null, 0, "closest", []);

    /// <summary>Rejects a mismatched rival, missing songs or unsafe IDs; drops unsafe display text.</summary>
    /// <param name="rivalId">Requested rival.</param>
    /// <returns>A sanitized copy.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public RivalDetailResponse Validated(string rivalId)
    {
        if (Rival is null || Songs is null || !string.Equals(Rival.AccountId, rivalId, StringComparison.OrdinalIgnoreCase))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var songs = new List<RivalSongComparison>(Songs.Count);
        foreach (var song in Songs)
        {
            if (song is null || !RivalsValidation.IsSafeText(song.SongId) || !InstrumentInfo.TryParse(song.Instrument, out _) ||
                song.UserRank < 0 || song.RivalRank < 0)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            songs.Add(song with
            {
                Title = RivalsValidation.SafeName(song.Title),
                Artist = RivalsValidation.SafeName(song.Artist),
                UserInstrument = InstrumentInfo.TryParse(song.UserInstrument, out _) ? song.UserInstrument : null,
                RivalInstrument = InstrumentInfo.TryParse(song.RivalInstrument, out _) ? song.RivalInstrument : null,
            });
        }
        return this with { Rival = Rival with { DisplayName = RivalsValidation.SafeName(Rival.DisplayName) }, Songs = songs };
    }
}
#endregion

#region All rivals
/// <summary>One compact shared-song sample (single-letter wire keys).</summary>
/// <param name="SongIndex">Index into <see cref="RivalsAllResponse.Songs"/>.</param>
/// <param name="Instrument">Chart service ID.</param>
/// <param name="UserRank">Player's rank.</param>
/// <param name="RivalRank">Rival's rank.</param>
/// <param name="UserScore">Player's score.</param>
/// <param name="RivalScore">Rival's score.</param>
public sealed record RivalsAllSample(
    [property: JsonPropertyName("s")] int SongIndex,
    [property: JsonPropertyName("i")] string Instrument,
    [property: JsonPropertyName("ur")] int UserRank,
    [property: JsonPropertyName("rr")] int RivalRank,
    [property: JsonPropertyName("us")] long? UserScore,
    [property: JsonPropertyName("rs")] long? RivalScore);

/// <summary>A rival in one combo of the all-combo response (precomputed or live-fallback shape).</summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="DisplayName">Name, if known.</param>
/// <param name="Direction"><c>above</c>/<c>below</c> on the precomputed shape.</param>
/// <param name="SharedSongCount">Shared songs.</param>
/// <param name="AheadCount">Songs where the rival is ahead.</param>
/// <param name="BehindCount">Songs where the rival is behind.</param>
/// <param name="RivalScore">Closeness score.</param>
/// <param name="AvgSignedDelta">Live-fallback only.</param>
/// <param name="Samples">Indexed samples (empty on the live fallback).</param>
public sealed record RivalsAllEntry(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string? DisplayName,
    [property: JsonPropertyName("direction")] string? Direction,
    [property: JsonPropertyName("sharedSongCount")] int SharedSongCount,
    [property: JsonPropertyName("aheadCount")] int AheadCount,
    [property: JsonPropertyName("behindCount")] int BehindCount,
    [property: JsonPropertyName("rivalScore")] double RivalScore,
    [property: JsonPropertyName("avgSignedDelta")] double? AvgSignedDelta,
    [property: JsonPropertyName("samples")] IReadOnlyList<RivalsAllSample>? Samples);

/// <summary>One combo's rivals.</summary>
/// <param name="Combo">Hex combo ID.</param>
/// <param name="Above">Rivals ahead.</param>
/// <param name="Below">Rivals behind.</param>
public sealed record RivalsAllCombo(
    [property: JsonPropertyName("combo")] string Combo,
    [property: JsonPropertyName("above")] IReadOnlyList<RivalsAllEntry> Above,
    [property: JsonPropertyName("below")] IReadOnlyList<RivalsAllEntry> Below);

/// <summary><c>GET /api/player/{accountId}/rivals/all</c>: every combo's rivals with a shared song index.</summary>
/// <param name="AccountId">Player.</param>
/// <param name="Songs">Song IDs referenced by sample indexes.</param>
/// <param name="Combos">Per-combo rivals.</param>
public sealed record RivalsAllResponse(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("songs")] IReadOnlyList<string>? Songs,
    [property: JsonPropertyName("combos")] IReadOnlyList<RivalsAllCombo> Combos)
{
    /// <summary>The normalized form of the endpoint's "No rivals found." 404.</summary>
    /// <param name="accountId">Player.</param>
    /// <returns>Empty response.</returns>
    public static RivalsAllResponse Empty(string accountId) => new(accountId, [], []);

    /// <summary>Whether no combo has any rival.</summary>
    [JsonIgnore]
    public bool IsEmpty => Combos.All(c => c.Above.Count == 0 && c.Below.Count == 0);

    /// <summary>Resolves a sample's song without trusting its index.</summary>
    /// <param name="sample">Sample from this response.</param>
    /// <returns>Song ID, or <see langword="null"/> when out of range.</returns>
    public string? SongId(RivalsAllSample sample) =>
        Songs is { } songs && sample.SongIndex >= 0 && sample.SongIndex < songs.Count ? songs[sample.SongIndex] : null;

    /// <summary>Source echoed by a detail rebuilt with <see cref="DetailFor"/>.</summary>
    public const string DetailSource = "rivals-all";

    /// <summary>
    /// Rebuilds a chart/combo rival detail from this response's samples, for when the detail endpoint answers 503 during a
    /// public-read freeze (issue #95). The precomputed samples are the same stored <c>rival_song_samples</c> rows the
    /// detail endpoint reads (each capped at 200 per chart), so ranks, scores and categories match; titles come from the
    /// catalogue. Not valid for the mixed-chart Pro Drums family (samples carry no player/rival chart).
    /// </summary>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="instruments">Charts the scope covers.</param>
    /// <param name="combo">Scope echoed as <see cref="RivalDetailResponse.Combo"/>.</param>
    /// <returns>Detail sorted closest-first like the service's <c>sort=closest</c>, or <see langword="null"/> when the rival
    /// or its samples on those charts are absent.</returns>
    public RivalDetailResponse? DetailFor(string rivalId, IReadOnlyCollection<Instrument> instruments, string? combo)
    {
        string? name = null;
        var seen = new HashSet<(string SongId, Instrument Instrument)>();
        var songs = new List<RivalSongComparison>();
        foreach (var entry in Combos.SelectMany(c => c.Above.Concat(c.Below)))
        {
            if (!string.Equals(entry.AccountId, rivalId, StringComparison.OrdinalIgnoreCase)) continue;
            name ??= entry.DisplayName;
            foreach (var sample in entry.Samples ?? [])
            {
                if (sample is null || sample.UserRank < 0 || sample.RivalRank < 0 ||
                    !InstrumentInfo.TryParse(sample.Instrument, out var instrument) || !instruments.Contains(instrument) ||
                    SongId(sample) is not { } songId || !RivalsValidation.IsSafeText(songId) || !seen.Add((songId, instrument)))
                    continue;
                songs.Add(new RivalSongComparison(songId, null, null, instrument.ServiceId(), null, null,
                    sample.UserRank, sample.RivalRank, sample.RivalRank - sample.UserRank, sample.UserScore, sample.RivalScore));
            }
        }
        if (songs.Count == 0) return null;
        var sorted = songs.OrderBy(s => Math.Abs((long)s.RankDelta)).ToList();
        return new RivalDetailResponse(new RivalIdentity(rivalId, name), combo, null, null, DetailSource, sorted.Count, "closest", sorted);
    }

    /// <summary>Rejects missing combos or unsafe IDs; defaults absent songs/samples to empty and drops unsafe names.</summary>
    /// <returns>A sanitized copy.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public RivalsAllResponse Validated()
    {
        if (Combos is null) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var combos = Combos.Select(c => c is null || c.Combo is null
            ? throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse)
            : c with { Above = Entries(c.Above), Below = Entries(c.Below) }).ToList();
        return this with { Songs = Songs ?? [], Combos = combos };

        static IReadOnlyList<RivalsAllEntry> Entries(IReadOnlyList<RivalsAllEntry> entries) =>
            RivalsValidation.Rivals(entries, e => e.AccountId, e => e.DisplayName, (e, n) => e with { DisplayName = n, Samples = e.Samples ?? [] },
                e => e.SharedSongCount >= 0 && e.AheadCount >= 0 && e.BehindCount >= 0 && double.IsFinite(e.RivalScore));
    }
}
#endregion

#region Validation
/// <summary>Shared checks for rival payloads: IDs are strict, display text is dropped rather than trusted when unsafe.</summary>
internal static class RivalsValidation
{
    /// <summary>Validates a rival list.</summary>
    /// <typeparam name="T">Row type.</typeparam>
    /// <param name="rows">Decoded rows (may be <see langword="null"/> on a malformed body).</param>
    /// <param name="id">Account ID accessor.</param>
    /// <param name="name">Display name accessor.</param>
    /// <param name="withName">Copies a row with a sanitized name.</param>
    /// <param name="valid">Numeric checks.</param>
    /// <param name="allowAnonymous">Keep rows with an empty account ID (list endpoints; production serves anonymous rows with
    /// no name, as in rankings: issue #200). They render unlinked.</param>
    /// <returns>Sanitized rows.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public static IReadOnlyList<T> Rivals<T>(IReadOnlyList<T>? rows, Func<T, string> id, Func<T, string?> name, Func<T, string?, T> withName, Func<T, bool> valid,
        bool allowAnonymous = false)
        where T : class
    {
        if (rows is null) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var result = new List<T>(rows.Count);
        foreach (var row in rows)
        {
            if (row is null || id(row) is not { } account || !(ProfileText.IsValidAccountId(account) || (allowAnonymous && account.Length == 0)) || !valid(row))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            result.Add(withName(row, SafeName(name(row))));
        }
        return result;
    }

    /// <summary>Trims display text, returning <see langword="null"/> for empty, oversized or unsafe values.</summary>
    /// <param name="text">Raw text.</param>
    /// <returns>Safe text or <see langword="null"/>.</returns>
    public static string? SafeName(string? text)
    {
        var trimmed = text?.Trim();
        return trimmed is { Length: > 0 and <= 200 } && !ProfileText.ContainsUnsafeCharacter(trimmed) ? trimmed : null;
    }

    /// <summary>Whether an identifier is non-empty, bounded and free of unsafe characters.</summary>
    /// <param name="text">Identifier.</param>
    /// <returns><see langword="true"/> when safe.</returns>
    public static bool IsSafeText(string? text) => text is { Length: > 0 and <= 200 } && !ProfileText.ContainsUnsafeCharacter(text);
}
#endregion
