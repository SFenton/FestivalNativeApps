using System.Globalization;

namespace Festival.Core.Data;

#region Band reads
/// <summary>
/// Keyless, publication-bound band reads. Every route here only <c>SELECT</c>s (verified in FSTService):
/// <c>GetPlayerBandsList</c> degrades to an empty page instead of rebuilding its projection, and Band Detail uses the
/// rankings board filtered by <c>teamKey</c> (<c>GetBandTeamRanking</c>). Band search serves only its projection since
/// the #320 service fix (unpinned, like the account search). <c>/api/bands/{bandId}</c> and
/// <c>/api/rankings/bands/{bandType}/{teamKey}</c> can write on a GET and have no builder.
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Largest band response accepted.</summary>
    private const int BandResponseLimit = 4_000_000;

    /// <summary>Reads one page of a player's bands (<c>GET /api/player/{accountId}/bands</c>).</summary>
    /// <param name="accountId">Public account.</param>
    /// <param name="group">Group filter.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows per page, 1–100.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated page.</returns>
    public async Task<PlayerBandListResponse> GetPlayerBandsAsync(
        string accountId, PlayerBandGroup group, int page, int pageSize = 25, CancellationToken cancellationToken = default)
    {
        var url = BandEndpoints.PlayerBands(BaseUri, accountId, group, page, pageSize);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var list = Decode(bytes, BandsJsonContext.Default.PlayerBandListResponse);
        list.Validate(accountId, pageSize);
        return list;
    }

    /// <summary>Reads one band's ranking row by the type and team key its originating row carried.</summary>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The team's ranking row.</returns>
    /// <exception cref="FestivalApiException">404 (<see cref="FestivalApiErrorKind.HttpStatus"/>) when the team is unranked.</exception>
    public async Task<BandDetail> GetBandProfileAsync(BandType bandType, string teamKey, CancellationToken cancellationToken = default)
    {
        var url = BandEndpoints.BandProfile(BaseUri, bandType, teamKey);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var envelope = Decode(bytes, BandsJsonContext.Default.BandProfileEnvelope);
        if (envelope.BandType != bandType.ServiceId())
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var detail = envelope.SelectedBandEntry ?? throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404);
        if (detail.TeamKey != teamKey || detail.Members is null)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        return detail;
    }

    /// <summary>Reads a band's daily rank history.</summary>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <param name="days">Window, 1–3650.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated history.</returns>
    public async Task<BandRankHistoryResponse> GetBandRankHistoryAsync(
        BandType bandType, string teamKey, int days = 30, CancellationToken cancellationToken = default)
    {
        var url = BandEndpoints.BandRankHistory(BaseUri, bandType, teamKey, days);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var history = Decode(bytes, BandsJsonContext.Default.BandRankHistoryResponse);
        if (history.BandType != bandType.ServiceId() || history.TeamKey != teamKey || history.History is null ||
            history.History.Any(h => h is null))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        return history;
    }

    /// <summary>Reads a band's best and worst songs (503 until the band-song projection is published).</summary>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <param name="limit">Rows per list, 1–20.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated lists.</returns>
    public async Task<BandSongExtremesResponse> GetBandSongExtremesAsync(
        BandType bandType, string teamKey, int limit = 5, CancellationToken cancellationToken = default)
    {
        var url = BandEndpoints.BandSongExtremes(BaseUri, bandType, teamKey, limit);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var songs = Decode(bytes, BandsJsonContext.Default.BandSongExtremesResponse);
        if (songs.BandType != bandType.ServiceId() || songs.TeamKey != teamKey || songs.Best is null || songs.Worst is null ||
            songs.Best.Count > limit || songs.Worst.Count > limit)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        return songs;
    }

    /// <summary>
    /// Reads one page of a song's band leaderboard. The selected player is sent only as the <c>accountId</c> query, which
    /// makes the service add that player's best band of this size (<c>selectedPlayerEntry</c>, a pure SELECT) for the pinned
    /// footer; never as a selected-profile header.
    /// </summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="top">Rows per page, 1–100.</param>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated rows.</returns>
    public async Task<SongBandLeaderboardResponse> GetSongBandLeaderboardAsync(
        string songId, BandType bandType, int page = 1, int top = 25, string? accountId = null, CancellationToken cancellationToken = default)
    {
        if (page < 1 || page - 1 > int.MaxValue / Math.Max(top, 1))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        var url = BandEndpoints.SongBandLeaderboard(BaseUri, songId, bandType, top, (page - 1) * top, accountId);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var board = Decode(bytes, BandsJsonContext.Default.SongBandLeaderboardResponse);
        board.Validate(songId, bandType, top);
        return board;
    }

    /// <summary>
    /// Reads Song Detail's band previews: every band size's top rows in one request
    /// (<c>GET /api/leaderboard/{songId}/bands/all</c>). The selected player is sent only as the <c>accountId</c> query,
    /// which makes the service add that player's best band per size; never as a selected-profile header.
    /// </summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="top">Rows per band size, 1–50.</param>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated previews.</returns>
    public async Task<SongBandLeaderboardsResponse> GetSongBandLeaderboardsAsync(
        string songId, int top = 10, string? accountId = null, CancellationToken cancellationToken = default)
    {
        var url = BandEndpoints.SongBandLeaderboards(BaseUri, songId, top, accountId);
        var bytes = await ReadPinnedAsync(url, BandResponseLimit, cancellationToken).ConfigureAwait(false);
        var previews = Decode(bytes, BandsJsonContext.Default.SongBandLeaderboardsResponse);
        previews.Validate(songId, top);
        return previews;
    }

    /// <summary>
    /// Searches bands by member name (<c>GET /api/bands/search</c>, first page). Like the account search it is not
    /// pinned to a publication: the rows only open band pages, which pin their own reads.
    /// </summary>
    /// <param name="query">User text (trimmed here; 2–200 characters).</param>
    /// <param name="pageSize">Rows, 1–100 (global search asks for 10, like the web).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated page.</returns>
    public async Task<BandSearchResponse> SearchBandsAsync(string query, int pageSize = 10, CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(BandEndpoints.BandSearch(BaseUri, query.Trim(), pageSize));
        var response = await gate.SendAsync(request, 512_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        var page = Decode(response.Body, BandsJsonContext.Default.BandSearchResponse);
        page.Validate(pageSize);
        return page;
    }
}
#endregion

