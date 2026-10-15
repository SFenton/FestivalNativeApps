namespace Festival.Core.Tests;

/// <summary>Windows form of pattern wide-columns R1/R2 (issue #653).</summary>
public class WideColumnsTests
{
    [Theory]
    [InlineData(1008, 720, 1.0, 20, 2)] // Fluent Large breakpoint, expanded navigation pane: two 350 epx columns
    [InlineData(1007.9, 720, 1.0, 20, 1)] // below it (Windows' stand-in for portrait): one column even when it would fit
    [InlineData(900, 804, 1.0, 20, 1)] // the medium preset
    [InlineData(1440, 1152, 1.0, 20, 2)] // the wide preset
    [InlineData(1920, 1232, 1.49, 20, 2)]
    [InlineData(1920, 1232, 1.5, 20, 1)] // accessibility text sizes keep one column
    [InlineData(1920, 1232, 2.25, 16, 1)]
    [InlineData(1200, 660, 1.0, 20, 2)] // exactly two 320 epx columns and the gutter
    [InlineData(1200, 659, 1.0, 20, 1)]
    [InlineData(1200, 655, 1.0, 16, 1)]
    [InlineData(1200, 656, 1.0, 16, 2)]
    public void Count_FollowsWindowContentAndTextSize(double window, double content, double textScale, double spacing, int expected) =>
        Assert.Equal(expected, WideColumns.Count(window, content, textScale, spacing));

    [Fact]
    public void Rows_AreRowMajorWithAShortLastRow()
    {
        var rows = WideColumns.Rows([1, 2, 3, 4, 5], 2);
        Assert.Equal([[1, 2], [3, 4], [5]], rows.Select(r => r.ToArray()).ToArray());
        Assert.Equal([[1], [2], [3]], WideColumns.Rows([1, 2, 3], 1).Select(r => r.ToArray()).ToArray());
        Assert.Empty(WideColumns.Rows(Array.Empty<int>(), 2));
    }

    [Theory]
    [InlineData(0, 2, 0, 0)]
    [InlineData(1, 2, 0, 0)]
    [InlineData(2, 2, 1, 2)]
    [InlineData(5, 2, 2, 4)]
    [InlineData(5, 1, 5, 5)]
    [InlineData(3, 0, 3, 3)] // a zero count is treated as one column
    public void RowOf_AndRowStart(int index, int columns, int row, int start)
    {
        Assert.Equal(row, WideColumns.RowOf(index, columns));
        Assert.Equal(start, WideColumns.RowStart(WideColumns.RowOf(index, columns), columns));
    }

    [Theory]
    [InlineData(0, 2, 0)]
    [InlineData(1, 2, 1)]
    [InlineData(4, 2, 2)]
    [InlineData(5, 2, 3)]
    [InlineData(5, 1, 5)]
    public void RowCount_RoundsUp(int count, int columns, int rows) => Assert.Equal(rows, WideColumns.RowCount(count, columns));
}
