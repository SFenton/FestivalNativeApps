using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Pages;

#region Settings page
/// <summary>Persisted preferences: profile, instrument visibility, accessibility overrides and About.</summary>
public sealed partial class SettingsPage : Page
{
    /// <summary>Creates the page.</summary>
    public SettingsPage()
    {
        ViewModel = new SettingsViewModel(App.Session);
        InitializeComponent();
        VersionText.Text = $"Festival Score Tracker for Windows {typeof(App).Assembly.GetName().Version?.ToString(3)}";
    }

    /// <summary>Page model.</summary>
    public SettingsViewModel ViewModel { get; }
}
#endregion
