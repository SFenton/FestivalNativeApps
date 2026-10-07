using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The pinned-section-title row fade (scroll-edge R2–R5, R7, R8; issues #49, #308).</summary>
public sealed class SongHeaderEdgeFadeTests
{
    private const double Bar = 35;

    [Fact]
    public void Depth_MatchesTheWebScrollMask() => Assert.Equal(40, SongHeaderEdgeFade.Depth);

    [Fact]
    public void Stops_AreALinearRampFromClearToOpaque() =>
        Assert.Equal([(0f, 0f), (1f, 1f)], SongHeaderEdgeFade.Stops);

    [Theory]
    [InlineData(false, true, false, false, true)]
    [InlineData(true, true, false, false, false)]
    [InlineData(false, false, false, false, false)]
    [InlineData(false, true, true, false, false)]
    [InlineData(false, true, false, true, false)]
    public void IsEnabled_KeepsTheHardEdgeInContrastAndTransparencyModes(bool contrastTheme, bool effects, bool less, bool more, bool expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.IsEnabled(contrastTheme, effects, less, more));

    [Theory]
    [InlineData(0, 0)]
    [InlineData(-5, 0)]
    [InlineData(14, 14)]
    [InlineData(40, 40)]
    [InlineData(500, 40)]
    [InlineData(double.NaN, 0)]
    public void FadeDepth_WithoutTitlesGrowsWithTheScrollLikeTheWeb(double offset, double expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.FadeDepth(offset, null, null, Bar), 6);

    [Theory]
    [InlineData(100, 40)] // far below: the full ramp
    [InlineData(25, 25)] // incoming title inside the band: the ramp ends at its top, so it is never dimmed
    [InlineData(0, 0)] // title at the viewport top
    [InlineData(-10, 0)] // title crossing into the bar
    [InlineData(-Bar, 0)] // pinned exactly (a Jump landing): the first row is fully opaque (R8)
    [InlineData(-Bar - 12, 12)] // rows scrolled 12 epx past the pin line
    [InlineData(-Bar - 400, 40)]
    public void FadeDepth_IsCutToTheNearestSectionTitle(double titleTop, double expected)
    {
        Assert.Equal(expected, SongHeaderEdgeFade.FadeDepth(5000, null, titleTop, Bar), 6);
        Assert.Equal(expected, SongHeaderEdgeFade.FadeDepth(5000, titleTop, null, Bar), 6);
    }

    [Fact]
    public void FadeDepth_TheNearerTitleWins() =>
        Assert.Equal(6, SongHeaderEdgeFade.FadeDepth(5000, -Bar - 30, 6, Bar), 6);

    [Fact]
    public void FadeDepth_IsContinuousAsATitleScrollsThroughTheBar()
    {
        double? last = null;
        for (var top = 60.0; top >= -Bar - 60; top -= 0.5)
        {
            var depth = SongHeaderEdgeFade.FadeDepth(5000, null, top, Bar);
            Assert.InRange(depth, 0, SongHeaderEdgeFade.Depth);
            if (last is { } previous) Assert.InRange(Math.Abs(depth - previous), 0, 0.5001);
            last = depth;
        }
    }

    [Theory]
    [InlineData(null, 1_000_000)]
    [InlineData(double.NaN, 1_000_000)]
    [InlineData(10.0, 10)]
    [InlineData(-20.0, 0)]
    [InlineData(-Bar - 5.0, 5)]
    public void TitleLimit_MatchesTheCompositorFormula(double? top, double expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.TitleLimit(top, Bar), 6);

    [Theory]
    [InlineData(-1, 40, 0)]
    [InlineData(0, 40, 0)]
    [InlineData(20, 40, 0.5)]
    [InlineData(40, 40, 1)]
    [InlineData(80, 40, 1)]
    [InlineData(0, 0, 1)]
    [InlineData(3, 0, 1)]
    public void MaskAlpha_IsClearAtTheEdgeAndOpaqueAfterTheRamp(double distance, double depth, double expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.MaskAlpha(distance, depth), 6);

    [Theory]
    [InlineData(false, true, 100, 40, "hidden")]
    [InlineData(false, false, 0, 0, "hidden")]
    [InlineData(true, false, 100, 40, "hard-edge")]
    [InlineData(true, false, 0, 0, "hard-edge")]
    [InlineData(true, true, 0, 0, "top")]
    [InlineData(true, true, 100, 0, "clear")]
    [InlineData(true, true, 100, 0.5, "clear")]
    [InlineData(true, true, 10, 10, "fading")]
    [InlineData(true, true, 100, 40, "fading")]
    public void Status_NamesEachReachableEdgeState(bool headerShown, bool enabled, double offset, double depth, string expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.Status(headerShown, enabled, offset, depth));
}
