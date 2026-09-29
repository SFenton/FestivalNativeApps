using System.Globalization;
using System.Net;

namespace Festival.Core.Tests;

/// <summary>Synthetic rankings payloads (captured shapes from <c>tools/mock_service.py</c>, no production data).</summary>
public static class RankingsWire
{
    public static string Entry(int rank, string? accountId = null, string? name = null, bool raw = false) =>
        string.Create(CultureInfo.InvariantCulture,
            $$"""{"accountId":"{{accountId ?? $"acct{rank}"}}","displayName":{{(name is null ? $"\"Player {rank}\"" : name == "" ? "null" : $"\"{name}\"")}},"songsPlayed":{{40 - rank}},"totalChartedSongs":50,"coverage":0.8,"rawSkillRating":0.0{{rank}},"adjustedSkillRating":0.1{{rank}},"adjustedSkillRank":{{rank}},"weightedRating":0.2{{rank}},"weightedRank":{{rank + 1}},"fcRate":0.5,"fcRateRank":{{rank + 2}},"totalScore":{{90_000_000 - rank}},"totalScoreRank":{{rank}},"maxScorePercent":0.9{{rank}},"maxScorePercentRank":{{rank + 3}},"avgAccuracy":0.99,"fullComboCount":{{20 - rank}},"avgStars":4.9,"bestRank":1,"avgRank":{{rank}}.5{{(raw ? ",\"rawWeightedRating\":0.33,\"rawMaxScorePercent\":0.8" : "")}}}""");

    public static string Board(string instrument, int page, int pageSize, int total, IEnumerable<int> ranks, string rankBy = "totalscore") =>
        $$"""{"instrument":"{{instrument}}","rankBy":"{{rankBy}}","page":{{page}},"pageSize":{{pageSize}},"totalAccounts":{{total}},"entries":[{{string.Join(",", ranks.Select(r => Entry(r)))}}]}""";

    public static string BandEntry(int rank) =>
        $$"""{"bandId":"band{{rank}}","teamKey":"team{{rank}}","teamMembers":[{"accountId":"m{{rank}}a","displayName":"Member A"},{"accountId":"m{{rank}}b","displayName":null}],"songsPlayed":{{30 - rank}},"totalChartedSongs":50,"coverage":0.6,"rawSkillRating":0.04,"adjustedSkillRating":0.14,"adjustedSkillRank":{{rank}},"weightedRating":0.05,"weightedRank":{{rank + 1}},"fcRate":0.4,"fcRateRank":{{rank + 2}},"totalScore":{{50_000_000 - rank}},"totalScoreRank":{{rank}},"avgAccuracy":0.95,"fullComboCount":{{10 - rank}},"avgStars":4.5,"bestRank":1,"avgRank":{{rank}}}""";

    public static string BandBoard(string bandType, int page, int pageSize, int total, IEnumerable<int> ranks) =>
        $$"""{"bandType":"{{bandType}}","rankBy":"totalscore","page":{{page}},"pageSize":{{pageSize}},"totalTeams":{{total}},"entries":[{{string.Join(",", ranks.Select(BandEntry))}}]}""";

    public static AccountRankingEntry Account(int rank, string? accountId = null) =>
        System.Text.Json.JsonSerializer.Deserialize(Entry(rank, accountId), TestJson.Default.AccountRankingEntry)!;
}

[System.Text.Json.Serialization.JsonSerializable(typeof(AccountRankingEntry))]
internal sealed partial class TestJson : System.Text.Json.Serialization.JsonSerializerContext;

public sealed class RankingMetricTests
{
    [Fact]
    public void ServiceIdsLabelsAndParsingRoundTrip()
    {
        Assert.Equal(RankingMetric.TotalScore, RankingMetricInfo.All[0]);
        foreach (var metric in RankingMetricInfo.All)
        {
            Assert.True(RankingMetricInfo.TryParse(metric.ServiceId(), out var parsed));
            Assert.Equal(metric, parsed);
            Assert.False(string.IsNullOrEmpty(metric.Label()));
        }
        Assert.Equal(["totalscore", "adjusted", "weighted", "fcrate", "maxscore"], RankingMetricInfo.All.Select(m => m.ServiceId()));
        Assert.Equal(["Total Score", "Adjusted", "Weighted", "FC Rate", "Max Score"], RankingMetricInfo.All.Select(m => m.Label()));
        Assert.False(RankingMetricInfo.TryParse("TotalScore", out var fallback));
        Assert.Equal(RankingMetric.TotalScore, fallback);
        Assert.Equal(RankingMetric.FcRate, RankingMetricInfo.Coerce("fcrate"));
        Assert.Equal(RankingMetric.TotalScore, RankingMetricInfo.Coerce(null));
    }

