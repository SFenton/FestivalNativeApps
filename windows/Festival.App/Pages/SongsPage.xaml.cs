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
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace Festival.App.Pages;

#region Songs page
/// <summary>
/// Songs catalogue: grouped, virtualized list with a semantic-zoom jump index, search, sort and filter, same-publication
/// Item Shop accents and the selected player's status chips or metadata pills. Rows realize in phases (text, then
/// art and trailing content) and reveal once the first rows' art has decoded (bounded).
/// </summary>
public sealed partial class SongsPage : Page
{
    /// <summary>Rows whose art is decoded before the first reveal.</summary>
    private const int ArtworkPrimeCount = 12;

    /// <summary>Upper bound on the first-reveal wait.</summary>
    private static readonly TimeSpan ArtworkPrimeTimeout = TimeSpan.FromMilliseconds(900);

    /// <summary>List width at which chips sit inline instead of under the title.</summary>
    private const double InlineChipsWidth = 760;

    /// <summary>List width at which every metadata pill sits inline.</summary>
    private const double InlineMetadataWidth = 1100;

    private readonly Dictionary<ListViewItem, CancellationTokenSource> artLoads = [];
    private DispatcherQueueTimer? autoScroll;
    private ScrollViewer? scroller;
    private double scrollStep = 6;
    private bool revealed;
    private bool wideLayout;

