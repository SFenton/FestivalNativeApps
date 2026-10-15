using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

public sealed class PathSelectorLayoutTests
{
    [Fact]
    public void WideBoxWidth_SharesTheWiderBoxAndKeepsTheMinimum()
    {
        // Default text: "Medium" and "Image" are short, so both wide boxes take the 200 epx minimum.
        Assert.Equal(PathSelectorLayout.WideBoxMinWidth, PathSelectorLayout.WideBoxWidth(110, 106));
        // 225% text: the longer box sets the shared width, so neither clips its longest option.
        Assert.Equal(236, PathSelectorLayout.WideBoxWidth(236, 214));
        Assert.Equal(251, PathSelectorLayout.WideBoxWidth(198, 251));
    }

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

    [Fact]
    public void IconBoxWidth_IsTheIconPlusChromeAndNeverBelowTheTouchTarget()
    {
        // 24 epx instrument icon + 12 padding + 38 glyph column; 20 epx display glyph.
        Assert.Equal(74, PathSelectorLayout.IconBoxWidth(PathSelectorLayout.InstrumentIconSize, 12, 0));
        Assert.Equal(70, PathSelectorLayout.IconBoxWidth(PathSelectorLayout.DisplayIconSize, 12, 0));
        Assert.Equal(PathSelectorLayout.FSTMinTarget, PathSelectorLayout.IconBoxWidth(0, 0, 0));
    }

    [Fact]
    public void Plan_KeepsLabelsWhenTheLabelledRowFits()
    {
        Assert.Equal(PathSelectorArrangement.Labelled, PathSelectorLayout.Plan(420, 212, 100, 92, 74, 70, 8));
        Assert.Equal(PathSelectorArrangement.Labelled, PathSelectorLayout.Plan(double.PositiveInfinity, 5000, 5000, 5000, 74, 70, 8));
    }

    [Fact]
    public void Plan_ShowsIconsBeforeReflowing()
    {
        // Issue #612: 200% text on a compact window used to stack; icon-only boxes leave difficulty the rest of one line.
        Assert.Equal(PathSelectorArrangement.IconOnly, PathSelectorLayout.Plan(420, 342, 150, 150, 74, 70, 8));
        Assert.Equal(PathSelectorArrangement.IconOnly, PathSelectorLayout.Plan(420, 212, 100, 93, 74, 70, 8));
        // Exactly fits icon-only: 74 + 260 + 70 + 16 = 420.
        Assert.Equal(PathSelectorArrangement.IconOnly, PathSelectorLayout.Plan(420, 342, 260, 150, 74, 70, 8));
    }

    [Fact]
    public void Plan_ReflowsOnlyWhenEvenIconsDoNotFit()
    {
        Assert.Equal(PathSelectorArrangement.Stacked, PathSelectorLayout.Plan(420, 342, 261, 150, 74, 70, 8));
        Assert.Equal(PathSelectorArrangement.Stacked, PathSelectorLayout.Plan(200, 212, 100, 92, 74, 70, 8));
    }
}
