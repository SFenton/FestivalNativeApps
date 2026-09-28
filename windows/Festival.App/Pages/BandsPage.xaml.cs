using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Bands landing page
/// <summary>
/// <c>/bands</c>: the selected player's bands and Band Rankings links. No band search: its GET can write server state.
/// </summary>
public sealed partial class BandsPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public BandsLandingViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new BandsLandingViewModel(App.Session);
        Bindings.Update();
        await ViewModel.LoadAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.Dispose();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Opens the selected player's full band list.</summary>
    /// <param name="sender">Link.</param>
    /// <param name="e">Unused.</param>
    private void OnViewAll(object sender, RoutedEventArgs e)
    {
        if (ViewModel.ViewAllRoute is { } route) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Opens Band Rankings for a size.</summary>
    /// <param name="sender">Card button.</param>
    /// <param name="e">Unused.</param>
    private void OnRankingLink(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: BandRankingLink link }) MainWindow.Instance?.Navigate(link.Route);
    }
}
#endregion
