using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Line chart base
/// <summary>
/// Static XAML-shape line chart drawn from unit-coordinate Core geometry: a label gutter with grid lines, a polyline,
/// point markers, optional bars below and first/last axis labels. It redraws only when the model or size changes, so it
/// costs nothing while idle. The whole chart is one UIA image named with the model's summary sentence.
/// </summary>
public abstract partial class PlayerLineChart : Grid
{
    private const double Gutter = 64;
    private readonly Canvas plot = new();
    private readonly Canvas bars = new();
    private readonly Canvas labels = new();
    private readonly TextBlock start = new() { FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock end = new() { FontSize = 12, HorizontalAlignment = HorizontalAlignment.Right, TextTrimming = TextTrimming.CharacterEllipsis };

    /// <summary>Builds the layout: plot, optional bar strip, date row.</summary>
    /// <param name="plotHeight">Line plot height.</param>
    /// <param name="barHeight">Bar strip height (0 hides it).</param>
    protected PlayerLineChart(double plotHeight, double barHeight)
    {
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(plotHeight) });
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(barHeight) });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Gutter) });
        ColumnDefinitions.Add(new ColumnDefinition());
        Children.Add(labels);
        SetColumnSpan(labels, 2);
        Children.Add(plot);
        SetColumn(plot, 1);
        Children.Add(bars);
        SetRow(bars, 1);
        SetColumn(bars, 1);
        var dates = new Grid { Margin = new Thickness(0, 4, 0, 0), ColumnSpacing = 8 };
        dates.ColumnDefinitions.Add(new ColumnDefinition());
        dates.ColumnDefinitions.Add(new ColumnDefinition());
        dates.Children.Add(start);
        dates.Children.Add(end);
        SetColumn(end, 1);
        Children.Add(dates);
        SetRow(dates, 2);
        SetColumn(dates, 1);
        foreach (var element in (FrameworkElement[])[plot, bars, labels, dates])
            AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Content);
        SizeChanged += (_, _) => Redraw();
    }

    /// <summary>Line points (unit coordinates).</summary>
    protected abstract IReadOnlyList<ChartPoint> Points { get; }

    /// <summary>Grid lines.</summary>
    protected abstract IReadOnlyList<ChartTick> Ticks { get; }

    /// <summary>Bars (unit coordinates), or empty.</summary>
    protected virtual IReadOnlyList<ChartBar> Bars => [];

    /// <summary>Leading date label.</summary>
    protected abstract string StartLabel { get; }

    /// <summary>Trailing date label.</summary>
    protected abstract string EndLabel { get; }

    /// <summary>Accessible summary.</summary>
    protected abstract string Summary { get; }

    /// <inheritdoc />
    protected override AutomationPeer OnCreateAutomationPeer() => new ChartAutomationPeer(this);

    /// <summary>Rebuilds every shape for the current size.</summary>
    protected void Redraw()
    {
        plot.Children.Clear();
        bars.Children.Clear();
        labels.Children.Clear();
        AutomationProperties.SetName(this, Summary);
        start.Text = StartLabel;
        end.Text = EndLabel;
        var width = ActualWidth - Gutter;
        var height = RowDefinitions[0].Height.Value;
        if (width <= 8 || Points.Count == 0) return;
        var secondary = (Brush)Application.Current.Resources["FSTSecondaryTextBrush"];
        var grid = (Brush)Application.Current.Resources["FSTGlassBorderBrush"];
        var accent = (Brush)Application.Current.Resources["FSTAccentBlueBrush"];
        var gold = (Brush)Application.Current.Resources["FSTGoldBrush"];
        start.Foreground = end.Foreground = secondary;
        const double inset = 8;
        double Y(double fraction) => inset + fraction * (height - 2 * inset);
        double X(double fraction) => inset + fraction * (width - 2 * inset);

        foreach (var tick in Ticks)
        {
            plot.Children.Add(new Line { X1 = 0, X2 = width, Y1 = Y(tick.Y), Y2 = Y(tick.Y), Stroke = grid, StrokeThickness = 1 });
            var label = new TextBlock { Text = tick.Label, FontSize = 12, Foreground = secondary, Width = Gutter - 8, TextAlignment = TextAlignment.Right };
            AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
            Canvas.SetTop(label, Y(tick.Y) - 9);
            labels.Children.Add(label);
        }

        var line = new Polyline { Stroke = accent, StrokeThickness = 2, StrokeLineJoin = PenLineJoin.Round };
        foreach (var point in Points) line.Points.Add(new Point(X(point.X), Y(point.Y)));
        plot.Children.Add(line);
        var size = Points.Count > 14 ? 5.0 : 8.0;
        foreach (var point in Points)
        {
            var marker = new Ellipse { Width = point.Highlight ? size + 3 : size, Height = point.Highlight ? size + 3 : size, Fill = point.Highlight ? gold : accent };
            Canvas.SetLeft(marker, X(point.X) - marker.Width / 2);
            Canvas.SetTop(marker, Y(point.Y) - marker.Height / 2);
            plot.Children.Add(marker);
        }

        var barHeight = RowDefinitions[1].Height.Value;
        if (Bars.Count == 0 || barHeight <= 0) return;
        var barWidth = Math.Clamp((width - 2 * inset) / Bars.Count * 0.6, 2, 18);
        var fill = new SolidColorBrush(((SolidColorBrush)accent).Color) { Opacity = 0.55 };
        foreach (var bar in Bars)
        {
            var rect = new Rectangle { Width = barWidth, Height = Math.Max(1, bar.Height * (barHeight - 6)), Fill = fill, RadiusX = 2, RadiusY = 2 };
            Canvas.SetLeft(rect, X(bar.X) - barWidth / 2);
            Canvas.SetTop(rect, barHeight - rect.Height);
            bars.Children.Add(rect);
        }
    }

    /// <summary>Exposes the chart as one named image.</summary>
    /// <param name="owner">Chart.</param>
    private sealed partial class ChartAutomationPeer(PlayerLineChart owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Image;
    }
}
#endregion

