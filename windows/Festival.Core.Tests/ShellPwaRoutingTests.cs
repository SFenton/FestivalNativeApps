namespace Festival.Core.Tests;

public class ShellPwaRoutingTests
{
    public static TheoryData<string> PlayerOnlyPaths => new()
    {
        "/rivals", "/rivals/all?category=common", "/rivals/r1", "/rivals/r1/rivalry?mode=almost_passed",
        "/compete", "/statistics", "/suggestions",
    };

    public static TheoryData<string> PublicPaths => new()
    {
        "/songs/s1", "/songs/s1/Solo_Guitar", "/songs/s1/bands/Band_Duets", "/player/acc1", "/bands", "/bands/b1",
        "/bands/player/acc1", "/leaderboards", "/leaderboards/all", "/leaderboards/bands/Band_Duets", "/shop",
        "/settings/licenses", "/search?q=abc",
        // The history page renders its own no-player state (web PlayerHistoryPage; issue #324).
        "/songs/s1/Solo_Guitar/history",
    };

    [Theory]
    [MemberData(nameof(PlayerOnlyPaths))]
    public void PlayerOnlyRoutes_RedirectToSongsWithoutProfile(string path)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out _));
        Assert.True(AppRouteParser.RequiresPlayer(route!));
        Assert.Null(AppRouteParser.ForProfile(route, hasPlayer: false));
        Assert.Same(route, AppRouteParser.ForProfile(route, hasPlayer: true));
    }

    [Theory]
    [MemberData(nameof(PublicPaths))]
    public void PublicRoutes_StayWithoutProfile(string path)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out _));
        Assert.False(AppRouteParser.RequiresPlayer(route!));
        Assert.Same(route, AppRouteParser.ForProfile(route, hasPlayer: false));
    }

    [Fact]
    public void ForProfile_SectionRootStaysRoot() => Assert.Null(AppRouteParser.ForProfile(null, hasPlayer: false));

    [Theory]
    [InlineData("/songs/s1", "Song Info")]
    [InlineData("/songs/s1/Solo_Guitar", "Leaderboards")]
    [InlineData("/songs/s1/bands/Band_Duets", "Leaderboards")]
    [InlineData("/songs/s1/Solo_Guitar/history", "Score History")]
    [InlineData("/player/acc1", "Player Profile")]
    [InlineData("/bands", "Player Bands")]
    [InlineData("/bands/b1", "Player Bands")]
    [InlineData("/bands/player/acc1", "Player Bands")]
    [InlineData("/leaderboards", "Leaderboards")]
    [InlineData("/leaderboards/all", "Leaderboards")]
    [InlineData("/leaderboards/bands/Band_Duets", "Leaderboards")]
    [InlineData("/rivals", "Rivals")]
    [InlineData("/rivals/all?category=common", "All Rivals")]
    [InlineData("/rivals/r1", "Rival Details")]
    [InlineData("/rivals/r1/rivalry?mode=almost_passed", "Rivalry")]
    [InlineData("/compete", "Compete")]
    [InlineData("/statistics", "Statistics")]
    [InlineData("/suggestions", "Suggestions")]
    [InlineData("/shop", "Item Shop")]
    [InlineData("/settings/licenses", "Licenses")]
    [InlineData("/search", "Search")]
    public void WindowTitle_UsesWebPageNames(string path, string page)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out var section));
        Assert.Equal($"Festival Score Tracker - {page}", WindowTitles.For(section, route));
    }

    [Theory]
    [InlineData(AppSection.Songs, "Songs")]
    [InlineData(AppSection.Settings, "Settings")]
    [InlineData(AppSection.Shop, "Item Shop")]
    [InlineData(AppSection.Leaderboards, "Leaderboards")]
    public void WindowTitle_SectionRoots(AppSection section, string page) =>
        Assert.Equal($"Festival Score Tracker - {page}", WindowTitles.For(section, null));
}
