using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class PathSelectorLayoutTests
{
    [Fact]
    public void BoxWidth_AddsPaddingAndGlyphColumnToTheLongestOption()
    {
        // "Pro Drums + Cymbals": 32 epx icon space + ~130 epx name, plus 12 padding and the 38 epx glyph column.
        Assert.Equal(212, PathSelectorLayout.BoxWidth(162, 12, 0, PathSelectorLayout.InstrumentMinWidth));
        Assert.Equal(213, PathSelectorLayout.BoxWidth(162.2, 12, 0, PathSelectorLayout.InstrumentMinWidth));
    }

    [Fact]
    public void BoxWidth_KeepsTheMinimumForShortOptions()
    {
        Assert.Equal(PathSelectorLayout.InstrumentMinWidth, PathSelectorLayout.BoxWidth(60, 12, 0, PathSelectorLayout.InstrumentMinWidth));
        Assert.Equal(PathSelectorLayout.DisplayMinWidth, PathSelectorLayout.BoxWidth(-5, 12, 0, PathSelectorLayout.DisplayMinWidth));
    }

    [Fact]
    public void Stacks_KeepsOneLineWhenAllThreeFit()
    {
        Assert.False(PathSelectorLayout.Stacks(420, 212, 100, 92, 8));
        Assert.False(PathSelectorLayout.Stacks(420, 212, 100, 92.4, 8));
        Assert.False(PathSelectorLayout.Stacks(double.PositiveInfinity, 5000, 5000, 5000, 8));
    }

    [Fact]
    public void Stacks_ReflowsWhenTheRowIsTooNarrow()
    {
        // 200% text on a compact window: the longest instrument alone takes most of the row.
        Assert.True(PathSelectorLayout.Stacks(420, 342, 150, 150, 8));
        Assert.True(PathSelectorLayout.Stacks(420, 212, 100, 93, 8));
    }
}
