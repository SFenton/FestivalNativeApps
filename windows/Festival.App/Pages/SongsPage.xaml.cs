using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace Festival.App.Pages;

#region Songs page
/// <summary>
/// Songs catalogue: grouped, virtualized list with a semantic-zoom jump index, search, sort and filter, same-publication
/// Item Shop accents and the selected player's status chips or metadata pills. Rows realize in phases (text, then
/// art and trailing content) and reveal once the first rows' art has decoded (bounded).
/// </summary>
public sealed partial class SongsPage : Page, IPageBack
{
    /// <summary>Rows whose art is decoded before the first reveal.</summary>
    private const int ArtworkPrimeCount = 12;

    /// <summary>Upper bound on the first-reveal wait.</summary>
    private static readonly TimeSpan ArtworkPrimeTimeout = TimeSpan.FromMilliseconds(900);

    /// <summary>List width at which chips sit inline instead of under the title.</summary>
    private const double InlineChipsWidth = 760;

    /// <summary>List width at which every metadata pill sits inline.</summary>
    private const double InlineMetadataWidth = 1100;

    /// <summary>Page width from which the list and the selected song's detail sit side by side.</summary>
    public const double SplitWidth = 1100;

    /// <summary>List column width in the split layout.</summary>
    private const double SplitListWidth = 560;

    /// <summary>Delay before the detail follows keyboard selection (arrowing through rows loads only where it stops).</summary>
    private static readonly TimeSpan DetailFollowDelay = TimeSpan.FromMilliseconds(180);

    private readonly Dictionary<ListViewItem, CancellationTokenSource> artLoads = [];
    private DispatcherQueueTimer? autoScroll;
    private ScrollViewer? scroller;
    private double scrollStep = 6;
    private bool revealed;
    private bool split;
    private string? detailSongId;
    private DispatcherQueueTimer? detailTimer;
    private string? appliedSort;
    private int[] groupStarts = [];
    private string[] stickyLabels = [];
    private int stickyRowCount;
    private bool wideLayout;
    private readonly TopEdgeFade edgeFade;
    private readonly Windows.UI.ViewManagement.UISettings fadeUiSettings = new();

    /// <summary>Content position that leaves the pinned title unpushed (no incoming title).</summary>
    private const float RestingTitle = 1e6f;

    /// <summary>Push geometry for the compositor: C (incoming title's content top), V (viewport top in PushLayer) and H (bar height).</summary>
    private CompositionPropertySet? pushProps;

    /// <summary>The in-list title made transparent while PushLayer draws it.</summary>
    private TextBlock? hiddenTitle;

    /// <summary>Section a jump-index pick still has to pin under the bar, or -1.</summary>
    private int pendingPin = -1;

