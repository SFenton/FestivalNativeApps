using System.ComponentModel;
using System.Globalization;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Song score history chart
/// <summary>
/// Web <c>ScoreHistoryChart</c>'s composed chart, drawn with XAML shapes (no per-frame work; redrawn only when the page of
/// bars or the width changes): accuracy bars on a 0–100% right axis (red→green, gold for a 100% FC, purple stroke on the
/// selected bar), the score as a blue line with dots on a left axis, <c>M/D/YY</c> date labels, and a legend. Bars are
/// buttons named "date, score, accuracy"; activating one selects it (the section shows its detail row).
/// </summary>
public sealed partial class SongScoreHistoryChart : UserControl
{
    /// <summary>Section model.</summary>
    public static readonly DependencyProperty ModelProperty = DependencyProperty.Register(
        nameof(Model), typeof(SongScoreHistoryViewModel), typeof(SongScoreHistoryChart),
        new PropertyMetadata(null, (d, e) => ((SongScoreHistoryChart)d).OnModelChanged(e.OldValue as SongScoreHistoryViewModel)));

    private const double LeftAxis = 64;
    private const double RightAxis = 64;
    private const double TopPad = 16;
    private const double LabelBand = 28;
    private static readonly SolidColorBrush LineBrush = new(ColorHelper.FromArgb(0xFF, 0x4C, 0x7D, 0xFF));
    private static readonly SolidColorBrush GoldBrush = new(ColorHelper.FromArgb(0xFF, 0xFF, 0xD7, 0x00));
    private static readonly SolidColorBrush SelectedStroke = new(ColorHelper.FromArgb(0xFF, 0x7C, 0x3A, 0xED));
    private static readonly SolidColorBrush AxisBrush = new(ColorHelper.FromArgb(0x33, 0xFF, 0xFF, 0xFF));

    /// <summary>Creates the chart.</summary>
    public SongScoreHistoryChart()
    {
        InitializeComponent();
        Plot.SizeChanged += (_, e) =>
        {
            Model?.SetPlotWidth(e.NewSize.Width - LeftAxis - RightAxis);
            Redraw();
        };
    }

    /// <summary>Section model.</summary>
    public SongScoreHistoryViewModel? Model
    {
        get => (SongScoreHistoryViewModel?)GetValue(ModelProperty);
        set => SetValue(ModelProperty, value);
    }

    /// <summary>Follows the new model's page of bars.</summary>
    /// <param name="old">Previous model.</param>
    private void OnModelChanged(SongScoreHistoryViewModel? old)
    {
        if (old is not null) old.PropertyChanged -= OnModelPropertyChanged;
        if (Model is { } model)
        {
            model.PropertyChanged += OnModelPropertyChanged;
            if (Plot.ActualWidth > 0) model.SetPlotWidth(Plot.ActualWidth - LeftAxis - RightAxis);
        }
        Redraw();
    }

