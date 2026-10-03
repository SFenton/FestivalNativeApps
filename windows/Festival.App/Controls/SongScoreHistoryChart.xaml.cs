using System.ComponentModel;
using System.Globalization;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region Song score history chart
/// <summary>
/// Web <c>ScoreHistoryChart</c>'s composed chart, drawn with XAML shapes (no per-frame work; redrawn only when the page of
/// bars or the width changes): accuracy bars on a 0–100% right axis (red→green, gold for a 100% FC, purple stroke on the
/// selected bar), the score as a blue line with dots on a left axis, <c>M/D/YY</c> date labels, and a legend. Bars are
/// toggle buttons named "date, score, accuracy" (pressed = selected); toggling one selects it (the section shows its
/// detail row). Axis bands grow with the Windows text size; a contrast theme swaps the brand hues for system colours.
/// </summary>
public sealed partial class SongScoreHistoryChart : UserControl
{
    /// <summary>Section model.</summary>
    public static readonly DependencyProperty ModelProperty = DependencyProperty.Register(
        nameof(Model), typeof(SongScoreHistoryViewModel), typeof(SongScoreHistoryChart),
        new PropertyMetadata(null, (d, e) => ((SongScoreHistoryChart)d).OnModelChanged(e.OldValue as SongScoreHistoryViewModel)));

    private const double AxisBand = 64;
    private const double TickLabelHeight = 16;
    private const double LabelBand = 28;
    private static readonly SolidColorBrush Clear = new(Colors.Transparent);
    private readonly UISettings uiSettings = new();

    /// <summary>Windows text size (1–2.25): the axis bands, date band and bar slots grow with the labels they hold.</summary>
    private static double TextScale => Math.Max(1, TextScaleLayout.Factor);

    /// <summary>Width of each axis band (tick labels plus the rotated axis title).</summary>
    private static double AxisWidth => Math.Ceiling(AxisBand * TextScale);

    /// <summary>Creates the chart.</summary>
    public SongScoreHistoryChart()
    {
        InitializeComponent();
        Plot.SizeChanged += (_, e) =>
        {
            Model?.SetPlotWidth(LayoutWidth(e.NewSize.Width));
            Redraw();
        };
        // Switching contrast themes raises ColorValuesChanged (off the UI thread); the code-drawn bars pick up the new roles.
        Loaded += (_, _) => uiSettings.ColorValuesChanged += OnColorValuesChanged;
        Unloaded += (_, _) => uiSettings.ColorValuesChanged -= OnColorValuesChanged;
    }

    /// <summary>Redraws with the current theme's role brushes.</summary>
    /// <param name="sender">Settings.</param>
    /// <param name="args">Unused.</param>
    private void OnColorValuesChanged(UISettings sender, object args) => DispatcherQueue.TryEnqueue(Redraw);

