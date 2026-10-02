using Festival.Core.ViewModels;
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
/// beside a game. Hidden from UIA; the card's loading state is conveyed by its heading and rows appearing. Each row is
/// a loaded <see cref="LeaderboardEntryRow"/>'s frosted surface at <see cref="LeaderboardRowMetrics.MinHeight"/>, spaced
/// like the loaded rows, so rows don't jump when data arrives (issue #90).
/// </summary>
public sealed partial class LeaderboardsSkeleton : StackPanel
{
    /// <summary>Placeholder rows per card.</summary>
    public const int RowCount = 5;

    /// <summary>Builds the placeholder rows.</summary>
    public LeaderboardsSkeleton()
    {
        Spacing = LeaderboardRowMetrics.Spacing;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        var resources = Application.Current.Resources;
        var bar = (Brush)resources["FSTSurfaceMutedBrush"];
        var surface = (Brush)resources["FSTCardSurfaceBrush"];
        var stroke = (Brush)resources["FSTCardStrokeBrush"];
        for (var i = 0; i < RowCount; i++)
        {
            var row = new Grid
            {
                ColumnSpacing = 12,
                MinHeight = LeaderboardRowMetrics.MinHeight,
                Padding = new Thickness(12, 0, 12, 0),
                CornerRadius = new CornerRadius(12),
                BorderThickness = new Thickness(1),
                Background = surface,
                BorderBrush = stroke,
            };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
            row.Children.Add(Bar(bar, 28, 0));
            row.Children.Add(Bar(bar, 140 - i * 12, 1));
            row.Children.Add(Bar(bar, 56, 2));
            Children.Add(row);
        }
    }

    /// <summary>One rounded placeholder bar, centred in its row.</summary>
    /// <param name="brush">Fill.</param>
    /// <param name="width">Width.</param>
    /// <param name="column">Grid column.</param>
    /// <returns>Bar.</returns>
    private static Rectangle Bar(Brush brush, double width, int column)
    {
        var bar = new Rectangle
        {
            Fill = brush, Height = 14, Width = width, RadiusX = 7, RadiusY = 7,
            HorizontalAlignment = column == 2 ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(bar, column);
        return bar;
    }
}
#endregion