    [Fact]
    public void BandNarrowingFallsBackToTotalScore()
    {
        Assert.Equal(BandRankingMetric.Adjusted, RankingMetric.Adjusted.ToBandMetric());
        Assert.Equal(BandRankingMetric.Weighted, RankingMetric.Weighted.ToBandMetric());
        Assert.Equal(BandRankingMetric.FcRate, RankingMetric.FcRate.ToBandMetric());
        Assert.Equal(BandRankingMetric.TotalScore, RankingMetric.TotalScore.ToBandMetric());
        Assert.Equal(BandRankingMetric.TotalScore, RankingMetric.MaxScore.ToBandMetric());
        foreach (var band in BandRankingMetricInfo.All) Assert.Equal(band, band.ToRankingMetric().ToBandMetric());
        Assert.True(RankingMetric.Adjusted.IsPercentile());
        Assert.True(RankingMetric.Weighted.IsPercentile());
        Assert.False(RankingMetric.MaxScore.IsPercentile());
    }
}

public sealed class RankingFormattingTests
{
    public RankingFormattingTests() => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");

    [Fact]
    public void FormatsEachMetricLikeTheWeb()
    {
        Assert.Equal("Top 3%", RankingFormatting.Rating(0.03, RankingMetric.Adjusted));
        Assert.Equal("Top 0.30%", RankingFormatting.Rating(0.003, RankingMetric.Weighted));
        Assert.Equal("Top 0.01%", RankingFormatting.Percentile(0));
        Assert.Equal("Top 100%", RankingFormatting.Percentile(2));
        Assert.Equal("97.3%", RankingFormatting.Rating(0.973, RankingMetric.FcRate));
        Assert.Equal("50.0%", RankingFormatting.Rating(0.5, RankingMetric.MaxScore));
        Assert.Equal("12,345,679", RankingFormatting.Rating(12_345_678.5, RankingMetric.TotalScore));
        Assert.Equal("N/A", RankingFormatting.Percentile(double.NaN));
        Assert.Equal("N/A", RankingFormatting.Percentage(double.PositiveInfinity));
        Assert.Equal("N/A", RankingFormatting.WholeNumber(double.NaN));
    }

    [Theory]
    [InlineData(0.05, "0.05")]
    [InlineData(0.0512, "0.0512")]
    [InlineData(0.0, "0.0")]
    [InlineData(0.5, "0.50")]
    [InlineData(12.34, "12.3")]
    [InlineData(double.NaN, "N/A")]
    public void BayesianTrimsByMagnitude(double value, string expected) => Assert.Equal(expected, RankingFormatting.Bayesian(value));

    [Theory]
    [InlineData(1, "1st")]
    [InlineData(2, "2nd")]
    [InlineData(3, "3rd")]
    [InlineData(4, "4th")]
    [InlineData(11, "11th")]
    [InlineData(12, "12th")]
    [InlineData(13, "13th")]
    [InlineData(21, "21st")]
    [InlineData(112, "112th")]
    [InlineData(1234, "1,234th")]
    public void OrdinalsUseEnglishSuffixes(int rank, string expected) => Assert.Equal(expected, RankingFormatting.Ordinal(rank));

    [Fact]
    public void SongsLabelGroups() => Assert.Equal("1,200 / 1,500", RankingFormatting.Songs(1200, 1500));
}

public sealed class LeaderboardPagingTests
{
    [Theory]
    [InlineData(0, 25, 1)]
    [InlineData(-5, 25, 1)]
    [InlineData(25, 25, 1)]
    [InlineData(26, 25, 2)]
    [InlineData(10, 0, 10)]
    public void PageCountIsAtLeastOne(long total, int size, int expected) => Assert.Equal(expected, LeaderboardPaging.PageCount(total, size));

