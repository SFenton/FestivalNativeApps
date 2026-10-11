using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class WrapLineLayoutTests
{
    [Fact]
    public void KeepsItemsOnOneLineWhileTheyFit()
    {
        Assert.Equal([0, 0, 0], WrapLineLayout.Lines([100, 80, 120], 316, 8));
    }

    [Fact]
    public void RoundingShortfallDoesNotWrapTheLastItem()
    {
        // Issue #516: arrange got a width a fraction of a pixel under the measured line, and the List View button wrapped.
        Assert.Equal([0, 0, 0], WrapLineLayout.Lines([100, 80, 120], 315.4, 8));
    }

    [Fact]
    public void WrapsWhenAnItemTrulyOverflows()
    {
        Assert.Equal([0, 0, 1], WrapLineLayout.Lines([100, 80, 120], 300, 8));
        Assert.Equal([0, 1, 2], WrapLineLayout.Lines([200, 200, 200], 250, 8));
    }

    [Fact]
    public void AnOversizedFirstItemStaysOnItsOwnLine()
    {
        Assert.Equal([0, 1], WrapLineLayout.Lines([400, 50], 300, 8));
    }

    [Fact]
    public void InfiniteWidthNeverWraps()
    {
        Assert.Equal([0, 0, 0], WrapLineLayout.Lines([5000, 5000, 5000], double.PositiveInfinity, 8));
    }

    [Fact]
    public void NoItemsGiveNoLines()
    {
        Assert.Empty(WrapLineLayout.Lines([], 100, 8));
    }
}
