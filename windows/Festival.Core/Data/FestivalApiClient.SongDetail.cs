namespace Festival.Core.Data;

#region Song detail reads
public sealed partial class FestivalApiClient
{
    /// <summary>Reads every chart's top rows for a song in one pinned read (web <c>getAllLeaderboards</c>).</summary>
    /// <param name="songId">Catalogue song.</param>
    /// <param name="top">Rows per chart (10 on Song Detail).</param>
    /// <param name="leeway">Invalid-score leeway, only while filtering is on.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated rows per chart.</returns>
    /// <exception cref="FestivalApiException">Invalid arguments, transport, status or corrupt data.</exception>
    public async Task<AllLeaderboardsResponse> GetAllLeaderboardsAsync(
        string songId, int top = 10, double? leeway = null, CancellationToken cancellationToken = default)
    {
        var bytes = await ReadPinnedAsync(ServiceEndpoints.AllLeaderboards(BaseUri, songId, top, leeway), 8_000_000, cancellationToken)
            .ConfigureAwait(false);
        var all = Decode(bytes, SongDetailJsonContext.Default.AllLeaderboardsResponse);
        all.Validate(songId, top);
        return all;
    }

    /// <summary>Reads a player's score changes on every chart of one song (web <c>playerHistoryQueryOptions(accountId, songId)</c>).</summary>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="songId">Song.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Rows (all charts), or an explicit syncing (202) / unregistered (404) state.</returns>
    /// <exception cref="FestivalApiException">Transport, other status or corrupt data.</exception>
    public async Task<PlayerHistoryPayload> GetPlayerSongHistoryAsync(string accountId, string songId, CancellationToken cancellationToken = default)
    {
        var url = ServiceEndpoints.PlayerSongHistory(BaseUri, accountId, songId);
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
