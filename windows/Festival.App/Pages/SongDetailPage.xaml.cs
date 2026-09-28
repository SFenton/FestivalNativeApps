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
    private CancellationTokenSource headerArt = new();

    /// <summary>Creates the page.</summary>
    public SongDetailPage() => InitializeComponent();

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
        base.OnNavigatedFrom(e);
    }

    /// <summary>Loads header art and updates the shared backdrop once the song resolves.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongDetailViewModel.ShopHighlight)) ApplyShopBadge();
        if (e.PropertyName != nameof(SongDetailViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(128 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
        PerfLog.Mark("song-detail-rendered");
    }

    /// <summary>Colors the Shop badge: white on red for Leaving Tomorrow, gold on dark for New.</summary>
    private void ApplyShopBadge()
    {
        var leaving = ViewModel.ShopHighlight == ShopHighlight.LeavingTomorrow;
        ShopBadge.Background = leaving
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["FSTStatusRedBrush"]
            : new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(0xE6, 0x12, 0x18, 0x26));
        ShopBadgeLabel.Foreground = leaving
            ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["FSTGoldBrush"];
    }

    /// <summary>Starts a card's top-10 read when it is realized.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnBoardPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (sender.ItemsSourceView?.GetAt(args.Index) is LeaderboardPreviewViewModel card) _ = card.EnsureLoadedAsync();
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
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Paths · {ViewModel.Song?.Title}",
            CloseButtonText = "Close",
            DefaultButton = ContentDialogButton.Close,
            FullSizeDesired = true,
            Content = new SongPathsView(paths),
        };
        dialog.Resources["ContentDialogMaxWidth"] = Math.Max(548, Math.Min(1200, XamlRoot.Size.Width - 48));
        dialog.Resources["ContentDialogMaxHeight"] = Math.Max(400, XamlRoot.Size.Height - 48);
        AutomationProperties.SetAutomationId(dialog, "fst.paths");
        _ = paths.LoadAsync();
        await dialog.ShowAsync();
        paths.Close();
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
