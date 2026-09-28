namespace Festival.Core.Data;

#region Rivals reads
/// <summary>
/// Keyless Rivals reads. Unpinned operational GETs (rivals are not part of the catalogue/score publication contract),
/// sharing the gate's transport, keyless guard, deadline and status mapping. Each endpoint's documented 404
/// ("no rivals found" / "no precomputed song data") becomes an empty result; a 503 scrape freeze surfaces as
/// <see cref="FestivalApiErrorKind.PublicReadFrozen"/> for the shared status view. Decoding lives in synchronous
/// <c>Parse*</c> methods so it is measured and testable apart from transport.
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Every combo's rivals in one read (suggestion rival families).</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated response; empty on 404.</returns>
    public Task<RivalsAllResponse> GetRivalsAllAsync(string accountId, CancellationToken cancellationToken = default) =>
        ReadRivalsAsync(RivalsEndpoints.All(BaseUri, accountId), 8_000_000, body => ParseRivalsAll(body, accountId), cancellationToken);

    /// <summary>Shared-song rivals for one chart, hex combo or the Pro Drums family.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated list; empty on 404.</returns>
    public Task<RivalsListResponse> GetRivalsListAsync(string accountId, string scope, CancellationToken cancellationToken = default) =>
        ReadRivalsAsync(RivalsEndpoints.List(BaseUri, accountId, scope), 2_000_000, body => ParseRivalsList(body, scope), cancellationToken);

    /// <summary>Global-leaderboard neighbours on one chart.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated list; empty on 404.</returns>
    public Task<LeaderboardRivalsListResponse> GetLeaderboardRivalsAsync(
        string accountId, Instrument instrument, RankingMetric rankBy, CancellationToken cancellationToken = default) =>
        ReadRivalsAsync(RivalsEndpoints.LeaderboardList(BaseUri, accountId, instrument, rankBy), 2_000_000,
            body => ParseLeaderboardRivals(body, instrument, rankBy), cancellationToken);

    /// <summary>Every shared song against one rival for a chart or combo scope.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="sort">Detail sort.</param>
    /// <param name="allowLiveFallback">Lets the service compute an untracked rival live (Find Rival only).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated detail; empty on 404.</returns>
    public Task<RivalDetailResponse> GetRivalDetailAsync(
        string accountId, string scope, string rivalId, string sort = "closest", bool allowLiveFallback = false,
        CancellationToken cancellationToken = default) =>
        ReadRivalsAsync(RivalsEndpoints.Detail(BaseUri, accountId, scope, rivalId, sort, allowLiveFallback), 8_000_000,
            body => ParseRivalDetail(body, rivalId), cancellationToken);

    /// <summary>Head-to-head songs against a leaderboard rival on one chart.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="sort">Detail sort.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated detail; empty on 404.</returns>
    public Task<RivalDetailResponse> GetLeaderboardRivalDetailAsync(
        string accountId, Instrument instrument, string rivalId, RankingMetric rankBy, string sort = "closest",
        CancellationToken cancellationToken = default) =>
        ReadRivalsAsync(RivalsEndpoints.LeaderboardDetail(BaseUri, accountId, instrument, rivalId, rankBy, sort), 8_000_000,
            body => ParseRivalDetail(body, rivalId), cancellationToken);

    /// <summary>Decodes <c>rivals/all</c> for the requested account (404 body <see langword="null"/> → empty).</summary>
    /// <param name="body">Body, or <see langword="null"/> for 404.</param>
    /// <param name="accountId">Requested player.</param>
    /// <returns>Validated response.</returns>
    /// <exception cref="FestivalApiException">Undecodable, invalid or for another account.</exception>
    internal static RivalsAllResponse ParseRivalsAll(byte[]? body, string accountId)
    {
        if (body is null) return RivalsAllResponse.Empty(accountId);
        var response = Decode(body, RivalsJsonContext.Default.RivalsAllResponse).Validated();
        return string.Equals(response.AccountId, accountId, StringComparison.OrdinalIgnoreCase)
            ? response : throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>Decodes a rivals list (404 → empty).</summary>
    /// <param name="body">Body, or <see langword="null"/> for 404.</param>
    /// <param name="scope">Requested scope.</param>
    /// <returns>Validated list.</returns>
    internal static RivalsListResponse ParseRivalsList(byte[]? body, string scope) =>
        body is null ? RivalsListResponse.Empty(scope) : Decode(body, RivalsJsonContext.Default.RivalsListResponse).Validated();

    /// <summary>Decodes a leaderboard-rivals list (404 → empty).</summary>
    /// <param name="body">Body, or <see langword="null"/> for 404.</param>
    /// <param name="instrument">Requested chart.</param>
    /// <param name="rankBy">Requested metric.</param>
    /// <returns>Validated list.</returns>
    internal static LeaderboardRivalsListResponse ParseLeaderboardRivals(byte[]? body, Instrument instrument, RankingMetric rankBy) =>
        body is null
            ? new LeaderboardRivalsListResponse(instrument.ServiceId(), rankBy.ServiceId(), null, [], [])
            : Decode(body, RivalsJsonContext.Default.LeaderboardRivalsListResponse).Validated();

    /// <summary>Decodes a rival detail for the requested rival (404 → empty).</summary>
    /// <param name="body">Body, or <see langword="null"/> for 404.</param>
    /// <param name="rivalId">Requested rival.</param>
    /// <returns>Validated detail.</returns>
    internal static RivalDetailResponse ParseRivalDetail(byte[]? body, string rivalId) =>
        body is null ? RivalDetailResponse.Empty(rivalId) : Decode(body, RivalsJsonContext.Default.RivalDetailResponse).Validated(rivalId);

    /// <summary>Sends one unpinned Rivals GET and parses it.</summary>
    /// <typeparam name="T">Result.</typeparam>
    /// <param name="url">Allowlisted URL.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="parse">Parser receiving the body, or <see langword="null"/> for the documented 404.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Parsed result.</returns>
    private async Task<T> ReadRivalsAsync<T>(Uri url, int maxBytes, Func<byte[]?, T> parse, CancellationToken cancellationToken)
    {
        using var request = RequestGate.CreateGet(url);
        var response = await gate.SendAsync(request, maxBytes, cancellationToken).ConfigureAwait(false);
        if (response.Status == 404) return parse(null);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        return parse(response.Body);
    }
}
#endregion
