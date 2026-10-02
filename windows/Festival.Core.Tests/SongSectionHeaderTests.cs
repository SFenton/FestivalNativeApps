using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Pinned Songs section header after jump-index picks (issue #48).</summary>
public class SongSectionHeaderTests
{
    // 27 sections (#, A–Z) of 4 rows each, like the mock service's --large-catalogue fixture.
    private static readonly string[] Labels = ["#", .. Enumerable.Range('A', 26).Select(c => ((char)c).ToString())];
    private static readonly int[] Starts = Enumerable.Range(0, Labels.Length).Select(i => i * 4).ToArray();
    private static readonly int Count = Labels.Length * 4;
    private const double Row = 100;

    private const double Viewport = 700;

    /// <summary>Realized rows <paramref name="first"/>..<paramref name="last"/> laid out with section <paramref name="top"/>'s header at the viewport top.</summary>
    private static List<SongSectionHeader.RealizedRow> Layout(int top, int first, int last, double headerGap = 60) =>
        Enumerable.Range(first, last - first + 1).Select(row =>
        {
            var bottom = (row - top * 4 + 1) * Row + headerGap * (row / 4 - top + 1);
            return new SongSectionHeader.RealizedRow(row, bottom - Row, bottom);
        }).ToList();

    private static string Label(int fallback, IEnumerable<SongSectionHeader.RealizedRow> rows) =>
        SongSectionHeader.Label(Starts, Labels, fallback, Count, rows, Viewport);

    [Fact]
    public void SectionAt_MapsRowsToTheirSection()
    {
        Assert.Equal(-1, SongSectionHeader.SectionAt([], 3));
        Assert.Equal(0, SongSectionHeader.SectionAt(Starts, 0));
        Assert.Equal(0, SongSectionHeader.SectionAt(Starts, 3));
        Assert.Equal(1, SongSectionHeader.SectionAt(Starts, 4));
        Assert.Equal(26, SongSectionHeader.SectionAt(Starts, Count - 1));
        // An empty (hidden) section shares its start with the next one: the visible, later section wins.
        Assert.Equal(2, SongSectionHeader.SectionAt([0, 4, 4, 8], 4));
    }

    [Fact]
    public void FarJump_HashToP_ShowsP()
    {
        // # → P: the panel may still report row 0 from before the jump; the realized rows put P on top.
        var p = Array.IndexOf(Labels, "P");
        Assert.Equal("P", Label(0, Layout(p, p * 4 - 6, p * 4 + 12)));
    }

    [Fact]
    public void BackwardJump_RToB_DropsTheStaleSectionAbove()
    {
        // Reproduced on Windows: R → B left "A" pinned; the panel's index was A's last row, which ends at the top edge.
        var b = Array.IndexOf(Labels, "B");
        var rows = Layout(b, 0, 20);
        Assert.Equal(0, rows.Single(r => r.Index == b * 4 - 1).Bottom);
        Assert.Equal("B", Label(b * 4 - 1, rows));
    }

    [Fact]
    public void StaleIndexBelowTheTop_MovesBackToTheVisibleRow()
    {
        var v = Array.IndexOf(Labels, "V");
        Assert.Equal("V", Label(v * 4 + 6, Layout(v, v * 4 - 4, v * 4 + 10)));
    }

    [Fact]
    public void BottomOut_JumpToZ_ShowsTheSectionAtTheTop()
    {
        // Z cannot reach the top: Y's last row still shows 30 px there, so the header says Y.
        var rows = Enumerable.Range(96, 12).Select(row => new SongSectionHeader.RealizedRow(row, (row - 103) * Row - 70, (row - 103) * Row + 30));
        Assert.Equal("Y", Label(104, rows));
    }

    [Fact]
    public void Edges_WithinToleranceOrBelowTheViewport_DoNotCount()
    {
        SongSectionHeader.RealizedRow[] rows =
        [
            new(8, -99, SongSectionHeader.Tolerance),
            new(9, 1, 101),
            new(30, Viewport, Viewport + 100),
        ];
        Assert.Equal(9, SongSectionHeader.FirstVisibleRow(30, Count, rows, Viewport));
        Assert.Equal(12, SongSectionHeader.FirstVisibleRow(12, Count, [new(30, Viewport + 1, Viewport + 101)], Viewport));
    }

    [Fact]
    public void NoRealizedRows_UsesTheClampedPanelIndex()
    {
        Assert.Equal(12, SongSectionHeader.FirstVisibleRow(12, Count, [], Viewport));
        Assert.Equal(Count - 1, SongSectionHeader.FirstVisibleRow(500, Count, [], Viewport));
        Assert.Equal(0, SongSectionHeader.FirstVisibleRow(-1, Count, [new(-1, 0, 100)], Viewport));
        Assert.Equal(0, SongSectionHeader.FirstVisibleRow(5, 0, [], Viewport));
        Assert.Equal("", SongSectionHeader.Label([], [], 0, 0, [], Viewport));
    }
}
