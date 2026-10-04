using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>CHOpt Paths text table: text columns and the stacking breakpoint follow the Windows text size (issue #223).</summary>
public sealed class PathTableLayoutTests
{
    [Theory]
    [InlineData(PathColumnKey.Beat, 1, 80d)]
    [InlineData(PathColumnKey.Time, 1, 110d)]
    [InlineData(PathColumnKey.Score, 1, 100d)]
    [InlineData(PathColumnKey.Beat, 2, 160d)]
    [InlineData(PathColumnKey.Time, 2, 220d)]
    [InlineData(PathColumnKey.Score, 2.25, 225d)]
    [InlineData(PathColumnKey.Time, double.NaN, 110d)]
    public void TextColumns_GrowWithText(PathColumnKey key, double scale, double expected) =>
        Assert.Equal(expected, PathTableLayout.Width(key, scale));

    [Theory]
    [InlineData(PathColumnKey.Note)]
    [InlineData(PathColumnKey.Od)]
    public void ActivationAndOverdrive_AreStarSized(PathColumnKey key)
    {
        Assert.Null(PathTableLayout.BaseWidth(key));
        Assert.Null(PathTableLayout.Width(key, 2));
    }

    [Fact]
    public void OverdriveLabel_GrowsWithText()
    {
        Assert.Equal(32, PathTableLayout.OdLabelMinWidth(1));
        Assert.Equal(64, PathTableLayout.OdLabelMinWidth(2));
    }

    [Theory]
    [InlineData(1, 640d)]          // web breakpoint at 100% text
    [InlineData(0.5, 640d)]        // never below the web breakpoint
    [InlineData(1.5, 801d)]        // 640 + (120 + 165 + 150 + 48) − 322
    [InlineData(2, 962d)]          // 640 + 322
    [InlineData(2.25, 1043d)]      // 640 + (180 + 248 + 225 + 72) − 322
    public void Breakpoint_GrowsByTheExtraTextWidth(double scale, double expected) =>
        Assert.Equal(expected, PathTableLayout.StackBreakpoint(scale));

    [Theory]
    [InlineData(639, 1, true)]
    [InlineData(640, 1, false)]
    [InlineData(852, 1, false)]    // medium window: grid rows at 100% text
    [InlineData(852, 2, true)]     // medium window: stacked cards at 200% text
    [InlineData(1100, 2, false)]   // wide window keeps the grid at 200% text
    [InlineData(0, 2, false)]      // before layout
    [InlineData(-1, 1, false)]
    public void Stacks_BelowTheScaledBreakpoint(double width, double scale, bool expected) =>
        Assert.Equal(expected, PathTableLayout.Stacks(width, scale));
}
