namespace Festival.Core.Tests;

public class FirstRunDemoTests
{
    [Fact]
    public void EveryCatalogueSlide_HasALiveDemo()
    {
        var ids = Enum.GetValues<FirstRunPageKey>().SelectMany(FirstRunCatalog.Slides).Select(s => s.Id).ToList();
        Assert.Equal(42, ids.Count);
        Assert.All(ids, id => Assert.NotNull(FirstRunDemos.KindFor(id)));
        Assert.Null(FirstRunDemos.KindFor("unknown"));
        Assert.Null(FirstRunDemos.KindFor(null));
        Assert.Equal(FirstRunDemoKind.LeavingPulse, FirstRunDemos.KindFor("songs-leaving-tomorrow"));
        Assert.Equal(FirstRunDemoKind.ShopTiles, FirstRunDemos.KindFor("shop-overview"));
    }

    [Fact]
    public void Timing_MatchesTheWebSwapConstants()
    {
        Assert.Equal(TimeSpan.FromSeconds(5), FirstRunDemos.Cycle);
        Assert.Equal(TimeSpan.FromSeconds(5), FirstRunDemoTiming.Interval);
        Assert.Equal(TimeSpan.FromMilliseconds(400), FirstRunDemos.Fade);
        Assert.Equal(TimeSpan.FromMilliseconds(400), FirstRunDemoTiming.FadeOut);
        Assert.Equal(TimeSpan.FromMilliseconds(400), FirstRunDemoTiming.FadeIn);
        Assert.Equal(TimeSpan.FromMilliseconds(2500), FirstRunDemoTiming.BarSelect);
        Assert.Equal(TimeSpan.FromMilliseconds(300), FirstRunDemoTiming.BarSelectFade);
        Assert.Equal(TimeSpan.FromMilliseconds(125), FirstRunDemoTiming.Stagger);
    }

    [Theory]
    [InlineData(180, 210, 1)]
    [InlineData(210, 210, 1)]
    [InlineData(420, 210, 0.5)]
    [InlineData(300, double.PositiveInfinity, 1)]
    [InlineData(300, 0, 1)]
    [InlineData(double.NaN, 210, 1)]
    public void Fit_ShrinksOnlyADemoTallerThanItsFrame(double natural, double available, double expected) =>
        Assert.Equal(expected, FirstRunDemoFit.Scale(natural, available), 6);

    [Fact]
    public void DataStatus_ReportsCatalogueOnlyForRealSongs()
    {
        Assert.Equal(FirstRunDemos.PlaceholderStatus, FirstRunDemos.DataStatus(FirstRunDemos.SongPool(null)));
        Assert.Equal(FirstRunDemos.PlaceholderStatus, FirstRunDemos.DataStatus([]));
        var pool = FirstRunDemos.SongPool([new Song { SongId = "a", Title = "A", Artist = "X", AlbumArt = "a.jpg" }]);
        Assert.Equal("catalogue", FirstRunDemos.DataStatus(pool));
        Assert.Equal("placeholder", FirstRunDemos.PlaceholderStatus);
    }

    [Theory]
    [InlineData(false, true, true, false, true, FirstRunDemoRotationState.Static)]
    [InlineData(false, false, false, true, false, FirstRunDemoRotationState.Static)]
    [InlineData(true, true, true, false, true, FirstRunDemoRotationState.Running)]
    [InlineData(true, false, true, false, true, FirstRunDemoRotationState.Inactive)]
    [InlineData(true, true, false, false, true, FirstRunDemoRotationState.Inactive)]
    [InlineData(true, true, true, true, true, FirstRunDemoRotationState.Hidden)]
    [InlineData(true, false, true, true, true, FirstRunDemoRotationState.Hidden)]
    [InlineData(true, true, true, true, false, FirstRunDemoRotationState.Hidden)]
    [InlineData(true, true, true, false, false, FirstRunDemoRotationState.Background)]
    [InlineData(true, false, true, false, false, FirstRunDemoRotationState.Background)]
    public void RotationState_RunsOnlyForTheVisibleSlideInAVisibleForegroundWindow(bool rotates, bool active, bool loaded, bool hidden, bool foreground, FirstRunDemoRotationState expected) =>
        Assert.Equal(expected, FirstRunDemoRotationStatus.State(rotates, active, loaded, hidden, foreground));

