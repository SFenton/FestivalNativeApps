using System.ComponentModel;
using System.Runtime.CompilerServices;
using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;

namespace Festival.App.Services;

#region Screen reader announcements
/// <summary>
/// Raises UIA notification events (Narrator speaks them; a WinUI live region alone does not) and attaches
/// <see cref="LoadAnnouncer"/>s to pages so loading, results and changes are announced.
/// </summary>
public static class ScreenReader
{
    private static readonly ConditionalWeakTable<FrameworkElement, LoadAnnouncer> Attached = [];

    /// <summary>Speaks an announcement through <paramref name="element"/>'s automation peer.</summary>
    /// <param name="element">Element whose peer raises the notification (must be in the live tree).</param>
    /// <param name="announcement">Text, kind and activity ID.</param>
    public static void Announce(UIElement element, Announcement announcement)
    {
        var peer = FrameworkElementAutomationPeer.FromElement(element) ?? FrameworkElementAutomationPeer.CreatePeerForElement(element);
        peer?.RaiseNotificationEvent(
            announcement.Kind == AnnouncementKind.Progress ? AutomationNotificationKind.ActionCompleted : AutomationNotificationKind.Other,
            announcement.Kind == AnnouncementKind.Error ? AutomationNotificationProcessing.ImportantAll : AutomationNotificationProcessing.MostRecent,
            announcement.Text, announcement.ActivityId);
    }

    /// <summary>
    /// Announces <paramref name="page"/>'s slow loads and result summaries until <see cref="Detach"/> (or the next
    /// <c>Attach</c> for the same page, e.g. a new view model on re-navigation).
    /// </summary>
    /// <param name="page">Page (speaks the announcements).</param>
    /// <param name="sources">View models whose changes affect the state.</param>
    /// <param name="isLoading">Whether the page is loading with nothing to show.</param>
    /// <param name="summary">Result summary, or <see langword="null"/>.</param>
    /// <param name="loadingText">Slow-load text (e.g. "Loading songs").</param>
    public static void Attach(FrameworkElement page, INotifyPropertyChanged[] sources, Func<bool> isLoading, Func<string?> summary,
        string? loadingText)
    {
        Detach(page);
        var queue = page.DispatcherQueue;
        var announcer = new LoadAnnouncer(sources, isLoading, summary, loadingText, TimeProvider.System,
            dispatch: action => queue.TryEnqueue(() => action()));
        announcer.Announced += (_, announcement) =>
        {
            if (page.IsLoaded) Announce(page, announcement);
        };
        Attached.AddOrUpdate(page, announcer);
    }

    /// <summary>Stops announcing for <paramref name="page"/>.</summary>
    /// <param name="page">Page passed to <see cref="Attach"/>.</param>
    public static void Detach(FrameworkElement page)
    {
        if (!Attached.TryGetValue(page, out var announcer)) return;
        announcer.Dispose();
        Attached.Remove(page);
    }
}
#endregion
