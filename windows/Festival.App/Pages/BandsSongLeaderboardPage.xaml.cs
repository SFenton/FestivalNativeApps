using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song band leaderboard page
/// <summary>
/// <c>/songs/:songId/bands/:bandType</c>: a song's band scores with an in-place band-size switcher and paging, and the
/// selected player's band highlighted in place and pinned above the pager (issue #306).
/// </summary>
public sealed partial class BandsSongLeaderboardPage : Page, IBackdropPage
{
    private int shownPage;
    private bool spotlightShown;
    private int pendingReveal = -1;

    /// <summary>Creates the page.</summary>
    public BandsSongLeaderboardPage()
    {
        InitializeComponent();
        Controls.BoardFooter.Inset(Footer, Rows);
        BoardFooterFade.Attach(BoardFadeSource, BoardFadeHost, Rows, Footer, FooterPlate);
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
        shownPage = ViewModel.Pager.Page;
        spotlightShown = ViewModel.ShowSpotlight;
        ViewModel.Activate();
        ContrastTheme.Changed += OnContrastChanged;
        await ViewModel.LoadAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        ViewModel.Deactivate();
        ContrastTheme.Changed -= OnContrastChanged;
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

    /// <summary>
    /// Names each row container for UI Automation, so a row is one Narrator stop that reads the whole card, and gives the
    /// selected player's band the player-row text (names, scores and chevron inherit it; HighlightText under a contrast theme).
    /// </summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not SongBandRow row) return;
        AutomationProperties.SetName(args.ItemContainer, row.PageAnnouncement);
        AutomationProperties.SetAutomationId(args.ItemContainer, row.AutomationId);
        if (row.IsSelected) args.ItemContainer.Foreground = ContrastTheme.Brush("FSTPlayerRowTextBrush");
        else args.ItemContainer.ClearValue(Control.ForegroundProperty);
    }

    /// <summary>Card fill: the purple player row for the selected player's band (web <c>isSelected</c>), else the card surface.</summary>
    /// <param name="selected">Whether the row is the selected player's band.</param>
    /// <returns>Brush for the current theme.</returns>
    public static Brush Surface(bool selected) => ContrastTheme.Brush(selected ? "FSTPlayerRowBrush" : "FSTCardSurfaceBrush");

    /// <summary>Card outline for <see cref="Surface"/>.</summary>
    /// <param name="selected">Whether the row is the selected player's band.</param>
    /// <returns>Brush for the current theme.</returns>
    public static Brush Stroke(bool selected) => ContrastTheme.Brush(selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush");

    /// <summary>Secondary text (rank, member scores), following the player-row fill on the selected band.</summary>
    /// <param name="selected">Whether the text sits on the selected player's band.</param>
    /// <returns>Brush for the current theme.</returns>
    public static Brush Secondary(bool selected) => ContrastTheme.Brush(selected ? "FSTPlayerRowTextBrush" : "FSTSecondaryTextBrush");

    /// <summary>Re-templates the rows so their looked-up brushes follow a contrast theme switch.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnContrastChanged(object? sender, EventArgs e) => DispatcherQueue.TryEnqueue(() =>
    {
        var items = Rows.ItemsSource;
        Rows.ItemsSource = null;
        Rows.ItemsSource = items;
    });

    /// <summary>Shows the resolved song's header art and backdrop; scrolls to the top on a new page.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.Rows))
        {
            // After x:Bind has swapped the items: every new page starts at the top; one that brings the selected band
            // (e.g. "Your Page") centres it once its entrance has finished (OnContentRevealed, issue #323).
            var pageChanged = ViewModel.Pager.Page != shownPage;
            shownPage = ViewModel.Pager.Page;
            pendingReveal = pageChanged ? ViewModel.Rows.Select((r, i) => r.IsSelected ? i : -1).FirstOrDefault(i => i >= 0, -1) : -1;
            DispatcherQueue.TryEnqueue(() =>
            {
                if (Rows.Items.Count > 0) Rows.ScrollIntoView(Rows.Items[0]);
            });
            return;
        }
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.ShowSpotlight))
        {
            var shown = ViewModel.ShowSpotlight;
            if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
                DispatcherQueue.TryEnqueue(() => FadeIn.Play(SpotlightPanel));
            spotlightShown = shown;
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

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned band entering alongside
    /// the first row when it was gated (issue #295); paging keeps it in place (issue #270). A queued selected band is
    /// centred once its own entrance has finished (<see cref="SelectedRowReveal"/>, web <c>navToBand</c>, issue #323).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(Rows);
            if (ViewModel.ShowSpotlight && ViewModel.PinnedGate.IsGated) FadeIn.Enter(Rows, SpotlightPanel, PinnedRowReveal.RevealDelay);
            var index = pendingReveal;
            pendingReveal = -1;
            if (index < 0 || index >= Rows.Items.Count) return;
            SelectedRowReveal.Start(Rows, index, animate =>
            {
                if (index >= Rows.Items.Count) return;
                if (Rows.ContainerFromIndex(index) is UIElement row)
                    row.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = animate });
                else
                    Rows.ScrollIntoView(Rows.Items[index], ScrollIntoViewAlignment.Leading);
            });
        });
}
#endregion
