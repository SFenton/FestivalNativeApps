using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Compact wire
/// <summary>One precomputed filtered-rank changepoint (<c>rt</c> item: <c>l</c>, <c>r</c>).</summary>
/// <param name="Leeway">Invalid-score leeway where this rank starts.</param>
/// <param name="Rank">Rank at that leeway.</param>
public sealed record PlayerRankTier(
    [property: JsonPropertyName("l")] double Leeway,
    [property: JsonPropertyName("r")] int Rank);

/// <summary>A historical valid score held apart from the current score (<c>vs</c> item).</summary>
public sealed record PlayerValidScoreVariant
{
    /// <summary>Score.</summary>
    [JsonPropertyName("sc")] public int Score { get; init; }
    /// <summary>Raw wire accuracy (percent × 10); use <see cref="Accuracy"/>.</summary>
    [JsonPropertyName("acc")] public double? RawAccuracy { get; init; }
    /// <summary>Explicit full-combo flag.</summary>
    [JsonPropertyName("fc")] public bool? IsFullCombo { get; init; }
    /// <summary>Stars, 0–6.</summary>
    [JsonPropertyName("st")] public int? Stars { get; init; }
    /// <summary>Minimum leeway at which this variant applies.</summary>
    [JsonPropertyName("ml")] public double MinLeeway { get; init; }
    /// <summary>Filtered-rank changepoints.</summary>
    [JsonPropertyName("rt")] public IReadOnlyList<PlayerRankTier>? RankTiers { get; init; }

    /// <summary>Accuracy in ten-thousandths of a percent (0–1,000,000), the leaderboard scale.</summary>
    [JsonIgnore] public double? Accuracy => RawAccuracy * 1_000;

    /// <summary>Whether every value is in range.</summary>
    [JsonIgnore]
    public bool IsValid =>
        Score >= 0 && double.IsFinite(MinLeeway) && PlayerScore.InRange(Accuracy) && Stars is null or (>= 0 and <= 6) &&
        (RankTiers ?? []).All(t => t is not null && double.IsFinite(t.Leeway) && t.Rank >= 0);
}

/// <summary>
/// One compact-wire score from <c>GET /api/player/{accountId}</c>. Keys are the service's short names;
/// <c>ins</c> is a single-bit hex instrument code and <c>acc</c> is percent × 10 (exposed ×1,000 as
/// <see cref="Accuracy"/>). Optional flags are never inferred from accuracy.
/// </summary>
public sealed record PlayerScore
{
    /// <summary>Song ID.</summary>
    [JsonPropertyName("si")] public string SongId { get; init; } = "";
    /// <summary>Single-bit hex instrument code; use <see cref="Instrument"/> after validation.</summary>
    [JsonPropertyName("ins")] public string InstrumentCode { get; init; } = "";
    /// <summary>Score.</summary>
    [JsonPropertyName("sc")] public int Score { get; init; }
    /// <summary>Raw wire accuracy (percent × 10); use <see cref="Accuracy"/>.</summary>
    [JsonPropertyName("acc")] public double? RawAccuracy { get; init; }
    /// <summary>Explicit full-combo flag.</summary>
    [JsonPropertyName("fc")] public bool? IsFullCombo { get; init; }
    /// <summary>Stars, 0–6 (6 = gold).</summary>
    [JsonPropertyName("st")] public int? Stars { get; init; }
    /// <summary>Season.</summary>
    [JsonPropertyName("sn")] public int? Season { get; init; }
    /// <summary>Played difficulty.</summary>
    [JsonPropertyName("dif")] public double? Difficulty { get; init; }
    /// <summary>Raw percentile; <c>-1</c> is the "unavailable" sentinel. Use <see cref="Percentile"/>.</summary>
    [JsonPropertyName("pct")] public double? RawPercentile { get; init; }
    /// <summary>One-based rank.</summary>
    [JsonPropertyName("rk")] public int? Rank { get; init; }
    /// <summary>Chart population.</summary>
    [JsonPropertyName("te")] public int? TotalEntries { get; init; }
    /// <summary>Whether the current score passes invalid-score checks.</summary>
    [JsonPropertyName("isValid")] public bool? IsValidScore { get; init; }
    /// <summary>Fallback valid score.</summary>
    [JsonPropertyName("validScore")] public int? ValidScore { get; init; }
    /// <summary>Raw fallback valid accuracy (percent × 10).</summary>
    [JsonPropertyName("validAccuracy")] public double? RawValidAccuracy { get; init; }
    /// <summary>Fallback valid full-combo flag.</summary>
    [JsonPropertyName("validIsFullCombo")] public bool? ValidIsFullCombo { get; init; }
    /// <summary>Minimum leeway at which the current score is valid.</summary>
    [JsonPropertyName("ml")] public double? MinLeeway { get; init; }
    /// <summary>Historical valid variants.</summary>
    [JsonPropertyName("vs")] public IReadOnlyList<PlayerValidScoreVariant>? ValidScores { get; init; }
    /// <summary>Score end time.</summary>
    [JsonPropertyName("et")] public string? EndTime { get; init; }
    /// <summary>Last played.</summary>
    [JsonPropertyName("lp")] public string? LastPlayedAt { get; init; }
    /// <summary>Valid score last played.</summary>
    [JsonPropertyName("vlp")] public string? ValidLastPlayedAt { get; init; }

