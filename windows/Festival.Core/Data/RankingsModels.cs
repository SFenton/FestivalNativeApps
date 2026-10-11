using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Account rankings
/// <summary>
/// One row of <c>GET /api/rankings/{instrument}</c> (web <c>AccountRankingEntry</c>,
/// <c>packages/core/src/api/serverTypes.ts:1116</c>). Not sealed: the single-account read
/// (<c>/api/rankings/{instrument}/{accountId}</c>) shares every field.
/// </summary>
public record AccountRankingEntry
{
    /// <summary>Public account key.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Display name, when known.</summary>
    [JsonPropertyName("displayName")] public string? DisplayName { get; init; }
    /// <summary>Songs with a score.</summary>
    [JsonPropertyName("songsPlayed")] public int SongsPlayed { get; init; }
    /// <summary>Charted songs on this instrument.</summary>
    [JsonPropertyName("totalChartedSongs")] public int TotalChartedSongs { get; init; }
    /// <summary>Played fraction.</summary>
    [JsonPropertyName("coverage")] public double Coverage { get; init; }
    /// <summary>Raw adjusted-skill percentile (0 best).</summary>
    [JsonPropertyName("rawSkillRating")] public double RawSkillRating { get; init; }
    /// <summary>Bayesian-adjusted skill rating.</summary>
    [JsonPropertyName("adjustedSkillRating")] public double AdjustedSkillRating { get; init; }
    /// <summary>Rank by adjusted skill.</summary>
    [JsonPropertyName("adjustedSkillRank")] public int AdjustedSkillRank { get; init; }
    /// <summary>Weighted rating.</summary>
    [JsonPropertyName("weightedRating")] public double WeightedRating { get; init; }
    /// <summary>Rank by weighted rating.</summary>
    [JsonPropertyName("weightedRank")] public int WeightedRank { get; init; }
    /// <summary>Full-combo rate.</summary>
    [JsonPropertyName("fcRate")] public double FcRate { get; init; }
    /// <summary>Rank by FC rate.</summary>
    [JsonPropertyName("fcRateRank")] public int FcRateRank { get; init; }
    /// <summary>Summed score.</summary>
    [JsonPropertyName("totalScore")] public long TotalScore { get; init; }
    /// <summary>Rank by total score.</summary>
    [JsonPropertyName("totalScoreRank")] public int TotalScoreRank { get; init; }
    /// <summary>Fraction of engine maximum.</summary>
    [JsonPropertyName("maxScorePercent")] public double MaxScorePercent { get; init; }
    /// <summary>Rank by max-score percent.</summary>
    [JsonPropertyName("maxScorePercentRank")] public int MaxScorePercentRank { get; init; }
    /// <summary>Average accuracy.</summary>
    [JsonPropertyName("avgAccuracy")] public double AvgAccuracy { get; init; }
    /// <summary>Full combos.</summary>
    [JsonPropertyName("fullComboCount")] public int FullComboCount { get; init; }
    /// <summary>Average stars.</summary>
    [JsonPropertyName("avgStars")] public double AvgStars { get; init; }
    /// <summary>Best per-song rank.</summary>
    [JsonPropertyName("bestRank")] public int BestRank { get; init; }
    /// <summary>Average per-song rank.</summary>
    [JsonPropertyName("avgRank")] public double AvgRank { get; init; }
    /// <summary>Unadjusted max-score percent, when sent.</summary>
    [JsonPropertyName("rawMaxScorePercent")] public double? RawMaxScorePercent { get; init; }
    /// <summary>Unadjusted weighted rating, when sent.</summary>
    [JsonPropertyName("rawWeightedRating")] public double? RawWeightedRating { get; init; }

    /// <summary>Display name, or the web's "Unknown User" placeholder.</summary>
    [JsonIgnore] public string Name => string.IsNullOrWhiteSpace(DisplayName) ? "Unknown User" : DisplayName!;

    /// <summary>Whether the row's account ID is safe to open as a profile (empty or unsafe IDs are shown without a link).</summary>
    [JsonIgnore] public bool HasProfile => ProfileText.IsValidAccountId(AccountId);

    /// <summary>Rank column for a metric.</summary>
    /// <param name="metric">Selected metric.</param>
    /// <returns>One-based rank for that metric.</returns>
    public virtual int Rank(RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => AdjustedSkillRank,
        RankingMetric.Weighted => WeightedRank,
        RankingMetric.FcRate => FcRateRank,
        RankingMetric.TotalScore => TotalScoreRank,
        _ => MaxScorePercentRank,
    };