    [Fact]
    public void PageCountSaturates() => Assert.Equal(int.MaxValue, LeaderboardPaging.PageCount(long.MaxValue, 1));

    [Theory]
    [InlineData(1, 1)]
    [InlineData(25, 1)]
    [InlineData(26, 2)]
    [InlineData(0, 1)]
    [InlineData(-3, 1)]
    public void PageForRank(int rank, int page) => Assert.Equal(page, LeaderboardPaging.PageForRank(rank));

    [Fact]
    public void CorrectedClamps()
    {
        Assert.Equal(1, LeaderboardPaging.Corrected(0, 5));
        Assert.Equal(5, LeaderboardPaging.Corrected(9, 5));
        Assert.Equal(1, LeaderboardPaging.Corrected(3, 0));
        Assert.Equal(3, LeaderboardPaging.Corrected(3, 5));
    }
}

public sealed class RankingSpotlightTests
{
    private static readonly AccountRankingEntry[] Top = [RankingsWire.Account(1, "a1"), RankingsWire.Account(2, "a2")];

    [Fact]
    public void NoSelectionShowsNothing()
    {
        Assert.Equal(SpotlightPlacementKind.None, RankingSpotlight.Place(null, Top, true, null).Kind);
        Assert.Equal(SpotlightPlacementKind.None, RankingSpotlight.Place("  ", Top, true, null).Kind);
    }

    [Fact]
    public void VisibleRowIsHighlightedInPlaceIgnoringCase() =>
        Assert.Equal(SpotlightPlacementKind.Inline, RankingSpotlight.Place("A2", Top, false, null).Kind);

    [Fact]
    public void HiddenRowIsPendingUnrankedOrFooter()
    {
        Assert.Equal(SpotlightPlacementKind.Pending, RankingSpotlight.Place("me", Top, false, null).Kind);
        Assert.Equal(SpotlightPlacementKind.Unranked, RankingSpotlight.Place("me", Top, true, null).Kind);
        var own = RankingsWire.Account(500, "ME");
        var placed = RankingSpotlight.Place("me", Top, true, own);
        Assert.Equal(SpotlightPlacementKind.Footer, placed.Kind);
        Assert.Same(own, placed.Entry);
        Assert.Equal(SpotlightPlacementKind.Pending, RankingSpotlight.Place("me", Top, true, RankingsWire.Account(9, "other")).Kind);
    }

    [Fact]
    public void SameAccountHandlesNulls()
    {
        Assert.False(RankingSpotlight.SameAccount(null, "a"));
        Assert.False(RankingSpotlight.SameAccount("a", null));
        Assert.True(RankingSpotlight.SameAccount("abc", "ABC"));
    }
}

public sealed class RankingsModelTests
{
    public RankingsModelTests() => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");

    [Fact]
    public void AccountEntryDispatchesPerMetric()
    {
        var entry = RankingsWire.Account(3);
        Assert.Equal([3, 3, 4, 5, 6], RankingMetricInfo.All.Select(entry.Rank));
        Assert.Equal(0.03, entry.RatingValue(RankingMetric.Adjusted));
        Assert.Equal(0.23, entry.RatingValue(RankingMetric.Weighted));
        Assert.Equal(17 / 50.0, entry.RatingValue(RankingMetric.FcRate));
        Assert.Equal(89_999_997, entry.RatingValue(RankingMetric.TotalScore));
        Assert.Equal(0.93, entry.RatingValue(RankingMetric.MaxScore));
        Assert.Equal(0.13, entry.BayesianValue(RankingMetric.Adjusted));
        Assert.Equal(0.23, entry.BayesianValue(RankingMetric.Weighted));
        Assert.Null(entry.BayesianValue(RankingMetric.TotalScore));
        Assert.Equal("37 / 50", entry.SongsLabel(RankingMetric.TotalScore));
        Assert.Equal("17 / 50", entry.SongsLabel(RankingMetric.FcRate));
        Assert.Equal("Player 3", entry.Name);
        Assert.Equal("Unknown User", (entry with { DisplayName = " " }).Name);
        Assert.Equal(0, (entry with { TotalChartedSongs = 0 }).RatingValue(RankingMetric.FcRate));
        Assert.Equal(0.5, (entry with { RawWeightedRating = 0.5 }).RatingValue(RankingMetric.Weighted));
    }

