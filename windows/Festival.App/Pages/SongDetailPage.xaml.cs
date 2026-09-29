using System.ComponentModel;
using Festival.App.Services;
using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song detail page
/// <summary>Song Detail: header, Intensity for every charted instrument and a top-10 card per visible chart.</summary>
public sealed partial class SongDetailPage : Page, IBackdropPage
{
    private readonly QuickLinksViewModel quickLinks = new("Quick Links");
    private CancellationTokenSource headerArt = new();

    /// <summary>Creates the page; its Quick Links menu shows on compact windows only.</summary>
    public SongDetailPage()
    {
        InitializeComponent();
        var host = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, pane: null, menuMaxWidth: 640);
        // Cards far below the viewport are not realized yet (virtualizing grid): realize one on demand for a jump.
        host.Binder.Resolve = id => ViewModel?.Leaderboards.FindIndex(c => c.QuickLinkId == id) is >= 0 and var index
            ? Boards.GetOrCreateElement(index) as FrameworkElement
            : null;
    }

    /// <summary>Page model (set on navigation).</summary>
    public SongDetailViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new SongDetailViewModel(App.Session, (AppRoute.SongDetail)e.Parameter);
        ViewModel.PropertyChanged += OnViewModelChanged;
        Bindings.Update();
        await ViewModel.LoadCommand.ExecuteAsync(null);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        headerArt.Cancel();
        ViewModel?.Detach();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Loads header art and updates the shared backdrop once the song resolves.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SongDetailViewModel.ShopHighlight) or nameof(SongDetailViewModel.ShopPulses)) ApplyShopPulse();
        if (e.PropertyName == nameof(SongDetailViewModel.QuickLinkSections)) quickLinks.SetSections(ViewModel.QuickLinkSections);
        if (e.PropertyName != nameof(SongDetailViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(128 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
        PinnedArt.Source = HeaderArt.Source;
        PerfLog.Mark("song-detail-rendered");
    }

    /// <summary>Applies the Item Shop button's status fill (gold New, red Leaving Tomorrow, green otherwise).</summary>
    private void ApplyShopPulse() => ShopFill.Apply(ViewModel.ShopHighlight, ViewModel.ShopPulses);

    /// <summary>Pins the compact header once the full header has scrolled out of view.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">Unused.</param>
    private void OnScrollerViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        var pinned = Scroller.VerticalOffset > FullHeader.ActualHeight + 12;
        var wanted = pinned ? Visibility.Visible : Visibility.Collapsed;
        if (PinnedHeader.Visibility != wanted) PinnedHeader.Visibility = wanted;
    }

    /// <summary>Intensity: three cells per row (3×3) at compact/medium, all in one row when they fit at wide widths.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="e">New size.</param>
    private void OnIntensitySizeChanged(object sender, SizeChangedEventArgs e)
    {
        var columns = SongDetailLayout.IntensityColumns(e.NewSize.Width, ViewModel?.Intensity.Count ?? 0);
        if (IntensityLayout.MaximumRowsOrColumns != columns) IntensityLayout.MaximumRowsOrColumns = columns;
    }

    /// <summary>Starts a card's top-10 read when it is realized.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnBoardPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (sender.ItemsSourceView?.GetAt(args.Index) is LeaderboardPreviewViewModel card) _ = card.EnsureLoadedAsync();
    }

    /// <summary>Opens a band-size leaderboard for this song.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnBandLink(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: AppRoute route }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Opens the selected player's score history for a chart.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnViewHistory(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: LeaderboardPreviewViewModel card }) MainWindow.Instance?.Navigate(card.HistoryRoute);
    }

    /// <summary>Opens the validated official Item Shop page.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnShopClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.ShopOffer?.ShopUri is { } uri) await Windows.System.Launcher.LaunchUriAsync(uri);
    }

    /// <summary>Opens the CHOpt Paths dialog (reset to Expert and the saved image/text default on every opening).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnPathsClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.CreatePaths() is not { } paths) return;
        await SongPathsView.ShowAsync(XamlRoot, paths, $"Paths · {ViewModel.Song?.Title}");
    }

    /// <summary>Opens the full 25-row leaderboard route.</summary>
    /// <param name="sender">Hyperlink.</param>
    /// <param name="e">Unused.</param>
    private void OnViewFull(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: LeaderboardPreviewViewModel card }) MainWindow.Instance?.Navigate(card.FullRoute);
    }
}
#endregion
