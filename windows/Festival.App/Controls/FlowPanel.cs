using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Flow panel
/// <summary>
/// Wraps children onto as many lines as needed instead of clipping (status chips and metadata pills in narrow
/// rows). Each line aligns left, right or centre per <see cref="LineAlignment"/>; with <see cref="BalanceLines"/> the
/// lines are evened out like the web's instrument chip rows (<see cref="InstrumentChipRows"/>, pattern
/// <c>instrument-chip-rows</c>).
/// </summary>
public sealed partial class FlowPanel : Panel
{
    /// <summary>Space between items and lines in epx.</summary>
    public double Spacing { get; set; } = 6;

    /// <summary>Alignment of each wrapped line (left, right or centre).</summary>
    public HorizontalAlignment LineAlignment
    {
        get => lineAlignment;
        set { if (lineAlignment != value) { lineAlignment = value; InvalidateArrange(); } }
    }

    /// <summary>
    /// Balance equal-width items over the fewest lines that fit them (nine chips read 5 + 4, not 7 + 2) instead of
    /// filling each line before the next.
    /// </summary>
    public bool BalanceLines
    {
        get => balanceLines;
        set { if (balanceLines != value) { balanceLines = value; InvalidateMeasure(); } }
    }

    private HorizontalAlignment lineAlignment = HorizontalAlignment.Left;
    private bool balanceLines;

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        foreach (var child in Children) child.Measure(new Size(availableSize.Width, double.PositiveInfinity));
        var lines = Lines(availableSize.Width);
        double width = 0, height = 0, lineWidth = 0, lineHeight = 0;
        for (var i = 0; i < Children.Count; i++)
        {
            var size = Children[i].DesiredSize;
            if (i > 0 && lines[i] != lines[i - 1])
            {
                width = Math.Max(width, lineWidth);
                height += lineHeight + Spacing;
                lineWidth = lineHeight = 0;
            }
            lineWidth += (lineWidth > 0 ? Spacing : 0) + size.Width;
            lineHeight = Math.Max(lineHeight, size.Height);
        }
        width = Math.Max(width, lineWidth);
        height += lineHeight;
        return new Size(double.IsInfinity(availableSize.Width) ? width : Math.Min(width, availableSize.Width), height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        var lines = Lines(finalSize.Width);
        var line = new List<UIElement>();
        double y = 0, lineWidth = 0, lineHeight = 0;
        for (var i = 0; i < Children.Count; i++)
        {
            var child = Children[i];
            var size = child.DesiredSize;
            if (line.Count > 0 && lines[i] != lines[i - 1])
            {
                ArrangeLine(line, y, lineWidth, lineHeight, finalSize.Width);
                y += lineHeight + Spacing;
                line.Clear();
                lineWidth = lineHeight = 0;
            }
            lineWidth += (line.Count > 0 ? Spacing : 0) + size.Width;
            lineHeight = Math.Max(lineHeight, size.Height);
            line.Add(child);
        }
        ArrangeLine(line, y, lineWidth, lineHeight, finalSize.Width);
        return finalSize;
    }

    /// <summary>Assigns each measured child to a line for the available width.</summary>
    /// <param name="available">Available width.</param>
    /// <returns>Zero-based line per child.</returns>
    private int[] Lines(double available)
    {
        var count = Children.Count;
        if (BalanceLines)
        {
            var item = 0d;
            foreach (var child in Children) item = Math.Max(item, child.DesiredSize.Width);
            return InstrumentChipRows.Lines(InstrumentChipRows.Split(count, available, item, Spacing));
        }
        var lines = new int[count];
        double lineWidth = 0;
        var index = 0;
        for (var i = 0; i < count; i++)
        {
            var width = Children[i].DesiredSize.Width;
            if (lineWidth > 0 && lineWidth + Spacing + width > available)
            {
                index++;
                lineWidth = 0;
            }
            lines[i] = index;
            lineWidth += (lineWidth > 0 ? Spacing : 0) + width;
        }
        return lines;
    }

    /// <summary>Places one line, vertically centering each item.</summary>
    /// <param name="line">Items.</param>
    /// <param name="y">Top.</param>
    /// <param name="lineWidth">Total width.</param>
    /// <param name="lineHeight">Height.</param>
    /// <param name="width">Available width.</param>
    private void ArrangeLine(List<UIElement> line, double y, double lineWidth, double lineHeight, double width)
    {
        var x = LineAlignment switch
        {
            HorizontalAlignment.Right => Math.Max(0, width - lineWidth),
            HorizontalAlignment.Center => Math.Max(0, (width - lineWidth) / 2),
            _ => 0,
        };
        foreach (var child in line)
        {
            var size = child.DesiredSize;
            child.Arrange(new Rect(x, y + (lineHeight - size.Height) / 2, size.Width, size.Height));
            x += size.Width + Spacing;
        }
    }
}
#endregion
