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
    private CancellationTokenSource headerArt = new();
    private int shownPage;
    private bool spotlightShown;

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
            () => new SongLeaderboardViewModel(App.Session, (AppRoute.SongLeaderboard)e.Parameter), out _);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        shownPage = ViewModel.Page;
        spotlightShown = ViewModel.ShowSpotlight;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title} leaderboard, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? $"{ViewModel.Title} leaderboard, no entries" : null,
            "Loading leaderboard");
        Bindings.Update();
        if (ViewModel.Song is not null) _ = ShowSongAsync();
        await ViewModel.ActivateAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        headerArt.Cancel();
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Loads art once the song resolves, scrolls to the top on page changes and fades in a late pinned row.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongLeaderboardViewModel.Song)) _ = ShowSongAsync();
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.ShowSpotlight))
        {
            var shown = ViewModel.ShowSpotlight;
            if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
                DispatcherQueue.TryEnqueue(() => FadeIn.Play(SpotlightPanel, TimeSpan.Zero));
            spotlightShown = shown;
        }
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.Rows) && ViewModel.Page != shownPage)
        {
            shownPage = ViewModel.Page;
            Scroller.ChangeView(null, 0, null, true);
            var selected = ViewModel.Rows.FindIndex(r => r.IsSelected);
            if (selected >= 0)
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    if (RowsRepeater.GetOrCreateElement(selected) is Microsoft.UI.Xaml.UIElement row)
                        row.StartBringIntoView(new Microsoft.UI.Xaml.BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
                });
            }
        }
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned "your score" row
    /// entering alongside the first row (issue #295).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(RowsRepeater);
            if (ViewModel.ShowSpotlight) FadeIn.Play(SpotlightPanel, PinnedRowReveal.RevealDelay);
        });

    /// <summary>Updates the backdrop and header art for the resolved song.</summary>
    /// <returns>Load task.</returns>
    private async Task ShowSongAsync()
    {
        if (ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(80 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
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
