namespace Festival.Core.Domain;

#region Songs pinned section header
/// <summary>
/// Picks the label for the Songs list's pinned section header (issue #48, cross-platform check of #9): the section
/// holding the first row that is actually visible below the list's top edge. The list panel's first-visible index can
/// still describe the pre-jump layout when a jump-index pick finishes, so the page reads the realized rows' geometry
/// instead and maps the first visible row to its section.
/// </summary>
public static class SongSectionHeader
{
    /// <summary>A realized row container.</summary>
    /// <param name="Index">Flat row index.</param>
    /// <param name="Top">Top edge relative to the viewport top.</param>
    /// <param name="Bottom">Bottom edge relative to the viewport top.</param>
    public readonly record struct RealizedRow(int Index, double Top, double Bottom);

    /// <summary>A row whose bottom edge is within this many pixels of the top edge counts as scrolled away.</summary>
    public const double Tolerance = 1;

    /// <summary>Returns the index of the section that holds <paramref name="row"/>.</summary>
    /// <param name="sectionStarts">Ascending first-row index of each section.</param>
    /// <param name="row">Flat row index.</param>
    /// <returns>Section index, or -1 when there are no sections.</returns>
    public static int SectionAt(IReadOnlyList<int> sectionStarts, int row)
    {
        if (sectionStarts.Count == 0) return -1;
        int low = 0, high = sectionStarts.Count - 1;
        while (low < high)
        {
            var mid = (low + high + 1) / 2;
            if (sectionStarts[mid] <= row) low = mid;
            else high = mid - 1;
        }
        return low;
    }

    /// <summary>
    /// Finds the first row actually visible in the list viewport from the realized rows' geometry, so a first-visible
    /// index that still describes the layout before a jump cannot win. Rows whose bottom edge is within
    /// <see cref="Tolerance"/> of the top edge, or that start below the viewport, do not count.
    /// </summary>
    /// <param name="fallback">The panel's first-visible index, used when no realized row is in view.</param>
    /// <param name="count">Row count.</param>
    /// <param name="realized">Realized rows with edges relative to the viewport top.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>Index of the first visible row, clamped to the rows.</returns>
    public static int FirstVisibleRow(int fallback, int count, IEnumerable<RealizedRow> realized, double viewportHeight)
    {
        if (count <= 0) return 0;
        var first = -1;
        foreach (var row in realized)
            if (row.Index >= 0 && row.Index < count && row.Bottom > Tolerance && row.Top < viewportHeight
                && (first < 0 || row.Index < first))
                first = row.Index;
        return first >= 0 ? first : Math.Clamp(fallback, 0, count - 1);
    }

    /// <summary>Maps a first-visible row to its section label.</summary>
    /// <param name="sectionStarts">Ascending first-row index of each section.</param>
    /// <param name="labels">Section labels, parallel to <paramref name="sectionStarts"/>.</param>
    /// <param name="fallback">The panel's first-visible index, used when no realized row is in view.</param>
    /// <param name="count">Row count.</param>
    /// <param name="realized">Realized rows with edges relative to the viewport top.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>The label, or an empty string without sections.</returns>
    public static string Label(IReadOnlyList<int> sectionStarts, IReadOnlyList<string> labels, int fallback, int count,
        IEnumerable<RealizedRow> realized, double viewportHeight)
    {
        var section = SectionAt(sectionStarts, FirstVisibleRow(fallback, count, realized, viewportHeight));
        return section >= 0 && section < labels.Count ? labels[section] : "";
    }
}
#endregion