    /// <summary>Redraws when the visible bars change.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Changed property.</param>
    private void OnModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SongScoreHistoryViewModel.Bars)) Redraw();
    }

    /// <summary>Rebuilds the plot for the current page.</summary>
    private void Redraw()
    {
        Plot.Children.Clear();
        var bars = Model?.Bars ?? [];
        var width = Plot.ActualWidth;
        var height = Plot.Height;
        var plotWidth = width - LeftAxis - RightAxis;
        if (bars.Count == 0 || plotWidth <= 0) return;
        var plotHeight = height - TopPad - LabelBand;
        var bottom = TopPad + plotHeight;
        LegendAccuracy.Visibility = bars.Any(b => !b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;
        LegendFc.Visibility = bars.Any(b => b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;

        // Axes: score (left), accuracy 0–100% (right, 4 epx headroom as the web's padding.top), baseline.
        var niceMax = ScoreHistoryChartScale.NiceMax(bars.Max(b => b.Point.Score));
        AddLine(LeftAxis, TopPad, LeftAxis, bottom);
        AddLine(LeftAxis + plotWidth, TopPad, LeftAxis + plotWidth, bottom);
        AddLine(LeftAxis, bottom, LeftAxis + plotWidth, bottom);
        for (var i = 0; i <= 4; i++)
        {
            var y = bottom - plotHeight * i / 4;
            AddText(ScoreHistoryChartScale.Tick(niceMax * i / 4.0), 0, y - 8, LeftAxis - 8, TextAlignment.Right);
            var accY = bottom - (plotHeight - 4) * i / 4;
            AddText((25 * i).ToString(CultureInfo.InvariantCulture) + "%", LeftAxis + plotWidth + 8, accY - 8, RightAxis - 8, TextAlignment.Left);
        }
        AddAxisTitle("Score", 4, TopPad + plotHeight / 2, -90);
        AddAxisTitle("Accuracy", width - 4, TopPad + plotHeight / 2, 90);

        // Bars (80% of each category, web barCategoryGap 10%), then the score line and dots over them.
        var slot = plotWidth / bars.Count;
        var barWidth = Math.Max(4, slot * 0.8);
        var line = new Polyline { Stroke = LineBrush, StrokeThickness = 2, IsHitTestVisible = false };
        var dots = new List<Ellipse>(bars.Count);
        for (var i = 0; i < bars.Count; i++)
        {
            var bar = bars[i];
            var point = bar.Point;
            var centre = LeftAxis + slot * (i + 0.5);
            var barHeight = Math.Max(2, (plotHeight - 4) * point.AccuracyPercent / 100);
            var (r, g, b) = SongScoreHistory.AccuracyColor(point.AccuracyPercent);
            var fill = new Border
            {
                Height = barHeight,
                CornerRadius = new CornerRadius(4, 4, 0, 0),
                Background = point.IsGold ? GoldBrush : new SolidColorBrush(ColorHelper.FromArgb(0xFF, r, g, b)),
                BorderBrush = bar.IsSelected ? SelectedStroke : null,
                BorderThickness = new Thickness(bar.IsSelected ? 3 : 0),
            };
            var button = new Button
            {
                Style = (Style)Resources["FSTChartBarButtonStyle"],
                Content = fill,
                Width = barWidth,
                Height = plotHeight,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
            };
            var row = new ScoreHistoryListRow(point, false);
            AutomationProperties.SetName(button, row.Announcement);
            AutomationProperties.SetAutomationId(button, "fst.history.bar." + bar.Index.ToString(CultureInfo.InvariantCulture));
            ToolTipService.SetToolTip(button, $"{point.DateLabel} · {row.Score} · {row.Accuracy}");
            var index = bar.Index;
            button.Click += (_, _) => Model?.ToggleBar(index);
            Canvas.SetLeft(button, centre - barWidth / 2);
            Canvas.SetTop(button, TopPad);
            Plot.Children.Add(button);
            AddText(point.DateLabel, centre - slot / 2, bottom + 6, slot, TextAlignment.Center);

            var y = bottom - plotHeight * point.Score / (double)niceMax;
            line.Points.Add(new Point(centre, y));
            var dot = new Ellipse { Width = 8, Height = 8, Fill = LineBrush, IsHitTestVisible = false };
            Canvas.SetLeft(dot, centre - 4);
            Canvas.SetTop(dot, y - 4);
            dots.Add(dot);
        }
        if (line.Points.Count > 1) Plot.Children.Add(line);
        foreach (var dot in dots) Plot.Children.Add(dot);
        AutomationProperties.SetName(Plot, Model?.ChartSummary ?? "");
    }

    /// <summary>Adds an axis line.</summary>
    /// <param name="x1">Start x.</param>
    /// <param name="y1">Start y.</param>
    /// <param name="x2">End x.</param>
    /// <param name="y2">End y.</param>
    private void AddLine(double x1, double y1, double x2, double y2) =>
        Plot.Children.Add(new Line { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = AxisBrush, StrokeThickness = 1, IsHitTestVisible = false });

    /// <summary>Adds a 12 epx label.</summary>
    /// <param name="text">Text.</param>
    /// <param name="left">Left.</param>
    /// <param name="top">Top.</param>
    /// <param name="width">Box width.</param>
    /// <param name="alignment">Alignment in the box.</param>
    private void AddText(string text, double left, double top, double width, TextAlignment alignment)
    {
        var block = new TextBlock
        {
            Text = text, FontSize = 12, Width = Math.Max(0, width), TextAlignment = alignment, IsHitTestVisible = false,
            TextTrimming = TextTrimming.Clip, TextWrapping = TextWrapping.NoWrap,
        };
        AutomationProperties.SetAccessibilityView(block, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetLeft(block, left);
        Canvas.SetTop(block, top);
        Plot.Children.Add(block);
    }

    /// <summary>Adds a rotated axis title centred on a point.</summary>
    /// <param name="text">Title.</param>
    /// <param name="x">Centre x.</param>
    /// <param name="y">Centre y.</param>
    /// <param name="angle">Rotation.</param>
    private void AddAxisTitle(string text, double x, double y, double angle)
    {
        const double box = 120;
        var block = new TextBlock
        {
            Text = text, FontSize = 14, FontWeight = FontWeights.SemiBold, Width = box, TextAlignment = TextAlignment.Center,
            IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new RotateTransform { Angle = angle },
        };
        AutomationProperties.SetAccessibilityView(block, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetLeft(block, x - box / 2 + (angle < 0 ? 8 : -8));
        Canvas.SetTop(block, y - 10);
        Plot.Children.Add(block);
    }
}
#endregion
