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
        Assert.False(narrow.MetaBelowName || wide.MetaBelowName);
    }

    [Fact]
    public void LargeTextRankingRows_MoveTheSongsLabelUnderTheName()
    {
        // Issue #208: Full Rankings at 200% text in a ~470 epx row left the name an ellipsis; the label moves under it.
        var rankings = new LeaderboardSection(LeaderboardRowKind.Ranking, RankChars: 3, MetaChars: 7, ValueChars: 10, HasAccuracy: false, HasStars: false);
        var squeezed = LeaderboardColumnLayout.Fit(rankings, 560, 2);
        Assert.Equal((false, 0d, true, false), (squeezed.ShowMeta, squeezed.MetaWidth, squeezed.MetaBelowName, squeezed.ValueBelowName));
        // Live Pro Lead "#1,450" with "38,267,723" at 200% in a ~470 epx row: still no room, so the row stacks.
        var stacked = LeaderboardColumnLayout.Fit(rankings with { RankChars = 6 }, 470, 2);
        Assert.Equal((true, true), (stacked.MetaBelowName, stacked.ValueBelowName));
        Assert.True(LeaderboardColumnLayout.Fit(rankings with { MetaChars = 0 }, 470, 2).ValueBelowName);
        var roomy = LeaderboardColumnLayout.Fit(rankings, 1200, 2);
        Assert.Equal((true, 98d, false, false), (roomy.ShowMeta, roomy.MetaWidth, roomy.MetaBelowName, roomy.ValueBelowName));
        // Before the first layout nothing moves; score rows drop the season instead.
        Assert.False(LeaderboardColumnLayout.Fit(rankings, double.NaN, 2).MetaBelowName);
        Assert.False(LeaderboardColumnLayout.Fit(rankings, double.NaN, 2).ValueBelowName);
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 470, 2).MetaBelowName);
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 300, 2).ValueBelowName);
        Assert.False(LeaderboardColumnLayout.Fit(rankings with { MetaChars = 0 }, 470, 2).MetaBelowName);
    }

    [Fact]
    public void LargeTextRankings_MoveTheSongsLabelUnderTheNameOnlyWhenTheNameWouldVanish()
    {
        // Issue #209: Band Rankings at 200% text in a 469 epx row. "#1", "29 / 50", "49,500,000": padding 24 + rank 56 +
        // songs 98 + rating 190 + chevron 24 + gaps 72 + name 144 = 608 epx, so the songs label moves under the name
        // (issue #208's placement; it is never dropped).
        var bands = new LeaderboardSection(LeaderboardRowKind.Ranking, RankChars: 2, MetaChars: 7, ValueChars: 10, HasAccuracy: false, HasStars: false);
        var squeezed = LeaderboardColumnLayout.Fit(bands, 469, 2);
        Assert.Equal((false, 0d, true), (squeezed.ShowMeta, squeezed.MetaWidth, squeezed.MetaBelowName));
        Assert.True(LeaderboardColumnLayout.Fit(bands, 469).ShowMeta);
        Assert.True(LeaderboardColumnLayout.Fit(bands, 608, 2).ShowMeta);
        Assert.True(LeaderboardColumnLayout.Fit(bands, 607, 2).MetaBelowName);
        Assert.True(LeaderboardColumnLayout.Fit(bands, double.NaN, 2).ShowMeta);
        // A section where no band opens frees the chevron's 24 epx: the label keeps its column down to 584 epx.
        var unrouted = bands with { HasRoutes = false };
        Assert.Equal((true, false), (LeaderboardColumnLayout.Fit(unrouted, 584, 2).ShowMeta, LeaderboardColumnLayout.Fit(unrouted, 584, 2).ShowChevron));
        Assert.True(LeaderboardColumnLayout.Fit(unrouted, 583, 2).MetaBelowName);
    }

    [Fact]
    public void LabelledRows_HaveNoRankColumn()
    {
        Assert.Equal(0, LeaderboardColumnLayout.Fit(Scores with { RankChars = 0 }, 600).RankWidth);
    }

    [Fact]
    public void LargeTextInANarrowRow_StacksTheValuesUnderTheName()
    {
        // Issue #207: Leaderboards at 200% text in a compact window (~470 epx rows). "#1", "39 / 50", "89,000,000"
        // need 24 + 56 + 98 + 190 + 24 + 72 + 144 = 608 epx, so the name used to get no width at all. Rankings rows use
        // the issue #208 placement (label, then rating, under the name) and never set the score-row flags.
        var rankings = new LeaderboardSection(LeaderboardRowKind.Ranking, RankChars: 2, MetaChars: 7, ValueChars: 10, HasAccuracy: false, HasStars: false);
        var ranked = LeaderboardColumnLayout.Fit(rankings, 470, 2);
        Assert.Equal((true, true, false, false), (ranked.MetaBelowName, ranked.ValueBelowName, ranked.Stacked, ranked.SplitValues));
        Assert.False(LeaderboardColumnLayout.Fit(rankings, 608, 2).MetaBelowName);
        Assert.True(LeaderboardColumnLayout.Fit(rankings, 607, 2).MetaBelowName);
        // Score rows drop stars and the season first and stack only when that is still not enough:
        // 24 + 76.5 + 182.25 + 130.5 + 27 + 72 + 162 = 674.25 epx at 225%.
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 720, 2.25).Stacked);
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 675, 2.25).Stacked);
        Assert.True(LeaderboardColumnLayout.Fit(Scores, 674, 2.25).Stacked);
        var squeezed = LeaderboardColumnLayout.Fit(Scores, 470, 2.25);
        Assert.Equal((false, false, true), (squeezed.ShowMeta, squeezed.ShowStars, squeezed.Stacked));
        Assert.False(squeezed.SplitValues); // no season to split from
        Assert.False(squeezed.MetaBelowName || squeezed.ValueBelowName);
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 470).Stacked);
        // A pinned season (Score History detail) goes under the name too, and splits from the score when both don't
        // fit side by side: 470 - 24 - 76.5 - 4 × 12 - 130.5 - 27 = 164 < 58.5 + 12 + 182.25.
        var pinned = LeaderboardColumnLayout.Fit(Scores, 470, 2.25, pinSeason: true);
        Assert.Equal((true, true, true), (pinned.ShowMeta, pinned.Stacked, pinned.SplitValues));
        // 300 - 24 - 34 - 4 × 8 - 58 - 12 = 140 ≥ 26 + 8 + 81: stacked on two lines only.
        var twoLines = LeaderboardColumnLayout.Fit(Scores, 300, 1, pinSeason: true);
        Assert.Equal((true, false), (twoLines.Stacked, twoLines.SplitValues));
        Assert.False(LeaderboardColumnLayout.Fit(Scores, 1200, 2, pinSeason: true).SplitValues); // only stacked rows split
        // Unmeasured rows never stack.
        Assert.False(LeaderboardColumnLayout.Fit(Scores, double.NaN, 2.25).Stacked);
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