    [Fact]
    public void BandEntryDispatchesPerMetric()
    {
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.BandBoard("Band_Trios", 1, 25, 60, [2])),
            RankingsJsonContext.Default.BandRankingsResponse);
        var entry = board.Entries[0];
        Assert.Equal(3, board.PageCount);
        Assert.Equal("Member A, Unknown User", entry.MembersLabel);
        Assert.Equal([2, 3, 4, 2], BandRankingMetricInfo.All.Select(entry.Rank));
        Assert.Equal(0.04, entry.RatingValue(BandRankingMetric.Adjusted));
        Assert.Equal(0.05, entry.RatingValue(BandRankingMetric.Weighted));
        Assert.Equal(0.7, (entry with { RawWeightedRating = 0.7 }).RatingValue(BandRankingMetric.Weighted));
        Assert.Equal(8 / 50.0, entry.RatingValue(BandRankingMetric.FcRate));
        Assert.Equal(0, (entry with { TotalChartedSongs = 0 }).RatingValue(BandRankingMetric.FcRate));
        Assert.Equal(49_999_998, entry.RatingValue(BandRankingMetric.TotalScore));
        Assert.Equal(0.14, entry.BayesianValue(BandRankingMetric.Adjusted));
        Assert.Equal(0.05, entry.BayesianValue(BandRankingMetric.Weighted));
        Assert.Null(entry.BayesianValue(BandRankingMetric.FcRate));
        Assert.Equal("28 / 50", entry.SongsLabel(BandRankingMetric.TotalScore));
        Assert.Equal("8 / 50", entry.SongsLabel(BandRankingMetric.FcRate));
        Assert.Equal("", (entry with { TeamMembers = null! }).MembersLabel);
    }

    [Fact]
    public void ValidationRejectsMismatchedOrCorruptBoards()
    {
        var good = new RankingsResponse { Instrument = "Solo_Bass", Page = 1, PageSize = 2, TotalAccounts = 2, Entries = [RankingsWire.Account(1)] };
        good.Validate(Instrument.Bass);
        Assert.Throws<FestivalApiException>(() => good.Validate(Instrument.Lead));
        Assert.Throws<FestivalApiException>(() => (good with { Page = 0 }).Validate(Instrument.Bass));
        Assert.Throws<FestivalApiException>(() => (good with { PageSize = 0 }).Validate(Instrument.Bass));
        Assert.Throws<FestivalApiException>(() => (good with { TotalAccounts = -1 }).Validate(Instrument.Bass));
        Assert.Throws<FestivalApiException>(() => (good with { Entries = null! }).Validate(Instrument.Bass));
        Assert.Throws<FestivalApiException>(() => (good with { PageSize = 1, Entries = [RankingsWire.Account(1), RankingsWire.Account(2)] }).Validate(Instrument.Bass));
        // Production serves rows with an empty account ID: accepted, but without a profile link.
        (good with { Entries = [RankingsWire.Account(1, "")] }).Validate(Instrument.Bass);
        Assert.False(RankingsWire.Account(1, "").HasProfile);
        Assert.False(RankingsWire.Account(1, "bad/id").HasProfile);
        Assert.True(RankingsWire.Account(1, "ok").HasProfile);

        var band = new BandRankingsResponse { BandType = "Band_Duets", Page = 1, PageSize = 1, TotalTeams = 1 };
        band.Validate(BandType.Duets);
        Assert.Throws<FestivalApiException>(() => band.Validate(BandType.Quad));
        Assert.Throws<FestivalApiException>(() => (band with { Page = 0 }).Validate(BandType.Duets));
        Assert.Throws<FestivalApiException>(() => (band with { PageSize = 0 }).Validate(BandType.Duets));
        Assert.Throws<FestivalApiException>(() => (band with { TotalTeams = -1 }).Validate(BandType.Duets));
        Assert.Throws<FestivalApiException>(() => (band with { Entries = null! }).Validate(BandType.Duets));
        (band with { Entries = [new BandRankingEntry { BandId = "b" }] }).Validate(BandType.Duets);
        Assert.False(new BandRankingEntry { BandId = "b" }.HasDetail);
        Assert.False(new BandRankingEntry { BandId = "b", TeamKey = "a‮b" }.HasDetail);
        Assert.True(new BandRankingEntry { BandId = "b", TeamKey = "t" }.HasDetail);
    }
}

