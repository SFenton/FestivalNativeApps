using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Widths that follow the Windows text size.</summary>
public sealed class TextScalingTests
{
    [Theory]
    [InlineData(72, 1, 72)]         // 100% text
    [InlineData(72, 2, 144)]        // 200% text
    [InlineData(72, 2.25, 162)]     // largest Windows text size
    [InlineData(72, 1.33, 96)]      // rounded up
    [InlineData(72, 0.5, 72)]       // never shrinks
    [InlineData(72, double.NaN, 72)]
    [InlineData(0, 2, 0)]
    [InlineData(-10, 2, 0)]
    [InlineData(double.PositiveInfinity, 2, 0)]
    public void ScaledWidth_GrowsWithText(double width, double factor, double expected) =>
        Assert.Equal(expected, TextScaling.ScaledWidth(width, factor));
}