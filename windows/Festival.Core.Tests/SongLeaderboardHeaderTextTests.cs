using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>The song leaderboard header button's accessible name (pattern <c>song-leaderboard-header</c>; issues #317, #465).</summary>
public class SongLeaderboardHeaderTextTests
{
    [Fact]
    public void BandBoard_ReadsEveryVisibleLineInOrder() =>
        Assert.Equal("Fixture Pulse, Synthetic Quartet, Duos, 29 Duos entries",
            SongLeaderboardHeaderText.AccessibleName("Fixture Pulse", "Synthetic Quartet", "Duos", "29 Duos entries"));

    [Fact]
    public void HiddenTotal_IsNotRead() =>
        Assert.Equal("Fixture Pulse, Synthetic Quartet, Quads",
            SongLeaderboardHeaderText.AccessibleName("Fixture Pulse", "Synthetic Quartet", "Quads", ""));

    [Theory]
    [InlineData(null, "Lead")]
    [InlineData("", "Lead")]
    [InlineData(" ", "Lead, 12 entries")]
    public void WithoutASong_ThereIsNoButtonName(string? title, string board) =>
        Assert.Equal("", SongLeaderboardHeaderText.AccessibleName(title, "Synthetic Quartet", board, ""));

    [Fact]
    public void EmptyAndBlankLines_AreSkippedAndTrimmed() =>
        Assert.Equal("Fixture Pulse, Lead",
            SongLeaderboardHeaderText.AccessibleName(" Fixture Pulse ", null, "Lead ", "  "));

    [Fact]
    public void Name_StartsWithTheVisibleTitle() =>
        Assert.StartsWith("Fixture Pulse" + SongLeaderboardHeaderText.Separator,
            SongLeaderboardHeaderText.AccessibleName("Fixture Pulse", "Synthetic Quartet", "Lead", ""));
}
