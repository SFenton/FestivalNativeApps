using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Player history page
/// <summary>Selected player's score history for one song and chart.</summary>
public sealed partial class PlayerHistoryPage : Page
{
    /// <summary>Creates the page.</summary>
    public PlayerHistoryPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public PlayerHistoryViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel?.Dispose();
        ViewModel = new PlayerHistoryViewModel(App.Session, (AppRoute.PlayerHistory)e.Parameter);
        Bindings.Update();
        await ViewModel.LoadCommand.ExecuteAsync(null);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel?.Dispose();
    }

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
}
#endregion
