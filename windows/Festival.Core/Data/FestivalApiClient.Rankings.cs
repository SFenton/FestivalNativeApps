using System.Globalization;

namespace Festival.Core.Data;

#region Rankings endpoints
/// <summary>
/// URL builders for the rankings boards. Both are pure keyless reads: the handlers only query the
/// precomputed rankings tables (<c>FSTService/Api/RankingsEndpoints.cs:187</c> and <c>:680</c>); re-probed
/// 200 on 2026-09-27 (service-safety allowlist).
/// </summary>
public static class RankingsEndpoints
{
    /// <summary>Largest page the service accepts.</summary>
    public const int MaxPageSize = 200;

    /// <summary><c>GET /api/rankings/{instrument}?rankBy=&amp;page=&amp;pageSize=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="instrument">Solo chart.</param>
    /// <param name="metric">Sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows, 1–200.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri Rankings(Uri baseUri, Instrument instrument, RankingMetric metric, int page, int pageSize)
    {
        RequirePaging(page, pageSize);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", instrument.ServiceId()], Query(metric.ServiceId(), page, pageSize));
    }

    /// <summary><c>GET /api/rankings/bands/{bandType}?rankBy=&amp;page=&amp;pageSize=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="metric">Band sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows, 1–200.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri BandRankings(Uri baseUri, BandType bandType, BandRankingMetric metric, int page, int pageSize)
    {
        RequirePaging(page, pageSize);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "bands", bandType.ServiceId()], Query(metric.ServiceId(), page, pageSize));
    }

    /// <summary><c>GET /api/rankings/combo?combo=&amp;rankBy=&amp;page=&amp;pageSize=</c> (pure read, issue #602).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="board">Within-group combo board.</param>
    /// <param name="metric">Sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows, 1–200.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/> for a single board.</exception>
    public static Uri ComboRankings(Uri baseUri, RankingBoard board, RankingMetric metric, int page, int pageSize)
    {
        RequirePaging(page, pageSize);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "combo"], [("combo", Combo(board)), .. Query(metric.ServiceId(), page, pageSize)]);
    }

    /// <summary><c>GET /api/rankings/combo/{accountId}?combo=&amp;rankBy=</c> (single-account row; 404 = unranked).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="board">Within-group combo board.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="metric">Sort metric.</param>
    /// <returns>Endpoint URL.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    public static Uri PlayerComboRanking(Uri baseUri, RankingBoard board, string accountId, RankingMetric metric)
    {
        if (!ProfileText.IsValidAccountId(accountId)) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
        return ServiceEndpoints.Build(baseUri, ["api", "rankings", "combo", accountId], [("combo", Combo(board)), ("rankBy", metric.ServiceId())]);
    }

    /// <summary>The combo ID of a combo board.</summary>
    /// <param name="board">Board.</param>
    /// <returns>Lowercase hex ID.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/> for a single board.</exception>
    private static string Combo(RankingBoard board) =>
        board.ComboId ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);

    /// <summary>Rejects a non-positive page or an out-of-range size.</summary>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    private static void RequirePaging(int page, int pageSize)
    {
        if (page < 1 || pageSize is < 1 or > MaxPageSize) throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
    }

    /// <summary>Builds the shared query items.</summary>
    /// <param name="rankBy">Metric service ID.</param>
    /// <param name="page">Page.</param>
    /// <param name="pageSize">Size.</param>
    /// <returns>Query pairs.</returns>
    private static (string, string)[] Query(string rankBy, int page, int pageSize) =>
    [
        ("rankBy", rankBy),
        ("page", page.ToString(CultureInfo.InvariantCulture)),
        ("pageSize", pageSize.ToString(CultureInfo.InvariantCulture)),
    ];
}
#endregion

#region Rankings reads
public sealed partial class FestivalApiClient
{
    /// <summary>Reads one page of an instrument's global rankings (publication-pinned).</summary>
    /// <param name="instrument">Solo chart.</param>
    /// <param name="metric">Sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows (10 for an overview card, 25 for Full Rankings).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated page.</returns>
    public async Task<RankingsResponse> GetRankingsAsync(
        Instrument instrument, RankingMetric metric, int page = 1, int pageSize = LeaderboardPaging.PageSize,
        CancellationToken cancellationToken = default)
    {
        var url = RankingsEndpoints.Rankings(BaseUri, instrument, metric, page, pageSize);
        var bytes = await ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false);
        var board = Decode(bytes, RankingsJsonContext.Default.RankingsResponse);
        board.Validate(instrument);
        return board;
    }

    /// <summary>Reads one page of a band size's rankings (publication-pinned).</summary>
    /// <param name="bandType">Band size.</param>
    /// <param name="metric">Band sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated page.</returns>
    public async Task<BandRankingsResponse> GetBandRankingsAsync(
        BandType bandType, BandRankingMetric metric, int page = 1, int pageSize = LeaderboardPaging.PageSize,
        CancellationToken cancellationToken = default)
    {
        var url = RankingsEndpoints.BandRankings(BaseUri, bandType, metric, page, pageSize);
        var bytes = await ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false);
        var board = Decode(bytes, RankingsJsonContext.Default.BandRankingsResponse);
        board.Validate(bandType);
        return board;
    }

    /// <summary>
    /// Reads one page of a within-group combo board (publication-pinned). A 404 means no account is ranked on the combo
    /// yet and reads as an empty board, like the web's <c>FullRankingsPage</c>.
    /// </summary>
    /// <param name="board">Combo board.</param>
    /// <param name="metric">Sort metric.</param>
    /// <param name="page">One-based page.</param>
    /// <param name="pageSize">Rows.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated page.</returns>
    public async Task<ComboRankingsResponse> GetComboRankingsAsync(
        RankingBoard board, RankingMetric metric, int page = 1, int pageSize = LeaderboardPaging.PageSize,
        CancellationToken cancellationToken = default)
    {
        var url = RankingsEndpoints.ComboRankings(BaseUri, board, metric, page, pageSize);
        try
        {
            var bytes = await ReadPinnedAsync(url, 4_000_000, cancellationToken).ConfigureAwait(false);
            var response = Decode(bytes, RankingsJsonContext.Default.ComboRankingsResponse);
            response.Validate(board.ComboId!);
            return response;
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            return ComboRankingsResponse.Empty(board.ComboId!, metric, page, pageSize);
        }
    }

    /// <summary>Reads one account's row on a combo board (never player-stats, no selected-profile header).</summary>
    /// <param name="board">Combo board.</param>
    /// <param name="accountId">Validated account ID.</param>
    /// <param name="metric">Sort metric.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The row, or <see langword="null"/> for HTTP 404 (unranked).</returns>
    public async Task<ComboRankingEntry?> GetPlayerComboRankingAsync(
        RankingBoard board, string accountId, RankingMetric metric, CancellationToken cancellationToken = default)
    {
        var url = RankingsEndpoints.PlayerComboRanking(BaseUri, board, accountId, metric);
        try
        {
            var bytes = await ReadPinnedAsync(url, 256_000, cancellationToken).ConfigureAwait(false);
            var row = Decode(bytes, RankingsJsonContext.Default.PlayerComboRanking);
            row.Validate(board.ComboId!, accountId);
            return row.ToEntry();
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            return null;
        }
    }
}
#endregion
