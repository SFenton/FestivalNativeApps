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
    private SongBandRow? pendingReveal;
    private bool spotlightShown;

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
        // The row's slice of the board's one grouped card (issue #543); the container's hover and press fill and its
        // focus ring follow the slice's corners and stay inside the row, which touches its neighbours.
        var index = args.ItemIndex;
        var items = sender.Items;
        var slice = GroupedRows.SliceFor(index, items.Count, row, index > 0 && index - 1 < items.Count ? items[index - 1] : null);
        if (args.ItemContainer.ContentTemplateRoot is UIElement root) GroupedRows.Apply(root, slice);
        args.ItemContainer.CornerRadius = GroupedRows.Radius(slice);
        args.ItemContainer.FocusVisualMargin = new Thickness(0);
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

    /// <summary>
    /// Shows the resolved song's header art and backdrop. On a new page, scrolls to the top, or after a jump or a reveal
    /// route brings the selected band's highlighted row into view (instantly, as the solo board).
    /// </summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.Rows))
        {
            // The reveal waits for the load gate to show the list (OnContentRevealed); the flag is spent either way.
            pendingReveal = ViewModel.RevealSelected ? ViewModel.Rows.FirstOrDefault(r => r.IsSelected) : null;
            ViewModel.RevealSelected = false;
            // After x:Bind has swapped the items.
            if (pendingReveal is null)
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
    /// After the shared load gate reveals a new page, replays the web row entrance, with the pinned row entering alongside
    /// the first row when it was gated (issue #295); paging keeps it in place (issue #270). A pending selected band is then
    /// centred once its own entrance has finished, rushing the rest (<see cref="SelectedRowReveal"/>, web <c>navToBand</c>,
    /// issues #307 and #323).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(Rows);
            if (ViewModel.ShowSpotlight && ViewModel.PinnedGate.IsGated) FadeIn.Enter(Rows, SpotlightPanel, PinnedRowReveal.RevealDelay);
            if (pendingReveal is { } reveal)
            {
                pendingReveal = null;
                SelectedRowReveal.Start(Rows, ViewModel.Rows.IndexOf(reveal), () => RevealRow(reveal));
            }
        });

    /// <summary>Frames <see cref="RevealRow"/> spends bringing the selected row into view before giving up (about a second).</summary>
    private const int RevealFrames = 60;

    /// <summary>
    /// Scrolls the selected band's row into view and centres it (without animation). A freshly swapped ListView defers
    /// <c>ScrollIntoView</c>, and scroll requests made in the same tick or inside <c>LayoutUpdated</c> do not commit (the
    /// list stays at the top), so this works once per rendered frame, outside layout: it asks the list to realize the row,
    /// then brings its container into view, and stops once the row lies inside the list's viewport, a newer page replaces
    /// the rows, the page unloads or the frames run out.
    /// </summary>
    /// <param name="row">Selected row.</param>
    private void RevealRow(SongBandRow row)
    {
        var items = ViewModel.Rows;
        var frames = 0;
        var asked = false;
        void OnFrame(object? sender, object e)
        {
            if (++frames > RevealFrames || !IsLoaded || !ReferenceEquals(ViewModel.Rows, items))
            {
                CompositionTarget.Rendering -= OnFrame;
                return;
            }
            if (Rows.ContainerFromItem(row) is not FrameworkElement container)
            {
                Rows.ScrollIntoView(row);
                return;
            }
            if (asked && IsInViewport(container))
            {
                CompositionTarget.Rendering -= OnFrame;
                return;
            }
            asked = true;
            container.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
        }
        CompositionTarget.Rendering += OnFrame;
    }

    /// <summary>
    /// Whether a row container lies wholly inside the list's clear area: its visible bounds above the floating footer,
    /// whose height the list carries as its bottom padding (<see cref="Controls.BoardFooter.Inset"/>; issue #461).
    /// </summary>
    /// <param name="container">Row container.</param>
    /// <returns><see langword="true"/> when the row is fully visible and clear of the footer.</returns>
    private bool IsInViewport(FrameworkElement container)
    {
        var top = container.TransformToVisual(Rows).TransformPoint(default).Y;
        return top >= 0 && top + container.ActualHeight <= Rows.ActualHeight - Rows.Padding.Bottom;
    }
}
#endregion