    /// <summary>Solo chart decoded from <see cref="InstrumentCode"/> (Lead when the code is invalid; validate first).</summary>
    [JsonIgnore] public Instrument Instrument => PlayerInstrumentCode.TryParse(InstrumentCode, out var i) ? i : Instrument.Lead;

    /// <summary>Accuracy in ten-thousandths of a percent (0–1,000,000), the leaderboard scale.</summary>
    [JsonIgnore] public double? Accuracy => RawAccuracy * 1_000;

    /// <summary>Fallback valid accuracy on the leaderboard scale.</summary>
    [JsonIgnore] public double? ValidAccuracy => RawValidAccuracy * 1_000;

    /// <summary>Percentile, or <see langword="null"/> for the <c>-1</c> sentinel.</summary>
    [JsonIgnore] public double? Percentile => RawPercentile == -1 ? null : RawPercentile;

    /// <summary>Whether identity, code and every metric are in range.</summary>
    [JsonIgnore]
    public bool IsValid =>
        SongId is { Length: > 0 and <= 200 } && !ProfileText.ContainsUnsafeCharacter(SongId) &&
        PlayerInstrumentCode.TryParse(InstrumentCode, out _) && Score >= 0 &&
        Rank is null or >= 0 && TotalEntries is null or >= 0 && Stars is null or (>= 0 and <= 6) && Season is null or >= 0 &&
        ValidScore is null or >= 0 && InRange(Accuracy) && InRange(ValidAccuracy) &&
        (Difficulty is null || (double.IsFinite(Difficulty.Value) && Difficulty >= 0)) &&
        (MinLeeway is null || double.IsFinite(MinLeeway.Value)) &&
        (Percentile is null || (double.IsFinite(Percentile.Value) && Percentile is >= 0 and <= 100)) &&
        (ValidScores ?? []).All(v => v is not null && v.IsValid);

    /// <summary>Whether an expanded accuracy is absent or finite within 0–1,000,000.</summary>
    /// <param name="accuracy">Expanded accuracy.</param>
    /// <returns><see langword="true"/> when acceptable.</returns>
    internal static bool InRange(double? accuracy) =>
        accuracy is null || (double.IsFinite(accuracy.Value) && accuracy is >= 0 and <= 1_000_000);
}

/// <summary>The service's single-instrument hex bit codes (<c>FSTService/ComboIds.cs</c>).</summary>
public static class PlayerInstrumentCode
{
    /// <summary>Decodes exactly one of the nine solo bits in source order (bit 0 = Lead … bit 8 = Pro Drums).</summary>
    /// <param name="hex">Canonical lower-case two- or three-digit hex, e.g. <c>01</c>, <c>100</c>.</param>
    /// <param name="instrument">Decoded chart.</param>
    /// <returns><see langword="false"/> for a composite, unknown or non-canonical code.</returns>
    public static bool TryParse(string? hex, out Instrument instrument)
    {
        instrument = default;
        if (hex is not { Length: 2 or 3 } ||
            !int.TryParse(hex, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var mask) ||
            mask <= 0 || int.PopCount(mask) != 1 || int.TrailingZeroCount(mask) >= InstrumentInfo.All.Count ||
            hex != mask.ToString("x2", CultureInfo.InvariantCulture))
            return false;
        instrument = InstrumentInfo.All[int.TrailingZeroCount(mask)];
        return true;
    }

