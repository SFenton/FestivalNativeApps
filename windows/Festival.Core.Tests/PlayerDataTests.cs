using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Synthetic player/ranking/history payloads (captured shapes, no production data).</summary>
public static class PlayerWire
{
    public const string Id = "fixtureplayer1";
    public const string Other = "fixtureplayer2";

    public static string Score(string song, string ins = "01", int score = 1000, int? acc = 979, bool? fc = false, int? st = 5,
        int? rk = 3, int? te = 100, double? pct = 3.0, string extra = "") =>
        $$"""{"si":"{{song}}","ins":"{{ins}}","sc":{{score}},"acc":{{N(acc)}},"fc":{{B(fc)}},"st":{{N(st)}},"sn":9,"dif":3,"pct":{{N(pct)}},"rk":{{N(rk)}},"te":{{N(te)}}{{extra}}}""";

    public static string Profile(string id = Id, string? name = "Fixture One", params string[] scores) =>
        $$"""{"accountId":"{{id}}","displayName":{{(name is null ? "null" : $"\"{name}\"")}},"totalScores":{{scores.Length}},"scores":[{{string.Join(",", scores)}}]}""";

    public static string Syncing(string id = Id) =>
        $$"""{"accountId":"{{id}}","displayName":null,"totalScores":0,"scores":[],"status":"syncing","notYetPublished":true}""";

    public static string Ranking(string id = Id, string instrument = "", int rank = 12, int total = 400, long score = 5000) =>
        $$"""{"accountId":"{{id}}","displayName":"Fixture One","instrument":"{{instrument}}","totalRankedAccounts":{{total}},"songsPlayed":10,"totalChartedSongs":50,"coverage":0.2,"rawSkillRating":0.1,"adjustedSkillRating":0.1,"adjustedSkillRank":9,"weightedRating":0.2,"weightedRank":8,"fcRate":0.5,"fcRateRank":7,"totalScore":{{score}},"totalScoreRank":{{rank}},"maxScorePercent":0.9,"maxScorePercentRank":6,"avgAccuracy":0.95,"fullComboCount":5,"avgStars":5.5,"bestRank":1,"avgRank":20}""";

    public static string Snapshot(string day, int rank, long? score = 100, int? field = 500) =>
        $$"""{"snapshotDate":"{{day}}","snapshotTakenAt":"{{day}}T06:00:00Z","adjustedSkillRank":1,"weightedRank":1,"fcRateRank":1,"totalScoreRank":{{rank}},"maxScorePercentRank":1,"totalScore":{{N(score)}},"rankedAccountCount":{{N(field)}}}""";

    public static string RankHistory(string id = Id, string instrument = "Solo_Guitar", params string[] snapshots) =>
        $$"""{"instrument":"{{instrument}}","accountId":"{{id}}","history":[{{string.Join(",", snapshots)}}]}""";

    public static string HistoryEntry(string song = "s1", string ins = "Solo_Guitar", long score = 1000, double? acc = 950000,
        bool? fc = false, int? season = 9, string? achieved = "2026-09-01T10:00:00Z", string changed = "2026-09-02T10:00:00Z") =>
        $$"""{"songId":"{{song}}","instrument":"{{ins}}","oldScore":null,"newScore":{{score}},"newRank":5,"accuracy":{{N(acc)}},"isFullCombo":{{B(fc)}},"stars":5,"season":{{N(season)}},"scoreAchievedAt":{{(achieved is null ? "null" : $"\"{achieved}\"")}},"changedAt":"{{changed}}"}""";

    public static string History(string id = Id, params string[] rows) =>
        $$"""{"accountId":"{{id}}","count":{{rows.Length}},"history":[{{string.Join(",", rows)}}]}""";

    public static string DefaultProfile(string id = Id) => Profile(id, "Fixture One",
        Score("s1", "01", 1000, 990, true, 6, 1, 100, 1.0),
        Score("s2", "01", 900, 950, false, 5, 30, 100, 30),
        Score("s1", "02", 800, 0, null, 4, null, null, -1),
        Score("s3", "100", 700, 1000, true, 6, 4, 200, 2));

    /// <summary>Routes player endpoints on a <see cref="FakeService"/>; <paramref name="profiles"/> maps account → (status, body).</summary>
    public static void Install(FakeService service, Dictionary<string, (HttpStatusCode Status, string Body)>? profiles = null,
        bool header = true)
    {
        var map = profiles ?? new() { [Id] = (HttpStatusCode.OK, DefaultProfile()), [Other] = (HttpStatusCode.OK, DefaultProfile(Other)) };
        service.Override = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            var pub = ("X-FST-Publication-Id", service.PublicationId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            var headers = header ? new[] { pub } : [];
            if (path.StartsWith("/api/player/", StringComparison.Ordinal))
            {
                var id = path.Split('/')[3];
                return map.TryGetValue(id, out var r) ? Wire.Response(r.Status, r.Body, headers) : Wire.Response(HttpStatusCode.NotFound, "{}", headers);
            }
            return null;
        };
    }

