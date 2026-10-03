using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.System;
using Windows.UI;

namespace Festival.App.Controls;

#region Rank history graph
/// <summary>
/// The player page's combined Rank History chart (web <c>RankHistoryChart</c> in a <c>GraphCard</c>): rank-coloured Total
/// Score bars on the left axis and the rank line on a reversed right axis, a legend, and paging through history newest
/// page first. Older/newer buttons, Left/Right on the focused plot, a horizontal wheel/touchpad scroll or a touch swipe
/// move one page. Static XAML shapes rebuilt only when the model, page or size changes, so nothing runs while idle. The
/// plot is one UIA image named with the visible page's summary; the paging buttons are separate, named controls.
/// </summary>
public sealed partial class RankHistoryGraph : Grid
{
    /// <summary>Chart model.</summary>
    public static readonly DependencyProperty ModelProperty = DependencyProperty.Register(
        nameof(Model), typeof(RankHistoryCombinedChart), typeof(RankHistoryGraph),
        new PropertyMetadata(null, (d, _) => ((RankHistoryGraph)d).OnModelChanged()));

    private const double PlotHeight = 220;
    private const double LeftAxis = 52;
    private const double RightAxis = 48;
    private const double SwipeThreshold = 50; // web SWIPE_THRESHOLD
    private const double TickFontSize = 12;
    private const double DateFontSize = 11;
    private const double DateBand = 22;