    /// <summary>Encodes a chart as its canonical hex code.</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns>Code such as <c>01</c>.</returns>
    public static string Encode(Instrument instrument) => (1 << (int)instrument).ToString("x2", CultureInfo.InvariantCulture);
}
#endregion

#region Profile envelope
/// <summary>HTTP 200 public scores (not proof of registration) or an explicit 202 syncing envelope.</summary>
public enum PlayerProfileState
{
    /// <summary>Public scores are available (possibly empty).</summary>
    Available,
    /// <summary>Registered but not yet published (HTTP 202 <c>status: syncing</c>).</summary>
    Syncing,
}

/// <summary>Compact public profile from <c>GET /api/player/{accountId}</c>; never a tracked identity.</summary>
public sealed record PlayerProfileResponse
{
    /// <summary>Largest accepted body.</summary>
    public const int WireByteLimit = 16_000_000;

    /// <summary>Account.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Server display name, trimmed; empty or whitespace becomes <see langword="null"/>.</summary>
    [JsonPropertyName("displayName")] public string? DisplayName { get; init; }
    /// <summary>Declared score count.</summary>
    [JsonPropertyName("totalScores")] public int TotalScores { get; init; }
    /// <summary>Compact score rows.</summary>
    [JsonPropertyName("scores")] public IReadOnlyList<PlayerScore> Scores { get; init; } = [];
    /// <summary><c>syncing</c> on a 202 envelope.</summary>
    [JsonPropertyName("status")] public string? Status { get; init; }
    /// <summary><see langword="true"/> on a 202 envelope.</summary>
    [JsonPropertyName("notYetPublished")] public bool? NotYetPublished { get; init; }

