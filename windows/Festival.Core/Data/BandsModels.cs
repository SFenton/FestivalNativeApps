using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Player band group
/// <summary>The player-bands <c>?group=</c> filter (web <c>PlayerBandListGroup</c>), distinct from <see cref="BandType"/>.</summary>
public enum PlayerBandGroup
{
    /// <summary>Every lineup (<c>all</c>).</summary>
    All,
    /// <summary>Two-player lineups (<c>duos</c>).</summary>
    Duos,
    /// <summary>Three-player lineups (<c>trios</c>).</summary>
    Trios,
    /// <summary>Four-player lineups (<c>quads</c>).</summary>
    Quads,
}

/// <summary>Query values and labels for <see cref="PlayerBandGroup"/>.</summary>
public static class PlayerBandGroupInfo
{
    /// <summary>All groups in the web filter's order.</summary>
    public static IReadOnlyList<PlayerBandGroup> All { get; } = Enum.GetValues<PlayerBandGroup>();

    /// <summary>Returns the <c>group</c> query value.</summary>
    /// <param name="group">Group.</param>
    /// <returns><c>all</c>, <c>duos</c>, <c>trios</c> or <c>quads</c>.</returns>
    public static string ServiceId(this PlayerBandGroup group) => group.ToString().ToLowerInvariant();

    /// <summary>Returns the web filter label (<c>bandList.groups.*</c>).</summary>
    /// <param name="group">Group.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this PlayerBandGroup group) => group == PlayerBandGroup.All ? "All Bands" : group.ToString();
}
#endregion

#region Members
/// <summary>
/// One band member as embedded in player-bands, band-ranking and song-band-leaderboard rows. Per-song stats are
/// only present on song-band-leaderboard members.
/// </summary>
public sealed record BandMember
{
    /// <summary>Public account key.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Display name, when known.</summary>
    [JsonPropertyName("displayName")] public string? DisplayName { get; init; }
    /// <summary>Observed service instrument IDs (may repeat or include unknown charts).</summary>
    [JsonPropertyName("instruments")] public IReadOnlyList<string>? Instruments { get; init; }
    /// <summary>Per-song score (song band leaderboard only).</summary>
    [JsonPropertyName("score")] public long? Score { get; init; }
    /// <summary>Per-song accuracy in ten-thousandths of a percent.</summary>
    [JsonPropertyName("accuracy")] public double? Accuracy { get; init; }
    /// <summary>Per-song full-combo flag.</summary>
    [JsonPropertyName("isFullCombo")] public bool? IsFullCombo { get; init; }
    /// <summary>Per-song stars.</summary>
    [JsonPropertyName("stars")] public int? Stars { get; init; }
    /// <summary>Per-song difficulty index.</summary>
    [JsonPropertyName("difficulty")] public int? Difficulty { get; init; }
    /// <summary>Per-song season.</summary>
    [JsonPropertyName("season")] public int? Season { get; init; }

    /// <summary>Readable name with the web's <c>common.unknownUser</c> fallback.</summary>
    [JsonIgnore] public string ResolvedName => string.IsNullOrWhiteSpace(DisplayName) ? "Unknown User" : DisplayName.Trim();

    /// <summary>Distinct charts this app can render, in first-seen order.</summary>
    [JsonIgnore]
    public IReadOnlyList<Instrument> ChartedInstruments =>
        (Instruments ?? []).Select(id => InstrumentInfo.TryParse(id, out var i) ? (Instrument?)i : null)
            .OfType<Instrument>().Distinct().ToArray();

    /// <summary>Joins distinct members' names with <c> + </c> (web <c>formatPlayerBandNames</c>).</summary>
    /// <param name="members">Members, possibly repeated.</param>
    /// <returns>Label such as <c>A + B</c>, or <c>Band</c> when empty.</returns>
    public static string JoinNames(IEnumerable<BandMember>? members)
    {
        var names = (members ?? []).DistinctBy(m => m.AccountId, StringComparer.Ordinal).Select(m => m.ResolvedName).ToArray();
        return names.Length == 0 ? "Band" : string.Join(" + ", names);
    }

    /// <summary>Whether the account ID is safe for a player route.</summary>
    [JsonIgnore] public bool HasValidAccount => ProfileText.IsValidAccountId(AccountId);
}
#endregion

