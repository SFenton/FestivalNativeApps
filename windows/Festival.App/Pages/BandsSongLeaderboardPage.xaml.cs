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
    private CancellationTokenSource headerArt = new();
    private int shownPage;
    private bool spotlightShown;

    /// <summary>Creates the page.</summary>
    public BandsSongLeaderboardPage()
    {
        InitializeComponent();
        Controls.BoardFooter.Inset(Footer, Rows);
        SizeChanged += (_, e) => ApplyWidth(e.NewSize.Width);
        Footer.SizeChanged += (_, _) => UpdateFooterPlate();
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
            () => ViewModel.ShowRows ? $"{ViewModel.Title}, {ViewModel.Pager.PageAnnouncement}" : ViewModel.ShowEmpty ? ViewModel.EmptyMessage : null,
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
        headerArt.Cancel();
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        ViewModel.Deactivate();
        ContrastTheme.Changed -= OnContrastChanged;
        base.OnNavigatedFrom(e);
    }

    /// <summary>Compacts the header when the page itself is narrow (the navigation pane can take most of a compact window).</summary>
    /// <param name="width">Page width in epx.</param>
    private void ApplyWidth(double width)
    {
        var narrow = width < 560;
        TitleText.Style = (Style)Application.Current.Resources[narrow ? "SubtitleTextBlockStyle" : "FSTPageTitleStyle"];
        HeaderArtFrame.Width = HeaderArtFrame.Height = narrow ? 48 : 72;
    }

    /// <summary>Applies the band-size choice in place.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnSizeChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        if (ViewModel is null || sender.SelectedItem is null) return;
        ViewModel.BandTypeIndex = sender.Items.IndexOf(sender.SelectedItem);
    }

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
        UpdateFooterPlate();
    });

    /// <summary>
    /// Under a Windows contrast theme, shows the window-colour plate behind the floating footer (pinned band and pager) down
    /// to the page bottom so rows scrolling beneath don't show through (scroll-edge R7, as the other boards); hidden otherwise.
    /// </summary>
    private void UpdateFooterPlate()
    {
        var on = ContrastTheme.IsOn && Footer.ActualHeight > 0;
        FooterPlate.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (on) FooterPlate.Height = Footer.ActualHeight + Footer.Margin.Bottom;
    }

    /// <summary>Opens Song Detail from the header title.</summary>
    /// <param name="sender">Link.</param>
    /// <param name="e">Unused.</param>
    private void OnSongTitle(object sender, RoutedEventArgs e) =>
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(ViewModel.SongId));

    /// <summary>Loads header art and the backdrop once the song resolves; scrolls to top on a new page.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.Rows))
        {
            // After x:Bind has swapped the items: a page change that brings the selected band (e.g. "Your Page") scrolls it
            // into view; anything else starts at the top.
            var pageChanged = ViewModel.Pager.Page != shownPage;
            shownPage = ViewModel.Pager.Page;
            DispatcherQueue.TryEnqueue(() =>
            {
                if (Rows.Items.Count == 0) return;
                var target = pageChanged ? ViewModel.Rows.FirstOrDefault(r => r.IsSelected) : null;
                Rows.ScrollIntoView(target ?? Rows.Items[0], target is null ? ScrollIntoViewAlignment.Default : ScrollIntoViewAlignment.Leading);
            });
            return;
        }
        if (e.PropertyName == nameof(SongBandLeaderboardViewModel.ShowSpotlight))
        {
            var shown = ViewModel.ShowSpotlight;
            if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
                DispatcherQueue.TryEnqueue(() => FadeIn.Play(SpotlightPanel, TimeSpan.Zero));
            spotlightShown = shown;
            return;
        }
        if (e.PropertyName != nameof(SongBandLeaderboardViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        if (App.Session.Settings.SaveData || App.Options.NoArt) return;
        var pixels = (int)Math.Ceiling(72 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned band entering alongside
    /// the first row when it was gated (issue #295); paging keeps it in place (issue #270).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(Rows);
            if (ViewModel.ShowSpotlight && ViewModel.PinnedGate.IsGated) FadeIn.Play(SpotlightPanel, PinnedRowReveal.RevealDelay);
        });
}
#endregion
