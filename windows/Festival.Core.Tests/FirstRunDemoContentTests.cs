using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Issue #380: the real-control first-run demo content, entrance stagger, Shop pulses and auto-scroll.</summary>
public class FirstRunDemoContentTests
{
    private static readonly DateTimeOffset Today = new(2026, 10, 7, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Entrance_CoversEveryCatalogueSlide_WithWebDelays()
    {
        var ids = Enum.GetValues<FirstRunPageKey>().SelectMany(FirstRunCatalog.Slides).Select(s => s.Id).ToHashSet();
        Assert.True(ids.SetEquals(FirstRunEntrance.SlideIds));

        var list = FirstRunEntrance.For("songs-song-list");
        Assert.Equal(TimeSpan.Zero, list.ItemDelay(0));
        Assert.Equal(TimeSpan.FromMilliseconds(250), list.ItemDelay(2));
        Assert.Equal(TimeSpan.FromMilliseconds(500), list.TitleDelay);
        Assert.Equal(TimeSpan.FromMilliseconds(625), list.DescriptionDelay);

        var offset = FirstRunEntrance.For("songinfo-top-scores");
        Assert.Equal(TimeSpan.FromMilliseconds(125), offset.ItemDelay(0));
        Assert.Equal(TimeSpan.FromMilliseconds(125), offset.ItemDelay(-3));
        Assert.Equal(TimeSpan.FromMilliseconds(300), FirstRunEntrance.For("songs-sort").ItemDelay(1));
        Assert.Equal(TimeSpan.Zero, FirstRunEntrance.For("songinfo-chart").ItemDelay(4));

        Assert.Same(FirstRunEntrance.None, FirstRunEntrance.For(null));
        Assert.Same(FirstRunEntrance.None, FirstRunEntrance.For("unknown"));
        Assert.Equal(TimeSpan.Zero, FirstRunEntrance.None.TitleDelay);
        Assert.Equal(TimeSpan.FromMilliseconds(400), FirstRunEntrance.Duration);
        Assert.Equal(12f, FirstRunEntrance.Rise);
    }

    [Fact]
    public void ShopPattern_PulsesRowsLikeTheWebDemos()
    {
        Assert.Equal(SongRowShopPulse.InShop, FirstRunShopPattern.Pulse("songs-shop-highlight", 0, 3));
        Assert.Null(FirstRunShopPattern.Pulse("songs-shop-highlight", 1, 3));
        Assert.Equal(SongRowShopPulse.InShop, FirstRunShopPattern.Pulse("shop-highlighting", 2, 3));

        Assert.Equal(SongRowShopPulse.New, FirstRunShopPattern.Pulse("songs-new-in-shop", 0, 3));
        Assert.Equal(SongRowShopPulse.InShop, FirstRunShopPattern.Pulse("shop-new-items", 1, 3));
        Assert.Null(FirstRunShopPattern.Pulse("shop-new-items", 2, 3));

        Assert.Equal(SongRowShopPulse.Leaving, FirstRunShopPattern.Pulse("shop-leaving-tomorrow", 0, 3));
        Assert.Equal(SongRowShopPulse.InShop, FirstRunShopPattern.Pulse("shop-leaving-tomorrow", 1, 3));
        Assert.Equal(SongRowShopPulse.Leaving, FirstRunShopPattern.Pulse("songs-leaving-tomorrow", 1, 3));
        Assert.Null(FirstRunShopPattern.Pulse("songs-leaving-tomorrow", 2, 3));
        Assert.Null(FirstRunShopPattern.Pulse("songs-song-list", 0, 3));
        Assert.Null(FirstRunShopPattern.Pulse(null, 0, 3));
    }

    [Fact]
    public void ShopPattern_BadgesOnlyShopPageRows()
    {
        Assert.Equal(ShopHighlight.New, FirstRunShopPattern.Badge("shop-new-items", 0, 3));
        Assert.Null(FirstRunShopPattern.Badge("shop-new-items", 1, 3));
        Assert.Equal(ShopHighlight.LeavingTomorrow, FirstRunShopPattern.Badge("shop-leaving-tomorrow", 0, 3));
        Assert.Null(FirstRunShopPattern.Badge("songs-new-in-shop", 0, 3));
        Assert.Null(FirstRunShopPattern.Badge(null, 0, 3));

        Assert.Equal(ShopHighlight.New, FirstRunShopPattern.Tile(0));
        Assert.Null(FirstRunShopPattern.Tile(1));
        Assert.Equal(ShopHighlight.LeavingTomorrow, FirstRunShopPattern.Tile(5));
    }

    [Fact]
    public void AutoScroll_WrapsAndFadesOnlyTowardHiddenContent()
    {
        Assert.Equal(0, FirstRunAutoScroll.Range(200, 300));
        Assert.Equal(150, FirstRunAutoScroll.Range(450, 300));
        Assert.Equal(TimeSpan.Zero, FirstRunAutoScroll.Pass(0));
        Assert.Equal(TimeSpan.FromSeconds(5), FirstRunAutoScroll.Pass(150));

        Assert.Equal(0, FirstRunAutoScroll.Offset(TimeSpan.FromSeconds(2), 0));
        Assert.Equal(0, FirstRunAutoScroll.Offset(TimeSpan.FromSeconds(-1), 150));
        Assert.Equal(60, FirstRunAutoScroll.Offset(TimeSpan.FromSeconds(2), 150), 6);
        Assert.Equal(30, FirstRunAutoScroll.Offset(TimeSpan.FromSeconds(6), 150), 6);

        Assert.Equal((0d, 36d), FirstRunAutoScroll.Fades(0, 150));
        Assert.Equal((36d, 36d), FirstRunAutoScroll.Fades(75, 150));
        Assert.Equal((36d, 10d), FirstRunAutoScroll.Fades(140, 150));
        Assert.Equal((0d, 0d), FirstRunAutoScroll.Fades(0, 0));
        Assert.Equal(TimeSpan.FromMilliseconds(100), FirstRunAutoScroll.StartDelay);
        Assert.Equal(6, FirstRunDemoContent.ScrollTemplates.Count);
    }

    [Fact]
    public void ScoreRows_ShareOneColumnPlan_AndDemoIds()
    {
        var top = FirstRunDemoContent.TopScores("songinfo-top-scores");
        Assert.Equal([1, 2, 3, 4], top.Select(r => r.Rank));
        Assert.All(top, r => Assert.Same(top[0].Section, r.Section));
        Assert.Equal("fst.first-run.demo.songinfo-top-scores.row.1", top[0].AutomationId);
        Assert.Null(top[0].Route);

        var history = FirstRunDemoContent.History("playerhistory-score-list", 9, Today, 12);
        Assert.Equal(5, history.Count);
        Assert.True(history[0].IsBest);
        Assert.False(history[1].IsBest);
        Assert.All(history, r => Assert.Same(history[0].Section, r.Section));
        Assert.Equal(12, history[1].Point.Entry.Season);
        Assert.True(history[2].Point.Entry.Season < 12);
        Assert.StartsWith("fst.first-run.demo.playerhistory-score-list.row.", history[0].AutomationId);
        Assert.Empty(FirstRunDemoContent.History("x", -1, Today, 0));
    }

    [Fact]
    public void Chart_SelectsOneBar_AndWrapsTheDetail()
    {
        var points = FirstRunDemoContent.ChartPoints(Today);
        Assert.Equal(FirstRunDemos.BarSelectBars.Count, points.Count);
        Assert.Equal(Today.Date, points[^1].Date.Date);
        var bars = FirstRunDemoContent.ChartBars(Today, 1);
        Assert.Equal([false, true, false], bars.Select(b => b.IsSelected).Take(3));
        Assert.DoesNotContain(FirstRunDemoContent.ChartBars(Today, null), b => b.IsSelected);
        var detail = FirstRunDemoContent.ChartDetail(Today, -1);
        Assert.True(detail.IsDetail);
        Assert.Equal(points[^1].Entry.NewScore, detail.Point.Entry.NewScore);
    }

    [Fact]
    public void Rankings_MarkThePlayer_AndShareColumns()
    {
        var rows = FirstRunDemoContent.Rankings([new(1, "GoldStreak", "2,480,000", false), FirstRunDemos.PlayerRanking], "leaderboards-your-rank");
        Assert.False(rows[0].IsSelected);
        Assert.True(rows[1].IsSelected);
        Assert.Same(rows[0].Section, rows[1].Section);
        Assert.Equal("fst.first-run.demo.leaderboards-your-rank.row.42", rows[1].AutomationId);
        Assert.Null(rows[1].Route);
        Assert.Contains("You", rows[1].Announcement);
    }

    [Fact]
    public void Metadata_UsesTheRealSongsPills()
    {
        var sample = new FirstRunDemoMetadata(198942, 1000000, true, 6, "Top 5%", 10, 4);
        var fields = FirstRunDemoContent.MetadataFields(sample, FirstRunDemoMetadataLayout.ScoreAccuracy);
        Assert.Equal([MetadataField.Score, MetadataField.Percentage], fields.Select(f => f.Kind));
        Assert.True(fields[1].FullCombo);
        Assert.EndsWith("FC", fields[1].Text);

        var plain = sample with { FullCombo = false, Accuracy = 960000 };
        Assert.False(FirstRunDemoContent.MetadataFields(plain, FirstRunDemoMetadataLayout.AccuracyDifficulty)[0].FullCombo);
        var stars = FirstRunDemoContent.MetadataFields(sample, FirstRunDemoMetadataLayout.StarsDifficulty);
        Assert.Equal((5, true), stars[0].Stars);
        Assert.Equal(MetadataField.Intensity, stars[1].Kind);
        var percentile = FirstRunDemoContent.MetadataFields(sample, FirstRunDemoMetadataLayout.PercentileSeason);
        Assert.Equal(SongPercentileTier.TopFive, percentile[0].Percentile);
        Assert.Equal("S10", percentile[1].Text);
        var fallback = FirstRunDemoContent.MetadataFields(sample with { Percentile = "Top 1%" }, (FirstRunDemoMetadataLayout)99);
        Assert.Equal([MetadataField.Percentile, MetadataField.Score], fallback.Select(f => f.Kind));
        Assert.Equal(SongPercentileTier.TopOne, fallback[0].Percentile);
        Assert.Equal(SongPercentileTier.Ordinary,
            FirstRunDemoContent.MetadataFields(sample with { Percentile = "n/a" }, FirstRunDemoMetadataLayout.PercentileSeason)[0].Percentile);
    }

    [Fact]
    public void TopSongPill_KeepsItsSlotTier()
    {
        for (var slot = 0; slot < FirstRunTopSongsDemo.SlotCount; slot++)
        {
            var pill = FirstRunDemoContent.TopSongPill(slot);
            Assert.Equal(MetadataField.Percentile, pill.Kind);
            Assert.Equal(FirstRunTopSongsDemo.Pill(slot), pill.Text);
        }
    }

    [Fact]
    public void Suggestions_UseTheRealRowLayouts()
    {
        var lead = FirstRunDemos.SuggestionTemplates.First(t => t.Key == "unfc_guitar");
        var row = FirstRunDemoContent.Suggestion(lead, "Fixture Pulse", "Synthetic Quartet", 1);
        Assert.Equal(Instrument.Lead, row.Instrument);
        Assert.Equal("98%", row.AccuracyText);
        Assert.Null(row.PercentileText);

        var bass = FirstRunDemos.SuggestionTemplates.First(t => t.Key == "pct_push_bass");
        var push = FirstRunDemoContent.Suggestion(bass, "Fixture Orbit", "Synthetic Quartet", 0);
        Assert.Equal("Top 3%", push.PercentileText);
        Assert.Equal(PercentileTier.Top5, push.PercentileTier);
        Assert.Equal(PercentileTier.Default, FirstRunDemoContent.Suggestion(bass, "a", "b", 5).PercentileTier);

        Assert.Equal(Instrument.Vocals, FirstRunDemoContent.HeaderInstrument(FirstRunDemoContent.ScrollTemplates[2]));
        Assert.Null(FirstRunDemoContent.HeaderInstrument(FirstRunDemoContent.ScrollTemplates[^1]));
        Assert.Equal(4, FirstRunDemoContent.Metrics.Count);
    }

    [Fact]
    public void StatTiles_FollowEachStatisticsDemo()
    {
        var overview = FirstRunDemoContent.StatTiles("statistics-overview");
        Assert.Equal(["songs-played", "full-combos", "gold-stars", "avg-accuracy", "best-rank"], overview.Select(t => t.Key));
        var drill = FirstRunDemoContent.StatTiles("statistics-drill-down");
        Assert.Equal(["songs-played", "gold-stars", "avg-accuracy", "full-combos"], drill.Select(t => t.Key));
        Assert.Equal([true, false, false, true], drill.Select(t => FirstRunDemoContent.TilePulses("statistics-drill-down", t)));
        Assert.DoesNotContain(overview, t => FirstRunDemoContent.TilePulses("statistics-overview", t));
        var lead = FirstRunDemoContent.StatTiles("statistics-instrument-breakdown");
        Assert.Equal(6, lead.Count);
        Assert.Contains(lead, t => t.Key == "stars-5" && t.Link is not null);
        Assert.Empty(FirstRunDemoContent.StatTiles(null));
        Assert.Equal(6, FirstRunDemoContent.PercentileBuckets.Count);
    }

    [Fact]
    public void Rivals_UseTheRealRowsAndCategoryCopy()
    {
        Assert.Equal("closest_battles", FirstRunDemoContent.RivalCategoryKey(" Closest Battles "));
        Assert.All(FirstRunDemos.RivalDetailCategories.Keys,
            title => Assert.NotNull(RivalCategorization.Describe(FirstRunDemoContent.RivalCategoryKey(title))));
        Assert.Null(RivalCategorization.Describe("unknown"));

        var rival = new FirstRunDemoRival("acct", "KeyDrifter", 1, 148, 82, 66, 0);
        var row = FirstRunDemoContent.RivalRow(rival, RivalDirection.Above);
        Assert.Equal(66, row.SongsAhead);
        Assert.Equal(82, row.SongsBehind);
        Assert.Equal("acct", row.Route.RivalId);

        Assert.Equal(Instrument.Drums, FirstRunDemoContent.RivalInstrument("Drums"));
        Assert.Equal(Instrument.Vocals, FirstRunDemoContent.RivalInstrument("Vocals"));
        Assert.Equal(Instrument.Bass, FirstRunDemoContent.RivalInstrument("Bass"));
        Assert.Equal(Instrument.Lead, FirstRunDemoContent.RivalInstrument("Lead"));
    }
}
