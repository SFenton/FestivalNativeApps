using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Notifications panel
/// <summary>
/// Body of the Notifications modal (issue #638): the no-player, loading, failed (Retry) and empty states and the New/Older
/// rows. The bell shows it in the shared <see cref="FestivalDialog"/>, docked to the window edge.
/// </summary>
public sealed partial class NotificationsPanel : UserControl
{
    /// <summary>Creates the body.</summary>
    /// <param name="model">Notifications model.</param>
    /// <param name="activated">Called with a row's destination after it is activated.</param>
    public NotificationsPanel(NotificationsViewModel model, Action<NotificationDestination> activated)
    {
        Model = model;
        Activated = activated;
        InitializeComponent();
    }

    /// <summary>Notifications model.</summary>
    public NotificationsViewModel Model { get; }

    /// <summary>Destination callback.</summary>
    private Action<NotificationDestination> Activated { get; }

    /// <summary>Marks the row seen and, when it has a destination, hands it to <see cref="Activated"/>.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not NotificationRowViewModel row) return;
        var destination = Model.Activate(row);
        // The row stays on screen when it has no destination: drop "Unread." from its Narrator name.
        if (sender is ListViewBase list && list.ContainerFromItem(row) is DependencyObject container)
            AutomationProperties.SetName(container, row.AccessibleName);
        if (destination is not null) Activated(destination);
    }

    /// <summary>Names each row's ListViewItem for UI Automation (one Narrator stop per row).</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not NotificationRowViewModel row) return;
        AutomationProperties.SetName(args.ItemContainer, row.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, row.AutomationId);
    }
}
#endregion
