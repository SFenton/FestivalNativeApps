using System.Net;
using System.Text.Json;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongListFilterTests
{
    private static Song S(string id, string title = "T", string artist = "A", int? year = 2020, string difficulty = """{"guitar":2,"bass":3}""") =>
        JsonSerializer.Deserialize<Song>($$"""{"songId":"{{id}}","title":"{{title}}","artist":"{{artist}}","year":{{(year?.ToString() ?? "null")}},"difficulty":{{difficulty}}}""")!;

    private static readonly Dictionary<string, ShopSong> Offers = new()
    {
        ["a"] = new ShopSong { SongId = "a", LeavingTomorrow = true },
        ["b"] = new ShopSong { SongId = "b" },
    };

    [Fact]
    public void ShopFilter_KeepsMembersAndLeaving()
    {
        IReadOnlyList<Song> songs = [S("a"), S("b"), S("c")];
        Assert.Same(songs, SongShopFilter.None.Filter(songs, null));
        Assert.Equal(["a", "b"], new SongShopFilter(InShop: true).Filter(songs, Offers).Select(s => s.SongId));
        Assert.Equal(["a"], new SongShopFilter(LeavingTomorrow: true).Filter(songs, Offers).Select(s => s.SongId));
        Assert.Equal(["a"], new SongShopFilter(true, true).Filter(songs, Offers).Select(s => s.SongId));
        Assert.Empty(new SongShopFilter(InShop: true).Filter(songs, new Dictionary<string, ShopSong>()));
        Assert.Throws<InvalidOperationException>(() => new SongShopFilter(InShop: true).Filter(songs, null));
    }

    [Fact]
    public void PlayerFilter_AndWithinChartOrAcrossCharts()
    {
        IReadOnlyList<Song> songs = [S("a"), S("b"), S("c"), S("d", difficulty: """{"bass":1}""")];
        var facts = new Dictionary<(string, Instrument), ChartScoreFacts>
        {
            [("a", Instrument.Lead)] = new(100, true),
            [("b", Instrument.Lead)] = new(100, false),
            [("c", Instrument.Bass)] = new(0, true),
        };
        ChartScoreFacts? Lookup(string id, Instrument i) => facts.TryGetValue((id, i), out var f) ? f : null;
        var all = InstrumentInfo.All;

        var hasLead = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Lead, true);
        Assert.Equal(["a", "b"], hasLead.Filter(songs, Lookup, all, null).Select(s => s.SongId));
        var hasNoFcLead = hasLead.With(SongScoreFilterKind.MissingFCs, Instrument.Lead, true);
        Assert.Equal(["b"], hasNoFcLead.Filter(songs, Lookup, all, null).Select(s => s.SongId));
        var missingLead = SongPlayerScoreFilter.None.With(SongScoreFilterKind.MissingScores, Instrument.Lead, true);
        Assert.Equal(["c"], missingLead.Filter(songs, Lookup, all, null).Select(s => s.SongId)); // d has no Lead chart
        var orAcross = hasLead.With(SongScoreFilterKind.HasFCs, Instrument.Bass, true);
        Assert.Equal(["a", "b", "c"], orAcross.Filter(songs, Lookup, all, null).Select(s => s.SongId));
        Assert.Equal(["c"], orAcross.Filter(songs, Lookup, all, Instrument.Bass).Select(s => s.SongId));
        Assert.Same(songs, orAcross.Filter(songs, Lookup, all, Instrument.Drums));
        Assert.Same(songs, orAcross.Filter(songs, Lookup, [Instrument.Drums], null));
    }

    [Fact]
    public void PlayerFilter_GlobalSwitchesScopeAndValidity()
    {
        IReadOnlyCollection<Instrument> visible = [Instrument.Lead, Instrument.Bass];
        var filter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasFCs, Instrument.Drums, true);
        Assert.True(filter.IsActive);
        Assert.False(filter.ScopedTo(visible).IsActive);
        filter = filter.WithAll(SongScoreFilterKind.MissingScores, visible, true);
        Assert.True(filter.AllVisible(SongScoreFilterKind.MissingScores, visible));
        Assert.False(filter.AllVisible(SongScoreFilterKind.MissingScores, []));
        Assert.Equal([Instrument.Lead, Instrument.Bass], filter.MissingScores);
        Assert.True(filter.Contains(SongScoreFilterKind.HasFCs, Instrument.Drums));
        filter = filter.WithAll(SongScoreFilterKind.MissingScores, visible, false).With(SongScoreFilterKind.HasFCs, Instrument.Drums, false);
        Assert.False(filter.IsActive);
        Assert.Equal(SongPlayerScoreFilter.None, filter);
        Assert.Equal(SongPlayerScoreFilter.None.GetHashCode(), filter.GetHashCode());
        Assert.True(filter.IsValid);
        Assert.False(new SongPlayerScoreFilter { HasScores = [Instrument.Lead, Instrument.Lead] }.IsValid);
        Assert.False(new SongPlayerScoreFilter { HasFCs = [(Instrument)42] }.IsValid);
        Assert.False(new SongPlayerScoreFilter { MissingFCs = null! }.IsValid);
        Assert.Equal(["Missing Scores", "Has Scores", "Missing FCs", "Has FCs"], SongScoreFilterKindInfo.All.Select(k => k.Label()));
        Assert.False(SongPlayerScoreFilter.None.Equals(null));
    }

    [Fact]
    public void Settings_MinimalFileKeepsDefaults()
    {
        var json = """{"version":1,"hideShop":true,"songFilter":{"Instrument":"Lead","MinDifficulty":1,"MaxDifficulty":7}}"""u8.ToArray();
        var loaded = JsonSerializer.Deserialize(json, FestivalJsonContext.Default.AppSettings)!.Sanitized();
        Assert.Equal((true, true, true, SongSortMode.Title), (loaded.SongSortAscending, loaded.ShowInstrumentIcons, loaded.MetadataScore, loaded.SongSort));
        Assert.True(loaded.HideShop);
        Assert.Equal(Instrument.Lead, loaded.SongFilter.Instrument);
        Assert.Equal(SongShopFilter.None, loaded.ShopFilter);
        var partialFilter = JsonSerializer.Deserialize("""{"songPlayerScoreFilter":{"hasScores":["Lead"]}}"""u8.ToArray(),
            FestivalJsonContext.Default.AppSettings)!.Sanitized();
        Assert.True(partialFilter.PlayerScoreFilter.IsValid);
        Assert.Equal([Instrument.Lead], partialFilter.PlayerScoreFilter.HasScores);
    }

    [Fact]
    public void Settings_RoundTripSongsOwnedFieldsAndResetKeepsThem()
    {
        var settings = new AppSettings
        {
            ShopFilter = new SongShopFilter(true, false),
            PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Bass, true),
            ShopViewMode = ShopViewMode.List,
            SongSort = SongSortMode.Shop,
        };
        var store = new InMemorySettingsStore(settings);
        var json = JsonSerializer.Serialize(settings, FestivalJsonContext.Default.AppSettings);
        var back = JsonSerializer.Deserialize(json, FestivalJsonContext.Default.AppSettings)!.Sanitized();
        Assert.Equal(settings.Sanitized(), back);
        Assert.Contains("\"songShopFilter\"", json);
        Assert.Contains("Solo_Bass", json.Replace("\"Bass\"", "Solo_Bass"));
        var reset = back.ResetAppSettings();
        Assert.Equal((back.ShopFilter, back.PlayerScoreFilter, back.ShopViewMode), (reset.ShopFilter, reset.PlayerScoreFilter, reset.ShopViewMode));
        Assert.NotEqual(back, back with { ShopViewMode = ShopViewMode.Grid });
        var nulls = (back with { ShopFilter = null!, PlayerScoreFilter = null!, ShopViewMode = (ShopViewMode)9 }).Sanitized();
        Assert.Equal((SongShopFilter.None, SongPlayerScoreFilter.None, ShopViewMode.Grid), (nulls.ShopFilter, nulls.PlayerScoreFilter, nulls.ShopViewMode));
        Assert.NotNull(store);
    }
}