    private static string N(double? value) => value?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "null";

    private static string B(bool? value) => value is null ? "null" : value.Value ? "true" : "false";
}

public class PlayerModelTests
{
    [Theory]
    [InlineData("01", Instrument.Lead)]
    [InlineData("02", Instrument.Bass)]
    [InlineData("40", Instrument.Karaoke)]
    [InlineData("80", Instrument.ProCymbals)]
    [InlineData("100", Instrument.ProDrums)]
    public void InstrumentCode_DecodesSingleBitsInSourceOrder(string hex, Instrument expected)
    {
        Assert.True(PlayerInstrumentCode.TryParse(hex, out var instrument));
        Assert.Equal(expected, instrument);
        Assert.Equal(hex, PlayerInstrumentCode.Encode(expected));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1")]
    [InlineData("03")]
    [InlineData("00")]
    [InlineData("200")]
    [InlineData("0A")]
    [InlineData("001")]
    [InlineData("zz")]
    public void InstrumentCode_RejectsCompositeUnknownOrNonCanonical(string? hex) =>
        Assert.False(PlayerInstrumentCode.TryParse(hex, out _));

    [Fact]
    public void Score_ExpandsAccuracyAndMapsPercentileSentinel()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.DefaultProfile()),
            PlayerJsonContext.Default.PlayerProfileResponse);
        Assert.Equal(PlayerProfileState.Available, profile.Validate(PlayerWire.Id.ToUpperInvariant()));
        var lead = profile.Scores[0];
        Assert.Equal(990_000, lead.Accuracy);
        Assert.Equal(Instrument.Lead, lead.Instrument);
        Assert.Equal(1.0, lead.Percentile);
        Assert.Null(profile.Scores[2].Percentile);
        Assert.Equal(Instrument.ProDrums, profile.Scores[3].Instrument);
        var index = profile.ScoreIndex();
        Assert.Equal(2, index["s1"].Count);
        Assert.Equal(800, index["s1"][Instrument.Bass].Score);
        Assert.Equal(Instrument.Lead, new PlayerScore { InstrumentCode = "zz" }.Instrument);
    }

    [Theory]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[]}""")]
    [InlineData("""{"accountId":"other","totalScores":0,"scores":[]}""")]
    [InlineData("""{"accountId":"bad id","totalScores":0,"scores":[]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":-1,"scores":[]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","displayName":"a‮b","totalScores":0,"scores":[]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":0,"scores":[],"status":"syncing"}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":0,"scores":[],"status":"other"}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":0,"scores":[],"notYetPublished":true}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1}],"status":"syncing","notYetPublished":true}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":2,"scores":[{"si":"s","ins":"01","sc":1},{"si":"s","ins":"01","sc":2}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"03","sc":1}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"","ins":"01","sc":1}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":-1}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"acc":1001}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"st":7}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"pct":101}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"rk":-2}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"dif":-1}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"vs":[{"sc":1,"ml":1,"st":9}]}]}""")]
    [InlineData("""{"accountId":"fixtureplayer1","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"vs":[{"sc":1,"ml":1,"rt":[{"l":1,"r":-1}]}]}]}""")]
    public void Profile_RejectsCorruptOrMixedData(string json)
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(json), PlayerJsonContext.Default.PlayerProfileResponse).Normalized();
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            Assert.Throws<FestivalApiException>(() => profile.Validate(PlayerWire.Id)).Kind);
    }

    [Fact]
    public void Profile_AcceptsVariantsAndNormalizesName()
    {
        var json = """{"accountId":"fixtureplayer1","displayName":"  ","totalScores":1,"scores":[{"si":"s","ins":"01","sc":1,"isValid":false,"validScore":1,"validAccuracy":900,"validIsFullCombo":true,"ml":0.5,"vs":[{"sc":1,"acc":900,"fc":true,"st":5,"ml":1,"rt":[{"l":1,"r":2}]}],"et":"x","lp":"y","vlp":"z"}]}""";
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(json), PlayerJsonContext.Default.PlayerProfileResponse).Normalized();
        Assert.Null(profile.DisplayName);
        Assert.Equal(PlayerProfileState.Available, profile.Validate(PlayerWire.Id));
        var row = profile.Scores[0];
        Assert.Equal(900_000, row.ValidAccuracy);
        Assert.Equal(900_000, row.ValidScores![0].Accuracy);
        Assert.Equal(2, row.ValidScores[0].RankTiers![0].Rank);
        Assert.Equal("Trimmed", (profile with { DisplayName = " Trimmed " }).Normalized().DisplayName);
    }

    [Fact]
    public void Payload_SelectableOnlyWhenHeaderVerifiedAndCurrent()
    {
        var profile = new PlayerProfileResponse { AccountId = PlayerWire.Id };
        Assert.True(new PlayerProfilePayload(profile, PlayerProfileState.Available, 7, 7).IsSelectable(7));
        Assert.False(new PlayerProfilePayload(profile, PlayerProfileState.Available, null, 7).IsSelectable(7));
        Assert.False(new PlayerProfilePayload(profile, PlayerProfileState.Available, 6, 7).IsSelectable(7));
        Assert.False(new PlayerProfilePayload(profile, PlayerProfileState.Syncing, 7, 7).IsSelectable(7));
    }

    [Fact]
    public void Stats_OverallCountsUniqueSongsAcrossVisibleChartsOnly()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.DefaultProfile()), PlayerJsonContext.Default.PlayerProfileResponse);
        var all = PlayerStatistics.Overall(profile, InstrumentInfo.All);
        Assert.Equal(3, all.SongsPlayed);
        Assert.Equal(2, all.FullComboCount);
        Assert.Equal(50, all.FullComboPercent);
        Assert.Equal(2, all.GoldStarCount);
        Assert.Equal((990_000 + 950_000 + 1_000_000) / 3.0, all.AverageAccuracy);
        Assert.Equal(1, all.BestRank);
        Assert.Equal("s1", all.BestRankSongId);
        Assert.Equal(Instrument.Lead, all.BestRankInstrument);
        Assert.Equal("#1", all.BestRankText);
        Assert.Equal("2 (50%)", all.FullComboText);

        var bassOnly = PlayerStatistics.Overall(profile, [Instrument.Bass]);
        Assert.Equal(1, bassOnly.SongsPlayed);
        Assert.Null(bassOnly.AverageAccuracy);
        Assert.Equal("—", bassOnly.AverageAccuracyText);
        Assert.Equal("—", bassOnly.BestRankText);
        Assert.Equal("0", bassOnly.FullComboText);
        Assert.Equal("3", (bassOnly with { FullComboCount = 3, FullComboPercent = 100 }).FullComboText);

        var none = PlayerStatistics.Overall(profile, []);
        Assert.Equal(0, none.SongsPlayed);
        Assert.Equal(0, none.FullComboPercent);
    }

    [Fact]
    public void Stats_InstrumentAndFlooredPercent()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.Profile(PlayerWire.Id, "N",
            PlayerWire.Score("a", fc: true), PlayerWire.Score("b"), PlayerWire.Score("c"), PlayerWire.Score("d", "02", st: 6))),
            PlayerJsonContext.Default.PlayerProfileResponse);
        var lead = PlayerStatistics.ForInstrument(profile, Instrument.Lead);
        Assert.Equal(3, lead.SongsPlayed);
        Assert.Equal(33.3, lead.FullComboPercent);
        Assert.Equal(3, lead.FiveStarCount);
        Assert.Equal(0, lead.GoldStarCount);
        Assert.Contains("33.3", lead.FullComboText);
        Assert.Equal(0, PlayerStatistics.ForInstrument(profile, Instrument.Drums).SongsPlayed);
        Assert.Equal("5", lead.AverageStarsText);
        Assert.False(lead.AverageStarsGold);
        var bass = PlayerStatistics.ForInstrument(profile, Instrument.Bass);
        Assert.True(bass.AverageStarsGold);
        Assert.Equal("5 gold stars", bass.AverageStarsText);
        Assert.Equal("—", PlayerStatistics.ForInstrument(profile, Instrument.Drums).AverageStarsText);
    }

    [Fact]
    public void Stats_AverageStarsLikeWebFormatClamped2()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.Profile(PlayerWire.Id, "N",
            PlayerWire.Score("a", st: 6), PlayerWire.Score("b", st: 5), PlayerWire.Score("c", st: 5), PlayerWire.Score("d", st: null))),
            PlayerJsonContext.Default.PlayerProfileResponse);
        var lead = PlayerStatistics.ForInstrument(profile, Instrument.Lead);
        Assert.Equal(16 / 3.0, lead.AverageStars, 6);
        Assert.Equal(5.33.ToString("0.##", System.Globalization.CultureInfo.CurrentCulture), lead.AverageStarsText);
    }

    [Fact]
    public void Stats_PercentileBucketsMatchWebThresholds()
    {
        var profile = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.Profile(PlayerWire.Id, "N",
            PlayerWire.Score("a", rk: 1, te: 100), PlayerWire.Score("b", rk: 5, te: 100), PlayerWire.Score("c", rk: 6, te: 100),
            PlayerWire.Score("d", rk: 100, te: 100), PlayerWire.Score("e", rk: null), PlayerWire.Score("f", rk: 1, te: 0),
            PlayerWire.Score("g", "02", rk: 1, te: 1))), PlayerJsonContext.Default.PlayerProfileResponse);
        var buckets = PlayerStatistics.PercentileBuckets(profile, Instrument.Lead);
        Assert.Equal([1, 5, 10, 100], buckets.Select(b => b.TopPercent));
        Assert.All(buckets, b => Assert.Equal(1, b.Count));
        Assert.True(buckets[1].IsTopFive);
        Assert.False(buckets[2].IsTopFive);
        Assert.Equal("Top 10%", buckets[2].Label);
    }

    [Fact]
    public void Ranking_ValidatesAndFormats()
    {
        var ranking = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.Ranking(rank: 12, total: 400, score: 1234567)),
            PlayerJsonContext.Default.PlayerInstrumentRanking);
        ranking.Validate(Instrument.Lead, PlayerWire.Id.ToUpperInvariant());
        (ranking with { Instrument = "Solo_Guitar" }).Validate(Instrument.Lead, PlayerWire.Id);
        Assert.Throws<FestivalApiException>(() => (ranking with { Instrument = "Solo_Bass" }).Validate(Instrument.Lead, PlayerWire.Id));
        Assert.Throws<FestivalApiException>(() => ranking.Validate(Instrument.Lead, PlayerWire.Other));
        Assert.Throws<FestivalApiException>(() => (ranking with { TotalRankedAccounts = -1 }).Validate(Instrument.Lead, PlayerWire.Id));
        Assert.Equal(0.03, ranking.TotalScorePercentile);
        Assert.True(ranking.IsTopFive);
        Assert.Equal("Top 3%", ranking.PercentileText);
        Assert.Equal("#12", ranking.RankText);
        Assert.Equal(1234567.ToString("N0", System.Globalization.CultureInfo.CurrentCulture), ranking.TotalScoreText);
        var unranked = ranking with { TotalScoreRank = 0 };
        Assert.Null(unranked.TotalScorePercentile);
        Assert.False(unranked.IsTopFive);
        Assert.Equal("—", unranked.PercentileText);
        Assert.Throws<FestivalApiException>(() => FestivalApiClient.Decode("""{"accountId":"a","totalScore":1}"""u8.ToArray(), PlayerJsonContext.Default.PlayerInstrumentRanking));
    }

    [Theory]
    [InlineData(0.00001, "Top 0.01%")]
    [InlineData(0.005, "Top 0.50%")]
    [InlineData(0.25, "Top 25%")]
    [InlineData(2.0, "Top 100%")]
    [InlineData(double.NaN, "N/A")]
    public void TopPercent_FormatsLikeWeb(double fraction, string expected) =>
        Assert.Equal(expected.Replace(".", System.Globalization.CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator),
            PlayerRankingText.TopPercent(fraction));

    [Fact]
    public void RankAxis_PadsAndNeverShowsZero()
    {
        var axis = PlayerRankingText.RankAxis([1, 1]);
        Assert.Equal(1, axis.Best);
        Assert.Equal(2, axis.Worst);
        Assert.Equal([1, 2], axis.Ticks);
        var wide = PlayerRankingText.RankAxis([10, 90]);
        Assert.Equal((1, 100), (wide.Best, wide.Worst));
        Assert.Equal([1, 34, 67, 100], wide.Ticks);
        Assert.True(wide.Ticks.Count <= 4);
        Assert.Equal((1, 2), (PlayerRankingText.RankAxis([]).Best, PlayerRankingText.RankAxis([]).Worst));
    }

    [Fact]
    public void RankHistory_ValidatesOrdersAndSummarizes()
    {
        var history = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.RankHistory(PlayerWire.Id, "Solo_Guitar",
            PlayerWire.Snapshot("2026-09-03", 8), PlayerWire.Snapshot("2026-09-01", 12), PlayerWire.Snapshot("2026-09-02", 0))),
            PlayerJsonContext.Default.PlayerRankHistory);
        history.Validate(Instrument.Lead, PlayerWire.Id);
        var ranked = history.RankedChronological;
        Assert.Equal(["2026-09-01", "2026-09-03"], ranked.Select(r => r.SnapshotDate));
        Assert.Equal(new DateOnly(2026, 9, 1), ranked[0].Date);
        Assert.Equal("2 daily snapshots. Latest rank 8, up 4 places.", PlayerRankingText.RankTrend(ranked));
        Assert.Contains("down 4", PlayerRankingText.RankTrend([.. ranked.AsEnumerable().Reverse()]));
        Assert.Contains("unchanged", PlayerRankingText.RankTrend([ranked[0]]));
        Assert.Equal("No snapshots", PlayerRankingText.RankTrend([]));

        Assert.Throws<FestivalApiException>(() => history.Validate(Instrument.Bass, PlayerWire.Id));
        Assert.Throws<FestivalApiException>(() => history.Validate(Instrument.Lead, PlayerWire.Other));
        Assert.Throws<FestivalApiException>(() => (history with { History = [history.History[0], history.History[0]] }).Validate(Instrument.Lead, PlayerWire.Id));
        Assert.Throws<FestivalApiException>(() => (history with { History = [history.History[0] with { SnapshotDate = "2026-13-01" }] }).Validate(Instrument.Lead, PlayerWire.Id));
        Assert.Throws<FestivalApiException>(() => (history with { History = [history.History[0] with { TotalScoreRank = -1 }] }).Validate(Instrument.Lead, PlayerWire.Id));
    }

    [Fact]
    public void History_ValidatesFiltersAndFormats()
    {
        var response = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(PlayerWire.History(PlayerWire.Id,
            PlayerWire.HistoryEntry(), PlayerWire.HistoryEntry("s2"), PlayerWire.HistoryEntry(ins: "Solo_Bass"))),
            PlayerJsonContext.Default.PlayerHistoryResponse);
        response.Validate(PlayerWire.Id.ToUpperInvariant());
        var payload = new PlayerHistoryPayload(response, PlayerHistoryState.Available);
        Assert.Single(payload.Entries("s1", Instrument.Lead));
        Assert.Throws<FestivalApiException>(() => response.Validate(PlayerWire.Other));
        Assert.Throws<FestivalApiException>(() => (response with { Count = 9 }).Validate(PlayerWire.Id));

        var entry = response.History[0];
        Assert.Equal("2026-09-01T10:00:00Z", entry.DateKey);
        Assert.Equal(new DateTimeOffset(2026, 9, 1, 10, 0, 0, TimeSpan.Zero), entry.DisplayDate);
        Assert.NotEmpty(entry.DateText);
        var noAchieved = entry with { ScoreAchievedAt = null, ChangedAt = "garbage" };
        Assert.Null(noAchieved.DisplayDate);
        Assert.Equal("garbage", noAchieved.DateText);
    }

    [Fact]
    public void HistorySort_ModesDirectionsTiesAndHighScore()
    {
        ScoreHistoryEntry E(long score, double? acc = 0, bool fc = false, int? season = 1, string date = "2026-01-01") =>
            new() { NewScore = score, Accuracy = acc, IsFullCombo = fc, Season = season, ScoreAchievedAt = date, ChangedAt = date };
        var a = E(100, 90, false, 2, "2026-01-03");
        var b = E(300, 90, true, 1, "2026-01-01");
        var c = E(200, 95, false, null, "2026-01-02");
        var d = E(300, 90, true, 1, "2026-01-04");
        var rows = new[] { a, b, c, d };

        Assert.Equal([b, d, c, a], PlayerScoreHistorySort.Sorted(rows, PlayerScoreSortMode.Score, false));
        Assert.Equal([a, c, b, d], PlayerScoreHistorySort.Sorted(rows, PlayerScoreSortMode.Score, true));
        Assert.Equal([b, c, a, d], PlayerScoreHistorySort.Sorted(rows, PlayerScoreSortMode.Date, true));
        Assert.Equal([c, d, b, a], PlayerScoreHistorySort.Sorted(rows, PlayerScoreSortMode.Accuracy, false));
        Assert.Equal([c, b, d, a], PlayerScoreHistorySort.Sorted(rows, PlayerScoreSortMode.Season, true));
        Assert.Equal("Accuracy", PlayerScoreSortMode.Accuracy.Label());

        Assert.Null(PlayerScoreHistorySort.HighScoreIndex([]));
        Assert.Equal(1, PlayerScoreHistorySort.HighScoreIndex([a, b, c, d]));
        Assert.Equal(0, PlayerScoreHistorySort.HighScoreIndex([d, a]));
    }
}

