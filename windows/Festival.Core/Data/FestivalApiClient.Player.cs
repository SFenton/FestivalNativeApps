using System.Globalization;

namespace Festival.Core.Data;

#region Player endpoints
public static partial class ServiceEndpoints
{
    /// <summary><c>GET /api/player/{accountId}</c> (compact public scores; 202 = syncing).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri Player(Uri baseUri, string accountId) => Build(baseUri, ["api", "player", Account(accountId)]);

    /// <summary><c>GET /api/player/{accountId}/history?songId=&amp;instrument=</c> (pure precomputed read).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="songId">Song.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerHistory(Uri baseUri, string accountId, string songId, Instrument instrument)
    {
        RequireSegment(songId);
        return Build(baseUri, ["api", "player", Account(accountId), "history"],
            [("songId", songId), ("instrument", instrument.ServiceId())]);
    }

    /// <summary><c>GET /api/rankings/{instrument}/{accountId}</c> (single-account row; 404 = unranked).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerInstrumentRanking(Uri baseUri, Instrument instrument, string accountId) =>
        Build(baseUri, ["api", "rankings", instrument.ServiceId(), Account(accountId)]);

    /// <summary><c>GET /api/rankings/{instrument}/{accountId}/history?days=</c> (pure <c>SELECT</c>).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="days">Lookback, 1–365.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerRankHistory(Uri baseUri, Instrument instrument, string accountId, int days)
    {
        if (days is < 1 or > 365) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return Build(baseUri, ["api", "rankings", instrument.ServiceId(), Account(accountId), "history"],
            [("days", days.ToString(CultureInfo.InvariantCulture))]);
    }

    /// <summary>Validates an account ID segment.</summary>
    /// <param name="accountId">Candidate.</param>
    /// <returns>The same ID.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    private static string Account(string accountId) =>
        ProfileText.IsValidAccountId(accountId) ? accountId : throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
}
#endregion

#region Player reads
public sealed partial class FestivalApiClient
{
    /// <summary>
    /// Reads a player's public compact scores. Keyless and headerless: never a selected-profile header or tracking call.
    /// </summary>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated profile, its state and publication provenance.</returns>
    /// <exception cref="FestivalApiException">Invalid ID, transport, status or corrupt data (404 surfaces as <see cref="FestivalApiErrorKind.HttpStatus"/>).</exception>
    public async Task<PlayerProfilePayload> GetPlayerProfileAsync(string accountId, CancellationToken cancellationToken = default)
    {
        var read = await ReadPinnedResponseAsync(ServiceEndpoints.Player(BaseUri, accountId), PlayerProfileResponse.WireByteLimit,
            acceptsSyncing: true, cancellationToken).ConfigureAwait(false);
        var profile = Decode(read.Body, PlayerJsonContext.Default.PlayerProfileResponse).Normalized();
        var state = profile.Validate(accountId);
        if ((state == PlayerProfileState.Syncing) != (read.Status == 202))
            throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, read.Status);
        return new PlayerProfilePayload(profile, state, read.PublicationId, read.ObservedPublicationId);
    }

    /// <summary>Reads one account's row on a per-instrument rankings board (never player-stats).</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The row, or <see cref="PlayerRankingState.Unranked"/> for HTTP 404.</returns>
    /// <exception cref="FestivalApiException">Transport, other status or corrupt data.</exception>
    public async Task<PlayerInstrumentRankingPayload> GetPlayerInstrumentRankingAsync(
        Instrument instrument, string accountId, CancellationToken cancellationToken = default)
    {
        try
        {
            var body = await ReadPinnedAsync(ServiceEndpoints.PlayerInstrumentRanking(BaseUri, instrument, accountId), 256_000,
                cancellationToken).ConfigureAwait(false);
            var ranking = Decode(body, PlayerJsonContext.Default.PlayerInstrumentRanking);
            ranking.Validate(instrument, accountId);
            return new PlayerInstrumentRankingPayload(ranking, PlayerRankingState.Available);
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            return new PlayerInstrumentRankingPayload(null, PlayerRankingState.Unranked);
        }
    }

    /// <summary>Reads one account's daily rank history on one instrument (empty history, not 404, when unranked).</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="days">Lookback, 1–365 (the web uses 30).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated history.</returns>
    /// <exception cref="FestivalApiException">Invalid arguments, transport, status or corrupt data.</exception>
    public async Task<PlayerRankHistory> GetPlayerRankHistoryAsync(
        Instrument instrument, string accountId, int days = 30, CancellationToken cancellationToken = default)
    {
        var body = await ReadPinnedAsync(ServiceEndpoints.PlayerRankHistory(BaseUri, instrument, accountId, days), 2_000_000,
            cancellationToken).ConfigureAwait(false);
        var history = Decode(body, PlayerJsonContext.Default.PlayerRankHistory);
        history.Validate(instrument, accountId);
        return history;
    }

    /// <summary>Reads a player's score-change history for one song and chart.</summary>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="songId">Song.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Rows, or an explicit syncing (202) / unregistered (404) state.</returns>
    /// <exception cref="FestivalApiException">Transport, other status or corrupt data.</exception>
    public async Task<PlayerHistoryPayload> GetPlayerHistoryAsync(
        string accountId, string songId, Instrument instrument, CancellationToken cancellationToken = default)
    {
        var url = ServiceEndpoints.PlayerHistory(BaseUri, accountId, songId, instrument);
        try
        {
            var read = await ReadPinnedResponseAsync(url, 8_000_000, acceptsSyncing: true, cancellationToken).ConfigureAwait(false);
            var response = Decode(read.Body, PlayerJsonContext.Default.PlayerHistoryResponse);
            response.Validate(accountId);
            return new PlayerHistoryPayload(response, read.Status == 202 ? PlayerHistoryState.Syncing : PlayerHistoryState.Available);
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            return new PlayerHistoryPayload(new PlayerHistoryResponse { AccountId = accountId }, PlayerHistoryState.Unregistered);
        }
    }
}
#endregion
