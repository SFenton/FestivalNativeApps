using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Full rankings page
/// <summary>Paginated global rankings with instrument and Rank By switchers and the pinned selected-player row.</summary>
public sealed partial class LeaderboardsFullRankingsPage : Page, IRouteHost
{
    /// <summary>Page width from which the rankings and a profile sit side by side.</summary>
    public const double SplitWidth = 1100;

    /// <summary>Rankings column width in the split layout.</summary>
    private const double SplitListWidth = 560;

    private readonly FailedReloadFocus reloadFocus;
    private int shownPage;
    private bool spotlightShown;
    private RankingSpotlightViewModel? watchedSpotlight;
    private int? revealSelected;
    private bool split;
    private string? detailAccountId;

    /// <summary>Creates the page.</summary>
    public LeaderboardsFullRankingsPage()
    {
        InitializeComponent();
        BoardFooter.Inset(Footer, RowsRepeater);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Scroller, Footer, FooterPlate);
        reloadFocus = FailedReloadFocus.Attach(Footer, BoardPager, RowsStatus, () => ViewModel?.LoadSwap.Phase == LoadSwapPhase.ContentIn,
            () => ViewModel?.State == LoadState.Failed);
        SizeChanged += (_, e) => ApplySplit(e.NewSize.Width >= SplitWidth);
    }

    /// <summary>Page model (set on navigation).</summary>
    public FullRankingsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = LeaderboardsPageState<FullRankingsViewModel>.GetOrCreate(e.Parameter,
            () => new FullRankingsViewModel(App.Session, (AppRoute.FullRankings)e.Parameter), out var created);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        shownPage = ViewModel.Page;
        WatchSpotlight();
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title}, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? $"{ViewModel.Title}, no entries" : null,
            "Loading rankings");
        Bindings.Update();
        if (created) await ViewModel.LoadAsync();
        else ViewModel.RefreshSelection(); // The selection may have changed on a pushed profile.
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        if (watchedSpotlight is not null) watchedSpotlight.PropertyChanged -= OnSpotlightChanged;
        watchedSpotlight = null;
        base.OnNavigatedFrom(e);
    }

    #region Pinned row
    /// <summary>Follows the current spotlight (rebuilt when another instrument's board commits) for late arrivals.</summary>
    private void WatchSpotlight()
    {
        if (watchedSpotlight is not null) watchedSpotlight.PropertyChanged -= OnSpotlightChanged;
        watchedSpotlight = ViewModel.Spotlight;
        watchedSpotlight.PropertyChanged += OnSpotlightChanged;
        PinnedRowChanged();
    }

    /// <summary>Re-evaluates the pinned row when its placement changes.</summary>
    /// <param name="sender">Spotlight.</param>
    /// <param name="e">Changed property.</param>
    private void OnSpotlightChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(RankingSpotlightViewModel.IsVisible)) PinnedRowChanged();
    }

    /// <summary>
    /// Fades in a pinned row that appears over an already revealed board (the own rank read finished after the rows),
    /// as the song board does (<see cref="PinnedRowReveal"/>, issue #295); one that commits with a board enters with
    /// the rows from <see cref="OnContentRevealed"/>.
    /// </summary>
    private void PinnedRowChanged()
    {
        var shown = ViewModel.Spotlight.IsVisible;
        if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
            DispatcherQueue.TryEnqueue(() => FadeIn.Play(FooterSpotlight, TimeSpan.Zero));
        spotlightShown = shown;
    }
    #endregion

    /// <summary>
    /// When a new page of rows arrives, brings the selected player's row into view (after the pinned row's jump),
    /// otherwise scrolls to the top.
    /// </summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FullRankingsViewModel.Spotlight)) WatchSpotlight();
        if (e.PropertyName is nameof(FullRankingsViewModel.Rows) or nameof(FullRankingsViewModel.ShowRows)) EnsureSplitSelection();
        if (e.PropertyName != nameof(FullRankingsViewModel.Rows) || ViewModel.Page == shownPage) return;
        shownPage = ViewModel.Page;
        var selected = ViewModel.Rows.FindIndex(r => r.IsSelected);
        revealSelected = selected < 0 ? null : selected;
        // A pending scroll-to-top can land after the centring below and leave the selected row off screen.
        if (revealSelected is null) Scroller.ChangeView(null, 0, null, true);
        // During a load swap the rows are not laid out yet; OnContentRevealed centres them once they are.
        if (ViewModel.ShowRows && ViewModel.LoadSwap.Phase == LoadSwapPhase.ContentIn) RevealSelected();
    }

    /// <summary>
    /// Centres the selected player's row on a newly shown page (pattern <c>leaderboard-row</c> R7). Keyboard focus stays
    /// on the pinned row that jumped, which remains in place, so a second Enter opens the profile. Rows arrive while the
    /// list is still hidden by the load swap, so this runs again once content is revealed.
    /// </summary>
    private void RevealSelected()
    {
        if (revealSelected is not { } index) return;
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!ViewModel.ShowRows || revealSelected != index) return;
            revealSelected = null;
            if (RowsRepeater.GetOrCreateElement(index) is not LeaderboardEntryRow row) return;
            // A freshly realized row has no arranged position yet; bringing it into view before layout is a no-op.
            row.UpdateLayout();
            row.StartBringIntoView(new Microsoft.UI.Xaml.BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
        });
    }

    /// <summary>
    /// Keeps a focused row (Tab, arrows, Narrator) clear of the floating footer that overlays the bottom of the rows: the
    /// target grows downwards by the rows' footer inset before the scroller handles the request (WCAG 2.4.11).
    /// </summary>
    /// <param name="sender">Rows.</param>
    /// <param name="args">Request; explicit alignments (the centred jump) are left alone.</param>
    private void OnRowsBringIntoViewRequested(UIElement sender, BringIntoViewRequestedEventArgs args)
    {
        if (!double.IsNaN(args.VerticalAlignmentRatio)) return;
        var target = args.TargetRect;
        args.TargetRect = new Windows.Foundation.Rect(target.X, target.Y, target.Width,
            LeaderboardPaging.RevealAboveFooter(target.Height, RowsRepeater.Margin.Bottom));
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned "your rank" row
    /// entering alongside the first row when it was gated (issue #270, as the song board's #295); paging keeps it in place.
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            reloadFocus.Settle();
            FadeIn.StaggerRealized(RowsRepeater);
            if (ViewModel.Spotlight.IsVisible && ViewModel.PinnedGate.IsGated) FadeIn.Play(FooterSpotlight, PinnedRowReveal.RevealDelay);
        });
        RevealSelected();
    }

    #region Split layout
    /// <summary>
    /// List + profile columns (never an empty detail): the page drops its 1100 epx cap, the rankings keep a fixed column
    /// and the profile fills the rest. Below the width, or without rows, it is the single centred column again.
    /// </summary>
    /// <param name="wanted">Whether the page is wide enough.</param>
    private void ApplySplit(bool wanted)
    {
        var on = wanted && ViewModel is { ShowRows: true } && ViewModel.Rows.Any(r => r.Route is not null);
        if (on == split) return;
        split = on;
        PageRoot.MaxWidth = on ? double.PositiveInfinity : 1100;
        ListColumn.Width = on ? new GridLength(SplitListWidth) : new GridLength(1, GridUnitType.Star);
        DetailColumn.Width = on ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        DetailFrame.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (on)
        {
            EnsureSplitSelection();
            return;
        }
        detailAccountId = null;
        DetailFrame.Content = null;
        MarkCurrentRows();
    }

    /// <summary>Keeps a profile showing: the current player if still on this page, else the selected player's row, else the first.</summary>
    private void EnsureSplitSelection()
    {
        if (!split)
        {
            ApplySplit(ActualWidth >= SplitWidth);
            return;
        }
        var rows = ViewModel.Rows.Where(r => r.Route is not null).ToList();
        if (!ViewModel.ShowRows || rows.Count == 0)
        {
            ApplySplit(false);
            return;
        }
        var target = rows.FirstOrDefault(r => r.Entry.AccountId == detailAccountId) ?? rows.FirstOrDefault(r => r.IsSelected) ?? rows[0];
        Show((AppRoute.Player)target.Route!);
    }

    /// <inheritdoc />
    public bool TryShow(AppRoute route)
    {
        if (!split || route is not AppRoute.Player player) return false;
        Show(player);
        return true;
    }

    /// <summary>Opens a profile in the detail column (once per player) and marks its row.</summary>
    /// <param name="route">Player route.</param>
    private void Show(AppRoute.Player route)
    {
        if (route.AccountId == detailAccountId && DetailFrame.Content is not null) return;
        detailAccountId = route.AccountId;
        DetailFrame.Navigate(typeof(PlayerProfilePage), route, new SuppressNavigationTransitionInfo());
        MarkCurrentRows();
    }

    /// <summary>Marks a realized row whose player shows in the detail column.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row.</param>
    private void OnRowPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is LeaderboardEntryRow row) row.IsCurrent = split && IsCurrent(row);
    }

    /// <summary>Re-marks every realized row.</summary>
    private void MarkCurrentRows()
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(RowsRepeater); i++)
            if (VisualTreeHelper.GetChild(RowsRepeater, i) is LeaderboardEntryRow row) row.IsCurrent = split && IsCurrent(row);
    }

    /// <summary>Whether a row's player is the one in the detail column.</summary>
    /// <param name="row">Row.</param>
    /// <returns><see langword="true"/> for the shown player.</returns>
    private bool IsCurrent(LeaderboardEntryRow row) => row.Route is AppRoute.Player p && p.AccountId == detailAccountId;
    #endregion

    /// <summary>Builds instrument radio items (Settings-visible charts plus the current one).</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnInstrumentMenuOpening(object sender, object e)
    {
        InstrumentMenu.Items.Clear();
        foreach (var instrument in ViewModel.InstrumentOptions)
        {
            var item = new RadioMenuFlyoutItem
            {
                Text = instrument.Label(),
                GroupName = "instrument",
                IsChecked = instrument == ViewModel.Instrument,
                Command = ViewModel.SelectInstrumentCommand,
                CommandParameter = instrument,
                Icon = new ImageIcon { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri($"ms-appx:///Assets/Instruments/{instrument.IconFile()}")) { DecodePixelWidth = 32 } },
            };
            AutomationProperties.SetAutomationId(item, "fst.full-rankings.instrument." + instrument.ServiceId());
            InstrumentMenu.Items.Add(item);
        }
    }

    /// <summary>Builds Rank By radio items.</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnMetricMenuOpening(object sender, object e)
    {
        MetricMenu.Items.Clear();
        foreach (var metric in ViewModel.MetricOptions)
        {
            var item = new RadioMenuFlyoutItem
            {
                Text = metric.Label(),
                GroupName = "rankBy",
                IsChecked = metric == ViewModel.Metric,
                Command = ViewModel.SelectMetricCommand,
                CommandParameter = metric,
            };
            AutomationProperties.SetAutomationId(item, "fst.rankings.rank-by." + metric.ServiceId());
            MetricMenu.Items.Add(item);
        }
    }

    /// <summary>F5 reloads the current page.</summary>
    /// <param name="sender">Accelerator.</param>
    /// <param name="args">Handled here.</param>
    private void OnRefreshInvoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        _ = ViewModel.LoadAsync();
    }
}
#endregion
