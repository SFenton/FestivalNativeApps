using System.Globalization;
using System.Net;

namespace Festival.Core.Tests;

/// <summary>Synthetic band payloads (captured shapes from contracts/fixtures, no production data).</summary>
public static class BandWire
{
    public const string Team = "fixture-rank-1:fixture-rank-2";

    public static string Fixture(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", name + ".json"));

    public static string PlayerBands(string accountId, int total, int count, int offset = 0)
    {
        var entries = string.Join(",", Enumerable.Range(offset + 1, count).Select(i =>
            $$"""{"bandId":"b{{i}}","teamKey":"{{accountId}}:mate{{i}}","bandType":"{{(i % 2 == 0 ? "Band_Trios" : "Band_Duets")}}","appearanceCount":{{i}},"members":[{"accountId":"{{accountId}}","displayName":"Player One","instruments":["Solo_Guitar","Solo_Guitar","Solo_Unknown"]},{"accountId":"mate{{i}}","displayName":null,"instruments":["Solo_Drums"]},{"accountId":"{{accountId}}","displayName":"Player One","instruments":[]}]}"""));
        return $$"""{"accountId":"{{accountId}}","group":"all","totalCount":{{total}},"entries":[{{entries}}]}""";
    }

    public static string SongBands(string songId, string bandType, int count, int total, int offset = 0, int? selectedRank = null, string? selectedType = null, bool? showTotals = null)
    {
        var entries = string.Join(",", Enumerable.Range(offset + 1, count).Select(i => SongBandEntry(bandType, i)));
        var selected = selectedRank is { } rank ? $$""","selectedPlayerEntry":{{SongBandEntry(selectedType ?? bandType, rank)}}""" : "";
        var totals = showTotals is { } show ? "\"showLeaderboardEntryTotals\":" + (show ? "true," : "false,") : "";
        return $$"""{"songId":"{{songId}}","bandType":"{{bandType}}",{{totals}}"count":{{count}},"totalEntries":{{total}},"localEntries":{{total}},"entries":[{{entries}}]{{selected}}}""";
    }

    public static string SongBandEntry(string bandType, int i) =>
        $$"""{"bandId":"sb{{i}}","bandType":"{{bandType}}","teamKey":"t{{i}}a:t{{i}}b","comboId":null,"members":[{"accountId":"t{{i}}a","displayName":"Lead {{i}}","instruments":["Solo_Guitar"],"score":500,"accuracy":990000,"isFullCombo":true,"stars":5,"difficulty":3,"season":9},{"accountId":"t{{i}}b","displayName":"","instruments":["Solo_Bass"]}],"score":{{100000 - i}},"rank":{{i}},"accuracy":{{(i == 1 ? "990000" : "null")}},"isFullCombo":{{(i == 1 ? "true" : "false")}},"stars":{{(i == 1 ? "6" : "0")}},"season":9,"difficulty":3,"percentile":0.1,"endTime":null}""";
}

/// <summary>A <see cref="FakeService"/> that also serves band routes from overridable bodies.</summary>
public sealed class BandService
{
    public FakeService Service { get; } = new();
    public Func<string, string?, HttpResponseMessage?>? Band { get; set; }

    public BandService()
    {
        Service.SongsBody = Wire.Songs(
            Wire.SongJson("fixture-pulse", "Pulse", "Fixture Artist", 2024, 200),
            Wire.SongJson("s1", "Alpha", "Zed Band", 2020, 100));
        Service.Override = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            var query = request.RequestUri.Query;
            if (Band?.Invoke(path, query) is { } custom) return custom;
            if (path.StartsWith("/api/player/", StringComparison.Ordinal) && path.EndsWith("/bands", StringComparison.Ordinal))
            {
                var account = path.Split('/')[3];
                var page = int.Parse(Query(query, "page") ?? "1", CultureInfo.InvariantCulture);
                var size = int.Parse(Query(query, "pageSize") ?? "25", CultureInfo.InvariantCulture);
                const int total = 30;
                var count = Math.Clamp(total - (page - 1) * size, 0, size);
                return Ok(BandWire.PlayerBands(account, total, count, (page - 1) * size));
            }
            if (path.EndsWith("/history", StringComparison.Ordinal)) return Ok(BandWire.Fixture("band-rank-history-demo"));
            if (path.EndsWith("/songs", StringComparison.Ordinal) && path.StartsWith("/api/rankings/", StringComparison.Ordinal))
                return Ok(BandWire.Fixture("band-song-extremes-demo"));
            if (path.StartsWith("/api/rankings/bands/", StringComparison.Ordinal)) return Ok(BandWire.Fixture("band-detail-demo"));
            if (path.Contains("/bands/", StringComparison.Ordinal) && path.StartsWith("/api/leaderboard/", StringComparison.Ordinal))
            {
                var parts = path.Split('/');
                var offset = int.Parse(Query(query, "offset") ?? "0", CultureInfo.InvariantCulture);
                const int total = 60;
                // Like the service: an accountId that leads a band ("t{rank}a") adds that band as selectedPlayerEntry.
                int? selected = Query(query, "accountId") is { Length: > 2 } account && account[0] == 't' && account[^1] == 'a' &&
                                int.TryParse(account[1..^1], NumberStyles.None, CultureInfo.InvariantCulture, out var rank) && rank <= total ? rank : null;
                return Ok(BandWire.SongBands(parts[3], parts[5], Math.Clamp(total - offset, 0, 25), total, offset, selected));
            }
            return null;
        };
    }

    public static HttpResponseMessage Ok(string body) => Wire.Ok(body, ("X-FST-Publication-Id", "7"));

    public static string? Query(string query, string key) =>
        query.TrimStart('?').Split('&').Select(p => p.Split('=')).Where(p => p[0] == key).Select(p => Uri.UnescapeDataString(p[1])).FirstOrDefault();

    public static HttpResponseMessage Unavailable() =>
        Wire.Response(HttpStatusCode.ServiceUnavailable, "", ("Retry-After", "30"));
}
