using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Bell
/// <summary>
/// Title-bar bell with an unread <see cref="InfoBadge"/>. It opens Notifications (<see cref="NotificationsPanel"/>) in the
/// shared modal docked to the window edge (issue #638). Opening refreshes the feed (no background polling); closing marks
/// every loaded row seen; a row with a destination closes the modal and navigates.
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

    /// <summary>Modal title (web <c>MobileNotificationsModal</c>).</summary>
    private const string NotificationsTitle = "Notifications";

    private NotificationsPanel? panel;
    private ContentDialog? open;
    private NotificationDestination? pending;

    /// <summary>
    /// Clears the contrast-theme text backplate from the badge's template parts. <see cref="UIElement.HighContrastAdjustment"/>
    /// is per element, and the count's <see cref="TextBlock"/> only exists once the badge is first shown and measured, so
    /// this runs on load and on every size change (first show, or the count gaining a digit).
    /// </summary>
    /// <param name="sender">Badge.</param>
    /// <param name="e">Unused.</param>
    private void OnBadgeLayout(object sender, RoutedEventArgs e) => DialogChrome.WithoutBackplate(UnreadBadge);

    /// <summary>
    /// Opens Notifications in the shared modal, docked to the window edge (issue #638): a trailing panel in a wide window,
    /// a bottom sheet once navigation collapses to the hamburger menu. Opening refreshes the feed; closing (Close, Esc, an
    /// outside click or a row's navigation) marks every loaded row seen, and focus returns to the bell.
    /// </summary>
    /// <param name="sender">Bell.</param>
    /// <param name="e">Unused.</param>
    private async void OnBellClick(object sender, RoutedEventArgs e)
    {
        if (open is not null || XamlRoot is null) return;
        panel ??= new NotificationsPanel(Model, OnActivated);
        var dialog = FestivalDialog.Create(XamlRoot, NotificationsTitle, panel, "fst.notifications.sheet");
        DialogChrome.WindowEdge(dialog, MainWindow.Instance?.NavigationMinimalBelow ?? ModalEdgeLayout.MinimalNavigationBelow);
        open = dialog;
        _ = Model.RefreshAsync();
        try
        {
            await FestivalDialog.ShowAsync(dialog);
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            Services.CrashLog.Write(error, "Notifications dialog");
            pending = null;
        }
        finally
        {
            open = null;
            // The body is reused by the next opening, so it leaves this dialog.
            dialog.Content = null;
            Model.MarkAllSeen();
        }
        if (pending is { } destination)
        {
            pending = null;
            Navigate(destination);
        }
    }

    /// <summary>A row with a destination closes the modal, then navigates once it has closed.</summary>
    /// <param name="destination">Destination.</param>
    private void OnActivated(NotificationDestination destination)
    {
        pending = destination;
        open?.Hide();
    }
}
#endregion
