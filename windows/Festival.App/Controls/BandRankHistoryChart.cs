using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Rank history chart
/// <summary>
/// Static rank-over-time line (best rank at the top) drawn from normalized <see cref="BandHistoryPoint"/>s. It only
/// re-lays out on data or size changes: no animation and no per-frame work.
/// </summary>
public sealed partial class BandRankHistoryChart : Grid
{
    /// <summary>Normalized points, oldest first.</summary>
    public static readonly DependencyProperty PointsProperty = DependencyProperty.Register(
        nameof(Points), typeof(List<BandHistoryPoint>), typeof(BandRankHistoryChart),
        new PropertyMetadata(null, (d, _) => ((BandRankHistoryChart)d).Redraw()));

    private const double Inset = 8;
    private readonly Polyline line = new() { StrokeThickness = 2.5, StrokeLineJoin = PenLineJoin.Round };
    private readonly Canvas dots = new();
    private readonly TextBlock best = new() { FontSize = 12 };
    private readonly TextBlock worst = new() { FontSize = 12, VerticalAlignment = VerticalAlignment.Bottom };

    /// <summary>Creates the chart.</summary>
    public BandRankHistoryChart()
    {
        Height = 160;
        var accent = BandsResources.Brush("AccentFillColorDefaultBrush");
        line.Stroke = accent;
        var secondary = BandsResources.Brush("FSTSecondaryTextBrush");
        best.Foreground = worst.Foreground = secondary;
        var plot = new Grid { Margin = new Thickness(56, 0, 0, 0) };
        plot.Children.Add(new Border
        {
            BorderBrush = BandsResources.Brush("FSTCardStrokeBrush"),
            BorderThickness = new Thickness(1, 0, 0, 1),
        });
        plot.Children.Add(line);
        plot.Children.Add(dots);
        plot.SizeChanged += (_, _) => Redraw();
        Children.Add(best);
        Children.Add(worst);
        Children.Add(plot);
        AutomationProperties.SetAutomationId(this, "fst.band.history-chart");
    }

    /// <summary>Points to draw.</summary>
    public List<BandHistoryPoint>? Points
    {
        get => (List<BandHistoryPoint>?)GetValue(PointsProperty);
        set => SetValue(PointsProperty, value);
    }

    /// <summary>Rebuilds the polyline and markers for the current size.</summary>
    private void Redraw()
    {
        var plot = (FrameworkElement)Children[2];
        var points = Points ?? [];
        line.Points.Clear();
        dots.Children.Clear();
        var width = Math.Max(0, plot.ActualWidth - Inset * 2);
        var height = Math.Max(0, plot.ActualHeight - Inset * 2);
        foreach (var point in points)
        {
            var at = new Point(Inset + point.X * width, Inset + point.Y * height);
            line.Points.Add(at);
            var dot = new Ellipse { Width = 7, Height = 7, Fill = line.Stroke };
            Canvas.SetLeft(dot, at.X - 3.5);
            Canvas.SetTop(dot, at.Y - 3.5);
            dots.Children.Add(dot);
        }
        if (points.Count == 0)
        {
            best.Text = worst.Text = "";
            AutomationProperties.SetName(this, "Rank history chart, no data");
            return;
        }
        var ranks = points.Select(p => p.Rank).ToArray();
        best.Text = BandFormatting.Rank(ranks.Min());
        worst.Text = ranks.Max() == ranks.Min() ? "" : BandFormatting.Rank(ranks.Max());
        AutomationProperties.SetName(this,
            $"Rank history chart, from {BandFormatting.Rank(ranks[0])} to {BandFormatting.Rank(ranks[^1])}, best {BandFormatting.Rank(ranks.Min())}");
    }
}
#endregion
