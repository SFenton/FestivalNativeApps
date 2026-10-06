using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The bottom-chrome ramp above a leaderboard's floating footer (scroll-edge R2–R4, R7; issues #93, #308).</summary>
public sealed class BoardFooterEdgeFadeTests
{
    [Fact]
    public void Depth_MatchesTheWebScrollFade() => Assert.Equal(36, BoardFooterEdgeFade.Depth);

    [Theory]
    [InlineData(1000, 1000, 0)]
    [InlineData(1000, 1200, 0)]
    [InlineData(1000, 982, 18)]
    [InlineData(1000, 964, 36)]
    [InlineData(1000, 0, 36)]
    [InlineData(0, 0, 0)]
    [InlineData(double.NaN, 0, 0)]
    public void FadeDepth_ShrinksToNothingOverTheLastDepthOfScroll(double scrollable, double offset, double expected) =>
        Assert.Equal(expected, BoardFooterEdgeFade.FadeDepth(scrollable, offset), 6);

    [Fact]
    public void FadeDepth_AccessibilityModesGiveAHardCut() =>
        Assert.Equal(0, BoardFooterEdgeFade.FadeDepth(1000, 0, enabled: false));

    [Fact]
    public void Stops_RunFromOpaqueToClearAtTheFooterTop() =>
        Assert.Equal([(0f, 1f), (1f, 0f)], BoardFooterEdgeFade.Stops);
}
