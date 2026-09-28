using System.Text.Json;
using System.Text.Json.Nodes;

namespace Festival.Core.Tests;

/// <summary>
/// Cross-platform parity: runs the C# generator over the shared fixture and compares every page of
/// every scenario, plus raw Mulberry32 output, with the unmodified Apple generator's output
/// (produced by <c>tools/windows/suggestion_parity/run_parity.py</c>).
/// </summary>
public sealed class SuggestionParityTests
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    internal sealed record FixtureScore(string SongId, string Instrument, long Score, double? Accuracy, bool? FullCombo,
        int? Stars, int? Season, int? Rank, int? TotalEntries);

    internal sealed record Scenario(string Name, uint Seed, bool? DisableSkipping, int? FixedDisplayCount, int CurrentSeason,
        string Rivals, int[] Pages, int[]? ResetPages, int? ResetCycles);

    internal sealed record Fixture(List<Song> Songs, List<FixtureScore> Scores, RivalsAllResponse RivalsAll, uint[] RngSeeds, List<Scenario> Scenarios);

    private static readonly Lazy<(Fixture Fixture, JsonNode Expected)> Data = new(() =>
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        var fixture = JsonSerializer.Deserialize<Fixture>(File.ReadAllText(Path.Combine(dir, "suggestions-parity.json")), Web)!;
        var expected = JsonNode.Parse(File.ReadAllText(Path.Combine(dir, "suggestions-parity.expected.json")))!;
        return (fixture, expected);
    });

    internal static Fixture LoadFixture() => Data.Value.Fixture;

    internal static IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> ScoreIndex(Fixture fixture)
    {
        var index = new Dictionary<string, Dictionary<Instrument, SuggestionScore>>(StringComparer.Ordinal);
        foreach (var row in fixture.Scores)
        {
            Assert.True(InstrumentInfo.TryParse(row.Instrument, out var instrument));
            if (!index.TryGetValue(row.SongId, out var perSong)) index[row.SongId] = perSong = [];
            perSong[instrument] = new SuggestionScore(row.Score, row.Stars, row.Accuracy, row.FullCombo, row.Season, row.Rank, row.TotalEntries);
        }
        return index.ToDictionary(p => p.Key, p => (IReadOnlyDictionary<Instrument, SuggestionScore>)p.Value, StringComparer.Ordinal);
    }

    [Fact]
    public void Mulberry32MatchesApple()
    {
        var (fixture, expected) = Data.Value;
        var actual = new JsonArray();
        foreach (var seed in fixture.RngSeeds)
        {
            var rng = new SeededSuggestionRng(seed);
            var doubles = new JsonArray(Enumerable.Range(0, 8).Select(_ => (JsonNode)JsonValue.Create(rng.NextDouble())).ToArray());
            var ints = new JsonArray(Enumerable.Range(0, 8).Select(_ => (JsonNode)JsonValue.Create(rng.NextInt(97))).ToArray());
            actual.Add(new JsonObject { ["seed"] = seed, ["doubles"] = doubles, ["ints"] = ints });
        }
        AssertSame(expected["rng"], actual, "rng");
    }

    [Fact]
    public void RivalIndexMatchesApple()
    {
        var (fixture, expected) = Data.Value;
        var index = RivalDataIndex.Build(fixture.RivalsAll);
        var actual = new JsonObject
        {
            ["songRivals"] = new JsonArray(index.SongRivals.Select(r => (JsonNode)new JsonObject
            {
                ["accountId"] = r.AccountId, ["displayName"] = r.DisplayName, ["direction"] = r.Direction,
            }).ToArray()),
            ["byRivalCounts"] = new JsonObject(index.ByRival.Select(p => KeyValuePair.Create(p.Key, (JsonNode?)p.Value.Count))),
            ["closestCount"] = index.ClosestRivalBySong.Count,
        };
        AssertSame(expected["rivalIndex"], actual, "rivalIndex");
    }

    public static TheoryData<string> ScenarioNames() => new(LoadFixture().Scenarios.Select(s => s.Name));

    [Theory]
    [MemberData(nameof(ScenarioNames))]
    public void ScenarioMatchesApple(string name)
    {
        var (fixture, expected) = Data.Value;
        var scenario = fixture.Scenarios.Single(s => s.Name == name);
        var rivals = RivalDataIndex.Build(fixture.RivalsAll);
        var generator = new SuggestionGenerator(new SuggestionGenerator.Options(
            scenario.Seed, scenario.DisableSkipping ?? false, scenario.FixedDisplayCount, scenario.CurrentSeason));
        generator.SetSource(fixture.Songs, ScoreIndex(fixture));
        if (scenario.Rivals == "early") generator.SetRivalData(rivals);
        var pages = new JsonArray();
        for (var n = 0; n < scenario.Pages.Length; n++)
        {
            pages.Add(Page(generator.GetNext(scenario.Pages[n])));
            if (n == 0 && scenario.Rivals == "late") generator.SetRivalData(rivals);
        }
        var resetPages = new JsonArray();
        if (scenario.ResetPages is { } counts)
        {
            for (var cycle = 0; cycle < (scenario.ResetCycles ?? 1); cycle++)
            {
                generator.ResetForEndless();
                foreach (var count in counts) resetPages.Add(Page(generator.GetNext(count)));
            }
        }
        var expectedScenario = expected["scenarios"]!.AsArray().Single(s => s!["name"]!.GetValue<string>() == name)!;
        AssertSame(expectedScenario["pages"], pages, $"{name}.pages");
        AssertSame(expectedScenario["resetPages"], resetPages, $"{name}.resetPages");
    }

    private static JsonArray Page(IReadOnlyList<SuggestionCategory> categories) =>
        new(categories.Select(c =>
        {
            var node = new JsonObject
            {
                ["key"] = c.Key, ["title"] = c.Title, ["description"] = c.Description, ["type"] = c.Type.Key(),
                ["songs"] = new JsonArray(c.Songs.Select(Item).ToArray()),
            };
            if (c.Instrument is { } i) node["instrument"] = i.ServiceId();
            return (JsonNode)node;
        }).ToArray());

    private static JsonNode Item(SuggestionSongItem item)
    {
        var node = new JsonObject { ["id"] = item.Id };
        if (item.Stars is { } stars) node["stars"] = stars;
        if (item.Percent is { } percent) node["percent"] = percent;
        if (item.FullCombo is { } fc) node["fullCombo"] = fc;
        if (item.PercentileDisplay is { } pct) node["percentileDisplay"] = pct;
        if (item.RivalName is { } rivalName) node["rivalName"] = rivalName;
        if (item.RivalAccountId is { } rivalId) node["rivalAccountId"] = rivalId;
        if (item.RivalRankDelta is { } delta) node["rivalRankDelta"] = delta;
        return node;
    }

    private static double Number(JsonValue value) => double.Parse(value.ToJsonString(), System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>Deep equality with numbers compared as doubles; reports the first differing path.</summary>
    internal static void AssertSame(JsonNode? expected, JsonNode? actual, string path)
    {
        switch (expected)
        {
            case JsonObject e:
                var a = Assert.IsType<JsonObject>(actual);
                Assert.True(e.Select(p => p.Key).Order().SequenceEqual(a.Select(p => p.Key).Order()),
                    $"{path}: keys {string.Join(",", e.Select(p => p.Key).Order())} vs {string.Join(",", a.Select(p => p.Key).Order())}");
                foreach (var (key, value) in e) AssertSame(value, a[key], $"{path}.{key}");
                break;
            case JsonArray e:
                var arr = Assert.IsType<JsonArray>(actual);
                for (var i = 0; i < Math.Min(e.Count, arr.Count); i++) AssertSame(e[i], arr[i], $"{path}[{i}]");
                Assert.True(e.Count == arr.Count, $"{path}: length {e.Count} vs {arr.Count}");
                break;
            case JsonValue e when e.GetValueKind() == JsonValueKind.Number:
                Assert.True(actual is JsonValue av && av.GetValueKind() == JsonValueKind.Number && Number(av) == Number(e),
                    $"{path}: {e.ToJsonString()} vs {actual?.ToJsonString()}");
                break;
            default:
                Assert.True(JsonNode.DeepEquals(expected, actual), $"{path}: {expected?.ToJsonString()} vs {actual?.ToJsonString()}");
                break;
        }
    }
}
