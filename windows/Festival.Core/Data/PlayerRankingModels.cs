using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Single-account ranking
/// <summary>
/// One account's own row on <c>GET /api/rankings/{instrument}/{accountId}</c>, a pure read
/// (<c>FSTService/Api/RankingsEndpoints.cs:272-327</c>: in-memory lookups on the precomputed board). The web uses the
/// same route as the fallback when player-stats has not embedded ranks; natives never call player-stats (it can store tiers).
/// </summary>
public sealed record PlayerInstrumentRanking : AccountRankingEntry
{
    /// <summary>Service instrument ID; production returns <c>""</c> for this route (live 2026-09-28).</summary>
    [JsonPropertyName("instrument")] public string? Instrument { get; init; }
    /// <summary>Size of the ranked field.</summary>
    [JsonPropertyName("totalRankedAccounts"), JsonRequired] public int TotalRankedAccounts { get; init; }

    /// <summary>Rejects a row for another account/instrument or an impossible total (a blank instrument is accepted).</summary>
    /// <param name="instrument">Requested chart.</param>
    /// <param name="accountId">Requested account.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(Instrument instrument, string accountId)
    {
        if (!(string.IsNullOrEmpty(Instrument) || Instrument == instrument.ServiceId()) ||
            !string.Equals(AccountId, accountId, StringComparison.OrdinalIgnoreCase) ||
            TotalRankedAccounts < 0 || TotalScoreRank < 0 || TotalScore < 0)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>Total Score rank over the field size, 0 (best) to 1, or <see langword="null"/> when unranked.</summary>
    public double? TotalScorePercentile =>
        TotalScoreRank > 0 && TotalRankedAccounts > 0 ? (double)TotalScoreRank / TotalRankedAccounts : null;

    /// <summary>Whether the placement is within the top 5% (gold).</summary>
    public bool IsTopFive => TotalScorePercentile * 100 <= 5;

    /// <summary>"#1,234".</summary>
    public string RankText => ScoreFormatting.Rank(TotalScoreRank);

    /// <summary>Grouped total score.</summary>
    public string TotalScoreText => ScoreFormatting.Score(TotalScore);

    /// <summary>"Top 3%" (two decimals below 1%), or an em dash.</summary>
    public string PercentileText => TotalScorePercentile is { } p ? PlayerRankingText.TopPercent(p) : "—";
}

/// <summary>Whether a single-account ranking exists (HTTP 404 means "not ranked yet", not a failure).</summary>
public enum PlayerRankingState
{
    /// <summary>A row was returned.</summary>
    Available,
    /// <summary>HTTP 404: the account has no rank on this instrument.</summary>
    Unranked,
}

/// <summary>A single-account ranking read.</summary>
/// <param name="Ranking">Row when available.</param>
/// <param name="State">Availability.</param>
public sealed record PlayerInstrumentRankingPayload(PlayerInstrumentRanking? Ranking, PlayerRankingState State);
#endregion

#region Rank history
/// <summary>One daily snapshot (<c>RankHistoryDto</c>) from <c>GET /api/rankings/{instrument}/{accountId}/history</c>.</summary>
public sealed record PlayerRankHistorySnapshot
{
    /// <summary>UTC calendar day <c>yyyy-MM-dd</c> (a label, not an instant).</summary>
    [JsonPropertyName("snapshotDate"), JsonRequired] public string SnapshotDate { get; init; } = "";
    /// <summary>When the snapshot was taken.</summary>
    [JsonPropertyName("snapshotTakenAt")] public string? SnapshotTakenAt { get; init; }
    /// <summary>Adjusted skill rank.</summary>
    [JsonPropertyName("adjustedSkillRank")] public int AdjustedSkillRank { get; init; }
    /// <summary>Weighted rank.</summary>
    [JsonPropertyName("weightedRank")] public int WeightedRank { get; init; }
    /// <summary>FC-rate rank.</summary>
    [JsonPropertyName("fcRateRank")] public int FcRateRank { get; init; }
    /// <summary>Total-score rank.</summary>
    [JsonPropertyName("totalScoreRank"), JsonRequired] public int TotalScoreRank { get; init; }
    /// <summary>Max-score-percent rank.</summary>
    [JsonPropertyName("maxScorePercentRank")] public int MaxScorePercentRank { get; init; }
    /// <summary>Total score.</summary>
    [JsonPropertyName("totalScore")] public long? TotalScore { get; init; }
    /// <summary>Songs played.</summary>
    [JsonPropertyName("songsPlayed")] public int? SongsPlayed { get; init; }
    /// <summary>Full combos.</summary>
    [JsonPropertyName("fullComboCount")] public int? FullComboCount { get; init; }
    /// <summary>Charted songs.</summary>
    [JsonPropertyName("totalChartedSongs")] public int? TotalChartedSongs { get; init; }
    /// <summary>Ranked field size.</summary>
    [JsonPropertyName("rankedAccountCount")] public int? RankedAccountCount { get; init; }

