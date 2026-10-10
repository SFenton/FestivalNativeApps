using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Grouped rows
/// <summary>A row that draws its slice of a board's single grouped card (issue #543).</summary>
public interface IGroupedRow
{
    /// <summary>The row's slice, or <see langword="null"/> for a standalone row card.</summary>
    GroupedRowSlice? Slice { set; }
}

/// <summary>
/// One grouped card per board (issue #543, owner-approved <c>leaderboard-row</c> variant): every row draws its
/// <see cref="GroupedRowSlice"/> (rounded top on the first row, rounded bottom on the last, side strokes between,
/// a hairline above each row except beside the selected player's), and the rows touch. Nothing wraps the list, so
/// virtualization, the staggered entrance, the load swap, <c>BoardFooter.Inset</c> and the footer fade work as for
/// separate row cards. <c>controls:GroupedRows.IsEnabled="True"</c> on an <see cref="ItemsRepeater"/> (with
/// <c>StackLayout Spacing="0"</c>) slices each realized row; a ListView page calls <see cref="Apply"/> from
/// <c>ContainerContentChanging</c>. Rows opt in by implementing <see cref="IGroupedRow"/>, or with a template root
/// <see cref="Grid"/> (its corners and outline) and an element named <c>RowSeparator</c> (the hairline).
/// </summary>
public static class GroupedRows
{
    /// <summary>Attached switch for an <see cref="ItemsRepeater"/>.</summary>
    public static readonly DependencyProperty IsEnabledProperty = DependencyProperty.RegisterAttached(
        "IsEnabled", typeof(bool), typeof(GroupedRows), new PropertyMetadata(false, OnIsEnabledChanged));

    /// <summary>Reads the switch.</summary>
    /// <param name="element">Repeater.</param>
    /// <returns>Whether the repeater's rows form one card.</returns>
    public static bool GetIsEnabled(DependencyObject element) => (bool)element.GetValue(IsEnabledProperty);

    /// <summary>Sets the switch.</summary>
    /// <param name="element">Repeater.</param>
    /// <param name="value">Whether the repeater's rows form one card.</param>
    public static void SetIsEnabled(DependencyObject element, bool value) => element.SetValue(IsEnabledProperty, value);

    /// <summary>Whether a row model is the selected player's (or band's) row.</summary>
    /// <param name="item">Row model.</param>
    /// <returns>Whether the row gets the selected outline.</returns>
    public static bool IsSelected(object? item) => item switch
    {
        ILeaderboardEntryRow row => row.IsSelected,
        SongBandRow band => band.IsSelected,
        _ => false,
    };

    /// <summary>Corners for a slice.</summary>
    /// <param name="slice">Slice.</param>
    /// <returns>Rounded top and/or bottom corners.</returns>
    public static CornerRadius Radius(GroupedRowSlice slice) =>
        new(slice.TopRadius, slice.TopRadius, slice.BottomRadius, slice.BottomRadius);

    /// <summary>Outline for a slice: both sides always, the top and bottom only on the card's edges or the selected row.</summary>
    /// <param name="slice">Slice.</param>
    /// <returns>Border thickness.</returns>
    public static Thickness Outline(GroupedRowSlice slice) =>
        new(GroupedRowSlice.Stroke, slice.TopStroke, GroupedRowSlice.Stroke, slice.BottomStroke);

    /// <summary>Works out a row's slice from its list.</summary>
    /// <param name="index">Row index.</param>
    /// <param name="count">Rows in the list.</param>
    /// <param name="item">Row model.</param>
    /// <param name="previous">Model of the row above, if any.</param>
    /// <returns>The slice.</returns>
    public static GroupedRowSlice SliceFor(int index, int count, object? item, object? previous) =>
        GroupedRowSlice.For(index, count, IsSelected(item), index > 0 && IsSelected(previous));

    /// <summary>Draws one row's slice.</summary>
    /// <param name="row">Row element: an <see cref="IGroupedRow"/>, or a template root <see cref="Grid"/>.</param>
    /// <param name="slice">Slice.</param>
    public static void Apply(UIElement row, GroupedRowSlice slice)
    {
        if (row is IGroupedRow grouped)
        {
            grouped.Slice = slice;
            return;
        }
        if (row is Grid grid)
        {
            grid.CornerRadius = Radius(slice);
            grid.BorderThickness = Outline(slice);
        }
        if (row is FrameworkElement element && element.FindName("RowSeparator") is UIElement line)
            line.Visibility = slice.ShowSeparator ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Hooks a repeater's realization events.</summary>
    /// <param name="d">Repeater.</param>
    /// <param name="e">Change.</param>
    private static void OnIsEnabledChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not ItemsRepeater repeater) return;
        repeater.ElementPrepared -= OnPrepared;
        repeater.ElementIndexChanged -= OnIndexChanged;
        if (e.NewValue is not true) return;
        repeater.ElementPrepared += OnPrepared;
        repeater.ElementIndexChanged += OnIndexChanged;
    }

    /// <summary>Slices a realized row. The boards replace their row lists, which re-prepares every realized row.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row and index.</param>
    private static void OnPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args) =>
        ApplyAt(sender, args.Element, args.Index);

    /// <summary>Re-slices a row that moved (insertions or removals above it).</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row and new index.</param>
    private static void OnIndexChanged(ItemsRepeater sender, ItemsRepeaterElementIndexChangedEventArgs args) =>
        ApplyAt(sender, args.Element, args.NewIndex);

    /// <summary>Slices the row at an index of a repeater.</summary>
    /// <param name="repeater">Repeater.</param>
    /// <param name="row">Row element.</param>
    /// <param name="index">Row index.</param>
    private static void ApplyAt(ItemsRepeater repeater, UIElement row, int index)
    {
        var source = repeater.ItemsSourceView;
        if (source is null || index < 0 || index >= source.Count) return;
        Apply(row, SliceFor(index, source.Count, source.GetAt(index), index > 0 ? source.GetAt(index - 1) : null));
    }
}
#endregion
