using Festival.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App;

#region Navigation shell
/// <summary>Native NavigationView shell for Songs and Settings.</summary>
public sealed partial class MainWindow : Window
{
    private readonly SongsState songs;
    private readonly bool fixtureMode;

    /// <summary>Creates the shell and selects the default Songs destination.</summary>
    /// <param name="songs">Shared Songs state.</param>
    /// <param name="fixtureMode">Whether local fixtures are active.</param>
    public MainWindow(SongsState songs, bool fixtureMode)
    {
        this.songs = songs;
        this.fixtureMode = fixtureMode;
        InitializeComponent();
        Shell.SelectedItem = Shell.MenuItems[0];
    }

    /// <summary>Routes native navigation selection to the associated page.</summary>
    /// <param name="sender">The navigation control.</param>
    /// <param name="args">Selected item.</param>
    private void OnSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
            ContentFrame.Content = new SettingsPage(fixtureMode);
        else
            ContentFrame.Content = new SongsPage(songs);
    }
#endregion
}
