namespace Festival.Core.Domain;

#region Policy
/// <summary>
/// Windows form of pattern <c>wide-columns</c> R1 (issue #653; Apple <c>WideColumns.swift</c>, Android
/// <c>WideColumns.kt</c>, #581): a page's repeated cards flow into two equal row-major columns (card 1 left, card 2
/// right, card 3 left on the next row) under full-width headings in a wide window, and stay one column otherwise.
/// Windows has no orientation, so the Fluent Large breakpoint (window width ≥ 1008 epx, where the navigation pane
/// expands) stands in for landscape; both columns must still keep <see cref="MinimumColumnWidth"/>, and accessibility
/// text sizes (<see cref="LargeText"/>, 150% and above) keep one column.
/// </summary>
public static class WideColumns
{
    /// <summary>Narrowest column in epx (the 320 shared with Apple and Android).</summary>
    public const double MinimumColumnWidth = 320;

    /// <summary>Narrowest window in epx that uses two columns (Fluent Large breakpoint; Windows' stand-in for landscape).</summary>
    public const double MinimumWindowWidth = 1008;

    /// <summary>Columns for a page's repeated cards.</summary>
    /// <param name="windowWidth">App window width in epx.</param>
    /// <param name="contentWidth">Width the cards share, in epx.</param>
    /// <param name="textScale">Windows text size factor (1 = 100%).</param>
    /// <param name="spacing">Gutter between the two columns, in epx.</param>
    /// <returns>
    /// 2 when the window is at least <see cref="MinimumWindowWidth"/>, the text is below <see cref="LargeText.Scale"/> and
    /// each column keeps <see cref="MinimumColumnWidth"/>; otherwise 1.
    /// </returns>
    public static int Count(double windowWidth, double contentWidth, double textScale, double spacing) =>
        windowWidth >= MinimumWindowWidth && !LargeText.Applies(textScale)
            && (contentWidth - spacing) / 2 >= MinimumColumnWidth ? 2 : 1;

    /// <summary>The row (line) that shows an item.</summary>
    /// <param name="index">Item index.</param>
    /// <param name="columns">Columns (at least 1).</param>
    /// <returns>Zero-based row.</returns>
    public static int RowOf(int index, int columns) => index / Math.Max(1, columns);

    /// <summary>The first item of a row.</summary>
    /// <param name="row">Zero-based row.</param>
    /// <param name="columns">Columns (at least 1).</param>
    /// <returns>Item index.</returns>
    public static int RowStart(int row, int columns) => row * Math.Max(1, columns);

    /// <summary>Row count for a number of items.</summary>
    /// <param name="count">Items.</param>
    /// <param name="columns">Columns (at least 1).</param>
    /// <returns>Rows (the last one may be partly filled).</returns>
    public static int RowCount(int count, int columns) => (Math.Max(0, count) + Math.Max(1, columns) - 1) / Math.Max(1, columns);

    /// <summary>Splits items into row-major rows (Android <c>WideColumnLines</c>).</summary>
    /// <typeparam name="T">Item type.</typeparam>
    /// <param name="items">Items in reading order.</param>
    /// <param name="columns">Columns (at least 1).</param>
    /// <returns>Rows in order; only the last may hold fewer than <paramref name="columns"/> items.</returns>
    public static IReadOnlyList<IReadOnlyList<T>> Rows<T>(IReadOnlyList<T> items, int columns)
    {
        var size = Math.Max(1, columns);
        var rows = new List<IReadOnlyList<T>>(RowCount(items.Count, size));
        for (var start = 0; start < items.Count; start += size)
            rows.Add(items.Skip(start).Take(size).ToArray());
        return rows;
    }
}
#endregion
