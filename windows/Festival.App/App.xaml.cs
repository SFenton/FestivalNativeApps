using Festival.Core;
using Microsoft.UI.Xaml;

namespace Festival.App;

#region Application
/// <summary>Festival native Windows entry point.</summary>
public partial class App : Application
{
    private Window? window;
    private static readonly HttpClient Http = new();

    /// <summary>Initializes XAML resources.</summary>
    public App() => InitializeComponent();

    /// <summary>Creates the system-navigation shell without invoking any side-effecting endpoint.</summary>
    /// <param name="args">Launch details.</param>
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
#if DEBUG
        var endpoint = new Uri("http://127.0.0.1:8765/api/songs");
        const bool fixtureMode = true;
#else
        var endpoint = new Uri("https://festivalscoretracker.com/api/songs");
        const bool fixtureMode = false;
#endif
        var songs = new SongsState(new SongsClient(Http, endpoint, fixtureMode));
        window = new MainWindow(songs, fixtureMode);
        window.Activate();
    }
#endregion
}
