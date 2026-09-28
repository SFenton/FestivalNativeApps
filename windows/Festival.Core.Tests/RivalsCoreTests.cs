using System.Net;

namespace Festival.Core.Tests;

/// <summary>Rivals wire models, endpoint allowlist, client reads and pure domain logic.</summary>
public class RivalsCoreTests
{
    private const string Me = "fixture-me";
    private const string Rival = "408abb67d81446f0ac714506950ce178";
    private static readonly Uri Base = new(Wire.BaseUrl);

    public static string Fixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", name + ".json"));

    private static (FestivalApiClient Client, FakeHandler Handler) Client(Func<HttpRequestMessage, HttpResponseMessage> respond)
    {
        var handler = new FakeHandler { Responder = (r, _) => Task.FromResult(respond(r)) };
        return (new FestivalApiClient(new RequestGate(new HttpClient(handler)), Base), handler);
    }

    public static RivalSummary Summary(string id, int shared = 10, double score = 1, string? name = null) =>
        new(id, name ?? id, score, shared, 3, 7, 0);

    public static RivalSongComparison Song(string id, int delta, string? title = null, string instrument = "Solo_Guitar") =>
        new(id, title ?? id, "Artist", instrument, null, null, 10, 10 + delta, delta, 1000, 900);

    #region Endpoints
    [Fact]
    public void Endpoints_BuildAllowlistedPaths()
    {
        Assert.Equal("/api/player/abc/rivals/all", RivalsEndpoints.All(Base, "abc").AbsolutePath);
        Assert.Equal("/api/player/abc/rivals/Solo_Bass", RivalsEndpoints.List(Base, "abc", "Solo_Bass").AbsolutePath);
        Assert.Equal("/api/player/abc/rivals/03", RivalsEndpoints.List(Base, "abc", "03").AbsolutePath);
        Assert.Equal("/api/player/abc/rivals/pro_drums/r1?sort=you_lead&limit=0&offset=0",
            RivalsEndpoints.Detail(Base, "abc", "pro_drums", "r1", "you_lead").PathAndQuery);
        Assert.Equal("/api/player/abc/leaderboard-rivals/Solo_Guitar?rankBy=fcrate",
            RivalsEndpoints.LeaderboardList(Base, "abc", Instrument.Lead, RankingMetric.FcRate).PathAndQuery);
        Assert.Equal("/api/player/abc/leaderboard-rivals/Solo_Drums/r1?rankBy=totalscore&sort=closest",
            RivalsEndpoints.LeaderboardDetail(Base, "abc", Instrument.Drums, "r1", RankingMetric.TotalScore).PathAndQuery);
    }

    [Theory]
    [InlineData("../x", "Solo_Guitar", "r1", "closest")]
    [InlineData("abc", "recompute", "r1", "closest")]
    [InlineData("abc", "zz", "r1", "closest")]
    [InlineData("abc", "Solo_Guitar", "r/1", "closest")]
    [InlineData("abc", "Solo_Guitar", "r1", "random")]
    public void Endpoints_RejectUnsafeSegments(string account, string scope, string rival, string sort)
    {
        var error = Assert.Throws<FestivalApiException>(() => RivalsEndpoints.Detail(Base, account, scope, rival, sort));
        Assert.Equal(FestivalApiErrorKind.InvalidResource, error.Kind);
    }

    [Fact]
    public void Endpoints_ValidateScopes()
    {
        Assert.True(RivalsEndpoints.IsValidScope("Solo_PeripheralDrums"));
        Assert.True(RivalsEndpoints.IsValidScope("1ff"));
        Assert.False(RivalsEndpoints.IsValidScope("200"));
        Assert.False(RivalsEndpoints.IsValidScope("0"));
        Assert.False(RivalsEndpoints.IsValidScope(null));
        Assert.Equal("5", RivalsEndpoints.Num(5));
    }
    #endregion

