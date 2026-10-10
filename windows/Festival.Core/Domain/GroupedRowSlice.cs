namespace Festival.Core.Domain;

#region Grouped row slice
/// <summary>
/// One row's part of a board's single grouped card (issue #543, owner-approved <c>leaderboard-row</c> variant): the first
/// row draws the card's rounded top, the last its rounded bottom, middle rows only its sides, and a hairline separates
/// each row from the one above it. The selected player's row draws a full purple outline in place, so the hairlines next
/// to it hide. Each row draws its own slice, so virtualized lists keep recycling rows and nothing wraps the list.
/// </summary>
/// <param name="IsFirst">Whether the row is the card's top row.</param>
/// <param name="IsLast">Whether the row is the card's bottom row.</param>
/// <param name="ShowSeparator">Whether the hairline above the row shows.</param>
/// <param name="IsSelected">Whether the row is the selected player's (full outline, its own stroke brush).</param>
public readonly record struct GroupedRowSlice(bool IsFirst, bool IsLast, bool ShowSeparator, bool IsSelected)
{
    /// <summary>The card's corner radius, the same as the floating pinned row and the standalone row (epx).</summary>
    public const double CornerRadius = 12;

    /// <summary>The card's outline thickness (epx).</summary>
    public const double Stroke = 1;

    /// <summary>The hairline's inset from each side of the card (epx), aligned with the rows' content padding.</summary>
    public const double SeparatorInset = 12;

    /// <summary>Works out a row's slice from its position.</summary>
    /// <param name="index">Row index in the card (clamped to the card).</param>
    /// <param name="count">Rows in the card (at least one is assumed).</param>
    /// <param name="selected">Whether the row is the selected player's.</param>
    /// <param name="previousSelected">Whether the row above is the selected player's.</param>
    /// <returns>The slice.</returns>
    public static GroupedRowSlice For(int index, int count, bool selected, bool previousSelected)
    {
        var last = Math.Max(count, 1) - 1;
        var at = Math.Clamp(index, 0, last);
        return new GroupedRowSlice(at == 0, at == last, at > 0 && !selected && !previousSelected, selected);
    }

    /// <summary>Radius of the slice's top corners (epx).</summary>
    public double TopRadius => IsFirst ? CornerRadius : 0;

    /// <summary>Radius of the slice's bottom corners (epx).</summary>
    public double BottomRadius => IsLast ? CornerRadius : 0;

    /// <summary>Top outline thickness: the card's top edge, or the selected row's own outline (epx).</summary>
    public double TopStroke => IsFirst || IsSelected ? Stroke : 0;

    /// <summary>Bottom outline thickness: the card's bottom edge, or the selected row's own outline (epx).</summary>
    public double BottomStroke => IsLast || IsSelected ? Stroke : 0;
}
#endregion
