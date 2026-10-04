using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Issue #37: one per-section column plan decides which leaderboard columns fit and their shared widths.</summary>
public class LeaderboardColumnLayoutTests
{
    private static readonly LeaderboardSection Scores = new(LeaderboardRowKind.Score, RankChars: 4, MetaChars: 3, ValueChars: 9, HasAccuracy: true, HasStars: true);

    [Fact]
    public void NarrowScoreRow_TightensGapsAndHidesSeasonAndStarsButReservesAccuracy()
    {
        var plan = LeaderboardColumnLayout.Fit(Scores, 360);
        Assert.True(plan.Compact);
        Assert.Equal(8, plan.Gap);
        Assert.Equal(34, plan.RankWidth); // ceil(4 × 8.5)
        Assert.Equal(81, plan.ValueWidth); // 9 × 9
        Assert.False(plan.ShowMeta);
        Assert.Equal(0, plan.MetaWidth);
        Assert.True(plan.ShowAccuracy);
        Assert.Equal(58, plan.AccuracyWidth);
        Assert.False(plan.ShowStars);
        Assert.Equal(0, plan.StarsWidth);
    }

    [Fact]
    public void PinnedSeason_ShowsAtAnyWidthAndIsNeverDroppedForSpace()
    {
        // Issue #62: the Score History detail row always shows the season (web renderDetailCard).
        foreach (var width in new[] { double.NaN, 0, 280, 360, 519 })
        {
            var plan = LeaderboardColumnLayout.Fit(Scores, width, pinSeason: true);
            Assert.True(plan.ShowMeta);
            Assert.Equal(26, plan.MetaWidth);
        }
        Assert.True(LeaderboardColumnLayout.Fit(Scores, 360, textScale: 2.25, pinSeason: true).ShowMeta);
        var noSeason = Scores with { MetaChars = 0 };
        Assert.False(LeaderboardColumnLayout.Fit(noSeason, 360, pinSeason: true).ShowMeta);
        var rankings = new LeaderboardSection(LeaderboardRowKind.Ranking, 4, 7, 6, false, false);
        Assert.Equal(LeaderboardColumnLayout.Fit(rankings, 360), LeaderboardColumnLayout.Fit(rankings, 360, pinSeason: true));
    }