    /// <summary>Width the model pages against: the plot less both axes, in 100%-text units so a date label fits its slot.</summary>
    /// <param name="width">Canvas width.</param>
    /// <returns>Unscaled plot width.</returns>
    private static double LayoutWidth(double width) => (width - 2 * AxisWidth) / TextScale;

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
            if (Plot.ActualWidth > 0) model.SetPlotWidth(LayoutWidth(Plot.ActualWidth));
        }
        Redraw();
    }

    /// <summary>
    /// Redraws when the visible bars change. The summary is set after the bars, so the plot's UIA name follows it
    /// separately (otherwise Narrator would read the previous chart's summary after a page or instrument change).
    /// </summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Changed property.</param>
    private void OnModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SongScoreHistoryViewModel.Bars)) Redraw();
        else if (e.PropertyName is nameof(SongScoreHistoryViewModel.ChartSummary)) AutomationProperties.SetName(Plot, Model?.ChartSummary ?? "");
    }

    /// <summary>
    /// Rebuilds the plot for the current page. A bar that had keyboard focus keeps it: selecting a bar redraws the plot,
    /// and without this the focus would fall to the pager below and a keyboard or Narrator user would lose their place.
    /// </summary>
    private void Redraw()
    {
        var (focusedIndex, focusState) = FocusedBar();
        Plot.Children.Clear();
        var bars = Model?.Bars ?? [];
        var width = Plot.ActualWidth;
        var height = Plot.Height;
        var scale = TextScale;
        var axis = AxisWidth;
        var plotWidth = width - 2 * axis;
        if (bars.Count == 0 || plotWidth <= 0) return;
        var labelBand = LabelBand * scale;
        var topPad = 8 + TickLabelHeight * scale / 2;
        var plotHeight = height - topPad - labelBand;
        var bottom = topPad + plotHeight;
        var contrast = Services.ContrastTheme.IsOn;
        LegendAccuracy.Visibility = bars.Any(b => !b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;
        LegendFc.Visibility = bars.Any(b => b.Point.IsGold) ? Visibility.Visible : Visibility.Collapsed;

        // Axes: score (left), accuracy 0–100% (right, 4 epx headroom as the web's padding.top), baseline.
        var niceMax = ScoreHistoryChartScale.NiceMax(bars.Max(b => b.Point.Score));
        AddLine(axis, topPad, axis, bottom);
        AddLine(axis + plotWidth, topPad, axis + plotWidth, bottom);
        AddLine(axis, bottom, axis + plotWidth, bottom);
        var tickOffset = TickLabelHeight * scale / 2;
        for (var i = 0; i <= 4; i++)
        {
            var y = bottom - plotHeight * i / 4;
            AddText(ScoreHistoryChartScale.Tick(niceMax * i / 4.0), 0, y - tickOffset, axis - 8, TextAlignment.Right);
            var accY = bottom - (plotHeight - 4) * i / 4;
            AddText((25 * i).ToString(CultureInfo.InvariantCulture) + "%", axis + plotWidth + 8, accY - tickOffset, axis - 8, TextAlignment.Left);
        }
        AddAxisTitle("Score", 2 + 10 * scale, topPad + plotHeight / 2, -90, scale);
        AddAxisTitle("Accuracy", width - 2 - 10 * scale, topPad + plotHeight / 2, 90, scale);

        // Bars (80% of each category, web barCategoryGap 10%), then the score line and dots over them. Under a contrast
        // theme the bars are outlined in WindowText, FC bars filled, and the selection and score line use Highlight.
        var lineBrush = Role("FSTChartLineBrush");
        var slot = plotWidth / bars.Count;
        var barWidth = Math.Max(4, slot * 0.8);
        var line = new Polyline { Stroke = lineBrush, StrokeThickness = 2, IsHitTestVisible = false };
        var dots = new List<Ellipse>(bars.Count);
        ToggleButton? restore = null;
        for (var i = 0; i < bars.Count; i++)
        {
            var bar = bars[i];
            var point = bar.Point;
            var centre = axis + slot * (i + 0.5);
            var barHeight = Math.Max(2, (plotHeight - 4) * point.AccuracyPercent / 100);
            var fill = new Border
            {
                Height = barHeight,
                CornerRadius = new CornerRadius(4, 4, 0, 0),
                Background = BarFill(point, contrast),
                BorderBrush = bar.IsSelected ? Role("FSTChartSelectedStrokeBrush") : contrast ? Role("FSTChartBarStrokeBrush") : Clear,
                BorderThickness = new Thickness(bar.IsSelected ? 3 : contrast ? 1 : 0),
            };
            // A toggle button, so UIA and Narrator report which bar is selected (pressed) and Space/Enter toggle it.
            var button = new ToggleButton
            {
                Style = (Style)Resources["FSTChartBarButtonStyle"],
                Content = fill,
                Width = barWidth,
                Height = plotHeight,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                IsChecked = bar.IsSelected,
                Tag = bar.Index,
            };
            var row = new ScoreHistoryListRow(point, false);
            AutomationProperties.SetName(button, row.Announcement);
            AutomationProperties.SetAutomationId(button, "fst.history.bar." + bar.Index.ToString(CultureInfo.InvariantCulture));
            ToolTipService.SetToolTip(button, $"{point.DateLabel} · {row.Score} · {row.Accuracy}");
            var index = bar.Index;
            // Subscribed after IsChecked is set, so only a user (or UIA) toggle selects.
            button.Checked += (_, _) => Model?.ToggleBar(index);
            button.Unchecked += (_, _) => Model?.ToggleBar(index);
            Canvas.SetLeft(button, centre - barWidth / 2);
            Canvas.SetTop(button, topPad);
            Plot.Children.Add(button);
            if (focusedIndex == bar.Index) restore = button;
            AddText(point.DateLabel, centre - slot / 2, bottom + 6, slot, TextAlignment.Center);

            var y = bottom - plotHeight * point.Score / (double)niceMax;
            line.Points.Add(new Point(centre, y));
            var dot = new Ellipse
            {
                Width = 8, Height = 8, Fill = lineBrush, IsHitTestVisible = false,
                Stroke = contrast ? Role("FSTChartDotStrokeBrush") : null, StrokeThickness = contrast ? 1.5 : 0,
            };
            Canvas.SetLeft(dot, centre - 4);
            Canvas.SetTop(dot, y - 4);
            dots.Add(dot);
        }
        if (line.Points.Count > 1) Plot.Children.Add(line);
        foreach (var dot in dots) Plot.Children.Add(dot);
        AutomationProperties.SetName(Plot, Model?.ChartSummary ?? "");
        if (focusedIndex is not null) RestoreFocus(restore ?? NearestBar(focusedIndex.Value), focusState);
    }

    /// <summary>The focused bar's point index and how it got focus, if a bar has focus.</summary>
    /// <returns>Index and focus state, or <c>null</c>.</returns>
    private (int? Index, FocusState State) FocusedBar() =>
        XamlRoot is { } root && FocusManager.GetFocusedElement(root) is ToggleButton { Tag: int index } focused && Plot.Children.Contains(focused)
            ? (index, focused.FocusState)
            : (null, FocusState.Unfocused);

    /// <summary>The bar nearest a point index (when the focused bar left the page).</summary>
    /// <param name="index">Point index.</param>
    /// <returns>Bar, or <c>null</c> when the plot is empty.</returns>
    private ToggleButton? NearestBar(int index) =>
        Plot.Children.OfType<ToggleButton>().MinBy(b => Math.Abs((int)b.Tag - index));

    /// <summary>Moves focus to a rebuilt bar, once it is in the tree.</summary>
    /// <param name="bar">Bar.</param>
    /// <param name="state">Original focus state (keyboard focus keeps its visual; pointer focus does not gain one).</param>
    private void RestoreFocus(ToggleButton? bar, FocusState state)
    {
        if (bar is null) return;
        var target = state == FocusState.Unfocused ? FocusState.Programmatic : state;
        if (!bar.Focus(target)) DispatcherQueue.TryEnqueue(() => bar.Focus(target));
    }

    /// <summary>A bar's fill: red→green by accuracy, gold for a 100% FC; a contrast theme drops the hue.</summary>
    /// <param name="point">Point.</param>
    /// <param name="contrast">Whether a contrast theme is on.</param>
    /// <returns>Fill brush.</returns>
    private static Brush BarFill(ScoreHistoryPoint point, bool contrast)
    {
        if (point.IsGold) return Role("FSTChartFcBrush");
        if (contrast) return Role("FSTChartBarBrush");
        var (r, g, b) = SongScoreHistory.AccuracyColor(point.AccuracyPercent);
        return new SolidColorBrush(ColorHelper.FromArgb(0xFF, r, g, b));
    }

    /// <summary>A chart role brush (<c>Themes/Styles.xaml</c>), resolved for the current theme.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Role(string key) => Services.ContrastTheme.Brush(key);

    /// <summary>Adds an axis line.</summary>
    /// <param name="x1">Start x.</param>
    /// <param name="y1">Start y.</param>
    /// <param name="x2">End x.</param>
    /// <param name="y2">End y.</param>
    private void AddLine(double x1, double y1, double x2, double y2) =>
        Plot.Children.Add(new Line { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = Role("FSTChartAxisBrush"), StrokeThickness = 1, IsHitTestVisible = false });

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
    /// <param name="scale">Windows text size (the title's line height grows with it).</param>
    private void AddAxisTitle(string text, double x, double y, double angle, double scale)
    {
        var box = 120 * scale;
        var lineHeight = 20 * scale;
        var block = new TextBlock
        {
            Text = text, FontSize = 14, FontWeight = FontWeights.SemiBold, Width = box, Height = lineHeight,
            TextAlignment = TextAlignment.Center, IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new RotateTransform { Angle = angle },
        };
        AutomationProperties.SetAccessibilityView(block, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetLeft(block, x - box / 2);
        Canvas.SetTop(block, y - lineHeight / 2);
        Plot.Children.Add(block);
    }
}
#endregion
