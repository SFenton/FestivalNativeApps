using Festival.Core.Domain;
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
        var visible = new List<UIElement>();
        foreach (var child in Children)
        {
            if (!arrange) child.Measure(new Size(width, double.PositiveInfinity));
            if (child.Visibility != Visibility.Collapsed) visible.Add(child);
        }
        // Shared rule (with a layout-rounding tolerance) so arrange never breaks a line that measure kept whole.
        var breaks = WrapLineLayout.Lines(visible.Select(c => c.DesiredSize.Width).ToArray(), width, HorizontalSpacing);
        var lines = new List<(List<UIElement> Items, double Height)>();
        double x = 0, used = 0;
        for (var i = 0; i < visible.Count; i++)
        {
            var size = visible[i].DesiredSize;
            if (i == 0 || breaks[i] != breaks[i - 1])
            {
                lines.Add(([], 0));
                x = 0;
            }
            var (items, height) = lines[^1];
            items.Add(visible[i]);
            lines[^1] = (items, Math.Max(height, size.Height));
            x += size.Width + HorizontalSpacing;
            used = Math.Max(used, x - HorizontalSpacing);
        }

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
