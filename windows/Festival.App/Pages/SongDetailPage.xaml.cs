using System.ComponentModel;
using System.Diagnostics;
using Festival.App.Services;
using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song detail page
/// <summary>
/// Song Detail: header, Intensity for every charted instrument, the selected player's score history and a top-10 card per
/// visible chart. Also hosts the score-history route (<c>/songs/:id/:instrument/history</c>), opened scrolled to history.
/// </summary>
public sealed partial class SongDetailPage : Page, IBackdropPage
{
    private readonly QuickLinksViewModel quickLinks = new("Quick Links");
    private CancellationTokenSource headerArt = new();
    private long navigatedAt;
    private long revealedAt;
    private bool revealing;

    /// <summary>Creates the page; its Quick Links menu shows on compact windows only.</summary>
    public SongDetailPage()
    {
        InitializeComponent();
        var host = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, pane: null, menuMaxWidth: 640);
        // Cards far below the viewport are not realized yet (virtualizing grid): realize one on demand for a jump.
        host.Binder.Resolve = id => ViewModel?.Leaderboards.FindIndex(c => c.QuickLinkId == id) is >= 0 and var index
            ? Boards.GetOrCreateElement(index) as FrameworkElement
            : null;
        HistorySelector.SelectionChanged += (_, instrument) =>
        {
            if (instrument is { } chart) ViewModel?.History.SelectInstrument(chart);
        };
    }

    /// <summary>Page model (set on navigation).</summary>
    public SongDetailViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        navigatedAt = Stopwatch.GetTimestamp();
        ViewModel = e.Parameter is AppRoute.PlayerHistory history
            ? new SongDetailViewModel(App.Session, history)
            : new SongDetailViewModel(App.Session, (AppRoute.SongDetail)e.Parameter);
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.History.PropertyChanged += OnHistoryChanged;
        Bindings.Update();
        await ViewModel.LoadCommand.ExecuteAsync(null);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        headerArt.Cancel();
        ViewModel?.Detach();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Loads header art, updates the backdrop and runs the reveal once the page is ready.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SongDetailViewModel.ShopHighlight) or nameof(SongDetailViewModel.ShopPulses)) ApplyShopPulse();
        if (e.PropertyName == nameof(SongDetailViewModel.QuickLinkSections)) quickLinks.SetSections(ViewModel.QuickLinkSections);
        if (e.PropertyName == nameof(SongDetailViewModel.State)) OnStateChanged();
        if (e.PropertyName != nameof(SongDetailViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(128 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
        PinnedArt.Source = HeaderArt.Source;
        PerfLog.Mark("song-detail-rendered");
    }

    /// <summary>Keeps the instrument selector in step with the history section.</summary>
    /// <param name="sender">History model.</param>
    /// <param name="e">Changed property.</param>
    private void OnHistoryChanged(object? sender, PropertyChangedEventArgs e)
    {
        var history = ViewModel.History;
        if (e.PropertyName is nameof(SongScoreHistoryViewModel.Instruments))
        {
            HistorySelector.KeyboardLead = history.KeyboardLead;
            HistorySelector.Instruments = history.Instruments;
        }
        if (e.PropertyName is nameof(SongScoreHistoryViewModel.Instruments) or nameof(SongScoreHistoryViewModel.Selected))
            HistorySelector.Selected = history.Selected;
    }

    #region Reveal
    /// <summary>
    /// Spinner until ready, then (web <c>useLoadPhase</c>) the spinner fades out and the sections fade up in order; a
    /// failure just drops the spinner. Loads that finished almost at once reveal without animation.
    /// </summary>
    private void OnStateChanged()
    {
        switch (ViewModel.State)
        {
            case LoadState.Loading:
                Spinner.Visibility = Visibility.Visible;
                Spinner.IsActive = true;
                ElementCompositionPreview.GetElementVisual(Spinner).Opacity = 1;
                break;
            case LoadState.Failed:
                StopSpinner();
                break;
            case LoadState.Loaded:
                var animate = SongDetailReveal.Animates(Stopwatch.GetElapsedTime(navigatedAt), Motion.Allowed);
                if (!animate)
                {
                    StopSpinner();
                    AfterReveal();
                    return;
                }
                // Content stays transparent (not collapsed, so layout and card realization proceed) until the spinner fades.
                foreach (var section in Sections()) ElementCompositionPreview.GetElementVisual(section).Opacity = 0;
                FadeOutSpinner();
                break;
        }
    }

    /// <summary>The sections that fade up, in reveal order with their delays.</summary>
    /// <returns>Sections.</returns>
    private UIElement[] Sections() => [FullHeader, IntensitySection, HistorySection, LeaderboardsSection];

    /// <summary>Fades the spinner out on the compositor, then staggers the content in.</summary>
    private void FadeOutSpinner()
    {
        var visual = ElementCompositionPreview.GetElementVisual(Spinner);
        var fade = visual.Compositor.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(1f, 0f);
        fade.Duration = SongDetailReveal.SpinnerFade;
        var batch = visual.Compositor.CreateScopedBatch(Microsoft.UI.Composition.CompositionBatchTypes.Animation);
        visual.StartAnimation("Opacity", fade);
        batch.End();
        batch.Completed += (_, _) => DispatcherQueue.TryEnqueue(() =>
        {
            StopSpinner();
            revealing = true;
            revealedAt = Stopwatch.GetTimestamp();
            FadeIn.Play(FullHeader, SongDetailReveal.Header);
            FadeIn.Play(IntensitySection, SongDetailReveal.Intensity);
            FadeIn.Play(HistorySection, SongDetailReveal.History);
            FadeIn.Play(LeaderboardsSection, SongDetailReveal.Leaderboards);
            for (var i = 0; i < (ViewModel?.Leaderboards.Count ?? 0); i++)
                if (Boards.TryGetElement(i) is UIElement card) FadeIn.Play(card, SongDetailReveal.Card(i, BoardColumns()));
            AfterReveal();
        });
    }

    /// <summary>Hides the spinner.</summary>
    private void StopSpinner()
    {
        Spinner.IsActive = false;
        Spinner.Visibility = Visibility.Collapsed;
    }

    /// <summary>Post-reveal: the history route scrolls to the history section.</summary>
    private void AfterReveal()
    {
        if (!ViewModel.ScrollToHistory || !ViewModel.History.IsVisible) return;
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            var top = HistorySection.TransformToVisual(Scroller.Content as UIElement).TransformPoint(default).Y;
            Scroller.ChangeView(null, Math.Max(0, top - 64), null, disableAnimation: !Motion.Allowed);
        });
    }

    /// <summary>Cards per row in the leaderboard grid (two from 2 × 340 + 16 epx).</summary>
    /// <returns>1 or 2.</returns>
    private int BoardColumns() => Boards.ActualWidth >= 2 * 340 + 16 ? 2 : 1;
    #endregion

    /// <summary>Applies the Item Shop button's status fill (gold New, red Leaving Tomorrow, green otherwise).</summary>
    private void ApplyShopPulse() => ShopFill.Apply(ViewModel.ShopHighlight, ViewModel.ShopPulses);

    /// <summary>Pins the compact header once the full header has scrolled out of view.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">Unused.</param>
    private void OnScrollerViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        var pinned = Scroller.VerticalOffset > FullHeader.ActualHeight + 12;
        var wanted = pinned ? Visibility.Visible : Visibility.Collapsed;
        if (PinnedHeader.Visibility != wanted) PinnedHeader.Visibility = wanted;
    }

    /// <summary>Intensity: three cells per row (3×3) at compact/medium, all in one row when they fit at wide widths.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="e">New size.</param>
    private void OnIntensitySizeChanged(object sender, SizeChangedEventArgs e)
    {
        var columns = SongDetailLayout.IntensityColumns(e.NewSize.Width, ViewModel?.Intensity.Count ?? 0);
        if (IntensityLayout.MaximumRowsOrColumns != columns) IntensityLayout.MaximumRowsOrColumns = columns;
    }

    /// <summary>Fills a realized card (Retry path) and staggers cards realized during the reveal.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnBoardPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (sender.ItemsSourceView?.GetAt(args.Index) is LeaderboardPreviewViewModel card) _ = card.EnsureLoadedAsync();
        if (revealing && FadeInTiming.WithinWindow(Stopwatch.GetElapsedTime(revealedAt)))
            FadeIn.Play(args.Element, SongDetailReveal.Card(args.Index, BoardColumns()));
        else
            FadeIn.Reset(args.Element);
    }

    /// <summary>Opens a band-size leaderboard for this song.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnBandLink(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: AppRoute route }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Checks the current mode and direction when the history sort menu opens.</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnSortMenuOpening(object sender, object e)
    {
        foreach (var item in SortMenu.Items.OfType<RadioMenuFlyoutItem>())
        {
            item.IsChecked = item.Tag switch
            {
                "asc" => ViewModel.History.SortAscending,
                "desc" => !ViewModel.History.SortAscending,
                string mode => mode == ViewModel.History.SortMode.ToString(),
                _ => false,
            };
        }
    }

    /// <summary>Applies a history sort key.</summary>
    /// <param name="sender">Menu item.</param>
    /// <param name="e">Unused.</param>
    private void OnSortModeClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && Enum.TryParse<PlayerScoreSortMode>(tag, out var mode))
            ViewModel.History.SortByCommand.Execute(mode);
    }

    /// <summary>Applies a history sort direction.</summary>
    /// <param name="sender">Menu item.</param>
    /// <param name="e">Unused.</param>
    private void OnSortDirectionClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && (tag == "asc") != ViewModel.History.SortAscending)
            ViewModel.History.ToggleDirectionCommand.Execute(null);
    }

    /// <summary>Opens the validated official Item Shop page.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnShopClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.ShopOffer?.ShopUri is { } uri) await Windows.System.Launcher.LaunchUriAsync(uri);
    }

    /// <summary>Opens the CHOpt Paths dialog (reset to Expert and the saved image/text default on every opening).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnPathsClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.CreatePaths() is not { } paths) return;
        await SongPathsView.ShowAsync(XamlRoot, paths, $"Paths · {ViewModel.Song?.Title}");
    }

    /// <summary>Opens the full 25-row leaderboard route.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnViewFull(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: LeaderboardPreviewViewModel card }) MainWindow.Instance?.Navigate(card.FullRoute);
    }
}
#endregion
