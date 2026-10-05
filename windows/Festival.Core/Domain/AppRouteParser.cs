using System.Globalization;

namespace Festival.Core.Domain;

#region Parser
/// <summary>Parses web-style paths (deep links, <c>--route</c>) into typed routes with validated segments.</summary>
public static class AppRouteParser
{
    /// <summary>Parses a path such as <c>/songs/abc/Solo_Guitar?page=2</c>.</summary>
    /// <param name="path">Path with optional query; a full <c>https://…</c> URL is also accepted.</param>
    /// <param name="route">Route, or a section root (<see langword="null"/>) for <c>/songs</c>, <c>/settings</c> or <c>/</c>.</param>
    /// <param name="section">Section that owns the result.</param>
    /// <returns><see langword="true"/> when the path is recognized and every segment is safe.</returns>
    public static bool TryParse(string? path, out AppRoute? route, out AppSection section)
    {
        route = null;
        section = AppSection.Songs;
        if (string.IsNullOrWhiteSpace(path)) return false;
        if (Uri.TryCreate(path, UriKind.Absolute, out var absolute) && absolute.Scheme is "https" or "http" or "fst")
            path = absolute.PathAndQuery;
        var queryStart = path.IndexOf('?');
        var query = ParseQuery(queryStart >= 0 ? path[(queryStart + 1)..] : "");
        var raw = (queryStart >= 0 ? path[..queryStart] : path).Trim('/');
        string[] parts = raw.Length == 0 ? [] : raw.Split('/').Select(Uri.UnescapeDataString).ToArray();
        if (parts.Any(p => p.Length == 0 || p.Length > 200 || p.Contains("..", StringComparison.Ordinal) ||
                           p.Contains('/') || ProfileText.ContainsUnsafeCharacter(p)))
            return false;

        object? parsed = parts switch
        {
            [] or ["songs"] => null,
            ["settings"] => null,
            ["songs", var id] => new AppRoute.SongDetail(id, Chart(query.GetValueOrDefault("instrument"))),
            ["songs", var id, "bands", var type] => new AppRoute.SongBandLeaderboard(id, type, Page(query.GetValueOrDefault("page")), Flag(query.GetValueOrDefault("navToBand"))),
            ["songs", var id, var chart, "history"] when InstrumentInfo.TryParse(chart, out var i) => new AppRoute.PlayerHistory(id, i),
            ["songs", var id, var chart] when InstrumentInfo.TryParse(chart, out var i) =>
                new AppRoute.SongLeaderboard(id, i, Page(query.GetValueOrDefault("page")), Flag(query.GetValueOrDefault("navToPlayer"))),
            ["player", var account] when ProfileText.IsValidAccountId(account) => new AppRoute.Player(account),
            ["bands", "player", var account] when ProfileText.IsValidAccountId(account) => new AppRoute.PlayerBands(account),
            ["bands"] => new AppRoute.Bands(),
            ["bands", var band] => new AppRoute.Band(band, query.GetValueOrDefault("bandType"), query.GetValueOrDefault("teamKey")),
            ["leaderboards"] => new AppRoute.Leaderboards(),
            ["leaderboards", "all"] => new AppRoute.FullRankings(
                Chart(query.GetValueOrDefault("instrument")) ?? Instrument.Lead, query.GetValueOrDefault("rankBy") ?? RankingMetricInfo.Default.ServiceId(),
                int.TryParse(query.GetValueOrDefault("page"), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var page)
                    && page > 0 ? page : 1),
            ["leaderboards", "bands", var type] => new AppRoute.BandRankings(type),
            ["rivals"] => new AppRoute.Rivals(),
            ["rivals", "all"] => RivalScope.FromAllRivalsQuery(query.GetValueOrDefault("category"), query.GetValueOrDefault("mode"),
                query.GetValueOrDefault("rankBy"), query.GetValueOrDefault("instruments")) is { } scope
                ? new AppRoute.AllRivals(scope) : Invalid,
            ["rivals", var rival] when ProfileText.IsValidAccountId(rival) =>
                new AppRoute.RivalDetail(rival, query.GetValueOrDefault("name"), RivalScope.FromToken(query.GetValueOrDefault("scope"))),
            ["rivals", var rival, "rivalry"] when ProfileText.IsValidAccountId(rival) =>
                new AppRoute.Rivalry(rival, query.GetValueOrDefault("mode") ?? "closest_battles", query.GetValueOrDefault("name"),
                    RivalScope.FromToken(query.GetValueOrDefault("scope"))),
            ["statistics"] => new AppRoute.Statistics(),
            ["suggestions"] => new AppRoute.Suggestions(),
            ["compete"] => new AppRoute.Compete(),
            ["shop"] => new AppRoute.Shop(),
            ["settings", "licenses"] => new AppRoute.Licenses(),
            ["search"] => new AppRoute.Search(query.GetValueOrDefault("q") ?? "", SearchScopes.Parse(query.GetValueOrDefault("scope"))),
            _ => Invalid,
        };
        if (ReferenceEquals(parsed, Invalid)) return false;
        route = (AppRoute?)parsed;
        section = route?.Section ?? (parts is ["settings"] ? AppSection.Settings : AppSection.Songs);
        return true;
    }