    #region Client
    [Fact]
    public async Task Client_ReadsFixturesUnpinnedWithoutProfileHeaders()
    {
        var (client, handler) = Client(r => r.RequestUri!.AbsolutePath switch
        {
            var p when p.EndsWith("/rivals/all", StringComparison.Ordinal) => Wire.Ok(Fixture("rivals-all-demo").Replace("0000000000000000000000000000a001", Me)),
            var p when p.Contains("/leaderboard-rivals/", StringComparison.Ordinal) && p.Count(c => c == '/') == 6 => Wire.Ok(Fixture("leaderboard-rival-detail-demo")),
            var p when p.Contains("/leaderboard-rivals/", StringComparison.Ordinal) => Wire.Ok(Fixture("leaderboard-rivals-demo")),
            var p when p.Count(c => c == '/') == 6 => Wire.Ok(Fixture("rival-detail-demo")),
            _ => Wire.Ok(Fixture("rivals-list-demo")),
        });

        var list = await client.GetRivalsListAsync(Me, "Solo_Guitar");
        Assert.Equal(3, list.Above.Count);
        Assert.False(list.IsEmpty);
        var board = await client.GetLeaderboardRivalsAsync(Me, Instrument.Lead, RankingMetric.TotalScore);
        Assert.Equal(1, board.UserRank);
        Assert.Empty(board.Above);
        Assert.False(board.IsEmpty);
        var detail = await client.GetRivalDetailAsync(Me, "01", Rival);
        Assert.Equal(4, detail.Songs.Count);
        Assert.Equal("uwphe", detail.Rival.DisplayName);
        var lbDetail = await client.GetLeaderboardRivalDetailAsync(Me, Instrument.Lead, "75a76ce7304d49c0ab76ea7ff5c3288e", RankingMetric.Weighted);
        Assert.Equal(2, lbDetail.Songs.Count);
        var all = await client.GetRivalsAllAsync(Me);
        Assert.False(all.IsEmpty);
        var sample = all.Combos[0].Above[0].Samples![0];
        Assert.Equal("demo-song-alpha", all.SongId(sample));
        Assert.Null(all.SongId(sample with { SongIndex = 99 }));

        Assert.All(handler.Requests, r =>
        {
            Assert.Equal(HttpMethod.Get, r.Method);
            Assert.DoesNotContain(r.Headers.Keys, k => k.StartsWith("x-fst-selected-", StringComparison.OrdinalIgnoreCase));
            Assert.DoesNotContain(r.Headers.Keys, k => k.Equals(FestivalApiClient.PublicationHeader, StringComparison.OrdinalIgnoreCase));
        });
        Assert.DoesNotContain(handler.Requests, r => r.Uri.AbsolutePath == "/api/publication");
    }

    [Fact]
    public async Task Client_NormalizesNotFoundToEmpty()
    {
        var (client, _) = Client(_ => Wire.Response(HttpStatusCode.NotFound, """{"error":"No rivals found."}"""));
        Assert.True((await client.GetRivalsListAsync(Me, "03")).IsEmpty);
        Assert.True((await client.GetLeaderboardRivalsAsync(Me, Instrument.Bass, RankingMetric.MaxScore)).IsEmpty);
        Assert.Empty((await client.GetRivalDetailAsync(Me, "Solo_Guitar", Rival)).Songs);
        Assert.Empty((await client.GetLeaderboardRivalDetailAsync(Me, Instrument.Bass, Rival, RankingMetric.Adjusted)).Songs);
        Assert.True((await client.GetRivalsAllAsync(Me)).IsEmpty);
    }

