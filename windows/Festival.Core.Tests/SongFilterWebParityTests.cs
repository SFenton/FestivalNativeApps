using Festival.Core.Data;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongBucketsTests
{
    [Fact]
    public void Keys_MatchTheWebToggleLists()
    {
        Assert.Equal([0, 1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100], SongBucketKind.Percentile.Keys());
        Assert.Equal([6, 5, 4, 3, 2, 1, 0], SongBucketKind.Stars.Keys());
        Assert.Equal([1, 2, 3, 4, 5, 6, 7, 0], SongBucketKind.Intensity.Keys());
        Assert.Equal([3, 9, 12, 0], SongBucketKind.Season.Keys([12, 3, 9, 3, 0, -1, 1000]));
        Assert.Equal([0], SongBucketKind.Season.Keys());
        Assert.Equal(SongBuckets.PercentileThresholds, PlayerStatistics.PercentileThresholds);
    }

    [Fact]
    public void TitlesHintsIdsAndLabels()
    {
        Assert.Equal(["Season", "Percentile", "Stars", "Song Intensity"], SongBuckets.All.Select(k => k.Title()));
        Assert.Equal(["season", "percentile", "stars", "intensity"], SongBuckets.All.Select(k => k.Id()));
        Assert.All(SongBuckets.All, k => Assert.EndsWith(".", k.Hint()));
        Assert.Equal([true, true, true, false], SongBuckets.All.Select(k => k.IsPlayerScoped()));
        Assert.Equal(["No Score", "Season 7"], new[] { 0, 7 }.Select(k => SongBucketKind.Season.Label(k)));
        Assert.Equal("Top 25%", SongBucketKind.Percentile.Label(25));
        Assert.Equal(["Gold Stars", "1 Star", "No Score"], new[] { 6, 1, 0 }.Select(k => SongBucketKind.Stars.Label(k)));
        Assert.Equal("Intensity 3 of 7", SongBucketKind.Intensity.Label(3));
    }

    [Fact]
    public void ScoreBuckets_FollowTheWebRules()
    {
        var scored = new SongScoreDetail(1000, Stars: 6, Season: 9, Rank: 31, TotalEntries: 100);
        Assert.Equal((9, 40, 6), (SongBuckets.SeasonOf(scored), SongBuckets.PercentileOf(scored), SongBuckets.StarsOf(scored)));
        Assert.Equal((0, 0, 0), (SongBuckets.SeasonOf(null), SongBuckets.PercentileOf(null), SongBuckets.StarsOf(null)));
        var zero = scored with { Score = 0 };
        Assert.Equal((0, 0, 0), (SongBuckets.SeasonOf(zero), SongBuckets.PercentileOf(zero), SongBuckets.StarsOf(zero)));
        var unranked = new SongScoreDetail(5, Stars: null, Season: null);
        Assert.Equal((0, 0, 0), (SongBuckets.SeasonOf(unranked), SongBuckets.PercentileOf(unranked), SongBuckets.StarsOf(unranked)));
        Assert.Equal((1, 7, 7, 0), (SongBuckets.IntensityOf(0), SongBuckets.IntensityOf(6.9), SongBuckets.IntensityOf(99), SongBuckets.IntensityOf(null)));
    }

    [Fact]
    public void Validation_BoundsKnownAndDistinct()
    {
        Assert.True(SongBuckets.AreValid(SongBucketKind.Season, [0, 999]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Season, [1000]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Percentile, [6]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Stars, [7]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Intensity, [8]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Stars, [1, 1]));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Stars, null));
        Assert.False(SongBuckets.AreValid(SongBucketKind.Season, [.. Enumerable.Range(0, 65)]));
        Assert.Equal([1, 4], SongBuckets.Normalize([4, 1, 4]));
    }
}

public class SongPlayerScoreFilterBucketTests
{
    private static readonly Song A = new() { SongId = "a", Title = "A", Artist = "x", Difficulty = new SongDifficulty { Guitar = 2, Bass = 3 } };
    private static readonly Song B = new() { SongId = "b", Title = "B", Artist = "x", Difficulty = new SongDifficulty { Guitar = 4 } };

    private static SongScoreDetail? Detail(string id, Instrument chart) => (id, chart) switch
    {
        ("a", Instrument.Lead) => new SongScoreDetail(100, IsFullCombo: true, Stars: 6, Season: 3, Rank: 1, TotalEntries: 100),
        ("b", Instrument.Lead) => new SongScoreDetail(50, Stars: 4, Season: 5, Rank: 60, TotalEntries: 100),
        _ => null,
    };

    private static ChartScoreFacts? Facts(string id, Instrument chart) => Detail(id, chart)?.Facts;