#region Player bands
/// <summary>One of a player's deduplicated bands (<c>PlayerBandEntryDto</c>).</summary>
public sealed record PlayerBandEntry
{
    /// <summary>One-way band hash.</summary>
    [JsonPropertyName("bandId")] public string BandId { get; init; } = "";
    /// <summary>Member-account roster key.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Band size service ID.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Songs played together.</summary>
    [JsonPropertyName("appearanceCount")] public int AppearanceCount { get; init; }
    /// <summary>Members with observed instruments.</summary>
    [JsonPropertyName("members")] public IReadOnlyList<BandMember> Members { get; init; } = [];

    /// <summary>Joined member names.</summary>
    [JsonIgnore] public string MembersLabel => BandMember.JoinNames(Members);

    /// <summary>Stable row key (band ID, or team key when absent).</summary>
    [JsonIgnore] public string Key => BandId.Length > 0 ? BandId : TeamKey;
}

/// <summary>Page from <c>GET /api/player/{accountId}/bands</c> (<c>PlayerBandListResponseDto</c>).</summary>
public sealed record PlayerBandListResponse
{
    /// <summary>Requested account.</summary>
    [JsonPropertyName("accountId")] public string AccountId { get; init; } = "";
    /// <summary>Echoed group.</summary>
    [JsonPropertyName("group")] public string? Group { get; init; }
    /// <summary>Bands across all pages.</summary>
    [JsonPropertyName("totalCount")] public int TotalCount { get; init; }
    /// <summary>This page's bands.</summary>
    [JsonPropertyName("entries")] public IReadOnlyList<PlayerBandEntry> Entries { get; init; } = [];

    /// <summary>Pages of <paramref name="pageSize"/> rows, at least one.</summary>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Page count.</returns>
    public int PageCount(int pageSize) => TotalCount <= 0 ? 1 : (TotalCount - 1) / Math.Max(1, pageSize) + 1;

