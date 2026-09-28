using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Wire
/// <summary>One tracked score change (<c>ServerScoreHistoryEntry</c>, <c>packages/core/src/api/serverTypes.ts:860-888</c>).</summary>
public sealed record ScoreHistoryEntry
{
    /// <summary>Song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Service instrument ID.</summary>
    [JsonPropertyName("instrument")] public string Instrument { get; init; } = "";
    /// <summary>Previous score.</summary>
    [JsonPropertyName("oldScore")] public long? OldScore { get; init; }
    /// <summary>New score.</summary>
    [JsonPropertyName("newScore")] public long NewScore { get; init; }
    /// <summary>Previous rank.</summary>
    [JsonPropertyName("oldRank")] public int? OldRank { get; init; }
    /// <summary>New rank.</summary>
    [JsonPropertyName("newRank")] public int NewRank { get; init; }
    /// <summary>Accuracy in ten-thousandths of a percent (leaderboard scale).</summary>
    [JsonPropertyName("accuracy")] public double? Accuracy { get; init; }
    /// <summary>Full combo.</summary>
    [JsonPropertyName("isFullCombo")] public bool? IsFullCombo { get; init; }
    /// <summary>Stars.</summary>
    [JsonPropertyName("stars")] public int? Stars { get; init; }
    /// <summary>Percentile.</summary>
    [JsonPropertyName("percentile")] public double? Percentile { get; init; }
    /// <summary>Season.</summary>
    [JsonPropertyName("season")] public int? Season { get; init; }
    /// <summary>When the score was achieved (preferred display date).</summary>
    [JsonPropertyName("scoreAchievedAt")] public string? ScoreAchievedAt { get; init; }
    /// <summary>Season rank.</summary>
    [JsonPropertyName("seasonRank")] public int? SeasonRank { get; init; }
    /// <summary>All-time rank.</summary>
    [JsonPropertyName("allTimeRank")] public int? AllTimeRank { get; init; }
    /// <summary>Difficulty.</summary>
    [JsonPropertyName("difficulty")] public double? Difficulty { get; init; }
    /// <summary>When the change was recorded.</summary>
    [JsonPropertyName("changedAt")] public string ChangedAt { get; init; } = "";

    /// <summary>Sort/display key: achieved time, else recorded time (ISO-8601 sorts lexically).</summary>
    [JsonIgnore] public string DateKey => ScoreAchievedAt ?? ChangedAt;

    /// <summary>Parsed display date, or <see langword="null"/>.</summary>
    [JsonIgnore]
    public DateTimeOffset? DisplayDate =>
        DateTimeOffset.TryParse(DateKey, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var d) ? d : null;

    /// <summary>Local short date, or the raw key.</summary>
    [JsonIgnore]
    public string DateText => DisplayDate is { } d ? d.ToLocalTime().ToString("d", CultureInfo.CurrentCulture) : DateKey;
}

/// <summary><c>GET /api/player/{accountId}/history</c> envelope (202 adds <c>status</c>/<c>notYetPublished</c>).</summary>
public sealed record PlayerHistoryResponse
{
    /// <summary>Account.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Declared row count.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("history")] public IReadOnlyList<ScoreHistoryEntry> History { get; init; } = [];
    /// <summary><c>syncing</c> on 202.</summary>
    [JsonPropertyName("status")] public string? Status { get; init; }
    /// <summary>Set on 202.</summary>
    [JsonPropertyName("notYetPublished")] public bool? NotYetPublished { get; init; }