    private readonly PlotSurface plot = new();
    private readonly Canvas shapes = new();
    private readonly Canvas leftLabels = new() { Width = LeftAxis };
    private readonly Canvas rightLabels = new() { Width = RightAxis };
    private readonly Canvas dates = new() { Height = DateBand };
    private readonly ColumnDefinition leftColumn = new() { Width = new GridLength(LeftAxis) };
    private readonly ColumnDefinition rightColumn = new() { Width = new GridLength(RightAxis) };
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
    private Rectangle? legendSwatch;
    private double leftAxis = LeftAxis;
    private double rightAxis = RightAxis;
    private readonly Button older = NavButton("", "Show older rank history");
    private readonly Button newer = NavButton("", "Show newer rank history");
    private readonly TextBlock range = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 };
    private readonly TextBlock metricLegend = new() { Text = "Total Score", FontSize = 14, VerticalAlignment = VerticalAlignment.Center };
    private int offset;
    private int maxBars = 1;
    private Point? swipeStart;
    private RankHistoryPage? page;

    /// <summary>Creates the chart.</summary>
    public RankHistoryGraph()
    {
        RowSpacing = 6;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(PlotHeight) });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        Children.Add(Legend());

        var plotGrid = new Grid();
        plotGrid.ColumnDefinitions.Add(leftColumn);
        plotGrid.ColumnDefinitions.Add(new ColumnDefinition());
        plotGrid.ColumnDefinitions.Add(rightColumn);
        plotGrid.Children.Add(leftLabels);
        plot.Content = new Grid { Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), Children = { shapes } };
        SetColumn(plot, 1);
        plotGrid.Children.Add(plot);
        SetColumn(rightLabels, 2);
        plotGrid.Children.Add(rightLabels);
        SetRow(plotGrid, 1);
        Children.Add(plotGrid);

        dates.Margin = new Thickness(LeftAxis, 0, RightAxis, 0);
        SetRow(dates, 2);
        Children.Add(dates);

        var nav = new Grid { ColumnSpacing = 8 };
        nav.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        nav.ColumnDefinitions.Add(new ColumnDefinition());
        nav.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        nav.Children.Add(older);
        SetColumn(range, 1);
        nav.Children.Add(range);
        SetColumn(newer, 2);
        nav.Children.Add(newer);
        SetRow(nav, 3);
        Children.Add(nav);

        foreach (var element in (FrameworkElement[])[leftLabels, rightLabels, dates, shapes, range])
            AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        older.Click += (_, _) => Move(+1);
        newer.Click += (_, _) => Move(-1);
        plot.KeyDown += OnPlotKeyDown;
        plot.PointerWheelChanged += OnPlotWheel;
        plot.PointerPressed += (_, e) =>
        {
            if (e.Pointer.PointerDeviceType == PointerDeviceType.Touch) swipeStart = e.GetCurrentPoint(plot).Position;
        };
        plot.PointerReleased += (_, e) => EndSwipe(e.GetCurrentPoint(plot).Position);
        plot.PointerCaptureLost += (_, _) => swipeStart = null;
        SizeChanged += (_, _) => Redraw();
        // A contrast-theme switch raises ColorValuesChanged (HighContrastChanged needs a CoreWindow) and a text-size change
        // TextScaleFactorChanged; both arrive off the UI thread. The shapes and gutters are code-built, so redraw.
        Loaded += (_, _) =>
        {
            ForwardAutomationId();
            uiSettings.ColorValuesChanged -= OnSystemSettingsChanged;
            uiSettings.ColorValuesChanged += OnSystemSettingsChanged;
            uiSettings.TextScaleFactorChanged -= OnSystemSettingsChanged;
            uiSettings.TextScaleFactorChanged += OnSystemSettingsChanged;
            Redraw();
        };
        Unloaded += (_, _) =>
        {
            uiSettings.ColorValuesChanged -= OnSystemSettingsChanged;
            uiSettings.TextScaleFactorChanged -= OnSystemSettingsChanged;
        };
    }

    /// <summary>Redraws with the new theme's brushes or the new text size's gutters.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnSystemSettingsChanged(Windows.UI.ViewManagement.UISettings sender, object args) => DispatcherQueue.TryEnqueue(Redraw);

    /// <summary>Chart model (the whole history).</summary>
    public RankHistoryCombinedChart? Model
    {
        get => (RankHistoryCombinedChart?)GetValue(ModelProperty);
        set => SetValue(ModelProperty, value);
    }

    /// <summary>The visible page (for diagnostics and tests).</summary>
    public RankHistoryPage? CurrentPage => page;

    #region Paging
    /// <summary>Shows the newest page of a new history.</summary>
    private void OnModelChanged()
    {
        offset = 0;
        metricLegend.Text = Model?.MetricLabel ?? "Total Score";
        Redraw();
    }

    /// <summary>Moves one page: +1 older, −1 newer (web <c>goBackPage</c> / <c>goForwardPage</c>).</summary>
    /// <param name="direction">Direction.</param>
    private void Move(int direction)
    {
        if (Model is not { } model) return;
        var next = Math.Clamp(offset + direction * maxBars, 0, model.MaxOffset(maxBars));
        if (next == offset) return;
        offset = next;
        Redraw();
    }

    /// <summary>Left/Right page the focused plot; Home/End jump to the oldest/newest page.</summary>
    /// <param name="sender">Plot.</param>
    /// <param name="e">Key.</param>
    private void OnPlotKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.Left: Move(+1); break;
            case VirtualKey.Right: Move(-1); break;
            case VirtualKey.Home when Model is { } model: offset = model.MaxOffset(maxBars); Redraw(); break;
            case VirtualKey.End: offset = 0; Redraw(); break;
            default: return;
        }
        e.Handled = true;
    }

    /// <summary>A horizontal wheel/touchpad scroll (or Shift+wheel) pages; plain vertical wheel keeps scrolling the page.</summary>
    /// <param name="sender">Plot.</param>
    /// <param name="e">Wheel.</param>
    private void OnPlotWheel(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(plot);
        var shift = e.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift);
        if (!point.Properties.IsHorizontalMouseWheel && !shift) return;
        var delta = point.Properties.MouseWheelDelta;
        if (delta == 0) return;
        // Horizontal wheel: positive scrolls right (newer). Shift+wheel: wheel up (positive) goes back in time.
        Move(point.Properties.IsHorizontalMouseWheel ? (delta > 0 ? -1 : +1) : (delta > 0 ? +1 : -1));
        e.Handled = true;
    }

    /// <summary>A horizontal touch swipe over 50 epx pages (right swipe shows older snapshots).</summary>
    /// <param name="end">Release point.</param>
    private void EndSwipe(Point end)
    {
        if (swipeStart is not { } start) return;
        swipeStart = null;
        var dx = end.X - start.X;
        if (Math.Abs(dx) < SwipeThreshold || Math.Abs(dx) < Math.Abs(end.Y - start.Y)) return;
        Move(dx > 0 ? +1 : -1);
    }
    #endregion

    #region Drawing
    /// <summary>Rebuilds the visible page for the current size, text size and theme.</summary>
    /// <remarks>
    /// Contrast themes: gridlines, bar outlines and the legend swatch outline use the window text colour
    /// (<c>FSTChartAxisBrush</c>) and the bars are opaque; the rank hues are a data series named by the legend and the
    /// plot's UIA summary, so they stay, outlined to keep each bar's shape at system contrast (as Song Details' chart).
    /// The side gutters and date band grow to the measured, text-scaled labels.
    /// </remarks>
    private void Redraw()
    {
        shapes.Children.Clear();
        leftLabels.Children.Clear();
        rightLabels.Children.Clear();
        dates.Children.Clear();
        var contrast = Services.ContrastTheme.IsOn;
        var axis = Services.ContrastTheme.Brush("FSTChartAxisBrush");
        if (legendSwatch is not null)
        {
            legendSwatch.Stroke = contrast ? axis : null;
            legendSwatch.StrokeThickness = contrast ? 1 : 0;
        }
        if (Model is not { } model || ActualWidth - LeftAxis - RightAxis <= 8)
        {
            page = null;
            return;
        }

        // Page with the design gutters, then widen them to the scaled labels and repage (labels depend on the page; gutters
        // only grow, and the third page is laid out with the final gutters without re-measuring).
        double left = LeftAxis, right = RightAxis, width = 0;
        for (var pass = 0; ; pass++)
        {
            width = ActualWidth - left - right;
            maxBars = RankHistoryCombinedChart.MaxBars(width);
            page = model.Page(maxBars, offset);
            if (pass == 2) break;
            var needLeft = RankHistoryCombinedChart.AxisGutter(WidestLabel(page.ValueTicks), LeftAxis);
            var needRight = RankHistoryCombinedChart.AxisGutter(WidestLabel(page.RankTicks), RightAxis);
            if (needLeft <= left && needRight <= right) break;
            left = Math.Max(left, needLeft);
            right = Math.Max(right, needRight);
        }
        if (width <= 8)
        {
            page = null;
            return;
        }
        SetGutters(left, right);
        offset = page.Offset;
        var tickHeight = MeasureText("0", TickFontSize).Height;
        dates.Height = Math.Max(DateBand, Math.Ceiling(MeasureText("0", DateFontSize).Height + 4));
        var text = (Brush)Application.Current.Resources["FSTSecondaryTextBrush"];
        var grid = contrast ? axis : (Brush)Application.Current.Resources["FSTGlassBorderBrush"];
        var lineBrush = Solid(RankHistoryCombinedChart.LineArgb);
        const double inset = 10;
        double Y(double fraction) => inset + fraction * (PlotHeight - 2 * inset);
        double X(double fraction) => fraction * width;

        foreach (var tick in page.ValueTicks)
        {
            shapes.Children.Add(new Line { X1 = 0, X2 = width, Y1 = Y(tick.Y), Y2 = Y(tick.Y), Stroke = grid, StrokeThickness = 1, StrokeDashArray = [3, 3] });
            leftLabels.Children.Add(Label(tick.Label, Y(tick.Y) - tickHeight / 2, left - RankHistoryCombinedChart.AxisLabelGap, TextAlignment.Right, 0, text));
        }
        foreach (var tick in page.RankTicks)
            rightLabels.Children.Add(Label(tick.Label, Y(tick.Y) - tickHeight / 2, right - RankHistoryCombinedChart.AxisLabelGap, TextAlignment.Left, RankHistoryCombinedChart.AxisLabelGap, text));

        // Bars (web barCategoryGap 10%, fill opacity 0.8), coloured by placement.
        var slot = width / page.Points.Count;
        var barWidth = Math.Max(4, slot * 0.8);
        for (var i = 0; i < page.Points.Count; i++)
        {
            var bar = page.Bars[i];
            var height = Math.Max(1, bar.Height * (PlotHeight - 2 * inset));
            var rect = new Rectangle
            {
                Width = barWidth, Height = height, RadiusX = 4, RadiusY = 4,
                Fill = new SolidColorBrush(Color(page.Points[i].BarArgb)) { Opacity = contrast ? 1 : 0.8 },
                Stroke = contrast ? axis : null,
                StrokeThickness = contrast ? 1 : 0,
            };
            Canvas.SetLeft(rect, X(bar.X) - barWidth / 2);
            Canvas.SetTop(rect, PlotHeight - inset - height);
            shapes.Children.Add(rect);
            var date = new TextBlock { Text = page.Points[i].AxisLabel, FontSize = DateFontSize, Foreground = text, Width = slot, TextAlignment = TextAlignment.Center };
            AutomationProperties.SetAccessibilityView(date, AccessibilityView.Raw);
            Canvas.SetLeft(date, X(bar.X) - slot / 2);
            dates.Children.Add(date);
        }

        // Rank line (web: 2 px accentBlueBright, 4 px dots) on the reversed right axis.
        var line = new Polyline { Stroke = lineBrush, StrokeThickness = 2, StrokeLineJoin = PenLineJoin.Round };
        foreach (var point in page.Line) line.Points.Add(new Point(X(point.X), Y(point.Y)));
        shapes.Children.Add(line);
        foreach (var point in page.Line)
        {
            var radius = point.Highlight ? 6 : 4;
            var dot = new Ellipse { Width = radius * 2, Height = radius * 2, Fill = lineBrush };
            Canvas.SetLeft(dot, X(point.X) - radius);
            Canvas.SetTop(dot, Y(point.Y) - radius);
            shapes.Children.Add(dot);
        }

        range.Text = page.RangeText;
        range.Foreground = text;
        older.IsEnabled = page.CanOlder;
        newer.IsEnabled = page.CanNewer;
        var paged = page.CanOlder || page.CanNewer;
        older.Visibility = newer.Visibility = paged ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(plot, page.Summary);
        AutomationProperties.SetHelpText(plot, paged ? "Use Left and Right to page through rank history." : "");
    }

    /// <summary>Hides a decorative element from UIA.</summary>
    /// <param name="element">Element.</param>
    /// <returns>The same element.</returns>
    private static TextBlock Hidden(TextBlock element)
    {
        AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        return element;
    }

    /// <summary>The web legend: gradient swatch named after the bar metric ("Total Score") and a line-with-dot "Rank".</summary>
    /// <returns>Legend row.</returns>
    private StackPanel Legend()
    {
        var legend = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, HorizontalAlignment = HorizontalAlignment.Center };
        var gradient = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 0) };
        gradient.GradientStops.Add(new GradientStop { Color = Color(0xFFDC2828), Offset = 0 });
        gradient.GradientStops.Add(new GradientStop { Color = Color(0xFF2ECC71), Offset = 1 });
        var swatch = new Rectangle { Width = 20, Height = 12, RadiusX = 2, RadiusY = 2, Fill = gradient, VerticalAlignment = VerticalAlignment.Center };
        legendSwatch = swatch;
        var rank = new Canvas { Width = 24, Height = 12, VerticalAlignment = VerticalAlignment.Center };
        rank.Children.Add(new Line { X1 = 0, X2 = 18, Y1 = 6, Y2 = 6, Stroke = Solid(RankHistoryCombinedChart.LineArgb), StrokeThickness = 2 });
        var dot = new Ellipse { Width = 6, Height = 6, Fill = Solid(RankHistoryCombinedChart.LineArgb) };
        Canvas.SetLeft(dot, 15);
        Canvas.SetTop(dot, 3);
        rank.Children.Add(dot);
        legend.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Children = { swatch, metricLegend } });
        legend.Children.Add(Item(rank, "Rank"));
        // Raw on the panel does not hide its children in WinUI: hide each label too (the bars' names carry the values).
        AutomationProperties.SetAccessibilityView(legend, AccessibilityView.Raw);
        AutomationProperties.SetAccessibilityView(metricLegend, AccessibilityView.Raw);
        return legend;

        static StackPanel Item(FrameworkElement glyph, string label) => new()
        {
            Orientation = Orientation.Horizontal, Spacing = 6,
            Children = { glyph, Hidden(new TextBlock { Text = label, FontSize = 14, VerticalAlignment = VerticalAlignment.Center }) },
        };
    }

    /// <summary>An axis label whose top is at <paramref name="top"/>.</summary>
    private static TextBlock Label(string value, double top, double width, TextAlignment alignment, double left, Brush brush)
    {
        var label = new TextBlock { Text = value, FontSize = TickFontSize, Foreground = brush, Width = width, TextAlignment = alignment, TextWrapping = TextWrapping.NoWrap };
        // Raw on the label panel alone still exposes its children; the chart's summary name carries the values.
        AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
        Canvas.SetTop(label, top);
        Canvas.SetLeft(label, left);
        return label;
    }

    /// <summary>Desired size of a label as the chart draws it (the system text size applies).</summary>
    /// <param name="value">Text.</param>
    /// <param name="size">Font size before text scaling.</param>
    /// <returns>Measured size.</returns>
    private static Size MeasureText(string value, double size)
    {
        var block = new TextBlock { Text = value, FontSize = size, TextWrapping = TextWrapping.NoWrap };
        block.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return block.DesiredSize;
    }

    /// <summary>Width of the widest tick label.</summary>
    /// <param name="ticks">Axis ticks.</param>
    /// <returns>Width in epx (0 without ticks).</returns>
    private static double WidestLabel(IEnumerable<ChartTick> ticks) =>
        ticks.Select(t => MeasureText(t.Label, TickFontSize).Width).DefaultIfEmpty(0).Max();

    /// <summary>Applies the side gutters to the label canvases, plot columns and date band.</summary>
    /// <param name="left">Left (value) gutter.</param>
    /// <param name="right">Right (rank) gutter.</param>
    private void SetGutters(double left, double right)
    {
        if (left == leftAxis && right == rightAxis) return;
        leftAxis = left;
        rightAxis = right;
        leftLabels.Width = left;
        rightLabels.Width = right;
        leftColumn.Width = new GridLength(left);
        rightColumn.Width = new GridLength(right);
        dates.Margin = new Thickness(left, 0, right, 0);
    }

    /// <summary>A paging button with a chevron glyph, tooltip and UIA name.</summary>
    private static Button NavButton(string glyph, string name)
    {
        var button = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 12 }, Padding = new Thickness(10, 6, 10, 6) };
        AutomationProperties.SetName(button, name);
        ToolTipService.SetToolTip(button, name);
        return button;
    }

    /// <summary>Gives the plot the chart's AutomationId and the buttons <c>&lt;id&gt;.older</c> / <c>.newer</c>.</summary>
    private void ForwardAutomationId()
    {
        if (AutomationProperties.GetAutomationId(this) is not { Length: > 0 } id) return;
        AutomationProperties.SetAutomationId(plot, id);
        AutomationProperties.SetAutomationId(older, id + ".older");
        AutomationProperties.SetAutomationId(newer, id + ".newer");
    }

    private static Color Color(uint argb) => Windows.UI.Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);

    private static SolidColorBrush Solid(uint argb) => new(Color(argb));
    #endregion

    #region Plot surface
    /// <summary>Focusable plot exposed to UI Automation as one named image.</summary>
    private sealed partial class PlotSurface : ContentControl
    {
        /// <summary>Creates a focusable surface whose content stretches.</summary>
        public PlotSurface()
        {
            IsTabStop = true;
            UseSystemFocusVisuals = true;
            HorizontalContentAlignment = HorizontalAlignment.Stretch;
            VerticalContentAlignment = VerticalAlignment.Stretch;
        }

        /// <inheritdoc />
        protected override AutomationPeer OnCreateAutomationPeer() => new SurfacePeer(this);

        /// <summary>Image peer.</summary>
        /// <param name="owner">Surface.</param>
        private sealed partial class SurfacePeer(PlotSurface owner) : FrameworkElementAutomationPeer(owner)
        {
            /// <inheritdoc />
            protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Image;

            /// <inheritdoc />
            protected override bool IsKeyboardFocusableCore() => true;
        }
    }
    #endregion
}
#endregion