    [Fact]
    public async Task Client_MapsScrapeFreeze()
    {
        var (client, _) = Client(_ => Wire.Response(HttpStatusCode.ServiceUnavailable, "",
            ("Retry-After", "30"), (ServiceFreezeReason.Header, "scrape")));
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRivalDetailAsync(Me, "Solo_Guitar", Rival));
        Assert.Equal(FestivalApiErrorKind.PublicReadFrozen, error.Kind);
        Assert.Equal("30", error.RetryAfter);
    }

    [Theory]
    [InlineData("""{"combo":"01","above":null,"below":[]}""")]
    [InlineData("""{"combo":"01","above":[{"accountId":"bad id","rivalScore":1,"sharedSongCount":1,"aheadCount":1,"behindCount":0,"avgSignedDelta":0}],"below":[]}""")]
    [InlineData("""{"combo":"01","above":[{"accountId":"ok","rivalScore":1,"sharedSongCount":-1,"aheadCount":1,"behindCount":0,"avgSignedDelta":0}],"below":[]}""")]
    [InlineData("not json")]
    public async Task Client_RejectsMalformedLists(string body)
    {
        var (client, _) = Client(_ => Wire.Ok(body));
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRivalsListAsync(Me, "01"));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, error.Kind);
    }

    [Fact]
    public async Task Client_RejectsMismatchedDetailAndAllAccount()
    {
        var (client, _) = Client(r => Wire.Ok(r.RequestUri!.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
            ? Fixture("rivals-all-demo") : Fixture("rival-detail-demo")));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRivalDetailAsync(Me, "Solo_Guitar", "someoneelse"))).Kind);
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => client.GetRivalsAllAsync(Me))).Kind);
    }

    [Fact]
    public void Validation_SanitizesDisplayTextAndRejectsBadSongs()
    {
        var detail = new RivalDetailResponse(new RivalIdentity(Rival, "  Name‮ "), "01", null, null, null, 1, "closest",
            [Song("s1", 1, "Title\u0001") with { UserInstrument = "Solo_Bass", RivalInstrument = "bogus" }]);
        var validated = detail.Validated(Rival);
        Assert.Null(validated.Rival.DisplayName);
        Assert.Null(validated.Songs[0].Title);
        Assert.Equal("Solo_Bass", validated.Songs[0].UserInstrument);
        Assert.Null(validated.Songs[0].RivalInstrument);
        Assert.Equal("s1:Solo_Guitar:Solo_Bass:", validated.Songs[0].Key);

        Assert.Throws<FestivalApiException>(() => (detail with { Songs = [Song("s1", 1, instrument: "Solo_Nope")] }).Validated(Rival));
        Assert.Throws<FestivalApiException>(() => (detail with { Songs = [Song("", 1)] }).Validated(Rival));
        Assert.Throws<FestivalApiException>(() => (detail with { Songs = null! }).Validated(Rival));
        Assert.Equal("Trimmed", RivalsValidation.SafeName("  Trimmed "));
        Assert.Null(RivalsValidation.SafeName(new string('x', 201)));

        var all = new RivalsAllResponse(Me, null, [new RivalsAllCombo("01",
            [new RivalsAllEntry("r1", "R", "above", 1, 1, 0, 2, null, null)], [])]).Validated();
        Assert.Empty(all.Songs!);
        Assert.Empty(all.Combos[0].Above[0].Samples!);
        Assert.Throws<FestivalApiException>(() => new RivalsAllResponse(Me, [], null!).Validated());
        Assert.Throws<FestivalApiException>(() => new RivalsAllResponse(Me, [], [new RivalsAllCombo(null!, [], [])]).Validated());
        Assert.Throws<FestivalApiException>(() => new LeaderboardRivalsListResponse("x", "y", null, null!, []).Validated());
    }
    #endregion

    #region Combos
    [Fact]
    public void Combo_DerivesWebScopes()
    {
        Assert.Equal("03", RivalCombo.DeriveToken([Instrument.Lead, Instrument.Bass]));
        Assert.Equal("0f", RivalCombo.DeriveToken([Instrument.Vocals, Instrument.Drums, Instrument.Bass, Instrument.Lead]));
        Assert.Equal("30", RivalCombo.DeriveToken([Instrument.ProLead, Instrument.ProBass]));
        Assert.Equal(RivalCombo.ProDrumsToken, RivalCombo.DeriveToken([Instrument.ProDrums, Instrument.ProCymbals]));
        Assert.Null(RivalCombo.DeriveToken([Instrument.Lead]));
        Assert.Null(RivalCombo.DeriveToken([Instrument.Lead, Instrument.ProLead]));
        Assert.Null(RivalCombo.DeriveToken(InstrumentInfo.All));
        Assert.Equal("01", RivalCombo.ComboId([Instrument.Lead]));
        Assert.Equal([Instrument.Lead, Instrument.Bass], RivalCombo.InstrumentsFor("03"));
        Assert.Equal([Instrument.ProCymbals, Instrument.ProDrums], RivalCombo.InstrumentsFor("pro_drums"));
        Assert.Null(RivalCombo.InstrumentsFor("xyz"));
        Assert.Null(RivalCombo.InstrumentsFor("12345"));
        Assert.Equal("Pro Drums Family", RivalCombo.Label("pro_drums"));
        Assert.Equal("Combined", RivalCombo.Label("03"));
    }
    #endregion

    #region Scope
    public static TheoryData<RivalScope> Scopes() =>
    [
        new RivalScope.Song([Instrument.Bass]),
        new RivalScope.Song([Instrument.Drums, Instrument.Lead]),
        new RivalScope.Leaderboard(Instrument.ProBass, RankingMetric.Weighted),
        new RivalScope.Combo("03"),
        new RivalScope.Combo("pro_drums"),
        new RivalScope.FromSettings(RivalSettingsScope.Common),
        new RivalScope.FromSettings(RivalSettingsScope.Combo),
    ];

    [Theory]
    [MemberData(nameof(Scopes))]
    public void Scope_TokenAndQueryRoundTrip(RivalScope scope)
    {
        Assert.Equal(scope, RivalScope.FromToken(scope.ToToken()));
        var query = scope.ToAllRivalsQuery().ToDictionary(p => p.Key, p => p.Value);
        var parsed = RivalScope.FromAllRivalsQuery(query.GetValueOrDefault("category"), query.GetValueOrDefault("mode"),
            query.GetValueOrDefault("rankBy"), query.GetValueOrDefault("instruments"));
        Assert.Equal(scope, parsed);
        Assert.EndsWith("Rivals", scope.ListTitle);
    }

    [Fact]
    public void Scope_EqualityIgnoresInstrumentOrder()
    {
        Assert.Equal(new RivalScope.Song([Instrument.Lead, Instrument.Bass]), new RivalScope.Song([Instrument.Bass, Instrument.Lead, Instrument.Bass]));
        Assert.True(new RivalScope.Song([Instrument.Lead, Instrument.Bass]).IsCommon);
        Assert.False(new RivalScope.Song([Instrument.Lead]).IsCommon);
        Assert.Equal("Lead Rivals", new RivalScope.Song([Instrument.Lead]).ListTitle);
        Assert.Equal("Common Rivals", new RivalScope.Song([Instrument.Lead, Instrument.Bass]).ListTitle);
        Assert.Equal("Pro Drums Family Rivals", new RivalScope.Combo("pro_drums").ListTitle);
        Assert.Equal("Combined Rivals", new RivalScope.FromSettings(RivalSettingsScope.Combo).ListTitle);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("song:")]
    [InlineData("song:Solo_Guitar,nope")]
    [InlineData("leaderboard:Solo_Guitar")]
    [InlineData("leaderboard:nope:totalscore")]
    [InlineData("leaderboard:Solo_Guitar:nope")]
    [InlineData("combo:zz")]
    [InlineData("settings:other")]
    [InlineData("settings:5")]
    [InlineData("bogus")]
    public void Scope_RejectsMalformedTokens(string? token) => Assert.Null(RivalScope.FromToken(token));

    [Fact]
    public void Scope_ParsesWebQueries()
    {
        Assert.Equal(new RivalScope.FromSettings(RivalSettingsScope.Common), RivalScope.FromAllRivalsQuery(null, null, null, null));
        Assert.Equal(new RivalScope.Leaderboard(Instrument.Lead, RankingMetric.TotalScore),
            RivalScope.FromAllRivalsQuery("Solo_Guitar", "leaderboard", "bogus", null));
        Assert.Null(RivalScope.FromAllRivalsQuery("common", "leaderboard", null, null));
        Assert.Null(RivalScope.FromAllRivalsQuery("nonsense", null, null, null));
        Assert.Null(RivalScope.FromAllRivalsQuery("common", null, null, "Solo_Nope"));
    }

    [Fact]
    public void Scope_ResolvesAgainstSettings()
    {
        IReadOnlyList<Instrument> two = [Instrument.Lead, Instrument.Bass];
        Assert.Equal(new RivalScope.Song(two), new RivalScope.FromSettings(RivalSettingsScope.Common).Resolve(two));
        Assert.Null(new RivalScope.FromSettings(RivalSettingsScope.Common).Resolve([Instrument.Lead]));
        Assert.Equal(new RivalScope.Combo("03"), new RivalScope.FromSettings(RivalSettingsScope.Combo).Resolve(two));
        Assert.Null(new RivalScope.FromSettings(RivalSettingsScope.Combo).Resolve([Instrument.Lead]));
        Assert.Null(new RivalScope.Song([]).Resolve(two));
        Assert.Null(new RivalScope.Combo("zz").Resolve(two));
        Assert.Empty(new RivalScope.Combo("zz").Instruments);
        var board = new RivalScope.Leaderboard(Instrument.Lead, RankingMetric.FcRate);
        Assert.Same(board, board.Resolve(two));
    }
    #endregion

    #region Common rivals
    [Fact]
    public void Common_IntersectsWithMajorityDirection()
    {
        var lead = new RivalsListResponse("Solo_Guitar", [Summary("a", 10, 5), Summary("b", 50, 9)], [Summary("c", 5, 1), Summary("only-lead")]);
        var bass = new RivalsListResponse("Solo_Bass", [Summary("c", 30, 1)], [Summary("a", 20, 5), Summary("b", 1, 9)]);
        var drums = new RivalsListResponse("Solo_Drums", [Summary("a", 1, 5), Summary("c", 1, 1)], [Summary("b", 2, 9), Summary("a", 99)]);

        var (above, below) = RivalCommonRivals.Intersect([lead, bass, drums]);
        Assert.Equal(["a", "c"], above.Select(r => r.AccountId));
        Assert.Equal(20, above[0].SharedSongCount);
        Assert.Equal(30, above[1].SharedSongCount);
        Assert.Equal(["b"], below.Select(r => r.AccountId));
        Assert.Equal(50, below[0].SharedSongCount);
    }

    [Fact]
    public void Common_NeedsTwoLists()
    {
        var (above, below) = RivalCommonRivals.Intersect([new RivalsListResponse("x", [Summary("a")], [])]);
        Assert.Empty(above);
        Assert.Empty(below);
    }
    #endregion

    #region Categories and head to head
    [Fact]
    public void Categorize_MatchesWebBuckets()
    {
        Assert.Empty(RivalCategorization.Categorize([]));
        List<RivalSongComparison> songs =
        [
            Song("t", 0), Song("r1", -1), Song("r2", -5), Song("r3", -50),
            Song("u1", 1), Song("u2", 2), Song("u3", 3), Song("u4", 40), Song("u5", 90), Song("u6", 500), Song("u7", 900),
        ];
        var categories = RivalCategorization.Categorize(songs);
        Assert.Equal(["closest_battles", "almost_passed", "slipping_away", "barely_winning", "pulling_forward", "dominating_them"],
            categories.Select(c => c.Key));
        Assert.Equal(["t", "r1", "u1", "u2", "u3"], categories[0].Songs.Select(s => s.SongId));
        Assert.Equal(["r1", "r2"], categories[1].Songs.Select(s => s.SongId));
        Assert.Equal(["r3"], categories[2].Songs.Select(s => s.SongId));
        Assert.Equal(["u1", "u2", "u3"], categories[3].Songs.Select(s => s.SongId));
        Assert.Equal(["u4", "u5", "u6"], categories[4].Songs.Select(s => s.SongId));
        Assert.Equal(["u7"], categories[5].Songs.Select(s => s.SongId));
        Assert.Equal(RivalCategorySentiment.Negative, categories[1].Sentiment);
        Assert.Equal(RivalCategorySentiment.Positive, categories[3].Sentiment);
    }

    [Fact]
    public void Categorize_OmitsEmptyBuckets()
    {
        var categories = RivalCategorization.Categorize([Song("u1", 4)]);
        Assert.Equal(["closest_battles", "barely_winning"], categories.Select(c => c.Key));
        Assert.Equal("Dominating Them", RivalCategorization.Title("dominating_them"));
        Assert.Equal("mystery", RivalCategorization.Title("mystery"));
        Assert.True(RivalCategorization.IsKnown("almost_passed"));
        Assert.False(RivalCategorization.IsKnown(null));
    }

    [Fact]
    public void HeadToHead_SortsAndSummarizes()
    {
        List<RivalSongComparison> songs = [Song("b", -3, "Bravo"), Song("a", 10, "alpha"), Song("c", 1, null)];
        Assert.Equal(["b", "a", "c"], RivalHeadToHead.Sort(songs, RivalrySort.Category).Select(s => s.SongId));
        Assert.Equal(["c", "b", "a"], RivalHeadToHead.Sort(songs, RivalrySort.Closest).Select(s => s.SongId));
        Assert.Equal(["a", "c", "b"], RivalHeadToHead.Sort(songs, RivalrySort.YouLead).Select(s => s.SongId));
        Assert.Equal(["b", "c", "a"], RivalHeadToHead.Sort(songs, RivalrySort.TheyLead).Select(s => s.SongId));
        Assert.Equal(["a", "b", "c"], RivalHeadToHead.Sort(songs, RivalrySort.Title).Select(s => s.SongId));
        Assert.All(Enum.GetValues<RivalrySort>(), s => Assert.NotEmpty(s.Label()));
        Assert.Equal("3 shared songs · 2 ahead / 1 behind", RivalHeadToHead.Summary(songs));
    }

    [Theory]
    [InlineData(0, "0")]
    [InlineData(12, "+12")]
    [InlineData(-9_999, "−9,999")]
    [InlineData(15_400, "+15K")]
    [InlineData(-1_500_000, "−1.5M")]
    [InlineData(2_000_000, "+2M")]
    [InlineData(25_000_000, "+25M")]
    public void HeadToHead_FormatsRankDelta(long delta, string expected)
    {
        using var _ = new CultureScope("en-US");
        Assert.Equal(expected, RivalHeadToHead.FormatRankDelta(delta));
    }

    [Fact]
    public void HeadToHead_FormatsScoreDiff()
    {
        using var _ = new CultureScope("en-US");
        Assert.Equal("+100", RivalHeadToHead.FormatScoreDiff(Song("s", 1)));
        Assert.Equal("−7,000", RivalHeadToHead.FormatScoreDiff(Song("s", 1) with { UserScore = null, RivalScore = 7000 }));
    }
    #endregion
}

/// <summary>Temporarily sets the current culture.</summary>
public sealed class CultureScope : IDisposable
{
    private readonly System.Globalization.CultureInfo previous = System.Globalization.CultureInfo.CurrentCulture;

    public CultureScope(string name) => System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo(name);

    public void Dispose() => System.Globalization.CultureInfo.CurrentCulture = previous;
}