    [Fact]
    public void Buckets_NeedADetailSourceAndAVisibleChart()
    {
        var filter = SongPlayerScoreFilter.None.Only(SongBucketKind.Stars, 6);
        Assert.True(filter.HasBucketChecks && !filter.HasChecks);
        Assert.False(filter.AppliesTo(null));
        Assert.True(filter.AppliesTo(Instrument.Lead));
        Song[] songs = [A, B];
        Assert.Equal(["a"], filter.Filter(songs, Facts, InstrumentInfo.All, Instrument.Lead, Detail).Select(s => s.SongId));
        Assert.Equal(2, filter.Filter(songs, Facts, InstrumentInfo.All, Instrument.Lead).Count);
        Assert.Equal(2, filter.Filter(songs, Facts, InstrumentInfo.All, null, Detail).Count);
        Assert.Equal(2, filter.Filter(songs, Facts, [Instrument.Bass], Instrument.Lead, Detail).Count);
        // Checks and buckets combine: AND across the two groups.
        var both = filter.With(SongScoreFilterKind.HasScores, Instrument.Lead, true);
        Assert.Equal(["a"], both.Filter(songs, Facts, InstrumentInfo.All, Instrument.Lead, Detail).Select(s => s.SongId));
        var season = SongPlayerScoreFilter.None.WithExcluded(SongBucketKind.Season, [3]);
        Assert.Equal(["b"], season.Filter(songs, Facts, InstrumentInfo.All, Instrument.Lead, Detail).Select(s => s.SongId));
        var pct = SongPlayerScoreFilter.None.Only(SongBucketKind.Percentile, 60);
        Assert.Equal(["b"], pct.Filter(songs, Facts, InstrumentInfo.All, Instrument.Lead, Detail).Select(s => s.SongId));
        // No score on Bass: only the No Score (0) bucket keeps them.
        Assert.Equal(2, SongPlayerScoreFilter.None.Only(SongBucketKind.Stars, 0).Filter(songs, Facts, InstrumentInfo.All, Instrument.Bass, Detail).Count);
    }

    [Fact]
    public void Editing_CleaningAndEquality()
    {
        var filter = SongPlayerScoreFilter.None
            .WithExcluded(SongBucketKind.Season, [5, 1, 5])
            .WithExcluded(SongBucketKind.Intensity, [1])
            .With(SongScoreFilterKind.HasFCs, Instrument.Lead, true)
            .With(SongScoreFilterKind.HasFCs, Instrument.Bass, true);
        Assert.Equal([1, 5], filter.Excluded(SongBucketKind.Season));
        Assert.Empty(filter.Excluded(SongBucketKind.Intensity));
        var cleaned = filter.CleanedFor(Instrument.Lead);
        Assert.False(cleaned.HasBucketChecks);
        Assert.Equal([Instrument.Bass], cleaned.HasFCs);
        Assert.Equal(filter, filter with { });
        Assert.NotEqual(filter, cleaned);
        Assert.Equal(filter.GetHashCode(), (filter with { }).GetHashCode());
        Assert.True(filter.ScopedTo([Instrument.Bass]).HasBucketChecks);
    }

    [Fact]
    public void Repaired_TurnsNullListsIntoAResetPrompt()
    {
        Assert.Same(SongPlayerScoreFilter.None, SongPlayerScoreFilter.Repaired(null));
        Assert.True(SongPlayerScoreFilter.Repaired(new SongPlayerScoreFilter()).IsValid);
        Assert.False(SongPlayerScoreFilter.Repaired(new SongPlayerScoreFilter { ExcludedStars = null! }).IsValid);
        Assert.False(SongPlayerScoreFilter.Repaired(new SongPlayerScoreFilter { HasFCs = null! }).IsValid);
        Assert.False(new SongPlayerScoreFilter { ExcludedPercentiles = [7] }.IsValid);
    }
}

