using System.ComponentModel;
using Festival.App.Services;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Band rankings page
/// <summary>Paginated band rankings with band-size and Rank By switchers.</summary>
public sealed partial class LeaderboardsBandRankingsPage : Page
{
    private int shownPage;

    /// <summary>Creates the page.</summary>
    public LeaderboardsBandRankingsPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public BandRankingsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = LeaderboardsPageState<BandRankingsViewModel>.GetOrCreate(e.Parameter,
            () => new BandRankingsViewModel(App.Session, (AppRoute.BandRankings)e.Parameter), out var created);
        ViewModel.PropertyChanged += OnViewModelChanged;
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
        base.OnNavigatedFrom(e);
    }

    /// <summary>Scrolls to the top when a new page of rows arrives.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(BandRankingsViewModel.Rows) || ViewModel.Page == shownPage) return;
        shownPage = ViewModel.Page;
        Scroller.ChangeView(null, 0, null, true);
    }

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