public class SongListPipelineTests
{
    private static Song S(string id, string title, string artist = "A", int? year = 2020) =>
        new() { SongId = id, Title = title, Artist = artist, Year = year, Difficulty = new SongDifficulty { Guitar = 2 } };

    private static readonly IReadOnlyList<Song> Songs = [S("a", "Alpha"), S("b", "Beta"), S("c", "Charlie"), S("d", "Delta")];

    private static readonly Dictionary<string, ShopSong> Offers = new()
    {
        ["c"] = new ShopSong { SongId = "c", LeavingTomorrow = true },
        ["b"] = new ShopSong { SongId = "b" },
    };

    [Fact]
    public void ShopSort_MembersFirstWithBucketsAndDirection()
    {
        var result = SongListPipeline.Run(new SongListInputs { Songs = Songs, Sort = SongSortMode.Shop, Offers = Offers });
        Assert.Equal(SongSortMode.Shop, result.EffectiveSort);
        Assert.Equal(["In Shop", "Leaving Tomorrow", "Not In Shop"], result.Sections.Select(s => s.Label).Order());
        Assert.Equal(["b", "c", "a", "d"], result.Sections.SelectMany(s => s.Songs).Select(s => s.SongId));
        Assert.Null(result.SortPaused);
        var descending = SongListPipeline.Run(new SongListInputs { Songs = Songs, Sort = SongSortMode.Shop, Ascending = false, Offers = Offers });
        Assert.Equal(["d", "a", "c", "b"], descending.Sections.SelectMany(s => s.Songs).Select(s => s.SongId));
        var single = SongListPipeline.Run(new SongListInputs { Songs = Songs, Sort = SongSortMode.Shop, Offers = new Dictionary<string, ShopSong>() });
        Assert.Equal([""], single.Sections.Select(s => s.Label));
    }