    /// <summary>Creates the page.</summary>
    public SongsPage()
    {
        ViewModel = new SongsViewModel(App.Session);
        InitializeComponent();
        ViewModel.PropertyChanged += OnViewModelChanged;
        Loaded += (_, _) => UpdateButtonTints();
        SizeChanged += OnSizeChanged;
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
                GroupedSongs.Source = ViewModel.Sections.Select(s => new SongGroup(s.Label, s.Rows)).ToList();
                if (ViewModel.Sections.Count > 0)
                {
                    if (!revealed) _ = RevealAsync();
                    PerfLog.Mark("songs-rendered");
                    if (App.Options.AutoScroll) StartAutoScroll();
                }
                break;
            case nameof(SongsViewModel.IsSortChanged) or nameof(SongsViewModel.IsFilterActive):
                UpdateButtonTints();
                break;
        }
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
        if (!MotionAllowed())
        {
            Zoom.Opacity = 1;
            return;
        }
        var fade = new DoubleAnimation { From = 0, To = 1, Duration = TimeSpan.FromMilliseconds(200), EnableDependentAnimation = false };
        Storyboard.SetTarget(fade, Zoom);
        Storyboard.SetTargetProperty(fade, "Opacity");
        var story = new Storyboard();
        story.Children.Add(fade);
        story.Completed += (_, _) => Zoom.Opacity = 1;
        story.Begin();
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
            AutomationProperties.SetName(container, row.Announcement);
            AutomationProperties.SetAutomationId(container, $"fst.songs.row.{row.Song.SongId}");
            ApplyHighlight(root, row.Highlight);
            HookMarquee(container);
            // Not Handled: x:Bind template bindings run in this same event.
            args.RegisterUpdateCallback(1, OnContainerContentChanging);
            return;
        }
        BuildTrailing(root, row);
        _ = LoadArtAsync(container, (Image)root.FindName("Art"), row.Song);
    }

    /// <summary>Paints the Shop accent border (gold New, red Leaving Tomorrow).</summary>
    /// <param name="card">Row card.</param>
    /// <param name="highlight">Accent.</param>
    private static void ApplyHighlight(Grid card, ShopHighlight? highlight)
    {
        if (highlight is { } h)
        {
            card.BorderBrush = Brush(h == ShopHighlight.LeavingTomorrow ? "FSTStatusRedBrush" : "FSTGoldBrush");
            card.BorderThickness = new Thickness(2);
        }
        else
        {
            card.BorderBrush = Brush("FSTCardStrokeBrush");
            card.BorderThickness = new Thickness(1);
        }
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
        secondary.Visibility = secondary.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
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

    /// <summary>Plays the row's marquees while it is hovered or focused (never while idle).</summary>
    /// <param name="container">Row container.</param>
    private void HookMarquee(ListViewItem container)
    {
        if (container.Tag is "marquee") return;
        container.Tag = "marquee";
        container.PointerEntered += (_, _) => SetMarquee(container, true);
        container.PointerExited += (_, _) => SetMarquee(container, false);
        container.PointerCanceled += (_, _) => SetMarquee(container, false);
        container.GotFocus += (_, _) => SetMarquee(container, container.FocusState == FocusState.Keyboard);
        container.LostFocus += (_, _) => SetMarquee(container, false);
    }

    /// <summary>Starts or stops a row's title and subtitle marquees.</summary>
    /// <param name="container">Row container.</param>
    /// <param name="play">Whether to play.</param>
    private static void SetMarquee(ListViewItem container, bool play)
    {
        if (container.ContentTemplateRoot is not Grid root) return;
        MarqueeText.MotionAllowed = MotionAllowed();
        foreach (var name in new[] { "TitleText", "SubtitleText" })
        {
            if (root.FindName(name) is not MarqueeText marquee) continue;
            if (play) marquee.Play();
            else marquee.Stop();
        }
    }

    /// <summary>Whether in-app and system settings allow motion.</summary>
    /// <returns><see langword="true"/> when animations may run.</returns>
    private static bool MotionAllowed() =>
        !App.Session.Settings.ReduceMotion && !App.Options.ReduceMotion && new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;

    /// <summary>Current list width.</summary>
    /// <returns>Width in epx.</returns>
    private double ListWidth() => SongList.ActualWidth > 0 ? SongList.ActualWidth : ActualWidth;

    /// <summary>Re-realizes rows when the layout crosses a trailing-content breakpoint.</summary>
    /// <param name="sender">Page.</param>
    /// <param name="e">Size change.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var wide = ListWidth() >= InlineChipsWidth;
        var compact = e.NewSize.Width < 640;
        JumpLabel.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        // Compact: search takes its own full-width row above Sort/Filter/Jump.
        Grid.SetColumnSpan(SearchBox, compact ? 5 : 1);
        SearchColumn.MaxWidth = compact ? double.PositiveInfinity : 440;
        Grid.SetRow(ActionButtons, compact ? 1 : 0);
        Grid.SetColumn(ActionButtons, compact ? 0 : 1);
        Grid.SetColumnSpan(ActionButtons, compact ? 5 : 1);
        Root.Padding = compact ? new Thickness(12, 8, 4, 0) : new Thickness(24, 12, 12, 0);
        if (wide == wideLayout) return;
        wideLayout = wide;
        if (GroupedSongs.Source is not null) GroupedSongs.Source = ViewModel.Sections.Select(s => new SongGroup(s.Label, s.Rows)).ToList();
    }

    /// <summary>Opens Song Detail, carrying the filtered chart.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnSongClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is SongRowItem row)
            MainWindow.Instance?.Navigate(new AppRoute.SongDetail(row.Song.SongId, App.Session.Settings.SongFilter.Instrument));
    }

    /// <summary>Applies search immediately on Enter.</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="args">Query.</param>
    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) =>
        ViewModel.SubmitSearchCommand.Execute(null);

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

    /// <summary>Discards the sort draft.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnSortCancel(object sender, RoutedEventArgs e) => SortFlyout.Hide();

    /// <summary>Applies the sort draft.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnSortApply(object sender, RoutedEventArgs e)
    {
        ViewModel.ApplySortCommand.Execute(null);
        SortFlyout.Hide();
    }

    /// <summary>Loads the applied filter into the draft.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterOpening(object sender, object e) => ViewModel.FilterDraft.Begin();

    /// <summary>Discards the filter draft.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterCancel(object sender, RoutedEventArgs e) => FilterFlyout.Hide();

    /// <summary>Applies the filter draft.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterApply(object sender, RoutedEventArgs e)
    {
        ViewModel.ApplyFilterCommand.Execute(null);
        FilterFlyout.Hide();
    }

    /// <summary>Tints Sort/Filter gold when a non-default choice is applied.</summary>
    private void UpdateButtonTints()
    {
        var gold = Brush("FSTGoldBrush");
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
    public SongGroup(string label, IEnumerable<SongRowItem> rows) : base(rows) => Label = label;

    /// <summary>White Title Case header.</summary>
    public string Label { get; }

    /// <summary>Whether the header shows (a single Shop bucket has none).</summary>
    public bool HasLabel => Label.Length > 0;
}
#endregion