    /// <summary>Creates the page.</summary>
    public SongsPage()
    {
        ViewModel = new SongsViewModel(App.Session);
        InitializeComponent();
        ViewModel.PropertyChanged += OnViewModelChanged;
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading,
            () => ViewModel.ShowList || ViewModel.ShowEmpty ? ViewModel.CountText : null, "Loading songs");
        Loaded += (_, _) => UpdateButtonTints();
        SizeChanged += OnSizeChanged;
        SongList.SelectionChanged += OnSongSelectionChanged;
        Zoom.PreviewKeyDown += OnZoomKeyDown;
        Zoom.ViewChangeCompleted += OnZoomViewChangeCompleted;
        edgeFade = new TopEdgeFade(ListFadeSource, ListFadeHost);
        Loaded += (_, _) => AttachEdgeFadeSettings();
        Unloaded += (_, _) => DetachEdgeFadeSettings();
    }

    /// <summary>Page model.</summary>
    public SongsViewModel ViewModel { get; }

    /// <summary>Negation helper for x:Bind.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Negated value.</returns>
    public static bool Not(bool value) => !value;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.AppearCommand.ExecuteAsync(null);
    }

    #region List
    /// <summary>Rebinds groups when sections change.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(SongsViewModel.Sections):
                // A new search, sort or filter closes the jump index: its letters described the old list.
                if (!Zoom.IsZoomedInViewActive) Zoom.IsZoomedInViewActive = true;
                RebindGroups();
                // A new sort starts at the top of the list (operator batch 5; web and every sortable list).
                if (appliedSort is not null && appliedSort != ViewModel.SortSummary)
                    EnsureScroller()?.ChangeView(null, 0, null, true);
                appliedSort = ViewModel.SortSummary;
                if (split) EnsureSplitSelection();
                else ApplySplit(ActualWidth >= SplitWidth);
                if (ViewModel.Sections.Count > 0)
                {
                    // A sort, filter or search change re-staggers the list, like the web's settings fingerprint.
                    if (revealed) FadeIn.Restagger(SongList);
                    if (!revealed) _ = RevealAsync();
                    PerfLog.Mark("songs-rendered");
                    if (App.Options.AutoScroll) StartAutoScroll();
                }
                break;
            case nameof(SongsViewModel.ShowList):
                UpdateStickyHeader();
                ApplySplit(ActualWidth >= SplitWidth);
                break;
            case nameof(SongsViewModel.IsSortChanged) or nameof(SongsViewModel.IsFilterActive):
                UpdateButtonTints();
                break;
        }
    }

    /// <summary>Rebuilds the grouped source and the sticky header's section offsets.</summary>
    private void RebindGroups()
    {
        ShowIncoming(null);
        pendingPin = -1;
        var groups = ViewModel.Sections.Select((s, i) => new SongGroup(s.Label, s.Rows, i == 0)).ToList();
        groupStarts = new int[groups.Count];
        for (int i = 0, start = 0; i < groups.Count; start += groups[i].Count, i++) groupStarts[i] = start;
        stickyLabels = groups.Select(g => g.Label).ToArray();
        stickyRowCount = groups.Sum(g => g.Count);
        GroupedSongs.Source = groups;
        UpdateStickyHeader();
    }

    /// <summary>
    /// Names the section holding the first visible row in the bar above the list, and lets the next section's title
    /// push it out like a plain list's pinned headers (issue #288; <see cref="SongSectionHeader.Push"/>). Runs on scroll
    /// view changes only (no per-frame work while idle); the push positions follow the scroll on the compositor. The
    /// first visible row comes from the realized rows' geometry: <see cref="ItemsStackPanel.FirstVisibleIndex"/> can
    /// still describe the layout before a jump-index pick (issue #48: R → B kept "A" pinned).
    /// </summary>
    private void UpdateStickyHeader()
    {
        EnsureScroller();
        var panel = SongList.ItemsPanelRoot as ItemsStackPanel;
        var fallback = panel is { FirstVisibleIndex: >= 0 } ? panel.FirstVisibleIndex : 0;
        var row = SongSectionHeader.FirstVisibleRow(fallback, stickyRowCount, RealizedRows(panel),
            scroller?.ViewportHeight ?? SongList.ActualHeight);
        var section = SongSectionHeader.SectionAt(groupStarts, row);
        var own = TitleAt(section);
        var next = TitleAt(section + 1);
        var push = SongSectionHeader.Push(section, stickyLabels.Length, own?.Top, next?.Top, StickyBar.ActualHeight,
            SongHeaderEdgeFade.Depth);
        var incoming = push.Incoming < 0 ? null : push.Incoming == section ? own : next;
        ShowStickyHeader(push.Current >= 0 ? stickyLabels[push.Current] : "", incoming);
    }

    /// <summary>Sets the pinned header's text and visibility.</summary>
    /// <param name="label">Section label ("" hides the bar).</param>
    /// <param name="incoming">The next section's in-list title pushing it out, if any.</param>
    private void ShowStickyHeader(string label, (TextBlock Text, double Top)? incoming = null)
    {
        StickyHeader.Text = label;
        var shown = label.Length > 0 && Zoom.IsZoomedInViewActive && ViewModel.ShowList && Zoom.Opacity > 0;
        StickyHeader.Visibility = shown ? Visibility.Visible : Visibility.Collapsed;
        ShowIncoming(shown ? incoming : null);
        UpdateEdgeFade(shown);
    }

    /// <summary>
    /// Finds the list's scroll viewer once, following its view changes for the pinned header and starting the push
    /// animations (every lookup goes through here so none skips the subscription).
    /// </summary>
    /// <returns>The scroll viewer, or <see langword="null"/> before the list's template applies.</returns>
    private ScrollViewer? EnsureScroller()
    {
        if (scroller is null && (scroller = FindScrollViewer(SongList)) is not null)
        {
            scroller.ViewChanged += (_, _) => UpdateStickyHeader();
            StartPushAnimations(scroller);
        }
        return scroller;
    }

    /// <summary>A section's visible in-list title and its text top relative to the list viewport's top.</summary>
    /// <param name="section">Section index.</param>
    /// <returns>The title, or <see langword="null"/> when it has none (the first section) or is not realized.</returns>
    private (TextBlock Text, double Top)? TitleAt(int section)
    {
        if (scroller is null || section <= 0 || section >= groupStarts.Length) return null;
        var end = section + 1 < groupStarts.Length ? groupStarts[section + 1] : stickyRowCount;
        if (end <= groupStarts[section] || SongList.ContainerFromIndex(groupStarts[section]) is not ListViewItem item) return null;
        if (SongList.GroupHeaderContainerFromItemContainer(item) is not ListViewHeaderItem
            { ContentTemplateRoot: TextBlock { Visibility: Visibility.Visible } text }) return null;
        return (text, text.TransformToVisual(scroller).TransformPoint(default).Y);
    }

    /// <summary>
    /// Ties the pinned title's and the incoming copy's offsets to the scroll position on the compositor, so they move
    /// with the rows in the same frame (live title top t = C + scroll translation): the pinned title moves up by
    /// Clamp(t, -H, 0) and the copy sits at Max(0, V + t), its own place until it lands at the bar's top.
    /// </summary>
    /// <param name="viewer">The list's scroll viewer.</param>
    private void StartPushAnimations(ScrollViewer viewer)
    {
        var scroll = ElementCompositionPreview.GetScrollViewerManipulationPropertySet(viewer);
        pushProps = scroll.Compositor.CreatePropertySet();
        pushProps.InsertScalar("C", RestingTitle);
        pushProps.InsertScalar("V", 0);
        pushProps.InsertScalar("H", 0);
        StartTranslation(StickyHeader, "Vector3(0, Clamp(p.C + s.Translation.Y, -p.H, 0), 0)", scroll, pushProps);
        StartTranslation(IncomingHeader, "Vector3(0, Max(0, p.V + p.C + s.Translation.Y), 0)", scroll, pushProps);
    }

    /// <summary>Drives an element's Translation with an expression over the scroll and push property sets.</summary>
    /// <param name="element">Element.</param>
    /// <param name="expression">Vector3 expression.</param>
    /// <param name="scroll">The scroll viewer's manipulation property set (s).</param>
    /// <param name="props">Push geometry (p).</param>
    private static void StartTranslation(UIElement element, string expression, CompositionPropertySet scroll, CompositionPropertySet props)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var animation = visual.Compositor.CreateExpressionAnimation(expression);
        animation.SetReferenceParameter("s", scroll);
        animation.SetReferenceParameter("p", props);
        visual.StartAnimation("Translation", animation);
    }

    /// <summary>
    /// Draws the incoming section title in PushLayer over its in-list place (made transparent, still the UIA heading),
    /// or hides the copy and restores the in-list title.
    /// </summary>
    /// <param name="incoming">The incoming title, or <see langword="null"/>.</param>
    private void ShowIncoming((TextBlock Text, double Top)? incoming)
    {
        var title = incoming is { } shown && scroller is not null && pushProps is not null ? shown.Text : null;
        if (hiddenTitle is not null && hiddenTitle != title) hiddenTitle.Opacity = 1;
        hiddenTitle = title;
        if (title is null || pushProps is null || scroller is null)
        {
            IncomingHeader.Visibility = Visibility.Collapsed;
            pushProps?.InsertScalar("C", RestingTitle);
            return;
        }
        var top = incoming!.Value.Top;
        var origin = title.TransformToVisual(PushLayer).TransformPoint(default);
        IncomingHeader.Text = title.Text;
        Canvas.SetLeft(IncomingHeader, origin.X);
        pushProps.InsertScalar("V", (float)(origin.Y - top));
        pushProps.InsertScalar("H", (float)StickyBar.ActualHeight);
        pushProps.InsertScalar("C", (float)(top + scroller.VerticalOffset));
        IncomingHeader.Visibility = Visibility.Visible;
        title.Opacity = 0;
    }

    /// <summary>Keeps the bar clipped to its own row (the pushed title leaves through its top) and re-lays the push.</summary>
    /// <param name="sender">Bar.</param>
    /// <param name="e">New size.</param>
    private void OnStickyBarSizeChanged(object sender, SizeChangedEventArgs e)
    {
        StickyBar.Clip = new RectangleGeometry { Rect = new(0, 0, e.NewSize.Width, e.NewSize.Height) };
        UpdateStickyHeader();
    }

    /// <summary>
    /// Fades rows out at the list's top edge under the section header bar (issue #49) while the header shows and the
    /// list is scrolled, unless a contrast theme, Windows transparency effects off or the in-app Increase Contrast or
    /// Less Transparency setting asks for the hard edge.
    /// </summary>
    /// <param name="headerShown">Whether the section header bar is visible.</param>
    private void UpdateEdgeFade(bool headerShown)
    {
        var settings = App.Session.Settings;
        var enabled = headerShown && SongHeaderEdgeFade.IsEnabled(ContrastTheme.IsOn, fadeUiSettings.AdvancedEffectsEnabled,
            settings.LessTransparency, settings.MoreContrast);
        edgeFade.Update(enabled ? SongHeaderEdgeFade.Strength(scroller?.VerticalOffset ?? 0) : 0);
    }

    /// <summary>Follows appearance changes that switch the edge fade on or off while the page is shown.</summary>
    private void AttachEdgeFadeSettings()
    {
        App.Session.PropertyChanged += OnEdgeFadeSettingsChanged;
        fadeUiSettings.AdvancedEffectsEnabledChanged += OnEdgeFadeSystemChanged;
        // HighContrastChanged needs a CoreWindow; a contrast-theme switch raises ColorValuesChanged instead.
        fadeUiSettings.ColorValuesChanged += OnEdgeFadeSystemChanged;
    }

    /// <summary>Stops following appearance changes.</summary>
    private void DetachEdgeFadeSettings()
    {
        App.Session.PropertyChanged -= OnEdgeFadeSettingsChanged;
        fadeUiSettings.AdvancedEffectsEnabledChanged -= OnEdgeFadeSystemChanged;
        fadeUiSettings.ColorValuesChanged -= OnEdgeFadeSystemChanged;
    }

    /// <summary>Re-evaluates the fade when the in-app settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnEdgeFadeSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == "Settings") DispatcherQueue.TryEnqueue(UpdateStickyHeader);
    }

    /// <summary>Re-evaluates the fade when Windows transparency effects or the contrast theme change (any thread).</summary>
    /// <param name="sender">Settings source.</param>
    /// <param name="args">Ignored.</param>
    private void OnEdgeFadeSystemChanged(object sender, object args) => DispatcherQueue.TryEnqueue(UpdateStickyHeader);

    /// <summary>Realized row containers with their edges relative to the list viewport's top.</summary>
    /// <param name="panel">Items panel.</param>
    /// <returns>Rows (recycled containers excluded).</returns>
    private IEnumerable<SongSectionHeader.RealizedRow> RealizedRows(ItemsStackPanel? panel)
    {
        if (panel is null || scroller is null) yield break;
        foreach (var child in panel.Children)
        {
            if (child is not ListViewItem item || item.Visibility != Visibility.Visible) continue;
            var index = SongList.IndexFromContainer(item);
            if (index < 0) continue;
            var top = item.TransformToVisual(scroller).TransformPoint(default).Y;
            yield return new(index, top, top + item.ActualHeight);
        }
    }

    /// <summary>
    /// A jump-index pick names its section in the pinned header at once, then re-reads the rows once layout settles and
    /// scrolls the picked title up under the bar so the section's first row sits at the top (a section that cannot reach
    /// the top, such as Z, leaves the previous section there).
    /// </summary>
    /// <param name="sender">Semantic zoom.</param>
    /// <param name="e">View change.</param>
    private void OnZoomViewChangeCompleted(object sender, SemanticZoomViewChangedEventArgs e)
    {
        pendingPin = -1;
        if (Zoom.IsZoomedInViewActive && e.DestinationItem?.Item is SongGroup group)
        {
            ShowStickyHeader(group.Label);
            if (GroupedSongs.Source is IList<SongGroup> groups) pendingPin = groups.IndexOf(group);
        }
        else UpdateStickyHeader();
        void Settle(object? _, object __)
        {
            SongList.LayoutUpdated -= Settle;
            PinJumpedSection();
            UpdateStickyHeader();
        }
        SongList.LayoutUpdated += Settle;
        DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            PinJumpedSection();
            pendingPin = -1;
            UpdateStickyHeader();
        });
    }

    /// <summary>Scrolls a jumped-to section's title under the bar once its header is realized (<see cref="SongSectionHeader.JumpPinDelta"/>).</summary>
    private void PinJumpedSection()
    {
        if (pendingPin < 0 || pendingPin >= groupStarts.Length || scroller is null) return;
        if (SongList.ContainerFromIndex(groupStarts[pendingPin]) is not ListViewItem item ||
            SongList.GroupHeaderContainerFromItemContainer(item) is not FrameworkElement header) return;
        pendingPin = -1;
        var bottom = header.TransformToVisual(scroller).TransformPoint(default).Y + header.ActualHeight;
        var delta = SongSectionHeader.JumpPinDelta(bottom, scroller.ViewportHeight);
        if (delta > 0) scroller.ChangeView(null, scroller.VerticalOffset + delta, null, true);
    }

    /// <summary>First-paint gate: decode the first rows' art (bounded), then fade the list in.</summary>
    /// <returns>Reveal task.</returns>
    private async Task RevealAsync()
    {
        revealed = true;
        LoadingRing.IsActive = true;
        var pixels = (int)Math.Ceiling(44 * (XamlRoot?.RasterizationScale ?? 1));
        using var cancellation = new CancellationTokenSource(ArtworkPrimeTimeout);
        var loads = ViewModel.Sections.SelectMany(s => s.Rows).Take(ArtworkPrimeCount)
            .Select(r => ArtworkImages.LoadAsync(r.Song.AlbumArt, pixels, cancellation.Token));
        await Task.WhenAny(Task.WhenAll(loads), Task.Delay(ArtworkPrimeTimeout));
        LoadingRing.IsActive = ViewModel.IsLoading;
        // Web fadeInUp stagger over the visible rows (FadeIn: 400 ms, 125 ms apart); a still list when motion is off.
        FadeIn.StaggerRealized(SongList);
        Zoom.Opacity = 1;
        UpdateStickyHeader();
    }

    /// <summary>Phased row realization: text first, then art and trailing content on phase 1.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.ItemContainer is not ListViewItem container || args.Item is not SongRowItem row) return;
        if (container.ContentTemplateRoot is not SongRowCard card) return;
        if (args.InRecycleQueue)
        {
            CancelArt(container);
            card.ApplyShop(null);
            return;
        }
        if (args.Phase == 0)
        {
            CancelArt(container);
            card.Reset();
            AutomationProperties.SetName(container, row.Announcement);
            AutomationProperties.SetAutomationId(container, $"fst.songs.row.{row.Song.SongId}");
            card.ApplyShop(row.Pulse);
            // Not Handled: x:Bind template bindings run in this same event.
            args.RegisterUpdateCallback(1, OnContainerContentChanging);
            return;
        }
        BuildTrailing(card, row);
        _ = LoadArtAsync(container, card.Art, row.Song);
    }

    /// <summary>Builds chips, metadata pills, the chart meter or the score-state text.</summary>
    /// <param name="card">Row card.</param>
    /// <param name="row">Row.</param>
    private void BuildTrailing(SongRowCard card, SongRowItem row)
    {
        var trailing = card.Trailing;
        var secondary = card.Secondary;
        trailing.Children.Clear();
        secondary.Children.Clear();
        var inlineChips = ListWidth() >= InlineChipsWidth;
        if (row.Chips.Count > 0)
        {
            var target = inlineChips ? trailing : secondary;
            foreach (var chip in row.Chips) target.Children.Add(SongRowVisuals.Chip(chip, row.Keyboard));
            secondary.LineAlignment = HorizontalAlignment.Left;
        }
        else if (row.Metadata.Count > 0)
        {
            var allInline = ListWidth() >= InlineMetadataWidth;
            if (row.NamesChart)
                trailing.Children.Add(new InstrumentIcon { File = row.Chart!.Value.IconFile(row.Keyboard), Label = row.Chart.Value.Label(), Width = 20, Height = 20 });
            for (var i = 0; i < row.Metadata.Count; i++)
                (i == 0 || allInline ? trailing : secondary).Children.Add(SongRowVisuals.Pill(row.Metadata[i]));
            secondary.LineAlignment = HorizontalAlignment.Right;
        }
        else
        {
            if (row.Chart is { } chart && row.ChartRaw is { } raw)
            {
                trailing.Children.Add(new InstrumentIcon { File = chart.IconFile(row.Keyboard), Label = chart.Label() });
                trailing.Children.Add(new DifficultyMeter { Raw = raw, VerticalAlignment = VerticalAlignment.Center });
            }
            if (row.ScoreState is { } state)
                trailing.Children.Add(new TextBlock { Text = state, Style = (Style)Application.Current.Resources["FSTSecondaryTextStyle"], VerticalAlignment = VerticalAlignment.Center });
        }
        var wrapped = secondary.Children.Count > 0;
        card.SetWrapped(wrapped);
    }

    /// <summary>Loads a row thumbnail unless the container is recycled first.</summary>
    /// <param name="container">Row container.</param>
    /// <param name="image">Target image.</param>
    /// <param name="song">Row song.</param>
    /// <returns>Load task.</returns>
    private async Task LoadArtAsync(ListViewItem container, Image image, Song song)
    {
        var cancellation = new CancellationTokenSource();
        artLoads[container] = cancellation;
        var pixels = (int)Math.Ceiling(44 * (XamlRoot?.RasterizationScale ?? 1));
        var bitmap = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, cancellation.Token);
        if (!cancellation.IsCancellationRequested && container.Content is SongRowItem current && ReferenceEquals(current.Song, song))
            image.Source = bitmap;
    }

    /// <summary>Cancels a row's pending art load.</summary>
    /// <param name="container">Row container.</param>
    private void CancelArt(ListViewItem container)
    {
        if (artLoads.Remove(container, out var pending)) pending.Cancel();
    }

    /// <summary>Current list width.</summary>
    /// <returns>Width in epx.</returns>
    private double ListWidth() => split ? SplitListWidth : SongList.ActualWidth > 0 ? SongList.ActualWidth : ActualWidth;

    /// <summary>Re-realizes rows when the layout crosses a trailing-content breakpoint.</summary>
    /// <param name="sender">Page.</param>
    /// <param name="e">Size change.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplySplit(e.NewSize.Width >= SplitWidth);
        ApplyLayout(e.NewSize.Width);
    }

    /// <summary>
    /// Lays out the toolbar and rows for the page width and the list column (narrower in the split layout).
    /// </summary>
    /// <param name="pageWidth">Page width in epx.</param>
    private void ApplyLayout(double pageWidth)
    {
        var compact = pageWidth < 640;
        // The split list column is as narrow as a compact page, so the search gets its own row there too.
        var narrowList = compact || split;
        JumpLabel.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        Grid.SetColumnSpan(SearchBox, narrowList ? 5 : 1);
        SearchColumn.MaxWidth = narrowList ? double.PositiveInfinity : 440;
        Grid.SetRow(ActionButtons, narrowList ? 1 : 0);
        Grid.SetColumn(ActionButtons, narrowList ? 0 : 1);
        Grid.SetColumnSpan(ActionButtons, narrowList ? 5 : 1);
        // Compact: the list's scroll indicator overlays the rows, so no right gutter is reserved for it and rows end
        // 12 epx from the edge like the left side (operator 7.24; was 16 epx).
        Root.Padding = compact ? new Thickness(12, 8, 12, 0) : new Thickness(24, 12, 12, 0);
        SongList.Padding = compact ? new Thickness(0, 0, 0, 24) : new Thickness(0, 0, 12, 24);
        Actions.Margin = Notices.Margin = compact ? new Thickness(0) : new Thickness(0, 0, 12, 0);
        var wide = ListWidth() >= InlineChipsWidth;
        if (wide == wideLayout) return;
        wideLayout = wide;
        if (GroupedSongs.Source is not null) RebindGroups();
    }

    /// <summary>Opens Song Detail, carrying the filtered chart.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnSongClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not SongRowItem row) return;
        // Split layout: the click selects the row and the detail column follows (SelectionChanged), no push.
        if (split) return;
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(row.Song.SongId, App.Session.Settings.SongFilter.Instrument));
    }

    #region Split layout
    /// <summary>
    /// Switches between the single list and list + detail (operator 2026-09-28, like Android foldables/iPad): the list
    /// keeps a fixed column, the selected song's detail fills the rest, and the first row is selected so the detail is
    /// never empty. With no rows the page is a single column again.
    /// </summary>
    /// <param name="wanted">Whether the page is wide enough.</param>
    private void ApplySplit(bool wanted)
    {
        var on = wanted && ViewModel.ShowList && ViewModel.Sections.Count > 0;
        if (on == split) return;
        split = on;
        ListColumn.Width = on ? new GridLength(SplitListWidth) : new GridLength(1, GridUnitType.Star);
        DetailColumn.Width = on ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        DetailFrame.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        SongList.SelectionMode = on ? ListViewSelectionMode.Single : ListViewSelectionMode.None;
        // The list column changed width: rebuild rows so chips wrap or sit inline for it, whatever the last breakpoint was.
        wideLayout = ListWidth() >= InlineChipsWidth;
        if (GroupedSongs.Source is not null) RebindGroups();
        ApplyLayout(ActualWidth);
        if (on)
        {
            EnsureSplitSelection();
            return;
        }
        detailTimer?.Stop();
        detailSongId = null;
        DetailFrame.Content = null;
    }

    /// <summary>Keeps a selection in the split layout: the current row if it survived a sort/filter, else the first.</summary>
    private void EnsureSplitSelection()
    {
        if (!split) return;
        if (ViewModel.Sections.Count == 0 || !ViewModel.ShowList)
        {
            ApplySplit(false);
            return;
        }
        var rows = ViewModel.Sections.SelectMany(section => section.Rows);
        var keep = detailSongId is null ? null : rows.FirstOrDefault(r => r.Song.SongId == detailSongId);
        var target = keep ?? rows.First();
        if (!ReferenceEquals(SongList.SelectedItem, target)) SongList.SelectedItem = target;
        ShowDetail(target, immediately: true);
    }

    /// <summary>The detail column follows the selected row (debounced for keyboard arrowing).</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Selection change.</param>
    private void OnSongSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (split && SongList.SelectedItem is SongRowItem row) ShowDetail(row, immediately: false);
    }

    /// <summary>Opens the row's Song Detail in the detail column (once per song).</summary>
    /// <param name="row">Selected row.</param>
    /// <param name="immediately">Skip the keyboard debounce.</param>
    private void ShowDetail(SongRowItem row, bool immediately)
    {
        detailTimer?.Stop();
        if (row.Song.SongId == detailSongId && DetailFrame.Content is not null) return;
        if (!immediately)
        {
            detailTimer ??= DispatcherQueue.CreateTimer();
            detailTimer.Interval = DetailFollowDelay;
            detailTimer.IsRepeating = false;
            detailTimer.Tick -= OnDetailTimer;
            detailTimer.Tick += OnDetailTimer;
            detailTimer.Start();
            return;
        }
        detailSongId = row.Song.SongId;
        DetailFrame.Navigate(typeof(SongDetailPage), new AppRoute.SongDetail(row.Song.SongId, App.Session.Settings.SongFilter.Instrument),
            new Microsoft.UI.Xaml.Media.Animation.SuppressNavigationTransitionInfo());
    }

    /// <summary>Shows the row selected when the debounce ends.</summary>
    /// <param name="sender">Timer.</param>
    /// <param name="args">Unused.</param>
    private void OnDetailTimer(DispatcherQueueTimer sender, object args)
    {
        if (split && SongList.SelectedItem is SongRowItem row) ShowDetail(row, immediately: true);
    }
    #endregion

    /// <summary>Applies search immediately on Enter.</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="args">Query.</param>
    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) =>
        ViewModel.SubmitSearchCommand.Execute(null);

    /// <summary>Escape closes the jump index back to the list (gap 5b), like the web's Quick Links sheet.</summary>
    /// <param name="sender">Semantic zoom.</param>
    /// <param name="e">Key.</param>
    private void OnZoomKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Escape || Zoom.IsZoomedInViewActive) return;
        Zoom.IsZoomedInViewActive = true;
        JumpButton.Focus(FocusState.Keyboard);
        e.Handled = true;
    }

    /// <inheritdoc />
    /// <remarks>Back closes an open jump index before anything navigates (operator batch 6.1).</remarks>
    public bool TryGoBack()
    {
        if (Zoom.IsZoomedInViewActive) return false;
        CloseJumpIndex();
        return true;
    }

    /// <summary>A click or tap outside the letters (not on an item) closes the jump index without picking.</summary>
    /// <param name="sender">Zoomed-out grid.</param>
    /// <param name="e">Tap.</param>
    private void OnJumpIndexTapped(object sender, TappedRoutedEventArgs e)
    {
        for (var node = e.OriginalSource as DependencyObject; node is not null && !ReferenceEquals(node, sender); node = VisualTreeHelper.GetParent(node))
            if (node is GridViewItem) return;
        CloseJumpIndex();
        e.Handled = true;
    }

    /// <summary>Returns to the list and puts focus back on the Jump button.</summary>
    private void CloseJumpIndex()
    {
        Zoom.IsZoomedInViewActive = true;
        JumpButton.Focus(FocusState.Programmatic);
    }

    /// <summary>Opens the jump index (semantic zoom out).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnJumpClick(object sender, RoutedEventArgs e)
    {
        if (Zoom.CanChangeViews) Zoom.IsZoomedInViewActive = false;
    }
    #endregion

    #region Sort and filter
    /// <summary>Loads the applied sort into the draft.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnSortOpening(object sender, object e) => ViewModel.SortDraft.Begin();

    /// <summary>Loads the applied filter into the draft.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterOpening(object sender, object e)
    {
        ViewModel.FilterDraft.Begin();
        // Fit the window: the Reset footer must stay on screen below the button at every size (compact 500 × 800 …).
        if (XamlRoot is { } root)
        {
            var below = root.Size.Height - FilterButton.TransformToVisual(null).TransformPoint(new(0, FilterButton.ActualHeight)).Y;
            FilterForm.MaxHeight = Math.Clamp(below - 24, 280, 680);
            FilterForm.Width = Math.Clamp(root.Size.Width - 32, 280, 440);
        }
        FilterInstrumentPicker.Instruments = ViewModel.FilterDraft.Instruments;
        FilterInstrumentPicker.Selected = ViewModel.FilterDraft.SelectedInstrument;
    }

    /// <summary>Instrument Selector choice (web <c>instrumentFilter</c>): applies live and reveals its bucket sections.</summary>
    /// <param name="sender">Selector.</param>
    /// <param name="instrument">Chart, or <see langword="null"/> when cleared.</param>
    private void OnFilterInstrumentChanged(object? sender, Instrument? instrument) => ViewModel.FilterDraft.SelectedInstrument = instrument;

    /// <summary>Tints Sort/Filter gold when a non-default choice is applied.</summary>
    private void UpdateButtonTints()
    {
        var gold = Brush("FSTEmphasisBrush");
        SortButton.ClearValue(ForegroundProperty);
        FilterButton.ClearValue(ForegroundProperty);
        if (ViewModel.IsSortChanged) SortButton.Foreground = gold;
        if (ViewModel.IsFilterActive) FilterButton.Foreground = gold;
    }

    /// <summary>Looks up an app brush.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
    #endregion

    #region Perf scenario
    /// <summary>
    /// Continuously scrolls the list (<c>--auto-scroll</c>) to measure frame delivery; <c>--auto-scroll-speed</c> sets a
    /// steady pace in epx/s and <c>--auto-scroll-span</c> turns back early (slow section-boundary checks, issue #288).
    /// </summary>
    private void StartAutoScroll()
    {
        if (autoScroll is not null) return;
        var clock = System.Diagnostics.Stopwatch.StartNew();
        autoScroll = DispatcherQueue.CreateTimer();
        autoScroll.Interval = TimeSpan.FromMilliseconds(16);
        autoScroll.Tick += (_, _) =>
        {
            var elapsed = clock.Elapsed.TotalSeconds;
            clock.Restart();
            if (EnsureScroller() is not { } viewer) return;
            if (App.Options.AutoScrollSpeed is { } speed)
                scrollStep = Math.CopySign(speed * Math.Min(elapsed, 0.1), scrollStep);
            var end = Math.Min(viewer.ScrollableHeight, App.Options.AutoScrollSpan ?? double.MaxValue);
            var next = viewer.VerticalOffset + scrollStep;
            if (next >= end || next <= 0) scrollStep = -scrollStep;
            viewer.ChangeView(null, Math.Clamp(next, 0, end), null, true);
        };
        autoScroll.Start();
    }

    /// <summary>Finds the first ScrollViewer below an element.</summary>
    /// <param name="root">Root element.</param>
    /// <returns>ScrollViewer or <see langword="null"/>.</returns>
    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is ScrollViewer viewer) return viewer;
            if (FindScrollViewer(child) is { } nested) return nested;
        }
        return null;
    }
    #endregion
}

/// <summary>A list group: header label plus rows.</summary>
public sealed partial class SongGroup : List<SongRowItem>
{
    /// <summary>Creates a group.</summary>
    /// <param name="label">Header ("" hides it).</param>
    /// <param name="rows">Rows.</param>
    /// <param name="isFirst">Whether it is the list's first section (the sticky bar names it, so it has no in-list header).</param>
    public SongGroup(string label, IEnumerable<SongRowItem> rows, bool isFirst = false) : base(rows)
    {
        Label = label;
        ShowInlineHeader = HasLabel && !isFirst;
    }

    /// <summary>White Title Case header.</summary>
    public string Label { get; }

    /// <summary>Whether the header shows (a single Shop bucket has none).</summary>
    public bool HasLabel => Label.Length > 0;

    /// <summary>Whether the in-list header shows: labelled sections after the first.</summary>
    public bool ShowInlineHeader { get; }
}
#endregion