    [Theory]
    [InlineData(FirstRunDemoRotationState.Static, 3, true, "catalogue")]
    [InlineData(FirstRunDemoRotationState.Running, 0, true, "catalogue rotation=running swaps=0 swap=none")]
    [InlineData(FirstRunDemoRotationState.Running, 2, true, "catalogue rotation=running swaps=2 swap=fade")]
    [InlineData(FirstRunDemoRotationState.Running, 4, false, "catalogue rotation=running swaps=4 swap=instant")]
    [InlineData(FirstRunDemoRotationState.Inactive, 0, false, "catalogue rotation=inactive swaps=0 swap=none")]
    [InlineData(FirstRunDemoRotationState.Hidden, 1, true, "catalogue rotation=not-visible swaps=1 swap=fade")]
    [InlineData(FirstRunDemoRotationState.Background, 1, true, "catalogue rotation=background swaps=1 swap=fade")]
    public void RotationStatus_AppendsTheRotationOnlyForRotatingDemos(FirstRunDemoRotationState state, int swaps, bool faded, string expected) =>
        Assert.Equal(expected, FirstRunDemoRotationStatus.Format(FirstRunDemos.CatalogueStatus, state, swaps, faded));

    [Fact]
    public void SongPool_UsesCatalogueSongsWithArt_EpicGamesFirst_ElsePlaceholders()
    {
        Song S(string id, string artist, string? art, int? year = 2024) => new() { SongId = id, Title = "T" + id, Artist = artist, AlbumArt = art, Year = year };
        foreach (var empty in new[] { null, Array.Empty<Song>(), [S("x", "Epic Games", null), S("y", "Other", "")] })
        {
            var placeholders = FirstRunDemos.SongPool(empty);
            Assert.Equal(FirstRunDemos.MaxVisibleSongs, placeholders.Count);
            Assert.All(placeholders, p => Assert.True(p.IsPlaceholder && p.Row.Title == "" && p.Row.Detail == "" && p.Art is null));
        }
        // A short catalogue shows its real songs, padded with placeholders rather than invented rows.
        var few = FirstRunDemos.SongPool([S("b", "Other", "b.jpg")]);
        Assert.Equal(["b", null, null, null, null], few.Select(p => p.SongId));
        var many = new[] { S("c", "Epic Games", "c.jpg"), S("a", "Epic Games", "a.jpg", null), S("b", "Epic Games ft. X", "b.jpg"),
            S("d", "Epic Games", null), S("e", "Someone", "e.jpg") };
        var pool = FirstRunDemos.SongPool(many);
        Assert.Equal(["Tc", "Ta", "Tb", "Te", ""], pool.Select(p => p.Row.Title));
        Assert.All(pool.Take(4), p => Assert.False(p.IsPlaceholder));
        Assert.True(pool[4].IsPlaceholder);
        Assert.Equal(("Epic Games", "a.jpg"), (pool[1].Row.Detail, pool[1].Art));
        Assert.Equal("Epic Games ft. X · 2024", pool[2].Row.Detail);
        Assert.Equal(["e", "c", "a", "b", null], FirstRunDemos.SongPool(many, ["e", "d", "missing", "e"]).Select(p => p.SongId));
        var lots = Enumerable.Range(0, 20).Select(i => S($"s{i:00}", "Epic Games", "x.jpg")).ToList();
        Assert.Equal(FirstRunDemos.PoolSize, FirstRunDemos.SongPool(lots).Count);
        Assert.Empty(FirstRunDemos.Pick(many, 0));
    }

