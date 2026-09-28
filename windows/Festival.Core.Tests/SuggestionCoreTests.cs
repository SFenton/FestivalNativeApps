using System.Text;

namespace Festival.Core.Tests;

/// <summary>Generator edge cases, filter settings, row presentation, rival index and filter persistence.</summary>
public sealed class SuggestionCoreTests
{
    #region Fixture builders
    private static Song MakeSong(string id, string? title = null, string? artist = null, int? year = null,
        IReadOnlyDictionary<string, int>? max = null, SongDifficulty? difficulty = null, string? sig = null) => new()
    {
        SongId = id, Title = title ?? $"Song {id}", Artist = artist ?? $"Artist {id}", Year = year, MaxScores = max, Sig = sig,
        Difficulty = difficulty ?? new SongDifficulty
        {
            Guitar = 1, Bass = 1, Drums = 1, Vocals = 1, ProGuitar = 1, ProBass = 1, ProVocals = 1, ProCymbals = 1, ProDrums = 1,
        },
    };

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> Index(
        params (string Song, Instrument Instrument, SuggestionScore Score)[] rows) =>
        rows.GroupBy(r => r.Song).ToDictionary(g => g.Key,
            g => (IReadOnlyDictionary<Instrument, SuggestionScore>)g.ToDictionary(r => r.Instrument, r => r.Score));

    private static SuggestionGenerator Generator(IReadOnlyList<Song> songs,
        IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>> scores, int? display = 3, int season = 10, ISuggestionRng? rng = null)
    {
        var generator = new SuggestionGenerator(rng, new SuggestionGenerator.Options(7, DisableSkipping: true, FixedDisplayCount: display, CurrentSeason: season));
        generator.SetSource(songs, scores);
        return generator;
    }

    private static readonly SongDifficulty LeadOnly = new() { Guitar = 1 };

    /// <summary>
    /// Songs whose only chart is a gold, full-combo, unranked, current-season Lead run: no family matches them
    /// except the catalogue-wide ones (variety), so they absorb those without starving the family under test.
    /// </summary>
    private static (List<Song> Songs, List<(string, Instrument, SuggestionScore)> Rows) Filler(int count = 40)
    {
        var songs = Enumerable.Range(0, count).Select(i => MakeSong($"f{i}", difficulty: LeadOnly)).ToList();
        return (songs, songs.Select(s => (s.SongId, Instrument.Lead, new SuggestionScore(1, 6, 1_000_000, true, 10))).ToList());
    }

    private static List<SuggestionCategory> Drain(SuggestionGenerator generator)
    {
        var all = new List<SuggestionCategory>();
        while (generator.GetNext(50) is { Count: > 0 } page) all.AddRange(page);
        return all;
    }

    /// <summary>A scripted RNG returning a fixed double.</summary>
    private sealed class FixedRng(double value) : ISuggestionRng
    {
        public double NextDouble() => value;
        public int NextInt(int maxExclusive) => maxExclusive > 0 ? (int)(value * maxExclusive) : 0;
    }
    #endregion

    #region RNG and generator
    [Fact]
    public void SeededRngIsDeterministicAndBounded()
    {
        var a = new SeededSuggestionRng(42);
        var b = new SeededSuggestionRng(42);
        Assert.Equal(Enumerable.Range(0, 5).Select(_ => a.NextDouble()), Enumerable.Range(0, 5).Select(_ => b.NextDouble()));
        var r = new SeededSuggestionRng(9);
        Assert.All(Enumerable.Range(0, 200).Select(_ => r.NextInt(7)), v => Assert.InRange(v, 0, 6));
        Assert.Equal(0, r.NextInt(0));
    }

    [Fact]
    public void EmptySourceProducesNothing()
    {
        var generator = new SuggestionGenerator();
        Assert.True(generator.HasPendingPipelines);
        Assert.Empty(generator.GetNext(10));
        Assert.False(generator.HasPendingPipelines);
    }

    [Fact]
    public void NoRepeatedKeysWithinAMixAndResetAllowsRepeats()
    {
        var songs = Enumerable.Range(0, 30).Select(i => MakeSong($"s{i}", year: 1980 + i % 30)).ToList();
        var scores = Index(songs.Select(s => (s.SongId, Instrument.Lead, new SuggestionScore(1000, 6, 960_000, false, 3, 5, 100))).ToArray());
        var generator = Generator(songs, scores);
        var first = Drain(generator);
        Assert.Equal(first.Count, first.Select(c => c.Key).Distinct().Count());
        Assert.Empty(generator.GetNext(5));
        generator.ResetForEndless();
        Assert.NotEmpty(generator.GetNext(5));
    }

