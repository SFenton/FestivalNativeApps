namespace Festival.Core.Domain;

#region Card row alignment
/// <summary>
/// Header alignment for cards placed side by side in a grid row (pattern <c>section-headers</c> R14, issue #657): every
/// titled card in a row takes the row's tallest header height, so the titles sit on one line and the card surfaces
/// (and their first rows) start on one line even when one header is taller (a combo board's icon row, a wrapped title).
/// A single column aligns nothing.
/// </summary>
public static class CardRowAlignment
{
    /// <summary>Header height each card should take.</summary>
    /// <param name="naturalHeights">
    /// Each card's own header height in grid order, or <see langword="null"/> for a card without a header (it neither
    /// sets nor takes the row height).
    /// </param>
    /// <param name="columns">Cards per row (values below 2 align nothing).</param>
    /// <returns>
    /// Per card, the row's tallest header height, or 0 for a card without a header and for every card in one column.
    /// </returns>
    public static double[] HeaderHeights(IReadOnlyList<double?> naturalHeights, int columns)
    {
        var result = new double[naturalHeights.Count];
        if (columns < 2) return result;
        for (var start = 0; start < naturalHeights.Count; start += columns)
        {
            var end = Math.Min(start + columns, naturalHeights.Count);
            double tallest = 0;
            for (var i = start; i < end; i++) tallest = Math.Max(tallest, naturalHeights[i] ?? 0);
            for (var i = start; i < end; i++) result[i] = naturalHeights[i] is null ? 0 : tallest;
        }
        return result;
    }

    /// <summary>Space a header adds above its content to reach its row's height.</summary>
    /// <param name="rowHeight">The row's header height from <see cref="HeaderHeights"/>.</param>
    /// <param name="naturalHeight">The header's own height.</param>
    /// <returns>The difference, never negative.</returns>
    public static double TopInset(double rowHeight, double naturalHeight) => Math.Max(0, rowHeight - naturalHeight);
}
#endregion