#region Band endpoint URLs
/// <summary>Allowlisted band GET URLs built from validated segments (see <see cref="ServiceEndpoints"/>).</summary>
public static class BandEndpoints
{
    /// <summary><c>GET /api/player/{accountId}/bands?group=&amp;page=&amp;pageSize=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Public account.</param>
    /// <param name="group">Group filter.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows, 1–100.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerBands(Uri baseUri, string accountId, PlayerBandGroup group, int page, int pageSize)
    {
        if (!ProfileText.IsValidAccountId(accountId) || !Enum.IsDefined(group) || page < 1 || pageSize is < 1 or > 100)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return ServiceEndpoints.Build(baseUri, ["api", "player", accountId, "bands"],
            [("group", group.ServiceId()), ("page", Text(page)), ("pageSize", Text(pageSize))]);
    }

    /// <summary><c>GET /api/rankings/bands/{bandType}?teamKey=&amp;rankBy=adjusted&amp;page=1&amp;pageSize=1</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri BandProfile(Uri baseUri, BandType bandType, string teamKey)
    {
        RequireType(bandType);
        RequireTeamKey(teamKey);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "bands", bandType.ServiceId()],
            [("teamKey", teamKey), ("rankBy", "adjusted"), ("page", "1"), ("pageSize", "1")]);
    }

    /// <summary><c>GET /api/rankings/bands/{bandType}/{teamKey}/history?days=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <param name="days">Window, 1–3650.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri BandRankHistory(Uri baseUri, BandType bandType, string teamKey, int days)
    {
        RequireType(bandType);
        RequireTeamKey(teamKey);
        if (days is < 1 or > 3650) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "bands", bandType.ServiceId(), teamKey, "history"],
            [("days", Text(days))]);
    }

    /// <summary><c>GET /api/rankings/bands/{bandType}/{teamKey}/songs?limit=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="teamKey">Member-account roster key.</param>
    /// <param name="limit">Rows per list, 1–20.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri BandSongExtremes(Uri baseUri, BandType bandType, string teamKey, int limit)
    {
        RequireType(bandType);
        RequireTeamKey(teamKey);
        if (limit is < 1 or > 20) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "bands", bandType.ServiceId(), teamKey, "songs"],
            [("limit", Text(limit))]);
    }

    /// <summary><c>GET /api/leaderboard/{songId}/bands/{bandType}?top=&amp;offset=[&amp;accountId=]</c> (pure read, allowlisted).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="top">Rows, 1–100.</param>
    /// <param name="offset">Non-negative offset.</param>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri SongBandLeaderboard(Uri baseUri, string songId, BandType bandType, int top, int offset, string? accountId = null)
    {
        ServiceEndpoints.RequireSegment(songId);
        RequireType(bandType);
        if (top is < 1 or > 100 || offset < 0 || (accountId is not null && !ProfileText.IsValidAccountId(accountId)))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        List<(string, string)> query = [("top", Text(top)), ("offset", Text(offset))];
        if (accountId is not null) query.Add(("accountId", accountId));
        return ServiceEndpoints.Build(baseUri, ["api", "leaderboard", songId, "bands", bandType.ServiceId()], [.. query]);
    }

    /// <summary><c>GET /api/leaderboard/{songId}/bands/all?top=[&amp;accountId=]</c> (pure read, allowlisted).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="top">Rows per band size, 1–50.</param>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri SongBandLeaderboards(Uri baseUri, string songId, int top, string? accountId)
    {
        ServiceEndpoints.RequireSegment(songId);
        if (top is < 1 or > 50 || (accountId is not null && !ProfileText.IsValidAccountId(accountId)))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        List<(string, string)> query = [("top", Text(top))];
        if (accountId is not null) query.Add(("accountId", accountId));
        return ServiceEndpoints.Build(baseUri, ["api", "leaderboard", songId, "bands", "all"], [.. query]);
    }

    /// <summary>
    /// <c>GET /api/bands/search?q=&amp;page=1&amp;pageSize=</c>: first page only, keyless (read-only since the #320
    /// service fix; see <c>.agents/platforms/service-safety.md</c>).
    /// </summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="query">Trimmed 2–200 character query without control characters.</param>
    /// <param name="pageSize">Rows, 1–100.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri BandSearch(Uri baseUri, string query, int pageSize)
    {
        if (query.Length is < 2 or > 200 || query != query.Trim() || ProfileText.ContainsUnsafeCharacter(query) ||
            pageSize is < 1 or > 100)
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return ServiceEndpoints.Build(baseUri, ["api", "bands", "search"],
            [("q", query), ("page", "1"), ("pageSize", Text(pageSize))]);
    }

    /// <summary>Whether a team key is a <c>:</c>-joined list of 1–4 valid account IDs (the service joins the sorted
    /// member IDs; fixtures may use one synthetic segment).</summary>
    /// <param name="teamKey">Candidate key.</param>
    /// <returns><see langword="true"/> when safe for a URL segment.</returns>
    public static bool IsValidTeamKey(string? teamKey) =>
        teamKey is { Length: > 0 and <= 600 } && teamKey.Split(':') is { Length: >= 1 and <= 4 } parts &&
        parts.All(ProfileText.IsValidAccountId);

    /// <summary>Rejects an undefined band type.</summary>
    /// <param name="bandType">Band size.</param>
    private static void RequireType(BandType bandType)
    {
        if (!Enum.IsDefined(bandType)) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
    }

    /// <summary>Rejects an unsafe team key.</summary>
    /// <param name="teamKey">Candidate key.</param>
    private static void RequireTeamKey(string teamKey)
    {
        if (!IsValidTeamKey(teamKey)) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
    }

    /// <summary>Invariant integer text.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Digits.</returns>
    private static string Text(int value) => value.ToString(CultureInfo.InvariantCulture);
}
#endregion