    [Fact]
    public void SkippingTableForceEmitsAfterTwoSkips()
    {
        // 0.999 never beats any probability < 1; the skip streak forces the third evaluation of a key to emit.
        var songs = Enumerable.Range(0, 4).Select(i => MakeSong($"s{i}")).ToList();
        var generator = new SuggestionGenerator(new FixedRng(0.999), new SuggestionGenerator.Options(1, FixedDisplayCount: 2));
        generator.SetSource(songs, Index());
        Assert.DoesNotContain(generator.GetNext(100), c => c.Key == "unplayed_any");
        generator.ResetForEndless();
        Assert.DoesNotContain(generator.GetNext(100), c => c.Key == "unplayed_any");
        generator.ResetForEndless();
        Assert.Single(generator.GetNext(100), c => c.Key == "unplayed_any");
    }

    [Fact]
    public void RandomDisplayCountStaysBetweenTwoAndFive()
    {
        var songs = Enumerable.Range(0, 40).Select(i => MakeSong($"s{i}")).ToList();
        var generator = new SuggestionGenerator(new SuggestionGenerator.Options(3, DisableSkipping: true));
        generator.SetSource(songs, Index());
        var categories = Drain(generator);
        Assert.NotEmpty(categories);
        Assert.All(categories.Where(c => c.Key.StartsWith("unplayed_", StringComparison.Ordinal)), c => Assert.InRange(c.Songs.Count, 2, 5));
    }

    [Fact]
    public void DecadeVariantsRetitleAndFilterByDecade()
    {
        var songs = Enumerable.Range(0, 12).Select(i => MakeSong($"s{i}", year: i < 6 ? 1985 : 1999)).ToList();
        var generator = Generator(songs, Index());
        var categories = Drain(generator);
        var decade = categories.Where(c => c.Key.StartsWith("unplayed_any_decade_", StringComparison.Ordinal)).ToList();
        Assert.NotEmpty(decade);
        Assert.All(decade, c => Assert.Matches(@"^First Plays \((80|90)'s\)$", c.Title));
        Assert.All(decade, c => Assert.Single(c.Songs.Select(s => s.Song.Year!.Value / 10).Distinct()));
        Assert.Contains(categories, c => c.Key.StartsWith("unplayed_Solo_", StringComparison.Ordinal) && c.Key.Contains("_decade_", StringComparison.Ordinal) &&
            c.Title.StartsWith("First ", StringComparison.Ordinal) && c.Description.StartsWith("Unplayed ", StringComparison.Ordinal));
    }

    [Fact]
    public void YearsOutsideDecadeRangeAreIgnoredAnd2000sUse00Label()
    {
        var songs = new[] { MakeSong("a", year: 1968), MakeSong("b", year: 2100), MakeSong("c", year: 2003), MakeSong("d", year: 2005) };
        var categories = Drain(Generator(songs, Index()));
        var decade = categories.Where(c => c.Key.Contains("_decade_", StringComparison.Ordinal)).ToList();
        Assert.NotEmpty(decade);
        Assert.All(decade, c => Assert.Contains("00's", c.Title, StringComparison.Ordinal));
        Assert.All(decade, c => Assert.EndsWith("_decade_00", c.Key, StringComparison.Ordinal));
    }

    [Fact]
    public void NearMaxTiersAreExclusive()
    {
        var max = new Dictionary<string, int> { ["Solo_Guitar"] = 100_000 };
        var (songs, rows) = Filler();
        (string Id, long Score)[] targets = [("a", 95_000), ("b", 99_000), ("c", 94_999), ("d", 84_000), ("e", 0)];
        foreach (var (id, score) in targets)
        {
            songs.Add(MakeSong(id, max: max, difficulty: LeadOnly));
            rows.Add((id, Instrument.Lead, new SuggestionScore(score, 6, 1_000_000, true, 10)));
        }
        var categories = Drain(Generator(songs, Index(rows.ToArray()), display: 5));
        Assert.Equal(["a", "b"], categories.Single(c => c.Key == "near_max_5k").Songs.Select(s => s.Song.SongId).Order());
        Assert.Equal(["c"], categories.Single(c => c.Key == "near_max_10k").Songs.Select(s => s.Song.SongId));
        Assert.DoesNotContain(categories, c => c.Key == "near_max_15k");
        Assert.Equal(Instrument.Lead, categories.Single(c => c.Key == "near_max_10k").Songs[0].Instrument);
    }

