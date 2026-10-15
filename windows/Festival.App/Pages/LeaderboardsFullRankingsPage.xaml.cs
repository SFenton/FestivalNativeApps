using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Full rankings page
/// <summary>Paginated global rankings with instrument and Rank By switchers and the pinned selected-player row.</summary>
public sealed partial class LeaderboardsFullRankingsPage : Page
{
    private readonly FailedReloadFocus reloadFocus;
    private int shownPage;
    private bool spotlightShown;
    private RankingSpotlightViewModel? watchedSpotlight;
    private int? revealSelected;

    /// <summary>Creates the page.</summary>
    public LeaderboardsFullRankingsPage()
    {
        InitializeComponent();
        LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, footer: Footer);
        BoardFooter.Inset(Footer, RowsRepeater);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Scroller, Footer, FooterPlate);
        reloadFocus = FailedReloadFocus.Attach(Footer, BoardPager, RowsStatus, () => ViewModel?.LoadSwap.Phase == LoadSwapPhase.ContentIn,
            () => ViewModel?.State == LoadState.Failed);
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
        // An arrival from a Leaderboards card's "your rank" row (navToPlayer, issue #370) brings the highlighted row into
        // view on first load, as the song board does for Song Detail's spotlight row.
        shownPage = created && ((AppRoute.FullRankings)e.Parameter).RevealSelected ? 0 : ViewModel.Page;
        WatchSpotlight();
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title}, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? $"{ViewModel.Title}, no entries" : null,
            "Loading rankings");
        Bindings.Update();
        if (created) await ViewModel.LoadAsync();
        else if (ViewModel.SyncExperimentalRanks() is { } reload) await reload; // Settings' Experimental Ranks changed.
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
            DispatcherQueue.TryEnqueue(() => FadeIn.Play(FooterSpotlight));
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
        if (e.PropertyName != nameof(FullRankingsViewModel.Rows) || ViewModel.Page == shownPage) return;
        shownPage = ViewModel.Page;
        var selected = ViewModel.Rows.FindIndex(r => r.IsSelected);
        revealSelected = selected < 0 ? null : selected;
        // A pending scroll-to-top can land after the centring below and leave the selected row off screen.
        if (revealSelected is null) Scroller.ChangeView(null, 0, null, true);
        // During a load swap the rows are not laid out yet; OnContentRevealed reveals them after the entrance.
        if (ViewModel.ShowRows && ViewModel.LoadSwap.Phase == LoadSwapPhase.ContentIn) DispatcherQueue.TryEnqueue(RevealSelected);
    }

    /// <summary>
    /// Centres the selected player's row on a newly shown page (pattern <c>leaderboard-row</c> R7) once its own entrance
    /// has finished, rushing the rest (<see cref="SelectedRowReveal"/>, issues #307 and #323). Keyboard focus stays on the
    /// pinned row that jumped, which remains in place, so a second Enter opens the profile.
    /// </summary>
    private void RevealSelected()
    {
        if (revealSelected is not { } index || !ViewModel.ShowRows) return;
        revealSelected = null;
        var rows = ViewModel.Rows;
        SelectedRowReveal.Start(RowsRepeater, index, () =>
        {
            if (ReferenceEquals(ViewModel.Rows, rows)) SelectedRowReveal.CentreRow(RowsRepeater, index);
        });
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned "your rank" row
    /// entering alongside the first row when it was gated (issue #270, as the song board's #295); paging keeps it in
    /// place. A pending selected row is revealed after the entrance starts (<see cref="RevealSelected"/>).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            reloadFocus.Settle();
            FadeIn.StaggerRealized(RowsRepeater);
            if (ViewModel.Spotlight.IsVisible && ViewModel.PinnedGate.IsGated) FadeIn.Enter(RowsRepeater, FooterSpotlight, PinnedRowReveal.RevealDelay);
            RevealSelected();
        });

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
