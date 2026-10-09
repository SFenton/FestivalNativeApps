using System.ComponentModel;
using System.Diagnostics;
using System.Numerics;
using Festival.App.Services;
using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song detail page
/// <summary>
/// Song Detail: header, Intensity for every charted instrument, the selected player's score history and a top-10 card per
/// visible chart. Its View All Scores opens the separate Player History page (<c>/songs/:id/:instrument/history</c>, issue #324).
/// </summary>
public sealed partial class SongDetailPage : Page, IBackdropPage
{
    private readonly QuickLinksViewModel quickLinks = new("Quick Links");
    private CancellationTokenSource headerArt = new();
    private long navigatedAt;
    private readonly ScoreHistorySwapper historySwap;
    private Storyboard? historyRelease;

    /// <summary>Pinned header's last laid-out height (0 until first shown); it reads 0 while collapsed.</summary>
    private double pinnedHeaderHeight;

    /// <summary>Creates the page; its Quick Links menu shows on compact windows only.</summary>
    public SongDetailPage()
    {
        InitializeComponent();
        var host = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, pane: null, menuMaxWidth: 640);
        // Realize a card on demand for a jump (the card grid realizes all, but a jump can run before the first layout).
        host.Binder.Resolve = id => ViewModel?.Leaderboards.FindIndex(c => c.QuickLinkId == id) is >= 0 and var index
            ? Boards.GetOrCreateElement(index) as FrameworkElement
            : ViewModel?.BandPreviews.FindIndex(b => b.QuickLinkId == id) is >= 0 and var band
                ? BandBoards.GetOrCreateElement(band) as FrameworkElement
                : null;
        // Sections land below the pinned compact header rather than under it (#251).
        host.Binder.ObscuredTop = offset =>
            SongDetailLayout.PinnedHeaderInset(offset, FullHeader.ActualHeight, pinnedHeaderHeight);
        PinnedHeader.SizeChanged += (_, e) =>
        {
            if (e.NewSize.Height > 0) pinnedHeaderHeight = e.NewSize.Height;
        };
        historySwap = new ScoreHistorySwapper(
            () => ViewModel?.History.Selected,
            chart => ViewModel?.History.SelectInstrument(chart),
            FadeHistoryAsync,
            HoldHistoryCard);
        // The selector shows the new chart at once; the graph fades over to it (issue #61).
        HistorySelector.SelectionChanged += (_, instrument) => _ = historySwap.RequestAsync(instrument, !Motion.Allowed);
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
        ViewModel = new SongDetailViewModel(App.Session, (AppRoute.SongDetail)e.Parameter);
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
        // Raised before the switch clears the row, so the closed row's height is still laid out (issue #261).
        if (e.PropertyName is nameof(SongScoreHistoryViewModel.ReservesDetail))
            HistoryDetailSlot.MinHeight = history.ReservesDetail ? Math.Max(HistoryDetail.ActualHeight, HistoryDetailSlot.ActualHeight) : 0;
    }

    #region Score history swap
    /// <summary>The parts of Score History that fade when the chart changes: graph, detail row, pager row and list.</summary>
    /// <returns>Elements.</returns>
    private UIElement[] HistorySwapTargets() => [HistoryChart, HistoryDetail, HistoryPagerSlot, HistoryRows, HistoryViewAll];

    /// <summary>Fades the score-history graph and list to <paramref name="opacity"/> on their composition visuals.</summary>
    /// <param name="opacity">Target opacity.</param>
    /// <param name="duration">Duration; zero sets it at once.</param>
    /// <param name="token">Cancelled by a newer swap (which restarts the fade from the current opacity).</param>
    /// <returns>Completes when the fade ends.</returns>
    private Task FadeHistoryAsync(double opacity, TimeSpan duration, CancellationToken token)
    {
        var instant = duration <= TimeSpan.Zero;
        foreach (var element in HistorySwapTargets())
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            if (instant)
            {
                visual.StopAnimation("Opacity");
                visual.Opacity = (float)opacity;
                continue;
            }
            var compositor = visual.Compositor;
            // Material/Fluent standard curves: accelerate out, decelerate in.
            var ease = opacity < 1
                ? compositor.CreateCubicBezierEasingFunction(new Vector2(0.4f, 0f), new Vector2(1f, 1f))
                : compositor.CreateCubicBezierEasingFunction(new Vector2(0f, 0f), new Vector2(0.2f, 1f));
            var fade = compositor.CreateScalarKeyFrameAnimation();
            fade.InsertKeyFrame(1f, (float)opacity, ease);
            fade.Duration = duration;
            visual.StartAnimation("Opacity", fade);
        }
        return instant ? Task.CompletedTask : Task.Delay(duration, token);
    }

    /// <summary>
    /// Holds the Score History card at its current height while the chart swaps, or releases it (easing down to the new
    /// content height when motion is allowed). The reserved pager and detail slots keep the natural height equal across
    /// charts, so the release normally moves nothing.
    /// </summary>
    /// <param name="hold">Hold or release.</param>
    private void HoldHistoryCard(bool hold)
    {
        historyRelease?.Stop();
        historyRelease = null;
        if (hold)
        {
            HistoryCard.MinHeight = Math.Max(HistoryCard.MinHeight, HistoryCard.ActualHeight);
            return;
        }
        var held = HistoryCard.MinHeight;
        HistoryCard.MinHeight = 0;
        if (held <= 0 || !Motion.Allowed) return;
        var release = new DoubleAnimation
        {
            From = held,
            To = 0,
            Duration = new Duration(ScoreHistorySwap.FadeIn),
            EnableDependentAnimation = true,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        Storyboard.SetTarget(release, HistoryCard);
        Storyboard.SetTargetProperty(release, nameof(FrameworkElement.MinHeight));
        historyRelease = new Storyboard { Children = { release } };
        historyRelease.Begin();
    }
    #endregion

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
                    return;
                }
                // Content stays transparent (not collapsed, so layout and card realization proceed) until the spinner fades.
                foreach (var section in Sections()) ElementCompositionPreview.GetElementVisual(section).Opacity = 0;
                // It can already scroll, so a scroll during the spinner's fade rushes the entrance it precedes.
                FadeIn.HoldEntrance(Scroller);
                FadeOutSpinner();
                break;
        }
    }

    /// <summary>The sections that fade up, in reveal order with their delays.</summary>
    /// <returns>Sections.</returns>
    private UIElement[] Sections() => [FullHeader, IntensitySection, HistorySection, LeaderboardsSection, BandBoards];

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
            FadeIn.BeginEntrance(Scroller);
            Enter(FullHeader, SongDetailReveal.Header);
            Enter(IntensitySection, SongDetailReveal.Intensity);
            Enter(HistorySection, SongDetailReveal.History);
            Enter(LeaderboardsSection, SongDetailReveal.Leaderboards);
            for (var i = 0; i < (ViewModel?.Leaderboards.Count ?? 0); i++)
                if (Boards.TryGetElement(i) is UIElement card) Enter(card, SongDetailReveal.Card(i, BoardColumns()));
            // Band previews come last, after the final instrument card's slot.
            Enter(BandBoards, SongDetailReveal.Card(ViewModel?.Leaderboards.Count ?? 0, BoardColumns()));
        });
    }

    /// <summary>
    /// Fades a section or card in with the page entrance (<see cref="FadeIn.Enter"/> on the page scroller): its own delay
    /// while the entrance runs, at once while a scroll rushes it (web <c>useStaggerRush</c>, issue #323), in place after
    /// it (R5).
    /// </summary>
    /// <param name="element">Section or card.</param>
    /// <param name="natural">Its delay in the reveal choreography.</param>
    private void Enter(UIElement element, TimeSpan natural) => FadeIn.Enter(Scroller, element, natural);

    /// <summary>Hides the spinner.</summary>
    private void StopSpinner()
    {
        Spinner.IsActive = false;
        Spinner.Visibility = Visibility.Collapsed;
    }

    /// <summary>Cards per row in the leaderboard grid (two from 2 × 320 + 16 epx).</summary>
    /// <returns>1 or 2.</returns>
    private int BoardColumns() => Boards.ActualWidth >= 2 * 320 + 16 ? 2 : 1;
    #endregion

    /// <summary>Applies the Item Shop button's status fill (gold New, red Leaving Tomorrow, green otherwise).</summary>
    private void ApplyShopPulse() => ShopFill.Apply(ViewModel.ShopHighlight, ViewModel.ShopPulses);

    /// <summary>Pins the compact header once the full header has scrolled out of view.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">Unused.</param>
    private void OnScrollerViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        var pinned = SongDetailLayout.PinsHeader(Scroller.VerticalOffset, FullHeader.ActualHeight);
        var wanted = pinned ? Visibility.Visible : Visibility.Collapsed;
        if (PinnedHeader.Visibility != wanted) PinnedHeader.Visibility = wanted;
    }

    /// <summary>
    /// Keeps a focused element (Tab, Shift+Tab, arrows, Narrator) clear of the pinned header that overlays the scroller:
    /// the target grows upwards by the header's height before the scroller handles the request (issue #195).
    /// </summary>
    /// <param name="sender">Scroller content.</param>
    /// <param name="args">Request; explicit alignments (e.g. a Quick Links jump) are left alone.</param>
    private void OnContentBringIntoViewRequested(UIElement sender, BringIntoViewRequestedEventArgs args)
    {
        if (!double.IsNaN(args.VerticalAlignmentRatio)) return;
        var target = args.TargetRect;
        var (top, height) = SongDetailLayout.RevealBelowPinnedHeader(target.Y, target.Height, PinnedHeader.ActualHeight);
        args.TargetRect = new Windows.Foundation.Rect(target.X, top, target.Width, height);
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
        Enter(args.Element, SongDetailReveal.Card(args.Index, BoardColumns()));
    }

    /// <summary>Opens this song's full band leaderboard for a preview's band size.</summary>
    /// <param name="sender">View Full Leaderboard button.</param>
    /// <param name="e">Unused.</param>
    private void OnBandViewFull(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: SongBandPreviewViewModel band }) MainWindow.Instance?.Navigate(band.FullRoute);
    }

    /// <summary>
    /// "View All Scores": opens the selected chart's sortable Player History page (view-all-cta R8; the card never
    /// expands in place, issue #324).
    /// </summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnHistoryViewAll(object sender, RoutedEventArgs e)
    {
        if (ViewModel.History.ViewAllRoute is { } route) MainWindow.Instance?.Navigate(route);
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