    [Fact]
    public void StaleFamiliesNeedASeason()
    {
        var bassOnly = new SongDifficulty { Bass = 1 };
        var songs = Enumerable.Range(0, 60).Select(i => MakeSong($"s{i}", difficulty: bassOnly)).ToList();
        var scores = Index(songs.Select(s => (s.SongId, Instrument.Bass, new SuggestionScore(10, 6, 1_000_000, true, 2))).ToArray());
        Assert.DoesNotContain(Drain(Generator(songs, scores, season: 0)), c => c.Type == SuggestionCategoryType.Stale);
        var categories = Drain(Generator(songs, scores, season: 10, display: 2));
        Assert.Contains(categories, c => c.Key == "stale_global_5plus" && c.Title == "Untouched for 5+ Seasons");
        Assert.Contains(categories, c => c.Key == "stale_global_1" && c.Title == "Play This Season");
        Assert.Contains(categories, c => c.Key == "stale_global_3" && c.Title == "Untouched for 3 Seasons");
        Assert.Contains(categories, c => c.Key == "stale_Solo_Bass_1" && c.Title == "Play Bass This Season");
        Assert.Contains(categories, c => c.Key == "stale_Solo_Bass_5plus" && c.Title == "Bass Untouched for 5+ Seasons");
        Assert.Contains(categories, c => c.Key == "stale_Solo_Bass_2" && c.Title == "Bass Untouched for 2 Seasons");
        Assert.All(categories.Single(c => c.Key == "stale_Solo_Bass_2").Songs, s => Assert.Equal(Instrument.Bass, s.Instrument));
    }

    [Fact]
    public void SeasonFallbackUsesHighestScoreSeason()
    {
        var scores = Index(("a", Instrument.Lead, new SuggestionScore(1, Season: 4)), ("b", Instrument.Bass, new SuggestionScore(1, Season: 9)),
            ("c", Instrument.Bass, new SuggestionScore(1)));
        Assert.Equal(9, SuggestionSeason.Effective(null, scores));
        Assert.Equal(9, SuggestionSeason.Effective(0, scores));
        Assert.Equal(12, SuggestionSeason.Effective(12, scores));
        Assert.Equal(0, SuggestionSeason.Effective(null, Index()));
    }

    [Fact]
    public void PercentileFamiliesUseBuckets()
    {
        var (songs, rows) = Filler();
        var leadBass = new SongDifficulty { Guitar = 1, Bass = 1 };
        int[] ranks = [2, 3, 4, 5, 9, 14, 19, 24, 29, 45];
        for (var i = 0; i < 80; i++)
        {
            var id = $"p{i}";
            songs.Add(MakeSong(id, difficulty: leadBass, year: 1980 + i % 20));
            var rank = ranks[i % ranks.Length];
            rows.Add((id, Instrument.Lead, new SuggestionScore(10, 6, 1_000_000, true, 10, rank, 100)));
            rows.Add((id, Instrument.Bass, new SuggestionScore(10, 6, 1_000_000, true, 10, i < 40 ? rank : 1, 100)));
        }
        var categories = Drain(Generator(songs, Index(rows.ToArray()), display: 1));
        var keys = string.Join(",", categories.Select(c => c.Key));
        string[] prefixes = ["same_pct_improve", "same_pct_", "pct_improve_", "pct_improve_Solo_", "almost_elite", "pct_push"];
        Assert.True(prefixes.All(prefix => categories.Any(c => c.Key.StartsWith(prefix, StringComparison.Ordinal))), keys);
        Assert.All(categories.Where(c => c.Key.StartsWith("same_pct_", StringComparison.Ordinal) && c.Key != "same_pct_improve"), c =>
        {
            Assert.StartsWith("Break Into ", c.Title, StringComparison.Ordinal);
            Assert.All(c.Songs, s => Assert.Equal("Top " + c.Key["same_pct_".Length..] + "%", s.PercentileDisplay));
        });
        Assert.Contains(categories.SelectMany(c => c.Songs), s => s.PercentileDisplay == "Top 3%");
    }

    [Fact]
    public void ImproveRankingsNeedsThreeBuckets()
    {
        var (songs, rows) = Filler();
        int[] ranks = [3, 9, 14, 24, 45];
        for (var i = 0; i < 40; i++)
        {
            songs.Add(MakeSong($"i{i}", difficulty: LeadOnly));
            rows.Add(($"i{i}", Instrument.Lead, new SuggestionScore(10, 6, 1_000_000, true, 10, ranks[i % ranks.Length], 100)));
        }
        var improve = Drain(Generator(songs, Index(rows.ToArray()), display: 5)).Single(c => c.Key == "improve_rankings_Solo_Guitar");
        Assert.Equal("Improve Lead Rankings", improve.Title);
        Assert.InRange(improve.Songs.Count, 3, 5);
        Assert.Equal(improve.Songs.Count, improve.Songs.Select(s => s.PercentileDisplay).Distinct().Count());
    }

