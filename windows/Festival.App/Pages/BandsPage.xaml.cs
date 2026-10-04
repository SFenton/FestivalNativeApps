using Festival.App.Services;
using Festival.Core.ViewModels;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Pages;

#region Bands without an ID
/// <summary>
/// <c>/bands</c> with no band ID: the web's "Band not found" state. Bands are reached from a player's Bands list or Band
/// Rankings (band search is blocked: its GET can write server state).
/// </summary>
public sealed partial class BandsPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsPage()
    {
        InitializeComponent();
        // Like ServiceStatusView errors: navigation only reads focus and the title, so speak the failure itself.
        Loaded += (_, _) => DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            if (IsLoaded) ScreenReader.Announce(this, Announcement.Failure(NotFoundTitle.Text, NotFoundMessage.Text));
        });
    }
}
#endregion