    [Fact]
    public void SongPool_ShortCatalogue_NeverRepeatsASongWithinTheVisibleRows()
    {
        // Issue #257: Statistics' top songs shows four rows, Rival detail four and the Suggestions card five; with a
        // pool padded only to three rows, row four wrapped to the first song and showed it twice.
        Assert.True(FirstRunDemos.MaxVisibleSongs >= FirstRunDemos.RowCount);
        Assert.True(FirstRunDemos.PoolSize >= FirstRunDemos.MaxVisibleSongs);
        for (var real = 0; real <= FirstRunDemos.MaxVisibleSongs; real++)
        {
            var catalog = Enumerable.Range(0, real).Select(i => new Song { SongId = $"s{i}", Title = $"T{i}", Artist = "A", AlbumArt = "x.jpg" }).ToList();
            var pool = FirstRunDemos.SongPool(catalog);
            Assert.True(pool.Count >= FirstRunDemos.MaxVisibleSongs);
            for (var rows = 1; rows <= FirstRunDemos.MaxVisibleSongs; rows++)
            {
                var visible = Enumerable.Range(0, rows).Select(i => pool[i % pool.Count]).Where(s => !s.IsPlaceholder).Select(s => s.SongId).ToList();
                Assert.Equal(visible.Distinct().Count(), visible.Count);
                Assert.Equal(Math.Min(real, rows), visible.Count);
            }
        }
    }

