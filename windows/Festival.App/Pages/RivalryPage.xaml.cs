using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Rivalry page
/// <summary>Rivalry (<c>/rivals/:rivalId/rivalry?mode=</c>): one category's songs head to head, virtualized, with a sort.</summary>
public sealed partial class RivalryPage : Page
{
    /// <summary>Creates the page.</summary>
    public RivalryPage()
    {
        InitializeComponent();
        SizeChanged += (_, e) => VisualStateManager.GoToState(this, e.NewSize.Width < 640 ? "Narrow" : "Wide", false);
        KeyboardAccelerators.Add(RivalsPage.Accelerator(Windows.System.VirtualKey.F5, Windows.System.VirtualKeyModifiers.None,
            () => ViewModel.RefreshCommand.Execute(null)));
    }

    /// <summary>Page model (set on navigation).</summary>
    public RivalryViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new RivalryViewModel(App.Session, (AppRoute.Rivalry)e.Parameter);
        Bindings.Update();
        ViewModel.Activate();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Names each row container for UI Automation.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not RivalSongItem row) return;
        AutomationProperties.SetName(args.ItemContainer, row.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, row.AutomationId);
    }

    /// <summary>Opens the song on its chart.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnSongClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is RivalSongItem row) MainWindow.Instance?.Navigate(row.Route);
    }

    /// <summary>Opens the rival's player page.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnViewProfile(object sender, RoutedEventArgs e) => MainWindow.Instance?.Navigate(ViewModel.ProfileRoute);
}
#endregion
