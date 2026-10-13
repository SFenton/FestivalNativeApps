using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Issue #606: one shared season pill and one shared percentile pill (pattern metadata-pills).</summary>
public sealed class MetadataPillStyleTests
{
    #region Text and tiers
    [Theory]
    [InlineData(0.5, PercentileTier.Top1)]
    [InlineData(1, PercentileTier.Top1)]
    [InlineData(1.01, PercentileTier.Top5)]
    [InlineData(5, PercentileTier.Top5)]
    [InlineData(5.5, PercentileTier.Default)]
    [InlineData(double.NaN, PercentileTier.Default)]
    [InlineData(double.PositiveInfinity, PercentileTier.Default)]
    public void TierFollowsWebThresholds(double percent, PercentileTier expected) =>
        Assert.Equal(expected, MetadataPillStyle.Tier(percent));

    [Theory]
    [InlineData("Top 1%", PercentileTier.Top1)]
    [InlineData("Top 0.5%", PercentileTier.Top1)]
    [InlineData("Top 2%", PercentileTier.Top5)]
    [InlineData("Top 5%", PercentileTier.Top5)]
    [InlineData("Top 50%", PercentileTier.Default)]
    [InlineData("Top x%", PercentileTier.Default)]
    [InlineData("1%", PercentileTier.Default)]
    [InlineData("Top 1", PercentileTier.Default)]
    [InlineData(null, PercentileTier.Default)]
    public void TierForParsesTopLabels(string? label, PercentileTier expected)
    {
        Assert.Equal(expected, MetadataPillStyle.TierFor(label));
        Assert.Equal(expected, SuggestionRowPresentation.TierFor(label));
    }

    [Fact]
    public void SeasonTextAndAnnouncementMatchWebAndApple()
    {
        Assert.Equal("S9", MetadataPillStyle.SeasonText(9));
        Assert.Equal("S12", MetadataPillStyle.SeasonText(12));
        Assert.Equal("Season 9", MetadataPillStyle.SeasonAnnouncement(9, false));
        Assert.Equal("Current season 9", MetadataPillStyle.SeasonAnnouncement(9, true));
    }

    [Theory]
    [InlineData(9, 9, true)]
    [InlineData(8, 9, false)]
    [InlineData(9, null, false)]
    [InlineData(0, 0, false)]
    public void CurrentSeasonNeedsAKnownEqualSeason(int season, int? current, bool expected) =>
        Assert.Equal(expected, MetadataPillStyle.IsCurrentSeason(season, current));
    #endregion

    #region Roles and geometry
    [Fact]
    public void SeasonRolesInvertForTheCurrentSeason()
    {
        var plain = MetadataPillStyle.Season(false);
        var current = MetadataPillStyle.Season(true);
        Assert.Equal(new MetadataPillRoles("FSTSeasonPillFillBrush", "FSTSeasonPillTextBrush", "FSTSeasonPillStrokeBrush"), plain);
        Assert.Equal(new MetadataPillRoles("FSTCurrentSeasonFillBrush", "FSTCurrentSeasonTextBrush", "FSTCurrentSeasonStrokeBrush"), current);
        Assert.False(plain.Bold || plain.Italic || plain.Skew);
    }

    [Fact]
    public void PercentileRolesFollowWebTiers()
    {
        var top1 = MetadataPillStyle.Percentile(PercentileTier.Top1);
        Assert.True(top1.Bold && top1.Italic && top1.Skew);
        Assert.Equal("FSTTopOneStrokeBrush", top1.Stroke);
        var top5 = MetadataPillStyle.Percentile(PercentileTier.Top5);
        Assert.True(top5.Bold);
        Assert.False(top5.Italic || top5.Skew);
        Assert.Equal("FSTEmphasisStrokeBrush", top5.Stroke);
        var plain = MetadataPillStyle.Percentile(PercentileTier.Default);
        Assert.Equal(new MetadataPillRoles("FSTMetadataPillFillBrush", "FSTMetadataPillTextBrush", "FSTNeutralPillStrokeBrush"), plain);
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(-1, 0)]
    [InlineData(1, 36)]
    [InlineData(2, 36)]
    [InlineData(3, 39)]
    [InlineData(4, 46)]
    public void SeasonWidthReservesTheWidestPill(int chars, double expected) =>
        Assert.Equal(expected, MetadataPillStyle.SeasonWidth(chars));
    #endregion

    #region Consumers
    [Fact]
    public void SuggestionSeasonPillKnowsTheCurrentSeason()
    {
        var song = new Song { SongId = "a", Title = "Title", Artist = "Band" };
        var scores = new Dictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>>
        {
            ["a"] = new Dictionary<Instrument, SuggestionScore> { [Instrument.Lead] = new(1, 6, Season: 9) },
        };
        var item = new SuggestionSongItem { Song = song, Instrument = Instrument.Lead };
        var category = new SuggestionCategory("stale_Solo_Guitar_1", "t", "d", SuggestionCategoryType.NearFC, Instrument.Lead, [item]);

        var current = SuggestionRowPresentation.Create(category, item, scores, [], currentSeason: 9);
        Assert.Equal(9, current.Season);
        Assert.Equal("S9", current.SeasonText);
        Assert.True(current.IsCurrentSeason);

        var older = SuggestionRowPresentation.Create(category, item, scores, [], currentSeason: 10);
        Assert.Equal(9, older.Season);
        Assert.False(older.IsCurrentSeason);
        Assert.False(SuggestionRowPresentation.Create(category, item, scores, []).IsCurrentSeason);
    }

    [Theory]
    [InlineData(1, PercentileTier.Top1)]
    [InlineData(5, PercentileTier.Top5)]
    [InlineData(25, PercentileTier.Default)]
    public void ProfilePercentileRowUsesTheSharedTier(int percentile, PercentileTier expected) =>
        Assert.Equal(expected, new PlayerPercentileRow(new PlayerPercentileBucket(percentile, 1), Instrument.Lead).Tier);

    [Fact]
    public void FirstRunMetadataDemoTypesSeasonAndPercentilePills()
    {
        var sample = new FirstRunDemoMetadata(123456, 990000, false, 5, "Top 1%", 11, 3);
        var pills = FirstRunDemos.MetadataPillsFor(sample, FirstRunDemoMetadataLayout.PercentileSeason);
        Assert.Equal(new FirstRunDemoPill(FirstRunDemoPillKind.Percentile, "Top 1%"), pills[0]);
        Assert.Equal(new FirstRunDemoPill(FirstRunDemoPillKind.Season, "S11", 11), pills[1]);
        Assert.All(FirstRunDemos.MetadataPillsFor(sample, FirstRunDemoMetadataLayout.ScoreAccuracy), p => Assert.Equal(FirstRunDemoPillKind.Text, p.Kind));
    }

    [Fact]
    public void ScoreRowsExposeTheirSeasonNumber()
    {
        ILeaderboardScoreRow song = new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "a", Score = 1, Season = 9 }, false);
        Assert.Equal(9, song.SeasonNumber);
        ILeaderboardScoreRow band = new SongBandSpotlightRow(new SongBandLeaderboardEntry { BandType = "Band_Duets", TeamKey = "a:b", Score = 1 });
        Assert.Null(band.SeasonNumber);
    }
    #endregion
}