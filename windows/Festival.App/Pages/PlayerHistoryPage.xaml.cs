using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Player history page
/// <summary>
/// Selected player's every score for one song and chart (<c>/songs/:songId/:instrument/history</c>, web
/// <c>PlayerHistoryPage</c>) over the song's static cover; Song Detail's "View All Scores" opens it (issue #324).
/// </summary>
public sealed partial class PlayerHistoryPage : Page, IBackdropPage
{
    /// <summary>Creates the page.</summary>
    public PlayerHistoryPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public PlayerHistoryViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel?.Dispose();
        ViewModel = new PlayerHistoryViewModel(App.Session, (AppRoute.PlayerHistory)e.Parameter);
        ViewModel.PropertyChanged += OnViewModelChanged;
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Announcement} loaded" : ViewModel.ShowMessage ? ViewModel.MessageTitle : null, "Loading score history");
        Bindings.Update();
        ShowSong();
        await ViewModel.LoadCommand.ExecuteAsync(null);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        if (ViewModel is null) return;
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.Dispose();
    }

    /// <summary>Shows the resolved song's art; a new sort order starts at the top (web <c>scrollTo(0)</c> on apply).</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PlayerHistoryViewModel.Song)) ShowSong();
        else if (e.PropertyName is nameof(PlayerHistoryViewModel.SortMode) or nameof(PlayerHistoryViewModel.SortAscending))
            Scroller.ChangeView(null, 0, null, !Motion.Allowed);
    }

    /// <summary>Updates the backdrop and header art for the resolved song.</summary>
    private void ShowSong()
    {
        if (ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        Header.ArtUrl = song.AlbumArt ?? "";
    }

    /// <summary>Opens Song Detail from the song header (web <c>onTitleClick={goToSongDetail}</c>).</summary>
    /// <param name="sender">Header.</param>
    /// <param name="e">Unused.</param>
    private void OnSongTitle(object? sender, EventArgs e) =>
        MainWindow.Instance?.Navigate(new AppRoute.SongDetail(ViewModel.SongId));

    /// <summary>Checks the current mode and direction when the sort menu opens.</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnSortMenuOpening(object sender, object e)
    {
        foreach (var item in SortMenu.Items.OfType<RadioMenuFlyoutItem>())
        {
            item.IsChecked = item.Tag switch
            {
                "asc" => ViewModel.SortAscending,
                "desc" => !ViewModel.SortAscending,
                string mode => mode == ViewModel.SortMode.ToString(),
                _ => false,
            };
        }
    }

    /// <summary>Applies a sort key.</summary>
    /// <param name="sender">Menu item.</param>
    /// <param name="e">Unused.</param>
    private void OnSortModeClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && Enum.TryParse<PlayerScoreSortMode>(tag, out var mode))
            ViewModel.SortByCommand.Execute(mode);
    }

    /// <summary>Applies a direction.</summary>
    /// <param name="sender">Menu item.</param>
    /// <param name="e">Unused.</param>
    private void OnSortDirectionClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && (tag == "asc") != ViewModel.SortAscending)
            ViewModel.ToggleDirectionCommand.Execute(null);
    }

    /// <summary>Restores Score, descending.</summary>
    /// <param name="sender">Menu item.</param>
    /// <param name="e">Unused.</param>
    private void OnSortResetClick(object sender, RoutedEventArgs e) => ViewModel.ResetSortCommand.Execute(null);
}
#endregion
