using System.Globalization;
using Festival.Core.Data;
using Festival.Core.Domain;
using Festival.Core.ViewModels;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Score-accuracy control policy (<c>.agents/controls/score-accuracy/spec.md</c>): text, tint, badge and spoken form.</summary>
public sealed class ScoreAccuracyTests
{
    public ScoreAccuracyTests() => CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

    [Theory]
    [InlineData(0d, 220, 40, 40)]
    [InlineData(500_000d, 133, 122, 77)]
    [InlineData(980_000d, 49, 201, 112)]
    [InlineData(1_000_000d, 46, 204, 113)]
    [InlineData(-10_000d, 220, 40, 40)]
    [InlineData(1_050_000d, 46, 204, 113)]
    [InlineData(double.NaN, 220, 40, 40)]
    [InlineData(double.PositiveInfinity, 220, 40, 40)]
    public void Tint_MatchesWebEndpointsAndClampsColourOnly(double accuracy, int r, int g, int b)
    {
        var tint = ScoreFormatting.AccuracyTint(accuracy);
        Assert.Equal((r, g, b), ((int)tint.R, (int)tint.G, (int)tint.B));
    }

    [Theory]
    [InlineData(120_000d, "12%")]
    [InlineData(500_000d, "50%")]
    [InlineData(995_000d, "99.5%")]
    [InlineData(0d, "0%")]
    [InlineData(1_050_000d, "105%")]
    public void Accuracy_KeepsOutOfRangeNumbers(double accuracy, string expected) =>
        Assert.Equal(expected, ScoreFormatting.Accuracy(accuracy));

    [Fact]
    public void Accuracy_RejectsNonFinite()
    {
        Assert.Equal("", ScoreFormatting.Accuracy(double.PositiveInfinity));
        Assert.Equal("", ScoreFormatting.Accuracy(double.NegativeInfinity));
    }

    [Theory]
    [InlineData("98%", false, "98%")]
    [InlineData("98%", true, "98%")]
    [InlineData("", true, "FC")]
    [InlineData("", false, "")]
    public void BadgeText_NeverInventsZeroOrInfersFullCombo(string accuracy, bool fullCombo, string expected) =>
        Assert.Equal(expected, ScoreFormatting.BadgeText(accuracy, fullCombo));

    [Fact]
    public void FullComboAnnouncement_SaysWhenAccuracyIsUnavailable()
    {
        Assert.Equal("full combo", ScoreFormatting.FullComboAnnouncement(true));
        Assert.Equal("full combo, accuracy unavailable", ScoreFormatting.FullComboAnnouncement(false));
    }

    [Fact]
    public void FullChartRow_BadgeStatesAndIds()
    {
        ILeaderboardScoreRow graded = new SongLeaderboardRowViewModel(Entry("a", 1, 985_000, false), false);
        ILeaderboardScoreRow fc = new SongLeaderboardRowViewModel(Entry("b", 2, 1_000_000, true), false);
        ILeaderboardScoreRow fcNoAccuracy = new SongLeaderboardRowViewModel(Entry("c", 3, null, true), false);
        ILeaderboardScoreRow absent = new SongLeaderboardRowViewModel(Entry("d", 4, null, false), false);

        Assert.Equal(["98.5%", "100%", "FC", ""], new[] { graded, fc, fcNoAccuracy, absent }.Select(r => r.BadgeText));
        Assert.Equal("fst.score.accuracy.c", fcNoAccuracy.BadgeAutomationId);
        Assert.Equal("Rank #3, Player c, 1,000 points, full combo, accuracy unavailable, 5 stars", fcNoAccuracy.Announcement);
        Assert.Equal("Rank #2, Player b, 1,000 points, 100% accuracy, full combo, 5 stars", fc.Announcement);
        Assert.Equal("Rank #4, Player d, 1,000 points, 5 stars", absent.Announcement);
    }

    [Fact]
    public void PreviewRow_BadgeIdIsUniquePerChartCard()
    {
        ILeaderboardScoreRow lead = new LeaderboardRow(Entry("p", 1, null, true)) { InstrumentId = "Solo_Guitar" };
        ILeaderboardScoreRow bass = new LeaderboardRow(Entry("p", 1, null, true)) { InstrumentId = "Solo_Bass" };
        ILeaderboardScoreRow anonymous = new LeaderboardRow(Entry("", 7, 990_000, false)) { InstrumentId = "Solo_Bass" };

        Assert.Equal("FC", lead.BadgeText);
        Assert.Equal("fst.score.accuracy.preview.Solo_Guitar.p", lead.BadgeAutomationId);
        Assert.NotEqual(lead.BadgeAutomationId, bass.BadgeAutomationId);
        Assert.Equal("fst.score.accuracy.preview.Solo_Bass.rank-7", anonymous.BadgeAutomationId);
        Assert.Equal("Rank 1, Player p, 1,000 points, full combo, accuracy unavailable", lead.Announcement);
    }

    [Fact]
    public void HistoryRow_BadgeIdFollowsDateAndDetail()
    {
        var point = new ScoreHistoryPoint(new ScoreHistoryEntry { NewScore = 5000, Accuracy = null, IsFullCombo = true, Season = 4, ChangedAt = "2024-05-06T07:08:09Z" },
            new DateTimeOffset(2024, 5, 6, 7, 8, 9, TimeSpan.Zero));
        ILeaderboardScoreRow row = new ScoreHistoryListRow(point, false);
        ILeaderboardScoreRow detail = new ScoreHistoryListRow(point, false) { IsDetail = true };

        Assert.Equal("FC", row.BadgeText);
        Assert.Equal("fst.score.accuracy.history.20240506070809", row.BadgeAutomationId);
        Assert.Equal("fst.score.accuracy.history.20240506070809.detail", detail.BadgeAutomationId);
        Assert.Contains("full combo, accuracy unavailable", row.Announcement);
    }

    [Fact]
    public void Measure_ReservesBadgeColumnForFullComboWithoutAccuracy()
    {
        var onlyFc = LeaderboardColumns.Measure([new SongLeaderboardRowViewModel(Entry("a", 1, null, true), false)]);
        var none = LeaderboardColumns.Measure([new SongLeaderboardRowViewModel(Entry("a", 1, null, false), false)]);

        Assert.True(onlyFc.HasAccuracy);
        Assert.False(none.HasAccuracy);
    }

    private static LeaderboardEntry Entry(string id, int rank, double? accuracy, bool fullCombo) => new()
    {
        AccountId = id, DisplayName = id.Length == 0 ? "" : "Player " + id, Rank = rank, Score = 1000,
        Accuracy = accuracy, IsFullCombo = fullCombo, Stars = 5, Season = 9,
    };
}
