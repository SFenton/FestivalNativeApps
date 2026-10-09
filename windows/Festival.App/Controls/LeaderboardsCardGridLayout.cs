using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Card grid layout
/// <summary>
/// Adaptive card grid for <see cref="ItemsRepeater"/>: as many equal-width columns as fit
/// <see cref="MinColumnWidth"/> (one at compact widths), each row as tall as its tallest card. Unlike
/// <see cref="UniformGridLayout"/>, which sizes every item from the first, cards of different heights
/// (spotlight rows, failures, three- and four-member band rows) never clip. Non-virtualizing: the Leaderboards
/// overview has at most twelve cards and Song Detail at most one per instrument and band size. With
/// <see cref="MaxColumns"/> 1 and <see cref="MinColumnWidth"/> 0 it is a plain non-virtualizing stack, used for the
/// top-ten rows inside cached pages' cards: a virtualizing <see cref="StackLayout"/> drops off-screen rows while the
/// page is away and re-estimates their heights on Back, which moved the page (#276). Player Profile stacks its instrument
/// sections and band groups the same way: re-estimating them near the page end pulled the scroll back (#533).
/// </summary>
public sealed partial class LeaderboardsCardGridLayout : NonVirtualizingLayout
{
    /// <summary>Smallest column width in effective pixels.</summary>
    public double MinColumnWidth { get; set; } = 360;

    /// <summary>
    /// Multiplies <see cref="MinColumnWidth"/> by the Windows text size (issue #207), so cards whose rows grow with text
    /// get fewer, wider columns instead of squeezing names out.
    /// </summary>
    public bool ScaleWithText { get; set; }

    /// <summary>Largest number of columns.</summary>
    public int MaxColumns { get; set; } = 4;

    /// <summary>Gap between cards.</summary>
    public double Spacing { get; set; } = 16;

    /// <inheritdoc />
    protected override Size MeasureOverride(NonVirtualizingLayoutContext context, Size availableSize)
    {
        var children = context.Children;
        var width = double.IsInfinity(availableSize.Width) ? MinColumnWidth : availableSize.Width;
        var columns = Columns(width);
        var columnWidth = ColumnWidth(width, columns);
        double height = 0, rowHeight = 0;
        for (var i = 0; i < children.Count; i++)
        {
            children[i].Measure(new Size(columnWidth, double.PositiveInfinity));
            rowHeight = Math.Max(rowHeight, children[i].DesiredSize.Height);
            if (i % columns == columns - 1 || i == children.Count - 1)
            {
                height += rowHeight + (height > 0 ? Spacing : 0);
                rowHeight = 0;
            }
        }
        return new Size(width, height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(NonVirtualizingLayoutContext context, Size finalSize)
    {
        var children = context.Children;
        var columns = Columns(finalSize.Width);
        var columnWidth = ColumnWidth(finalSize.Width, columns);
        double y = 0;
        for (var start = 0; start < children.Count; start += columns)
        {
            var end = Math.Min(start + columns, children.Count);
            double rowHeight = 0;
            for (var i = start; i < end; i++) rowHeight = Math.Max(rowHeight, children[i].DesiredSize.Height);
            for (var i = start; i < end; i++)
                children[i].Arrange(new Rect((i - start) * (columnWidth + Spacing), y, columnWidth, rowHeight));
            y += rowHeight + Spacing;
        }
        return finalSize;
    }

    /// <summary>Columns that fit the width.</summary>
    /// <param name="width">Available width.</param>
    /// <returns>1…<see cref="MaxColumns"/>.</returns>
    private int Columns(double width) =>
        Math.Clamp((int)Math.Floor((width + Spacing) / (EffectiveMinColumnWidth + Spacing)), 1, Math.Max(1, MaxColumns));

    /// <summary>Minimum column width after text scaling.</summary>
    private double EffectiveMinColumnWidth => ScaleWithText ? MinColumnWidth * TextScaleLayout.Factor : MinColumnWidth;

    /// <summary>Equal column width.</summary>
    /// <param name="width">Available width.</param>
    /// <param name="columns">Column count.</param>
    /// <returns>Width per column.</returns>
    private double ColumnWidth(double width, int columns) => Math.Max(0, (width - (columns - 1) * Spacing) / columns);
}
#endregion
