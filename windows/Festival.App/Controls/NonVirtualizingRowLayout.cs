using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Non-virtualizing row layout
/// <summary>
/// A horizontal <see cref="StackLayout"/> for a short, bounded <see cref="ItemsRepeater"/> row nested in a scrolled card
/// or row (a band member's instrument icons): items left to right at their desired widths, <see cref="Spacing"/> apart,
/// each as tall as the row. Non-virtualizing, so the repeater does not follow its effective viewport while the page
/// scrolls (issue #668): with a virtualizing <see cref="StackLayout"/>, a page of band cards whose rows nest these
/// repeaters re-measured them on every scroll frame (Player Bands p95 99–141 ms, up to 480 ms stalls). The vertical
/// equivalent is <see cref="LeaderboardsCardGridLayout"/> with <c>MaxColumns="1" MinColumnWidth="0"</c>.
/// </summary>
public sealed partial class NonVirtualizingRowLayout : NonVirtualizingLayout
{
    /// <summary>Gap between items in effective pixels.</summary>
    public double Spacing { get; set; }

    /// <inheritdoc />
    protected override Size MeasureOverride(NonVirtualizingLayoutContext context, Size availableSize)
    {
        var childSize = new Size(double.PositiveInfinity, availableSize.Height);
        double width = 0, height = 0;
        var children = context.Children;
        for (var i = 0; i < children.Count; i++)
        {
            children[i].Measure(childSize);
            width += children[i].DesiredSize.Width + (i > 0 ? Spacing : 0);
            height = Math.Max(height, children[i].DesiredSize.Height);
        }
        return new Size(width, height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(NonVirtualizingLayoutContext context, Size finalSize)
    {
        double x = 0;
        foreach (var child in context.Children)
        {
            child.Arrange(new Rect(x, 0, child.DesiredSize.Width, finalSize.Height));
            x += child.DesiredSize.Width + Spacing;
        }
        return finalSize;
    }
}
#endregion
