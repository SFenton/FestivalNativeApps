using Festival.Core.Domain;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Issue #606: one season pill and one percentile pill, sized and coloured once for every Windows surface.</summary>
public class MetadataPillStyleTests
{
    [Fact]
    public void Metrics_MatchTheWebPillsAtFluentDensity()
    {
        Assert.Equal(14, MetadataPillStyle.FontSize);
        Assert.Equal(24, MetadataPillStyle.Height);
        Assert.Equal(2, MetadataPillStyle.StrokeWidth);
        Assert.Equal(4, MetadataPillStyle.CornerRadius);
        Assert.Equal(48, MetadataPillStyle.SeasonMinWidth);
        Assert.Equal(77, MetadataPillStyle.PercentileMinWidth); // web 5.5em
    }

    [Fact]
    public void Season_TextAnnouncementAndCurrentMatch()
    {
        Assert.Equal("S9", MetadataPillStyle.SeasonText(9));
        Assert.Equal("Season 9", MetadataPillStyle.SeasonAnnouncement(9, false));
        Assert.Equal("Current season 12", MetadataPillStyle.SeasonAnnouncement(12, true));
        Assert.True(MetadataPillStyle.IsCurrent(12, 12));
        Assert.False(MetadataPillStyle.IsCurrent(11, 12));
        Assert.False(MetadataPillStyle.IsCurrent(12, null));
        Assert.False(MetadataPillStyle.IsCurrent(null, null));
        Assert.False(MetadataPillStyle.IsCurrent(0, 0));
    }

    [Fact]
    public void SeasonLook_CurrentSeasonIsTheInvertedRole()
    {
        var older = MetadataPillStyle.Season(false);
        var current = MetadataPillStyle.Season(true);
        Assert.Equal(("FSTSeasonPillFillBrush", "FSTSeasonPillStrokeBrush", "FSTSeasonPillTextBrush"), (older.FillKey, older.StrokeKey, older.TextKey));
        Assert.Equal(("FSTCurrentSeasonFillBrush", "FSTCurrentSeasonStrokeBrush", "FSTCurrentSeasonTextBrush"), (current.FillKey, current.StrokeKey, current.TextKey));
        Assert.False(older.Bold || older.Italic || older.Skewed);
        Assert.False(current.Bold || current.Italic || current.Skewed);
    }

    [Fact]
    public void PercentileLook_FollowsTheWebTiers()
    {
        var one = MetadataPillStyle.Percentile(SongPercentileTier.TopOne);
        Assert.Equal(("FSTGoldPillFillBrush", "FSTEmphasisStrokeBrush", "FSTEmphasisBrush"), (one.FillKey, one.StrokeKey, one.TextKey));
        Assert.True(one.Bold && one.Italic && one.Skewed);
        var five = MetadataPillStyle.Percentile(SongPercentileTier.TopFive);
        Assert.Equal(("FSTGoldPillFillBrush", "FSTEmphasisStrokeBrush", "FSTEmphasisBrush"), (five.FillKey, five.StrokeKey, five.TextKey));
        Assert.True(five.Bold);
        Assert.False(five.Italic || five.Skewed);
        var ordinary = MetadataPillStyle.Percentile(SongPercentileTier.Ordinary);
        Assert.Equal("FSTPercentileNeutralFillBrush", ordinary.FillKey);
        Assert.Equal("FSTPercentileNeutralTextBrush", ordinary.TextKey);
        Assert.False(ordinary.Bold || ordinary.Italic || ordinary.Skewed);
        Assert.True(MetadataPillStyle.Percentile(SongPercentileTier.Ordinary, bold: true).Bold);
    }

    [Fact]
    public void FullComboLook_IsTheWebGoldOutlineSkew()
    {
        // Issue #644: web AccuracyDisplay fcBadge is goldOutlineSkew, the same look as the Top 1% pill.
        var fc = MetadataPillStyle.FullCombo;
        Assert.Equal(("FSTGoldPillFillBrush", "FSTEmphasisStrokeBrush", "FSTEmphasisBrush"), (fc.FillKey, fc.StrokeKey, fc.TextKey));
        Assert.True(fc.Bold && fc.Italic && fc.Skewed);
        Assert.Equal(52.5, MetadataPillStyle.AccuracyMinWidth); // web accuracyPillMinWidth 3.75em
        Assert.Equal(MetadataPillStyle.Height, MetadataPillStyle.StarCircle); // stars line up with the pills
    }

    [Fact]
    public void FirstRunMetadataDemo_FullComboShowsThePercentOnly()
    {
        var sample = new FirstRunDemoMetadata(142_800, 1_000_000, true, 6, "Top 1%", 11, 3);
        Assert.Equal(["142,800", "100%"], FirstRunDemos.MetadataPillsFor(sample, FirstRunDemoMetadataLayout.ScoreAccuracy));
    }

    [Theory]
    [InlineData(PercentileTier.Top5, SongPercentileTier.TopFive)]
    [InlineData(PercentileTier.Default, SongPercentileTier.Ordinary)]
    public void SuggestionTier_MapsOntoTheSharedTier(PercentileTier tier, SongPercentileTier expected) =>
        Assert.Equal(expected, MetadataPillStyle.Tier(tier));

