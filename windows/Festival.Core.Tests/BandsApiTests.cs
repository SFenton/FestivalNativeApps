using System.Globalization;
using System.Net;

namespace Festival.Core.Tests;

public class BandsApiTests
{
    private static async Task<FestivalApiException> Fails(Func<Task> action) =>
        await Assert.ThrowsAsync<FestivalApiException>(action);

    [Fact]
    public async Task PlayerBands_BuildsUrlDecodesAndPins()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var list = await client.GetPlayerBandsAsync("acc_1", PlayerBandGroup.Trios, 2, 10);
        var sent = bands.Service.Handler.To("/api/player/acc_1/bands").Single();
        Assert.Equal("?group=trios&page=2&pageSize=10", sent.Uri.Query);
        Assert.DoesNotContain(sent.Headers.Keys, h => h.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) || h == "X-API-Key");
        Assert.Equal(30, list.TotalCount);
        Assert.Equal(10, list.Entries.Count);
        Assert.Equal(3, list.PageCount(10));
        Assert.Equal(1, new PlayerBandListResponse().PageCount(25));
        Assert.Equal("b11", list.Entries[0].Key);
        Assert.DoesNotContain(bands.Service.Handler.Requests, r => r.Uri.AbsolutePath.StartsWith("/api/bands", StringComparison.Ordinal));
    }

    [Fact]
    public async Task PlayerBands_DecodesContractFixture()
    {
        var bands = new BandService { Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok(BandWire.Fixture("player-bands-demo")) : null };
        var list = await bands.Service.Client().GetPlayerBandsAsync("fixture-player-1", PlayerBandGroup.All, 1);
        Assert.Equal(2, list.Entries.Count);
        Assert.Equal("Fixture Player 1 + Fixture Player 2", list.Entries[0].MembersLabel);
        Assert.Equal("Fixture Player 1 + Unknown User + Fixture Player 3", list.Entries[1].MembersLabel);
        Assert.Equal([Instrument.Drums], list.Entries[0].Members[1].ChartedInstruments);
    }

    [Fact]
    public async Task PlayerBands_RejectsMismatchedOrOversizedPagesAndBadArguments()
    {
        var bands = new BandService { Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok(BandWire.PlayerBands("other", 5, 2)) : null };
        var client = bands.Service.Client();
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 1))).Kind);
        bands.Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok(BandWire.PlayerBands("acc", 5, 3)) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 1, 2))).Kind);
        bands.Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok("""{"accountId":"acc","totalCount":-1,"entries":[]}""") : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 1))).Kind);
        bands.Band = (p, _) => p.EndsWith("/bands", StringComparison.Ordinal) ? BandService.Ok("""{"accountId":"acc","totalCount":1,"entries":[{"bandId":"x","teamKey":"","bandType":"Band_Duets","members":[]}]}""") : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 1))).Kind);
        foreach (var call in new Func<Task>[]
                 {
                     () => client.GetPlayerBandsAsync("bad id", PlayerBandGroup.All, 1),
                     () => client.GetPlayerBandsAsync("acc", (PlayerBandGroup)9, 1),
                     () => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 0),
                     () => client.GetPlayerBandsAsync("acc", PlayerBandGroup.All, 1, 101),
                 })
            Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(call)).Kind);
    }

    [Fact]
    public async Task BandProfile_UsesRankingsBoardNeverBandsById()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var detail = await client.GetBandProfileAsync(BandType.Duets, BandWire.Team);
        var sent = bands.Service.Handler.To("/api/rankings/bands/Band_Duets").Single();
        Assert.Equal("?teamKey=fixture-rank-1%3Afixture-rank-2&rankBy=adjusted&page=1&pageSize=1", sent.Uri.Query);
        Assert.DoesNotContain(bands.Service.Handler.Requests, r => r.Uri.AbsolutePath.StartsWith("/api/bands", StringComparison.Ordinal));
        Assert.Equal("fixture-band-1", detail.BandId);
        Assert.Equal(40, detail.SongsPlayed);
        Assert.Equal(222222222, detail.TotalScore);
        Assert.Equal("Fixture Rank One + Unknown User", BandMember.JoinNames(detail.DisplayMembers));
        Assert.Equal(1, detail.Rank(BandRankingMetric.Adjusted));
        Assert.Equal(1, detail.Rank(BandRankingMetric.Weighted));
        Assert.Equal(2, detail.Rank(BandRankingMetric.FcRate));
        Assert.Equal(1, detail.Rank(BandRankingMetric.TotalScore));
    }

    [Fact]
    public async Task BandProfile_MapsMissingTeamToNotFoundAndRejectsMismatches()
    {
        var body = "";
        var bands = new BandService { Band = (p, _) => p == "/api/rankings/bands/Band_Duets" ? BandService.Ok(body) : null };
        var client = bands.Service.Client();
        body = """{"bandType":"Band_Duets","selectedBandEntry":null}""";
        var missing = await Fails(() => client.GetBandProfileAsync(BandType.Duets, BandWire.Team));
        Assert.Equal(404, missing.StatusCode);
        Assert.Equal(ServiceIssueKind.NotFound, ServiceIssue.From(missing).Kind);
        body = BandWire.Fixture("band-detail-demo").Replace("\"bandType\": \"Band_Duets\"", "\"bandType\": \"Band_Trios\"", StringComparison.Ordinal);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetBandProfileAsync(BandType.Duets, BandWire.Team))).Kind);
        body = BandWire.Fixture("band-detail-demo");
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetBandProfileAsync(BandType.Duets, "a:b"))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetBandProfileAsync(BandType.Duets, "bad key"))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetBandProfileAsync((BandType)7, BandWire.Team))).Kind);
    }

    [Fact]
    public async Task RankHistory_BuildsUrlDecodesAndValidates()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var history = await client.GetBandRankHistoryAsync(BandType.Duets, BandWire.Team, 14);
        var sent = bands.Service.Handler.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/history", StringComparison.Ordinal));
        Assert.Equal("/api/rankings/bands/Band_Duets/fixture-rank-1%3Afixture-rank-2/history", sent.Uri.AbsolutePath);
        Assert.Equal("?days=14", sent.Uri.Query);
        Assert.Equal(2, history.History.Count);
        Assert.Equal("ready", history.HistoryStatus);
        var day = history.History[1];
        Assert.Equal(2, day.Rank(BandRankingMetric.Adjusted));
        Assert.Equal(2, day.Rank(BandRankingMetric.Weighted));
        Assert.Equal(3, day.Rank(BandRankingMetric.FcRate));
        Assert.Equal(2, day.Rank(BandRankingMetric.TotalScore));
        Assert.Equal(0.0052, day.Value(BandRankingMetric.Adjusted));
        Assert.Equal(0.88, day.Value(BandRankingMetric.Weighted));
        Assert.Equal(0.85, day.Value(BandRankingMetric.FcRate));
        Assert.Equal(210000000, day.Value(BandRankingMetric.TotalScore));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetBandRankHistoryAsync(BandType.Trios, BandWire.Team));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetBandRankHistoryAsync(BandType.Duets, BandWire.Team, 0));
    }

    [Fact]
    public async Task SongExtremes_BuildsUrlDecodesAndSurfacesUnpublished503()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var songs = await client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team, 2);
        Assert.Contains(bands.Service.Handler.Requests, r => r.Uri.AbsolutePath.EndsWith("/songs", StringComparison.Ordinal) && r.Uri.Query == "?limit=2");
        Assert.Equal("fixture-pulse", songs.Best.Single().SongId);
        Assert.Equal(0.769, songs.Worst.Single().Percentile);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetBandSongExtremesAsync(BandType.Trios, BandWire.Team, 2))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team, 21))).Kind);
        bands.Band = (p, _) => p.EndsWith("/songs", StringComparison.Ordinal) ? BandService.Unavailable() : null;
        var unpublished = await Fails(() => client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team, 2));
        Assert.Equal(FestivalApiErrorKind.Unavailable, unpublished.Kind);
        Assert.Equal(30, ServiceIssue.From(unpublished).RetryAfter);
        bands.Band = (p, _) => p.EndsWith("/songs", StringComparison.Ordinal)
            ? BandService.Ok($$"""{"bandType":"Band_Duets","teamKey":"{{BandWire.Team}}","limit":1,"best":[{"songId":"a"},{"songId":"b"}],"worst":[]}""") : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team, 1))).Kind);
    }

    [Fact]
    public async Task SongBandLeaderboard_PagesAndValidates()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var board = await client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Quad, 3);
        var sent = bands.Service.Handler.To("/api/leaderboard/fixture-pulse/bands/Band_Quad").Single();
        Assert.Equal("?top=25&offset=50", sent.Uri.Query);
        Assert.Equal(10, board.Entries.Count);
        Assert.Equal(60, board.Population);
        Assert.Equal(3, board.PageCount(25));
        Assert.Equal("Lead 51 + Unknown User", board.Entries[0].MembersLabel);
        Assert.Equal(1, new SongBandLeaderboardResponse().PageCount(25));
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets, 0))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetSongBandLeaderboardAsync("a/b", BandType.Duets))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetSongBandLeaderboardAsync("s", BandType.Duets, 1, 101))).Kind);
        bands.Band = (p, _) => p.Contains("/bands/", StringComparison.Ordinal) && p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(BandWire.SongBands("other", "Band_Duets", 1, 1)) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets))).Kind);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(BandWire.Fixture("song-band-leaderboard-demo")) : null;
        var fixture = await client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets);
        Assert.Equal(2, fixture.Entries.Count);
        Assert.Equal("Fixture Rank Three + Unknown User", fixture.Entries[1].MembersLabel);
        Assert.Equal(999999, fixture.Entries[0].Score);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets, 1, 1))).Kind);
    }

    [Fact]
    public async Task SongBandLeaderboard_AccountReadBuildsTheQuery_AndValidatesSelectedEntries()
    {
        var origin = new Uri(Wire.BaseUrl);
        Assert.Equal($"https://festivalscoretracker.com/api/leaderboard/s1/bands/Band_Trios?top=25&offset=25&accountId={PlayerWire.Id}",
            BandEndpoints.SongBandLeaderboard(origin, "s1", BandType.Trios, 25, 25, PlayerWire.Id).AbsoluteUri);
        Assert.Equal("https://festivalscoretracker.com/api/leaderboard/s1/bands/Band_Trios?top=25&offset=0",
            BandEndpoints.SongBandLeaderboard(origin, "s1", BandType.Trios, 25, 0, null).AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => BandEndpoints.SongBandLeaderboard(origin, "s1", BandType.Trios, 25, 0, "bad id"));

        var bands = new BandService();
        var client = bands.Service.Client();
        var board = await client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets, 1, 25, "t40a");
        Assert.Equal(40, board.PinnedEntry("t40a")!.Rank);
        Assert.Null(board.SelectedBandEntry);
        Assert.DoesNotContain(board.Entries, e => SongBandPreview.IsSameBand(e, board.SelectedPlayerEntry!));
        var sent = bands.Service.Handler.To("/api/leaderboard/fixture-pulse/bands/Band_Duets").Single();
        Assert.DoesNotContain(sent.Headers.Keys, h => h.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) || h == "X-API-Key");

        // A selected band entry of another size is a malformed response, not a footer; a selected band entry (teamKey
        // query, not sent by natives) is never pinned.
        var body = BandWire.SongBands("fixture-pulse", "Band_Duets", 1, 1);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(body[..^1] + ",\"selectedBandEntry\":" + BandWire.SongBandEntry("Band_Trios", 3) + "}") : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets, 4, 25, "t3a"))).Kind);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(body[..^1] + ",\"selectedBandEntry\":" + BandWire.SongBandEntry("Band_Duets", 7) + "}") : null;
        Assert.Null((await client.GetSongBandLeaderboardAsync("fixture-pulse", BandType.Duets, 3, 25, "t7a")).PinnedEntry("t7a"));
    }

    [Fact]
    public async Task SongBandLeaderboard_SendsAccountIdAndReadsSelectedPlayerEntry()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var board = await client.GetSongBandLeaderboardAsync("s1", BandType.Duets, 1, 25, "t30a");
        var sent = bands.Service.Handler.To("/api/leaderboard/s1/bands/Band_Duets").Single();
        Assert.Equal("?top=25&offset=0&accountId=t30a", sent.Uri.Query);
        Assert.Equal(30, board.SelectedPlayerEntry!.Rank);
        Assert.Equal("t30a:t30b", board.PinnedEntry("T30A")!.TeamKey);
        Assert.Null(board.PinnedEntry("t31a"));
        Assert.Null(board.PinnedEntry(null));
        Assert.Null(board.SelectedBandEntry);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetSongBandLeaderboardAsync("s1", BandType.Duets, 1, 25, "a/b"))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResource, (await Fails(() => client.GetSongBandLeaderboardAsync("s1", BandType.Duets, 1, 25, ""))).Kind);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok(BandWire.SongBands("s1", "Band_Duets", 1, 1, 0, 1, "Band_Quad")) : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetSongBandLeaderboardAsync("s1", BandType.Duets, 1, 25, "t1a"))).Kind);
        bands.Band = (p, _) => p.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? BandService.Ok("""{"songId":"s1","bandType":"Band_Duets","count":0,"totalEntries":0,"entries":[],"selectedPlayerEntry":{"bandType":"Band_Duets","teamKey":"a:b","members":null}}""") : null;
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, (await Fails(() => client.GetSongBandLeaderboardAsync("s1", BandType.Duets, 1, 25, "a"))).Kind);
    }

    [Theory]
    [InlineData("a:b", true)]
    [InlineData("a:b:c:d", true)]
    [InlineData("fixture-team-1", true)]
    [InlineData("a:b:c:d:e", false)]
    [InlineData("a::b", false)]
    [InlineData("a:b/c", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void TeamKey_Validation(string? key, bool valid) => Assert.Equal(valid, BandEndpoints.IsValidTeamKey(key));
}

public class BandsModelTests
{
    [Fact]
    public void Member_NamesAndInstruments()
    {
        var member = new BandMember { AccountId = "a", DisplayName = "  Name ", Instruments = ["Solo_Bass", "Solo_Bass", "Nope", "Solo_PeripheralVocals"] };
        Assert.Equal("Name", member.ResolvedName);
        Assert.Equal([Instrument.Bass, Instrument.Karaoke], member.ChartedInstruments);
        Assert.True(member.HasValidAccount);
        var blank = new BandMember { AccountId = "bad id", DisplayName = " " };
        Assert.Equal("Unknown User", blank.ResolvedName);
        Assert.Empty(blank.ChartedInstruments);
        Assert.False(blank.HasValidAccount);
        Assert.Equal("Band", BandMember.JoinNames(null));
        Assert.Equal("Name + Unknown User", BandMember.JoinNames([member, blank, member]));
    }

    [Fact]
    public void Detail_DisplayMembersFallsBackToRoster()
    {
        var roster = new BandDetail { Members = [], TeamMembers = [new BandMember { AccountId = "x", DisplayName = "X" }] };
        Assert.Equal("X", roster.DisplayMembers.Single().ResolvedName);
        Assert.Empty(new BandDetail { Members = [], TeamMembers = null }.DisplayMembers);
        Assert.Equal("t", new PlayerBandEntry { TeamKey = "t" }.Key);
    }

    [Fact]
    public void Group_LabelsAndIds()
    {
        Assert.Equal(["all", "duos", "trios", "quads"], PlayerBandGroupInfo.All.Select(g => g.ServiceId()));
        Assert.Equal(["All Bands", "Duos", "Trios", "Quads"], PlayerBandGroupInfo.All.Select(g => g.Label()));
    }
}

public class BandFormattingTests
{
    [Fact]
    public void FormatsLikeTheWebBandPage()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Assert.Equal("#1,234", BandFormatting.Rank(1234));
        Assert.Equal("—", BandFormatting.Rank(0));
        Assert.Equal("#1.5", BandFormatting.AverageRank(1.5));
        Assert.Equal("—", BandFormatting.AverageRank(0));
        Assert.Equal("—", BandFormatting.AverageRank(double.NaN));
        Assert.Equal("99.2%", BandFormatting.Accuracy(992000));
        Assert.Equal("99.0%", BandFormatting.Accuracy(990000));
        Assert.Equal("—", BandFormatting.Accuracy(0));
        Assert.Equal("—", BandFormatting.Accuracy(null));
        Assert.Equal("—", BandFormatting.Accuracy(double.PositiveInfinity));
        Assert.Equal("4.9", BandFormatting.Stars(4.9));
        Assert.Equal("—", BandFormatting.Stars(0));
        Assert.Equal("90.0%", BandFormatting.Percentage(0.9));
        Assert.Equal("—", BandFormatting.Percentage(double.NaN));
        Assert.Equal("Top 4%", BandFormatting.Percentile(0.0385));
        Assert.Equal("Top 0.30%", BandFormatting.Percentile(0.003));
        Assert.Equal("Top 0.01%", BandFormatting.Percentile(0));
        Assert.Equal("—", BandFormatting.Percentile(double.NaN));
        Assert.Equal("36 / 40", BandFormatting.Fraction(36, 40));
        Assert.Equal("Top 1%", BandFormatting.MetricValue(0.0100, BandRankingMetric.Adjusted));
        Assert.Equal("Top 91%", BandFormatting.MetricValue(0.91, BandRankingMetric.Weighted));
        Assert.Equal("85.0%", BandFormatting.MetricValue(0.85, BandRankingMetric.FcRate));
        Assert.Equal("222,222,222", BandFormatting.MetricValue(222222222, BandRankingMetric.TotalScore));
        Assert.Equal("—", BandFormatting.MetricValue(null, BandRankingMetric.TotalScore));
        Assert.Equal("Sep 27", BandFormatting.ShortDate("2026-09-27"));
        Assert.Equal("today", BandFormatting.ShortDate("today"));
        Assert.Equal(1, BandFormatting.PageForRank(0));
        Assert.Equal(1, BandFormatting.PageForRank(25));
        Assert.Equal(2, BandFormatting.PageForRank(26));
    }
}
