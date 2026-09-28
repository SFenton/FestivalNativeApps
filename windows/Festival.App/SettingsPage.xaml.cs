using Microsoft.UI.Xaml.Controls;

namespace Festival.App;

#region Settings screen
/// <summary>Displays the active transport mode without exposing service credentials.</summary>
public sealed partial class SettingsPage : Page
{
    /// <summary>Creates the read-only Settings page.</summary>
    /// <param name="fixtureMode">Whether the app uses the local fixture endpoint.</param>
    public SettingsPage(bool fixtureMode)
    {
        InitializeComponent();
        ConnectionMode.Text = fixtureMode
            ? "Debug: local fixture server only (127.0.0.1:8765)."
            : "Release: HTTPS read-only songs endpoint.";
    }
#endregion
}
