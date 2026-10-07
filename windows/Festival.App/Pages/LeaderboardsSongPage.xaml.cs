using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song leaderboard page
/// <summary>Solo song leaderboard (<c>/songs/:songId/:instrument</c>) over the song's static cover.</summary>
public sealed partial class LeaderboardsSongPage : Page, IBackdropPage
{
    private int shownPage;
    private bool spotlightShown;
    private bool navToPlayer;
    private int pendingReveal = -1;

    /// <summary>Creates the page.</summary>
    public LeaderboardsSongPage()
    {
        InitializeComponent();
        BoardFooter.Inset(Footer, ScrollContent);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Scroller, Footer, FooterPlate);
    }

    /// <summary>Page model (set on navigation).</summary>
    public SongLeaderboardViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = LeaderboardsPageState<SongLeaderboardViewModel>.GetOrCreate(e.Parameter,
            () => new SongLeaderboardViewModel(App.Session, (AppRoute.SongLeaderboard)e.Parameter), out var created);
        // Web navToPlayer: only a fresh visit from Song Details' player score scrolls to the row (Back restores the page).
        navToPlayer = created && e.Parameter is AppRoute.SongLeaderboard { NavToPlayer: true };
        pendingReveal = -1;
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        shownPage = ViewModel.Page;
        spotlightShown = ViewModel.ShowSpotlight;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title} leaderboard, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? $"{ViewModel.Title} leaderboard, no entries" : null,
            "Loading leaderboard");
        Bindings.Update();
        if (ViewModel.Song is not null) ShowSong();
        await ViewModel.ActivateAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>
    /// Loads art once the song resolves, scrolls to the top on page changes (queuing the selected row's reveal when the
    /// new page, or a navToPlayer visit's first rows, holds it) and fades in a late pinned row.
    /// </summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongLeaderboardViewModel.Song)) ShowSong();
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.ShowSpotlight))
        {
            var shown = ViewModel.ShowSpotlight;
            if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
                DispatcherQueue.TryEnqueue(() => FadeIn.Play(SpotlightPanel));
            spotlightShown = shown;
        }
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.Rows))
        {
            var paged = ViewModel.Page != shownPage;
            if (paged)
            {
                shownPage = ViewModel.Page;
                Scroller.ChangeView(null, 0, null, true);
            }
            var selected = ViewModel.Rows.FindIndex(r => r.IsSelected);
            pendingReveal = paged || navToPlayer ? selected : -1;
            if (paged || selected >= 0) navToPlayer = false;
        }
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned "your score" row
    /// entering alongside the first row when it was gated (issue #295); paging keeps it in place (issue #270). A queued
    /// selected row is centred once its own entrance has finished (<see cref="SelectedRowReveal"/>, issue #323).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(RowsRepeater);
            if (ViewModel.ShowSpotlight && ViewModel.PinnedGate.IsGated) FadeIn.Enter(RowsRepeater, SpotlightPanel, PinnedRowReveal.RevealDelay);
            var index = pendingReveal;
            pendingReveal = -1;
            if (index < 0 || index >= ViewModel.Rows.Count) return;
            SelectedRowReveal.Start(RowsRepeater, index, animate =>
            {
                if (index < ViewModel.Rows.Count && RowsRepeater.GetOrCreateElement(index) is UIElement row)
                    row.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = animate });
            });
        });

    /// <summary>Opens Song Detail from the song header (web <c>onTitleClick={goToSongDetail}</c>).</summary>
    /// <param name="sender">Header.</param>
    /// <param name="e">Unused.</param>
    private void OnSongTitle(object? sender, EventArgs e) =>
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(ViewModel.SongId));

    /// <summary>Updates the backdrop and header art for the resolved song.</summary>
    private void ShowSong()
    {
        if (ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        Header.ArtUrl = song.AlbumArt ?? "";
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
