using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
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
    private List<SongGroup> stickyGroups = [];
    private bool wideLayout;

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
        Zoom.ViewChangeCompleted += (_, _) => UpdateStickyHeader();
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
                    (scroller ??= FindScrollViewer(SongList))?.ChangeView(null, 0, null, true);
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
        var groups = ViewModel.Sections.Select((s, i) => new SongGroup(s.Label, s.Rows, i == 0)).ToList();
        groupStarts = new int[groups.Count];
        for (int i = 0, start = 0; i < groups.Count; start += groups[i].Count, i++) groupStarts[i] = start;
        stickyGroups = groups;
        GroupedSongs.Source = groups;
        UpdateStickyHeader();
    }

    /// <summary>
    /// Shows the label of the section holding the first visible row in the bar above the list. Runs on scroll view
    /// changes only (no per-frame work while idle).
    /// </summary>
    private void UpdateStickyHeader()
    {
        if (scroller is null && (scroller = FindScrollViewer(SongList)) is not null)
            scroller.ViewChanged += (_, _) => UpdateStickyHeader();
        var first = SongList.ItemsPanelRoot is ItemsStackPanel panel && panel.FirstVisibleIndex >= 0 ? panel.FirstVisibleIndex : 0;
        var index = Array.BinarySearch(groupStarts, first);
        if (index < 0) index = ~index - 1;
        var label = index >= 0 && index < stickyGroups.Count ? stickyGroups[index].Label : "";
        StickyHeader.Text = label;
        var shown = label.Length > 0 && Zoom.IsZoomedInViewActive && ViewModel.ShowList && Zoom.Opacity > 0;
        StickyHeader.Visibility = shown ? Visibility.Visible : Visibility.Collapsed;
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
        if (container.ContentTemplateRoot is not Grid root) return;
        if (args.InRecycleQueue)
        {
            CancelArt(container);
            ((ShopPulseRing)root.FindName("ShopRing")).Apply(null);
            return;
        }
        if (args.Phase == 0)
        {
            CancelArt(container);
            ((Image)root.FindName("Art")).Source = null;
            ((Panel)root.FindName("Trailing")).Children.Clear();
            var secondary = (Panel)root.FindName("Secondary");
            secondary.Children.Clear();
            secondary.Visibility = Visibility.Collapsed;
            Grid.SetRowSpan((FrameworkElement)root.FindName("ArtHost"), 1);
            AutomationProperties.SetName(container, row.Announcement);
            AutomationProperties.SetAutomationId(container, $"fst.songs.row.{row.Song.SongId}");
            ((ShopPulseRing)root.FindName("ShopRing")).Apply(row.Pulse);
            var badge = (Border)root.FindName("ShopBadge");
            badge.Visibility = row.Pulse is null ? Visibility.Collapsed : Visibility.Visible;
            if (row.Pulse is { } pulse)
            {
                // Contrast themes: Highlight / HighlightText instead of the brand gold/red bag.
                var contrast = Services.ContrastTheme.IsOn;
                badge.Background = contrast ? Services.ContrastTheme.Brush("FSTShopNewBrush")
                    : new SolidColorBrush(Color.FromArgb(0xFF, (byte)(pulse.Argb >> 16), (byte)(pulse.Argb >> 8), (byte)pulse.Argb));
                if (contrast)
                {
                    badge.BorderBrush = Services.ContrastTheme.Brush("FSTShopBadgeTextBrush");
                    ((FontIcon)badge.Child).Foreground = Services.ContrastTheme.Brush("FSTShopBadgeTextBrush");
                }
            }
            // Not Handled: x:Bind template bindings run in this same event.
            args.RegisterUpdateCallback(1, OnContainerContentChanging);
            return;
        }
        BuildTrailing(root, row);
        _ = LoadArtAsync(container, (Image)root.FindName("Art"), row.Song);
    }

    /// <summary>Builds chips, metadata pills, the chart meter or the score-state text.</summary>
    /// <param name="card">Row card.</param>
    /// <param name="row">Row.</param>
    private void BuildTrailing(Grid card, SongRowItem row)
    {
        var trailing = (Panel)card.FindName("Trailing");
        var secondary = (FlowPanel)card.FindName("Secondary");
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
        secondary.Visibility = wrapped ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetRowSpan((FrameworkElement)card.FindName("ArtHost"), wrapped ? 2 : 1);
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
    /// <summary>Continuously scrolls the list (<c>--auto-scroll</c>) to measure frame delivery.</summary>
    private void StartAutoScroll()
    {
        if (autoScroll is not null) return;
        autoScroll = DispatcherQueue.CreateTimer();
        autoScroll.Interval = TimeSpan.FromMilliseconds(16);
        autoScroll.Tick += (_, _) =>
        {
            scroller ??= FindScrollViewer(SongList);
            if (scroller is null) return;
            var next = scroller.VerticalOffset + scrollStep;
            if (next >= scroller.ScrollableHeight || next <= 0) scrollStep = -scrollStep;
            scroller.ChangeView(null, Math.Clamp(next, 0, scroller.ScrollableHeight), null, true);
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