    [Fact]
    public void NearFcStarsAndSameNameFamilies()
    {
        var (songs, rows) = Filler();
        var drumsVocals = new SongDifficulty { Drums = 1, Vocals = 1 };
        for (var i = 0; i < 60; i++)
        {
            songs.Add(MakeSong($"n{i}", title: i < 4 ? "  Twin " : null, year: 1990 + i % 20, difficulty: drumsVocals));
            rows.Add(($"n{i}", Instrument.Drums, new SuggestionScore(10, 6, 960_000, false, 10)));
            rows.Add(($"n{i}", Instrument.Vocals, new SuggestionScore(10, i % 2 == 0 ? 5 : 3, 930_000, false, 10)));
        }
        var categories = Drain(Generator(songs, Index(rows.ToArray()), display: 2));
        Assert.Contains(categories, c => c.Key == "near_fc_any" && c.Songs.All(s => s.Instrument == Instrument.Drums));
        Assert.Contains(categories, c => c.Key == "unfc_Solo_Drums" && c.Instrument == Instrument.Drums && c.Songs.All(s => s.Instrument is null));
        Assert.Contains(categories, c => c.Key == "samename_nearfc_Twin" && c.Title == "Close to FC: 'Twin' Variants");
        Assert.Contains(categories, c => c.Key == "samename_Twin" && c.Title == "Songs Named 'Twin'");
        Assert.Contains(categories, c => c.Key == "star_gains");
        Assert.Contains(categories, c => c.Key.StartsWith("unfc_Solo_Drums_decade_", StringComparison.Ordinal) && c.Title.StartsWith("Close Drums FCs (", StringComparison.Ordinal));
        Assert.Contains(categories, c => c.Key.StartsWith("near_fc_relaxed", StringComparison.Ordinal));
        Assert.Contains(categories, c => c.Key.StartsWith("almost_six_star", StringComparison.Ordinal) || c.Key.StartsWith("more_stars", StringComparison.Ordinal));
        var fc = categories.First(c => c.Key == "near_fc_any").Songs[0];
        Assert.Equal(96, fc.Percent);
        Assert.False(fc.FullCombo);
        Assert.Equal(6, fc.Stars);
    }

