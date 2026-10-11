using System.Globalization;
using System.Net;
using Festival.Core.Domain;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Combo leaderboards (issue #602): board domain, wire format, reads, routes and the combo Full Rankings mode.</summary>
public sealed class ComboRankingsTests
{
    public ComboRankingsTests() => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");

    #region Board domain
    [Theory]
    [InlineData("0f", "0f", "Lead + Bass + Drums + Tap Vocals")]
    [InlineData("0F", "0f", "Lead + Bass + Drums + Tap Vocals")]
    [InlineData("03", "03", "Lead + Bass")]
    [InlineData("30", "30", "Pro Lead + Pro Bass")]
    public void ComboParsesWithinGroupIds(string id, string normalized, string label)
    {
        var board = RankingBoard.Combo(id)!;
        Assert.True(board.IsCombo);
        Assert.Equal(normalized, board.ComboId);
        Assert.Equal(normalized, board.Id);
        Assert.Equal(label, board.Label);
        Assert.Equal(board.Instruments.Select(i => i.IconFile()), board.IconFiles);
        Assert.Equal(board, RankingBoard.Combo(normalized));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("zz")]
    [InlineData("01")] // one instrument
    [InlineData("11")] // Lead + Pro Lead: cross-group (the service answers 404)
    [InlineData("c0")] // Karaoke + Pro Cymbals: no combo family
    [InlineData("100")] // Pro Drums token
    public void ComboRejectsSingleCrossGroupAndMalformedIds(string? id) => Assert.Null(RankingBoard.Combo(id));

    [Fact]
    public void SingleBoardKeepsTheInstrumentIdentity()
    {
        var board = RankingBoard.Single(Instrument.Drums);
        Assert.False(board.IsCombo);
        Assert.Null(board.ComboId);
        Assert.Equal("Solo_Drums", board.Id);
        Assert.Equal("Drums", board.Label);
        Assert.Equal(Instrument.Drums, board.Instrument);
    }

    [Fact]
    public void ScopesPutEachFamilysComboBeforeItsInstruments()
    {
        Assert.Equal(["0f", "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "30", "Solo_PeripheralGuitar", "Solo_PeripheralBass",
                "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums"],
            RankingBoard.Scopes(InstrumentInfo.All).Select(b => b.Id));
        // Only Settings-visible instruments join a combo, and a family needs two for one.
        Assert.Equal(["05", "Solo_Guitar", "Solo_Drums", "Solo_PeripheralBass"],
            RankingBoard.Scopes([Instrument.ProBass, Instrument.Drums, Instrument.Lead]).Select(b => b.Id));
        // Karaoke / Pro Drums never get a combo.
        Assert.Equal(["Solo_PeripheralVocals", "Solo_PeripheralDrums"],
            RankingBoard.Scopes([Instrument.ProDrums, Instrument.Karaoke]).Select(b => b.Id));
        Assert.Empty(RankingBoard.Scopes([]));
    }
    #endregion

    #region Routes
    [Fact]
    public void FullRankingsRouteCarriesTheBoard()
    {
        var route = AppRoute.FullRankings.For(RankingBoard.Combo("30")!, "adjusted", 2, revealSelected: true);
        Assert.Equal(new AppRoute.FullRankings(Instrument.ProLead, "adjusted", 2, true, "30"), route);
        Assert.Equal(RankingBoard.Combo("30"), route.Board);
        Assert.Equal(RankingBoard.Single(Instrument.Bass), new AppRoute.FullRankings(Instrument.Bass, "totalscore").Board);
        // An invalid combo falls back to the instrument board.
        Assert.Equal(RankingBoard.Single(Instrument.Bass), new AppRoute.FullRankings(Instrument.Bass, "totalscore", Combo: "11").Board);
        Assert.Equal("/leaderboards/all?instrument=Solo_Bass&rankBy=totalscore", new AppRoute.FullRankings(Instrument.Bass, "totalscore", Combo: "11").ToPath());
    }

    [Theory]
    [InlineData("/leaderboards/all?combo=0F&rankBy=fcrate", Instrument.Lead, "0f")]
    [InlineData("/leaderboards/all?combo=30", Instrument.ProLead, "30")]
    [InlineData("/leaderboards/all?combo=11&instrument=Solo_Bass", Instrument.Bass, null)]
    [InlineData("/leaderboards/all?combo=zz", Instrument.Lead, null)]
    public void ParserReadsTheComboQuery(string path, Instrument instrument, string? combo)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out var section));
        var full = Assert.IsType<AppRoute.FullRankings>(route);
        Assert.Equal(AppSection.Leaderboards, section);
        Assert.Equal(instrument, full.Instrument);
        Assert.Equal(combo, full.Combo);
    }
    #endregion

    #region Wire format
    [Fact]
    public void ComboEntryDisplaysLikeTheWebComboBoard()
    {
        var entry = Decode(RankingsWire.ComboEntry(3));
        foreach (var metric in RankingMetricInfo.All) Assert.Equal(3, entry.Rank(metric));
        Assert.Equal(0.03, entry.RatingValue(RankingMetric.Adjusted));
        Assert.Equal(0.13, entry.RatingValue(RankingMetric.Weighted));
        Assert.Equal(0.6, entry.RatingValue(RankingMetric.FcRate));
        Assert.Equal(399_999_997, entry.RatingValue(RankingMetric.TotalScore));
        Assert.Equal(0.93, entry.RatingValue(RankingMetric.MaxScore));
        Assert.Equal(0.03, entry.BayesianValue(RankingMetric.Adjusted));
        Assert.Equal(0.13, entry.BayesianValue(RankingMetric.Weighted));
        Assert.Null(entry.BayesianValue(RankingMetric.TotalScore));
        Assert.Equal("2,897 / 2,932", entry.SongsLabel(RankingMetric.TotalScore));
        Assert.Equal("2,797 / 2,897", entry.SongsLabel(RankingMetric.FcRate));
        Assert.Equal("2,897", (entry with { TotalChartedSongs = 0 }).SongsLabel(RankingMetric.MaxScore));
        Assert.Equal("Player 3", entry.Name);

        // The service may omit displayName.
        var unnamed = Decode(RankingsWire.ComboEntry(4, "abc", withName: false));
        Assert.Null(unnamed.DisplayName);
        Assert.Equal("abc", unnamed.AccountId);
    }

    [Fact]
    public void ComboBoardValidatesAndConvertsToTheSharedBoard()
    {
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.ComboBoard("0f", 2, 3, 247_907, [4, 5, 6])),
            RankingsJsonContext.Default.ComboRankingsResponse);
        board.Validate("0F");
        var shared = board.ToBoard();
        Assert.Equal(3, shared.Entries.Count);
        Assert.Equal(247_907, shared.TotalAccounts);
        Assert.Equal(82_636, shared.PageCount);
        Assert.Equal(4, shared.Entries[0].Rank(RankingMetric.FcRate));

        Assert.Throws<FestivalApiException>(() => board.Validate("03"));
        Assert.Throws<FestivalApiException>(() => (board with { Page = 0 }).Validate("0f"));
        Assert.Throws<FestivalApiException>(() => (board with { PageSize = 2 }).Validate("0f"));
        Assert.Throws<FestivalApiException>(() => (board with { TotalAccounts = -1 }).Validate("0f"));
        Assert.Throws<FestivalApiException>(() => (board with { Entries = [board.Entries[0] with { ComboRank = 0 }] }).Validate("0f"));

        var empty = ComboRankingsResponse.Empty("03", RankingMetric.FcRate, 1, 10);
        empty.Validate("03");
        Assert.Equal("fcrate", empty.RankBy);
        Assert.Empty(empty.ToBoard().Entries);
    }

    [Fact]
    public void PlayerComboRowValidatesAccountAndCombo()
    {
        var row = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.PlayerCombo("0f", 1234, "me")),
            RankingsJsonContext.Default.PlayerComboRanking);
        row.Validate("0F", "ME");
        var entry = row.ToEntry();
        Assert.Equal(1234, entry.Rank(RankingMetric.TotalScore));
        Assert.Equal("me", entry.AccountId);
        Assert.Equal(row.TotalScore, (long)entry.RatingValue(RankingMetric.TotalScore));
        Assert.Throws<FestivalApiException>(() => row.Validate("03", "me"));
        Assert.Throws<FestivalApiException>(() => row.Validate("0f", "other"));
        Assert.Throws<FestivalApiException>(() => (row with { Rank = 0 }).Validate("0f", "me"));
    }
    #endregion

    #region Reads
    [Fact]
    public void EndpointsAreThePublicComboReads()
    {
        var origin = new Uri("https://festivalscoretracker.com");
        var combo = RankingBoard.Combo("0f")!;
        Assert.Equal("https://festivalscoretracker.com/api/rankings/combo?combo=0f&rankBy=fcrate&page=3&pageSize=25",
            RankingsEndpoints.ComboRankings(origin, combo, RankingMetric.FcRate, 3, 25).ToString());
        Assert.Equal("https://festivalscoretracker.com/api/rankings/combo/0123456789abcdef0123456789abcdef?combo=0f&rankBy=adjusted",
            RankingsEndpoints.PlayerComboRanking(origin, combo, "0123456789abcdef0123456789abcdef", RankingMetric.Adjusted).ToString());
        Assert.Throws<FestivalApiException>(() => RankingsEndpoints.ComboRankings(origin, RankingBoard.Single(Instrument.Lead), RankingMetric.FcRate, 1, 10));
        Assert.Throws<FestivalApiException>(() => RankingsEndpoints.ComboRankings(origin, combo, RankingMetric.FcRate, 0, 10));
        Assert.Throws<FestivalApiException>(() => RankingsEndpoints.PlayerComboRanking(origin, combo, "a/b", RankingMetric.FcRate));
    }

    [Fact]
    public async Task ReadsMapNotFoundToEmptyAndUnrankedWithoutProfileHeaders()
    {
        var status = HttpStatusCode.OK;
        var fake = new RankingsFake { TotalAccounts = 12 };
        fake.Extra = r => status == HttpStatusCode.OK ? null : Wire.Response(status, "{}", ("X-FST-Publication-Id", "7"));
        var client = fake.Service.Client();
        var combo = RankingBoard.Combo("03")!;

        var board = await client.GetComboRankingsAsync(combo, RankingMetric.TotalScore, 2, 10);
        Assert.Equal(2, board.Entries.Count);
        Assert.Equal("Player 11", board.Entries[0].Name);
        var own = await client.GetPlayerComboRankingAsync(combo, PlayerWire.Id, RankingMetric.Weighted);
        Assert.Equal(120, own!.Rank(RankingMetric.Weighted));

        status = HttpStatusCode.NotFound;
        var empty = await client.GetComboRankingsAsync(combo, RankingMetric.FcRate, 1, 10);
        Assert.Empty(empty.Entries);
        Assert.Equal(0, empty.TotalAccounts);
        Assert.Null(await client.GetPlayerComboRankingAsync(combo, PlayerWire.Id, RankingMetric.Weighted));

        status = HttpStatusCode.InternalServerError;
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetComboRankingsAsync(combo, RankingMetric.FcRate));
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetPlayerComboRankingAsync(combo, PlayerWire.Id, RankingMetric.FcRate));
        Assert.All(fake.Service.Handler.Requests, r => Assert.DoesNotContain(r.Headers.Keys, k => k.Contains("Selected", StringComparison.OrdinalIgnoreCase) || k.Contains("Profile", StringComparison.OrdinalIgnoreCase)));
    }
    #endregion

    #region Full Rankings combo mode
    [Fact]
    public async Task FullRankingsShowsTheComboBoardWithoutTheInstrumentSwitcher()
    {
        var fake = new RankingsFake { TotalAccounts = 60 };
        var session = fake.Session(RankingsFake.Selected("me", [Instrument.Lead, Instrument.Bass]) with { ExperimentalRanks = true });
        var reader = new FakeReader();
        var vm = new FullRankingsViewModel(session, new AppRoute.FullRankings(Instrument.Lead, "totalscore", Combo: "0f"), reader.Read);
        await vm.LoadAsync();
        await Async.Until(() => vm.Spotlight.ShowRow);

        Assert.True(vm.IsCombo);
        Assert.False(vm.ShowInstrumentPicker);
        Assert.False(vm.ShowInstrumentIcon);
        Assert.Equal("Lead + Bass + Drums + Tap Vocals Rankings", vm.Title);
        Assert.Equal(["instrument_guitar.png", "instrument_bass.png", "instrument_drums.png", "instrument_vocals.png"], vm.IconFiles);
        Assert.Equal("60 ranked players", vm.TotalText);
        Assert.Equal(25, vm.Rows.Count);
        Assert.Equal("#1", vm.Rows[0].RankText);
        Assert.Equal(3, vm.Pager.TotalPages);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.AbsolutePath == "/api/rankings/combo" &&
                                                            r.Uri.Query == "?combo=0f&rankBy=totalscore&page=1&pageSize=25");
        // The pinned row comes from the combo read, never the instrument reader.
        Assert.Empty(reader.Calls);
        Assert.Equal("#120", vm.Spotlight.Row!.RankText);
        Assert.Equal("Not yet ranked on Lead + Bass + Drums + Tap Vocals.", vm.Spotlight.UnrankedText);

        // The switcher is hidden and inert: the board stays the combo.
        await vm.SelectInstrumentAsync(Instrument.Bass);
        Assert.Equal("Lead + Bass + Drums + Tap Vocals Rankings", vm.Title);

        // A combo row ranks one metric, so Rank By re-reads the player's combo row.
        var first = vm.Spotlight;
        fake.PlayerComboRank = 7;
        await vm.SelectMetricAsync(RankingMetric.FcRate);
        await Async.Until(() => vm.Spotlight.ShowRow);
        Assert.NotSame(first, vm.Spotlight);
        Assert.Equal("#7", vm.Spotlight.Row!.RankText);
        Assert.Contains(fake.Service.Handler.Requests, r => r.Uri.AbsolutePath == "/api/rankings/combo/me" &&
                                                            r.Uri.Query == "?combo=0f&rankBy=fcrate");
        // Paging keeps the spotlight.
        var paged = vm.Spotlight;
        await vm.Pager.NextCommand.ExecuteAsync(null);
        Assert.Same(paged, vm.Spotlight);
    }

    [Fact]
    public async Task InstrumentFullRankingsKeepsTheSwitcher()
    {
        var fake = new RankingsFake();
        var vm = new FullRankingsViewModel(fake.Session(), new AppRoute.FullRankings(Instrument.Bass, "totalscore"), new FakeReader().Read);
        await vm.LoadAsync();
        Assert.False(vm.IsCombo);
        Assert.True(vm.ShowInstrumentPicker);
        Assert.True(vm.ShowInstrumentIcon);
        Assert.Empty(vm.IconFiles);
        Assert.Equal(RankingBoard.Single(Instrument.Bass), vm.Board);
    }

    [Fact]
    public async Task FailedComboBoardShowsTheFullPageFailure()
    {
        var fake = new RankingsFake();
        fake.Failing.Add("/api/rankings/combo");
        var vm = new FullRankingsViewModel(fake.Session(), new AppRoute.FullRankings(Instrument.ProLead, "totalscore", Combo: "30"), new FakeReader().Read);
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.Equal("Pro Lead + Pro Bass Rankings", vm.Title);
    }
    #endregion

    private static ComboRankingEntry Decode(string json) =>
        FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes($$"""{"comboId":"0f","rankBy":"totalscore","page":1,"pageSize":1,"totalAccounts":1,"entries":[{{json}}]}"""),
            RankingsJsonContext.Default.ComboRankingsResponse).Entries[0];
}
