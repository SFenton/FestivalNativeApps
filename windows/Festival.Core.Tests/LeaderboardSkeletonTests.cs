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
        Assert.Equal(LeaderboardRowMetrics.SkeletonSection(band.Metric.ToRankingMetric(), LeaderboardRowMetrics.BandNameLines(band.BandType.MemberCount())),
            band.SkeletonRows[0].Section);
    }

    [Fact]
    public void NameBudgetIsTwoLinesForPlayersOnePerBandMemberAndOneForLabels()
    {
        // Issue #455 (R2): at 150%+ text names wrap, and every row of a section reserves the same lines.
        Assert.Equal(2, LeaderboardRowMetrics.PlayerNameLines);
        Assert.Equal(1, LeaderboardRowMetrics.LabelNameLines);
        Assert.Equal([2, 3, 4], BandTypeInfo.All.Select(t => LeaderboardRowMetrics.BandNameLines(t.MemberCount())));
        Assert.Equal(2, LeaderboardRowMetrics.BandNameLines(1));
        Assert.Equal(2, LeaderboardRowMetrics.SkeletonSection(RankingMetric.TotalScore).NameLines);
        Assert.Equal(4, LeaderboardRowMetrics.SkeletonSection(RankingMetric.TotalScore, 4).NameLines);
        Assert.Equal(2, LeaderboardColumns.Measure([]).NameLines);
    }

    [Fact]
    public void PlayerRowsPinnedRowAndSkeletonShareTheNameBudget()
    {
        var visible = new[] { RankingsWire.Account(1, "a"), RankingsWire.Account(2, "b") };
        var rows = visible.Select(e => new RankingRowViewModel(e, RankingMetric.TotalScore, false)).ToList();
        var pinned = new RankingRowViewModel(RankingsWire.Account(40, "me"), RankingMetric.TotalScore, true);
        RankingRowViewModel.ShareColumns(rows, pinned);
        Assert.All(rows, r => Assert.Equal(LeaderboardRowMetrics.PlayerNameLines, r.Section!.NameLines));
        Assert.Equal(rows[0].Section!.NameLines, pinned.Section!.NameLines);
        Assert.Equal(rows[0].Section!.NameLines, LeaderboardRowMetrics.SkeletonRows(RankingMetric.TotalScore, "p")[0].LargeTextNameLines);

        var spotlight = new RankingSpotlightViewModel(Instrument.Lead, null, new FakeTimeProvider(), "t");
        spotlight.Apply("me", visible, RankingMetric.TotalScore);
        Assert.Equal(LeaderboardRowMetrics.PlayerNameLines, spotlight.LoadingRow!.Section!.NameLines);
    }

    [Theory]
    [InlineData(BandType.Duets, "Band_Duets", 2)]
    [InlineData(BandType.Trios, "Band_Trios", 3)]
    [InlineData(BandType.Quad, "Band_Quad", 4)]
    public void BandRowsReserveOneNameLinePerMember(BandType bandType, string serviceId, int lines)
    {
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.BandBoard(serviceId, 1, 25, 30, [1, 12])),
            RankingsJsonContext.Default.BandRankingsResponse);
        var rows = board.Entries.Select(e => new BandRankingRowViewModel(e, bandType, BandRankingMetric.TotalScore)).ToList();
        BandRankingRowViewModel.ShareColumns(rows);
        Assert.All(rows, r => Assert.Equal(lines, r.Section!.NameLines));
    }

    [Fact]
    public void SectionReservesTheMostLinesAnyRowAsksFor()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var point = new ScoreHistoryPoint(new ScoreHistoryEntry { NewScore = 5000, Season = 4, ChangedAt = "x" },
            new DateTimeOffset(2026, 3, 30, 12, 5, 9, TimeSpan.Zero));
        // Date-labelled history rows reserve one line; a placeholder in a band section carries its section's budget.
        Assert.Equal(1, LeaderboardColumns.Measure([new ScoreHistoryListRow(point, true)]).NameLines);
        var quad = LeaderboardRowMetrics.SkeletonRows(RankingMetric.TotalScore, "q", 4)[0];
        Assert.Equal(4, LeaderboardColumns.Measure([LeaderboardRowMetrics.SkeletonRows(RankingMetric.TotalScore, "p")[0], quad]).NameLines);
    }
}
