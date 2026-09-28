namespace Festival.Core.Data;

#region Rivals reads
/// <summary>
/// Keyless Rivals reads. Unpinned operational GETs (rivals are not part of the catalogue/score publication contract),
/// sharing the gate's transport, keyless guard, deadline and status mapping. Each endpoint's documented 404
/// ("no rivals found" / "no precomputed song data") becomes an empty result; a 503 scrape freeze surfaces as
/// <see cref="FestivalApiErrorKind.PublicReadFrozen"/> for the shared status view.
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Every combo's rivals in one read (suggestion rival families).</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated response; empty on 404.</returns>
    public async Task<RivalsAllResponse> GetRivalsAllAsync(string accountId, CancellationToken cancellationToken = default)
    {
        var body = await ReadRivalsAsync(RivalsEndpoints.All(BaseUri, accountId), 8_000_000, cancellationToken).ConfigureAwait(false);
        if (body is null) return RivalsAllResponse.Empty(accountId);
        var response = Decode(body, RivalsJsonContext.Default.RivalsAllResponse).Validated();
        return string.Equals(response.AccountId, accountId, StringComparison.OrdinalIgnoreCase)
            ? response : throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
    }

    /// <summary>Shared-song rivals for one chart, hex combo or the Pro Drums family.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated list; empty on 404.</returns>
    public async Task<RivalsListResponse> GetRivalsListAsync(string accountId, string scope, CancellationToken cancellationToken = default)
    {
        var body = await ReadRivalsAsync(RivalsEndpoints.List(BaseUri, accountId, scope), 2_000_000, cancellationToken).ConfigureAwait(false);
        return body is null ? RivalsListResponse.Empty(scope) : Decode(body, RivalsJsonContext.Default.RivalsListResponse).Validated();
    }

    /// <summary>Global-leaderboard neighbours on one chart.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated list; empty on 404.</returns>
    public async Task<LeaderboardRivalsListResponse> GetLeaderboardRivalsAsync(
        string accountId, Instrument instrument, RivalRankMetric rankBy, CancellationToken cancellationToken = default)
    {
        var body = await ReadRivalsAsync(RivalsEndpoints.LeaderboardList(BaseUri, accountId, instrument, rankBy), 2_000_000, cancellationToken)
            .ConfigureAwait(false);
        return body is null
            ? new LeaderboardRivalsListResponse(instrument.ServiceId(), rankBy.ServiceId(), null, [], [])
            : Decode(body, RivalsJsonContext.Default.LeaderboardRivalsListResponse).Validated();
    }

    /// <summary>Every shared song against one rival for a chart or combo scope.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="sort">Detail sort.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated detail; empty on 404.</returns>
    public async Task<RivalDetailResponse> GetRivalDetailAsync(
        string accountId, string scope, string rivalId, string sort = "closest", CancellationToken cancellationToken = default)
    {
        var body = await ReadRivalsAsync(RivalsEndpoints.Detail(BaseUri, accountId, scope, rivalId, sort), 8_000_000, cancellationToken)
            .ConfigureAwait(false);
        return body is null ? RivalDetailResponse.Empty(rivalId) : Decode(body, RivalsJsonContext.Default.RivalDetailResponse).Validated(rivalId);
    }

    /// <summary>Head-to-head songs against a leaderboard rival on one chart.</summary>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="sort">Detail sort.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated detail; empty on 404.</returns>
    public async Task<RivalDetailResponse> GetLeaderboardRivalDetailAsync(
        string accountId, Instrument instrument, string rivalId, RivalRankMetric rankBy, string sort = "closest",
        CancellationToken cancellationToken = default)
    {
        var url = RivalsEndpoints.LeaderboardDetail(BaseUri, accountId, instrument, rivalId, rankBy, sort);
        var body = await ReadRivalsAsync(url, 8_000_000, cancellationToken).ConfigureAwait(false);
        return body is null ? RivalDetailResponse.Empty(rivalId) : Decode(body, RivalsJsonContext.Default.RivalDetailResponse).Validated(rivalId);
    }

    /// <summary>Sends one unpinned Rivals GET.</summary>
    /// <param name="url">Allowlisted URL.</param>
    /// <param name="maxBytes">Largest accepted body.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Body bytes, or <see langword="null"/> for the documented 404.</returns>
    private async Task<byte[]?> ReadRivalsAsync(Uri url, int maxBytes, CancellationToken cancellationToken)
    {
        using var request = RequestGate.CreateGet(url);
        var response = await gate.SendAsync(request, maxBytes, cancellationToken).ConfigureAwait(false);
        if (response.Status == 404) return null;
        RequestGate.MapStatus(response, acceptsSyncing: false);
        return response.Body;
    }
}
#endregion