    /// <summary>Rejects another account or an inconsistent count.</summary>
    /// <param name="accountId">Requested account.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string accountId)
    {
        if (!string.Equals(AccountId, accountId, StringComparison.OrdinalIgnoreCase) || History is null ||
            Count < 0 || Count != History.Count || History.Any(h => h is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}

/// <summary>Availability of a player's score history.</summary>
public enum PlayerHistoryState
{
    /// <summary>Rows (possibly none) are ready.</summary>
    Available,
    /// <summary>HTTP 202: registered, not yet computed.</summary>
    Syncing,
    /// <summary>HTTP 404: not a registered user — never "no history".</summary>
    Unregistered,
}

/// <summary>A history read.</summary>
/// <param name="Response">Validated envelope (empty for unregistered).</param>
/// <param name="State">Availability.</param>
public sealed record PlayerHistoryPayload(PlayerHistoryResponse Response, PlayerHistoryState State)
{
    /// <summary>Rows for exactly one song and chart (the server already filters; re-filtered defensively like the web).</summary>
    /// <param name="songId">Song.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Matching rows.</returns>
    public List<ScoreHistoryEntry> Entries(string songId, Instrument instrument) =>
        Response.History.Where(h => h.SongId == songId && h.Instrument == instrument.ServiceId()).ToList();
}
#endregion

#region Sort
/// <summary>Score-history sort keys (web <c>PlayerScoreSortModal</c>).</summary>
public enum PlayerScoreSortMode
{
    /// <summary>Achieved/recorded date.</summary>
    Date,
    /// <summary>New score (default, descending).</summary>
    Score,
    /// <summary>Accuracy, ties by FC, score, date.</summary>
    Accuracy,
    /// <summary>Season.</summary>
    Season,
}

/// <summary>Pure history ordering (<c>useSortedScoreHistory.ts</c>).</summary>
public static class PlayerScoreHistorySort
{
    /// <summary>Title Case label.</summary>
    /// <param name="mode">Mode.</param>
    /// <returns>Label.</returns>
    public static string Label(this PlayerScoreSortMode mode) => mode.ToString();

    /// <summary>Orders rows; stable for equal keys.</summary>
    /// <param name="entries">Rows for one song/chart.</param>
    /// <param name="mode">Key.</param>
    /// <param name="ascending">Direction.</param>
    /// <returns>New list.</returns>
    public static List<ScoreHistoryEntry> Sorted(IEnumerable<ScoreHistoryEntry> entries, PlayerScoreSortMode mode, bool ascending)
    {
        var direction = ascending ? 1 : -1;
        return entries
            .Select((e, i) => (e, i))
            .OrderBy(x => x, Comparer<(ScoreHistoryEntry E, int I)>.Create((a, b) =>
            {
                var c = direction * Compare(a.E, b.E, mode);
                return c != 0 ? c : a.I.CompareTo(b.I);
            }))
            .Select(x => x.e)
            .ToList();
    }

    /// <summary>Index of the highest <see cref="ScoreHistoryEntry.NewScore"/> in the displayed order (first wins ties).</summary>
    /// <param name="sorted">Displayed rows.</param>
    /// <returns>Index or <see langword="null"/> when empty.</returns>
    public static int? HighScoreIndex(IReadOnlyList<ScoreHistoryEntry> sorted)
    {
        if (sorted.Count == 0) return null;
        var best = 0;
        for (var i = 1; i < sorted.Count; i++)
            if (sorted[i].NewScore > sorted[best].NewScore) best = i;
        return best;
    }

    /// <summary>Ascending comparison for one mode.</summary>
    /// <param name="a">Left.</param>
    /// <param name="b">Right.</param>
    /// <param name="mode">Key.</param>
    /// <returns>Sign.</returns>
    private static int Compare(ScoreHistoryEntry a, ScoreHistoryEntry b, PlayerScoreSortMode mode) => mode switch
    {
        PlayerScoreSortMode.Date => string.CompareOrdinal(a.DateKey, b.DateKey),
        PlayerScoreSortMode.Score => a.NewScore.CompareTo(b.NewScore),
        PlayerScoreSortMode.Season => (a.Season ?? 0).CompareTo(b.Season ?? 0),
        _ => FirstNonZero(
            (a.Accuracy ?? 0).CompareTo(b.Accuracy ?? 0),
            (a.IsFullCombo == true).CompareTo(b.IsFullCombo == true),
            a.NewScore.CompareTo(b.NewScore),
            string.CompareOrdinal(a.DateKey, b.DateKey)),
    };

    /// <summary>First non-zero comparison.</summary>
    /// <param name="values">Comparisons in priority order.</param>
    /// <returns>Sign.</returns>
    private static int FirstNonZero(params int[] values) => values.FirstOrDefault(v => v != 0);
}
#endregion
