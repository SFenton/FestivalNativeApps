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
            ApplyLayout();
        };
        Unloaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            TextScaleChanged -= OnTextScaleChanged;
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
        panes[depth] = pane;
        ApplyLayout();
        frame.Navigate(page, route);
        // The list narrows to half width and reflows; its opener stays in view (back-keeps-place R6).
        if (reflows && AllowsSplit) KeepInView(opener);
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
        ApplyLayout();
        pane.Frame.Content = null;
        // The list reflows from half to full width; the row that opened the pane stays in view (back-keeps-place R6), and
        // focus that was in the pane returns to it; focus elsewhere stays.
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
    /// the list alone otherwise.
    /// </summary>
    private void ApplyLayout()
    {
        var pane = VisiblePane;
        var split = pane is not null && AllowsSplit;
        var wasStacked = stacked;
        stacked = pane is not null && !split;
        listColumn.Width = stacked ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
        paneColumn.Width = pane is null ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
        Section.Visibility = stacked ? Visibility.Collapsed : Visibility.Visible;
        paneRoot.Visibility = pane is null ? Visibility.Collapsed : Visibility.Visible;
        // Stacked, the title bar's Back closes the pane as it pops a pushed page, so the pane drops its Close bar.
        closeBar.Visibility = split ? Visibility.Visible : Visibility.Collapsed;
        if (!ReferenceEquals(paneHost.Child, pane)) paneHost.Child = pane;
        var hairlineOn = split && (App.Session.Settings.MoreContrast || ContrastTheme.IsOn);
        hairline.Visibility = hairlineOn ? Visibility.Visible : Visibility.Collapsed;
        if (hairlineOn) hairline.Background = ContrastTheme.Brush("FSTRowSeparatorBrush");
        ApplyPaneTitle();
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
        // Low priority: after the list's reflow to full width has been laid out.
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

    /// <summary>Scrolls the list page, without animation, so the control is fully shown.</summary>
    /// <param name="control">Control, if any.</param>
    private void BringIntoView(Control? control)
    {
        if (control is null) return;
        Section.UpdateLayout();
        var top = control.TransformToVisual(Section).TransformPoint(default).Y;
        if (top >= 0 && top + control.ActualHeight <= Section.ActualHeight) return;
        // Centred, so a page's pinned header never covers it.
        control.StartBringIntoView(new BringIntoViewOptions { AnimationDesired = false, VerticalAlignmentRatio = 0.5 });
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
    #endregion
}
#endregion
