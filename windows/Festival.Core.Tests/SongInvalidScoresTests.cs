using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Filter Invalid Scores on Songs (web substitution) and the Over CHOpt Threshold check.</summary>
public class SongInvalidScoresTests
{
    private static readonly Song Chart = new()
    {
        SongId = "s1", Title = "T", Artist = "A",
        Difficulty = new SongDifficulty { Guitar = 3 },
        MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 1000 },
    };

    private static PlayerScore Score(int score, double? minLeeway = null, IReadOnlyList<PlayerValidScoreVariant>? variants = null,
        int? validScore = null) => new()
    {
        SongId = "s1", InstrumentCode = "01", Score = score, RawAccuracy = 990, IsFullCombo = true, Stars = 6, Rank = 1, TotalEntries = 50,
        MinLeeway = minLeeway, ValidScores = variants, ValidScore = validScore, RawValidAccuracy = 950, ValidIsFullCombo = false,
    };

    private static List<string> Ids(SongsViewModel vm) => [.. vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId)];

    private static InvalidScoreResolution Resolve(PlayerScore score, double leeway = 1, bool over = false) =>
        InvalidScorePolicy.Resolve(score, SongScoreSource.ToDetail(score), Chart, Instrument.Lead, leeway, over);

    [Fact]
    public void Validity_UsesMinLeewayElseTheChoptMaximumPlusLeeway()
    {
        Assert.Equal(1010, InvalidScorePolicy.Threshold(Chart, Instrument.Lead, 1));
        Assert.Null(InvalidScorePolicy.Threshold(Chart, Instrument.Bass, 1));
        Assert.Null(InvalidScorePolicy.Threshold(null, Instrument.Lead, 1));
        Assert.True(InvalidScorePolicy.IsValid(Score(1010), Chart, Instrument.Lead, 1));
        Assert.False(InvalidScorePolicy.IsValid(Score(1011), Chart, Instrument.Lead, 1));
        Assert.True(InvalidScorePolicy.IsValid(Score(5000), Chart, Instrument.Bass, 1)); // no maximum: not judgeable
        Assert.True(InvalidScorePolicy.IsValid(Score(5000, minLeeway: 0.5), Chart, Instrument.Lead, 1));
        Assert.False(InvalidScorePolicy.IsValid(Score(1, minLeeway: 2), Chart, Instrument.Lead, 1));
        Assert.True(InvalidScorePolicy.IsOverThreshold(1011, Chart, Instrument.Lead, 1));
        Assert.False(InvalidScorePolicy.IsOverThreshold(0, Chart, Instrument.Lead, -5));
        Assert.False(InvalidScorePolicy.IsOverThreshold(9999, Chart, Instrument.Bass, 1));
    }

    [Fact]
    public void RankAt_TakesTheLastChangepointAtOrBelowTheLeeway()
    {
        PlayerRankTier[] tiers = [new(-5, 9), new(0, 7), new(2, 4)];
        Assert.Null(InvalidScorePolicy.RankAt(tiers, -6));
        Assert.Equal(7, InvalidScorePolicy.RankAt(tiers, 1));
        Assert.Equal(4, InvalidScorePolicy.RankAt(tiers, 5));
        Assert.Null(InvalidScorePolicy.RankAt(null, 1));
    }

    [Fact]
    public void Resolve_FallbackVariantLegacyDroppedOrRaw()
    {
        var valid = Resolve(Score(900));
        Assert.Equal((900L, (InvalidScoreReason?)null), (valid.Detail!.Score, valid.Reason));

        var variant = new PlayerValidScoreVariant { Score = 950, RawAccuracy = 970, IsFullCombo = false, Stars = 5, MinLeeway = -1, RankTiers = [new(-5, 3)] };
        var fallback = Resolve(Score(2000, variants: [new PlayerValidScoreVariant { Score = 999, MinLeeway = 3 }, variant]));
        Assert.Equal(InvalidScoreReason.Fallback, fallback.Reason);
        Assert.Equal((950L, 970_000d, false, 5, 3), (fallback.Detail!.Score, fallback.Detail.Accuracy!.Value, fallback.Detail.IsFullCombo!.Value,
            fallback.Detail.Stars!.Value, fallback.Detail.Rank!.Value));
        // A variant without its own values keeps the raw ones.
        var bare = Resolve(Score(2000, variants: [new PlayerValidScoreVariant { Score = 800, MinLeeway = 0 }]));
        Assert.Equal((800L, true, 6, 1), (bare.Detail!.Score, bare.Detail.IsFullCombo!.Value, bare.Detail.Stars!.Value, bare.Detail.Rank!.Value));

        var none = Resolve(Score(2000, variants: [new PlayerValidScoreVariant { Score = 999, MinLeeway = 3 }]));
        Assert.Equal((null, InvalidScoreReason.NoFallback), (none.Detail, none.Reason));

        var legacy = Resolve(Score(2000, validScore: 990));
        Assert.Equal(InvalidScoreReason.Fallback, legacy.Reason);
        Assert.Equal((990L, 0, 950_000d, false), (legacy.Detail!.Score, legacy.Detail.Rank!.Value, legacy.Detail.Accuracy!.Value, legacy.Detail.IsFullCombo!.Value));

        Assert.Equal((null, InvalidScoreReason.NoFallback), (Resolve(Score(2000)).Detail, Resolve(Score(2000)).Reason));

        var raw = Resolve(Score(2000, validScore: 990), over: true);
        Assert.Equal((2000L, InvalidScoreReason.OverThreshold), (raw.Detail!.Score, raw.Reason));
    }

    [Fact]
    public void ResolveFiltered_SongDetailsUsesTheWebFilterPlayerScoresRule()
    {
        static InvalidScoreResolution Filtered(PlayerScore score) =>
            InvalidScorePolicy.ResolveFiltered(score, SongScoreSource.ToDetail(score), Chart, Instrument.Lead, 1);

        // minLeeway present and invalid: only validScores may replace it, never the legacy fields (web filterPlayerScores).
        var noVariants = Filtered(Score(500, minLeeway: 2, validScore: 450));
        Assert.Equal((null, InvalidScoreReason.NoFallback), (noVariants.Detail, noVariants.Reason));
        Assert.Equal(450L, Resolve(Score(500, minLeeway: 2, validScore: 450)).Detail!.Score); // Songs' effectiveScores keeps legacy
        var variant = Filtered(Score(500, minLeeway: 2, variants: [new PlayerValidScoreVariant { Score = 400, MinLeeway = 0 }], validScore: 450));
        Assert.Equal((400L, InvalidScoreReason.Fallback), (variant.Detail!.Score, variant.Reason));
        Assert.Equal(500L, Filtered(Score(500, minLeeway: 0.5, validScore: 450)).Detail!.Score);

        // Without minLeeway: the CHOpt ceiling and the legacy fallback apply, and there is no Over CHOpt Threshold exemption.
        Assert.Equal((990L, InvalidScoreReason.Fallback), (Filtered(Score(2000, validScore: 990)).Detail!.Score, Filtered(Score(2000, validScore: 990)).Reason));
        Assert.Null(Filtered(Score(2000)).Detail);
    }

    [Fact]
    public void Filter_OverThresholdNeedsARawScoreOverTheMaximum()
    {
        var songs = new[] { Chart, Chart with { SongId = "s2" }, Chart with { SongId = "s3" } };
        var filter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true);
        Assert.True(filter.IsActive);
        Assert.True(filter.Contains(SongScoreFilterKind.OverThreshold, Instrument.Lead));
        ChartScoreFacts? Facts(string id, Instrument _) => id switch
        {
            "s1" => new ChartScoreFacts(2000, true, OverThreshold: true),
            "s2" => new ChartScoreFacts(900, true),
            _ => null,
        };
        Assert.Equal(["s1"], filter.Filter(songs, Facts, InstrumentInfo.All, null).Select(s => s.SongId));
        // Off while Filter Invalid Scores is off (kept saved), like the web.
        Assert.Same(filter, filter.Effective(true));
        Assert.False(filter.Effective(false).IsActive);
        Assert.Same(SongPlayerScoreFilter.None, SongPlayerScoreFilter.None.Effective(false));
        Assert.Empty(filter.ScopedTo([Instrument.Bass]).OverThreshold);
        Assert.False(filter.Equals(SongPlayerScoreFilter.None));
        Assert.False(SongPlayerScoreFilter.Repaired(new SongPlayerScoreFilter { OverThreshold = null! }).IsValid);
        Assert.Empty(filter.CleanedFor(Instrument.Lead).OverThreshold);
    }

    [Fact]
    public void Pipeline_AppliesOverThresholdOnlyUnderFilterInvalidScores()
    {
        var songs = new[] { Chart, Chart with { SongId = "s2" } };
        var filter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true);
        ChartScoreFacts? Facts(string id, Instrument _) => id == "s1" ? new ChartScoreFacts(2000, null, true) : new ChartScoreFacts(900, null);
        SongListResult Run(bool invalid) => SongListPipeline.Run(new SongListInputs
        {
            Songs = songs, PlayerFilter = filter, HasPlayer = true, FilterInvalidScores = invalid, Scores = Facts,
        });
        Assert.Equal(1, Run(true).Count);
        Assert.True(Run(true).FiltersApplied);
        Assert.Equal(2, Run(false).Count);
        Assert.Null(Run(false).ScoreFilterPaused);
    }

    [Fact]
    public void Draft_OffersOverThresholdOnlyUnderFilterInvalidScores()
    {
        var service = new FakeService();
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var draft = new SongFilterDraft(session);
        draft.Begin();
        Assert.DoesNotContain(draft.GlobalRows, r => r.Label == "Over CHOpt Threshold");
        Assert.DoesNotContain(draft.ScoreRows[0].Toggles, r => r.Label.EndsWith("Over CHOpt Threshold", StringComparison.Ordinal));
        session.UpdateSettings(s => s with { FilterInvalidScores = true });
        draft.Begin();
        var global = draft.GlobalRows.Single(r => r.Label == "Over CHOpt Threshold");
        Assert.Equal("fst.songs.filter.score.global.over-threshold", global.AutomationId);
        Assert.StartsWith("Songs with scores above the configured CHOpt max", global.Description, StringComparison.Ordinal);
        var lead = draft.ScoreRows.Single(r => r.Instrument == Instrument.Lead).Toggles.Single(r => r.Label == "Lead Over CHOpt Threshold");
        Assert.Equal("fst.songs.filter.score.chart.lead.over-threshold", lead.AutomationId);
        Assert.Equal("Songs with Lead scores above the configured CHOpt max score threshold in app settings.", lead.Description);
        lead.IsOn = true;
        Assert.True(draft.ScoreFilter.Contains(SongScoreFilterKind.OverThreshold, Instrument.Lead));
        global.IsOn = true;
        Assert.True(draft.ScoreFilter.AllVisible(SongScoreFilterKind.OverThreshold, session.Settings.VisibleInstruments));
    }

    [Fact]
    public async Task Songs_ResolveInvalidScoresAndShowRawOnesForOverThreshold()
    {
        // s1 Lead: invalid at leeway 1 with a valid variant; s2 Lead: invalid with no fallback; s3 Lead: valid.
        var fallback = ""","ml":2.0,"vs":[{"sc":850,"acc":960,"fc":false,"st":5,"ml":-5,"rt":[{"l":-5,"r":7}]}]""";
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One",
            PlayerWire.Score("s1", "01", 1000, 990, true, 6, 1, 100, 1.0, fallback),
            PlayerWire.Score("s2", "01", 900, 950, false, 5, 30, 100, 30, ""","ml":3.0"""),
            PlayerWire.Score("s3", "01", 700, 1000, true, 6, 4, 200, 2));
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var session = service.Session(settings: new AppSettings
        {
            SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true,
            PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Lead, true),
        });
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        // The no-fallback score is dropped (web), the fallback counts as a score.
        Assert.Equal(["s1", "s3"], Ids(vm).Order());
        var source = SongScoreSource.ForSongs(session, session.Catalog!.Songs);
        Assert.Equal(850, source.Detail!("s1", Instrument.Lead)!.Score);
        Assert.Equal(7, source.Detail!("s1", Instrument.Lead)!.Rank);
        Assert.Equal(InvalidScoreReason.Fallback, source.Reason!("s1", Instrument.Lead));
        Assert.Equal(InvalidScoreReason.NoFallback, source.Reason!("s2", Instrument.Lead));
        Assert.Null(source.Reason!("s3", Instrument.Lead));
        Assert.Null(source.Facts!("s2", Instrument.Lead));

        // Over CHOpt Threshold on Lead: only the raw invalid scores remain, shown raw.
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true) });
        Assert.Equal(["s1", "s2"], Ids(vm).Order());
        var raw = SongScoreSource.ForSongs(session, session.Catalog!.Songs);
        Assert.Equal((1000L, true), (raw.Facts!("s1", Instrument.Lead)!.Value.Score, raw.Facts!("s1", Instrument.Lead)!.Value.OverThreshold));
        Assert.Equal(InvalidScoreReason.OverThreshold, raw.Reason!("s2", Instrument.Lead));

        // Filter Invalid Scores off: raw scores, the saved Over CHOpt check stays but does nothing.
        session.UpdateSettings(s => s with { FilterInvalidScores = false });
        Assert.Equal(3, vm.ResultCount);
        Assert.Null(SongScoreSource.ForSongs(session, session.Catalog!.Songs).Reason!("s1", Instrument.Lead));
        Assert.Null(SongScoreSource.ForSongs(session, null).Reason!("s1", Instrument.Lead));
    }

    [Fact]
    public void PopulationTiers_DecodeLenientlyAndPickTheLeewayTotal()
    {
        static Song Decode(string tiers) => System.Text.Json.JsonSerializer.Deserialize(
            $$"""{"songId":"x","title":"X","artist":"Y","populationTiers":{{tiers}}}""", FestivalJsonContext.Default.Song)!;
        var song = Decode("""
            {"Solo_Guitar":{"bc":10,"t":[{"l":0.5,"t":12},{"l":1.0,"t":15}]},"Solo_Bass":null,"Solo_Drums":{"t":[1,2]},
             "Solo_Vocals":{"bc":1,"t":[{"l":2.0,"t":3},{"l":1.0,"t":4}]},"Solo_PeripheralGuitar":{"bc":-1,"t":[]},
             "Solo_PeripheralBass":{"bc":2,"t":[{"l":"x","t":3}]},"Solo_PeripheralVocals":[1],
             "Solo_PeripheralCymbals":{"bc":4,"t":[],"extra":{"a":[1]}}}
            """);
        Assert.Equal(10, song.FilteredPopulation(Instrument.Lead, 0.1));
        Assert.Equal(12, song.FilteredPopulation(Instrument.Lead, 0.7));
        Assert.Equal(15, song.FilteredPopulation(Instrument.Lead, 2.0));
        Assert.Equal(4, song.FilteredPopulation(Instrument.ProCymbals, 0));
        // Malformed curves (missing base, unsorted, negative, non-numeric, not an object) and absent charts: no curve.
        foreach (var chart in new[] { Instrument.Bass, Instrument.Drums, Instrument.Vocals, Instrument.ProLead, Instrument.ProBass, Instrument.Karaoke, Instrument.ProDrums })
            Assert.Null(song.FilteredPopulation(chart, 1));
        Assert.Null(Decode("[1]").PopulationTiers);
        Assert.Null(Decode("null").PopulationTiers);
        Assert.Null(new Song().FilteredPopulation(Instrument.Lead, 1));
        // Round trip keeps the well-formed curves.
        var again = System.Text.Json.JsonSerializer.Deserialize(System.Text.Json.JsonSerializer.Serialize(song, FestivalJsonContext.Default.Song), FestivalJsonContext.Default.Song)!;
        Assert.Equal([12, 4], new[] { again.FilteredPopulation(Instrument.Lead, 0.7)!.Value, again.FilteredPopulation(Instrument.ProCymbals, 0)!.Value });
        Assert.Null(System.Text.Json.JsonSerializer.Deserialize(System.Text.Json.JsonSerializer.Serialize(new Song(), FestivalJsonContext.Default.Song), FestivalJsonContext.Default.Song)!.PopulationTiers);
    }

    [Fact]
    public void Resolve_FallbackUsesTheFilteredPopulationAndLegacyFieldsLikeTheWeb()
    {
        var tiered = Chart with { PopulationTiers = new Dictionary<string, PopulationTiers> { ["Solo_Guitar"] = new(40, [new(0.5, 44), new(1.5, 48)]) } };
        InvalidScoreResolution At(PlayerScore score, double leeway) =>
            InvalidScorePolicy.Resolve(score, SongScoreSource.ToDetail(score), tiered, Instrument.Lead, leeway, false);
        var invalid = Score(2000, minLeeway: 3, variants: [new PlayerValidScoreVariant { Score = 900, MinLeeway = -5 }]);
        Assert.Equal(44, At(invalid, 1).Detail!.TotalEntries);
        Assert.Equal(40, At(invalid, 0.2).Detail!.TotalEntries);
        Assert.Equal(48, At(invalid, 2).Detail!.TotalEntries);
        // A valid raw score keeps its own population (web uses the raw te).
        Assert.Equal(50, At(Score(900), 1).Detail!.TotalEntries);

        var legacy = Score(2000, validScore: 990) with { ValidRank = 9, ValidStars = 4, ValidTotalEntries = 45 };
        var substituted = At(legacy, 1).Detail!;
        Assert.Equal((990L, 9, 4, 45), (substituted.Score, substituted.Rank!.Value, substituted.Stars!.Value, substituted.TotalEntries!.Value));
        Assert.True(legacy.IsValid);
        Assert.False((legacy with { ValidStars = 7 }).IsValid);
        Assert.False((legacy with { ValidRank = -1 }).IsValid);
        Assert.False((legacy with { ValidTotalEntries = -1 }).IsValid);

        var wire = System.Text.Json.JsonSerializer.Deserialize(
            PlayerWire.Score("s1", extra: ""","validScore":5,"validRank":2,"validStars":3,"validTotalEntries":4"""), PlayerJsonContext.Default.PlayerScore)!;
        Assert.Equal((2, 3, 4), (wire.ValidRank!.Value, wire.ValidStars!.Value, wire.ValidTotalEntries!.Value));
    }

    [Fact]
    public void Warning_ExplainsEachCaseLikeTheWebIcon()
    {
        var lead = Instrument.Lead;
        const string Footer = "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings.";
        const string Footers = "To see the absolute highest scores you've achieved, toggle off 'Filter Invalid Scores' in App Settings.";
        const string ChipsHint = "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument.";

        var one = InvalidScoreWarning.Of("Song", new Dictionary<Instrument, InvalidScoreReason> { [lead] = InvalidScoreReason.Fallback }, null)!;
        Assert.False(one.IsWarning);
        Assert.Equal($"Song has an invalid, filtered-out score on Lead. The Lead chip reflects the next valid score.\n\n{Footer} {ChipsHint}", one.Message);
        Assert.Equal(("Filtered Score", "Invalid score indicator", "OK", "Settings"),
            (InvalidScoreWarning.Title, InvalidScoreWarning.Label, InvalidScoreWarning.OkCommand, InvalidScoreWarning.SettingsCommand));
        Assert.Equal("fst.songs.invalid-score.s1", InvalidScoreWarning.AutomationId("s1"));

        var mixed = new Dictionary<Instrument, InvalidScoreReason>
        {
            [Instrument.Drums] = InvalidScoreReason.NoFallback, [lead] = InvalidScoreReason.Fallback,
            [Instrument.Bass] = InvalidScoreReason.Fallback, [Instrument.Vocals] = InvalidScoreReason.OverThreshold,
        };
        var chips = InvalidScoreWarning.Of("Song", mixed, null)!;
        Assert.Equal([lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals], chips.Reasons.Select(r => r.Key));
        Assert.False(chips.IsWarning);
        Assert.Equal(
            "Song has an invalid, filtered-out score on Lead, Bass, Drums, and Tap Vocals. The chips for these instruments reflect the next valid score. " +
            "Because there is no valid other score for Drums, the Drums icon chip is red here. The Tap Vocals score shown exceeds the CHOpt maximum." +
            $"\n\n{Footers} {ChipsHint}", chips.Message);

        var filtered = InvalidScoreWarning.Of("Song", mixed, lead)!;
        Assert.Equal([lead], filtered.Reasons.Select(r => r.Key));
        Assert.Equal("Song has an invalid, filtered-out score on Lead. We are showing the next valid score here." +
            $"\n\n{Footer} You can also temporarily filter to 'Lead Over CHOpt Threshold' in the Filter modal.", filtered.Message);

        var over = InvalidScoreWarning.Of("Song", mixed, Instrument.Vocals)!;
        Assert.True(over.IsWarning);
        Assert.Equal("Song has a score on Tap Vocals that exceeds the CHOpt maximum. This is the highest unfiltered invalid score.", over.Message);
        var twoOver = InvalidScoreWarning.Of("Song", new Dictionary<Instrument, InvalidScoreReason>
            { [lead] = InvalidScoreReason.OverThreshold, [Instrument.Bass] = InvalidScoreReason.OverThreshold }, null)!;
        Assert.True(twoOver.IsWarning);
        Assert.StartsWith("Song has a score on Lead and Bass that exceeds", twoOver.Message, StringComparison.Ordinal);

        Assert.Null(InvalidScoreWarning.Of("Song", mixed, Instrument.ProBass));
        Assert.Null(InvalidScoreWarning.Of("Song", new Dictionary<Instrument, InvalidScoreReason>(), null));
        Assert.True(one.SameAs(InvalidScoreWarning.Of("Song", new Dictionary<Instrument, InvalidScoreReason> { [lead] = InvalidScoreReason.Fallback }, null)));
        Assert.False(one.SameAs(filtered));
        Assert.False(one.SameAs(null));
    }

    [Fact]
    public async Task Songs_RowsCarryTheWarningAndUpdateInPlace()
    {
        var fallback = ""","ml":2.0,"vs":[{"sc":850,"acc":960,"fc":false,"st":5,"ml":-5,"rt":[{"l":-5,"r":7}]}]""";
        var profile = PlayerWire.Profile(PlayerWire.Id, "Fixture One",
            PlayerWire.Score("s1", "01", 1000, 990, true, 6, 1, 100, 1.0, fallback),
            PlayerWire.Score("s2", "01", 900, 950, false, 5, 30, 100, 30, ""","ml":3.0"""),
            PlayerWire.Score("s3", "01", 700, 1000, true, 6, 4, 200, 2));
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.OK, profile) });
        var session = service.Session(settings: new AppSettings
        {
            SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One"), FilterInvalidScores = true,
        });
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        SongRowItem Row(string id) => vm.Sections.SelectMany(s => s.Rows).Single(r => r.Song.SongId == id);

        // Chips: the fallback chip counts as scored, the dropped one as no score; both rows warn in red.
        var s1 = Row("s1");
        Assert.Equal(InvalidScoreReason.Fallback, Assert.Single(s1.Warning!.Reasons).Value);
        Assert.False(s1.Warning.IsWarning);
        Assert.Contains("The Lead chip reflects the next valid score.", s1.Warning.Message, StringComparison.Ordinal);
        Assert.EndsWith(", Filtered score", s1.Announcement, StringComparison.Ordinal);
        Assert.Equal(SongInstrumentStatus.Scored, s1.Chips.Single(c => c.Instrument == Instrument.Lead).Status);
        Assert.Equal(SongInstrumentStatus.NoScore, Row("s2").Chips.Single(c => c.Instrument == Instrument.Lead).Status);
        Assert.Equal(InvalidScoreReason.NoFallback, Assert.Single(Row("s2").Warning!.Reasons).Value);
        Assert.Null(Row("s3").Warning);

        // Lead filter: metadata shows the effective score; the warning speaks about the shown score.
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Lead) });
        Assert.Contains(Row("s1").Metadata, m => m.Announcement.Contains("850", StringComparison.Ordinal));
        Assert.Contains("We are showing the next valid score here.", Row("s1").Warning!.Message, StringComparison.Ordinal);

        // Over CHOpt Threshold on Lead: the raw invalid scores show, with the gold warning.
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.OverThreshold, Instrument.Lead, true) });
        Assert.True(Row("s1").Warning!.IsWarning);
        Assert.EndsWith(", Score over the CHOpt maximum", Row("s1").Announcement, StringComparison.Ordinal);

        // Leeway raised past both minimums: the raw scores are valid, no warning.
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None, Leeway = 5 });
        Assert.Null(Row("s1").Warning);
        Assert.Contains(Row("s1").Metadata, m => m.Announcement.Contains("1,000", StringComparison.Ordinal));

        // Filter Invalid Scores off: raw scores, no warning, no reload.
        session.UpdateSettings(s => s with { Leeway = 1, FilterInvalidScores = false });
        Assert.Null(Row("s1").Warning);
        Assert.Null(Row("s2").Warning);
        Assert.Single(service.Handler.To("/api/songs"));
    }
}
