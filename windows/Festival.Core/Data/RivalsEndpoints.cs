using System.Globalization;

namespace Festival.Core.Data;

#region Rivals endpoint URLs
/// <summary>
/// Allowlisted keyless Rivals GETs (<c>FSTService/Api/RivalsEndpoints.cs</c>, <c>LeaderboardRivalsEndpoints.cs</c>): pure reads
/// served from precomputed rows or the in-memory response cache. <c>POST …/rivals/recompute</c> has no builder, and the
/// detail builders never add <c>allowLiveFallback</c>/<c>includeGaps</c> (live computation, not in the safety allowlist).
/// </summary>
public static class RivalsEndpoints
{
    /// <summary>Sorts accepted by the detail endpoints.</summary>
    public static IReadOnlySet<string> Sorts { get; } = new HashSet<string>(StringComparer.Ordinal) { "closest", "they_lead", "you_lead" };

    /// <summary><c>GET /api/player/{accountId}/rivals/all</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Selected player.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri All(Uri baseUri, string accountId) =>
        ServiceEndpoints.Build(baseUri, ["api", "player", Account(accountId), "rivals", "all"]);

    /// <summary><c>GET /api/player/{accountId}/rivals/{scope}</c> for a chart, hex combo or <c>pro_drums</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri List(Uri baseUri, string accountId, string scope) =>
        ServiceEndpoints.Build(baseUri, ["api", "player", Account(accountId), "rivals", Scope(scope)]);

    /// <summary><c>GET /api/player/{accountId}/rivals/{scope}/{rivalId}?sort=&amp;limit=0&amp;offset=0</c> (limit 0 = all rows).</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Selected player.</param>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="sort"><c>closest</c>, <c>they_lead</c> or <c>you_lead</c>.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri Detail(Uri baseUri, string accountId, string scope, string rivalId, string sort = "closest") =>
        ServiceEndpoints.Build(baseUri, ["api", "player", Account(accountId), "rivals", Scope(scope), Account(rivalId)],
            [("sort", Sort(sort)), ("limit", "0"), ("offset", "0")]);

    /// <summary><c>GET /api/player/{accountId}/leaderboard-rivals/{instrument}?rankBy=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rankBy">Metric.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri LeaderboardList(Uri baseUri, string accountId, Instrument instrument, RivalRankMetric rankBy) =>
        ServiceEndpoints.Build(baseUri, ["api", "player", Account(accountId), "leaderboard-rivals", instrument.ServiceId()],
            [("rankBy", rankBy.ServiceId())]);

    /// <summary><c>GET /api/player/{accountId}/leaderboard-rivals/{instrument}/{rivalId}?rankBy=&amp;sort=</c>.</summary>
    /// <param name="baseUri">Validated origin.</param>
    /// <param name="accountId">Selected player.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="sort">Detail sort.</param>
    /// <returns>Endpoint URL.</returns>
    public static Uri LeaderboardDetail(Uri baseUri, string accountId, Instrument instrument, string rivalId, RivalRankMetric rankBy, string sort = "closest") =>
        ServiceEndpoints.Build(baseUri, ["api", "player", Account(accountId), "leaderboard-rivals", instrument.ServiceId(), Account(rivalId)],
            [("rankBy", rankBy.ServiceId()), ("sort", Sort(sort))]);

    /// <summary>Whether a scope segment is a chart service ID or a valid combo token.</summary>
    /// <param name="scope">Candidate.</param>
    /// <returns><see langword="true"/> when safe.</returns>
    public static bool IsValidScope(string? scope) => InstrumentInfo.TryParse(scope, out _) || RivalCombo.InstrumentsFor(scope) is not null;

    /// <summary>Validates an account segment.</summary>
    /// <param name="accountId">Candidate.</param>
    /// <returns>The account ID.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    private static string Account(string accountId) => ProfileText.IsValidAccountId(accountId)
        ? accountId : throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);

    /// <summary>Validates a scope segment.</summary>
    /// <param name="scope">Candidate.</param>
    /// <returns>The scope.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    private static string Scope(string scope) => IsValidScope(scope)
        ? scope : throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);

    /// <summary>Validates a sort.</summary>
    /// <param name="sort">Candidate.</param>
    /// <returns>The sort.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/>.</exception>
    private static string Sort(string sort) => Sorts.Contains(sort)
        ? sort : throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);

    /// <summary>Invariant integer text.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Text.</returns>
    internal static string Num(int value) => value.ToString(CultureInfo.InvariantCulture);
}
#endregion
