using System.Globalization;
using Festival.Core.Domain;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

/// <summary>Loading placeholder rows fitted like loaded rows (issue #281, <c>leaderboard-row</c> R2).</summary>
public sealed class LeaderboardSkeletonTests
{
    public LeaderboardSkeletonTests() => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");

    [Theory]
    [InlineData(RankingMetric.TotalScore, 11)]
    [InlineData(RankingMetric.Adjusted, 9)]
    [InlineData(RankingMetric.Weighted, 9)]
    [InlineData(RankingMetric.FcRate, 6)]
    [InlineData(RankingMetric.MaxScore, 6)]
    public void SkeletonSectionUsesTheWidestTopTenContentForTheMetric(RankingMetric metric, int valueChars)
    {
        // "#10", "999 / 999" and "999,999,999" / "Top 0.99%" / "100.0%": a top-ten board's widest plausible values.
        Assert.Equal(new LeaderboardSection(LeaderboardRowKind.Ranking, 3, 9, valueChars, false, false),
            LeaderboardRowMetrics.SkeletonSection(metric));
    }

    [Theory]
    [InlineData(RankingMetric.TotalScore, false)]
    [InlineData(RankingMetric.Adjusted, true)]
    [InlineData(RankingMetric.Weighted, true)]
    [InlineData(RankingMetric.FcRate, false)]
    public void SkeletonRowsAreFivePlaceholdersSharingOneSection(RankingMetric metric, bool percentile)
    {
        var rows = LeaderboardRowMetrics.SkeletonRows(metric, "fst.leaderboards.card.Solo_Bass");

        Assert.Equal(LeaderboardRowMetrics.SkeletonRowCount, rows.Count);
        Assert.Equal(Enumerable.Range(0, 5), rows.Select(r => r.Index));
        Assert.Equal(Enumerable.Range(0, 5).Select(i => $"fst.leaderboards.card.Solo_Bass.skeleton.{i}"), rows.Select(r => r.AutomationId));
        foreach (var row in rows)
        {
            Assert.Same(rows[0].Section, row.Section);
            Assert.Equal(LeaderboardRowMetrics.SkeletonSection(metric), row.Section);
            Assert.True(row.ShowBars);
            // A percentile board's rows carry a second (Bayesian) line; its placeholder must too, or it is a line short.
            Assert.Equal(percentile ? "0" : "", row.BayesianText);
            Assert.Equal("#0", row.RankText);
            Assert.Equal("\u00A0", row.Name);
            Assert.Equal("0", row.SongsText);
            Assert.Equal("0", row.RatingText);
            Assert.False(row.IsSelected);
            Assert.Null(row.Route);
            Assert.Equal("", row.Announcement);
        }
    }

    [Fact]
    public void SkeletonStacksAtLargeTextLikeLoadedRows()
    {
        var section = LeaderboardRowMetrics.SkeletonSection(RankingMetric.TotalScore);
        // Compact card (500 epx window): one line at 100% text, songs label under the name at 200%.
        var normal = LeaderboardColumnLayout.Fit(section, 452, 1.0);
        Assert.False(normal.MetaBelowName);
        Assert.False(normal.ValueBelowName);
        Assert.True(LeaderboardColumnLayout.Fit(section, 452, 2.0).MetaBelowName);
    }

    [Fact]
    public void SpotlightLoadingRowFitsTheBoardOrTheSkeletonWhenTheBoardIsEmpty()
    {
        var spotlight = new RankingSpotlightViewModel(Instrument.Lead, null, new FakeTimeProvider(), "t");
        Assert.Null(spotlight.LoadingRow);

        spotlight.Apply("me", [], RankingMetric.TotalScore);
        Assert.True(spotlight.ShowLoading);
        var empty = spotlight.LoadingRow!;
        Assert.Equal(LeaderboardRowMetrics.SkeletonSection(RankingMetric.TotalScore), empty.Section);
        Assert.False(empty.ShowBars);
        Assert.Equal("", empty.BayesianText);
        Assert.Equal("", empty.AutomationId);

        var visible = new[] { RankingsWire.Account(1, "a"), RankingsWire.Account(2, "b") };
        spotlight.Apply("me", visible, RankingMetric.Adjusted);
        var board = LeaderboardColumns.Measure(visible.Select(e => new RankingRowViewModel(e, RankingMetric.Adjusted, false)).ToList());
        Assert.Equal(board with { HasRoutes = true }, spotlight.LoadingRow!.Section);
        Assert.Equal("0", spotlight.LoadingRow.BayesianText);
    }

    [Fact]
    public async Task CardsExposeSkeletonRowsForTheirMetric()
    {
        var fake = new RankingsFake();
        var session = fake.Session(new AppSettings { VisibleInstruments = [Instrument.Lead] });
        var vm = new LeaderboardsViewModel(session, new FakeReader().Read);
        await vm.ActivateAsync();

        var lead = vm.InstrumentCards[0];
        Assert.Equal(5, lead.SkeletonRows.Count);
        Assert.Equal(lead.AutomationId + ".skeleton.0", lead.SkeletonRows[0].AutomationId);
        Assert.Equal(LeaderboardRowMetrics.SkeletonSection(lead.Metric), lead.SkeletonRows[0].Section);
        var band = vm.BandCards[0];
        Assert.Equal(5, band.SkeletonRows.Count);
        Assert.Equal(band.AutomationId + ".skeleton.4", band.SkeletonRows[4].AutomationId);
        Assert.Equal(LeaderboardRowMetrics.SkeletonSection(band.Metric.ToRankingMetric()), band.SkeletonRows[0].Section);
    }
}