public class PlayerClientTests
{
    [Fact]
    public async Task Profile_KeylessHeaderlessReadWithProvenance()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var payload = await service.Client().GetPlayerProfileAsync(PlayerWire.Id);
        Assert.Equal(PlayerProfileState.Available, payload.State);
        Assert.Equal(7, payload.PublicationId);
        Assert.Equal(7, payload.ObservedPublicationId);
        Assert.Equal("Fixture One", payload.Profile.DisplayName);
        var sent = Assert.Single(service.Handler.To($"/api/player/{PlayerWire.Id}"));
        Assert.Equal(HttpMethod.Get, sent.Method);
        Assert.DoesNotContain(sent.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) ||
                                                      k.Equals("x-api-key", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Profile_SyncingHeaderlessAndMismatches()
    {
        var service = new FakeService();
        PlayerWire.Install(service, new()
        {
            [PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing()),
            [PlayerWire.Other] = (HttpStatusCode.OK, PlayerWire.Syncing(PlayerWire.Other)),
            ["fixtureplayer3"] = (HttpStatusCode.Accepted, PlayerWire.DefaultProfile("fixtureplayer3")),
        }, header: false);
        var client = service.Client();
        var syncing = await client.GetPlayerProfileAsync(PlayerWire.Id);
        Assert.Equal(PlayerProfileState.Syncing, syncing.State);
        Assert.Null(syncing.PublicationId);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerProfileAsync(PlayerWire.Other))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerProfileAsync("fixtureplayer3"))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerProfileAsync("bad/id"))).Kind);
        var notFound = await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerProfileAsync("fixtureplayer9"));
        Assert.Equal(404, notFound.StatusCode);
    }

    [Fact]
    public async Task Profile_HeaderlessWhilePinnedIsRejected()
    {
        var service = new FakeService();
        PlayerWire.Install(service, header: false);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath == "/api/publication" ? Wire.Ok(Wire.Publication(7, pinning: true)) : inner(r);
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPlayerProfileAsync(PlayerWire.Id));
        Assert.Equal(FestivalApiErrorKind.InvalidPublication, error.Kind);
    }

    [Fact]
    public async Task Profile_ReusesSamePublicationETagBody()
    {
        var service = new FakeService();
        var calls = 0;
        service.Override = r =>
        {
            if (!r.RequestUri!.AbsolutePath.StartsWith("/api/player/", StringComparison.Ordinal)) return null;
            calls++;
            return r.Headers.TryGetValues("If-None-Match", out _)
                ? Wire.Response(HttpStatusCode.NotModified, "", ("X-FST-Publication-Id", "7"))
                : Wire.Ok(PlayerWire.DefaultProfile(), ("X-FST-Publication-Id", "7"), ("ETag", "\"p\""));
        };
        var client = service.Client();
        await client.GetPlayerProfileAsync(PlayerWire.Id);
        var again = await client.GetPlayerProfileAsync(PlayerWire.Id);
        Assert.Equal(2, calls);
        Assert.Equal(4, again.Profile.Scores.Count);
        Assert.Equal(7, again.PublicationId);
    }

    [Fact]
    public async Task Ranking_AvailableUnrankedAndErrors()
    {
        var service = new FakeService();
        var status = HttpStatusCode.OK;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/rankings/", StringComparison.Ordinal)
            ? Wire.Response(status, status == HttpStatusCode.OK ? PlayerWire.Ranking() : "{}", ("X-FST-Publication-Id", "7"))
            : null;
        var client = service.Client();
        var available = await client.GetPlayerInstrumentRankingAsync(Instrument.Bass, PlayerWire.Id);
        Assert.Equal(PlayerRankingState.Available, available.State);
        Assert.Equal(12, available.Ranking!.TotalScoreRank);
        Assert.Single(service.Handler.To($"/api/rankings/Solo_Bass/{PlayerWire.Id}"));

        status = HttpStatusCode.NotFound;
        var unranked = await client.GetPlayerInstrumentRankingAsync(Instrument.Bass, PlayerWire.Id);
        Assert.Equal(PlayerRankingState.Unranked, unranked.State);
        Assert.Null(unranked.Ranking);

        status = HttpStatusCode.InternalServerError;
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerInstrumentRankingAsync(Instrument.Bass, PlayerWire.Id));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerInstrumentRankingAsync(Instrument.Bass, "a/b"));
    }

    [Fact]
    public async Task RankHistory_ReadsWithDaysAndRejectsBadArguments()
    {
        var service = new FakeService();
        service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)
            ? Wire.Ok(PlayerWire.RankHistory(PlayerWire.Id, "Solo_Drums", PlayerWire.Snapshot("2026-09-01", 3)), ("X-FST-Publication-Id", "7"))
            : null;
        var client = service.Client();
        var history = await client.GetPlayerRankHistoryAsync(Instrument.Drums, PlayerWire.Id);
        Assert.Single(history.History);
        Assert.Equal("?days=30", service.Handler.To($"/api/rankings/Solo_Drums/{PlayerWire.Id}/history").Single().Uri.Query);
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerRankHistoryAsync(Instrument.Drums, PlayerWire.Id, 0));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerRankHistoryAsync(Instrument.Lead, PlayerWire.Id));
    }

    [Fact]
    public async Task History_AvailableSyncingUnregisteredAndErrors()
    {
        var service = new FakeService();
        var status = HttpStatusCode.OK;
        service.Override = r =>
        {
            if (!r.RequestUri!.AbsolutePath.EndsWith("/history", StringComparison.Ordinal)) return null;
            var body = status switch
            {
                HttpStatusCode.OK => PlayerWire.History(PlayerWire.Id, PlayerWire.HistoryEntry()),
                HttpStatusCode.Accepted => """{"accountId":"fixtureplayer1","status":"syncing","notYetPublished":true,"count":0,"history":[]}""",
                _ => """{"error":"Score history is only available for registered users."}""",
            };
            return Wire.Response(status, body, ("X-FST-Publication-Id", "7"));
        };
        var client = service.Client();
        var available = await client.GetPlayerHistoryAsync(PlayerWire.Id, "s1", Instrument.Lead);
        Assert.Equal(PlayerHistoryState.Available, available.State);
        Assert.Single(available.Entries("s1", Instrument.Lead));
        var query = service.Handler.To($"/api/player/{PlayerWire.Id}/history").Single().Uri.Query;
        Assert.Equal("?songId=s1&instrument=Solo_Guitar", query);

        status = HttpStatusCode.Accepted;
        Assert.Equal(PlayerHistoryState.Syncing, (await client.GetPlayerHistoryAsync(PlayerWire.Id, "s1", Instrument.Lead)).State);
        status = HttpStatusCode.NotFound;
        var unregistered = await client.GetPlayerHistoryAsync(PlayerWire.Id, "s1", Instrument.Lead);
        Assert.Equal(PlayerHistoryState.Unregistered, unregistered.State);
        Assert.Empty(unregistered.Entries("s1", Instrument.Lead));
        status = HttpStatusCode.ServiceUnavailable;
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerHistoryAsync(PlayerWire.Id, "s1", Instrument.Lead));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerHistoryAsync(PlayerWire.Id, "a/b", Instrument.Lead));
    }
}