    /// <summary>
    /// Whether a route needs a selected profile. The web wraps Rivals (hub, all, detail, rivalry), Compete, Statistics and
    /// Suggestions in <c>RequirePlayer</c>/<c>RequireSelection</c> and redirects to Songs without one; Player History joins
    /// them here (operator 2026-09-28: the web's anonymous history is an empty song header).
    /// </summary>
    /// <param name="route">Route.</param>
    /// <returns><see langword="true"/> for player-only routes.</returns>
    public static bool RequiresPlayer(AppRoute route) => route is AppRoute.Rivals or AppRoute.AllRivals or AppRoute.RivalDetail
        or AppRoute.Rivalry or AppRoute.Compete or AppRoute.Statistics or AppRoute.Suggestions or AppRoute.PlayerHistory;

    /// <summary>Applies the anonymous redirect: a player-only route becomes the Songs root (<see langword="null"/>).</summary>
    /// <param name="route">Parsed route (or a section root).</param>
    /// <param name="hasPlayer">Whether a profile is selected.</param>
    /// <returns>The route, or <see langword="null"/> (Songs) when it needs a missing profile.</returns>
    public static AppRoute? ForProfile(AppRoute? route, bool hasPlayer) =>
        route is not null && !hasPlayer && RequiresPlayer(route) ? null : route;

    /// <summary>Sentinel for unrecognized paths.</summary>
    private static readonly object Invalid = new();

    /// <summary>Parses an optional instrument service ID.</summary>
    /// <param name="value">Query value.</param>
    /// <returns>Chart or <see langword="null"/>.</returns>
    private static Instrument? Chart(string? value) => InstrumentInfo.TryParse(value, out var i) ? i : null;

    /// <summary>Parses a positive page, defaulting to one.</summary>
    /// <param name="value">Query value.</param>
    /// <returns>Page ≥ 1.</returns>
    private static int Page(string? value) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var page) && page > 0 ? page : 1;

    /// <summary>Parses a web boolean flag (<c>navToPlayer=true</c>).</summary>
    /// <param name="value">Query value.</param>
    /// <returns><see langword="true"/> only for <c>true</c>.</returns>
    private static bool Flag(string? value) => string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);

    /// <summary>Splits a query string; later duplicates win.</summary>
    /// <param name="query">Text after <c>?</c>.</param>
    /// <returns>Unescaped pairs.</returns>
    private static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var equals = pair.IndexOf('=');
            if (equals <= 0) continue;
            var value = Uri.UnescapeDataString(pair[(equals + 1)..].Replace('+', ' '));
            if (value.Length > 0 && value.Length <= 200 && !ProfileText.ContainsUnsafeCharacter(value))
                result[Uri.UnescapeDataString(pair[..equals])] = value;
        }
        return result;
    }
}
#endregion
