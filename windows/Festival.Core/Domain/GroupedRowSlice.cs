namespace Festival.Core.Domain;

#region Grouped row slice
/// <summary>
/// One row's part of a board's single grouped card (issue #543, owner-approved <c>leaderboard-row</c> variant): the first
/// row draws the card's rounded top, the last its rounded bottom, middle rows only its sides, and a hairline separates
/// each row from the one above it. The selected player's row draws a full purple outline in place, so the hairlines next
/// to it hide. Each row draws its own slice, so virtualized lists keep recycling rows and nothing wraps the list.
/// <para>
/// An in-card slice (<paramref name="InCard"/>, issue #588) is a row inside a card that already draws the surface and
/// outline (Song Detail's Score History card, like Apple's flush <c>FestivalGlassSection</c> rows): it draws no outline
/// or surface of its own, only the hairline, and the selected row's purple fill and outline with Fluent's
/// <c>ControlCornerRadius</c> corners, like a list item inside a card.
/// </para>
/// </summary>
/// <param name="IsFirst">Whether the row is the card's top row.</param>
/// <param name="IsLast">Whether the row is the card's bottom row.</param>
/// <param name="ShowSeparator">Whether the hairline above the row shows.</param>
/// <param name="IsSelected">Whether the row is the selected player's (full outline, its own stroke brush).</param>
/// <param name="InCard">Whether the rows sit inside a card that owns the surface and outline.</param>
public readonly record struct GroupedRowSlice(bool IsFirst, bool IsLast, bool ShowSeparator, bool IsSelected, bool InCard = false)
{
    /// <summary>The card's corner radius, the same as the floating pinned row and the standalone row (epx).</summary>
    public const double CornerRadius = 12;

    /// <summary>An in-card row's corner radius: Fluent <c>ControlCornerRadius</c>, as for a list item in a card (epx).</summary>
    public const double InCardCornerRadius = 4;

    /// <summary>The card's outline thickness (epx).</summary>
    public const double Stroke = 1;

    /// <summary>The hairline's inset from each side of the card (epx), aligned with the rows' content padding.</summary>
    public const double SeparatorInset = 12;

    /// <summary>Works out a row's slice from its position.</summary>
    /// <param name="index">Row index in the card (clamped to the card).</param>
    /// <param name="count">Rows in the card (at least one is assumed).</param>
    /// <param name="selected">Whether the row is the selected player's.</param>
    /// <param name="previousSelected">Whether the row above is the selected player's.</param>
    /// <param name="inCard">Whether the rows sit inside a card that owns the surface and outline.</param>
    /// <returns>The slice.</returns>
    public static GroupedRowSlice For(int index, int count, bool selected, bool previousSelected, bool inCard = false)
    {
        var last = Math.Max(count, 1) - 1;
        var at = Math.Clamp(index, 0, last);
        return new GroupedRowSlice(at == 0, at == last, at > 0 && !selected && !previousSelected, selected, inCard);
    }

    /// <summary>Radius of the slice's top corners (epx).</summary>
    public double TopRadius => InCard ? InCardCornerRadius : IsFirst ? CornerRadius : 0;

    /// <summary>Radius of the slice's bottom corners (epx).</summary>
    public double BottomRadius => InCard ? InCardCornerRadius : IsLast ? CornerRadius : 0;

    /// <summary>Top outline thickness: the card's top edge, or the selected row's own outline (epx).</summary>
    public double TopStroke => IsSelected || !InCard && IsFirst ? Stroke : 0;

    /// <summary>Bottom outline thickness: the card's bottom edge, or the selected row's own outline (epx).</summary>
    public double BottomStroke => IsSelected || !InCard && IsLast ? Stroke : 0;

    /// <summary>Side outline thickness: the card's sides on a board, only the selected row's own outline in a card (epx).</summary>
    public double SideStroke => IsSelected || !InCard ? Stroke : 0;
}
#endregion