    [Fact]
    public void ShopTies_FallBackThroughArtistYearAndId()
    {
        IReadOnlyList<Song> twins = [S("z", "Same", "B", 2001), S("y", "Same", "A", 2002), S("x", "Same", "A", 2001), S("w", "Same", "A", 2001)];
        var ids = SongListPipeline.Run(new SongListInputs { Songs = twins, Sort = SongSortMode.Shop, Offers = Offers }).Sections.SelectMany(s => s.Songs).Select(s => s.SongId);
        Assert.Equal(["w", "x", "y", "z"], ids);
    }

    [Theory]
    [InlineData(true, false, false, "hidden")]
    [InlineData(false, true, true, "update together")]
    [InlineData(false, false, false, "loads")]
    public void ShopChoices_PauseInsteadOfGuessing(bool hide, bool mismatch, bool hasOffers, string reason)
    {
        var result = SongListPipeline.Run(new SongListInputs
        {
            Songs = Songs, Sort = SongSortMode.Shop, ShopFilter = new SongShopFilter(InShop: true), HideShop = hide,
            ShopPublicationMismatch = mismatch, Offers = hasOffers && !mismatch ? Offers : null,
        });
        Assert.Equal(SongSortMode.Title, result.EffectiveSort);
        Assert.Contains(reason, result.SortPaused);
        Assert.Contains("filters paused", result.ShopFilterPaused);
        Assert.Equal(4, result.Count);
        Assert.False(result.FiltersApplied);
    }

    [Fact]
    public void ShopFilter_AppliesWithMatchingFeed()
    {
        var result = SongListPipeline.Run(new SongListInputs { Songs = Songs, ShopFilter = new SongShopFilter(LeavingTomorrow: true), Offers = Offers });
        Assert.Equal(["c"], result.Sections.SelectMany(s => s.Songs).Select(s => s.SongId));
        Assert.True(result.FiltersApplied);
    }

