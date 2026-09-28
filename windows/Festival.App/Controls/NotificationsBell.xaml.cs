using Microsoft.UI.Xaml.Controls;

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

    /// <summary>Marks everything seen on close.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnClosed(object sender, object e) => Model.MarkAllSeen();

    /// <summary>Marks the row seen and navigates.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not NotificationRowViewModel row || Model.Activate(row) is not { } destination) return;
        Panel.Hide();
        Navigate(destination);
    }
}
#endregion
