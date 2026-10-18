using System.Diagnostics;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.Foundation;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region On-demand split host
/// <summary>
/// One section's page area with its on-demand trailing pane (split-panes R7 owner-approved Windows variant, issue #652):
/// the section frame fills the area until a list page (Rivals, All Rivals, Leaderboards, Song Detail) opens one of its
/// sub-pages, which then shows beside it in an equal half, so both halves grow and shrink with the window. The pane has
/// its own stack for the open item's sub-pages; Back pops it, then closes it, then leaves the list page (back-keeps-place
/// R6). A window too narrow for two panes shows an open pane alone (Fluent list/details stacked mode) until it widens.
/// Opening or closing a pane beside the list animates (pattern reflow-motion, #669): the list re-lays out once while the
/// pane slides in from its trailing edge and fades in, or slides out and fades as it uncovers the widened list; motion
/// off makes it instant.
/// </summary>
public sealed class OnDemandSplitHost : Grid
{
    #region Fields
    /// <summary>Open panes by the section stack depth of the list page they belong to.</summary>
    private readonly Dictionary<int, Pane> panes = [];
    private readonly ColumnDefinition listColumn = new() { Width = new GridLength(1, GridUnitType.Star) };
    private readonly ColumnDefinition paneColumn = new() { Width = new GridLength(0) };
    private readonly Grid paneRoot;
    private readonly Border paneHost;
    private readonly Grid closeBar;
    private readonly Border hairline;
    private static readonly UISettings SharedTextSettings = new();
    private object? listParameter;
    private bool interactionInPane;
    private bool stacked;
    /// <summary>How far open the pane is drawn when no move runs (0 list alone, 1 split); pattern reflow-motion.</summary>
    private double progress;
    private SplitMove? move;
    /// <summary>A closed pane still sliding out over the widened list.</summary>
    private Pane? leaving;
    #endregion