    [Fact]
    public void ScoreFilters_PauseForEachUnavailableReason()
    {
        var filter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Lead, true);
        ChartScoreFacts? Facts(string id, Instrument i) => id == "a" ? new ChartScoreFacts(10, null) : null;
        SongListResult Run(bool player = true, bool invalid = false, bool scores = true, IReadOnlyCollection<Instrument>? visible = null) =>
            SongListPipeline.Run(new SongListInputs
            {
                Songs = Songs, PlayerFilter = filter, HasPlayer = player, FilterInvalidScores = invalid,
                Scores = scores ? Facts : null, Visible = visible ?? InstrumentInfo.All,
            });
        Assert.Equal(1, Run().Count);
        Assert.Null(Run().ScoreFilterPaused);
        Assert.Contains("hidden in Settings", Run(visible: [Instrument.Bass]).ScoreFilterPaused);
        Assert.Contains("until a player", Run(player: false).ScoreFilterPaused);
        Assert.Contains("Filter Invalid Scores", Run(invalid: true).ScoreFilterPaused);
        Assert.Contains("same update", Run(scores: false).ScoreFilterPaused);
        Assert.Equal(4, Run(scores: false).Count);
    }
}

public class SongRowProjectionTests
{
    private static readonly Song Song = new()
    {
        SongId = "s", Title = "T", Artist = "A",
        Difficulty = new SongDifficulty { Guitar = 3, Bass = 1, Drums = 99 },
    };

