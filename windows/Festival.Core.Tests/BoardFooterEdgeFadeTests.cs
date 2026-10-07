using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The bottom-chrome ramp above a leaderboard's floating footer (scroll-edge R2–R4, R7; issues #93, #308).</summary>
public sealed class BoardFooterEdgeFadeTests
{
    [Fact]
    public void Depth_MatchesTheWebBoardPageMask() => Assert.Equal(40, BoardFooterEdgeFade.Depth);

    [Theory]
    [InlineData(1000, 1000, 0)]
    [InlineData(1000, 1200, 0)]
    [InlineData(1000, 980, 20)]
    [InlineData(1000, 960, 40)]
    [InlineData(1000, 0, 40)]
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

    [Theory]
    [InlineData(false, true, 40, "hidden")]
    [InlineData(false, false, 0, "hidden")]
    [InlineData(true, false, 0.01, "hard-edge")]
    [InlineData(true, false, 40, "hard-edge")]
    [InlineData(true, true, 0.01, "end")]
    [InlineData(true, true, 0.6, "end")]
    [InlineData(true, true, double.NaN, "end")]
    [InlineData(true, true, 1, "fading:1")]
    [InlineData(true, true, 17.6, "fading:18")]
    [InlineData(true, true, 40, "fading:40")]
    public void Status_NamesTheDrawnEdge(bool drawn, bool enabled, double depth, string expected) =>
        Assert.Equal(expected, BoardFooterEdgeFade.Status(drawn, enabled, depth));

    [Fact]
    public void Status_MidScrollReportsTheFullWebRamp() =>
        Assert.Equal("fading:40", BoardFooterEdgeFade.Status(true, true, BoardFooterEdgeFade.FadeDepth(1000, 500)));
}
