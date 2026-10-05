using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class SettingValueLayoutTests
{
    [Fact]
    public void FitsSideBySideWhenLabelGapAndValueFit()
    {
        Assert.False(SettingValueLayout.ShouldStack(300, 150, 138));
        Assert.False(SettingValueLayout.ShouldStack(300, 150, 100));
    }

    [Fact]
    public void StacksWhenOneEpxTooWide()
    {
        Assert.True(SettingValueLayout.ShouldStack(300, 150, 138.5));
        Assert.True(SettingValueLayout.ShouldStack(200, 250, 0));
    }

    [Theory]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NaN)]
    public void UnboundedWidthNeverStacks(double available)
    {
        Assert.False(SettingValueLayout.ShouldStack(available, 5000, 5000));
    }

    [Fact]
    public void SpacingConstantsMatchCardRhythm()
    {
        Assert.Equal(12, SettingValueLayout.ColumnSpacing);
        Assert.Equal(4, SettingValueLayout.StackedSpacing);
    }
}