    [Fact]
    public void MediumScoreRow_ShowsSeasonFrom520()
    {
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 519).ShowMeta);
        var plan = LeaderboardColumnLayout.Fit(Scores, 520);
        Assert.False(plan.Compact);
        Assert.Equal(12, plan.Gap);
        Assert.True(plan.ShowMeta);
        Assert.Equal(26, plan.MetaWidth); // ceil(3 × 8.5)
        Assert.False(plan.ShowStars);
    }

    [Fact]
    public void WideScoreRow_ShowsEveryColumnFrom700()
    {
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 699).ShowStars);
        var plan = LeaderboardColumnLayout.Fit(Scores, 900);
        Assert.Equal((true, true, true), (plan.ShowMeta, plan.ShowAccuracy, plan.ShowStars));
        Assert.Equal(LeaderboardColumnLayout.StarsWidth, plan.StarsWidth);
    }

    [Fact]
    public void UnmeasuredRow_ShowsNoOptionalColumns()
    {
        var plan = LeaderboardColumnLayout.Fit(Scores, double.NaN);
        Assert.Equal((false, false, true, 12d), (plan.ShowMeta, plan.ShowStars, plan.ShowAccuracy, plan.Gap));
    }

    [Fact]
    public void SectionWithoutValues_ReservesNothingForThem()
    {
        var bare = Scores with { MetaChars = 0, HasAccuracy = false, HasStars = false };
        var plan = LeaderboardColumnLayout.Fit(bare, 1200);
        Assert.Equal((false, false, false), (plan.ShowMeta, plan.ShowAccuracy, plan.ShowStars));
        Assert.Equal((0d, 0d, 0d), (plan.MetaWidth, plan.AccuracyWidth, plan.StarsWidth));
    }

    [Fact]
    public void LargeText_DropsStarsThenSeasonUntilTheNameFits()
    {
        // 225% text at 720 epx: everything needs ~831 epx, without stars ~733, without the season too ~674.
        var squeezed = LeaderboardColumnLayout.Fit(Scores, 720, 2.25);
        Assert.Equal((false, false, true), (squeezed.ShowMeta, squeezed.ShowStars, squeezed.ShowAccuracy));
        Assert.Equal(76.5, squeezed.RankWidth);
        // 780 epx: dropping stars is enough.
        var partial = LeaderboardColumnLayout.Fit(Scores, 780, 2.25);
        Assert.Equal((true, false), (partial.ShowMeta, partial.ShowStars));
        // Wide enough for everything at the same text size.
        var roomy = LeaderboardColumnLayout.Fit(Scores, 1000, 2.25);
        Assert.Equal((true, true), (roomy.ShowMeta, roomy.ShowStars));
        Assert.Equal(58 * 2.25, roomy.AccuracyWidth);
    }

    [Fact]
    public void RankingRows_AlwaysKeepTheSongsLabelAndNeverReserveBadgeOrStars()
    {
        var rankings = new LeaderboardSection(LeaderboardRowKind.Ranking, RankChars: 2, MetaChars: 9, ValueChars: 6, HasAccuracy: true, HasStars: true);
        var narrow = LeaderboardColumnLayout.Fit(rankings, 320);
        Assert.True(narrow.ShowMeta);
        Assert.Equal(63, narrow.MetaWidth); // 9 × 7
        Assert.Equal(57, narrow.ValueWidth); // 6 × 9.5
        Assert.Equal(28, narrow.RankWidth); // "#1" gets the minimum
        Assert.Equal((false, false), (narrow.ShowAccuracy, narrow.ShowStars));
        var wide = LeaderboardColumnLayout.Fit(rankings, 1200);
        Assert.Equal((true, false, false), (wide.ShowMeta, wide.ShowAccuracy, wide.ShowStars));
        Assert.Equal(narrow.MetaWidth, wide.MetaWidth);
    }

    [Fact]
    public void LargeTextRankings_DropTheSongsLabelOnlyWhenTheNameWouldVanish()
    {
        // Issue #209: Band Rankings at 200% text in a 469 epx row. "#1", "29 / 50", "49,500,000": padding 24 + rank 56 +
        // songs 98 + rating 190 + chevron 24 + gaps 72 + name 144 = 608 epx, so the songs label yields.
        var bands = new LeaderboardSection(LeaderboardRowKind.Ranking, RankChars: 2, MetaChars: 7, ValueChars: 10, HasAccuracy: false, HasStars: false);
        var squeezed = LeaderboardColumnLayout.Fit(bands, 469, 2);
        Assert.Equal((false, 0d), (squeezed.ShowMeta, squeezed.MetaWidth));
        Assert.True(LeaderboardColumnLayout.Fit(bands, 469).ShowMeta);
        Assert.True(LeaderboardColumnLayout.Fit(bands, 608, 2).ShowMeta);
        Assert.False(LeaderboardColumnLayout.Fit(bands, 607, 2).ShowMeta);
        Assert.True(LeaderboardColumnLayout.Fit(bands, double.NaN, 2).ShowMeta);
    }

    [Fact]
    public void LabelledRows_HaveNoRankColumn()
    {
        Assert.Equal(0, LeaderboardColumnLayout.Fit(Scores with { RankChars = 0 }, 600).RankWidth);
    }

    [Fact]
    public void Measure_CoversEveryRowAndThePinnedRow()
    {
        System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
        var rows = new List<ILeaderboardEntryRow>
        {
            new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "a", Rank = 1, Score = 100, Season = 9 }, false),
            new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "b", Rank = 2, Score = 99, Accuracy = 990000, Stars = 0 }, false),
            // Pinned row far down the board widens the shared rank, score and season columns.
            new SongLeaderboardRowViewModel(new LeaderboardEntry { AccountId = "me", Rank = 1234, Score = 1_234_567, Season = 12, Stars = 6 }, true),
        };
        var section = LeaderboardColumns.Measure(rows);
        Assert.Equal(new LeaderboardSection(LeaderboardRowKind.Score, 6, 3, 9, true, true), section);
        // Out-of-range stars draw nothing, so they reserve no column.
        var unstarred = LeaderboardColumns.Measure(rows.Take(2));
        Assert.False(unstarred.HasStars);
        Assert.Equal(LeaderboardRowKind.Ranking,
            LeaderboardColumns.Measure([new RankingRowViewModel(RankingsWire.Account(7, "x"), RankingMetric.TotalScore, false)]).Kind);
        Assert.Equal(LeaderboardRowKind.Score, LeaderboardColumns.Measure([]).Kind);
    }

    [Fact]
    public void UnopenableRow_KeepsTheChevronSlotWhileAnyRowOpens()
    {
        // Issue #209: a band without a team key sits beside openable bands; its values must stay in line with theirs.
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.BandBoard("Band_Duets", 1, 25, 2, [1, 2])),
            RankingsJsonContext.Default.BandRankingsResponse);
        var open = new BandRankingRowViewModel(board.Entries[0], BandType.Duets, BandRankingMetric.TotalScore);
        var closed = new BandRankingRowViewModel(board.Entries[1] with { BandId = "", TeamKey = "" }, BandType.Duets, BandRankingMetric.TotalScore);
        Assert.NotNull(open.Route);
        Assert.Null(closed.Route);
        var mixed = LeaderboardColumns.Measure([open, closed]);
        Assert.True(mixed.HasRoutes);
        Assert.True(LeaderboardColumnLayout.Fit(mixed, 600).ShowChevron);
        var none = LeaderboardColumns.Measure([closed]);
        Assert.False(none.HasRoutes);
        Assert.False(LeaderboardColumnLayout.Fit(none, 600).ShowChevron);
        Assert.True(LeaderboardColumns.Measure([]).HasRoutes);
    }

    [Fact]
    public void SectionWithoutDestinations_GivesTheChevronSpaceToOptionalColumns()
    {
        // 225% text, no season: padding 24 + rank 76.5 + score 182.25 + badge 130.5 + stars 98 + gaps 72 + name 162
        // = 745.25 epx, plus the chevron's 27 = 772.25. At 760 epx only a section without destinations keeps its stars.
        var stars = Scores with { MetaChars = 0 };
        var routed = LeaderboardColumnLayout.Fit(stars, 760, 2.25);
        Assert.Equal((false, true), (routed.ShowStars, routed.ShowChevron));
        var bare = LeaderboardColumnLayout.Fit(stars with { HasRoutes = false }, 760, 2.25);
        Assert.Equal((true, false), (bare.ShowStars, bare.ShowChevron));
    }
}
