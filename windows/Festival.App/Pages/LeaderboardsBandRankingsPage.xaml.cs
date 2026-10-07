using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Band rankings page
/// <summary>
/// Paginated band rankings with band-size and Rank By switchers; at wide widths the chosen band's detail fills a second
/// column (like Full Rankings).
/// </summary>
public sealed partial class LeaderboardsBandRankingsPage : Page, IRouteHost
{
    /// <summary>Page width from which the rankings and a band's detail sit side by side.</summary>
    public const double SplitWidth = LeaderboardsFullRankingsPage.SplitWidth;

    /// <summary>Rankings column width in the split layout.</summary>
    private const double SplitListWidth = 560;

    private int shownPage;
    private bool split;
    private AppRoute.Band? detailRoute;

    /// <summary>Creates the page.</summary>
    public LeaderboardsBandRankingsPage()
    {
        InitializeComponent();
        BoardFooter.Inset(Footer, RowsRepeater);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Scroller, Footer, FooterPlate);
        SizeChanged += (_, e) => ApplySplit(e.NewSize.Width >= SplitWidth);
    }

    /// <summary>Page model (set on navigation).</summary>
    public BandRankingsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = LeaderboardsPageState<BandRankingsViewModel>.GetOrCreate(e.Parameter,
            () => new BandRankingsViewModel(App.Session, (AppRoute.BandRankings)e.Parameter), out var created);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        shownPage = ViewModel.Page;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title}, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? ViewModel.EmptyText : null,
            "Loading band rankings");
        Bindings.Update();
        if (created) await ViewModel.LoadAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        base.OnNavigatedFrom(e);
    }

    /// <summary>Scrolls to the top when a new page of rows arrives.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(BandRankingsViewModel.Rows) or nameof(BandRankingsViewModel.ShowRows)) EnsureSplitSelection();
        if (e.PropertyName != nameof(BandRankingsViewModel.Rows) || ViewModel.Page == shownPage) return;
        shownPage = ViewModel.Page;
        Scroller.ChangeView(null, 0, null, true);
    }

    /// <summary>Replays the web row entrance after the shared load gate reveals a new page.</summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() => FadeIn.StaggerRealized(RowsRepeater));

    #region Split layout
    /// <summary>
    /// List + Band Detail columns (never an empty detail): the page drops its 1100 epx cap, the rankings keep a fixed
    /// column and the band fills the rest. Below the width, or without openable rows, it is one centred column again.
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
        detailRoute = null;
        DetailFrame.Content = null;
        MarkCurrentRows();
    }

    /// <summary>Keeps a band showing: the current one if still on this page, else the first openable row.</summary>
    private void EnsureSplitSelection()
    {
        if (!split)
        {
            ApplySplit(ActualWidth >= SplitWidth);
            return;
        }
        var routes = ViewModel.Rows.Select(r => r.Route).OfType<AppRoute.Band>().ToList();
        if (!ViewModel.ShowRows || routes.Count == 0)
        {
            ApplySplit(false);
            return;
        }
        Show(routes.FirstOrDefault(r => r == detailRoute) ?? routes[0]);
    }

    /// <inheritdoc />
    public bool TryShow(AppRoute route)
    {
        if (!split || route is not AppRoute.Band band) return false;
        Show(band);
        return true;
    }

    /// <summary>Opens a band in the detail column (once per band) and marks its row.</summary>
    /// <param name="route">Band route.</param>
    private void Show(AppRoute.Band route)
    {
        if (route == detailRoute && DetailFrame.Content is not null) return;
        detailRoute = route;
        DetailFrame.Navigate(typeof(BandsDetailPage), route, new SuppressNavigationTransitionInfo());
        MarkCurrentRows();
    }

    /// <summary>Marks a realized row whose band shows in the detail column.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row.</param>
    private void OnRowPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is LeaderboardEntryRow row) row.IsCurrent = split && row.Route == detailRoute;
    }

    /// <summary>Re-marks every realized row.</summary>
    private void MarkCurrentRows()
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(RowsRepeater); i++)
            if (VisualTreeHelper.GetChild(RowsRepeater, i) is LeaderboardEntryRow row) row.IsCurrent = split && row.Route == detailRoute;
    }
    #endregion

    /// <summary>Builds band-size radio items.</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnBandTypeMenuOpening(object sender, object e)
    {
        BandTypeMenu.Items.Clear();
        foreach (var bandType in ViewModel.BandTypeOptions)
        {
            var item = new RadioMenuFlyoutItem
            {
                Text = bandType.Label(),
                GroupName = "bandType",
                IsChecked = bandType == ViewModel.BandType,
                Command = ViewModel.SelectBandTypeCommand,
                CommandParameter = bandType,
            };
            AutomationProperties.SetAutomationId(item, "fst.band-rankings.band-type." + bandType.ServiceId());
            BandTypeMenu.Items.Add(item);
        }
    }

    /// <summary>Builds band Rank By radio items (no Max Score).</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnMetricMenuOpening(object sender, object e)
    {
        MetricMenu.Items.Clear();
        foreach (var metric in ViewModel.MetricOptions)
        {
            var item = new RadioMenuFlyoutItem
            {
                Text = metric.ToRankingMetric().Label(),
                GroupName = "rankBy",
                IsChecked = metric == ViewModel.Metric,
                Command = ViewModel.SelectMetricCommand,
                CommandParameter = metric,
            };
            AutomationProperties.SetAutomationId(item, "fst.band-rankings.rank-by." + metric.ServiceId());
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