    [Fact]
    public void ShopPreference_RequiresAMatchingVisibleFeed()
    {
        var feed = new ShopResponse { Count = 2, Songs = [new() { SongId = "f", Title = "F", Artist = "A", ShopUrl = "https://www.fortnite.com/item-shop/jam-tracks/f" },
            new() { SongId = "a", Title = "A", Artist = "A", ShopUrl = "https://www.fortnite.com/item-shop/jam-tracks/a" }] };
        var offers = feed.Songs.ToDictionary(s => s.SongId);
        Assert.Equal(["f", "a"], FirstRunDemos.ShopPreference(feed, offers, hideShop: false));
        Assert.Empty(FirstRunDemos.ShopPreference(feed, null, hideShop: false));
        Assert.Empty(FirstRunDemos.ShopPreference(feed, offers, hideShop: true));
        Assert.Empty(FirstRunDemos.ShopPreference(null, offers, hideShop: false));
        Assert.True(FirstRunDemos.UsesShopSongs(FirstRunDemoKind.ShopTiles));
        Assert.True(FirstRunDemos.UsesShopSongs(FirstRunDemoKind.LeavingPulse));
        Assert.False(FirstRunDemos.UsesShopSongs(FirstRunDemoKind.Metadata));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 1)]
    [InlineData(3, 1)]
    [InlineData(4, 2)]
    [InlineData(6, 2)]
    [InlineData(7, 3)]
    [InlineData(20, 3)]
    public void SwapCount_MatchesWebTable(int rows, int expected) =>
        Assert.Equal(expected, FirstRunDemoRotation.SwapCount(rows));

    [Fact]
    public void SwapIndices_AreDistinctInRangeNonRepeatingAndDeterministic()
    {
        var first = FirstRunDemoRotation.SwapIndices(3, 6);
        var repeat = FirstRunDemoRotation.SwapIndices(3, 6);
        Assert.Equal(repeat, first);
        Assert.Equal(2, first.Count);
        Assert.Equal(first.Count, first.Distinct().Count());
        Assert.All(first, i => Assert.InRange(i, 0, 5));

        var next = FirstRunDemoRotation.SwapIndices(4, 6, first.ToHashSet());
        Assert.Equal(2, next.Count);
        Assert.NotEqual(first, next);
        Assert.Equal(next.Count, next.Distinct().Count());
        Assert.All(next, i => Assert.InRange(i, 0, 5));
    }

    [Fact]
    public void RowRotation_WalksPoolWithoutDuplicateVisibleIds()
    {
        var pool = Enumerable.Range(0, 6).Select(i => new FirstRunDemoSong($"s{i}", new FirstRunDemoRow($"Song {i}", "Epic Games"), null)).ToList();
        var rotation = new FirstRunRowRotation<FirstRunDemoSong>(pool, 3);
        Assert.Equal(["s0", "s1", "s2"], rotation.Rows.Select(r => r.Id));
        var first = rotation.NextSwap();
        rotation.Replace(first);
        Assert.Equal(3, rotation.Rows.Select(r => r.Id).Distinct().Count());
        Assert.Contains("s3", rotation.Rows.Select(r => r.Id));
        var seen = rotation.Rows.Select(r => r.Id).ToHashSet();
        for (var i = 0; i < 6; i++)
        {
            var indices = rotation.NextSwap();
            rotation.Replace(indices);
            Assert.Equal(rotation.Rows.Count, rotation.Rows.Select(r => r.Id).Distinct().Count());
            foreach (var id in rotation.Rows.Select(r => r.Id)) seen.Add(id);
        }
        Assert.Subset(seen, pool.Select(p => p.Id).ToHashSet());
        Assert.Contains("s5", seen);
    }

    [Fact]
    public void RowRotation_DoesNotRotateWhenPoolCannotReplaceVisibleRows()
    {
        var pool = Enumerable.Range(0, 3).Select(i => new FirstRunDemoSong($"s{i}", new FirstRunDemoRow($"Song {i}", "Epic Games"), null)).ToList();
        var rotation = new FirstRunRowRotation<FirstRunDemoSong>(pool, 3);
        Assert.False(rotation.CanRotate);
        Assert.Empty(rotation.NextSwap());
    }

    [Fact]
    public void RowRotation_HoldsPlaceholdersStill()
    {
        Assert.False(new FirstRunRowRotation<FirstRunDemoSong>(FirstRunDemos.SongPool(null), FirstRunDemos.RowCount).CanRotate);
        var shortPool = FirstRunDemos.SongPool([new Song { SongId = "b", Title = "B", Artist = "Other", AlbumArt = "b.jpg" }]);
        var rotation = new FirstRunRowRotation<FirstRunDemoSong>(shortPool, FirstRunDemos.RowCount);
        Assert.False(rotation.CanRotate);
        Assert.Empty(rotation.NextSwap());
    }

    [Fact]
    public void WindowRotation_WrapsByVisibleCount()
    {
        var rotation = new FirstRunWindowRotation<int>([1, 2, 3, 4, 5, 6], 3);
        Assert.Equal([1, 2, 3], rotation.Rows);
        rotation.Advance();
        Assert.Equal([4, 5, 6], rotation.Rows);
        rotation.Advance();
        Assert.Equal([1, 2, 3], rotation.Rows);
        var wrapped = new FirstRunWindowRotation<int>([1, 2, 3, 4, 5], 3);
        wrapped.Advance();
        Assert.Equal([4, 5, 1], wrapped.Rows);
    }

    [Fact]
    public void ScorePattern_UsesWebInt32Utf16Hash()
    {
        Assert.Equal(65, FirstRunDemoScorePattern.Hash("A"));
        Assert.Equal(67, FirstRunDemoScorePattern.Hash("C"));
        Assert.Equal([FirstRunDemoScorePattern.State.Scored, FirstRunDemoScorePattern.State.NoScore, FirstRunDemoScorePattern.State.NoScore, FirstRunDemoScorePattern.State.Scored],
            FirstRunDemoScorePattern.States("A", 4));
        Assert.Equal([FirstRunDemoScorePattern.State.FullCombo, FirstRunDemoScorePattern.State.NoScore, FirstRunDemoScorePattern.State.NoScore, FirstRunDemoScorePattern.State.Scored],
            FirstRunDemoScorePattern.States("C", 4));
    }

    [Fact]
    public void RotationMap_ContainsExactlyTheWebRotatingSlides()
    {
        var expected = new[]
        {
            "songs-song-list", "songs-icons", "songs-metadata", "statistics-top-songs", "songinfo-bar-select",
            "suggestions-category-card", "leaderboards-experimental-metrics", "compete-hub", "compete-rivals",
            "rivals-overview", "rivals-instruments", "rivals-detail",
        }.Order(StringComparer.Ordinal).ToList();
        Assert.Equal(expected, FirstRunDemos.RotatingSlideIds);
        Assert.All(expected, id => Assert.True(FirstRunDemos.Rotates(id), id));
        Assert.False(FirstRunDemos.Rotates("songs-sort"));
        Assert.False(FirstRunDemos.Rotates("songs-filter"));
        Assert.False(FirstRunDemos.Rotates("shop-overview"));
        Assert.False(FirstRunDemos.Rotates("shop-highlighting"));
    }

    [Fact]
    public void TopSongsDemo_RotatesSongsUnderPinnedPills()
    {
        // Issue #257: each slot's pill is the web's DEMO_PERCENTILES[i]; a swap changes the song, never the pill.
        var catalog = Enumerable.Range(0, 20).Select(i => new Song { SongId = $"s{i:00}", Title = $"T{i}", Artist = "A", AlbumArt = "x.jpg" });
        var demo = new FirstRunTopSongsDemo(FirstRunDemos.SongPool(catalog));
        string[] pills = ["Top 1.2%", "Top 3.5%", "Top 7.8%", "Top 14.2%"];
        Assert.Equal(pills, Enumerable.Range(0, FirstRunTopSongsDemo.SlotCount).Select(FirstRunTopSongsDemo.Pill));
        Assert.Equal(["s00", "s01", "s02", "s03"], demo.Songs.Select(s => s.SongId));
        var everSwapped = new HashSet<int>();
        int? firstFull = null;
        for (var tick = 1; tick <= 6; tick++)
        {
            var before = demo.Songs.Select(s => s.SongId).ToList();
            var swapped = demo.Advance();
            Assert.Equal(2, swapped.Count);
            Assert.Equal(tick, demo.Rotations);
            everSwapped.UnionWith(swapped);
            if (everSwapped.Count == FirstRunTopSongsDemo.SlotCount) firstFull ??= tick;
            for (var slot = 0; slot < FirstRunTopSongsDemo.SlotCount; slot++)
                Assert.Equal(swapped.Contains(slot), before[slot] != demo.Songs[slot].SongId);
            Assert.Equal(FirstRunTopSongsDemo.SlotCount, demo.Songs.Select(s => s.SongId).Distinct().Count());
            Assert.Equal(pills, Enumerable.Range(0, FirstRunTopSongsDemo.SlotCount).Select(FirstRunTopSongsDemo.Pill));
        }
        // tools/windows/first_run_journey.py (TOP_SONG_TICKS) waits for every slot's first swap: three ticks.
        Assert.Equal(3, firstFull);
    }

    [Fact]
    public void TopSongsDemo_ShortOrMissingCatalogue_DoesNotRotate()
    {
        foreach (var real in new[] { 0, 2 })
        {
            var catalog = Enumerable.Range(0, real).Select(i => new Song { SongId = $"s{i}", Title = $"T{i}", Artist = "A", AlbumArt = "x.jpg" });
            var demo = new FirstRunTopSongsDemo(FirstRunDemos.SongPool(catalog));
            Assert.Equal(FirstRunTopSongsDemo.SlotCount, demo.Songs.Count);
            Assert.Equal(FirstRunTopSongsDemo.SlotCount - real, demo.Songs.Count(s => s.IsPlaceholder));
            Assert.Empty(demo.Advance());
            Assert.Equal(0, demo.Rotations);
        }
    }

    [Fact]
    public void WebDataPools_AreAvailable()
    {
        Assert.Equal(10, FirstRunDemos.Rankings.Count);
        Assert.Equal("GoldStreak", FirstRunDemos.Rankings[0].DisplayName);
        Assert.Equal("You", FirstRunDemos.PlayerRanking.DisplayName);
        Assert.Equal(10, FirstRunDemos.MetaData.Count);
        Assert.Equal(6, FirstRunDemos.MetadataLayouts.Count);
        Assert.Equal([1.2, 3.5, 7.8, 14.2, 22.6, 35.1, 48.9], FirstRunDemos.TopSongPercentiles);
        // Issue #257: the web pins each row's pill (DEMO_PERCENTILES[i]); rotation must not reorder or repeat them.
        Assert.Equal([1.2, 3.5, 7.8, 14.2], Enumerable.Range(0, 4).Select(FirstRunDemos.TopSongPercentile));
        Assert.Equal(1.2, FirstRunDemos.TopSongPercentile(7));
        Assert.Equal(4, FirstRunDemos.SuggestionTemplates.Count);
        Assert.Equal(4, FirstRunDemos.ExperimentalMetrics.Count);
        Assert.Equal(6, FirstRunDemos.RivalsAbove.Count);
        Assert.Equal(6, FirstRunDemos.RivalsBelow.Count);
        Assert.Equal(3, FirstRunDemos.InstrumentRivals.Count);
        Assert.Equal(6, FirstRunDemos.RivalDetailCategories.Count);
    }
}