    [Fact]
    public void SeasonWidth_IsAtLeastTheMinimumAndGrowsWithTheLabel()
    {
        Assert.Equal(48, MetadataPillStyle.SeasonWidth(3, 8.5));
        Assert.Equal(48, MetadataPillStyle.SeasonWidth(0, 8.5));
        Assert.Equal(55, MetadataPillStyle.SeasonWidth(5, 8.5)); // ceil(42.5) + 12
    }

    [Fact]
    public void ScoreRows_ExposeTheSeasonNumberBehindTheirLabel()
    {
        ILeaderboardScoreRow preview = new LeaderboardRow(new LeaderboardEntry { AccountId = "a", Season = 12 });
        Assert.Equal(("S12", 12), (preview.Season, preview.SeasonNumber));
        ILeaderboardScoreRow none = new LeaderboardRow(new LeaderboardEntry { AccountId = "b" });
        Assert.Equal(("", (int?)null), (none.Season, none.SeasonNumber));
        ILeaderboardScoreRow board = new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "c", Season = 7 }, false);
        Assert.Equal(7, board.SeasonNumber);
        var point = new ScoreHistoryPoint(new ScoreHistoryEntry { NewScore = 1, Season = 4, ChangedAt = "x" }, DateTimeOffset.UnixEpoch);
        Assert.Equal(4, ((ILeaderboardScoreRow)new ScoreHistoryListRow(point, false)).SeasonNumber);
        ILeaderboardScoreRow band = new SongBandSpotlightRow(new SongBandLeaderboardEntry { TeamKey = "x:y", BandType = "Band_Duets", Rank = 1, Season = 11 });
        Assert.Equal(("S11", 11), (band.Season, band.SeasonNumber));
    }

    [Fact]
    public void SuggestionSeasonRows_CarryTheSeasonNumber()
    {
        var song = new Song { SongId = "s1", Title = "T", Artist = "A" };
        var category = new SuggestionCategory("stale_global", "Stale", "", SuggestionCategoryType.Stale, null, []);
        var item = new SuggestionSongItem { Song = song, Instrument = Instrument.Lead };
        var scores = new Dictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>>
        {
            ["s1"] = new Dictionary<Instrument, SuggestionScore> { [Instrument.Lead] = new SuggestionScore(1, Season: 6) },
        };
        var row = SuggestionRowPresentation.Create(category, item, scores, []);
        Assert.Equal(("S6", 6), (row.SeasonText, row.SeasonNumber));
    }

    [Fact]
    public void FirstRunMetadataDemo_UsesTheSharedSeasonLabel()
    {
        var sample = new FirstRunDemoMetadata(142_800, 960_000, false, 5, "Top 8%", 11, 3);
        Assert.Equal(["Top 8%", "S11"], FirstRunDemos.MetadataPillsFor(sample, FirstRunDemoMetadataLayout.PercentileSeason));
    }

    [Theory]
    [InlineData("Rank 1, Ada, 99,900 points, season 9, you", 9, 9, "Rank 1, Ada, 99,900 points, current season 9, you")]
    [InlineData("Jan 4, 2024, score 850,000, season 40", 40, 40, "Jan 4, 2024, score 850,000, current season 40")]
    [InlineData("Jan 4, 2024, score 850,000, season 40", 4, 4, "Jan 4, 2024, score 850,000, season 40")]
    [InlineData("Rank 1, Ada, season 9, you", 9, 10, "Rank 1, Ada, season 9, you")]
    [InlineData("Rank 1, Ada, season 9, you", 9, null, "Rank 1, Ada, season 9, you")]
    public void WithCurrentSeason_SpeaksTheInvertedPill(string name, int season, int? current, string expected) =>
        Assert.Equal(expected, MetadataPillStyle.WithCurrentSeason(name, season, current));

    [Theory]
    [InlineData(0.004, SongPercentileTier.TopOne)]
    [InlineData(0.01, SongPercentileTier.TopOne)]
    [InlineData(0.0104, SongPercentileTier.TopOne)] // shown "Top 1%"
    [InlineData(0.016, SongPercentileTier.TopFive)] // shown "Top 2%"
    [InlineData(0.054, SongPercentileTier.TopFive)] // shown "Top 5%"
    [InlineData(0.056, SongPercentileTier.Ordinary)] // shown "Top 6%"
    [InlineData(0.5, SongPercentileTier.Ordinary)]
    [InlineData(double.NaN, SongPercentileTier.Ordinary)]
    public void TierOf_FollowsTheShownLabel(double raw, SongPercentileTier expected) =>
        Assert.Equal(expected, MetadataPillStyle.TierOf(raw));

    [Fact]
    public void BandDetailSongRows_UseThePercentilePillTier()
    {
        var row = new BandSongRow(new Festival.Core.Data.BandSongPerformance { SongId = "s", Percentile = 0.04 }, null);
        Assert.Equal("Top 4%", row.PercentileText);
        Assert.Equal(SongPercentileTier.TopFive, row.PercentileTier);
    }
}
