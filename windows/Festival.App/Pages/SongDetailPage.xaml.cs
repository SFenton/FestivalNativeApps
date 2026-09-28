using System.ComponentModel;
using Festival.App.Services;
using Microsoft.UI.Xaml;
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
        if (e.PropertyName != nameof(SongDetailViewModel.Song) || ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(128 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
        PerfLog.Mark("song-detail-rendered");
    }

    /// <summary>Starts a card's top-10 read when it is realized.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnBoardPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (sender.ItemsSourceView?.GetAt(args.Index) is LeaderboardPreviewViewModel card) _ = card.EnsureLoadedAsync();
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
