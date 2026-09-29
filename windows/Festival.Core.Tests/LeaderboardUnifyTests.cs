using System.Globalization;
using System.Windows.Input;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Operator batches 7.4/7.7: every board's rows and pagers go through one row contract and one pager contract.</summary>
public class LeaderboardUnifyTests
{
    [Fact]
    public void Widest_IsTheLongestRankOrZero()
    {
        Assert.Equal(0, LeaderboardColumns.Widest([]));
        Assert.Equal(6, LeaderboardColumns.Widest(["#1", "#1,234", "#99"]));
    }

    [Fact]
    public void BandRows_ShareOneRankWidthAndAreNeverSelected()
    {
        var board = FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(RankingsWire.BandBoard("Band_Duets", 1, 25, 30, [1, 12])),
            RankingsJsonContext.Default.BandRankingsResponse);
        var rows = board.Entries.Select(e => new BandRankingRowViewModel(e, BandType.Duets, BandRankingMetric.Weighted)).ToList();
        BandRankingRowViewModel.ShareRankWidth(rows);
        var chars = rows.Max(r => r.RankText.Length);
        Assert.All(rows, r => Assert.Equal(chars, r.RankChars));
        ILeaderboardRankingRow contract = rows[0];
        Assert.False(contract.IsSelected);
        Assert.Equal(rows[0].SongsText, contract.SongsText);
    }

    [Fact]
    public void RankingAndSongRows_ExposeTheSharedContract()
    {
        ILeaderboardRankingRow ranking = new RankingRowViewModel(RankingsWire.Account(2, "abc"), RankingMetric.TotalScore, true);
        Assert.True(ranking.IsSelected);
        Assert.Equal("#2", ranking.RankText);
        ILeaderboardScoreRow song = new SongLeaderboardRowViewModel(
            new LeaderboardEntry { AccountId = "x", Score = 1234, Rank = 3, Season = 9, Stars = 5, Accuracy = 990000, IsFullCombo = true }, false)
        { RankChars = 3, ScoreChars = 5 };
        Assert.Equal(("#3", "S9", "1,234", 5, true, 3, 5), (song.RankText, song.Season, song.Score, song.StarCount, song.IsFullCombo, song.RankChars, song.ScoreChars));
    }

    [Fact]
    public void HistoryRows_AreLabelledRowsWithoutRankOrDestination()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var point = new ScoreHistoryPoint(new ScoreHistoryEntry { NewScore = 5000, Accuracy = 1000000, IsFullCombo = true, Season = 4, ChangedAt = "x" },
            new DateTimeOffset(2026, 3, 30, 12, 5, 9, TimeSpan.Zero));
        ILeaderboardScoreRow best = new ScoreHistoryListRow(point, true);
        Assert.Equal("", best.RankText);
        Assert.Equal(point.LongDate, best.Name);
        Assert.True(best.IsSelected);
        Assert.Null(best.Route);
        Assert.Equal((0, 0, 0), (best.RankChars, best.ScoreChars, best.StarCount));
        Assert.Equal("fst.song-detail.history.row.20260330120509", best.AutomationId);
        Assert.False(((ILeaderboardEntryRow)new ScoreHistoryListRow(point, false)).IsSelected);
    }

    [Fact]
    public async Task BothPagers_ImplementTheBoardPagerContract()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var requested = new List<int>();
        IBoardPager bands = new BandsPagerViewModel(p => { requested.Add(p); return Task.CompletedTask; });
        var changed = new List<string?>();
        bands.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        Assert.False(bands.IsPaged);
        ((BandsPagerViewModel)bands).PageCount = 3;
        ((BandsPagerViewModel)bands).Page = 2;
        Assert.Contains(nameof(IBoardPager.InfoText), changed);
        Assert.Contains(nameof(IBoardPager.IsPaged), changed);
        Assert.Equal(("2 / 3", "Page 2 of 3", true, true, true), (bands.InfoText, bands.InfoAnnouncement, bands.IsPaged, bands.CanGoBack, bands.CanGoForward));
        foreach (var command in new ICommand[] { bands.FirstCommand, bands.PreviousCommand, bands.NextCommand, bands.LastCommand }) command.Execute(null);
        Assert.Equal([1, 1, 3, 3], requested);

        requested.Clear();
        IBoardPager rankings = new RankingsPagerViewModel("fst.x", p => { requested.Add(p); return Task.CompletedTask; });
        Assert.False(rankings.IsPaged);
        ((RankingsPagerViewModel)rankings).Update(5, 9);
        Assert.Equal(("5 / 9", true), (rankings.InfoText, rankings.IsPaged));
        foreach (var command in new ICommand[] { rankings.FirstCommand, rankings.PreviousCommand, rankings.NextCommand, rankings.LastCommand }) command.Execute(null);
        await Task.Yield();
        Assert.Equal([1, 4, 6, 9], requested);
    }
}