public class SelectedProfileSessionTests
{
    private static FestivalSession Session(FakeService service, SelectedPlayer? player = null) =>
        service.Session(settings: new AppSettings { SelectedPlayer = player });

    [Fact]
    public async Task Load_NoPlayerIsNone()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var session = Session(service);
        await session.LoadSelectedProfileAsync();
        Assert.Equal(SelectedProfileStatus.None, session.SelectedProfileStatus);
        Assert.Null(session.SelectedScoreIndex);
        Assert.False(session.IsSelectedProfileCurrent);
    }

    [Fact]
    public async Task Load_RestoredPlayerLoadsOncePerPublication()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var session = Session(service, new SelectedPlayer(PlayerWire.Id, "Fixture One"));
        var changes = new List<string?>();
        session.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        await session.LoadSelectedProfileAsync();
        Assert.Equal(SelectedProfileStatus.Available, session.SelectedProfileStatus);
        Assert.Equal(7, session.SelectedProfilePublicationId);
        Assert.True(session.IsSelectedProfileCurrent);
        Assert.Equal(1000, session.SelectedScoreIndex!["s1"][Instrument.Lead].Score);
        Assert.Contains(nameof(FestivalSession.SelectedScoreIndex), changes);

        await session.LoadSelectedProfileAsync();
        Assert.Single(service.Handler.To($"/api/player/{PlayerWire.Id}"));

        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        Assert.False(session.IsSelectedProfileCurrent);
        await session.LoadSelectedProfileAsync();
        Assert.Equal(2, service.Handler.To($"/api/player/{PlayerWire.Id}").Count());
        Assert.Equal(8, session.SelectedProfilePublicationId);

        await session.LoadSelectedProfileAsync(force: true);
        Assert.Equal(3, service.Handler.To($"/api/player/{PlayerWire.Id}").Count());
    }

    [Fact]
    public async Task Load_SyncingAndFailureNeverLookLikeEmptySuccess()
    {
        var service = new FakeService();
        PlayerWire.Install(service, new() { [PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing()) });
        var session = Session(service, new SelectedPlayer(PlayerWire.Id, "Fixture One"));
        await session.LoadSelectedProfileAsync();
        Assert.Equal(SelectedProfileStatus.Syncing, session.SelectedProfileStatus);
        Assert.Null(session.SelectedScoreIndex);
        Assert.False(session.IsSelectedProfileCurrent);

        PlayerWire.Install(service, new() { [PlayerWire.Id] = (HttpStatusCode.ServiceUnavailable, "{}") });
        await session.LoadSelectedProfileAsync(force: true);
        Assert.Equal(SelectedProfileStatus.Failed, session.SelectedProfileStatus);
        Assert.Equal(ServiceIssueKind.Unavailable, session.SelectedProfileIssue!.Kind);
        Assert.Null(session.SelectedProfile);
    }

    [Fact]
    public async Task SelectSwitchDeselect_ClearsEarlierScoresAndRejectsUnverified()
    {
        var service = new FakeService();
        PlayerWire.Install(service);
        var session = Session(service);
        var viewed = await session.ViewPlayerAsync(PlayerWire.Id);
        Assert.Equal(SelectedProfileStatus.None, session.SelectedProfileStatus);
        Assert.True(session.SelectPlayer(viewed, "Fixture One"));
        Assert.Equal(PlayerWire.Id, session.SelectedPlayer!.AccountId);
        Assert.Equal(SelectedProfileStatus.Available, session.SelectedProfileStatus);
        Assert.Empty(service.Handler.To($"/api/player/{PlayerWire.Id}").Skip(1));

        var other = await session.ViewPlayerAsync(PlayerWire.Other);
        Assert.False(session.SelectPlayer(other with { PublicationId = null }, "Two"));
        Assert.False(session.SelectPlayer(other, "  "));
        Assert.Equal(PlayerWire.Id, session.SelectedPlayer!.AccountId);
        Assert.True(session.SelectPlayer(other, "Fixture Two"));
        Assert.Equal(PlayerWire.Other, session.SelectedProfile!.Profile.AccountId);

        session.DeselectPlayer();
        Assert.Equal(SelectedProfileStatus.None, session.SelectedProfileStatus);
        Assert.Null(session.SelectedProfile);
        Assert.Null(session.SelectedScoreIndex);
    }

    [Fact]
    public async Task Load_LateResultForPreviousAccountIsDropped()
    {
        var service = new FakeService();
        var release = new TaskCompletionSource();
        service.Handler.Responder = async (request, token) =>
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/publication") return Wire.Ok(Wire.Publication());
            if (path == $"/api/player/{PlayerWire.Id}") await release.Task;
            var id = path.Split('/')[^1];
            return Wire.Ok(PlayerWire.DefaultProfile(id), ("X-FST-Publication-Id", "7"));
        };
        var session = Session(service, new SelectedPlayer(PlayerWire.Id, "One"));
        var slow = session.LoadSelectedProfileAsync();
        await Async.Until(() => session.SelectedProfileStatus == SelectedProfileStatus.Loading);
        await session.LoadSelectedProfileAsync();
        session.UpdateSettings(s => s with { SelectedPlayer = new SelectedPlayer(PlayerWire.Other, "Two") });
        Assert.Equal(SelectedProfileStatus.None, session.SelectedProfileStatus);
        release.SetResult();
        await slow;
        Assert.Null(session.SelectedProfile);
        await session.LoadSelectedProfileAsync();
        Assert.Equal(PlayerWire.Other, session.SelectedProfile!.Profile.AccountId);

        session.UpdateSettings(s => s with { ReduceMotion = true });
        Assert.Equal(SelectedProfileStatus.Available, session.SelectedProfileStatus);
    }

    [Fact]
    public async Task Load_FailureForSupersededAccountIsIgnored()
    {
        var service = new FakeService();
        var release = new TaskCompletionSource();
        service.Handler.Responder = async (request, token) =>
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/publication") return Wire.Ok(Wire.Publication());
            await release.Task;
            return Wire.Response(HttpStatusCode.InternalServerError);
        };
        var session = Session(service, new SelectedPlayer(PlayerWire.Id, "One"));
        var load = session.LoadSelectedProfileAsync();
        await Async.Until(() => session.SelectedProfileStatus == SelectedProfileStatus.Loading);
        session.DeselectPlayer();
        release.SetResult();
        await load;
        Assert.Equal(SelectedProfileStatus.None, session.SelectedProfileStatus);
        Assert.Null(session.SelectedProfileIssue);
    }
}
