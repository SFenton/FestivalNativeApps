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

    private const double TopPad = 16;
    private const double TickFontSize = 12;
    private const double TitleFontSize = 14;
    private static readonly SolidColorBrush LineBrush = new(ColorHelper.FromArgb(0xFF, 0x4C, 0x7D, 0xFF));
    private static readonly SolidColorBrush GoldBrush = new(ColorHelper.FromArgb(0xFF, 0xFF, 0xD7, 0x00));
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
    private double leftAxis = ScoreHistoryChartScale.MinAxisGutter;
    private double rightAxis = ScoreHistoryChartScale.MinAxisGutter;
    private double tickHeight = 16;
    private double labelBand = 28;
    private Size scoreTitle = new(40, 20);
    private Size accuracyTitle = new(64, 20);

    /// <summary>Creates the chart.</summary>
    public SongScoreHistoryChart()
    {
        InitializeComponent();
        Plot.SizeChanged += (_, _) =>
        {
            MeasureLabels();
            Model?.SetPlotWidth(PlotWidth);
            Redraw();
        };
        // A contrast-theme switch raises ColorValuesChanged (HighContrastChanged needs a CoreWindow); the axes, outlines and
        // selected stroke are code-built, so they are redrawn with the new theme's brushes. A text-size change re-measures
        // the gutters for the scaled labels.
        Loaded += (_, _) =>
        {
            uiSettings.ColorValuesChanged -= OnColorValuesChanged;
            uiSettings.ColorValuesChanged += OnColorValuesChanged;
            uiSettings.TextScaleFactorChanged -= OnTextScaleFactorChanged;
            uiSettings.TextScaleFactorChanged += OnTextScaleFactorChanged;
        };
        Unloaded += (_, _) =>
        {
            uiSettings.ColorValuesChanged -= OnColorValuesChanged;
            uiSettings.TextScaleFactorChanged -= OnTextScaleFactorChanged;
        };
    }

    /// <summary>Width left for bars between the two measured axis gutters.</summary>
    private double PlotWidth => Plot.ActualWidth - leftAxis - rightAxis;

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
            if (Plot.ActualWidth > 0)
            {
                MeasureLabels();
                model.SetPlotWidth(PlotWidth);
            }
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

    /// <summary>Redraws for a changed contrast theme.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnColorValuesChanged(Windows.UI.ViewManagement.UISettings sender, object args) => DispatcherQueue.TryEnqueue(Redraw);

    /// <summary>Re-measures the gutters and repages for a changed text size.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnTextScaleFactorChanged(Windows.UI.ViewManagement.UISettings sender, object args) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            MeasureLabels();
            if (Plot.ActualWidth > 0) Model?.SetPlotWidth(PlotWidth);
            Redraw();
        });

    /// <summary>
    /// Measures the scaled tick labels and axis titles (the system text size applies to them) and sizes the side gutters
    /// and date band so neither title overlaps its ticks nor the dates leave the plot.
    /// </summary>
    private void MeasureLabels()
    {
        var tick = MeasureText("0000k", TickFontSize, FontWeights.Normal);
        var percent = MeasureText("100%", TickFontSize, FontWeights.Normal);
        scoreTitle = MeasureText("Score", TitleFontSize, FontWeights.SemiBold);
        accuracyTitle = MeasureText("Accuracy", TitleFontSize, FontWeights.SemiBold);
        tickHeight = Math.Max(tick.Height, 16);
        labelBand = Math.Max(28, Math.Ceiling(6 + tickHeight + 4));
        leftAxis = ScoreHistoryChartScale.AxisGutter(tick.Width, scoreTitle.Height);
        rightAxis = ScoreHistoryChartScale.AxisGutter(percent.Width, accuracyTitle.Height);
    }

    /// <summary>Desired size of a label as the chart draws it.</summary>
    /// <param name="text">Sample text.</param>
    /// <param name="size">Font size before text scaling.</param>
    /// <param name="weight">Font weight.</param>
    /// <returns>Measured size.</returns>
    private static Size MeasureText(string text, double size, Windows.UI.Text.FontWeight weight)
    {
        var block = new TextBlock { Text = text, FontSize = size, FontWeight = weight, TextWrapping = TextWrapping.NoWrap };
        block.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return block.DesiredSize;
    }

    /// <summary>Rebuilds the plot for the current page.</summary>
    /// <remarks>
    /// Contrast themes: axes and bar outlines use the window text colour and the selected bar Highlight
    /// (<c>FSTChartAxisBrush</c>, <c>FSTChartSelectedStrokeBrush</c>); the accuracy, FC and score hues are data series
    /// named by the legend and every bar's UIA name, so they stay, outlined to keep each bar's shape at system contrast.
    /// </remarks>
    private void Redraw()
    {
        Plot.Children.Clear();
        var bars = Model?.Bars ?? [];
        var width = Plot.ActualWidth;
        var height = Plot.Height;
        var plotWidth = width - leftAxis - rightAxis;
        if (bars.Count == 0 || plotWidth <= 0) return;
        var contrast = Services.ContrastTheme.IsOn;
        var axis = Services.ContrastTheme.Brush("FSTChartAxisBrush");
        var selectedStroke = Services.ContrastTheme.Brush("FSTChartSelectedStrokeBrush");
        var plotHeight = height - TopPad - labelBand;
        var bottom = TopPad + plotHeight;
        LegendAccuracy.Visibility = bars.Any(b => !b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;
        LegendFc.Visibility = bars.Any(b => b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;

        // Axes: score (left), accuracy 0–100% (right, 4 epx headroom as the web's padding.top), baseline.
        var niceMax = ScoreHistoryChartScale.NiceMax(bars.Max(b => b.Point.Score));
        AddLine(leftAxis, TopPad, leftAxis, bottom, axis);
        AddLine(leftAxis + plotWidth, TopPad, leftAxis + plotWidth, bottom, axis);
        AddLine(leftAxis, bottom, leftAxis + plotWidth, bottom, axis);
        for (var i = 0; i <= 4; i++)
        {
            var y = bottom - plotHeight * i / 4;
            AddText(ScoreHistoryChartScale.Tick(niceMax * i / 4.0), 0, y - tickHeight / 2, leftAxis - ScoreHistoryChartScale.AxisTickGap, TextAlignment.Right);
            var accY = bottom - (plotHeight - 4) * i / 4;
            AddText((25 * i).ToString(CultureInfo.InvariantCulture) + "%", leftAxis + plotWidth + ScoreHistoryChartScale.AxisTickGap, accY - tickHeight / 2, rightAxis - ScoreHistoryChartScale.AxisTickGap, TextAlignment.Left);
        }
        AddAxisTitle("Score", scoreTitle, ScoreHistoryChartScale.AxisTitleInset + scoreTitle.Height / 2, TopPad + plotHeight / 2, -90);
        AddAxisTitle("Accuracy", accuracyTitle, width - ScoreHistoryChartScale.AxisTitleInset - accuracyTitle.Height / 2, TopPad + plotHeight / 2, 90);

        // Bars (80% of each category, web barCategoryGap 10%), then the score line and dots over them.
        var slot = plotWidth / bars.Count;
        var barWidth = Math.Max(4, slot * 0.8);
        var line = new Polyline { Stroke = LineBrush, StrokeThickness = 2, IsHitTestVisible = false };
        var dots = new List<Ellipse>(bars.Count);
        for (var i = 0; i < bars.Count; i++)
        {
            var bar = bars[i];
            var point = bar.Point;
            var centre = leftAxis + slot * (i + 0.5);
            var barHeight = Math.Max(2, (plotHeight - 4) * point.AccuracyPercent / 100);
            var (r, g, b) = SongScoreHistory.AccuracyColor(point.AccuracyPercent);
            var fill = new Border
            {
                Height = barHeight,
                CornerRadius = new CornerRadius(4, 4, 0, 0),
                Background = point.IsGold ? GoldBrush : new SolidColorBrush(ColorHelper.FromArgb(0xFF, r, g, b)),
                BorderBrush = bar.IsSelected ? selectedStroke : contrast ? axis : null,
                BorderThickness = new Thickness(bar.IsSelected ? 3 : contrast ? 1 : 0),
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
    /// <param name="stroke">Axis brush for the current theme.</param>
    private void AddLine(double x1, double y1, double x2, double y2, Brush stroke) =>
        Plot.Children.Add(new Line { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = stroke, StrokeThickness = 1, IsHitTestVisible = false });

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
            Text = text, FontSize = TickFontSize, Width = Math.Max(0, width), TextAlignment = alignment, IsHitTestVisible = false,
            TextTrimming = TextTrimming.Clip, TextWrapping = TextWrapping.NoWrap,
        };
        AutomationProperties.SetAccessibilityView(block, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetLeft(block, left);
        Canvas.SetTop(block, top);
        Plot.Children.Add(block);
    }

    /// <summary>Adds a rotated axis title centred on a point.</summary>
    /// <param name="text">Title.</param>
    /// <param name="measured">Measured unrotated size (<see cref="MeasureLabels"/>).</param>
    /// <param name="x">Centre x.</param>
    /// <param name="y">Centre y.</param>
    /// <param name="angle">Rotation.</param>
    private void AddAxisTitle(string text, Size measured, double x, double y, double angle)
    {
        var box = Math.Max(120, Math.Ceiling(measured.Width) + 8);
        var block = new TextBlock
        {
            Text = text, FontSize = TitleFontSize, FontWeight = FontWeights.SemiBold, Width = box, Height = measured.Height,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.NoWrap,
            IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new RotateTransform { Angle = angle },
        };
        AutomationProperties.SetAccessibilityView(block, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetLeft(block, x - box / 2);
        Canvas.SetTop(block, y - measured.Height / 2);
        Plot.Children.Add(block);
    }
}
#endregion
