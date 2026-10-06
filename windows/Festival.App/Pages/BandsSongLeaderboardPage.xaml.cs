using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song band leaderboard page
/// <summary><c>/songs/:songId/bands/:bandType</c>: a song's band scores with an in-place band-size switcher and paging.</summary>
public sealed partial class BandsSongLeaderboardPage : Page, IBackdropPage
{
    private CancellationTokenSource headerArt = new();
    private SongBandRow? pendingReveal;

    /// <summary>Creates the page.</summary>
    public BandsSongLeaderboardPage()
    {
        InitializeComponent();
        Controls.BoardFooter.Inset(Footer, Rows);
        SizeChanged += (_, e) => ApplyWidth(e.NewSize.Width);
        // The selected-band surface is set from code, so a contrast-theme switch must re-resolve it (issue #242).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
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
        await ViewModel.LoadAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        headerArt.Cancel();
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
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
    /// Names each row container for UI Automation, so a row is one Narrator stop that reads the whole card, and paints the
    /// selected player's band in the player-row surface (web <c>isPlayer</c>, as the Song Detail preview row).
    /// </summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not SongBandRow row) return;
        AutomationProperties.SetName(args.ItemContainer, row.PageAnnouncement);
        AutomationProperties.SetAutomationId(args.ItemContainer, row.AutomationId);
        ApplySurface(args.ItemContainer, row.IsSelected);
    }

    /// <summary>
    /// Paints a row card: the purple player-row fill, stroke and text for the selected band, else the plain card. Always
    /// set, because containers are recycled between rows.
    /// </summary>
    /// <param name="container">Row container.</param>
    /// <param name="selected">Whether the row is the selected player's band.</param>
    private static void ApplySurface(SelectorItem container, bool selected)
    {
        if (container.ContentTemplateRoot is not Grid card) return;
        card.Background = ContrastTheme.Brush(selected ? "FSTPlayerRowBrush" : "FSTCardSurfaceBrush");
        card.BorderBrush = ContrastTheme.Brush(selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush");
        var rank = card.Children.OfType<TextBlock>().FirstOrDefault();
        if (selected)
        {
            var text = ContrastTheme.Brush("FSTPlayerRowTextBrush");
            container.Foreground = text;
            if (rank is not null)
            {
                rank.Foreground = text;
                rank.FontWeight = Microsoft.UI.Text.FontWeights.Bold;
            }
        }
        else
        {
            container.ClearValue(Control.ForegroundProperty);
            if (rank is not null)
            {
                rank.Foreground = ContrastTheme.Brush("FSTSecondaryTextBrush");
                rank.ClearValue(TextBlock.FontWeightProperty);
            }
        }
    }

    /// <summary>Re-applies the row surfaces after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(() =>
    {
        foreach (var item in Rows.Items)
            if (item is SongBandRow row && Rows.ContainerFromItem(item) is SelectorItem container) ApplySurface(container, row.IsSelected);
    });

    /// <summary>Opens Song Detail from the header title.</summary>
    /// <param name="sender">Link.</param>
    /// <param name="e">Unused.</param>
    private void OnSongTitle(object sender, RoutedEventArgs e) =>
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(ViewModel.SongId));

    /// <summary>
    /// Loads header art and the backdrop once the song resolves. On a new page, scrolls to the top, or after a jump or a
    /// reveal route brings the selected band's highlighted row into view (instantly, as the solo board).
    /// </summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
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
        if (e.PropertyName != nameof(SongBandLeaderboardViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        if (App.Session.Settings.SaveData || App.Options.NoArt) return;
        var pixels = (int)Math.Ceiling(72 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
    }

    /// <summary>
    /// After the shared load gate reveals a new page, brings a pending selected row into view (centred, without animation)
    /// and replays the web row entrance, with the pinned row entering alongside the first row (issue #295).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (pendingReveal is { } reveal)
            {
                pendingReveal = null;
                Rows.ScrollIntoView(reveal);
                Rows.UpdateLayout();
                if (Rows.ContainerFromItem(reveal) is UIElement container)
                    container.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
            }
            FadeIn.StaggerRealized(Rows);
            if (ViewModel.ShowSpotlight && ViewModel.PinnedGate.IsGated) FadeIn.Play(SpotlightRow, PinnedRowReveal.RevealDelay);
        });
}
#endregion