    [Fact]
    public void Chips_StatusRulesAndVisibility()
    {
        Assert.True(SongInstrumentStatusPolicy.ShowsChips(true, true, true, null, false));
        Assert.False(SongInstrumentStatusPolicy.ShowsChips(true, true, true, Instrument.Lead, false));
        Assert.False(SongInstrumentStatusPolicy.ShowsChips(true, true, false, null, false));
        Assert.False(SongInstrumentStatusPolicy.ShowsChips(true, false, true, null, false));
        Assert.False(SongInstrumentStatusPolicy.ShowsChips(true, true, true, null, true));
        Assert.False(SongInstrumentStatusPolicy.ShowsChips(false, true, true, null, false));

        var facts = new Dictionary<Instrument, ChartScoreFacts> { [Instrument.Lead] = new(10, true), [Instrument.Bass] = new(0, true), [Instrument.Drums] = new(5, false) };
        var badges = SongInstrumentStatusPolicy.Badges(Song, [Instrument.Drums, Instrument.Lead, Instrument.Bass, Instrument.Vocals],
            i => facts.TryGetValue(i, out var f) ? f : null);
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals], badges.Select(b => b.Instrument));
        Assert.Equal([SongInstrumentStatus.FullCombo, SongInstrumentStatus.InconsistentFullCombo, SongInstrumentStatus.Unavailable, SongInstrumentStatus.Unavailable],
            badges.Select(b => b.Status));
        Assert.Equal(SongInstrumentStatus.Scored, SongInstrumentStatusPolicy.Status(Song, Instrument.Lead, new ChartScoreFacts(1, null)));
        Assert.Equal(SongInstrumentStatus.NoScore, SongInstrumentStatusPolicy.Status(Song, Instrument.Lead, null));
        Assert.Equal(SongInstrumentStatus.NoScore, SongInstrumentStatusPolicy.Status(Song, Instrument.Lead, new ChartScoreFacts(0, false)));
        Assert.Equal("Lead, full combo", badges[0].Announcement);
        Assert.Equal(["full combo", "score missing despite a reported full combo", "not charted"],
            badges.Take(3).Select(b => b.StatusText));
        Assert.Equal("scored", new SongInstrumentBadge(Instrument.Lead, SongInstrumentStatus.Scored).StatusText);
        Assert.Equal("no score", new SongInstrumentBadge(Instrument.Lead, SongInstrumentStatus.NoScore).StatusText);
    }

    [Fact]
    public void Metadata_DefaultOrderAndFields()
    {
        var detail = new SongScoreDetail(123456, 985000, false, 6, 9, 3, 4, 200, "2026-09-01T10:00:00Z");
        var fields = SongMetadataPolicy.Fields(detail, Instrument.Lead, Song, 9, new AppSettings());
        Assert.Equal([MetadataField.Score, MetadataField.Percentage, MetadataField.Percentile, MetadataField.Stars, MetadataField.Season,
            MetadataField.Intensity, MetadataField.Difficulty, MetadataField.LastPlayed], fields.Select(f => f.Kind));
        Assert.Equal("Score 123,456", fields[0].Announcement);
        Assert.Equal(("98.5%", "Accuracy 98.5%"), (fields[1].Text, fields[1].Announcement));
        Assert.NotNull(fields[1].Tint);
        Assert.Equal(("Top 2%", SongPercentileTier.TopFive), (fields[2].Text, fields[2].Percentile));
        Assert.Equal(("★★★★★", "5 gold stars", true), (fields[3].Text, fields[3].Announcement, fields[3].Stars.Gold));
        Assert.Equal(("S9", "Current season 9", true), (fields[4].Text, fields[4].Announcement, fields[4].CurrentSeason));
        Assert.Equal(3, fields[5].IntensityRaw);
        Assert.Equal(("X", "Expert difficulty", 3), (fields[6].Text, fields[6].Announcement, fields[6].GameDifficulty));
        Assert.StartsWith("Last played ", fields[7].Text);
        Assert.Empty(SongMetadataPolicy.Fields(detail with { Score = 0 }, Instrument.Lead, Song, 9, new AppSettings()));
    }

    [Fact]
    public void Metadata_VisibilityOrderAndFullComboRules()
    {
        var detail = new SongScoreDetail(500, 1000000, true, 3, 8, 1, 1, 100, "garbage");
        var settings = new AppSettings
        {
            MetadataPercentage = false, MetadataScore = false, EnableVisualOrder = true,
            SongRowVisualOrder = [MetadataField.LastPlayed, MetadataField.Stars, MetadataField.Season, MetadataField.Percentile],
        };
        var fields = SongMetadataPolicy.Fields(detail, Instrument.Lead, Song, 9, settings);
        Assert.Equal([MetadataField.Stars, MetadataField.Season, MetadataField.Percentile, MetadataField.Percentage, MetadataField.Intensity,
            MetadataField.Difficulty, MetadataField.LastPlayed], fields.Select(f => f.Kind));
        var fc = fields.Single(f => f.Kind == MetadataField.Percentage);
        Assert.Equal(("FC", "Full combo", true), (fc.Text, fc.Announcement, fc.FullCombo));
        Assert.Equal(("M", "Medium difficulty"), (fields[5].Text, fields[5].Announcement));
        Assert.Equal("3 stars", fields[0].Announcement);
        Assert.Equal("Season 8", fields[1].Announcement);
        Assert.Equal(SongPercentileTier.TopOne, fields[2].Percentile);
        Assert.Equal("Last played date unavailable", fields[^1].Text);

        var shown = SongMetadataPolicy.Fields(detail, Instrument.Lead, Song, 8, new AppSettings());
        Assert.Equal(("100% FC", "Full combo, accuracy 100%"), (shown[1].Text, shown[1].Announcement));
        var noAccuracy = SongMetadataPolicy.Fields(detail with { Accuracy = null }, Instrument.Lead, Song, 8, new AppSettings());
        Assert.Equal("Full combo, accuracy unavailable", noAccuracy[1].Announcement);
        var sparse = SongMetadataPolicy.Fields(new SongScoreDetail(5, Stars: 1, Difficulty: 1.5, Rank: 5, TotalEntries: 100), Instrument.Drums, Song, null, new AppSettings());
        Assert.Equal([MetadataField.Score, MetadataField.Percentile, MetadataField.Stars], sparse.Select(f => f.Kind));
        Assert.Equal(("1 star", SongPercentileTier.TopFive), (sparse[2].Announcement, sparse[1].Percentile));
        var none = new AppSettings { MetadataScore = false, MetadataPercentage = false, MetadataPercentile = false, MetadataSeason = false,
            MetadataIntensity = false, MetadataDifficulty = false, MetadataStars = false, MetadataLastPlayed = false };
        Assert.Empty(SongMetadataPolicy.Fields(detail with { IsFullCombo = false }, Instrument.Lead, Song, 8, none));
    }

    [Fact]
    public void PercentileBuckets()
    {
        Assert.Equal("Top 1%", SongMetadataPolicy.PercentileBucket(1, 1000));
        Assert.Equal("Top 5%", SongMetadataPolicy.PercentileBucket(45, 1000));
        Assert.Equal("Top 10%", SongMetadataPolicy.PercentileBucket(51, 1000));
        Assert.Equal("Top 100%", SongMetadataPolicy.PercentileBucket(1000, 1000));
        Assert.Null(SongMetadataPolicy.PercentileBucket(0, 10));
        Assert.Null(SongMetadataPolicy.PercentileBucket(1, null));
        Assert.Equal(new ChartScoreFacts(5, true), new SongScoreDetail(5, IsFullCombo: true).Facts);
    }

    [Fact]
    public void RowItem_AnnouncesEverything()
    {
        var chipsRow = new SongRowItem(Song)
        {
            Highlight = ShopHighlight.New,
            Chips = [new SongInstrumentBadge(Instrument.Lead, SongInstrumentStatus.Scored)],
        };
        Assert.Equal("T, A, Item Shop: New, Lead, scored", chipsRow.Announcement);
        var metaRow = new SongRowItem(Song) { Chart = Instrument.Bass, Metadata = [new SongMetadataField(MetadataField.Score, "5", "Score 5")] };
        Assert.True(metaRow.NamesChart);
        Assert.Equal("T, A, Bass chart, Score 5", metaRow.Announcement);
        var meterRow = new SongRowItem(Song) { Chart = Instrument.Lead, ChartRaw = 3, ScoreState = "No score" };
        Assert.Equal("T, A, Lead, " + DifficultyScale.Announcement(3) + ", No score", meterRow.Announcement);
        Assert.False(meterRow.Keyboard);
    }
}