    /// <summary>Raw value behind the displayed rating, like the web's <c>getRatingForMetric</c>.</summary>
    /// <param name="metric">Selected metric.</param>
    /// <returns>Percentile fraction, score total or fraction.</returns>
    public virtual double RatingValue(RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => RawSkillRating,
        RankingMetric.Weighted => RawWeightedRating ?? WeightedRating,
        RankingMetric.FcRate => TotalChartedSongs > 0 ? (double)FullComboCount / TotalChartedSongs : 0,
        RankingMetric.TotalScore => TotalScore,
        _ => MaxScorePercent,
    };

    /// <summary>Bayesian value shown beside a "Top N%" rating (percentile metrics only).</summary>
    /// <param name="metric">Selected metric.</param>
    /// <returns>Adjusted/weighted rating, else <see langword="null"/>.</returns>
    public virtual double? BayesianValue(RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => AdjustedSkillRating,
        RankingMetric.Weighted => WeightedRating,
        _ => null,
    };

    /// <summary>Songs subtitle; counts full combos under FC Rate (web <c>getSongsLabel</c>).</summary>
    /// <param name="metric">Selected metric.</param>
    /// <returns>Text such as "40 / 50 ".</returns>
    public virtual string SongsLabel(RankingMetric metric) =>
        RankingFormatting.Songs(metric == RankingMetric.FcRate ? FullComboCount : SongsPlayed, TotalChartedSongs);
}

/// <summary>Envelope of <c>GET /api/rankings/{instrument}?rankBy=&amp;page=&amp;pageSize=</c>.</summary>
public sealed record RankingsResponse
{
    /// <summary>Requested service instrument ID.</summary>
    [JsonPropertyName("instrument")] public string Instrument { get; init; } = "";
    /// <summary>Requested metric.</summary>
    [JsonPropertyName("rankBy")] public string RankBy { get; init; } = "";
    /// <summary>One-based page.</summary>
    [JsonPropertyName("page")] public int Page { get; init; }
    /// <summary>Rows per page.</summary>
    [JsonPropertyName("pageSize")] public int PageSize { get; init; }
    /// <summary>Ranked population.</summary>
    [JsonPropertyName("totalAccounts")] public int TotalAccounts { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("entries")] public List<AccountRankingEntry> Entries { get; init; } = [];

    /// <summary>Pages of <see cref="PageSize"/> rows, at least one.</summary>
    [JsonIgnore] public int PageCount => LeaderboardPaging.PageCount(TotalAccounts, PageSize);

