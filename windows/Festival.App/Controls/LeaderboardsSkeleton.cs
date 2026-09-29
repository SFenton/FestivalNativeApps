using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Festival.App.Controls;

#region Skeleton
/// <summary>
/// Five static placeholder rows shown while a card loads. Static on purpose: a shimmer would add per-frame work
/// beside a game. Hidden from UIA; the card's loading state is conveyed by its heading and rows appearing.
/// </summary>
public sealed partial class LeaderboardsSkeleton : StackPanel
{
    /// <summary>Builds the placeholder rows.</summary>
    public LeaderboardsSkeleton()
    {
        Spacing = 10;
        Padding = new Thickness(12, 6, 12, 6);
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        var brush = (Brush)Application.Current.Resources["FSTSurfaceMutedBrush"];
        for (var i = 0; i < 5; i++)
        {
            var row = new Grid { ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
            row.Children.Add(Bar(brush, 28, 0));
            row.Children.Add(Bar(brush, 140 - i * 12, 1));
            row.Children.Add(Bar(brush, 56, 2));
            Children.Add(row);
        }
    }

    /// <summary>One rounded placeholder bar.</summary>
    /// <param name="brush">Fill.</param>
    /// <param name="width">Width.</param>
    /// <param name="column">Grid column.</param>
    /// <returns>Bar.</returns>
    private static Rectangle Bar(Brush brush, double width, int column)
    {
        var bar = new Rectangle { Fill = brush, Height = 14, Width = width, RadiusX = 7, RadiusY = 7, HorizontalAlignment = HorizontalAlignment.Left };
        if (column == 2) bar.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetColumn(bar, column);
        return bar;
    }
}
#endregion