public class SongsViewModelPlayerTests
{
    private static async Task<(FakeService Service, FestivalSession Session, SongsViewModel Vm)> Loaded(AppSettings? settings = null, bool player = true,
        Dictionary<string, (HttpStatusCode, string)>? profiles = null)
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: profiles);
        var initial = settings ?? new AppSettings();
        if (player) initial = initial with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") };
        var session = service.Session(settings: initial);
        var vm = new SongsViewModel(session);
        await vm.AppearCommand.ExecuteAsync(null);
        return (service, session, vm);
    }

    private static SongRowItem Row(SongsViewModel vm, string id) => vm.Sections.SelectMany(s => s.Rows).Single(r => r.Song.SongId == id);

    [Fact]
    public async Task SelectedPlayer_ShowsChipsAndShopAccents()
    {
        var (_, session, vm) = await Loaded();
        Assert.Equal(SelectedProfileStatus.Available, session.SelectedProfileStatus);
        var s1 = Row(vm, "s1");
        Assert.Equal(SongInstrumentStatus.FullCombo, s1.Chips.Single(c => c.Instrument == Instrument.Lead).Status);
        Assert.Equal(SongInstrumentStatus.Scored, s1.Chips.Single(c => c.Instrument == Instrument.Bass).Status);
        Assert.Equal(SongInstrumentStatus.Unavailable, s1.Chips.Single(c => c.Instrument == Instrument.Drums).Status);
        Assert.Equal(ShopHighlight.New, Row(vm, "s2").Highlight);
        Assert.Equal(ShopHighlight.LeavingTomorrow, Row(vm, "s3").Highlight);
        Assert.Null(s1.Highlight);
        Assert.Empty(vm.Notices);
    }

    [Fact]
    public async Task IconsOff_ShowsMetadataForFirstVisibleChart()
    {
        var (_, session, vm) = await Loaded(new AppSettings { ShowInstrumentIcons = false });
        var s1 = Row(vm, "s1");
        Assert.Empty(s1.Chips);
        Assert.Equal(Instrument.Lead, s1.Chart);
        Assert.Equal(MetadataField.Score, s1.Metadata[0].Kind);
        Assert.Null(s1.ScoreState);
        Assert.Equal("No score", Row(vm, "s3").ScoreState);
        session.UpdateSettings(s => s with { SongFilter = new SongFilter(Instrument.Bass) });
        var bass = Row(vm, "s1");
        Assert.Equal(Instrument.Bass, bass.Chart);
        Assert.True(bass.NamesChart);
        session.UpdateSettings(s => s with { SongFilter = SongFilter.None, VisibleInstruments = [Instrument.Drums] });
        Assert.Equal("No Drums chart", Row(vm, "s3").ScoreState);
        session.UpdateSettings(s => s with { FilterInvalidScores = true, VisibleInstruments = InstrumentInfo.All });
        Assert.Equal("Scores paused while Filter Invalid Scores is on", Row(vm, "s1").ScoreState);
    }

    [Fact]
    public async Task ScoreFilters_ApplyAndClearOnDeselect()
    {
        var (_, session, vm) = await Loaded();
        vm.FilterDraft.Begin();
        Assert.True(vm.FilterDraft.ShowScoreFilters);
        Assert.Equal(9, vm.FilterDraft.ScoreRows.Count);
        var lead = vm.FilterDraft.ScoreRows[0];
        lead.HasFCs = true;
        Assert.True(lead.HasFCs);
        Assert.Equal("Lead: Has FCs", lead.HasFCsName);
        Assert.Equal(("Lead: Missing Scores", "Lead: Has Scores", "Lead: Missing FCs"), (lead.MissingScoresName, lead.HasScoresName, lead.MissingFCsName));
        Assert.False(lead.MissingScores || lead.HasScores || lead.MissingFCs);
        Assert.Equal("instrument_guitar.png", lead.IconFile);
        Assert.False(vm.FilterDraft.CanApply); // applied live
        Assert.Equal(["s1"], vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId));
        Assert.True(vm.IsFilterActive);
        session.DeselectPlayer();
        Assert.False(session.Settings.PlayerScoreFilter.IsActive);
        Assert.Equal(3, vm.ResultCount);
    }

    [Fact]
    public async Task GlobalSwitches_AndHiddenChecksDisclosure()
    {
        var (_, session, vm) = await Loaded();
        vm.FilterDraft.Begin();
        vm.FilterDraft.AllMissingScores = true;
        Assert.True(vm.FilterDraft.AllMissingScores);
        Assert.True(vm.FilterDraft.ScoreRows.All(r => r.MissingScores));
        vm.FilterDraft.AllMissingScores = true;
        vm.FilterDraft.AllMissingScores = false;
        vm.FilterDraft.AllHasScores = true;
        vm.FilterDraft.AllMissingFCs = true;
        vm.FilterDraft.AllHasFCs = true;
        Assert.True(vm.FilterDraft.AllHasScores && vm.FilterDraft.AllMissingFCs && vm.FilterDraft.AllHasFCs);
        vm.FilterDraft.ResetCommand.Execute(null);
        Assert.False(vm.FilterDraft.CanApply);
        session.UpdateSettings(s => s with { PlayerScoreFilter = SongPlayerScoreFilter.None.With(SongScoreFilterKind.HasScores, Instrument.Drums, true) });
        session.UpdateSettings(s => s.WithInstrumentVisible(Instrument.Drums, false));
        vm.FilterDraft.Begin();
        Assert.True(vm.FilterDraft.HasHiddenScoreChecks);
        Assert.Contains(vm.Notices, n => n.Contains("hidden in Settings"));
        vm.FilterDraft.InShop = true;
        vm.ApplyFilterCommand.Execute(null);
        Assert.False(session.Settings.PlayerScoreFilter.IsActive);
        Assert.True(session.Settings.ShopFilter.InShop);
        Assert.Equal(["s2", "s3"], vm.Sections.SelectMany(s => s.Rows).Select(r => r.Song.SongId));
        vm.ClearFilterCommand.Execute(null);
        Assert.False(vm.IsFilterActive);
    }

    [Fact]
    public async Task SyncingAndFailedProfiles_AreExplicitStates()
    {
        var (_, _, syncing) = await Loaded(profiles: new() { [PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing()) });
        Assert.Equal("Scores syncing", Row(syncing, "s1").ScoreState);
        Assert.Contains(syncing.Notices, n => n.Contains("still syncing"));
        Assert.Empty(Row(syncing, "s1").Chips);

        var (_, _, failed) = await Loaded(profiles: new() { [PlayerWire.Id] = (HttpStatusCode.InternalServerError, "{}") });
        Assert.Equal("Scores unavailable", Row(failed, "s1").ScoreState);
        Assert.Contains(failed.Notices, n => n.StartsWith("Player scores unavailable", StringComparison.Ordinal));
    }

    [Fact]
    public async Task PublicationMismatch_PausesScoresAndShop()
    {
        var (service, session, vm) = await Loaded();
        service.Override = service.Override is { } inner
            ? r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.ServiceUnavailable) : inner(r)
            : null;
        service.PublicationId = 8;
        await session.Api.GetPublicationAsync(force: true);
        await Async.Until(() => vm.Notices.Any(n => n.Contains("same update")));
        Assert.Contains("Player scores paused until songs update", Row(vm, "s1").ScoreState);
        Assert.Null(Row(vm, "s2").Highlight);
    }

    [Fact]
    public async Task InvalidSavedFilter_BlocksUntilReset()
    {
        var (_, session, vm) = await Loaded(new AppSettings { PlayerScoreFilter = new SongPlayerScoreFilter { HasScores = [Instrument.Lead, Instrument.Lead] } });
        Assert.True(vm.ShowInvalidFilter);
        Assert.False(vm.ShowError);
        Assert.Empty(vm.Sections);
        vm.ClearFilterCommand.Execute(null);
        Assert.False(vm.ShowInvalidFilter);
        Assert.True(vm.ShowList);
        Assert.True(session.Settings.PlayerScoreFilter.IsValid);
    }

    [Fact]
    public async Task SortDraft_HidesShopWhenHidden_AndShopSortGroups()
    {
        var (_, session, vm) = await Loaded(player: false);
        vm.SortDraft.Begin();
        Assert.Contains("Item Shop", vm.SortDraft.ModeLabels);
        vm.SortDraft.ModeIndex = vm.SortDraft.Modes.IndexOf(SongSortMode.Shop);
        vm.ApplySortCommand.Execute(null);
        Assert.Equal(["In Shop", "Leaving Tomorrow", "Not In Shop"], vm.Sections.Select(s => s.Label)); // first-seen buckets
        Assert.True(vm.HasJumpIndex);
        Assert.Equal("Item Shop ↑", vm.SortSummary);
        session.UpdateSettings(s => s with { HideShop = true });
        Assert.Contains(vm.Notices, n => n.Contains("sort paused"));
        vm.SortDraft.Begin();
        Assert.DoesNotContain("Item Shop", vm.SortDraft.ModeLabels);
        Assert.Equal(-1, vm.SortDraft.ModeIndex);
        Assert.Null(Row(vm, "s2").Highlight);
        vm.FilterDraft.Begin();
        Assert.False(vm.FilterDraft.ShopEnabled);
        Assert.False(vm.FilterDraft.ShowScoreFilters);
    }

    [Fact]
    public async Task ChartFilter_WithoutPlayerShowsMeter()
    {
        var (_, _, vm) = await Loaded(new AppSettings { SongFilter = new SongFilter(Instrument.Lead) }, player: false);
        var row = Row(vm, "s1");
        Assert.Equal((Instrument.Lead, 2d), (row.Chart!.Value, row.ChartRaw!.Value));
        Assert.Empty(row.Chips);
    }
}
