using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Bell
/// <summary>
/// Title-bar bell with an unread <see cref="InfoBadge"/>; its light-dismiss flyout lists New/Older rows. Opening
/// refreshes the feed (no background polling); closing marks every loaded row seen; a row with a destination closes
/// the flyout and navigates.
/// </summary>
public sealed partial class NotificationsBell : UserControl
{
    /// <summary>Creates the bell.</summary>
    /// <param name="model">Notifications model.</param>
    /// <param name="navigate">Opens a destination.</param>
    public NotificationsBell(NotificationsViewModel model, Action<NotificationDestination> navigate)
    {
        Model = model;
        Navigate = navigate;
        InitializeComponent();
    }

    /// <summary>Notifications model.</summary>
    public NotificationsViewModel Model { get; }

    /// <summary>Navigation callback.</summary>
    private Action<NotificationDestination> Navigate { get; }

    /// <summary>Refreshes on open.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnOpening(object sender, object e) => _ = Model.RefreshAsync();

    /// <summary>
    /// Names the flyout's popup. While loading, empty or not generated the flyout has nothing focusable, so focus rests
    /// on the popup itself, which UI Automation otherwise reports as an unnamed "Popup" window.
    /// </summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnOpened(object sender, object e)
    {
        if (XamlRoot is null) return;
        var ancestors = new HashSet<DependencyObject>();
        for (DependencyObject? node = PanelRoot; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is Popup host) AutomationProperties.SetName(host, "Notifications");
            ancestors.Add(node);
        }
        foreach (var popup in VisualTreeHelper.GetOpenPopupsForXamlRoot(XamlRoot))
            if (popup.Child is { } child && ancestors.Contains(child))
                AutomationProperties.SetName(popup, "Notifications");
    }

    /// <summary>Marks everything seen on close.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnClosed(object sender, object e) => Model.MarkAllSeen();

    /// <summary>Marks the row seen and navigates.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not NotificationRowViewModel row) return;
        var destination = Model.Activate(row);
        // The row stays on screen when it has no destination: drop "Unread." from its Narrator name.
        if (sender is ListViewBase list && list.ContainerFromItem(row) is DependencyObject container)
            AutomationProperties.SetName(container, row.AccessibleName);
        if (destination is null) return;
        Panel.Hide();
        Navigate(destination);
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
