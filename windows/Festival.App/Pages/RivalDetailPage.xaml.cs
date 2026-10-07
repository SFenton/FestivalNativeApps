using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region Rival detail page
/// <summary>Rival Detail (<c>/rivals/:rivalId</c>): head-to-head summary and category cards, each ending with the shared View All button.</summary>
public sealed partial class RivalDetailPage : Page
{
    /// <summary>Creates the page.</summary>
    public RivalDetailPage()
    {
        InitializeComponent();
        SizeChanged += (_, e) => VisualStateManager.GoToState(this, e.NewSize.Width < 640 ? "Narrow" : "Wide", false);
        _ = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, pane: null, menuMaxWidth: 640);
        KeyboardAccelerators.Add(RivalsPage.Accelerator(Windows.System.VirtualKey.F5, Windows.System.VirtualKeyModifiers.None,
            () => ViewModel.RefreshCommand.Execute(null)));
    }

    private readonly QuickLinksViewModel quickLinks = new("Quick Links");

    /// <summary>Page model (set on navigation).</summary>
    public RivalDetailViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new RivalDetailViewModel(App.Session, (AppRoute.RivalDetail)e.Parameter);
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading,
            () => ViewModel.ShowContent ? $"{ViewModel.Title} loaded" : ViewModel.ShowEmpty ? ViewModel.EmptyTitle : null, "Loading rival");
        ViewModel.PropertyChanged += (_, change) =>
        {
            if (change.PropertyName == nameof(RivalDetailViewModel.QuickLinkSections)) quickLinks.SetSections(ViewModel.QuickLinkSections);
        };
        Bindings.Update();
        ViewModel.Activate();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Opens the rival's player page.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnViewProfile(object sender, RoutedEventArgs e) => MainWindow.Instance?.Navigate(ViewModel.ProfileRoute);

    /// <summary>Navigates to a song or a category's View All route.</summary>
    /// <param name="sender">Element whose <c>Tag</c> is an <see cref="AppRoute"/>.</param>
    /// <param name="e">Unused.</param>
    private void OnRouteClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: AppRoute route }) MainWindow.Instance?.Navigate(route);
    }
}
#endregion
