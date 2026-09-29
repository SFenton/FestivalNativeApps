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
    public void SongPool_UsesEpicGamesSongsWithArt_ElseFallback()
    {
        Song S(string id, string artist, string? art, int? year = 2024) => new() { SongId = id, Title = "T" + id, Artist = artist, AlbumArt = art, Year = year };
        Assert.Equal(FirstRunDemos.FallbackSongs, FirstRunDemos.SongPool(null).Select(p => p.Row));
        Assert.All(FirstRunDemos.SongPool(null), p => Assert.Null(p.Art));
        var few = new[] { S("a", "Epic Games", "a.jpg"), S("b", "Other", "b.jpg") };
        Assert.Equal(FirstRunDemos.FallbackSongs.Count, FirstRunDemos.SongPool(few).Count);
        var many = new[] { S("c", "Epic Games", "c.jpg"), S("a", "Epic Games", "a.jpg", null), S("b", "Epic Games ft. X", "b.jpg"),
            S("d", "Epic Games", null), S("e", "Someone", "e.jpg") };
        var pool = FirstRunDemos.SongPool(many);
        Assert.Equal(["Ta", "Tb", "Tc"], pool.Select(p => p.Row.Title));
        Assert.Equal(("Epic Games", "a.jpg"), (pool[0].Row.Detail, pool[0].Art));
        Assert.Equal("Epic Games ft. X · 2024", pool[1].Row.Detail);
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
