using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Songs page
/// <summary>Songs catalogue: grouped, virtualized list with a semantic-zoom jump index, search, sort and filter.</summary>
public sealed partial class SongsPage : Page
{
    private readonly Dictionary<ListViewItem, CancellationTokenSource> artLoads = [];
    private DispatcherQueueTimer? autoScroll;
    private ScrollViewer? scroller;
    private double scrollStep = 6;

    /// <summary>Creates the page.</summary>
    public SongsPage()
    {
        ViewModel = new SongsViewModel(App.Session);
        InitializeComponent();
        ViewModel.PropertyChanged += OnViewModelChanged;
        Loaded += (_, _) => UpdateButtonTints();
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
                GroupedSongs.Source = ViewModel.Sections.Select(s => new SongGroup(s.Label, s.Songs)).ToList();
                if (ViewModel.Sections.Count > 0)
                {
                    PerfLog.Mark("songs-rendered");
                    if (App.Options.AutoScroll) StartAutoScroll();
                }
                break;
            case nameof(SongsViewModel.IsSortChanged) or nameof(SongsViewModel.IsFilterActive):
                UpdateButtonTints();
                break;
        }
    }

    /// <summary>Phased row realization: text first, then art on phase 1.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.ItemContainer is not ListViewItem container || args.Item is not Song song) return;
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
            AutomationProperties.SetName(container, $"{song.Title}, {song.Subtitle}");
            var chart = (FrameworkElement)root.FindName("Chart");
            if (App.Session.Settings.SongFilter.Instrument is { } instrument && song.Difficulty?.ChartedValue(instrument) is { } raw)
            {
                var icon = (InstrumentIcon)root.FindName("ChartIcon");
                icon.File = instrument.IconFile(song.UsesKeyboardIcon);
                icon.Label = instrument.Label();
                ((DifficultyMeter)root.FindName("ChartMeter")).Raw = raw;
                chart.Visibility = Visibility.Visible;
            }
            else
            {
                chart.Visibility = Visibility.Collapsed;
            }
            // Not Handled: x:Bind template bindings run in this same event.
            args.RegisterUpdateCallback(1, OnContainerContentChanging);
            return;
        }
        _ = LoadArtAsync(container, (Image)root.FindName("Art"), song);
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
        if (!cancellation.IsCancellationRequested && ReferenceEquals(container.Content, song)) image.Source = bitmap;
    }

    /// <summary>Cancels a row's pending art load.</summary>
    /// <param name="container">Row container.</param>
    private void CancelArt(ListViewItem container)
    {
        if (artLoads.Remove(container, out var pending)) pending.Cancel();
    }

    /// <summary>Opens Song Detail, carrying the filtered chart.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked song.</param>
    private void OnSongClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is Song song)
            MainWindow.Instance?.Navigate(new AppRoute.SongDetail(song.SongId, App.Session.Settings.SongFilter.Instrument));
    }

    /// <summary>Applies search immediately on Enter.</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="args">Query.</param>
    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) =>
        ViewModel.SubmitSearchCommand.Execute(null);
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
        var gold = (Brush)Application.Current.Resources["FSTGoldBrush"];
        SortButton.ClearValue(ForegroundProperty);
        FilterButton.ClearValue(ForegroundProperty);
        if (ViewModel.IsSortChanged) SortButton.Foreground = gold;
        if (ViewModel.IsFilterActive) FilterButton.Foreground = gold;
    }
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
public sealed partial class SongGroup : List<Song>
{
    /// <summary>Creates a group.</summary>
    /// <param name="label">Header.</param>
    /// <param name="songs">Rows.</param>
    public SongGroup(string label, IEnumerable<Song> songs) : base(songs) => Label = label;

    /// <summary>White Title Case header.</summary>
    public string Label { get; }
}
#endregion
