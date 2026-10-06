using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class BandScoreFooterLayoutTests
{
    [Fact]
    public void FitsOnOneLineWhenScoreGapAndBadgesFit()
    {
        Assert.False(BandScoreFooterLayout.Stacks(300, 120, 174, 6));
        Assert.False(BandScoreFooterLayout.Stacks(300, 120, 174.4, 6));
    }

    [Fact]
    public void StacksWhenBadgesWouldSqueezeTheScore()
    {
        // 200% text in a half-width Quads card: "1,939,822" plus FC, accuracy and five stars.
        Assert.True(BandScoreFooterLayout.Stacks(220, 150, 180, 6));
        Assert.True(BandScoreFooterLayout.Stacks(300, 120, 175, 6));
    }

    [Fact]
    public void NoBadgesNeverStacks()
    {
        Assert.False(BandScoreFooterLayout.Stacks(50, 400, 0, 6));
    }

    [Fact]
    public void SectionStacksEveryRowWhenAnyRowNeedsTwoLines()
    {
        var section = new BandScoreFooterSection<string>();
        Assert.False(section.Report("row1", false));
        Assert.False(section.Stacked);
        Assert.True(section.Report("row2", true));
        Assert.True(section.Stacked);
        Assert.Equal(["row1", "row2"], section.Members.Order());
        Assert.False(section.Report("row3", true));
        Assert.False(section.Report("row2", false));
        Assert.True(section.Stacked);
        Assert.True(section.Report("row3", false));
        Assert.False(section.Stacked);
    }

    [Fact]
    public void RemovingTheLastStackingRowReturnsTheSectionToOneLine()
    {
        var section = new BandScoreFooterSection<string>();
        section.Report("row1", false);
        section.Report("row2", true);
        Assert.True(section.Remove("row2"));
        Assert.False(section.Stacked);
        Assert.Equal(["row1"], section.Members);
        Assert.False(section.Remove("missing"));
    }

    [Theory]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NaN)]
    public void UnboundedWidthNeverStacks(double available)
    {
        Assert.False(BandScoreFooterLayout.Stacks(available, 5000, 5000, 6));
    }
}