public class SongFilterMigrationTests : IDisposable
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "fst-tests-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
    }

    private AppSettings Load(string json, out string path)
    {
        path = Path.Combine(directory, "settings.json");
        Directory.CreateDirectory(directory);
        File.WriteAllText(path, json);
        return new JsonFileSettingsStore(path).Load();
    }

    [Fact]
    public void Version1_RangeAndBandBecomeBuckets()
    {
        var settings = Load("""
            {"version":1,"songFilter":{"Instrument":"Lead","MinDifficulty":3,"MaxDifficulty":5},
             "songScoreBandFilter":{"instrument":"Lead","topPercent":5,"stars":6},
             "songPlayerScoreFilter":{"missingScores":[],"hasScores":["Bass"],"missingFCs":[],"hasFCs":[]}}
            """, out var path);
        Assert.Equal(AppSettings.CurrentVersion, settings.Version);
        Assert.Equal(new SongFilter(Instrument.Lead, [1, 2, 6, 7]), settings.SongFilter);
        Assert.Null(settings.SongFilter.LegacyMinDifficulty);
        Assert.Null(settings.LegacyScoreBandFilter);
        Assert.Equal(SongBuckets.PercentileKeys.Where(k => k != 5).Order(), settings.PlayerScoreFilter.ExcludedPercentiles);
        Assert.Equal([0, 1, 2, 3, 4, 5], settings.PlayerScoreFilter.ExcludedStars);
        Assert.Equal([Instrument.Bass], settings.PlayerScoreFilter.HasScores);
        new JsonFileSettingsStore(path).Save(settings);
        var text = File.ReadAllText(path);
        Assert.DoesNotContain("MinDifficulty", text);
        Assert.DoesNotContain("songScoreBandFilter", text);
        Assert.Contains("\"version\": 3", text);
        Assert.Equal(settings, new JsonFileSettingsStore(path).Load());
    }

    [Fact]
    public void Version2_GeneralAndShopAvailabilityMigrateAndRoundTrip()
    {
        var settings = Load("""
            {"version":2,
             "songGeneralFilter":{"excludedDecades":[1980],"excludedDurationBuckets":[0,10],"doubleBassSupported":true,"doubleBassUnsupported":false},
             "songShopFilter":{"inShop":true,"leavingTomorrow":true}}
            """, out var path);
        Assert.Equal(AppSettings.CurrentVersion, settings.Version);
        Assert.Equal([1980], settings.GeneralFilter.ExcludedDecades);
        Assert.Equal([0, 10], settings.GeneralFilter.ExcludedDurationBuckets);
        Assert.False(settings.GeneralFilter.DoubleBassUnsupported);
        Assert.True(settings.ShopFilter.Available);
        Assert.False(settings.ShopFilter.Unavailable);
        new JsonFileSettingsStore(path).Save(settings);
        var text = File.ReadAllText(path);
        Assert.Contains("\"available\": true", text);
        Assert.Contains("\"unavailable\": false", text);
        Assert.DoesNotContain("inShop", text);
        Assert.DoesNotContain("leavingTomorrow", text);
        Assert.Equal(settings, new JsonFileSettingsStore(path).Load());
    }

    [Fact]
    public void Version1_UnmappableChoicesAreDropped()
    {
        // A range without a chart has no web equivalent; a band on another chart, or an invalid band, is dropped.
        var noChart = Load("""{"version":1,"songFilter":{"MinDifficulty":2,"MaxDifficulty":4},"songScoreBandFilter":{"instrument":"Bass","stars":5}}""", out _);
        Assert.Equal(SongFilter.None, noChart.SongFilter);
        Assert.False(noChart.PlayerScoreFilter.IsActive);
        var inverted = Load("""{"version":1,"songFilter":{"Instrument":"Drums","MinDifficulty":6,"MaxDifficulty":2},"songScoreBandFilter":{"instrument":"Drums","topPercent":7}}""", out _);
        Assert.Equal(new SongFilter(Instrument.Drums), inverted.SongFilter);
        Assert.False(inverted.PlayerScoreFilter.IsActive);
        var full = Load("""{"version":1,"songFilter":{"Instrument":"Bass","MinDifficulty":1,"MaxDifficulty":7}}""", out _);
        Assert.Equal(new SongFilter(Instrument.Bass), full.SongFilter);
    }

    [Theory]
    [InlineData("""{"songFilter":{"Instrument":"Lead","excludedIntensities":[3,3]}}""")]
    [InlineData("""{"songFilter":{"Instrument":"Lead","excludedIntensities":null}}""")]
    [InlineData("""{"songGeneralFilter":{"excludedDecades":[1980,1980]}}""")]
    [InlineData("""{"songGeneralFilter":{"excludedDecades":[1985]}}""")]
    [InlineData("""{"songGeneralFilter":{"excludedDurationBuckets":[11]}}""")]
    [InlineData("""{"songGeneralFilter":{"excludedDurationBuckets":null}}""")]
    [InlineData("""{"songPlayerScoreFilter":{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":[],"excludedStars":[9]}}""")]
    [InlineData("""{"songPlayerScoreFilter":{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":[],"excludedSeasons":null}}""")]
    public async Task CorruptBuckets_BlockSongsUntilReset(string json)
    {
        var settings = Load(json, out _);
        Assert.False(settings.GeneralFilter.IsValid && settings.SongFilter.IsValid && settings.PlayerScoreFilter.IsValid);
        var session = new FakeService().Session(settings: settings);
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        Assert.True(vm.ShowInvalidFilter);
        Assert.Empty(vm.Sections);
        vm.FilterDraft.Begin();
        Assert.Equal(SongFilter.None, vm.FilterDraft.ToFilter());
        vm.ClearFilterCommand.Execute(null);
        Assert.False(vm.ShowInvalidFilter);
        Assert.True(vm.ShowList);
    }
}

