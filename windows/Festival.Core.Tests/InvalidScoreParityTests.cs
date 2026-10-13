using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #613: Filter Invalid Scores parity with the web — filtered populations for fallback percentiles, the legacy
/// fallback fields, the Songs row indicator (web <c>InvalidScoreIcon</c>) and Song Detail's filtered player row.
/// </summary>
public class InvalidScoreParityTests
{
    private static Song Decode(string json) =>
        FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(Wire.Songs(json)), FestivalJsonContext.Default.SongsResponse).Songs.Single();

    private static string SongWithTiers(string id, string tiers) =>
        Wire.SongJson(id, "Title " + id, "Artist").Replace("""
            "populationTiers":{"Solo_Guitar":{"bc":1,"t":[]}}
            """.Trim(), "\"populationTiers\":" + tiers, StringComparison.Ordinal);

    private static IReadOnlyDictionary<Instrument, InvalidScoreReason> Reasons(params (Instrument, InvalidScoreReason)[] items) =>
        items.ToDictionary(i => i.Item1, i => i.Item2);

    #region Population tiers
    [Fact]
    public void PopulationTiers_DecodeLenientlyAndTakeTheLastChangepointAtOrBelowTheLeeway()
    {
        var song = Decode(SongWithTiers("s1", """{"Solo_Guitar":{"bc":40,"t":[{"l":-5,"t":42},{"l":0.5,"t":45},{"l":2,"t":48}]},"Solo_Bass":{"bc":"x"},"Solo_Drums":null,"Solo_Vocals":{"bc":3}}"""));
        var lead = song.PopulationTiers!["Solo_Guitar"]!;
        Assert.True(lead.IsWellFormed);
        Assert.Equal(40, lead.Total(-6));
        Assert.Equal(42, lead.Total(0));
        Assert.Equal(45, lead.Total(0.5));
        Assert.Equal(48, lead.Total(10));
        Assert.Equal(45, song.FilteredPopulation(Instrument.Lead, 1));
        // Malformed or missing curves never invent a population.
        Assert.False(song.PopulationTiers["Solo_Bass"]!.IsWellFormed);
        Assert.Null(song.FilteredPopulation(Instrument.Bass, 1));
        Assert.Null(song.FilteredPopulation(Instrument.Drums, 1));
        Assert.Null(song.FilteredPopulation(Instrument.ProBass, 1));
        Assert.Equal(3, song.FilteredPopulation(Instrument.Vocals, 1)); // no changepoints: the base count
        Assert.Null((song with { PopulationTiers = null }).FilteredPopulation(Instrument.Lead, 1));
    }

    [Theory]
    [InlineData("""{"bc":1,"t":{}}""")]
    [InlineData("""{"bc":1,"t":[{"l":"a","t":2}]}""")]
    [InlineData("""{"bc":1,"t":[{"l":1}]}""")]
    [InlineData("""{"bc":1,"t":[3]}""")]
    [InlineData("""[1]""")]
    [InlineData("""{"bc":-1}""")]
    [InlineData("""{"bc":1,"t":[{"l":2,"t":4},{"l":1,"t":5}]}""")]
    [InlineData("""{"bc":1,"t":[{"l":1,"t":-5}]}""")]
    [InlineData("""{"bc":"x"}""")]
    [InlineData("""{"bc":1,"t":[{"l":1,"t":2.5}]}""")]
    public void PopulationTiers_MalformedCurvesAreIgnoredWithoutFailingTheCatalogue(string tiers)
    {
        var song = Decode(SongWithTiers("s1", $$"""{"Solo_Guitar":{{tiers}}}"""));
        Assert.False(song.PopulationTiers!["Solo_Guitar"]!.IsWellFormed);
        Assert.Null(song.FilteredPopulation(Instrument.Lead, 5));
    }

    [Fact]
    public void PopulationTiers_RoundTripThroughTheConverter()
    {
        var curve = new PopulationTiers(7, [-1.5, 2], [8, 9]);
        var json = System.Text.Json.JsonSerializer.Serialize(curve, new System.Text.Json.JsonSerializerOptions { Converters = { new PopulationTiersConverter() } });
        Assert.Equal("""{"bc":7,"t":[{"l":-1.5,"t":8},{"l":2,"t":9}]}""", json);
        var back = System.Text.Json.JsonSerializer.Deserialize<PopulationTiers>(json, new System.Text.Json.JsonSerializerOptions { Converters = { new PopulationTiersConverter() } })!;
        Assert.Equal((7, 9), (back.BaseCount, back.Total(3)));
        Assert.Null(System.Text.Json.JsonSerializer.Deserialize<PopulationTiers>("null", new System.Text.Json.JsonSerializerOptions { Converters = { new PopulationTiersConverter() } }));
    }
    #endregion

    #region Resolution
    [Fact]
    public void Resolve_VariantFallbackUsesTheFilteredPopulationElseTheRawTotal()
    {
        var song = Decode(SongWithTiers("s1", """{"Solo_Guitar":{"bc":40,"t":[{"l":0,"t":45}]}}"""));
        var score = new PlayerScore
        {
            SongId = "s1", InstrumentCode = "01", Score = 2000, Rank = 1, TotalEntries = 50, MinLeeway = 5,
            ValidScores = [new PlayerValidScoreVariant { Score = 900, MinLeeway = -1, RankTiers = [new(-1, 12)] }],
        };
        var resolved = InvalidScorePolicy.Resolve(score, SongScoreSource.ToDetail(score), song, Instrument.Lead, 1, false);
        Assert.Equal((900L, 12, 45), (resolved.Detail!.Score, resolved.Detail.Rank!.Value, resolved.Detail.TotalEntries!.Value));
        var withoutCurve = InvalidScorePolicy.Resolve(score, SongScoreSource.ToDetail(score), song with { PopulationTiers = null }, Instrument.Lead, 1, false);
        Assert.Equal(50, withoutCurve.Detail!.TotalEntries);
    }

    [Fact]
    public void Resolve_LegacyFallbackUsesItsOwnRankStarsAndPopulation()
    {
        var song = Decode(Wire.SongJson("s1", "T", "A"));
        var score = new PlayerScore
        {
            SongId = "s1", InstrumentCode = "01", Score = 2000, Stars = 6, Rank = 1, TotalEntries = 50,
            ValidScore = 990, ValidRank = 7, ValidStars = 5, ValidTotalEntries = 44,
        };
        var resolved = InvalidScorePolicy.Resolve(score, SongScoreSource.ToDetail(score), song, Instrument.Lead, 1, false);
        Assert.Equal((990L, 7, 5, 44), (resolved.Detail!.Score, resolved.Detail.Rank!.Value, resolved.Detail.Stars!.Value, resolved.Detail.TotalEntries!.Value));
        Assert.True(score.IsValid);
        Assert.False((score with { ValidStars = 7 }).IsValid);
        Assert.False((score with { ValidRank = -1 }).IsValid);
        Assert.False((score with { ValidTotalEntries = -1 }).IsValid);
    }
    #endregion

    #region Warning
    [Fact]
    public void Warning_NoneWithoutReasonsOrOutsideTheFilterChart()
    {
        Assert.Null(InvalidScoreWarning.Of("Song", Reasons(), null));
        Assert.Null(InvalidScoreWarning.Of("Song", Reasons((Instrument.Bass, InvalidScoreReason.Fallback)), Instrument.Lead));
        Assert.Equal("fst.songs.invalid-score.s1", InvalidScoreWarning.AutomationId("s1"));
    }

    [Fact]
    public void Warning_ChipsViewDescribesEveryChartInServiceOrder()
    {
        var one = InvalidScoreWarning.Of("Song", Reasons((Instrument.Lead, InvalidScoreReason.Fallback)), null)!;
        Assert.False(one.Warning);
        Assert.Equal("Song has an invalid, filtered-out score on Lead. The Lead chip reflects the next valid score.\n\n" +
            "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings. " +
            "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument.", one.Message);

        var three = InvalidScoreWarning.Of("Song", Reasons(
            (Instrument.Drums, InvalidScoreReason.NoFallback), (Instrument.Lead, InvalidScoreReason.Fallback),
            (Instrument.Bass, InvalidScoreReason.Fallback)), null)!;
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Drums], three.Reasons.Select(r => r.Key));
        Assert.Equal("Song has an invalid, filtered-out score on Lead, Bass, and Drums. The chips for these instruments reflect the next valid score. " +
            "Because there is no valid other score for Drums, the Drums icon chip is red here.\n\n" +
            "To see the absolute highest scores you've achieved, toggle off 'Filter Invalid Scores' in App Settings. " +
            "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument.", three.Message);

        var mixed = InvalidScoreWarning.Of("Song", Reasons((Instrument.Lead, InvalidScoreReason.OverThreshold), (Instrument.Bass, InvalidScoreReason.NoFallback)), null)!;
        Assert.False(mixed.Warning);
        Assert.Contains("on Lead and Bass. The Lead score shown exceeds the CHOpt maximum. Because there is no valid other score for Bass", mixed.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Warning_OverThresholdOnlyIsTheGoldWarning()
    {
        var gold = InvalidScoreWarning.Of("Song", Reasons((Instrument.Lead, InvalidScoreReason.OverThreshold), (Instrument.Bass, InvalidScoreReason.OverThreshold)), null)!;
        Assert.True(gold.Warning);
        Assert.Equal("Song has a score on Lead and Bass that exceeds the CHOpt maximum. This is the highest unfiltered invalid score.", gold.Message);
    }

    [Fact]
    public void Warning_SingleChartFilterDescribesOnlyThatChart()
    {
        var reasons = Reasons((Instrument.Lead, InvalidScoreReason.OverThreshold), (Instrument.Bass, InvalidScoreReason.Fallback));
        var bass = InvalidScoreWarning.Of("Song", reasons, Instrument.Bass)!;
        Assert.False(bass.Warning);
        Assert.Equal("Song has an invalid, filtered-out score on Bass. We are showing the next valid score here.\n\n" +
            "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings. " +
            "You can also temporarily filter to 'Bass Over CHOpt Threshold' in the Filter modal.", bass.Message);
        Assert.True(InvalidScoreWarning.Of("Song", reasons, Instrument.Lead)!.Warning);
        Assert.True(bass.SameContent(InvalidScoreWarning.Of("Song", reasons, Instrument.Bass)));
        Assert.False(bass.SameContent(InvalidScoreWarning.Of("Song", reasons, Instrument.Lead)));
        Assert.False(bass.SameContent(null));
    }
    #endregion

    #region Songs rows
    private static async Task<(FestivalSession Session, SongsViewModel Vm)> OpenSongs(AppSettings settings)
    {
        // s1 Lead: invalid at leeway 1 with a variant valid from -5 (rank 7; population 60 from leeway 0); s2 Lead: invalid, no fallback.
        var fallback = ""","ml":2.0,"vs":[{"sc":850,"acc":960,"fc":false,"st":5,"ml":-5,"rt":[{"l":-5,"r":7}]}]""";
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One",
            PlayerWire.Score("s1", "01", 1000, 990, true, 6, 1, 100, 1.0, fallback),
            PlayerWire.Score("s2", "01", 900, 950, false, 5, 30, 100, 30, ""","ml":3.0"""),
            PlayerWire.Score("s3", "01", 700, 1000, true, 6, 4, 200, 2));
        var service = new FakeService
        {
            SongsBody = Wire.Songs(
                SongWithTiers("s1", """{"Solo_Guitar":{"bc":50,"t":[{"l":0,"t":60}]}}"""),
                Wire.SongJson("s2", "Beta", "B"),
                Wire.SongJson("s3", "Gamma", "C")),
        };
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var session = service.Session(settings: settings with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true });
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        return (session, vm);
    }

    private static SongRowItem Row(SongsViewModel vm, string id) => vm.Sections.SelectMany(s => s.Rows).Single(r => r.Song.SongId == id);

    [Fact]
    public async Task Rows_ChipsViewCarriesTheIndicatorAndFollowsLeewayInPlace()
    {
        var (session, vm) = await OpenSongs(new AppSettings { ShowInstrumentIcons = true, VisibleInstruments = [Instrument.Lead, Instrument.Bass] });
        var s1 = Row(vm, "s1");
        Assert.NotEmpty(s1.Chips);
        Assert.Equal(InvalidScoreReason.Fallback, Assert.Single(s1.Warning!.Reasons).Value);
        Assert.False(s1.Warning.Warning);
        Assert.EndsWith(", Filtered Score", s1.Announcement, StringComparison.Ordinal);
        Assert.Equal(InvalidScoreReason.NoFallback, Assert.Single(Row(vm, "s2").Warning!.Reasons).Value);
        Assert.Null(Row(vm, "s3").Warning);
        Assert.DoesNotContain(vm.Notices, n => n.Message.Contains("Filter Invalid Scores", StringComparison.Ordinal));

        // Raising the leeway above every minLeeway: the raw scores are valid, the indicator goes away without a reload.
        session.UpdateSettings(s => s with { Leeway = 5 });
        Assert.Null(Row(vm, "s1").Warning);
        Assert.Null(Row(vm, "s2").Warning);
        Assert.DoesNotContain(", Filtered Score", Row(vm, "s1").Announcement, StringComparison.Ordinal);

        // Off: raw scores and no indicator.
        session.UpdateSettings(s => s with { Leeway = 1, FilterInvalidScores = false });
        Assert.Null(Row(vm, "s1").Warning);
    }

    [Fact]
    public async Task Rows_MetadataViewShowsTheFallbackWithItsFilteredPercentile()
    {
        var (session, vm) = await OpenSongs(new AppSettings
        {
            ShowInstrumentIcons = false, VisibleInstruments = [Instrument.Lead],
            SongFilter = new SongFilter { Instrument = Instrument.Lead },
        });
        var s1 = Row(vm, "s1");
        Assert.NotNull(s1.Warning);
        Assert.Contains("We are showing the next valid score here.", s1.Warning!.Message, StringComparison.Ordinal);
        var detail = SongScoreSource.ForSongs(session, session.Catalog!.Songs).Detail!("s1", Instrument.Lead)!;
        Assert.Equal((850L, 7, 60), (detail.Score, detail.Rank!.Value, detail.TotalEntries!.Value));
        var s2 = Row(vm, "s2");
        Assert.Equal("No score", s2.ScoreState);
        Assert.NotNull(s2.Warning);
    }

    [Fact]
    public async Task Rows_HiddenChartsDoNotRaiseTheIndicator()
    {
        var (_, vm) = await OpenSongs(new AppSettings { ShowInstrumentIcons = true, VisibleInstruments = [Instrument.Bass] });
        Assert.All(vm.Sections.SelectMany(s => s.Rows), r => Assert.Null(r.Warning));
    }

    [Fact]
    public async Task Rows_OverThresholdCheckShowsTheGoldWarning()
    {
        var (_, vm) = await OpenSongs(new AppSettings
        {
            ShowInstrumentIcons = true, VisibleInstruments = [Instrument.Lead],
            PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true),
        });
        var s1 = Row(vm, "s1");
        Assert.True(s1.Warning!.Warning);
        Assert.StartsWith("Title s1 has a score on Lead that exceeds the CHOpt maximum.", s1.Warning.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RowSameContent_ComparesTheIndicator()
    {
        var song = new Song { SongId = "s1", Title = "T", Artist = "A" };
        var warning = InvalidScoreWarning.Of("T", Reasons((Instrument.Lead, InvalidScoreReason.Fallback)), null);
        var gold = InvalidScoreWarning.Of("T", Reasons((Instrument.Lead, InvalidScoreReason.OverThreshold)), null);
        Assert.True(new SongRowItem(song).SameContent(new SongRowItem(song)));
        Assert.False(new SongRowItem(song) { Warning = warning }.SameContent(new SongRowItem(song)));
        Assert.False(new SongRowItem(song).SameContent(new SongRowItem(song) { Warning = warning }));
        Assert.True(new SongRowItem(song) { Warning = warning }.SameContent(new SongRowItem(song) { Warning = warning }));
        Assert.False(new SongRowItem(song) { Warning = warning }.SameContent(new SongRowItem(song) { Warning = gold }));
    }
    #endregion

    #region Song Detail
    [Fact]
    public async Task SongDetail_PlayerRowShowsTheFilteredScoreAndFollowsTheLeeway()
    {
        // s2 Lead: invalid below leeway 3 with a variant ranked 25 (web filterPlayerScores; no Over CHOpt exemption here).
        var variant = ""","ml":3.0,"vs":[{"sc":800,"ml":-5,"rt":[{"l":-5,"r":25}]}]""";
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One", PlayerWire.Score("s2", "01", 900, 950, false, 5, 30, 100, 30, variant));
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var session = service.Session(settings: new AppSettings
        {
            SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true, Leeway = 1,
            PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true),
        });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s2"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.Equal(("#25", "800"), (lead.Rows[10].Rank, lead.Rows[10].Score));

        session.UpdateSettings(s => s with { Leeway = 4 });
        Assert.Equal(("#30", "900"), (lead.Rows[10].Rank, lead.Rows[10].Score));

        session.UpdateSettings(s => s with { Leeway = 1 });
        Assert.Equal("800", lead.Rows[10].Score);
        session.UpdateSettings(s => s with { FilterInvalidScores = false });
        Assert.Equal("900", lead.Rows[10].Score);
        vm.Detach();
    }

    [Fact]
    public async Task SongDetail_DroppedScoreRemovesThePlayerRow()
    {
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One", PlayerWire.Score("s2", "01", 900, 950, false, 5, 30, 100, 30, ""","ml":3.0"""));
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s2"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.Equal(10, lead.Rows.Count);
        Assert.False(lead.HasPlayerRow);
        Assert.Null(SongScoreSource.ForDetail(session, null).Reason!("s2", Instrument.Lead));
    }
    #endregion
}
