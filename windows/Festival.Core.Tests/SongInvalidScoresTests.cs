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
}
