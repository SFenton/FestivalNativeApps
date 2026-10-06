using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song band leaderboard page
/// <summary><c>/songs/:songId/bands/:bandType</c>: a song's band scores with an in-place band-size switcher and paging.</summary>
public sealed partial class BandsSongLeaderboardPage : Page, IBackdropPage
{
    /// <summary>Creates the page.</summary>
    public BandsSongLeaderboardPage()
    {
        InitializeComponent();
        Controls.BoardFooter.Inset(Footer, Rows);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Rows, Footer);
    }

    /// <summary>Page model (set on navigation).</summary>
    public SongBandLeaderboardViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new SongBandLeaderboardViewModel(App.Session, (AppRoute.SongBandLeaderboard)e.Parameter);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.LeaderboardName}, {ViewModel.Pager.PageAnnouncement}" : ViewModel.ShowEmpty ? ViewModel.EmptyMessage : null,
            "Loading band leaderboard");
        Bindings.Update();
        SizeBar.SelectedItem = SizeBar.Items[ViewModel.BandTypeIndex];
        await ViewModel.LoadAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        base.OnNavigatedFrom(e);
    }

    /// <summary>Applies the band-size choice in place.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnSizeChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        if (ViewModel is null || sender.SelectedItem is null) return;
        ViewModel.BandTypeIndex = sender.Items.IndexOf(sender.SelectedItem);
    }

    /// <summary>Opens Song Detail from the song header (web <c>onTitleClick={goToSongDetail}</c>).</summary>
    /// <param name="sender">Header.</param>
    /// <param name="e">Unused.</param>
    private void OnSongTitle(object? sender, EventArgs e) =>
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(ViewModel.SongId));

    /// <summary>Opens Band Detail for a row.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is SongBandRow row) MainWindow.Instance?.Navigate(row.Route);
    }

    /// <summary>Names each row container for UI Automation, so a row is one Narrator stop that reads the whole card.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not SongBandRow row) return;
        AutomationProperties.SetName(args.ItemContainer, row.PageAnnouncement);
        AutomationProperties.SetAutomationId(args.ItemContainer, row.AutomationId);
    }

    /// <summary>Shows the resolved song's header art and backdrop; scrolls to the top on a new page.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.Rows))
        {
            // After x:Bind has swapped the items.
            DispatcherQueue.TryEnqueue(() =>
            {
                if (Rows.Items.Count > 0) Rows.ScrollIntoView(Rows.Items[0]);
            });
            return;
        }
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.Song)) ShowSong();
    }

    /// <summary>Points the backdrop and the header art at the resolved song (the solo board's static cover).</summary>
    private void ShowSong()
    {
        if (ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        Header.ArtUrl = song.AlbumArt ?? "";
    }

    /// <summary>Replays the web row entrance after the shared load gate reveals a new page.</summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() => FadeIn.StaggerRealized(Rows));
}
#endregion