    /// <summary>The snapshot day as a date, or <see langword="null"/> for a malformed value.</summary>
    [JsonIgnore]
    public DateOnly? Date => DateOnly.TryParseExact(SnapshotDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
        ? d : null;
}

/// <summary>Response for <c>/api/rankings/{instrument}/{accountId}/history</c>.</summary>
public sealed record PlayerRankHistory
{
    /// <summary>Service instrument ID.</summary>
    [JsonPropertyName("instrument")] public string Instrument { get; init; } = "";
    /// <summary>Account.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Daily snapshots.</summary>
    [JsonPropertyName("history")] public IReadOnlyList<PlayerRankHistorySnapshot> History { get; init; } = [];

    /// <summary>Rejects another instrument/account, malformed dates, negative ranks or duplicate days.</summary>
    /// <param name="instrument">Requested chart.</param>
    /// <param name="accountId">Requested account.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(Instrument instrument, string accountId)
    {
        if (Instrument != instrument.ServiceId() || !string.Equals(AccountId, accountId, StringComparison.OrdinalIgnoreCase) ||
            History is null || History.Any(h => h is null || h.Date is null || h.TotalScoreRank < 0) ||
            History.Select(h => h.SnapshotDate).Distinct(StringComparer.Ordinal).Count() != History.Count)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>Snapshots with a real Total Score rank, oldest first.</summary>
    [JsonIgnore]
    public List<PlayerRankHistorySnapshot> RankedChronological =>
        History.Where(h => h.TotalScoreRank > 0).OrderBy(h => h.SnapshotDate, StringComparer.Ordinal).ToList();
}
#endregion

#region Formatting
/// <summary>Ranking text shared by the player page and charts.</summary>
public static class PlayerRankingText
{
    /// <summary>"Top N%" from a 0–1 fraction (two decimals below 1%), matching the web's percentile pill.</summary>
    /// <param name="fraction">Rank over field size.</param>
    /// <returns>Text, or <c>N/A</c> for a non-finite value.</returns>
    public static string TopPercent(double fraction)
    {
        if (!double.IsFinite(fraction)) return "N/A";
        var top = Math.Clamp(fraction * 100, 0.01, 100);
        return "Top " + top.ToString(top < 1 ? "0.00" : "0", CultureInfo.CurrentCulture) + "%";
    }

    /// <summary>Padded rank axis (best ≥ 1) with up to four whole-number ticks, best first.</summary>
    /// <param name="ranks">Charted ranks (all ≥ 1).</param>
    /// <returns>Bounds and ticks.</returns>
    public static (int Best, int Worst, List<int> Ticks) RankAxis(IReadOnlyCollection<int> ranks)
    {
        var low = ranks.Count == 0 ? 1 : ranks.Min();
        var high = ranks.Count == 0 ? 1 : ranks.Max();
        var pad = Math.Max(1, (high - low) / 8);
        var best = Math.Max(1, low - pad);
        var worst = Math.Max(best + 1, high + pad);
        var step = Math.Max(1, (int)Math.Ceiling((worst - best) / 3.0));
        var ticks = new List<int>();
        for (var t = best; t <= worst; t += step) ticks.Add(t);
        return (best, worst, ticks);
    }

    /// <summary>First-to-latest movement summary for screen readers (lower rank is better).</summary>
    /// <param name="points">Chronological ranked snapshots.</param>
    /// <returns>Sentence.</returns>
    public static string RankTrend(IReadOnlyList<PlayerRankHistorySnapshot> points)
    {
        if (points.Count == 0) return "No snapshots";
        var delta = points[0].TotalScoreRank - points[^1].TotalScoreRank;
        var trend = delta > 0 ? $"up {delta:N0} places" : delta < 0 ? $"down {-delta:N0} places" : "unchanged";
        return $"{points.Count} daily snapshots. Latest rank {points[^1].TotalScoreRank:N0}, {trend}.";
    }
}
#endregion