public sealed class RankingsClientTests
{
    private static FakeService Service(Func<HttpRequestMessage, HttpResponseMessage?> route)
    {
        var service = new FakeService();
        service.Override = route;
        return service;
    }

    private static readonly (string, string) Pub = ("X-FST-Publication-Id", "7");

    [Fact]
    public async Task ReadsAccountRankingsWithQueryAndNoForbiddenHeaders()
    {
        var service = Service(r => r.RequestUri!.AbsolutePath == "/api/rankings/Solo_Bass"
            ? Wire.Ok(RankingsWire.Board("Solo_Bass", 2, 25, 60, Enumerable.Range(26, 25), "fcrate"), Pub) : null);
        var board = await service.Client().GetRankingsAsync(Instrument.Bass, RankingMetric.FcRate, 2, 25);
        Assert.Equal(25, board.Entries.Count);
        Assert.Equal(3, board.PageCount);
        var sent = Assert.Single(service.Handler.To("/api/rankings/Solo_Bass"));
        Assert.Equal("?rankBy=fcrate&page=2&pageSize=25", sent.Uri.Query);
        Assert.DoesNotContain(sent.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) ||
                                                       k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task ReadsBandRankings()
    {
        var service = Service(r => r.RequestUri!.AbsolutePath == "/api/rankings/bands/Band_Quad"
            ? Wire.Ok(RankingsWire.BandBoard("Band_Quad", 1, 10, 2, [1, 2]), Pub) : null);
        var board = await service.Client().GetBandRankingsAsync(BandType.Quad, BandRankingMetric.Weighted, 1, 10);
        Assert.Equal(2, board.Entries.Count);
        Assert.Equal("?rankBy=weighted&page=1&pageSize=10", Assert.Single(service.Handler.To("/api/rankings/bands/Band_Quad")).Uri.Query);
    }

    [Fact]
    public async Task RejectsMismatchedInstrumentAndCorruptJson()
    {
        var service = Service(r => r.RequestUri!.AbsolutePath switch
        {
            "/api/rankings/Solo_Drums" => Wire.Ok(RankingsWire.Board("Solo_Bass", 1, 10, 1, [1]), Pub),
            "/api/rankings/Solo_Vocals" => Wire.Ok("{not json", Pub),
            _ => null,
        });
        var client = service.Client();
        var mismatch = await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRankingsAsync(Instrument.Drums, RankingMetric.TotalScore));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, mismatch.Kind);
        var corrupt = await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRankingsAsync(Instrument.Vocals, RankingMetric.TotalScore));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, corrupt.Kind);
    }

    [Fact]
    public async Task ScrapeFreezeSurfacesAsFrozenRead()
    {
        var service = Service(r => r.RequestUri!.AbsolutePath.StartsWith("/api/rankings/", StringComparison.Ordinal)
            ? Wire.Response(HttpStatusCode.ServiceUnavailable, "", ("Retry-After", "30"), ("X-FST-Public-Read-Freeze-Reason", "scrape")) : null);
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetBandRankingsAsync(BandType.Duets, BandRankingMetric.TotalScore));
        Assert.Equal(FestivalApiErrorKind.PublicReadFrozen, error.Kind);
    }

    [Theory]
    [InlineData(0, 25)]
    [InlineData(1, 0)]
    [InlineData(1, 201)]
    public void EndpointsRejectBadPaging(int page, int size)
    {
        var origin = new Uri(Wire.BaseUrl);
        Assert.Throws<FestivalApiException>(() => RankingsEndpoints.Rankings(origin, Instrument.Lead, RankingMetric.TotalScore, page, size));
        Assert.Throws<FestivalApiException>(() => RankingsEndpoints.BandRankings(origin, BandType.Duets, BandRankingMetric.TotalScore, page, size));
    }
}
