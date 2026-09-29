using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Song detail endpoints
public static partial class ServiceEndpoints
{
    /// <summary><c>GET /api/leaderboard/{songId}/all?top=10[&amp;leeway=]</c>: every chart's top rows in one read (web <c>getAllLeaderboards</c>).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="songId">Song.</param>
    /// <param name="top">Rows per chart, 1–25.</param>
    /// <param name="leeway">Invalid-score leeway, only while filtering is on.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri AllLeaderboards(Uri baseUri, string songId, int top = 10, double? leeway = null)
    {
        RequireSegment(songId);
        if (top is < 1 or > 25 || (leeway is { } l && (!double.IsFinite(l) || l is < -5 or > 5)))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var query = new List<(string, string)> { ("top", top.ToString(CultureInfo.InvariantCulture)) };
        if (leeway is { } value) query.Add(("leeway", value.ToString(CultureInfo.InvariantCulture)));
        return Build(baseUri, ["api", "leaderboard", songId, "all"], query);
    }

    /// <summary><c>GET /api/player/{accountId}/history?songId=</c>: the player's score changes on every chart of one song.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="songId">Song.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerSongHistory(Uri baseUri, string accountId, string songId)
    {
        RequireSegment(songId);
        return Build(baseUri, ["api", "player", Account(accountId), "history"], [("songId", songId)]);
    }
}
#endregion

#region All leaderboards
/// <summary>One chart inside <see cref="AllLeaderboardsResponse"/>.</summary>
public sealed record AllLeaderboardsInstrument
{
    /// <summary>Service instrument ID.</summary>
    [JsonPropertyName("instrument")] public string Instrument { get; init; } = "";
    /// <summary>Rows returned.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Chart population.</summary>
    [JsonPropertyName("totalEntries")] public int TotalEntries { get; init; }
    /// <summary>Locally ranked population.</summary>
    [JsonPropertyName("localEntries")] public int? LocalEntries { get; init; }
    /// <summary>Top rows.</summary>
    [JsonPropertyName("entries")] public IReadOnlyList<LeaderboardEntry> Entries { get; init; } = [];
}

/// <summary><c>GET /api/leaderboard/{songId}/all</c> envelope (<c>AllLeaderboardsResponse</c>).</summary>
public sealed record AllLeaderboardsResponse
{
    /// <summary>Requested song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Whether totals may be displayed.</summary>
    [JsonPropertyName("showLeaderboardEntryTotals")] public bool? ShowLeaderboardEntryTotals { get; init; }
    /// <summary>One block per chart with scores (charts without scores may be absent).</summary>
    [JsonPropertyName("instruments")] public IReadOnlyList<AllLeaderboardsInstrument> Instruments { get; init; } = [];

    /// <summary>Rejects another song, duplicate charts or inconsistent counts.</summary>
    /// <param name="songId">Requested song.</param>
    /// <param name="top">Requested rows per chart.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string songId, int top)
    {
        if (SongId != songId || Instruments is null || Instruments.Any(i => i is null || i.Entries is null ||
                i.Count != i.Entries.Count || i.Count < 0 || i.Count > top || i.TotalEntries < 0 || i.LocalEntries is < 0) ||
            Instruments.Select(i => i.Instrument).Distinct(StringComparer.Ordinal).Count() != Instruments.Count)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>One chart's rows as a single-chart page (empty when the chart is absent).</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns>Page equivalent to <c>GET /api/leaderboard/{song}/{instrument}?top=</c>.</returns>
    public LeaderboardResponse For(Instrument instrument) =>
        Instruments.FirstOrDefault(i => i.Instrument == instrument.ServiceId()) is { } block
            ? new LeaderboardResponse
            {
                SongId = SongId,
                Instrument = block.Instrument,
                ShowLeaderboardEntryTotals = ShowLeaderboardEntryTotals,
                Count = block.Count,
                TotalEntries = block.TotalEntries,
                LocalEntries = block.LocalEntries,
                Entries = block.Entries,
            }
            : new LeaderboardResponse { SongId = SongId, Instrument = instrument.ServiceId(), ShowLeaderboardEntryTotals = ShowLeaderboardEntryTotals };
}
#endregion
