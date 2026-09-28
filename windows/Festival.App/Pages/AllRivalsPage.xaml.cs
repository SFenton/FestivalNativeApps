using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region All rivals page
/// <summary>All Rivals (<c>/rivals/all</c>): one scope's full list in a virtualized, centred column.</summary>
public sealed partial class AllRivalsPage : Page
{
    /// <summary>Creates the page.</summary>
    public AllRivalsPage()
    {
        InitializeComponent();
        KeyboardAccelerators.Add(RivalsPage.Accelerator(Windows.System.VirtualKey.F5, Windows.System.VirtualKeyModifiers.None,
            () => ViewModel.RefreshCommand.Execute(null)));
    }

    /// <summary>Page model (set on navigation).</summary>
    public AllRivalsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new AllRivalsViewModel(App.Session, (AppRoute.AllRivals)e.Parameter);
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
        if (args.InRecycleQueue || args.Item is not RivalRowItem row) return;
        AutomationProperties.SetName(args.ItemContainer, row.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, "fst.all-rivals.row." + row.AccountId);
    }

    /// <summary>Opens the rival.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRivalClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is RivalRowItem row) MainWindow.Instance?.Navigate(row.Route);
    }
}
#endregion
