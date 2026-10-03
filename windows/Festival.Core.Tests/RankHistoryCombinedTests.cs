using System.Globalization;
using Festival.Core.Data;
using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Combined Rank History chart: web colours, rank domain, value ticks and paging.</summary>
public sealed class RankHistoryCombinedTests
{
    private static PlayerRankHistorySnapshot Snap(int day, int rank, long? score = 1000, int? field = 100) => new()
    {
        SnapshotDate = $"2026-09-{day:00}", TotalScoreRank = rank, TotalScore = score, RankedAccountCount = field,
    };

    [Fact]
    public void Build_EmptyIsNull() => Assert.Null(RankHistoryCombinedChart.Build([]));

    [Fact]
    public void Build_WebAxisDatesColoursAndDomain()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var chart = RankHistoryCombinedChart.Build([Snap(1, 50), Snap(2, 10, field: null), Snap(3, 1)])!;
        Assert.Equal("9/1/26", chart.Points[0].AxisLabel);
        Assert.Equal("Sep 01, 2026".Replace("01", "1", StringComparison.Ordinal), chart.Points[0].DisplayDate);
        Assert.Equal(RankHistoryCombinedChart.RankColor(50, 100), chart.Points[0].BarArgb);
        Assert.Equal(RankHistoryCombinedChart.UnknownArgb, chart.Points[1].BarArgb);
        Assert.Equal((1, 55), (chart.Best, chart.Worst));
        var bad = RankHistoryCombinedChart.Build([new PlayerRankHistorySnapshot { SnapshotDate = "bad", TotalScoreRank = 3 }])!;
        Assert.Equal("bad", bad.Points[0].AxisLabel);
        Assert.Equal(0, bad.Points[0].Value);
    }

    [Fact]
    public void BuildBand_ChartsTheMetricValueAndRank()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Assert.Null(RankHistoryCombinedChart.BuildBand([], BandRankingMetric.Adjusted, 10));
        var entries = new List<BandRankHistoryEntry>
        {
            new() { SnapshotDate = "2026-09-01", AdjustedSkillRank = 40, AdjustedSkillRating = 1.25, TotalRankedTeams = 200 },
            new() { SnapshotDate = "2026-09-02", AdjustedSkillRank = 20, AdjustedSkillRating = 2.5, TotalRankedTeams = 200 },
        };
        var chart = RankHistoryCombinedChart.BuildBand(entries, BandRankingMetric.Adjusted, null)!;
        Assert.Equal("Adjusted", chart.MetricLabel.Split(' ')[0]);
        Assert.Equal([40, 20], chart.Points.Select(p => p.Rank));
        Assert.Equal([1.25, 2.5], chart.Points.Select(p => p.Value));
        Assert.Equal(RankHistoryCombinedChart.RankColor(20, 200), chart.Points[1].BarArgb);
        var page = chart.Page(10, 0);
        Assert.Equal(["2.50", "1.25", "0.00"], page.ValueTicks.Select(t => t.Label));
        Assert.Equal(0.5, page.Bars[0].Height, 3);
        Assert.Contains($"{chart.MetricLabel} 2.5", page.Summary, StringComparison.Ordinal);

        // The ranking's field size wins over the snapshots'; a bad date stays as sent.
        var fc = RankHistoryCombinedChart.BuildBand([new BandRankHistoryEntry { SnapshotDate = "x", FcRateRank = 5, FcRate = 0.5 }], BandRankingMetric.FcRate, 10)!;
        Assert.Equal(("x", RankHistoryCombinedChart.RankColor(5, 10)), (fc.Points[0].AxisLabel, fc.Points[0].BarArgb));
        Assert.Equal("50%", fc.Page(3, 0).ValueTicks[0].Label);
        Assert.Contains("50%", fc.Page(3, 0).Summary, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(0.5, RankingMetric.FcRate, "50%", "50%")]
    [InlineData(0.9875, RankingMetric.MaxScore, "99%", "98.8%")]
    [InlineData(1.234, RankingMetric.Adjusted, "1.23", "1.2")]
    [InlineData(3.0, RankingMetric.Weighted, "3.00", "3")]
    [InlineData(2_500_000, RankingMetric.TotalScore, "2.5M", "2,500,000")]
    public void MetricFormats_FollowTheWeb(double value, RankingMetric metric, string tick, string detail)
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Assert.Equal(tick, RankHistoryCombinedChart.MetricTick(value, metric));
        Assert.Equal(detail, RankHistoryCombinedChart.MetricDetail(value, metric));
    }

    [Theory]
    [InlineData(new[] { 10, 20 }, 9, 21)]
    [InlineData(new[] { 5 }, 4, 6)]
    [InlineData(new[] { 1, 101 }, 1, 111)]
    [InlineData(new int[0], 1, 100)]
    public void Domain_PadsTenPercent(int[] ranks, int best, int worst) =>
        Assert.Equal((best, worst), RankHistoryCombinedChart.Domain(ranks));

    [Fact]
    public void RankColor_RedToGreenByPlacement()
    {
        Assert.Equal(0xFFDC2828u, RankColor(100, 100)); // last place: rgb(220,40,40)
        Assert.Equal(0xFF30CA70u, RankColor(1, 100));   // 99th percentile: rgb(48,202,112)
        Assert.Equal(0xFF2ECC71u, RankColor(1, 1_000_000_000)); // clamps to rgb(46,204,113)
        Assert.Equal(RankHistoryCombinedChart.UnknownArgb, RankColor(0, 100));
        Assert.Equal(RankHistoryCombinedChart.UnknownArgb, RankColor(5, 0));
        Assert.Equal(RankHistoryCombinedChart.UnknownArgb, RankColor(-1, 100));
        static uint RankColor(int rank, int field) => RankHistoryCombinedChart.RankColor(rank, field);
    }

    [Theory]
    [InlineData(1_500_000_000, "1.5B")]
    [InlineData(2_000_000, "2M")]
    [InlineData(12_500, "12.5K")]
    [InlineData(999, "999")]
    [InlineData(-3_000, "-3K")]
    [InlineData(0, "0")]
    public void ValueTick_MatchesWebTotalScore(double value, string expected) =>
        Assert.Equal(expected, RankHistoryCombinedChart.ValueTick(value));

    [Theory]
    [InlineData(0, 1)]
    [InlineData(95, 1)]
    [InlineData(200, 2)]
    [InlineData(520, 5)]
    [InlineData(double.NaN, 1)]
    public void MaxBars_FitsWebBarWidth(double width, int bars) => Assert.Equal(bars, RankHistoryCombinedChart.MaxBars(width));

    [Theory]
    [InlineData(30, 52, 52)]       // 100% text: the design gutter
    [InlineData(46, 52, 52)]       // exactly fits with the 6 epx gap
    [InlineData(60.2, 52, 67)]     // 200% text: widest label + gap, rounded up
    [InlineData(-5, 48, 48)]
    [InlineData(double.NaN, 48, 48)]
    [InlineData(double.PositiveInfinity, 48, 48)]
    [InlineData(10, double.NaN, 16)]
    [InlineData(10, -4, 16)]
    public void AxisGutter_FitsScaledLabels(double label, double minimum, double gutter) =>
        Assert.Equal(gutter, RankHistoryCombinedChart.AxisGutter(label, minimum));

    [Fact]
    public void Page_NewestFirstAndClamped()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var chart = RankHistoryCombinedChart.Build(Enumerable.Range(1, 7).Select(d => Snap(d, 10 - d, score: d * 100)).ToList())!;
        var newest = chart.Page(3, 0);
        Assert.Equal(["9/5/26", "9/6/26", "9/7/26"], newest.Points.Select(p => p.AxisLabel));
        Assert.Equal(4, newest.MaxOffset);
        Assert.True(newest.CanOlder);
        Assert.False(newest.CanNewer);
        Assert.Equal([1.0 / 6, 0.5, 5.0 / 6], newest.Bars.Select(b => b.X));
        Assert.Equal(1, newest.Bars[^1].Height);
        Assert.True(newest.Line[^1].Highlight);
        Assert.False(newest.Line[0].Highlight);
        Assert.True(newest.Line[^1].Y < newest.Line[0].Y); // rank improves upward
        Assert.Equal(["#2", "#6", "#10"], newest.RankTicks.Select(t => t.Label));
        Assert.Equal(["700", "350", "0"], newest.ValueTicks.Select(t => t.Label));
        Assert.Equal("Sep 5, 2026 – Sep 7, 2026", newest.RangeText);
        Assert.StartsWith("Rank history, Sep 5, 2026 – Sep 7, 2026: Sep 5, 2026 rank #5, Total Score 500", newest.Summary);

        var oldest = chart.Page(3, 99);
        Assert.Equal(4, oldest.Offset);
        Assert.Equal(["9/1/26", "9/2/26", "9/3/26"], oldest.Points.Select(p => p.AxisLabel));
        Assert.False(oldest.CanOlder);
        Assert.True(oldest.CanNewer);
        Assert.DoesNotContain(oldest.Line, p => p.Highlight);

        var single = RankHistoryCombinedChart.Build([Snap(4, 3, score: null)])!.Page(0, -5);
        Assert.Equal("Sep 4, 2026", single.RangeText);
        Assert.Equal(0, single.Bars[0].Height);
        Assert.Equal(0.5, single.Bars[0].X);
        Assert.False(single.CanOlder || single.CanNewer);
    }

    [Fact]
    public void ProfileModel_CarriesTheCombinedChart()
    {
        var model = RankHistoryChartModel.Build([Snap(1, 4), Snap(2, 3)])!;
        Assert.NotNull(model.Combined);
        Assert.Equal(2, model.Combined!.Points.Count);
    }
}