public class SongFilterDraftWebTests
{
    [Fact]
    public async Task PlayerDraft_OffersEverySectionInWebOrder()
    {
        var (session, vm) = await SongsScoreBandTests.Loaded();
        var draft = vm.FilterDraft;
        draft.Begin();
        Assert.Equal(["Year", "Duration"], draft.GeneralSections.Select(s => s.Title));
        Assert.Equal(["Double Bass Support", "No Double Bass Support"], draft.DoubleBassRows.Select(r => r.Label));
        Assert.Equal(SongBuckets.All, draft.BucketSections.Select(s => s.Kind));
        var season = draft.BucketSections[0];
        Assert.Equal(["Season 9", "No Score"], season.Rows.Select(r => r.Label));
        Assert.Equal("fst.songs.filter.season.9", season.Rows[0].AutomationId);
        var stars = draft.BucketSections[2];
        Assert.Equal([6, 5, 4, 3, 2, 1, 0], stars.Rows.Select(r => r.Stars));
        Assert.True(stars.Rows[0].ShowStars && !stars.Rows[0].ShowText);
        Assert.Equal(["Available in Item Shop", "Not Available in Item Shop"], draft.ShopRows.Select(r => r.Label));
        Assert.True(draft.ShopRows.All(r => r.IsEnabled));

        var duration = draft.GeneralSections.Single(s => s.Kind == GeneralFilterSectionKind.Duration);
        duration.ClearAllCommand.Execute(null);
        Assert.Equal(duration.Keys, session.Settings.GeneralFilter.ExcludedDurationBuckets);
        duration.Rows[0].IsOn = true;
        Assert.DoesNotContain(0, session.Settings.GeneralFilter.ExcludedDurationBuckets);
        duration.SelectAllCommand.Execute(null);
        Assert.Empty(session.Settings.GeneralFilter.ExcludedDurationBuckets);
        draft.DoubleBassRows[1].IsOn = false;
        Assert.False(session.Settings.GeneralFilter.DoubleBassUnsupported);
        draft.DoubleBassRows[1].IsOn = true;

        draft.SelectedInstrument = Instrument.Lead;
        var percentile = draft.BucketSections[1];
        percentile.ClearAllCommand.Execute(null);
        percentile.Rows.Single(r => r.Label == "Top 1%").IsOn = true;
        Assert.Equal(["s1"], SongsScoreBandTests.Ids(vm));
        Assert.True(vm.IsFilterActive);
        percentile.SelectAllCommand.Execute(null);
        Assert.Empty(session.Settings.PlayerScoreFilter.ExcludedPercentiles);
        season.Rows[0].IsOn = false;
        Assert.False(season.Rows[0].IsOn);
        Assert.Equal([9], session.Settings.PlayerScoreFilter.ExcludedSeasons);
        draft.ShopRows[0].IsOn = true;
        draft.ShopRows[1].IsOn = false;
        Assert.True(session.Settings.ShopFilter.Available);
        Assert.False(session.Settings.ShopFilter.Unavailable);
        draft.ResetCommand.Execute(null);
        Assert.False(session.Settings.GeneralFilter.IsActive);
        Assert.False(session.Settings.PlayerScoreFilter.IsActive);
        Assert.False(session.Settings.ShopFilter.IsActive);
        Assert.Null(session.Settings.SongFilter.Instrument);
    }

    [Fact]
    public async Task HiddenShop_DisablesShopSwitches()
    {
        var (_, vm) = await SongsScoreBandTests.Loaded(settings: new AppSettings { HideShop = true, ShopFilter = new SongShopFilter(available: true, unavailable: false) });
        vm.FilterDraft.Begin();
        Assert.False(vm.FilterDraft.ShowShopFilter);
        Assert.True(vm.FilterDraft.ShopRows.All(r => !r.IsEnabled));
        Assert.True(vm.FilterDraft.ShopRows[0].IsOn);
    }

    [Fact]
    public async Task HiddenChecks_ClearAfterTheNextLiveChange()
    {
        var (session, vm) = await SongsScoreBandTests.Loaded();
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Drums, true) });
        session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Drums, false));
        vm.FilterDraft.Begin();
        Assert.True(vm.FilterDraft.HasHiddenScoreChecks);
        Assert.False(vm.FilterDraft.CanApply);
        vm.FilterDraft.ShopRows[1].IsOn = false;
        Assert.False(session.Settings.PlayerScoreFilter.IsActive);
        Assert.False(vm.FilterDraft.HasHiddenScoreChecks);
        Assert.False(vm.FilterDraft.CanApply);
    }
}
