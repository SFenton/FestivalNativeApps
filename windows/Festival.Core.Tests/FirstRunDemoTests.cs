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
    public void Timing_MatchesThePwa()
    {
        Assert.Equal(TimeSpan.FromSeconds(6), FirstRunDemos.Cycle);
        Assert.Equal(TimeSpan.FromMilliseconds(400), FirstRunDemos.Fade);
    }

    [Fact]
    public void SongPool_UsesCatalogueSongsWithArt_EpicGamesFirst_ElsePlaceholders()
    {
        Song S(string id, string artist, string? art, int? year = 2024) => new() { SongId = id, Title = "T" + id, Artist = artist, AlbumArt = art, Year = year };
        foreach (var empty in new[] { null, Array.Empty<Song>(), [S("x", "Epic Games", null), S("y", "Other", "")] })
        {
            var placeholders = FirstRunDemos.SongPool(empty);
            Assert.Equal(FirstRunDemos.RowCount, placeholders.Count);
            Assert.All(placeholders, p => Assert.True(p.IsPlaceholder && p.Row.Title == "" && p.Row.Detail == "" && p.Art is null));
        }
        // A short catalogue shows its real songs, padded with placeholders rather than invented rows.
        var few = FirstRunDemos.SongPool([S("b", "Other", "b.jpg")]);
        Assert.Equal(["b", null, null], few.Select(p => p.SongId));
        var many = new[] { S("c", "Epic Games", "c.jpg"), S("a", "Epic Games", "a.jpg", null), S("b", "Epic Games ft. X", "b.jpg"),
            S("d", "Epic Games", null), S("e", "Someone", "e.jpg") };
        var pool = FirstRunDemos.SongPool(many);
        Assert.Equal(["Tc", "Ta", "Tb", "Te"], pool.Select(p => p.Row.Title));
        Assert.All(pool, p => Assert.False(p.IsPlaceholder));
        Assert.Equal(("Epic Games", "a.jpg"), (pool[1].Row.Detail, pool[1].Art));
        Assert.Equal("Epic Games ft. X · 2024", pool[2].Row.Detail);
        Assert.Equal(["e", "c", "a", "b"], FirstRunDemos.SongPool(many, ["e", "d", "missing", "e"]).Select(p => p.SongId));
        var lots = Enumerable.Range(0, 20).Select(i => S($"s{i:00}", "Epic Games", "x.jpg")).ToList();
        Assert.Equal(FirstRunDemos.PoolSize, FirstRunDemos.SongPool(lots).Count);
        Assert.Empty(FirstRunDemos.Pick(many, 0));
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
    [InlineData(0, 3, 5, 0, 3)]
    [InlineData(1, 3, 5, 1, 4)]
    [InlineData(2, 3, 5, 2, 0)]
    [InlineData(3, 3, 5, 0, 1)]
    [InlineData(0, 0, 5, 0, 0)]
    [InlineData(4, 3, 0, 0, 0)]
    public void Swap_RotatesRowsAndWalksThePool(int step, int rows, int pool, int row, int index) =>
        Assert.Equal((row, index), FirstRunDemos.Swap(step, rows, pool));

    [Fact]
    public void SampleData_IsBounded()
    {
        Assert.Equal(5, FirstRunDemos.Players.Count);
        Assert.All(FirstRunDemos.Bars, b => Assert.InRange(b, 0, 1));
        Assert.NotEmpty(FirstRunDemos.MetadataPills);
        Assert.NotEmpty(FirstRunDemos.FilterChips);
        Assert.Equal(6, FirstRunDemos.Tiles.Count);
    }
}