    /// <summary>Creates the host around a section frame (before the shell subscribes to its navigations).</summary>
    /// <param name="section">Section frame.</param>
    public OnDemandSplitHost(Frame section)
    {
        Section = section;
        ColumnDefinitions.Add(listColumn);
        ColumnDefinitions.Add(paneColumn);
        Children.Add(section);

        var close = new Button
        {
            Content = new FontIcon { Glyph = "\uE711", FontSize = 16 },
            Width = 40,
            Height = 40,
            Padding = new Thickness(0),
            Margin = new Thickness(12, 4, 0, 0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        close.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("ms-appx:///Themes/NavRowButtonResources.xaml") });
        ToolTipService.SetToolTip(close, "Close");
        AutomationProperties.SetName(close, "Close");
        AutomationProperties.SetAutomationId(close, "fst.split.close");
        close.Click += (_, _) => ClosePane();
        closeBar = new Grid { Children = { close } };

        paneHost = new Border();
        AutomationProperties.SetName(paneHost, "Detail");
        AutomationProperties.SetAutomationId(paneHost, "fst.split.pane");
        SetRow(paneHost, 1);
        paneRoot = new Grid { Visibility = Visibility.Collapsed };
        paneRoot.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        paneRoot.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        paneRoot.Children.Add(closeBar);
        paneRoot.Children.Add(paneHost);
        SetColumn(paneRoot, 1);
        Children.Add(paneRoot);

        // R2: a midpoint hairline only under Increase Contrast; decorative, never a splitter or an accessibility element.
        hairline = new Border
        {
            Width = 1,
            HorizontalAlignment = HorizontalAlignment.Left,
            IsHitTestVisible = false,
            Visibility = Visibility.Collapsed,
        };
        AutomationProperties.SetAccessibilityView(hairline, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        SetColumn(hairline, 1);
        Children.Add(hairline);

        section.Navigated += OnSectionNavigated;
        SizeChanged += (_, _) => ApplyLayout();
        // System colour changes (a contrast theme) re-resolve the hairline and text size changes the pane minimum; both
        // are static events, so only while shown.
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed += OnColorsChanged;
            TextScaleChanged += OnTextScaleChanged;
            Motion.Changed += OnMotionChanged;
            ApplyLayout();
        };
        Unloaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            TextScaleChanged -= OnTextScaleChanged;
            Motion.Changed -= OnMotionChanged;
            EndMove();
        };
        AddHandler(PointerPressedEvent, new PointerEventHandler((_, e) => Note(e.OriginalSource)), handledEventsToo: true);
        GotFocus += (_, e) => Note(e.OriginalSource);
    }

    /// <summary>Raised when the pane opens, closes, navigates or changes layout (the shell updates Back and the title).</summary>
    public event EventHandler? Changed;

    /// <summary>The section's own frame (the list page and everything pushed full width).</summary>
    public Frame Section { get; }

    /// <summary>The pane frame beside the visible list page, if one is open.</summary>
    public Frame? VisiblePane => panes.GetValueOrDefault(Section.BackStackDepth)?.Frame;

    /// <summary>The visible pane's top route, if one is open.</summary>
    public AppRoute? PaneRoute => panes.GetValueOrDefault(Section.BackStackDepth)?.Route;

    /// <summary>The visible pages, list first.</summary>
    public IEnumerable<object> Pages
    {
        get
        {
            if (!stacked && Section.Content is { } list) yield return list;
            if (VisiblePane?.Content is { } detail) yield return detail;
        }
    }

    /// <summary>Whether the content area is wide enough for two equal panes now.</summary>
    public bool AllowsSplit => AllowsSplitAt(ActualWidth);

    #region Text scale
    /// <summary>The Windows text scale every split decision uses (each pane's minimum grows from 130%, #371).</summary>
    public static double TextScale => SharedTextSettings.TextScaleFactor;

    /// <summary>Whether a region of this width holds two equal split panes at the current Windows text scale.</summary>
    /// <param name="width">Region width in epx.</param>
    /// <returns>True when each half keeps <see cref="OnDemandSplitPolicy.PaneMinimum"/>.</returns>
    public static bool AllowsSplitAt(double width) => OnDemandSplitPolicy.AllowsSplit(width, TextScale);

    /// <summary>Raised on a background thread when the Windows text scale changes; subscribe only while loaded.</summary>
    public static event TypedEventHandler<UISettings, object> TextScaleChanged
    {
        add => SharedTextSettings.TextScaleFactorChanged += value;
        remove => SharedTextSettings.TextScaleFactorChanged -= value;
    }

    /// <summary>Re-lays out the split for a new text scale, on the UI thread.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnTextScaleChanged(UISettings sender, object args) => DispatcherQueue.TryEnqueue(ApplyLayout);
    #endregion

    #region Navigation
    /// <summary>Where a navigation lands, from the visible list page and where the reader last pointed or focused.</summary>
    /// <param name="route">Destination.</param>
    /// <returns>Action.</returns>
    public SplitAction Decide(AppRoute route) =>
        OnDemandSplitPolicy.Decide(OnDemandSplitPolicy.PageOf(listParameter), AllowsSplit, VisiblePane is not null, interactionInPane, route);

    /// <summary>Opens a page in a new trailing pane beside the visible list page, replacing an open one.</summary>
    /// <param name="page">Page type.</param>
    /// <param name="route">Route.</param>
    public void OpenPane(Type page, AppRoute route)
    {
        var depth = Section.BackStackDepth;
        // A row that replaces an open pane becomes its opener; one opened from elsewhere keeps the first row.
        var opener = FocusedOpener() ?? panes.GetValueOrDefault(depth)?.Opener;
        var frame = new Frame();
        CachedPageScroll.Attach(frame);
        var pane = new Pane(frame, opener) { Route = route };
        frame.Navigated += (_, e) =>
        {
            pane.Route = e.Parameter as AppRoute;
            ApplyPaneTitle();
            Changed?.Invoke(this, EventArgs.Empty);
        };
        var reflows = !panes.ContainsKey(depth) && !stacked;
        DropLeaving();
        panes[depth] = pane;
        ApplyLayout(animate: reflows, opener);
        frame.Navigate(page, route);
    }

    /// <summary>Pushes a page onto the visible pane's stack.</summary>
    /// <param name="page">Page type.</param>
    /// <param name="route">Route.</param>
    public void PushInPane(Type page, AppRoute route) => VisiblePane?.Navigate(page, route);

    /// <summary>Back inside the split: the pane's own stack, then the pane itself.</summary>
    /// <returns><see langword="true"/> when the pane consumed Back.</returns>
    public bool TryGoBack()
    {
        if (VisiblePane is not { } pane) return false;
        if (pane.Content is IPageBack page && page.TryGoBack()) return true;
        if (pane.CanGoBack) pane.GoBack();
        else ClosePane();
        return true;
    }

    /// <summary>Closes the visible pane and returns focus to the control that opened it.</summary>
    public void ClosePane()
    {
        if (!panes.Remove(Section.BackStackDepth, out var pane)) return;
        var hadFocus = XamlRoot is not null && IsInside(FocusManager.GetFocusedElement(XamlRoot) as DependencyObject, paneRoot);
        interactionInPane = false;
        DropLeaving();
        leaving = pane;
        ApplyLayout(animate: true, pane.Opener);
        // Focus that was in the pane returns to its opener at once (the leaving pane takes no input); focus elsewhere stays.
        RestoreFocus(pane, hadFocus);
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Closes every pane (re-invoking the section pops it to its root).</summary>
    public void CloseAll()
    {
        if (panes.Count == 0) return;
        foreach (var pane in panes.Values) pane.Frame.Content = null;
        panes.Clear();
        interactionInPane = false;
        ApplyLayout();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Records that the reader acted outside the split (title bar, navigation pane).</summary>
    public void NoteOutside() => interactionInPane = false;

    /// <summary>A pushed page hides the pane of the page below it; Back shows it again. Popped pages drop their panes.</summary>
    /// <param name="sender">Section frame.</param>
    /// <param name="e">Navigation.</param>
    private void OnSectionNavigated(object sender, NavigationEventArgs e)
    {
        listParameter = e.Parameter;
        var depth = Section.BackStackDepth;
        foreach (var key in panes.Keys.Where(k => e.NavigationMode == NavigationMode.Back ? k > depth : k >= depth).ToList())
        {
            panes[key].Frame.Content = null;
            panes.Remove(key);
        }
        interactionInPane = false;
        ApplyLayout();
    }
    #endregion

    #region Layout
    /// <summary>
    /// Two equal halves while the window allows a split and a pane is open; the pane alone (stacked) when it is too narrow;
    /// the list alone otherwise. Instant: window resizes, text size, contrast and section navigation.
    /// </summary>
    private void ApplyLayout() => ApplyLayout(animate: false, null);

    /// <summary>
    /// Lays out the split. A pane opened or closed beside the list (<paramref name="animate"/>) moves there: the columns
    /// change at once and the pane slides in from its trailing edge as it fades in, or slides out and fades as it uncovers
    /// the widened list, over <see cref="ReflowTiming.Duration"/> on the compositor (pattern reflow-motion, #669; Apple
    /// <c>OnDemandSplit</c>). Motion off, the stacked layout and an unloaded host change at once.
    /// </summary>
    /// <param name="animate">Whether an open or close asked for the move.</param>
    /// <param name="opener">The row that opened the pane, kept in view once the list has its new width (back-keeps-place R6).</param>
    private void ApplyLayout(bool animate, Opener? opener)
    {
        var pane = VisiblePane;
        var split = pane is not null && AllowsSplit;
        var wasStacked = stacked;
        stacked = pane is not null && !split;
        var target = split ? 1.0 : 0.0;
        var motion = Motion.Allowed;
        var from = move?.ProgressNow() ?? progress;
        var moves = animate && ReflowTiming.AnimatesSplit(motion, IsLoaded && ActualWidth > 0, wasStacked, stacked)
            && from != target;
        if (!moves)
        {
            // A Reduce Motion change can re-apply the layout before Motion.Changed arrives: that settle is the R4 stop.
            EndMove(stopped: !motion);
            DropLeaving();
        }
        progress = target;
        Section.Visibility = stacked ? Visibility.Collapsed : Visibility.Visible;
        var shown = pane ?? leaving?.Frame;
        paneRoot.Visibility = shown is null ? Visibility.Collapsed : Visibility.Visible;
        paneRoot.IsHitTestVisible = pane is not null;
        // Stacked, the title bar's Back closes the pane as it pops a pushed page, so the pane drops its Close bar.
        closeBar.Visibility = split || leaving is not null ? Visibility.Visible : Visibility.Collapsed;
        if (!ReferenceEquals(paneHost.Child, shown)) paneHost.Child = shown;
        var hairlineOn = split && (App.Session.Settings.MoreContrast || ContrastTheme.IsOn);
        hairline.Visibility = hairlineOn ? Visibility.Visible : Visibility.Collapsed;
        if (hairlineOn) hairline.Background = ContrastTheme.Brush("FSTRowSeparatorBrush");
        ApplyPaneTitle();
        if (moves) StartMove(from, target);
        else
        {
            ApplyGeometry();
            if (animate) TraceSettle(target == 1, animated: false, motion);
        }
        // The list has its new width now; the opener stays in view (back-keeps-place R6).
        if (animate && !stacked) KeepInView(opener);
        if (wasStacked != stacked) Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// Tells the visible pane's page whether it shows beside Song Detail at the pane's root, where a song board drops its
    /// song header for its board title (song-leaderboard-header Variants, #342; Windows #667). Stacking, widening, a push
    /// inside the pane and Back inside it all re-run this, so the song header returns whenever Song Detail is not beside it.
    /// </summary>
    private void ApplyPaneTitle()
    {
        if (panes.GetValueOrDefault(Section.BackStackDepth) is not { Frame.Content: ISplitPaneTitlePage page } pane) return;
        page.BesideList = OnDemandSplitPolicy.TitlesBoardBesideList(OnDemandSplitPolicy.PageOf(listParameter), !stacked,
            pane.Frame.BackStackDepth, pane.Route);
    }

    /// <summary>Re-applies the layout on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue.TryEnqueue(ApplyLayout);

    /// <summary>Re-applies the layout after a settings change (Increase Contrast).</summary>
    public void Refresh() => ApplyLayout();
    #endregion

    #region Reflow motion
    /// <summary>
    /// Settled columns: star halves (or one column). A closed pane that is still leaving is drawn over the widened list's
    /// trailing half at its old width, where <see cref="ReflowMotion.SlidePane"/> slides it out.
    /// </summary>
    private void ApplyGeometry()
    {
        listColumn.Width = stacked ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
        paneColumn.Width = VisiblePane is null ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
        if (VisiblePane is null && leaving is not null && move is { } leavingMove)
        {
            SetColumn(paneRoot, 0);
            SetColumnSpan(paneRoot, 2);
            paneRoot.Width = leavingMove.PaneWidth;
            paneRoot.HorizontalAlignment = HorizontalAlignment.Right;
            return;
        }
        SetColumn(paneRoot, 1);
        SetColumnSpan(paneRoot, 1);
        paneRoot.ClearValue(WidthProperty);
        paneRoot.HorizontalAlignment = HorizontalAlignment.Stretch;
    }

    /// <summary>Starts (or turns around) the move to <paramref name="target"/> from where the pane is drawn now.</summary>
    /// <param name="from">Progress the pane is drawn at now.</param>
    /// <param name="target">1 to open, 0 to close.</param>
    private void StartMove(double from, double target)
    {
        var paneWidth = move?.PaneWidth ?? ActualWidth / 2;
        var started = new SplitMove(from, target, Stopwatch.GetTimestamp(), ReflowTiming.Plan(from, target, true, ReflowMotion.Duration), paneWidth);
        move = started;
        ApplyGeometry();
        TraceMove(started);
        var batch = ReflowMotion.SlidePane(paneRoot, Section, paneWidth, from, target, started.Duration);
        // Completion also arrives early when a newer move replaces this one's animations; only the current move ends.
        batch.Completed += (_, _) =>
        {
            if (ReferenceEquals(move, started)) EndMove();
        };
    }

    /// <summary>Finishes a running move where it was heading: a closed pane leaves and the pane is drawn in place again.</summary>
    /// <param name="stopped">Whether motion turned off mid-move (R4) rather than the move completing or being replaced.</param>
    private void EndMove(bool stopped = false)
    {
        if (move is not { } ended) return;
        move = null;
        if (ended.To == 0) DropLeaving();
        ReflowMotion.SettlePane(paneRoot, Section);
        ApplyGeometry();
        TraceSettle(ended.To == 1, animated: true, Motion.Allowed, Stopwatch.GetElapsedTime(ended.Start), stopped);
    }

    /// <summary>
    /// Animation effects or the app's Reduce Motion turned off while a pane slides (pattern reflow-motion R4): the move
    /// ends at once through the same settle as a completed one (an opening pane shows in place, a closing one leaves).
    /// </summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e)
    {
        if (move is not null && !Motion.Allowed) EndMove(stopped: true);
    }

    /// <summary>Lets a leaving pane go: its page is dropped and the pane area hides when nothing else is open.</summary>
    private void DropLeaving()
    {
        if (leaving is not { } gone) return;
        leaving = null;
        if (ReferenceEquals(paneHost.Child, gone.Frame)) paneHost.Child = VisiblePane;
        gone.Frame.Content = null;
        if (VisiblePane is null)
        {
            paneRoot.Visibility = Visibility.Collapsed;
            closeBar.Visibility = Visibility.Collapsed;
        }
    }

    /// <summary>Writes a move's start (<c>--perf-log</c> only).</summary>
    /// <param name="started">The move.</param>
    private static void TraceMove(SplitMove started)
    {
        if (!PerfLog.Enabled) return;
        PerfLog.Write(FormattableString.Invariant(
            $"split-move open={(started.To == 1 ? 1 : 0)} from={started.From:F3} to={started.To:F3} pane={started.PaneWidth:F1} duration={started.Duration.TotalMilliseconds:F0}"));
    }

    /// <summary>Writes where the split settled and whether a move led there (<c>--perf-log</c> only).</summary>
    /// <param name="open">Whether the pane is open.</param>
    /// <param name="animated">Whether a move led here.</param>
    /// <param name="motion">Whether motion was allowed.</param>
    /// <param name="elapsed">The move's run time.</param>
    /// <param name="stopped">Whether motion turned off mid-move.</param>
    private void TraceSettle(bool open, bool animated, bool motion, TimeSpan elapsed = default, bool stopped = false)
    {
        if (!PerfLog.Enabled) return;
        PerfLog.Write(FormattableString.Invariant(
            $"split-settle open={(open ? 1 : 0)} animated={(animated ? 1 : 0)} motion={(motion ? 1 : 0)} stopped={(stopped ? 1 : 0)} t={elapsed.TotalMilliseconds:F0} list={Section.ActualWidth:F1}"));
    }
    #endregion

    #region Focus
    /// <summary>Remembers whether the reader's last pointer press or focus was inside the pane.</summary>
    /// <param name="source">Original source.</param>
    private void Note(object source)
    {
        if (source is DependencyObject element) interactionInPane = IsInside(element, paneRoot);
    }

    /// <summary>The focused control inside the list page (the row that opens the pane), with its focus state.</summary>
    /// <returns>Opener, or <see langword="null"/>.</returns>
    private Opener? FocusedOpener() =>
        XamlRoot is not null && FocusManager.GetFocusedElement(XamlRoot) is Control { FocusState: not FocusState.Unfocused } control
            && IsInside(control, Section)
            ? new Opener(new WeakReference<Control>(control), control.FocusState)
            : null;

    /// <summary>Brings the pane's opener back into view and, when focus was in the pane, focuses it (else the list page).</summary>
    /// <param name="pane">Closed pane.</param>
    /// <param name="focus">Whether focus was inside the pane.</param>
    private void RestoreFocus(Pane pane, bool focus)
    {
        // Low priority: after the close's first layout, which widens the list at once while the pane slides out over it.
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            var opener = Live(pane.Opener);
            BringIntoView(opener);
            if (!focus || (opener is not null && opener.Focus(pane.Opener!.State))) return;
            if (Section.Content is Control page) page.Focus(FocusState.Programmatic);
        });
    }

    /// <summary>Keeps an opener in view once the list's reflow has been laid out.</summary>
    /// <param name="opener">Opener, if known.</param>
    private void KeepInView(Opener? opener)
    {
        if (opener is null) return;
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => BringIntoView(Live(opener)));
    }

    /// <summary>The opener's control while it is still shown in the list page.</summary>
    /// <param name="opener">Opener.</param>
    /// <returns>Control, or <see langword="null"/>.</returns>
    private static Control? Live(Opener? opener) =>
        opener is not null && opener.Control.TryGetTarget(out var control) && control.IsLoaded
            && control.Visibility == Visibility.Visible ? control : null;

    /// <summary>
    /// Scrolls the list page, without animation, so the control is fully shown (centred when it was not). The control is
    /// measured where layout put it (<see cref="LaidOutTop"/>): a reflow's card glide (pattern reflow-motion) still draws it
    /// at its old place, where it read as on screen while its new place was below the fold (#673).
    /// </summary>
    /// <param name="control">Control, if any.</param>
    private void BringIntoView(Control? control)
    {
        if (control is null) return;
        Section.UpdateLayout();
        if (LaidOutTop(control) is not var (scroller, top)) return; // Nothing scrolls: the list shows it whole.
        var offset = ReflowTiming.RevealOffset(top, control.ActualHeight, scroller.ViewportHeight, scroller.VerticalOffset);
        TraceKeep(top - scroller.VerticalOffset, control.ActualHeight, scroller.ViewportHeight, offset);
        if (offset is { } to) scroller.ChangeView(null, to, null, disableAnimation: true);
    }

    /// <summary>
    /// The control's laid-out top in its nearest vertically scrollable ancestor's content: the sum of each element's
    /// arranged offset (<see cref="UIElement.ActualOffset"/>), which leaves out composition translations such as a reflow
    /// glide that <see cref="UIElement.TransformToVisual"/> and <see cref="UIElement.StartBringIntoView()"/> include.
    /// </summary>
    /// <param name="control">Control.</param>
    /// <returns>The scroller and the control's top in its content, or <see langword="null"/> without one.</returns>
    private static (ScrollViewer Scroller, double Top)? LaidOutTop(UIElement control)
    {
        double top = 0;
        for (DependencyObject? node = control; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is ScrollViewer { ScrollableHeight: > 0 } scroller) return (scroller, top);
            if (node is UIElement element) top += element.ActualOffset.Y;
        }
        return null;
    }

    /// <summary>Writes where the opener was laid out and whether the list scrolled to it (<c>--perf-log</c> only).</summary>
    /// <param name="shown">Laid-out top relative to the viewport.</param>
    /// <param name="height">Opener height.</param>
    /// <param name="viewport">Viewport height.</param>
    /// <param name="offset">Offset scrolled to, or <see langword="null"/>.</param>
    private static void TraceKeep(double shown, double height, double viewport, double? offset)
    {
        if (!PerfLog.Enabled) return;
        PerfLog.Write(FormattableString.Invariant(
            $"split-keep top={shown:F1} height={height:F1} viewport={viewport:F1} scrolled={(offset is null ? 0 : 1)} to={offset ?? -1:F1}"));
    }

    /// <summary>Whether an element sits inside a container.</summary>
    /// <param name="element">Element.</param>
    /// <param name="container">Container.</param>
    /// <returns><see langword="true"/> when the container is an ancestor or the element itself.</returns>
    public static bool IsInside(DependencyObject? element, DependencyObject container)
    {
        for (var node = element; node is not null; node = VisualTreeHelper.GetParent(node))
            if (ReferenceEquals(node, container)) return true;
        return false;
    }
    #endregion

    #region Types
    /// <summary>An open pane: its frame, top route and the control that opened it.</summary>
    /// <param name="Frame">Pane frame.</param>
    /// <param name="Opener">Opener in the list page.</param>
    private sealed record Pane(Frame Frame, Opener? Opener)
    {
        /// <summary>The pane's top route.</summary>
        public AppRoute? Route { get; set; }
    }

    /// <summary>A control that opened a pane and how it was focused.</summary>
    /// <param name="Control">Control.</param>
    /// <param name="State">Focus state to restore.</param>
    private sealed record Opener(WeakReference<Control> Control, FocusState State);

    /// <summary>A running split move (pattern reflow-motion).</summary>
    /// <param name="From">Pane progress it started from.</param>
    /// <param name="To">Pane progress it heads to.</param>
    /// <param name="Start">Start timestamp (<see cref="Stopwatch.GetTimestamp"/>).</param>
    /// <param name="Duration">Run time (<see cref="ReflowTiming.Plan"/>).</param>
    /// <param name="PaneWidth">The pane's width (half the host when the move began).</param>
    private sealed record SplitMove(double From, double To, long Start, TimeSpan Duration, double PaneWidth)
    {
        /// <summary>How far open the pane is drawn now, on the same curve as the compositor.</summary>
        /// <returns>Progress in [0, 1].</returns>
        public double ProgressNow() => ReflowTiming.Progress(From, To, Stopwatch.GetElapsedTime(Start), Duration);
    }
    #endregion
}
#endregion
