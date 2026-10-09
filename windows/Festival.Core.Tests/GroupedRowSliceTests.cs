using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #543: a board's rows read as one grouped card. The first row owns the rounded top, the last the rounded bottom,
/// hairlines separate rows, and the selected player's row keeps a full outline with no hairline beside it.
/// </summary>
public class GroupedRowSliceTests
{
    [Fact]
    public void SingleRow_IsAWholeCard()
    {
        var slice = GroupedRowSlice.For(0, 1, selected: false, previousSelected: false);
        Assert.True(slice.IsFirst);
        Assert.True(slice.IsLast);
        Assert.False(slice.ShowSeparator);
        Assert.Equal((12, 12, 1, 1), (slice.TopRadius, slice.BottomRadius, slice.TopStroke, slice.BottomStroke));
    }

    [Fact]
    public void FirstRow_OwnsTheRoundedTopAndNoHairline()
    {
        var slice = GroupedRowSlice.For(0, 25, false, false);
        Assert.Equal((12, 0, 1, 0), (slice.TopRadius, slice.BottomRadius, slice.TopStroke, slice.BottomStroke));
        Assert.False(slice.ShowSeparator);
    }

    [Fact]
    public void MiddleRow_DrawsOnlySidesAndAHairline()
    {
        var slice = GroupedRowSlice.For(12, 25, false, false);
        Assert.Equal((0, 0, 0, 0), (slice.TopRadius, slice.BottomRadius, slice.TopStroke, slice.BottomStroke));
        Assert.True(slice.ShowSeparator);
    }

    [Fact]
    public void LastRow_OwnsTheRoundedBottom()
    {
        var slice = GroupedRowSlice.For(24, 25, false, false);
        Assert.Equal((0, 12, 0, 1), (slice.TopRadius, slice.BottomRadius, slice.TopStroke, slice.BottomStroke));
        Assert.True(slice.ShowSeparator);
    }

    [Fact]
    public void SelectedRow_HasAFullOutlineAndHidesTheHairlinesBesideIt()
    {
        var selected = GroupedRowSlice.For(5, 25, selected: true, previousSelected: false);
        Assert.True(selected.IsSelected);
        Assert.False(selected.ShowSeparator);
        Assert.Equal((0, 0, 1, 1), (selected.TopRadius, selected.BottomRadius, selected.TopStroke, selected.BottomStroke));

        var below = GroupedRowSlice.For(6, 25, selected: false, previousSelected: true);
        Assert.False(below.ShowSeparator);
        Assert.Equal((0, 0), (below.TopStroke, below.BottomStroke));
    }

    [Fact]
    public void SelectedFirstRow_KeepsTheCardsRoundedTop()
    {
        var slice = GroupedRowSlice.For(0, 25, selected: true, previousSelected: false);
        Assert.Equal((12, 0, 1, 1), (slice.TopRadius, slice.BottomRadius, slice.TopStroke, slice.BottomStroke));
    }

    [Theory]
    [InlineData(-1, 3, true, false)]
    [InlineData(7, 3, false, true)]
    [InlineData(0, 0, true, true)]
    public void OutOfRangePositions_Clamp(int index, int count, bool first, bool last)
    {
        var slice = GroupedRowSlice.For(index, count, false, false);
        Assert.Equal((first, last), (slice.IsFirst, slice.IsLast));
    }
}