    [Fact]
    public void ArtistFamiliesSkipBlankAndFeaturedNames()
    {
        var songs = new List<Song>();
        foreach (var artist in new[] { "X", "Featured Artist", "Real Band" })
            for (var i = 0; i < 4; i++) songs.Add(MakeSong($"{artist}{i}", artist: artist));
        for (var i = 0; i < 8; i++) songs.Add(MakeSong($"solo{i}", artist: $"Solo {i}"));
        var categories = Drain(Generator(songs, Index()));
        var samplers = categories.Where(c => c.Type == SuggestionCategoryType.ArtistEssentials).ToList();
        Assert.All(samplers, c => Assert.Equal("artist_sampler_Real Band", c.Key));
        Assert.Contains(categories, c => c.Type == SuggestionCategoryType.ArtistDiscover && c.Title.StartsWith("Discover ", StringComparison.Ordinal));
        var variety = categories.Single(c => c.Key == "variety_pack");
        Assert.Equal(variety.Songs.Count, variety.Songs.Select(s => s.Song.Artist).Distinct().Count());
        Assert.Contains("different artists", variety.Description, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(2, "Two")]
    [InlineData(4, "Four")]
    [InlineData(5, "Five")]
    public void VarietyPackDescribesItsSize(int count, string word)
    {
        var (songs, rows) = Filler(8);
        var categories = Drain(Generator(songs, Index(rows.ToArray()), display: count));
        Assert.StartsWith(word, categories.Single(c => c.Key == "variety_pack").Description, StringComparison.Ordinal);
    }

    [Fact]
    public void FirstPlaysMixedRotatesInstrumentsAndHonorsSupport()
    {
        var unsupported = new SongDifficulty { Guitar = 1, Bass = 99 };
        var songs = Enumerable.Range(0, 6).Select(i => MakeSong($"s{i}", difficulty: unsupported, year: 2011)).ToList();
        var categories = Drain(Generator(songs, Index(), display: 6));
        var mixed = categories.Single(c => c.Key == "first_plays_mixed");
        Assert.All(mixed.Songs, s => Assert.Equal(Instrument.Lead, s.Instrument));
        Assert.DoesNotContain(categories, c => c.Key == "unplayed_Solo_Bass");
    }
    #endregion

    #region Rivals
    private static RivalsAllResponse Rivals(params (string Id, string? Name, string Direction, (int Song, string Instrument, int User, int Rival)[] Samples)[] rivals) =>
        new("me", ["a", "b", "c", "d", "e", "gone"],
        [
            new RivalsAllCombo("01",
                rivals.Where(r => r.Direction == "above").Select(Entry).ToList(),
                rivals.Where(r => r.Direction == "below").Select(Entry).ToList()),
        ]);

    private static RivalsAllEntry Entry((string Id, string? Name, string Direction, (int Song, string Instrument, int User, int Rival)[] Samples) r) =>
        new(r.Id, r.Name, r.Direction, r.Samples.Length, 1, 1, 1.5, null,
            r.Samples.Select(s => new RivalsAllSample(s.Song, s.Instrument, s.User, s.Rival, 100, 90)).ToList());

    [Fact]
    public void RivalIndexDedupesLimitsAndPicksClosest()
    {
        var response = new RivalsAllResponse("me", ["a", "b"],
        [
            new RivalsAllCombo("01", [Entry(("r1", "One", "above", [(0, "Solo_Guitar", 10, 5)])), Entry(("r2", null, "above", [(0, "Solo_Guitar", 10, 9), (9, "Solo_Guitar", 1, 1), (1, "Bogus", 1, 1)]))], []),
            new RivalsAllCombo("02", [Entry(("r1", "Dup", "above", [(1, "Solo_Bass", 3, 1)]))], [Entry(("r3", "Three", "below", [(1, "Solo_Bass", 3, 4)]))]),
        ]);
        var index = RivalDataIndex.Build(response, limit: 5);
        Assert.Equal(["r1", "r2", "r3"], index.SongRivals.Select(r => r.AccountId));
        Assert.Equal("One", index.SongRivals[0].DisplayName);
        Assert.Equal("Unknown", index.SongRivals[1].DisplayName);
        Assert.Equal(2, index.ByRival["r1"].Count);
        Assert.Equal("r2", index.ClosestRivalBySong["a:Solo_Guitar"].Rival.AccountId);
        Assert.Equal(-1, index.ClosestRivalBySong["b:Solo_Bass"].RankDelta);
        Assert.Single(RivalDataIndex.Build(response, combo: "02", limit: 1).SongRivals, r => r.Direction == "above");
        Assert.Empty(RivalDataIndex.Empty.SongRivals);
    }

    [Fact]
    public void RivalFamiliesFollowRankDeltaThresholds()
    {
        var (songs, rows) = Filler();
        var ids = Enumerable.Range(0, 40).Select(i => $"r{i}").ToList();
        foreach (var id in ids)
        {
            songs.Add(MakeSong(id, difficulty: LeadOnly));
            rows.Add((id, Instrument.Lead, new SuggestionScore(10, 5, 930_000, false, 2, 30, 100)));
        }
        var r1 = new List<(int, string, int, int)>();
        var r2 = new List<(int, string, int, int)>();
        for (var i = 0; i < 10; i++) r1.Add((i, "Solo_Guitar", 50, 52 + i % 4));       // rival barely ahead: gap
        for (var i = 10; i < 15; i++) r1.Add((i, "Solo_Guitar", 50, 47));              // player barely ahead: protect
        for (var i = 15; i < 20; i++) r1.Add((i, "Solo_Guitar", 50, 80));              // delta < -20: slipping
        for (var i = 20; i < 25; i++) r2.Add((i, "Solo_Guitar", 90, 40));              // player far ahead: dominate
        for (var i = 25; i < 30; i++)
        {
            r1.Add((i, "Solo_Guitar", 50, 53));
            r2.Add((i, "Solo_Guitar", 50, 51));                                        // two rivals within 10: battleground
        }
        for (var i = 30; i < 40; i++) r1.Add((i, "Solo_Guitar", 50, 46));              // more protect candidates
        var response = new RivalsAllResponse("me", ids,
            [new RivalsAllCombo("01", [Entry(("r1", "Near", "above", r1.ToArray()))], [Entry(("r2", "Other", "below", r2.ToArray()))])]);
        var generator = Generator(songs, Index(rows.ToArray()), display: 1);
        generator.SetRivalData(RivalDataIndex.Build(response));
        var categories = Drain(generator);
        string[] expected = ["song_rival_gap_r1", "song_rival_protect_r1", "song_rival_slipping_r1", "song_rival_dominate_r2",
            "song_rival_spotlight_r1", "song_rival_battleground", "song_rival_near_fc", "song_rival_star_gains", "song_rival_pct_push", "song_rival_stale"];
        Assert.True(!expected.Except(categories.Select(c => c.Key)).Any(), string.Join(",", categories.Select(c => c.Key)));
        Assert.Equal("Close the Gap vs Near", categories.Single(c => c.Key == "song_rival_gap_r1").Title);
        Assert.Equal("Near is Pulling Ahead", categories.Single(c => c.Key == "song_rival_slipping_r1").Title);
        Assert.Equal("Dominate Other", categories.Single(c => c.Key == "song_rival_dominate_r2").Title);
        Assert.StartsWith("FC These to Beat ", categories.Single(c => c.Key == "song_rival_near_fc").Title, StringComparison.Ordinal);
        Assert.All(categories.Single(c => c.Key == "song_rival_gap_r1").Songs, s =>
        {
            Assert.True(s.RivalRankDelta < 0);
            Assert.Equal("r1", s.RivalAccountId);
        });
        Assert.Equal(5, categories.Single(c => c.Key == "song_rival_spotlight_r1").Songs.Count);
    }

    [Fact]
    public void LateRivalDataIsSplicedIntoTheRunningMix()
    {
        var songs = new[] { "a", "b", "c", "d", "e" }.Select(id => MakeSong(id)).ToList();
        var generator = Generator(songs, Index());
        generator.GetNext(1);
        generator.SetRivalData(RivalDataIndex.Build(Rivals(("r1", "Late", "above", [(0, "Solo_Guitar", 50, 1), (1, "Solo_Guitar", 50, 2), (2, "Solo_Guitar", 50, 3)]))));
        var next = generator.GetNext(200);
        Assert.Contains(next, c => c.Key.StartsWith("song_rival_", StringComparison.Ordinal));
        generator.SetRivalData(null);
    }
    #endregion

    #region Filter settings
    [Fact]
    public void FilterTogglesCascadeLikeTheWeb()
    {
        var visible = new[] { Instrument.Lead, Instrument.Bass };
        var filter = SuggestionFilterSettings.Default;
        Assert.False(filter.IsActive);
        filter = filter.WithGlobalType(SuggestionCategoryType.NearFC, false, visible);
        Assert.False(filter.IsGlobalEnabled(SuggestionCategoryType.NearFC));
        Assert.False(filter.IsTypeEnabled(SuggestionCategoryType.NearFC, Instrument.Lead));
        Assert.False(filter.IsTypeEnabled(SuggestionCategoryType.NearFC, null));
        filter = filter.WithInstrumentType(SuggestionCategoryType.NearFC, Instrument.Lead, true, visible);
        Assert.True(filter.IsGlobalEnabled(SuggestionCategoryType.NearFC));
        Assert.True(filter.IsTypeEnabled(SuggestionCategoryType.NearFC, Instrument.Lead));
        Assert.False(filter.IsTypeEnabled(SuggestionCategoryType.NearFC, Instrument.Bass));
        filter = filter.WithInstrumentType(SuggestionCategoryType.NearFC, Instrument.Lead, false, visible);
        Assert.False(filter.IsGlobalEnabled(SuggestionCategoryType.NearFC));
        filter = filter.WithGlobalType(SuggestionCategoryType.NearFC, true);
        Assert.False(filter.IsActive);
        filter = filter.WithInstrument(Instrument.Bass, false);
        Assert.Equal([Instrument.Lead], filter.EffectiveInstruments(visible));
        Assert.True(filter.IsActive);
        Assert.Equal(SuggestionFilterSettings.Default, filter.WithInstrument(Instrument.Bass, true));
        Assert.NotEqual(filter, SuggestionFilterSettings.Default);
        Assert.False(filter.Equals((object)"x"));
        Assert.Equal(filter.GetHashCode(), SuggestionFilterSettings.Decode(filter.Encode()).GetHashCode());
    }

    [Fact]
    public void FilterRoundTripsAndRejectsCorruptData()
    {
        var filter = SuggestionFilterSettings.Default.WithInstrument(Instrument.Karaoke, false)
            .WithInstrumentType(SuggestionCategoryType.Stale, Instrument.Drums, false, [Instrument.Drums, Instrument.Bass]);
        var bytes = filter.Encode();
        Assert.Contains("Solo_PeripheralVocals", Encoding.UTF8.GetString(bytes), StringComparison.Ordinal);
        Assert.Equal(filter, SuggestionFilterSettings.Decode(bytes));
        Assert.Empty(SuggestionFilterSettings.Default.Encode());
        Assert.Equal(SuggestionFilterSettings.Default, SuggestionFilterSettings.Decode([]));
        Assert.Equal(SuggestionFilterSettings.Default, SuggestionFilterSettings.Decode("{"u8));
        Assert.Equal(SuggestionFilterSettings.Default, SuggestionFilterSettings.Decode("[1]"u8));
        Assert.Equal(SuggestionFilterSettings.Default, SuggestionFilterSettings.Decode(new byte[SuggestionFilterSettings.MaxBytes + 1]));
        var junk = SuggestionFilterSettings.Decode("""{"instrumentOff":["Nope",3,"Solo_Bass"],"globalTypeOff":"x","perInstrumentTypeOff":["Solo_Bass|nope"]}"""u8);
        Assert.False(junk.IsInstrumentEnabled(Instrument.Bass));
        Assert.True(junk.IsGlobalEnabled(SuggestionCategoryType.NearFC));
    }

    [Fact]
    public void CategoryFilterDropsOrTrims()
    {
        var song = MakeSong("a");
        var mixed = new SuggestionCategory("near_fc_any", "t", "d", SuggestionCategoryType.NearFC, null,
        [
            new SuggestionSongItem { Song = song, Instrument = Instrument.Lead },
            new SuggestionSongItem { Song = song, Instrument = Instrument.Bass },
            new SuggestionSongItem { Song = MakeSong("b") },
        ]);
        var single = mixed with { Key = "unfc_Solo_Bass", Instrument = Instrument.Bass, Songs = [new SuggestionSongItem { Song = song }] };
        var all = InstrumentInfo.All.ToHashSet();
        var filter = SuggestionFilterSettings.Default;
        Assert.Same(mixed, SuggestionCategoryFilter.Visible(mixed, all, filter));
        var noBass = filter.WithInstrument(Instrument.Bass, false);
        var trimmed = SuggestionCategoryFilter.Visible(mixed, noBass.EffectiveInstruments(all), noBass)!;
        Assert.Equal(2, trimmed.Songs.Count);
        Assert.Null(SuggestionCategoryFilter.Visible(single, noBass.EffectiveInstruments(all), noBass));
        Assert.Null(SuggestionCategoryFilter.Visible(mixed, all, filter.WithGlobalType(SuggestionCategoryType.NearFC, false)));
        var leadOnly = mixed with { Songs = [mixed.Songs[0]] };
        Assert.Null(SuggestionCategoryFilter.Visible(leadOnly, all, filter.WithInstrumentType(SuggestionCategoryType.NearFC, Instrument.Lead, false)));
    }

    [Fact]
    public void TypeMetadataIsCompleteAndUnique()
    {
        Assert.Equal(13, SuggestionCategoryTypeInfo.All.Count);
        Assert.Equal(13, SuggestionCategoryTypeInfo.All.Select(t => t.Key()).Distinct().Count());
        Assert.Equal(13, SuggestionCategoryTypeInfo.All.Select(t => t.Label()).Distinct().Count());
        Assert.All(SuggestionCategoryTypeInfo.All, t => Assert.EndsWith(".", t.FilterDescription(), StringComparison.Ordinal));
    }

    [Fact]
    public void FileStorePersistsDeletesAndSurvivesCorruption()
    {
        var dir = Path.Combine(Path.GetTempPath(), "fst-suggest-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(dir, "suggestions-filter.json");
        try
        {
            var store = new JsonFileSuggestionFilterStore(path);
            Assert.Equal(SuggestionFilterSettings.Default, store.Load());
            var filter = SuggestionFilterSettings.Default.WithInstrument(Instrument.Lead, false);
            store.Save(filter);
            Assert.Equal(filter, new JsonFileSuggestionFilterStore(path).Load());
            store.Save(SuggestionFilterSettings.Default);
            Assert.False(File.Exists(path));
            Directory.CreateDirectory(dir);
            File.WriteAllText(path, "not json");
            Assert.Equal(SuggestionFilterSettings.Default, store.Load());
            File.WriteAllBytes(path, new byte[SuggestionFilterSettings.MaxBytes + 10]);
            Assert.Equal(SuggestionFilterSettings.Default, store.Load());
            using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.None))
                Assert.Equal(SuggestionFilterSettings.Default, store.Load());
            Assert.EndsWith("suggestions-filter.json", JsonFileSuggestionFilterStore.DefaultPath, StringComparison.Ordinal);
            var memory = new InMemorySuggestionFilterStore();
            memory.Save(filter);
            Assert.Equal(1, memory.SaveCount);
            Assert.Equal(filter, memory.Load());
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }
    #endregion

    #region Row presentation
    [Theory]
    [InlineData("song_rival_gap_x", SuggestionRowLayout.Rival)]
    [InlineData("lb_rival_x", SuggestionRowLayout.Rival)]
    [InlineData("variety_pack", SuggestionRowLayout.Hidden)]
    [InlineData("artist_sampler_A", SuggestionRowLayout.Hidden)]
    [InlineData("artist_unplayed_a", SuggestionRowLayout.Hidden)]
    [InlineData("unplayed_Solo_Bass", SuggestionRowLayout.Hidden)]
    [InlineData("samename_X", SuggestionRowLayout.Hidden)]
    [InlineData("samename_nearfc_X", SuggestionRowLayout.SingleInstrument)]
    [InlineData("unfc_Solo_Bass", SuggestionRowLayout.UnfcAccuracy)]
    [InlineData("stale_global_1", SuggestionRowLayout.Season)]
    [InlineData("almost_elite", SuggestionRowLayout.Percentile)]
    [InlineData("pct_push_Solo_Bass", SuggestionRowLayout.Percentile)]
    [InlineData("pct_improve_5", SuggestionRowLayout.Percentile)]
    [InlineData("same_pct_improve", SuggestionRowLayout.Percentile)]
    [InlineData("improve_rankings_Solo_Bass", SuggestionRowLayout.Percentile)]
    [InlineData("near_fc_any", SuggestionRowLayout.SingleInstrument)]
    [InlineData("near_max_5k", SuggestionRowLayout.SingleInstrument)]
    [InlineData("first_plays_mixed", SuggestionRowLayout.SingleInstrument)]
    [InlineData("star_gains", SuggestionRowLayout.SingleInstrument)]
    [InlineData("almost_six_star", SuggestionRowLayout.SingleInstrument)]
    [InlineData("more_stars", SuggestionRowLayout.SingleInstrument)]
    [InlineData("something_else", SuggestionRowLayout.InstrumentChips)]
    public void RowLayoutMatchesWebKeys(string key, SuggestionRowLayout layout) => Assert.Equal(layout, SuggestionRowPresentation.LayoutFor(key));

    [Theory]
    [InlineData("Top 1%", PercentileTier.Top1)]
    [InlineData("Top 5%", PercentileTier.Top5)]
    [InlineData("Top 10%", PercentileTier.Default)]
    [InlineData("Top x%", PercentileTier.Default)]
    [InlineData("S5", PercentileTier.Default)]
    [InlineData(null, PercentileTier.Default)]
    public void PercentileTierParsesLabels(string? display, PercentileTier tier) => Assert.Equal(tier, SuggestionRowPresentation.TierFor(display));

    [Fact]
    public void RowPresentationCoversEachLayout()
    {
        var song = MakeSong("a", "Title", "Band", 1999);
        var scores = Index(("a", Instrument.Lead, new SuggestionScore(1, 6, Season: 4, IsFullCombo: true)), ("a", Instrument.Bass, new SuggestionScore(1, 2, Season: 7)));
        var chips = new[] { Instrument.Lead, Instrument.Bass, Instrument.Drums };
        SuggestionRowPresentation Make(string key, SuggestionSongItem item, Instrument? catInstrument = null) =>
            SuggestionRowPresentation.Create(new SuggestionCategory(key, "t", "d", SuggestionCategoryType.NearFC, catInstrument, [item]), item, scores, chips);

        var rival = Make("song_rival_gap_r", new SuggestionSongItem { Song = song, Instrument = Instrument.Bass, RivalName = "AVeryLongRivalName", RivalRankDelta = -4 });
        Assert.Equal("AVeryLongRi…", rival.RivalName);
        Assert.Equal("-4", rival.RivalDeltaText);
        Assert.Equal(-1, rival.RivalDeltaSign);
        Assert.Contains("behind by 4 ranks", rival.AccessibleName, StringComparison.Ordinal);
        Assert.Equal("+2", Make("song_rival_x", new SuggestionSongItem { Song = song, RivalRankDelta = 2, RivalName = "R" }).RivalDeltaText);
        Assert.Null(Make("song_rival_x", new SuggestionSongItem { Song = song }).RivalDeltaText);

        var unfc = Make("unfc_Solo_Bass", new SuggestionSongItem { Song = song, Percent = 99.7 }, Instrument.Bass);
        Assert.Equal(990_000, unfc.AccuracyExpanded);
        Assert.Null(Make("unfc_Solo_Bass", new SuggestionSongItem { Song = song }).AccuracyText);

        Assert.Equal("S7", Make("stale_global_1", new SuggestionSongItem { Song = song }).SeasonText);
        Assert.Equal("S4", Make("stale_Solo_Guitar_1", new SuggestionSongItem { Song = song, Instrument = Instrument.Lead }).SeasonText);
        Assert.Null(Make("stale_Solo_Drums_1", new SuggestionSongItem { Song = song, Instrument = Instrument.Drums }).SeasonText);

        var pct = Make("almost_elite", new SuggestionSongItem { Song = song, Instrument = Instrument.Lead, PercentileDisplay = "Top 2%" });
        Assert.Equal(PercentileTier.Top5, pct.PercentileTier);
        Assert.StartsWith("Title, Band · 1999, Lead, Top 2%", pct.AccessibleName, StringComparison.Ordinal);

        var gold = Make("star_gains", new SuggestionSongItem { Song = song, Instrument = Instrument.Lead, Stars = 6 });
        Assert.True(gold.GoldStars);
        Assert.Equal(5, gold.StarCount);
        Assert.Equal(3, Make("star_gains", new SuggestionSongItem { Song = song, Stars = 3 }).StarCount);
        Assert.Contains("1 star", Make("star_gains", new SuggestionSongItem { Song = song, Stars = 1 }).AccessibleName, StringComparison.Ordinal);
        Assert.Equal(0, Make("near_fc_any", new SuggestionSongItem { Song = song, Stars = 5 }).StarCount);

        var chipRow = Make("other", new SuggestionSongItem { Song = MakeSong("a", year: null) });
        Assert.Equal([true, true, false], chipRow.Chips.Select(c => c.HasScore));
        Assert.Equal([true, false, false], chipRow.Chips.Select(c => c.IsFullCombo));
        Assert.Equal("Artist a", chipRow.Subtitle);
        Assert.Equal(SuggestionRowLayout.Hidden, Make("variety_pack", new SuggestionSongItem { Song = song }).Layout);
        Assert.Equal(new AppRoute.SongDetail("a", Instrument.Bass),
            SuggestionRowPresentation.RouteFor(new SuggestionCategory("k", "t", "d", SuggestionCategoryType.NearFC, Instrument.Bass, []), new SuggestionSongItem { Song = song }));
        Assert.Equal("a|Solo_Bass", new SuggestionSongItem { Song = song, Instrument = Instrument.Bass }.Id);
    }
    #endregion
}
