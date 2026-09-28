using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Wrap panel
/// <summary>Left-to-right panel that wraps children onto new lines (rival pills at narrow widths).</summary>
public sealed partial class WrapPanel : Panel
{
    /// <summary>Gap between items on a line.</summary>
    public double HorizontalSpacing { get; set; } = 6;

    /// <summary>Gap between lines.</summary>
    public double VerticalSpacing { get; set; } = 4;

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize) => Layout(availableSize.Width, arrange: false);

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        Layout(finalSize.Width, arrange: true);
        return finalSize;
    }

    /// <summary>Measures or arranges children line by line, centring each item vertically within its line.</summary>
    /// <param name="width">Available width.</param>
    /// <param name="arrange">Whether to arrange (otherwise measure).</param>
    /// <returns>Used size.</returns>
    private Size Layout(double width, bool arrange)
    {
        var lines = new List<(List<UIElement> Items, double Height)>();
        var current = new List<UIElement>();
        double x = 0, line = 0, used = 0;
        foreach (var child in Children)
        {
            if (!arrange) child.Measure(new Size(width, double.PositiveInfinity));
            if (child.Visibility == Visibility.Collapsed) continue;
            var size = child.DesiredSize;
            if (x > 0 && x + size.Width > width)
            {
                lines.Add((current, line));
                current = [];
                x = 0;
                line = 0;
            }
            current.Add(child);
            x += size.Width + HorizontalSpacing;
            used = Math.Max(used, x - HorizontalSpacing);
            line = Math.Max(line, size.Height);
        }
        if (current.Count > 0) lines.Add((current, line));

        double y = 0;
        foreach (var (items, height) in lines)
        {
            if (arrange)
            {
                double left = 0;
                foreach (var item in items)
                {
                    var size = item.DesiredSize;
                    item.Arrange(new Rect(left, y + (height - size.Height) / 2, Math.Min(size.Width, width), size.Height));
                    left += size.Width + HorizontalSpacing;
                }
            }
            y += height + VerticalSpacing;
        }
        var total = lines.Count == 0 ? 0 : y - VerticalSpacing;
        return new Size(double.IsInfinity(width) ? used : Math.Min(used, width), total);
    }
}
#endregion