    /// <summary>Validates identity, cardinality and every row, and reports syncing vs available.</summary>
    /// <param name="requestedAccountId">Account that was requested.</param>
    /// <returns>The profile state.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/> for corrupt or mixed-identity data.</exception>
    public PlayerProfileState Validate(string requestedAccountId)
    {
        var name = DisplayName;
        if (!ProfileText.IsValidAccountId(requestedAccountId) || !ProfileText.IsValidAccountId(AccountId) ||
            !string.Equals(AccountId, requestedAccountId, StringComparison.OrdinalIgnoreCase) || Scores is null ||
            TotalScores is < 0 or > 20_000 || TotalScores != Scores.Count ||
            (name is not null && (name.Length is 0 or > 200 || name != name.Trim() || ProfileText.ContainsUnsafeCharacter(name))))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        if (Status == "syncing")
        {
            if (NotYetPublished != true || Scores.Count != 0) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            return PlayerProfileState.Syncing;
        }
        if (Status is not null || NotYetPublished == true) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var seen = new HashSet<(string, Instrument)>();
        foreach (var row in Scores)
        {
            if (row is null || !row.IsValid || !seen.Add((row.SongId, row.Instrument)))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
        return PlayerProfileState.Available;
    }

    /// <summary>Returns a copy whose display name is trimmed (blank becomes <see langword="null"/>).</summary>
    /// <returns>Normalized response.</returns>
    internal PlayerProfileResponse Normalized()
    {
        if (DisplayName is { } raw && ProfileText.ContainsUnsafeCharacter(raw)) return this;
        var trimmed = DisplayName?.Trim();
        return this with { DisplayName = string.IsNullOrEmpty(trimmed) ? null : trimmed };
    }

    /// <summary>One lookup per profile: song ID → chart → row (build once, not per visible row).</summary>
    /// <returns>Index over the validated rows.</returns>
    public IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>> ScoreIndex()
    {
        var index = new Dictionary<string, Dictionary<Instrument, PlayerScore>>(StringComparer.Ordinal);
        foreach (var row in Scores)
        {
            if (!index.TryGetValue(row.SongId, out var charts)) index[row.SongId] = charts = [];
            charts[row.Instrument] = row;
        }
        return index.ToDictionary(p => p.Key, p => (IReadOnlyDictionary<Instrument, PlayerScore>)p.Value, StringComparer.Ordinal);
    }
}

/// <summary>A validated profile read with its publication provenance.</summary>
/// <param name="Profile">Validated response.</param>
/// <param name="State">Available or syncing.</param>
/// <param name="PublicationId">Header-verified publication, or <see langword="null"/> when headerless (preview only).</param>
/// <param name="ObservedPublicationId">Generation the client observed for this read.</param>
public sealed record PlayerProfilePayload(PlayerProfileResponse Profile, PlayerProfileState State, long? PublicationId, long ObservedPublicationId)
{
    /// <summary>Whether this read may back an explicit Select (header-verified against the current generation).</summary>
    /// <param name="currentPublicationId">Client's current publication.</param>
    /// <returns><see langword="true"/> when selectable.</returns>
    public bool IsSelectable(long? currentPublicationId) =>
        State == PlayerProfileState.Available && PublicationId is { } id && id == currentPublicationId;
}
#endregion

#region Client-side statistics
/// <summary>
/// Player-page overview computed only from the compact scores, mirroring the web's <c>computeOverallStats</c>
/// (<c>pages/player/helpers/playerStats.ts</c>) without the side-effecting player-stats GET.
/// </summary>
/// <param name="SongsPlayed">Unique songs across visible charts (per chart for instrument stats).</param>
/// <param name="FullComboCount">Rows with an explicit full combo.</param>
/// <param name="FullComboPercent">FC share, floored to one decimal.</param>
/// <param name="GoldStarCount">Rows with 6 stars.</param>
/// <param name="FiveStarCount">Rows with exactly 5 stars.</param>
/// <param name="AverageAccuracy">Mean positive expanded accuracy.</param>
/// <param name="BestRank">Best positive rank.</param>
/// <param name="BestRankSongId">Song holding the best rank.</param>
/// <param name="BestRankInstrument">Chart holding the best rank.</param>
/// <param name="AverageStars">Mean stars over rows with at least one star (web <c>averageStars</c>), 0 when none.</param>
public sealed record PlayerStats(
    int SongsPlayed, int FullComboCount, double FullComboPercent, int GoldStarCount, int FiveStarCount,
    double? AverageAccuracy, int? BestRank, string? BestRankSongId, Instrument? BestRankInstrument, double AverageStars = 0)
{
    /// <summary>Whether every starred score is six stars: the web draws gold stars instead of the number.</summary>
    public bool AverageStarsGold => AverageStars == StarRating.GoldValue;

    /// <summary>Web <c>formatClamped2</c>: up to two decimals without trailing zeros ("5.5", "4.83"), or an em dash.</summary>
    public string AverageStarsText => AverageStarsGold
        ? StarRating.From(StarRating.GoldValue)!.Value.Announcement
        : AverageStars > 0 ? Math.Round(AverageStars, 2).ToString("0.##", CultureInfo.CurrentCulture) : "—";

    /// <summary>"12 (40.5%)" or "0".</summary>
    public string FullComboText => FullComboCount == 0
        ? "0"
        : $"{FullComboCount.ToString("N0", CultureInfo.CurrentCulture)} ({PercentText(FullComboPercent)}%)";

    /// <summary>Accuracy text or an em dash.</summary>
    public string AverageAccuracyText => AverageAccuracy is { } a ? ScoreFormatting.Accuracy(a) : "—";

    /// <summary>"#12" or an em dash.</summary>
    public string BestRankText => BestRank is { } r ? ScoreFormatting.Rank(r) : "—";

    /// <summary>One decimal only when needed.</summary>
    /// <param name="value">Percent.</param>
    /// <returns>Text.</returns>
    internal static string PercentText(double value) =>
        value.ToString(value == Math.Round(value) ? "0" : "0.0", CultureInfo.CurrentCulture);
}

/// <summary>One "Top N%" placement band for the percentile chart (web <c>PlayerPercentileTable</c>).</summary>
/// <param name="TopPercent">Band upper bound.</param>
/// <param name="Count">Songs in <c>(previous, TopPercent]</c>.</param>
public sealed record PlayerPercentileBucket(int TopPercent, int Count)
{
    /// <summary>"Top 5%".</summary>
    public string Label => $"Top {TopPercent.ToString(CultureInfo.CurrentCulture)}%";