    /// <summary>
    /// Rejects a response for another chart or with an impossible row count. Rows are not rejected for their account
    /// ID: production serves rows with an empty <c>accountId</c> and no name (seen 2026-09-28, Lead rank 15), which are
    /// shown as "Unknown User" without a profile link (<see cref="AccountRankingEntry.HasProfile"/>).
    /// </summary>
    /// <param name="instrument">Requested chart.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(Instrument instrument)
    {
        if (Instrument != instrument.ServiceId() || Page < 1 || PageSize < 1 || TotalAccounts < 0 || Entries is null ||
            Entries.Count > PageSize || Entries.Any(e => e is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion

#region Combo rankings
/// <summary>
/// One row of <c>GET /api/rankings/combo?combo=</c> (web <c>ComboRankingEntry</c>): one rank for the requested metric and
/// combo-wide ratings, displayed like the web's combo <c>FullRankingsPage</c> (<c>getDisplayRank</c>,
/// <c>getDisplayRating</c>, <c>getDisplayBayesianRating</c>, <c>getDisplaySongsLabel</c>).
/// </summary>
public sealed record ComboRankingEntry : AccountRankingEntry
{
    /// <summary>One-based rank for the requested metric.</summary>
    [JsonPropertyName("rank")] public int ComboRank { get; init; }
    /// <summary>Bayesian-adjusted combo rating.</summary>
    [JsonPropertyName("adjustedRating")] public double AdjustedRating { get; init; }

    /// <summary>The combo rank (the board is already sorted by the requested metric).</summary>
    /// <param name="metric">Requested metric (unused).</param>
    /// <returns>One-based rank.</returns>
    public override int Rank(RankingMetric metric) => ComboRank;

    /// <summary>Raw value behind the displayed rating.</summary>
    /// <param name="metric">Requested metric.</param>
    /// <returns>Rating, FC rate, score total or max-score fraction.</returns>
    public override double RatingValue(RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => AdjustedRating,
        RankingMetric.Weighted => WeightedRating,
        RankingMetric.FcRate => FcRate,
        RankingMetric.TotalScore => TotalScore,
        _ => MaxScorePercent,
    };

    /// <summary>Bayesian value beside a percentile rating.</summary>
    /// <param name="metric">Requested metric.</param>
    /// <returns>Adjusted/weighted rating, else <see langword="null"/>.</returns>
    public override double? BayesianValue(RankingMetric metric) => metric switch
    {
        RankingMetric.Adjusted => AdjustedRating,
        RankingMetric.Weighted => WeightedRating,
        _ => null,
    };

    /// <summary>Full combos of played songs under FC Rate, else played of charted songs (played alone without a total).</summary>
    /// <param name="metric">Requested metric.</param>
    /// <returns>Text such as "40 / 50".</returns>
    public override string SongsLabel(RankingMetric metric) => metric == RankingMetric.FcRate
        ? RankingFormatting.Songs(FullComboCount, SongsPlayed)
        : TotalChartedSongs > 0
            ? RankingFormatting.Songs(SongsPlayed, TotalChartedSongs)
            : SongsPlayed.ToString("N0", System.Globalization.CultureInfo.CurrentCulture);
}

/// <summary>Envelope of <c>GET /api/rankings/combo?combo=&amp;rankBy=&amp;page=&amp;pageSize=</c> (pure read).</summary>
public sealed record ComboRankingsResponse
{
    /// <summary>Requested combo ID.</summary>
    [JsonPropertyName("comboId")] public string ComboId { get; init; } = "";
    /// <summary>Requested metric.</summary>
    [JsonPropertyName("rankBy")] public string RankBy { get; init; } = "";
    /// <summary>One-based page.</summary>
    [JsonPropertyName("page")] public int Page { get; init; }
    /// <summary>Rows per page.</summary>
    [JsonPropertyName("pageSize")] public int PageSize { get; init; }
    /// <summary>Ranked population.</summary>
    [JsonPropertyName("totalAccounts")] public int TotalAccounts { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("entries")] public List<ComboRankingEntry> Entries { get; init; } = [];

    /// <summary>
    /// Rejects a response for another combo, with an impossible row count or with a non-positive rank (rows with an empty
    /// account ID are kept and shown without a profile link, as on the instrument boards).
    /// </summary>
    /// <param name="comboId">Requested combo ID.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string comboId)
    {
        if (!string.Equals(ComboId, comboId, StringComparison.OrdinalIgnoreCase) || Page < 1 || PageSize < 1 || TotalAccounts < 0 ||
            Entries is null || Entries.Count > PageSize || Entries.Any(e => e is null || e.ComboRank < 1))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>The ranked-population-only board the service's 404 stands for (no combo rows yet).</summary>
    /// <param name="comboId">Requested combo ID.</param>
    /// <param name="metric">Requested metric.</param>
    /// <param name="page">Requested page.</param>
    /// <param name="pageSize">Requested size.</param>
    /// <returns>Empty board.</returns>
    public static ComboRankingsResponse Empty(string comboId, RankingMetric metric, int page, int pageSize) =>
        new() { ComboId = comboId, RankBy = metric.ServiceId(), Page = page, PageSize = pageSize };

    /// <summary>The page as an instrument-board envelope so the shared rows, pager and spotlight can show it.</summary>
    /// <returns>Board.</returns>
    public RankingsResponse ToBoard() => new()
    {
        Instrument = ComboId, RankBy = RankBy, Page = Page, PageSize = PageSize, TotalAccounts = TotalAccounts, Entries = [.. Entries],
    };
}

/// <summary><c>GET /api/rankings/combo/{accountId}?combo=&amp;rankBy=</c>: one account's combo row (404 when unranked).</summary>
public sealed record PlayerComboRanking
{
    /// <summary>Public account key.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Requested combo ID.</summary>
    [JsonPropertyName("comboId")] public string ComboId { get; init; } = "";
    /// <summary>Display name, when known.</summary>
    [JsonPropertyName("displayName")] public string? DisplayName { get; init; }
    /// <summary>One-based rank for the requested metric.</summary>
    [JsonPropertyName("rank")] public int Rank { get; init; }
    /// <summary>Bayesian-adjusted combo rating.</summary>
    [JsonPropertyName("adjustedRating")] public double AdjustedRating { get; init; }
    /// <summary>Weighted rating.</summary>
    [JsonPropertyName("weightedRating")] public double WeightedRating { get; init; }
    /// <summary>Full-combo rate.</summary>
    [JsonPropertyName("fcRate")] public double FcRate { get; init; }
    /// <summary>Summed score.</summary>
    [JsonPropertyName("totalScore")] public long TotalScore { get; init; }
    /// <summary>Fraction of engine maximum.</summary>
    [JsonPropertyName("maxScorePercent")] public double MaxScorePercent { get; init; }
    /// <summary>Songs with a score.</summary>
    [JsonPropertyName("songsPlayed")] public int SongsPlayed { get; init; }
    /// <summary>Charted songs across the combo.</summary>
    [JsonPropertyName("totalChartedSongs")] public int TotalChartedSongs { get; init; }
    /// <summary>Full combos.</summary>
    [JsonPropertyName("fullComboCount")] public int FullComboCount { get; init; }

    /// <summary>Rejects a row for another account or combo, or without a rank.</summary>
    /// <param name="comboId">Requested combo ID.</param>
    /// <param name="accountId">Requested account.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string comboId, string accountId)
    {
        if (!string.Equals(AccountId, accountId, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(ComboId, comboId, StringComparison.OrdinalIgnoreCase) || Rank < 1)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>The row as a board entry for the shared spotlight.</summary>
    /// <returns>Entry.</returns>
    public ComboRankingEntry ToEntry() => new()
    {
        AccountId = AccountId, DisplayName = DisplayName, ComboRank = Rank, AdjustedRating = AdjustedRating, WeightedRating = WeightedRating,
        FcRate = FcRate, TotalScore = TotalScore, MaxScorePercent = MaxScorePercent, SongsPlayed = SongsPlayed,
        TotalChartedSongs = TotalChartedSongs, FullComboCount = FullComboCount,
    };
}
#endregion

#region Band rankings
/// <summary>One member inside a <see cref="BandRankingEntry"/>.</summary>
/// <param name="AccountId">Public account key.</param>
/// <param name="DisplayName">Display name, when known.</param>
public sealed record BandTeamMember(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string? DisplayName);

/// <summary>One row of <c>GET /api/rankings/bands/{bandType}</c> (web <c>BandRankingEntry</c>, <c>serverTypes.ts:1147</c>).</summary>
public sealed record BandRankingEntry
{
    /// <summary>One-way band hash (never resolved through <c>/api/bands/{id}</c>, which writes).</summary>
    [JsonPropertyName("bandId")] public string BandId { get; init; } = "";
    /// <summary>Team key for the safe rankings read.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Members.</summary>
    [JsonPropertyName("teamMembers")] public List<BandTeamMember> TeamMembers { get; init; } = [];
    /// <summary>Songs with a score.</summary>
    [JsonPropertyName("songsPlayed")] public int SongsPlayed { get; init; }
    /// <summary>Charted songs.</summary>
    [JsonPropertyName("totalChartedSongs")] public int TotalChartedSongs { get; init; }
    /// <summary>Played fraction.</summary>
    [JsonPropertyName("coverage")] public double Coverage { get; init; }
    /// <summary>Raw adjusted-skill percentile.</summary>
    [JsonPropertyName("rawSkillRating")] public double RawSkillRating { get; init; }
    /// <summary>Bayesian-adjusted skill rating.</summary>
    [JsonPropertyName("adjustedSkillRating")] public double AdjustedSkillRating { get; init; }
    /// <summary>Rank by adjusted skill.</summary>
    [JsonPropertyName("adjustedSkillRank")] public int AdjustedSkillRank { get; init; }
    /// <summary>Weighted rating.</summary>
    [JsonPropertyName("weightedRating")] public double WeightedRating { get; init; }
    /// <summary>Rank by weighted rating.</summary>
    [JsonPropertyName("weightedRank")] public int WeightedRank { get; init; }
    /// <summary>Full-combo rate.</summary>
    [JsonPropertyName("fcRate")] public double FcRate { get; init; }
    /// <summary>Rank by FC rate.</summary>
    [JsonPropertyName("fcRateRank")] public int FcRateRank { get; init; }
    /// <summary>Summed score.</summary>
    [JsonPropertyName("totalScore")] public long TotalScore { get; init; }
    /// <summary>Rank by total score.</summary>
    [JsonPropertyName("totalScoreRank")] public int TotalScoreRank { get; init; }
    /// <summary>Average accuracy.</summary>
    [JsonPropertyName("avgAccuracy")] public double AvgAccuracy { get; init; }
    /// <summary>Full combos.</summary>
    [JsonPropertyName("fullComboCount")] public int FullComboCount { get; init; }
    /// <summary>Average stars.</summary>
    [JsonPropertyName("avgStars")] public double AvgStars { get; init; }
    /// <summary>Best per-song rank.</summary>
    [JsonPropertyName("bestRank")] public int BestRank { get; init; }
    /// <summary>Average per-song rank.</summary>
    [JsonPropertyName("avgRank")] public double AvgRank { get; init; }
    /// <summary>Unadjusted weighted rating, when sent.</summary>
    [JsonPropertyName("rawWeightedRating")] public double? RawWeightedRating { get; init; }

    /// <summary>Whether Band Detail can be opened (needs the band hash and team key; bad rows are shown without a link).</summary>
    [JsonIgnore]
    public bool HasDetail => !string.IsNullOrEmpty(BandId) && !string.IsNullOrEmpty(TeamKey) &&
                             !IsUnsafeValue(BandId) && !IsUnsafeValue(TeamKey);

    /// <summary>Whether a value would be unsafe as a route segment or query value.</summary>
    /// <param name="value">Candidate.</param>
    /// <returns><see langword="true"/> when too long or containing control/bidi characters.</returns>
    private static bool IsUnsafeValue(string value) => value.Length > 400 || ProfileText.ContainsUnsafeCharacter(value);

    /// <summary>Roster joined like the web ("Unknown User" for a blank name).</summary>
    [JsonIgnore]
    public string MembersLabel => string.Join(", ",
        (TeamMembers ?? []).Select(m => string.IsNullOrWhiteSpace(m.DisplayName) ? "Unknown User" : m.DisplayName));

    /// <summary>Rank column for a metric.</summary>
    /// <param name="metric">Selected band metric.</param>
    /// <returns>One-based rank.</returns>
    public int Rank(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => AdjustedSkillRank,
        BandRankingMetric.Weighted => WeightedRank,
        BandRankingMetric.FcRate => FcRateRank,
        _ => TotalScoreRank,
    };

    /// <summary>Raw value behind the displayed rating.</summary>
    /// <param name="metric">Selected band metric.</param>
    /// <returns>Percentile fraction, score total or fraction.</returns>
    public double RatingValue(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => RawSkillRating,
        BandRankingMetric.Weighted => RawWeightedRating ?? WeightedRating,
        BandRankingMetric.FcRate => TotalChartedSongs > 0 ? (double)FullComboCount / TotalChartedSongs : 0,
        _ => TotalScore,
    };

    /// <summary>Bayesian value beside a percentile rating.</summary>
    /// <param name="metric">Selected band metric.</param>
    /// <returns>Adjusted/weighted rating, else <see langword="null"/>.</returns>
    public double? BayesianValue(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => AdjustedSkillRating,
        BandRankingMetric.Weighted => WeightedRating,
        _ => null,
    };

    /// <summary>Songs subtitle; counts full combos under FC Rate.</summary>
    /// <param name="metric">Selected band metric.</param>
    /// <returns>Text such as "30 / 50 ".</returns>
    public string SongsLabel(BandRankingMetric metric) =>
        RankingFormatting.Songs(metric == BandRankingMetric.FcRate ? FullComboCount : SongsPlayed, TotalChartedSongs);
}

/// <summary>Envelope of <c>GET /api/rankings/bands/{bandType}?rankBy=&amp;page=&amp;pageSize=</c>.</summary>
public sealed record BandRankingsResponse
{
    /// <summary>Requested band type.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Requested metric.</summary>
    [JsonPropertyName("rankBy")] public string RankBy { get; init; } = "";
    /// <summary>One-based page.</summary>
    [JsonPropertyName("page")] public int Page { get; init; }
    /// <summary>Rows per page.</summary>
    [JsonPropertyName("pageSize")] public int PageSize { get; init; }
    /// <summary>Ranked teams.</summary>
    [JsonPropertyName("totalTeams")] public int TotalTeams { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("entries")] public List<BandRankingEntry> Entries { get; init; } = [];

    /// <summary>Pages of <see cref="PageSize"/> rows, at least one.</summary>
    [JsonIgnore] public int PageCount => LeaderboardPaging.PageCount(TotalTeams, PageSize);

    /// <summary>Rejects a response for another band type or with an impossible row count.</summary>
    /// <param name="bandType">Requested band type.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(BandType bandType)
    {
        if (BandType != bandType.ServiceId() || Page < 1 || PageSize < 1 || TotalTeams < 0 || Entries is null ||
            Entries.Count > PageSize || Entries.Any(e => e is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion
