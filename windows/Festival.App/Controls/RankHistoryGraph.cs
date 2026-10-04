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
    private const double TickFontSize = 12;
    private const double DateFontSize = 11;
    private const double SwipeThreshold = 50; // web SWIPE_THRESHOLD

    private readonly PlotSurface plot = new();
    private readonly Canvas shapes = new();
    private readonly Canvas leftLabels = new();
    private readonly Canvas rightLabels = new();
    private readonly Canvas dates = new();
    private readonly ColumnDefinition leftColumn = new();
    private readonly ColumnDefinition rightColumn = new();
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();
    private readonly Button older = NavButton("", "Show older rank history");
    private readonly Button newer = NavButton("", "Show newer rank history");
    private readonly TextBlock range = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 };
    private readonly TextBlock metricLegend = new() { Text = "Total Score", FontSize = 14, VerticalAlignment = VerticalAlignment.Center };
    private double leftAxis = RankHistoryCombinedChart.MinValueGutter;
    private double rightAxis = RankHistoryCombinedChart.MinRankGutter;
    private Rectangle? legendSwatch;
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

        ApplyGutters(RankHistoryCombinedChart.MinDateBand);
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
        // The chart is code-built: a contrast-theme switch (ColorValuesChanged; HighContrastChanged needs a CoreWindow)
        // redraws it with the new theme's brushes, and a text-size change re-measures the gutters and date band.
        Loaded += (_, _) =>
        {
            ForwardAutomationId();
            uiSettings.ColorValuesChanged -= OnSystemChanged;
            uiSettings.ColorValuesChanged += OnSystemChanged;
            uiSettings.TextScaleFactorChanged -= OnSystemChanged;
            uiSettings.TextScaleFactorChanged += OnSystemChanged;
            Redraw(); // a theme or text size changed while the page was cached and unloaded
        };
        Unloaded += (_, _) =>
        {
            uiSettings.ColorValuesChanged -= OnSystemChanged;
            uiSettings.TextScaleFactorChanged -= OnSystemChanged;
        };
        // The section repeater recycles charts across instruments: re-forward when x:Bind changes the ID in place.
        RegisterPropertyChangedCallback(AutomationProperties.AutomationIdProperty, (_, _) => ForwardAutomationId());
    }

    /// <summary>Redraws on the UI thread after a contrast-theme or text-size change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnSystemChanged(Windows.UI.ViewManagement.UISettings sender, object args) => DispatcherQueue.TryEnqueue(Redraw);

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
    /// <summary>Rebuilds the visible page for the current size, text size and contrast theme.</summary>
    /// <remarks>
    /// The side gutters fit the page's widest measured (text-scaled) tick labels; when they change, the page is laid out
    /// again for the new plot width. Contrast themes: gridlines and bar outlines use the window text colour
    /// (<c>FSTChartGridBrush</c>, <c>FSTChartAxisBrush</c>); the bar and rank-line hues are data series named by the legend
    /// and the plot's UIA summary, so they stay, opaque and outlined (as is the legend swatch) to keep each bar's shape at
    /// system contrast.
    /// </remarks>
    private void Redraw()
    {
        shapes.Children.Clear();
        leftLabels.Children.Clear();
        rightLabels.Children.Clear();
        dates.Children.Clear();
        var contrast = Services.ContrastTheme.IsOn;
        var outline = Services.ContrastTheme.Brush("FSTChartAxisBrush");
        if (legendSwatch is not null)
        {
            legendSwatch.Stroke = contrast ? outline : null;
            legendSwatch.StrokeThickness = contrast ? 1 : 0;
        }
        page = null;
        if (Model is not { } model) return;
        RankHistoryPage? laid = null;
        for (var pass = 0; pass < 2; pass++)
        {
            var available = ActualWidth - leftAxis - rightAxis;
            if (available <= 8) return;
            maxBars = RankHistoryCombinedChart.MaxBars(available);
            laid = model.Page(maxBars, offset);
            var left = RankHistoryCombinedChart.AxisGutter(WidestLabel(laid.ValueTicks), RankHistoryCombinedChart.MinValueGutter);
            var right = RankHistoryCombinedChart.AxisGutter(WidestLabel(laid.RankTicks), RankHistoryCombinedChart.MinRankGutter);
            if (left == leftAxis && right == rightAxis) break;
            leftAxis = left;
            rightAxis = right;
            laid = null;
        }
        var width = ActualWidth - leftAxis - rightAxis;
        if (width <= 8) return;
        if (laid is null)
        {
            maxBars = RankHistoryCombinedChart.MaxBars(width);
            laid = model.Page(maxBars, offset);
        }
        page = laid;
        offset = page.Offset;
        var tickHeight = MeasureText("0", TickFontSize).Height;
        ApplyGutters(RankHistoryCombinedChart.DateBand(MeasureText("0/0/00", DateFontSize).Height));
        var text = Services.ContrastTheme.Brush("FSTSecondaryTextBrush");
        var grid = Services.ContrastTheme.Brush("FSTChartGridBrush");
        var lineBrush = Solid(RankHistoryCombinedChart.LineArgb);
        const double inset = 10;
        double Y(double fraction) => inset + fraction * (PlotHeight - 2 * inset);
        double X(double fraction) => fraction * width;

        foreach (var tick in page.ValueTicks)
        {
            shapes.Children.Add(new Line { X1 = 0, X2 = width, Y1 = Y(tick.Y), Y2 = Y(tick.Y), Stroke = grid, StrokeThickness = 1, StrokeDashArray = [3, 3] });
            leftLabels.Children.Add(Label(tick.Label, Y(tick.Y) - tickHeight / 2, leftAxis - RankHistoryCombinedChart.AxisLabelGap,
                TextAlignment.Right, 0, text));
        }
        foreach (var tick in page.RankTicks)
            rightLabels.Children.Add(Label(tick.Label, Y(tick.Y) - tickHeight / 2, rightAxis - RankHistoryCombinedChart.AxisLabelGap,
                TextAlignment.Left, RankHistoryCombinedChart.AxisLabelGap, text));

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
                Stroke = contrast ? outline : null,
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

    /// <summary>An axis label whose top edge is <paramref name="top"/> (callers centre it on its tick).</summary>
    private static TextBlock Label(string value, double top, double width, TextAlignment alignment, double left, Brush brush)
    {
        var label = new TextBlock
        {
            Text = value, FontSize = TickFontSize, Foreground = brush, Width = width, TextAlignment = alignment, TextWrapping = TextWrapping.NoWrap,
        };
        // Raw on the label panel alone still exposes its children; the chart's summary name carries the values.
        AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
        Canvas.SetTop(label, top);
        Canvas.SetLeft(label, left);
        return label;
    }

    /// <summary>Sizes the side gutters and the date band (the date row lines up with the plot between the gutters).</summary>
    /// <param name="dateBand">Date band height.</param>
    private void ApplyGutters(double dateBand)
    {
        leftColumn.Width = new GridLength(leftAxis);
        rightColumn.Width = new GridLength(rightAxis);
        leftLabels.Width = leftAxis;
        rightLabels.Width = rightAxis;
        dates.Height = dateBand;
        dates.Margin = new Thickness(leftAxis, 0, rightAxis, 0);
    }

    /// <summary>Widest measured tick label.</summary>
    /// <param name="ticks">Ticks.</param>
    /// <returns>Width in epx, 0 without ticks.</returns>
    private static double WidestLabel(IEnumerable<ChartTick> ticks) =>
        ticks.Select(tick => MeasureText(tick.Label, TickFontSize).Width).DefaultIfEmpty(0).Max();

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
