using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Leaderboards page
/// <summary>Leaderboards section root: instrument and band top-ten cards in an adaptive grid with a Rank By menu.</summary>
public sealed partial class LeaderboardsPage : Page
{
    /// <summary>Creates the page and its (cached) model.</summary>
    public LeaderboardsPage()
    {
        ViewModel = new LeaderboardsViewModel(App.Session);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        InitializeComponent();
        _ = new QuickLinksHost(Root, Scroller, ViewModel.QuickLinks, QuickLinksMenu, Pane);
        ViewModel.PropertyChanged += (_, e) =>
        {
            // Cards realize when they turn visible: re-arm both repeaters so they stagger in then.
            if (e.PropertyName != nameof(LeaderboardsViewModel.IsReady) || !ViewModel.IsReady) return;
            FadeIn.Restagger(InstrumentRepeater);
            FadeIn.Restagger(BandRepeater);
        };
    }

    /// <summary>Negation helper for x:Bind.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Negated value.</returns>
    public static bool Not(bool value) => !value;

    /// <summary>Visible while <paramref name="ready"/> is false.</summary>
    /// <param name="ready">Readiness.</param>
    /// <returns>Visibility.</returns>
    public static Visibility Collapsed(bool ready) => ready ? Visibility.Collapsed : Visibility.Visible;

    /// <summary>Visible only while <paramref name="text"/> has content, so an idle countdown leaves no blank line
    /// (or empty UIA text element) in a failed card.</summary>
    /// <param name="text">Countdown text.</param>
    /// <returns>Visibility.</returns>
    public static Visibility VisibleWhenText(string? text) => string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;

    /// <summary>Page model.</summary>
    public LeaderboardsViewModel ViewModel { get; }

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.ActivateAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Builds the Rank By radio items for the current metric.</summary>
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

    /// <summary>Opens Full Rankings or Band Rankings for a card.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnViewAll(object sender, RoutedEventArgs e)
    {
        var route = (sender as FrameworkElement)?.Tag switch
        {
            RankingCardViewModel card => card.ViewAllRoute,
            BandRankingCardViewModel band => band.ViewAllRoute,
            _ => null,
        };
        if (route is not null) MainWindow.Instance?.Navigate(route);
    }


    /// <summary>F5 reloads every card.</summary>
    /// <param name="sender">Accelerator.</param>
    /// <param name="args">Handled here.</param>
    private void OnRefreshInvoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        _ = ViewModel.LoadAsync();
    }

    /// <summary>Replays the web card entrance after the shared load gate reveals refreshed cards.</summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(InstrumentRepeater);
            FadeIn.StaggerRealized(BandRepeater);
        });
}
#endregion
