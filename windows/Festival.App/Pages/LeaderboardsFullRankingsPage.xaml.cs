using System.ComponentModel;
using Festival.App.Services;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Full rankings page
/// <summary>Paginated global rankings with instrument and Rank By switchers and the pinned selected-player row.</summary>
public sealed partial class LeaderboardsFullRankingsPage : Page
{
    private int shownPage;

    /// <summary>Creates the page.</summary>
    public LeaderboardsFullRankingsPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public FullRankingsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = LeaderboardsPageState<FullRankingsViewModel>.GetOrCreate(e.Parameter,
            () => new FullRankingsViewModel(App.Session, (AppRoute.FullRankings)e.Parameter), out var created);
        ViewModel.PropertyChanged += OnViewModelChanged;
        shownPage = ViewModel.Page;
        Bindings.Update();
        if (created) await ViewModel.LoadAsync();
        else ViewModel.RefreshSelection(); // The selection may have changed on a pushed profile.
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
        if (e.PropertyName != nameof(FullRankingsViewModel.Rows) || ViewModel.Page == shownPage) return;
        shownPage = ViewModel.Page;
        Scroller.ChangeView(null, 0, null, true);
    }

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
