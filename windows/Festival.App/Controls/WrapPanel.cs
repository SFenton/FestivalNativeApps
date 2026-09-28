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

    /// <summary>Measures or arranges children line by line.</summary>
    /// <param name="width">Available width.</param>
    /// <param name="arrange">Whether to arrange (otherwise measure).</param>
    /// <returns>Used size.</returns>
    private Size Layout(double width, bool arrange)
    {
        double x = 0, y = 0, line = 0, used = 0;
        foreach (var child in Children)
        {
            if (!arrange) child.Measure(new Size(width, double.PositiveInfinity));
            var size = child.DesiredSize;
            if (child.Visibility == Visibility.Collapsed) continue;
            if (x > 0 && x + size.Width > width)
            {
                x = 0;
                y += line + VerticalSpacing;
                line = 0;
            }
            if (arrange) child.Arrange(new Rect(x, y, Math.Min(size.Width, width), size.Height));
            x += size.Width + HorizontalSpacing;
            used = Math.Max(used, x - HorizontalSpacing);
            line = Math.Max(line, size.Height);
        }
        return new Size(double.IsInfinity(width) ? used : Math.Min(used, width), y + line);
    }
}
#endregion