    /// <summary>Rejects a response for another account or with impossible counts.</summary>
    /// <param name="accountId">Requested account.</param>
    /// <param name="pageSize">Requested page size.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string accountId, int pageSize)
    {
        if (AccountId != accountId || Entries is null || TotalCount < 0 || Entries.Count > pageSize ||
            Entries.Any(e => e is null || e.TeamKey.Length == 0 || e.Members is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion

#region Band search
/// <summary>
/// Page from <c>GET /api/bands/search?q=&amp;page=1&amp;pageSize=</c> (<c>BandSearchResponseDto</c>; read-only since the
/// #320 service fix). Rows carry the same shape as a player's band rows, so the canonical band card renders them.
/// </summary>
public sealed record BandSearchResponse
{
    /// <summary>Echoed page.</summary>
    [JsonPropertyName("page")] public int Page { get; init; }
    /// <summary>Echoed page size.</summary>
    [JsonPropertyName("pageSize")] public int PageSize { get; init; }
    /// <summary>Matches across all pages.</summary>
    [JsonPropertyName("totalCount")] public int TotalCount { get; init; }
    /// <summary>This page's bands, best match first.</summary>
    [JsonPropertyName("results")] public IReadOnlyList<PlayerBandEntry> Results { get; init; } = [];

    /// <summary>
    /// Rejects the whole page when any row is unusable (spec "Band scope": a malformed page fails instead of
    /// silently dropping rows): an unknown band type, an unsafe band ID or team key, no members, an invalid member
    /// account, an unsafe member name, a duplicate band, a negative count or more rows than requested.
    /// </summary>
    /// <param name="pageSize">Requested page size.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(int pageSize)
    {
        if (Results is null || TotalCount < 0 || Results.Count > pageSize)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var band in Results)
        {
            if (band is null || !BandTypeInfo.TryParse(band.BandType, out _) || !BandEndpoints.IsValidTeamKey(band.TeamKey) ||
                band.BandId.Length > 200 || band.BandId.Contains('/') || band.BandId.Contains('\\') ||
                ProfileText.ContainsUnsafeCharacter(band.BandId) || band.AppearanceCount < 0 ||
                band.Members is not { Count: > 0 } || !seen.Add(band.Key))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            foreach (var member in band.Members)
            {
                if (member is null || !member.HasValidAccount ||
                    member.DisplayName is { } name && (name.Length > 200 || ProfileText.ContainsUnsafeCharacter(name)))
                    throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            }
        }
    }
}
#endregion

#region Band detail
/// <summary>One observed instrument-combo configuration (<c>BandConfigurationDto</c>); Duos with a combo only.</summary>
public sealed record BandConfiguration
{
    /// <summary>Raw combo text.</summary>
    [JsonPropertyName("rawInstrumentCombo")] public string? RawInstrumentCombo { get; init; }
    /// <summary>Normalized combo ID.</summary>
    [JsonPropertyName("comboId")] public string? ComboId { get; init; }
    /// <summary>Instruments in the combo.</summary>
    [JsonPropertyName("instruments")] public IReadOnlyList<string>? Instruments { get; init; }
    /// <summary>Assignment key.</summary>
    [JsonPropertyName("assignmentKey")] public string? AssignmentKey { get; init; }
    /// <summary>Times observed.</summary>
    [JsonPropertyName("appearanceCount")] public int AppearanceCount { get; init; }
}

/// <summary>
/// A band's ranking row: the <c>selectedBandEntry</c> of <c>GET /api/rankings/bands/{bandType}?teamKey=</c>. Band
/// Detail never reads <c>/api/bands/{bandId}</c> or <c>/api/rankings/bands/{bandType}/{teamKey}</c>: both call
/// <c>GetBandConfigurations</c>, which rebuilds <c>band_team_configurations</c> on a cache miss (a write from a GET).
/// </summary>
public sealed record BandDetail
{
    /// <summary>One-way band hash.</summary>
    [JsonPropertyName("bandId")] public string BandId { get; init; } = "";
    /// <summary>Combo filter applied, if any.</summary>
    [JsonPropertyName("comboId")] public string? ComboId { get; init; }
    /// <summary>Member-account roster key.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Members with observed instruments.</summary>
    [JsonPropertyName("members")] public IReadOnlyList<BandMember> Members { get; init; } = [];
    /// <summary>Roster names (fallback when <see cref="Members"/> is empty).</summary>
    [JsonPropertyName("teamMembers")] public IReadOnlyList<BandMember>? TeamMembers { get; init; }
    /// <summary>Observed configurations.</summary>
    [JsonPropertyName("configurations")] public IReadOnlyList<BandConfiguration>? Configurations { get; init; }
    /// <summary>Songs with a band score.</summary>
    [JsonPropertyName("songsPlayed")] public int SongsPlayed { get; init; }
    /// <summary>Charted songs.</summary>
    [JsonPropertyName("totalChartedSongs")] public int TotalChartedSongs { get; init; }
    /// <summary>Played fraction.</summary>
    [JsonPropertyName("coverage")] public double Coverage { get; init; }
    /// <summary>Raw adjusted percentile.</summary>
    [JsonPropertyName("rawSkillRating")] public double RawSkillRating { get; init; }
    /// <summary>Bayesian adjusted percentile.</summary>
    [JsonPropertyName("adjustedSkillRating")] public double AdjustedSkillRating { get; init; }
    /// <summary>Adjusted rank.</summary>
    [JsonPropertyName("adjustedSkillRank")] public int AdjustedSkillRank { get; init; }
    /// <summary>Weighted percentile.</summary>
    [JsonPropertyName("weightedRating")] public double WeightedRating { get; init; }
    /// <summary>Weighted rank.</summary>
    [JsonPropertyName("weightedRank")] public int WeightedRank { get; init; }
    /// <summary>Full-combo fraction.</summary>
    [JsonPropertyName("fcRate")] public double FcRate { get; init; }
    /// <summary>FC-rate rank.</summary>
    [JsonPropertyName("fcRateRank")] public int FcRateRank { get; init; }
    /// <summary>Summed score.</summary>
    [JsonPropertyName("totalScore")] public long TotalScore { get; init; }
    /// <summary>Total-score rank.</summary>
    [JsonPropertyName("totalScoreRank")] public int TotalScoreRank { get; init; }
    /// <summary>Mean accuracy in ten-thousandths of a percent.</summary>
    [JsonPropertyName("avgAccuracy")] public double AvgAccuracy { get; init; }
    /// <summary>Full combos.</summary>
    [JsonPropertyName("fullComboCount")] public int FullComboCount { get; init; }
    /// <summary>Mean stars.</summary>
    [JsonPropertyName("avgStars")] public double AvgStars { get; init; }
    /// <summary>Best per-song rank.</summary>
    [JsonPropertyName("bestRank")] public int BestRank { get; init; }
    /// <summary>Mean per-song rank.</summary>
    [JsonPropertyName("avgRank")] public double AvgRank { get; init; }
    /// <summary>Raw weighted percentile, when computed.</summary>
    [JsonPropertyName("rawWeightedRating")] public double? RawWeightedRating { get; init; }
    /// <summary>Ranked teams in this board, when reported.</summary>
    [JsonPropertyName("totalRankedTeams")] public int? TotalRankedTeams { get; init; }
    /// <summary>Computation time.</summary>
    [JsonPropertyName("computedAt")] public string? ComputedAt { get; init; }

    /// <summary>Members to show: <see cref="Members"/>, or roster names without instruments.</summary>
    [JsonIgnore]
    public IReadOnlyList<BandMember> DisplayMembers =>
        Members is { Count: > 0 } ? Members : TeamMembers ?? [];

    /// <summary>Rank for a metric.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>One-based rank (0 when unranked).</returns>
    public int Rank(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => AdjustedSkillRank,
        BandRankingMetric.Weighted => WeightedRank,
        BandRankingMetric.FcRate => FcRateRank,
        _ => TotalScoreRank,
    };
}

/// <summary>Envelope of <c>GET /api/rankings/bands/{bandType}?teamKey=</c>; only the selected team matters here.</summary>
public sealed record BandProfileEnvelope
{
    /// <summary>Echoed band type.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>The team matching <c>teamKey</c>, or <see langword="null"/> when unranked.</summary>
    [JsonPropertyName("selectedBandEntry")] public BandDetail? SelectedBandEntry { get; init; }
}
#endregion

#region Rank history
/// <summary>One daily snapshot (<c>BandRankHistoryDto</c>).</summary>
public sealed record BandRankHistoryEntry
{
    /// <summary><c>yyyy-MM-dd</c>.</summary>
    [JsonPropertyName("snapshotDate")] public string SnapshotDate { get; init; } = "";
    /// <summary>Adjusted rank.</summary>
    [JsonPropertyName("adjustedSkillRank")] public int AdjustedSkillRank { get; init; }
    /// <summary>Weighted rank.</summary>
    [JsonPropertyName("weightedRank")] public int WeightedRank { get; init; }
    /// <summary>FC-rate rank.</summary>
    [JsonPropertyName("fcRateRank")] public int FcRateRank { get; init; }
    /// <summary>Total-score rank.</summary>
    [JsonPropertyName("totalScoreRank")] public int TotalScoreRank { get; init; }
    /// <summary>Adjusted percentile.</summary>
    [JsonPropertyName("adjustedSkillRating")] public double? AdjustedSkillRating { get; init; }
    /// <summary>Weighted percentile.</summary>
    [JsonPropertyName("weightedRating")] public double? WeightedRating { get; init; }
    /// <summary>FC fraction.</summary>
    [JsonPropertyName("fcRate")] public double? FcRate { get; init; }
    /// <summary>Summed score.</summary>
    [JsonPropertyName("totalScore")] public long? TotalScore { get; init; }
    /// <summary>Songs played.</summary>
    [JsonPropertyName("songsPlayed")] public int? SongsPlayed { get; init; }
    /// <summary>Charted songs.</summary>
    [JsonPropertyName("totalChartedSongs")] public int? TotalChartedSongs { get; init; }
    /// <summary>Ranked teams that day.</summary>
    [JsonPropertyName("totalRankedTeams")] public int? TotalRankedTeams { get; init; }

    /// <summary>Rank for a metric.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>One-based rank (0 when unranked).</returns>
    public int Rank(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => AdjustedSkillRank,
        BandRankingMetric.Weighted => WeightedRank,
        BandRankingMetric.FcRate => FcRateRank,
        _ => TotalScoreRank,
    };

    /// <summary>Metric value for a snapshot.</summary>
    /// <param name="metric">Metric.</param>
    /// <returns>Rating, fraction or score; <see langword="null"/> when absent.</returns>
    public double? Value(BandRankingMetric metric) => metric switch
    {
        BandRankingMetric.Adjusted => AdjustedSkillRating,
        BandRankingMetric.Weighted => WeightedRating,
        BandRankingMetric.FcRate => FcRate,
        _ => TotalScore,
    };
}

/// <summary>Response of <c>GET /api/rankings/bands/{bandType}/{teamKey}/history</c>.</summary>
public sealed record BandRankHistoryResponse
{
    /// <summary>Echoed band type.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Echoed team key.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Window in days.</summary>
    [JsonPropertyName("days")] public int Days { get; init; }
    /// <summary>Snapshots (any order).</summary>
    [JsonPropertyName("history")] public IReadOnlyList<BandRankHistoryEntry> History { get; init; } = [];
    /// <summary><c>current</c>, <c>ready</c>, <c>catching_up</c>, <c>stale</c>, <c>disabled</c> or <c>failed</c>.</summary>
    [JsonPropertyName("historyStatus")] public string? HistoryStatus { get; init; }
    /// <summary>Optional service explanation.</summary>
    [JsonPropertyName("historyMessage")] public string? HistoryMessage { get; init; }
}
#endregion

#region Best and worst songs
/// <summary>One song performance (<c>BandSongPerformanceDto</c>).</summary>
public sealed record BandSongPerformance
{
    /// <summary>Catalogue song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>One-based rank.</summary>
    [JsonPropertyName("rank")] public int Rank { get; init; }
    /// <summary>Song band population.</summary>
    [JsonPropertyName("totalEntries")] public int TotalEntries { get; init; }
    /// <summary>Rank fraction (0 is best).</summary>
    [JsonPropertyName("percentile")] public double Percentile { get; init; }
    /// <summary>Team score.</summary>
    [JsonPropertyName("score")] public long Score { get; init; }
    /// <summary>Accuracy in ten-thousandths of a percent.</summary>
    [JsonPropertyName("accuracy")] public double? Accuracy { get; init; }
    /// <summary>Full-combo flag.</summary>
    [JsonPropertyName("isFullCombo")] public bool? IsFullCombo { get; init; }
    /// <summary>Stars.</summary>
    [JsonPropertyName("stars")] public int? Stars { get; init; }
}

/// <summary>Response of <c>GET /api/rankings/bands/{bandType}/{teamKey}/songs</c> (503 until the projection is published).</summary>
public sealed record BandSongExtremesResponse
{
    /// <summary>Echoed band type.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Echoed team key.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Rows per list.</summary>
    [JsonPropertyName("limit")] public int Limit { get; init; }
    /// <summary>Best songs by percentile.</summary>
    [JsonPropertyName("best")] public IReadOnlyList<BandSongPerformance> Best { get; init; } = [];
    /// <summary>Worst songs by percentile.</summary>
    [JsonPropertyName("worst")] public IReadOnlyList<BandSongPerformance> Worst { get; init; } = [];
}
#endregion

#region Song band leaderboard
/// <summary>One band score on a song (<c>SongBandLeaderboardEntryDto</c>).</summary>
public sealed record SongBandLeaderboardEntry
{
    /// <summary>One-way band hash.</summary>
    [JsonPropertyName("bandId")] public string BandId { get; init; } = "";
    /// <summary>Band size service ID.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Member-account roster key.</summary>
    [JsonPropertyName("teamKey")] public string TeamKey { get; init; } = "";
    /// <summary>Combo ID of this score.</summary>
    [JsonPropertyName("comboId")] public string? ComboId { get; init; }
    /// <summary>Members with per-song stats.</summary>
    [JsonPropertyName("members")] public IReadOnlyList<BandMember> Members { get; init; } = [];
    /// <summary>Team score.</summary>
    [JsonPropertyName("score")] public long Score { get; init; }
    /// <summary>One-based rank.</summary>
    [JsonPropertyName("rank")] public int Rank { get; init; }
    /// <summary>Team accuracy in ten-thousandths of a percent.</summary>
    [JsonPropertyName("accuracy")] public double? Accuracy { get; init; }
    /// <summary>Full-combo flag.</summary>
    [JsonPropertyName("isFullCombo")] public bool? IsFullCombo { get; init; }
    /// <summary>Stars.</summary>
    [JsonPropertyName("stars")] public int? Stars { get; init; }
    /// <summary>Season.</summary>
    [JsonPropertyName("season")] public int? Season { get; init; }

    /// <summary>Joined member names.</summary>
    [JsonIgnore] public string MembersLabel => BandMember.JoinNames(Members);
}

/// <summary>Page from <c>GET /api/leaderboard/{songId}/bands/{bandType}?top=&amp;offset=[&amp;accountId=]</c>.</summary>
public sealed record SongBandLeaderboardResponse
{
    /// <summary>Echoed song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Echoed band type.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Rows in this page.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Population.</summary>
    [JsonPropertyName("totalEntries")] public int TotalEntries { get; init; }
    /// <summary>Paging population.</summary>
    [JsonPropertyName("localEntries")] public int? LocalEntries { get; init; }
    /// <summary>
    /// Whether the header names the entry total (web <c>songBandLeaderboard.subtitle</c>); absent or false shows only the
    /// band size, as the solo board does for its own flag.
    /// </summary>
    [JsonPropertyName("showLeaderboardEntryTotals")] public bool? ShowLeaderboardEntryTotals { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("entries")] public IReadOnlyList<SongBandLeaderboardEntry> Entries { get; init; } = [];
    /// <summary>The selected player's best band on this song and size (<c>accountId</c> query; a pure read).</summary>
    [JsonPropertyName("selectedPlayerEntry")] public SongBandLeaderboardEntry? SelectedPlayerEntry { get; init; }
    /// <summary>A selected band's own row (<c>teamKey</c> query, not sent by natives yet).</summary>
    [JsonPropertyName("selectedBandEntry")] public SongBandLeaderboardEntry? SelectedBandEntry { get; init; }

    /// <summary>
    /// The pinned footer's row (web <c>SongBandLeaderboardPage</c> <c>selectedPlayerEntry</c>): the selected player's best
    /// band, only when it actually includes that player. <see cref="SelectedBandEntry"/> answers a <c>teamKey</c> query
    /// natives don't send, so it is never pinned.
    /// </summary>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <returns>Pinned row, or <see langword="null"/>.</returns>
    public SongBandLeaderboardEntry? PinnedEntry(string? accountId) =>
        !string.IsNullOrEmpty(accountId) && SelectedPlayerEntry is { } own &&
        own.Members.Any(m => string.Equals(m.AccountId, accountId, StringComparison.OrdinalIgnoreCase))
            ? own : null;

    /// <summary>Paging population (<c>localEntries ?? totalEntries</c>, never negative).</summary>
    [JsonIgnore] public int Population => Math.Max(0, LocalEntries ?? TotalEntries);

    /// <summary>Pages of <paramref name="pageSize"/> rows, at least one.</summary>
    /// <param name="pageSize">Rows per page.</param>
    /// <returns>Page count.</returns>
    public int PageCount(int pageSize) => Population == 0 ? 1 : (Population - 1) / Math.Max(1, pageSize) + 1;

    /// <summary>Rejects a response for another board, with impossible counts or with a selected row of another size.</summary>
    /// <param name="songId">Requested song.</param>
    /// <param name="bandType">Requested size.</param>
    /// <param name="top">Requested page size.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string songId, BandType bandType, int top)
    {
        if (SongId != songId || BandType != bandType.ServiceId() || Entries is null || Count != Entries.Count ||
            Count > top || TotalEntries < 0 || LocalEntries is < 0 || Entries.Any(e => e is null || e.Members is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        IEnumerable<SongBandLeaderboardEntry?> selected = [SelectedPlayerEntry, SelectedBandEntry];
        if (selected.OfType<SongBandLeaderboardEntry>().Any(e => e.BandType != BandType || e.Members is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }
}
#endregion

#region Song Detail band previews
/// <summary>
/// One band size's preview inside <c>GET /api/leaderboard/{songId}/bands/all</c> (service
/// <c>BuildSongBandLeaderboardsPayload</c>): the top rows plus, when the request carried <c>accountId</c>, the selected
/// player's best band row for that size.
/// </summary>
public sealed record SongBandPreview
{
    /// <summary>Band size service ID.</summary>
    [JsonPropertyName("bandType")] public string BandType { get; init; } = "";
    /// <summary>Rows in <see cref="Entries"/>.</summary>
    [JsonPropertyName("count")] public int Count { get; init; }
    /// <summary>Ranked bands of this size on the song.</summary>
    [JsonPropertyName("totalEntries")] public int TotalEntries { get; init; }
    /// <summary>Paging population.</summary>
    [JsonPropertyName("localEntries")] public int? LocalEntries { get; init; }
    /// <summary>Top rows.</summary>
    [JsonPropertyName("entries")] public IReadOnlyList<SongBandLeaderboardEntry> Entries { get; init; } = [];
    /// <summary>The selected player's best band on this song and size (<c>accountId</c> query).</summary>
    [JsonPropertyName("selectedPlayerEntry")] public SongBandLeaderboardEntry? SelectedPlayerEntry { get; init; }
    /// <summary>A selected band's own row (<c>selectedTeamKey</c> query, not sent by natives yet).</summary>
    [JsonPropertyName("selectedBandEntry")] public SongBandLeaderboardEntry? SelectedBandEntry { get; init; }

    /// <summary>The highlighted row: a selected band wins over the selected player's best band (web preview).</summary>
    [JsonIgnore] public SongBandLeaderboardEntry? SelectedEntry => SelectedBandEntry ?? SelectedPlayerEntry;

    /// <summary>Whether a top row is the highlighted row.</summary>
    /// <param name="entry">Top row.</param>
    /// <returns><see langword="true"/> when it is the same band as <see cref="SelectedEntry"/>.</returns>
    public bool IsSelected(SongBandLeaderboardEntry entry) => SelectedEntry is { } selected && IsSameBand(entry, selected);

    /// <summary>The highlighted row to append after the top rows when they don't already show it.</summary>
    [JsonIgnore]
    public SongBandLeaderboardEntry? FooterEntry =>
        SelectedEntry is { } selected && !Entries.Any(e => IsSameBand(e, selected)) ? selected : null;

    /// <summary>Web <c>isSameSongBandEntry</c>: equal non-empty band ID, or equal size and roster.</summary>
    /// <param name="a">First row.</param>
    /// <param name="b">Second row.</param>
    /// <returns><see langword="true"/> for the same band.</returns>
    public static bool IsSameBand(SongBandLeaderboardEntry a, SongBandLeaderboardEntry b) =>
        (a.BandId.Length > 0 && a.BandId == b.BandId) || (a.BandType == b.BandType && a.TeamKey == b.TeamKey);
}

/// <summary>Response of <c>GET /api/leaderboard/{songId}/bands/all</c>: one preview per band size.</summary>
public sealed record SongBandLeaderboardsResponse
{
    /// <summary>Echoed song.</summary>
    [JsonPropertyName("songId")] public string SongId { get; init; } = "";
    /// <summary>Whether totals may be shown.</summary>
    [JsonPropertyName("showLeaderboardEntryTotals")] public bool? ShowLeaderboardEntryTotals { get; init; }
    /// <summary>Previews by band size.</summary>
    [JsonPropertyName("bands")] public IReadOnlyList<SongBandPreview> Bands { get; init; } = [];

    /// <summary>The preview for one size; a size the service omitted reads as empty (web <c>createSongBandData</c>).</summary>
    /// <param name="bandType">Band size.</param>
    /// <returns>Preview.</returns>
    public SongBandPreview For(BandType bandType) =>
        Bands.FirstOrDefault(b => b.BandType == bandType.ServiceId()) ?? new SongBandPreview { BandType = bandType.ServiceId() };

    /// <summary>
    /// Rejects a response for another song, an unknown or repeated size, an impossible count or a row filed under the
    /// wrong size.
    /// </summary>
    /// <param name="songId">Requested song.</param>
    /// <param name="top">Requested rows per size.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(string songId, int top)
    {
        if (SongId != songId || Bands is null) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var band in Bands)
        {
            if (band is null || !BandTypeInfo.TryParse(band.BandType, out _) || !seen.Add(band.BandType) || band.Entries is null ||
                band.Count != band.Entries.Count || band.Count > top || band.TotalEntries < 0 || band.LocalEntries is < 0)
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
            IEnumerable<SongBandLeaderboardEntry?> rows = [.. band.Entries, band.SelectedPlayerEntry, band.SelectedBandEntry];
            if (band.Entries.Any(e => e is null) ||
                rows.OfType<SongBandLeaderboardEntry>().Any(e => e.BandType != band.BandType || e.Members is null))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
    }
}
#endregion
