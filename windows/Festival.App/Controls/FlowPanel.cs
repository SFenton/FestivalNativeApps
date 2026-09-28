using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Flow panel
/// <summary>
/// Wraps children onto as many lines as needed instead of clipping (status chips and metadata pills in narrow
/// rows). Each line aligns left or right per <see cref="LineAlignment"/>.
/// </summary>
public sealed partial class FlowPanel : Panel
{
    /// <summary>Space between items and lines in epx.</summary>
    public double Spacing { get; set; } = 6;

    /// <summary>Alignment of each wrapped line.</summary>
    public HorizontalAlignment LineAlignment { get; set; } = HorizontalAlignment.Left;

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        double width = 0, height = 0, lineWidth = 0, lineHeight = 0;
        foreach (var child in Children)
        {
            child.Measure(new Size(availableSize.Width, double.PositiveInfinity));
            var size = child.DesiredSize;
            if (lineWidth > 0 && lineWidth + Spacing + size.Width > availableSize.Width)
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
        var line = new List<UIElement>();
        double y = 0, lineWidth = 0, lineHeight = 0;
        foreach (var child in Children)
        {
            var size = child.DesiredSize;
            if (line.Count > 0 && lineWidth + Spacing + size.Width > finalSize.Width)
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

    /// <summary>Places one line, vertically centering each item.</summary>
    /// <param name="line">Items.</param>
    /// <param name="y">Top.</param>
    /// <param name="lineWidth">Total width.</param>
    /// <param name="lineHeight">Height.</param>
    /// <param name="width">Available width.</param>
    private void ArrangeLine(List<UIElement> line, double y, double lineWidth, double lineHeight, double width)
    {
        var x = LineAlignment == HorizontalAlignment.Right ? Math.Max(0, width - lineWidth) : 0;
        foreach (var child in line)
        {
            var size = child.DesiredSize;
            child.Arrange(new Rect(x, y + (lineHeight - size.Height) / 2, size.Width, size.Height));
            x += size.Width + Spacing;
        }
    }
}
#endregion
