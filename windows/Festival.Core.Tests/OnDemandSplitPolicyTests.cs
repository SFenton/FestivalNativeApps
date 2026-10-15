namespace Festival.Core.Tests;

/// <summary>Windows on-demand split rules (split-panes R7 Windows variant, issue #652).</summary>
public class OnDemandSplitPolicyTests
{
    private static readonly AppRoute Rival = new AppRoute.RivalDetail("r1");
    private static readonly AppRoute Rivalry = new AppRoute.Rivalry("r1", "closest");
    private static readonly AppRoute Rankings = new AppRoute.FullRankings(Instrument.Lead, "totalscore");
    private static readonly AppRoute BandRankings = new AppRoute.BandRankings("Band_Duets");
    private static readonly AppRoute Board = new AppRoute.SongLeaderboard("s1", Instrument.Lead);
    private static readonly AppRoute BandBoard = new AppRoute.SongBandLeaderboard("s1", "Band_Duets");
    private static readonly AppRoute History = new AppRoute.PlayerHistory("s1", Instrument.Lead);
    private static readonly AppRoute Song = new AppRoute.SongDetail("s1");
    private static readonly AppRoute Player = new AppRoute.Player("p1");

    [Theory]
    [InlineData(959.9, 1.0, false)]
    [InlineData(960, 1.0, true)]
    [InlineData(1040, 1.0, true)] // the default 1280 epx window with the expanded navigation pane
    [InlineData(768, 1.0, false)] // the 1008 epx Expanded threshold
    [InlineData(1040, 1.29, true)]
    [InlineData(1247, 1.3, false)]
    [InlineData(1248, 1.3, true)]
    [InlineData(2159, 2.25, false)]
    [InlineData(2160, 2.25, true)]
    [InlineData(0, 1.0, false)]
    public void AllowsSplit_KeepsEachHalfAtTheMinimumScaledFromLargeText(double width, double scale, bool split) =>
        Assert.Equal(split, OnDemandSplitPolicy.AllowsSplit(width, scale));

    [Fact]
    public void PaneMinimum_GrowsOnlyFromLargeText()
    {
        Assert.Equal(480, OnDemandSplitPolicy.PaneMinimum(1));
        Assert.Equal(480, OnDemandSplitPolicy.PaneMinimum(1.25));
        Assert.Equal(720, OnDemandSplitPolicy.PaneMinimum(1.5));
    }

    [Fact]
    public void PageOf_ListsOnlyTheDuoAndIPadSplitPages()
    {
        Assert.Equal(SplitListPage.Rivals, OnDemandSplitPolicy.PageOf(AppSection.Rivals));
        Assert.Equal(SplitListPage.Rivals, OnDemandSplitPolicy.PageOf(new AppRoute.Rivals()));
        Assert.Equal(SplitListPage.Rivals, OnDemandSplitPolicy.PageOf(new AppRoute.Compete()));
        Assert.Equal(SplitListPage.Rivals, OnDemandSplitPolicy.PageOf(new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead]))));
        Assert.Equal(SplitListPage.Leaderboards, OnDemandSplitPolicy.PageOf(AppSection.Leaderboards));
        Assert.Equal(SplitListPage.Leaderboards, OnDemandSplitPolicy.PageOf(new AppRoute.Leaderboards()));
        Assert.Equal(SplitListPage.SongDetail, OnDemandSplitPolicy.PageOf(Song));
        // Songs never splits (#652): a song pushes Song Detail full width, as on iPad and the Duo.
        Assert.Null(OnDemandSplitPolicy.PageOf(AppSection.Songs));
        Assert.Null(OnDemandSplitPolicy.PageOf(AppSection.Suggestions));
        Assert.Null(OnDemandSplitPolicy.PageOf(AppSection.Statistics));
        Assert.Null(OnDemandSplitPolicy.PageOf(AppSection.Shop));
        Assert.Null(OnDemandSplitPolicy.PageOf(AppSection.Settings));
        Assert.Null(OnDemandSplitPolicy.PageOf(Rankings));
        Assert.Null(OnDemandSplitPolicy.PageOf(Board));
        Assert.Null(OnDemandSplitPolicy.PageOf(Player));
        Assert.Null(OnDemandSplitPolicy.PageOf(null));
    }

    [Fact]
    public void Accepts_EachListPagesOwnSubPages()
    {
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.Rivals, Rival));
        Assert.False(OnDemandSplitPolicy.Accepts(SplitListPage.Rivals, Rivalry));
        Assert.False(OnDemandSplitPolicy.Accepts(SplitListPage.Rivals, Rankings));
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.Leaderboards, Rankings));
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.Leaderboards, BandRankings));
        Assert.False(OnDemandSplitPolicy.Accepts(SplitListPage.Leaderboards, Player));
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.SongDetail, Board));
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.SongDetail, BandBoard));
        Assert.True(OnDemandSplitPolicy.Accepts(SplitListPage.SongDetail, History));
        Assert.False(OnDemandSplitPolicy.Accepts(SplitListPage.SongDetail, Song));
        Assert.False(OnDemandSplitPolicy.Accepts(SplitListPage.SongDetail, Rival));
    }

    [Fact]
    public void OpensInPane_KeepsBoardsRankingsAndRivalPagesButNotProfilesOrSongs()
    {
        Assert.All(new[] { Rival, Rivalry, Rankings, BandRankings, Board, BandBoard, History }, r => Assert.True(OnDemandSplitPolicy.OpensInPane(r)));
        Assert.All(new[] { Song, Player, new AppRoute.Band("b1"), new AppRoute.Search(), new AppRoute.Licenses() },
            r => Assert.False(OnDemandSplitPolicy.OpensInPane(r)));
    }

    [Fact]
    public void Decide_OpensReplacesPushesInPaneOrPushesFull()
    {
        // A list page's sub-page opens the pane, or replaces the open one when picked from the list.
        Assert.Equal(SplitAction.OpenPane, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, true, false, false, Rival));
        Assert.Equal(SplitAction.OpenPane, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, true, true, false, Rival));
        Assert.Equal(SplitAction.OpenPane, OnDemandSplitPolicy.Decide(SplitListPage.Leaderboards, true, false, false, BandRankings));
        Assert.Equal(SplitAction.OpenPane, OnDemandSplitPolicy.Decide(SplitListPage.SongDetail, true, false, false, History));
        // The pane's own sub-pages stay in it; profiles and songs cover both panes.
        Assert.Equal(SplitAction.PushInPane, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, true, true, true, Rivalry));
        Assert.Equal(SplitAction.PushInPane, OnDemandSplitPolicy.Decide(SplitListPage.SongDetail, true, true, true, Board));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(SplitListPage.Leaderboards, true, true, true, Player));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, true, true, true, Song));
        // A narrow window and the pages that never split push full width.
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, false, false, false, Rival));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(null, true, false, false, Song));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(null, true, false, false, Board));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, true, false, false, Rivalry));
        // A pane shown alone in a narrow window keeps its own sub-pages; the list's taps push full width.
        Assert.Equal(SplitAction.PushInPane, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, false, true, true, Rivalry));
        Assert.Equal(SplitAction.PushFull, OnDemandSplitPolicy.Decide(SplitListPage.Rivals, false, true, false, Rival));
    }
}
