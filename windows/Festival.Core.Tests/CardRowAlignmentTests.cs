using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Side-by-side card headers share their row's height (section-headers R14, issue #657).</summary>
public class CardRowAlignmentTests
{
    [Fact]
    public void ComboHeaderRaisesItsRowOnly()
    {
        // Leaderboards at three columns: the combo board (icon row above its title) leads the first row.
        double?[] heights = [76, 36, 36, 36, 36, 36];
        Assert.Equal([76, 76, 76, 36, 36, 36], CardRowAlignment.HeaderHeights(heights, 3));
    }

    [Fact]
    public void LastPartialRowAlignsWithinItself()
    {
        double?[] heights = [76, 36, 36, 40, 36];
        Assert.Equal([76, 76, 40, 40, 36], CardRowAlignment.HeaderHeights(heights, 2));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(0)]
    public void OneColumnAlignsNothing(int columns) =>
        Assert.Equal([0, 0], CardRowAlignment.HeaderHeights([76, 36], columns));

    [Fact]
    public void CardsWithoutHeadersNeitherSetNorTakeTheRowHeight()
    {
        double?[] heights = [null, 36, 28];
        Assert.Equal([0, 36, 36], CardRowAlignment.HeaderHeights(heights, 3));
    }

    [Fact]
    public void EmptyGridHasNoHeights() => Assert.Empty(CardRowAlignment.HeaderHeights([], 3));

    [Theory]
    [InlineData(76, 36, 40)]
    [InlineData(36, 36, 0)]
    [InlineData(36, 44, 0)]
    [InlineData(0, 36, 0)]
    public void TopInsetIsTheShortfall(double row, double natural, double inset) =>
        Assert.Equal(inset, CardRowAlignment.TopInset(row, natural));
}
