using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The Songs section header edge fade (issue #49).</summary>
public sealed class SongHeaderEdgeFadeTests
{
    [Fact]
    public void Depth_MatchesIos() => Assert.Equal(28, SongHeaderEdgeFade.Depth);

    [Fact]
    public void Stops_AreAnEasedRampFromTransparentToOpaque()
    {
        var stops = SongHeaderEdgeFade.Stops;
        Assert.Equal([0f, 0.25f, 0.5f, 0.75f, 1f], stops.Select(s => s.Offset));
        Assert.Equal(0f, stops[0].Alpha);
        Assert.Equal(0.15625f, stops[1].Alpha, 6);
        Assert.Equal(0.5f, stops[2].Alpha, 6);
        Assert.Equal(0.84375f, stops[3].Alpha, 6);
        Assert.Equal(1f, stops[4].Alpha);
    }

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
    [InlineData(14, 0.5)]
    [InlineData(28, 1)]
    [InlineData(500, 1)]
    [InlineData(double.NaN, 0)]
    public void Strength_RampsInOverTheDepth(double offset, double expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.Strength(offset), 6);

    [Theory]
    [InlineData(0f, 0, 1f)]
    [InlineData(0f, 0.5, 0.5f)]
    [InlineData(0f, 1, 0f)]
    [InlineData(0f, 2, 0f)]
    [InlineData(1f, 1, 1f)]
    [InlineData(0.5f, 1, 0.5f)]
    public void MaskAlpha_ScalesWithStrength(float stop, double strength, float expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.MaskAlpha(stop, strength), 6);

    [Theory]
    [InlineData(false, true, 1, "hidden")]
    [InlineData(false, false, 0, "hidden")]
    [InlineData(true, false, 1, "hard-edge")]
    [InlineData(true, false, 0, "hard-edge")]
    [InlineData(true, true, 0, "top")]
    [InlineData(true, true, 0.25, "fading")]
    [InlineData(true, true, 1, "fading")]
    public void Status_NamesEachReachableEdgeState(bool headerShown, bool enabled, double strength, string expected) =>
        Assert.Equal(expected, SongHeaderEdgeFade.Status(headerShown, enabled, strength));
}
