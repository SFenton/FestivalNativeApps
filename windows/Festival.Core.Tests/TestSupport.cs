using System.Net;
using System.Text;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>A request as seen by the fake transport.</summary>
public sealed record SentRequest(HttpMethod Method, Uri Uri, Dictionary<string, string> Headers);

/// <summary>Scriptable HTTP handler that records every request.</summary>
public sealed class FakeHandler : HttpMessageHandler
{
    public List<SentRequest> Requests { get; } = [];

    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Responder { get; set; } =
        (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(", ", h.Value), StringComparer.OrdinalIgnoreCase);
        Requests.Add(new SentRequest(request.Method, request.RequestUri!, headers));
        return Responder(request, cancellationToken);
    }

    public IEnumerable<SentRequest> To(string path) => Requests.Where(r => r.Uri.AbsolutePath == path);
}

/// <summary>Synthetic wire payloads (captured shapes, no production data).</summary>
public static class Wire
{
    public const string BaseUrl = "https://festivalscoretracker.com/";

    public static string Publication(long id = 7, bool pinning = false) =>
        $$"""{"contractVersion":1,"publicationId":{{id}},"publishedScrapeId":42,"readyForPinning":{{Lower(pinning)}},"pinningEnabled":{{Lower(pinning)}},"unreadySurfaces":[]}""";

    public static string SongJson(string id, string title, string artist, int? year = 2026, int? duration = 180,
        string difficulty = """{"guitar":2,"bass":3,"drums":99,"vocals":0}""", string? sig = null) =>
        $$$"""{"songId":"{{{id}}}","title":"{{{title}}}","artist":"{{{artist}}}","year":{{{Num(year)}}},"durationSeconds":{{{Num(duration)}}},"albumArt":"art-{{{id}}}.jpg","difficulty":{{{difficulty}}}{{{(sig is null ? "" : $",\"sig\":\"{sig}\"")}}},"maxScores":{"Solo_Guitar":1000},"populationTiers":{"Solo_Guitar":{"bc":1,"t":[]""" + "}}}";

    public static string Songs(params string[] songs) =>
        $$"""{"count":{{songs.Length}},"currentSeason":15,"songs":[{{string.Join(",", songs)}}]}""";

    public static string DefaultSongs() => Songs(
        SongJson("s1", "Alpha", "Zed Band", 2020, 100),
        SongJson("s2", "Beta", "Ann Artist", 2021, 250, sig: "Keyboard"),
        SongJson("s3", "Électrique", "Mid", null, null, """{"guitar":6,"proVocals":4}"""));

    public static string Leaderboard(string songId, string instrument, int count, int total = 100, int? local = 90)
    {
        var entries = string.Join(",", Enumerable.Range(1, count).Select(Entry));
        return $$"""{"songId":"{{songId}}","instrument":"{{instrument}}","count":{{count}},"totalEntries":{{total}},"localEntries":{{Num(local)}},"entries":[{{entries}}]}""";
    }

    private static string Entry(int i) =>
        $$"""{"accountId":"a{{i}}","displayName":"Player {{i}}","score":{{100000 - i}},"rank":{{i}},"accuracy":985000,"isFullCombo":{{Lower(i == 1)}},"stars":6,"season":15}""";

    public static HttpResponseMessage Response(HttpStatusCode status, string body = "", params (string Name, string Value)[] headers)
    {
        var response = new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        foreach (var (name, value) in headers)
        {
            if (!response.Headers.TryAddWithoutValidation(name, value))
                response.Content.Headers.TryAddWithoutValidation(name, value);
        }
        return response;
    }

    public static HttpResponseMessage Ok(string body, params (string Name, string Value)[] headers) =>
        Response(HttpStatusCode.OK, body, headers);

    private static string Lower(bool value) => value ? "true" : "false";

    private static string Num(int? value) => value?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "null";
}

/// <summary>A standard fake service: publication 7, three songs and ten-row leaderboards.</summary>
public sealed class FakeService
{
    public FakeHandler Handler { get; } = new();
    public long PublicationId { get; set; } = 7;
    public string SongsBody { get; set; } = Wire.DefaultSongs();
    public Func<HttpRequestMessage, HttpResponseMessage?>? Override { get; set; }

    public FakeService()
    {
        Handler.Responder = (request, _) => Task.FromResult(Route(request));
    }

    public FestivalApiClient Client(TimeSpan? timeout = null) =>
        new(new RequestGate(new HttpClient(Handler), timeout), new Uri(Wire.BaseUrl));

    public FestivalSession Session(FakeTimeProvider? time = null, AppSettings? settings = null) =>
        new(Client(), new InMemorySettingsStore(settings), time ?? new FakeTimeProvider());

    private HttpResponseMessage Route(HttpRequestMessage request)
    {
        if (Override?.Invoke(request) is { } custom) return custom;
        var path = request.RequestUri!.AbsolutePath;
        var pub = ("X-FST-Publication-Id", PublicationId.ToString(System.Globalization.CultureInfo.InvariantCulture));
        if (path == "/api/publication") return Wire.Ok(Wire.Publication(PublicationId));
        if (path == "/api/songs") return Wire.Ok(SongsBody, pub, ("ETag", "W/\"songs\""));
        if (path.StartsWith("/api/leaderboard/", StringComparison.Ordinal))
        {
            var parts = path.Split('/');
            return Wire.Ok(Wire.Leaderboard(parts[3], parts[4], 10), pub);
        }
        if (path.StartsWith("/__art/", StringComparison.Ordinal) || request.RequestUri.Host == "cdn2.unrealengine.com")
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) };
            response.Content.Headers.TryAddWithoutValidation("Content-Type", "image/jpeg");
            return response;
        }
        return Wire.Response(HttpStatusCode.NotFound);
    }
}

/// <summary>Async helpers for view-model tests.</summary>
public static class Async
{
    /// <summary>Lets queued continuations run.</summary>
    public static async Task Settle(int rounds = 5)
    {
        for (var i = 0; i < rounds; i++) await Task.Yield();
        await Task.Delay(10);
    }

    /// <summary>Advances a fake clock one step at a time, settling between steps.</summary>
    public static async Task Advance(FakeTimeProvider time, TimeSpan by, TimeSpan? step = null)
    {
        var increment = step ?? TimeSpan.FromSeconds(1);
        for (var elapsed = TimeSpan.Zero; elapsed < by; elapsed += increment)
        {
            time.Advance(increment);
            await Settle();
        }
    }

    /// <summary>Polls until a condition holds (bounded).</summary>
    public static async Task Until(Func<bool> condition, int timeoutMs = 3000)
    {
        var start = Environment.TickCount64;
        while (!condition())
        {
            if (Environment.TickCount64 - start > timeoutMs) throw new TimeoutException("Condition not met.");
            await Task.Delay(5);
        }
    }
}
