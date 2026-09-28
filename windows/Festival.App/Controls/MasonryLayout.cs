using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Masonry layout
/// <summary>
/// Column-packing layout for a handful of variable-height cards (Rivals sections and categories): as many columns
/// as fit <see cref="MinColumnWidth"/>, each card placed in the shortest column so cards never stretch to a shared
/// row height. Non-virtualizing: intended for at most a few dozen items. Reading order stays the item order.
/// </summary>
public sealed partial class MasonryLayout : NonVirtualizingLayout
{
    private readonly List<Rect> slots = [];

    /// <summary>Smallest column width in DIPs.</summary>
    public double MinColumnWidth { get; set; } = 360;

    /// <summary>Horizontal gap.</summary>
    public double ColumnSpacing { get; set; } = 16;

    /// <summary>Vertical gap.</summary>
    public double RowSpacing { get; set; } = 16;

    /// <summary>Largest column count (0 = unlimited).</summary>
    public int MaxColumns { get; set; }

    /// <inheritdoc />
    protected override Size MeasureOverride(NonVirtualizingLayoutContext context, Size availableSize)
    {
        var width = double.IsInfinity(availableSize.Width) ? MinColumnWidth : availableSize.Width;
        var columns = Math.Max(1, (int)((width + ColumnSpacing) / (MinColumnWidth + ColumnSpacing)));
        if (MaxColumns > 0) columns = Math.Min(columns, MaxColumns);
        columns = Math.Min(columns, Math.Max(1, context.Children.Count));
        var columnWidth = Math.Max(0, (width - (columns - 1) * ColumnSpacing) / columns);
        var heights = new double[columns];
        slots.Clear();
        foreach (var child in context.Children)
        {
            child.Measure(new Size(columnWidth, double.PositiveInfinity));
            var column = Array.IndexOf(heights, heights.Min());
            var top = heights[column] == 0 ? 0 : heights[column] + RowSpacing;
            slots.Add(new Rect(column * (columnWidth + ColumnSpacing), top, columnWidth, child.DesiredSize.Height));
            heights[column] = top + child.DesiredSize.Height;
        }
        return new Size(width, heights.Max());
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(NonVirtualizingLayoutContext context, Size finalSize)
    {
        for (var i = 0; i < context.Children.Count && i < slots.Count; i++) context.Children[i].Arrange(slots[i]);
        return finalSize;
    }
}
#endregion
