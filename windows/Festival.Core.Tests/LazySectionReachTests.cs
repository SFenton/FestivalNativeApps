using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Player Profile sections start their reads within one viewport of the visible area (#533).</summary>
public sealed class LazySectionReachTests
{
    [Theory]
    // Section on screen, partly visible above or below.
    [InlineData(0, 800, 500, true)]
    [InlineData(-400, 800, 500, true)]
    [InlineData(300, 800, 500, true)]
    // Exactly one viewport below or above the visible area.
    [InlineData(-1600, 800, 500, true)]
    [InlineData(1300, 800, 500, true)]
    // Further away.
    [InlineData(-1601, 800, 500, false)]
    [InlineData(1301, 800, 500, false)]
    public void IsNear_CoversOneViewportEachWay(double top, double height, double section, bool expected) =>
        Assert.Equal(expected, LazySectionReach.IsNear(top, height, section));

    [Theory]
    [InlineData(0, 0, 500)]
    [InlineData(0, -1, 500)]
    [InlineData(double.NaN, 800, 500)]
    [InlineData(double.PositiveInfinity, 800, 500)]
    [InlineData(double.NegativeInfinity, 800, 500)]
    public void IsNear_IgnoresEmptyViewports(double top, double height, double section) =>
        Assert.False(LazySectionReach.IsNear(top, height, section));

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(0)]
    [InlineData(-5)]
    public void IsNear_TreatsUnmeasuredSectionsAsPoints(double section)
    {
        Assert.True(LazySectionReach.IsNear(800, 800, section));
        Assert.False(LazySectionReach.IsNear(801, 800, section));
    }
}