    /// <summary>Whether the band is a top-5% (gold) band.</summary>
    public bool IsTopFive => TopPercent <= 5;
}

/// <summary>Aggregation over the compact scores.</summary>
public static class PlayerStatistics
{
    /// <summary>Band upper bounds, matching the web's <c>pctThresholds</c> (<c>playerStats.ts:69</c>).</summary>
    public static IReadOnlyList<int> PercentileThresholds { get; } = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100];

    /// <summary>Overview across Settings-visible charts; songs are counted once across charts.</summary>
    /// <param name="profile">Validated profile.</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns>Zeroed totals when nothing is visible.</returns>
    public static PlayerStats Overall(PlayerProfileResponse profile, IEnumerable<Instrument> visible)
    {
        var set = visible.ToHashSet();
        var rows = profile.Scores.Where(s => set.Contains(s.Instrument)).ToList();
        return Aggregate(rows, rows.Select(r => r.SongId).Distinct(StringComparer.Ordinal).Count());
    }

    /// <summary>One chart's summary.</summary>
    /// <param name="profile">Validated profile.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Zeroed totals when the chart has no scores.</returns>
    public static PlayerStats ForInstrument(PlayerProfileResponse profile, Instrument instrument)
    {
        var rows = profile.Scores.Where(s => s.Instrument == instrument).ToList();
        return Aggregate(rows, rows.Count);
    }

    /// <summary>Per-star-level score counts for one chart (web <c>goldStarCount</c> ... <c>oneStarCount</c>), gold first.</summary>
    /// <param name="profile">Validated profile.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>(stars, count) for 6 down to 1; six means six or more.</returns>
    public static List<(int Stars, int Count)> StarCounts(PlayerProfileResponse profile, Instrument instrument)
    {
        var stars = profile.Scores.Where(s => s.Instrument == instrument).Select(s => s.Stars ?? 0).ToList();
        return [.. Enumerable.Range(1, 6).Reverse().Select(level => (level, stars.Count(s => level == 6 ? s >= 6 : s == level)))];
    }

    /// <summary>Placement distribution: each ranked row contributes <c>rank / totalEntries</c> to its first band.</summary>
    /// <param name="profile">Validated profile.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Non-empty bands, best first.</returns>
    public static List<PlayerPercentileBucket> PercentileBuckets(PlayerProfileResponse profile, Instrument instrument)
    {
        var fractions = profile.Scores
            .Where(s => s.Instrument == instrument && s.Rank is > 0 && s.TotalEntries is > 0)
            .Select(s => (double)s.Rank!.Value / s.TotalEntries!.Value * 100)
            .ToList();
        var buckets = new List<PlayerPercentileBucket>();
        var previous = 0;
        foreach (var threshold in PercentileThresholds)
        {
            var count = fractions.Count(f => f > previous && f <= threshold);
            if (count > 0) buckets.Add(new PlayerPercentileBucket(threshold, count));
            previous = threshold;
        }
        return buckets;
    }

    /// <summary>Shared arithmetic.</summary>
    /// <param name="rows">Contributing rows.</param>
    /// <param name="songsPlayed">Songs-played count for this aggregate.</param>
    /// <returns>Stats.</returns>
    private static PlayerStats Aggregate(List<PlayerScore> rows, int songsPlayed)
    {
        var fc = rows.Count(r => r.IsFullCombo == true);
        var fcPercent = rows.Count == 0 ? 0 : Math.Floor((double)fc / rows.Count * 1_000) / 10;
        var accuracies = rows.Select(r => r.Accuracy).OfType<double>().Where(a => a > 0).ToList();
        var ranked = rows.Where(r => r.Rank is > 0).ToList();
        var best = ranked.Count == 0 ? null : ranked.MinBy(r => r.Rank!.Value);
        var starred = rows.Where(r => r.Stars is > 0).Select(r => (double)r.Stars!.Value).ToList();
        return new PlayerStats(
            songsPlayed, fc, fcPercent,
            rows.Count(r => r.Stars >= 6), rows.Count(r => r.Stars == 5),
            accuracies.Count == 0 ? null : accuracies.Average(),
            best?.Rank, best?.SongId, best?.Instrument,
            starred.Count == 0 ? 0 : starred.Average());
    }
}
#endregion