#region Score history chart
/// <summary>Score over time; the personal best is gold.</summary>
public sealed partial class ScoreHistoryChart : PlayerLineChart
{
    /// <summary>Chart model.</summary>
    public static readonly DependencyProperty ModelProperty = DependencyProperty.Register(
        nameof(Model), typeof(ScoreHistoryChartModel), typeof(ScoreHistoryChart), new PropertyMetadata(null, (d, _) => ((ScoreHistoryChart)d).Redraw()));

    /// <summary>Creates a 160 px plot.</summary>
    public ScoreHistoryChart() : base(160, 0) { }

    /// <summary>Chart model.</summary>
    public ScoreHistoryChartModel? Model
    {
        get => (ScoreHistoryChartModel?)GetValue(ModelProperty);
        set => SetValue(ModelProperty, value);
    }

    /// <inheritdoc />
    protected override IReadOnlyList<ChartPoint> Points => Model?.Points ?? [];

    /// <inheritdoc />
    protected override IReadOnlyList<ChartTick> Ticks => Model?.Ticks ?? [];

    /// <inheritdoc />
    protected override string StartLabel => Model?.StartLabel ?? "";

    /// <inheritdoc />
    protected override string EndLabel => Model?.EndLabel ?? "";

    /// <inheritdoc />
    protected override string Summary => Model?.Summary ?? "";
}
#endregion

#region Brushes
/// <summary>x:Bind helpers for tinted stat values.</summary>
public static class PlayerBrushes
{
    /// <summary>Gold for highlighted tiles, else the accent blue.</summary>
    /// <param name="gold">Whether to use gold.</param>
    /// <returns>Brush.</returns>
    public static Brush Tile(bool gold) => (Brush)Application.Current.Resources[gold ? "FSTEmphasisBrush" : "FSTStatBlueBrush"];

    /// <summary>Stat tile value colour (web <c>StatBox</c> <c>color</c>).</summary>
    /// <param name="tint">Tint.</param>
    /// <returns>Brush.</returns>
    public static Brush Tint(PlayerStatTint tint) => (Brush)Application.Current.Resources[tint switch
    {
        PlayerStatTint.Gold => "FSTEmphasisBrush",
        PlayerStatTint.Green => "FSTStatGreenBrush",
        _ => "FSTStatBlueBrush",
    }];

    /// <summary>Gold or accent bar fill.</summary>
    /// <param name="gold">Whether to use gold.</param>
    /// <returns>Brush.</returns>
    public static Brush Bar(bool gold) => Tile(gold);

    /// <summary>Star colour: gold for six stars, else primary text.</summary>
    /// <param name="gold">Gold stars.</param>
    /// <returns>Brush.</returns>
    public static Brush Stars(bool gold) => (Brush)Application.Current.Resources[gold ? "FSTEmphasisBrush" : "FSTTextPrimaryBrush"];

    /// <summary>Gold stroke for a personal-best row, else the card stroke.</summary>
    /// <param name="highlight">Whether to highlight.</param>
    /// <returns>Brush.</returns>
    public static Brush Highlight(bool highlight) =>
        (Brush)Application.Current.Resources[highlight ? "FSTGoldStrokeBrush" : "FSTCardStrokeBrush"];

    /// <summary>Star grid length for a bar fraction.</summary>
    /// <param name="fraction">0–1.</param>
    /// <returns>Star length.</returns>
    public static GridLength Star(double fraction) => new(Math.Max(0.001, fraction), GridUnitType.Star);

    /// <summary>Complementary star length.</summary>
    /// <param name="fraction">0–1.</param>
    /// <returns>Star length.</returns>
    public static GridLength Rest(double fraction) => new(Math.Max(0.001, 1 - fraction), GridUnitType.Star);
}
#endregion
