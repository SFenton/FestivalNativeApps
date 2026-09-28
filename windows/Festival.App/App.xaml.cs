using System.Net;
using Festival.App.Services;
using Microsoft.UI.Xaml;

namespace Festival.App;

#region Application
/// <summary>Festival Score Tracker for Windows: composition root and launch handling.</summary>
public partial class App : Application
{
    private MainWindow? window;

    /// <summary>Loads XAML resources.</summary>
    public App()
    {
        PerfLog.Mark("app-constructor");
        InitializeComponent();
        UnhandledException += (_, e) => CrashLog.Write(e.Exception, e.Message);
        DebugSettings.BindingFailed += (_, e) => CrashLog.Write(null, "Binding failed: " + e.Message);
        DebugSettings.XamlResourceReferenceFailed += (_, e) => CrashLog.Write(null, "Resource failed: " + e.Message);
    }

    /// <summary>The process-lifetime session shared by every page.</summary>
    public static FestivalSession Session { get; private set; } = null!;

    /// <summary>Parsed launch/debug options.</summary>
    public static LaunchOptions Options { get; private set; } = new();

    /// <summary>Builds services and shows the main window. Never calls a side-effecting endpoint.</summary>
    /// <param name="args">Launch details.</param>
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Options = LaunchOptions.Parse(Environment.GetCommandLineArgs().Skip(1).ToArray(), Environment.GetEnvironmentVariable);
        PerfLog.Configure(Options.PerfLogPath);
        var handler = new SocketsHttpHandler
        {
            AutomaticDecompression = DecompressionMethods.All,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            UseCookies = false,
        };
        var http = new HttpClient(handler);
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"FestivalScoreTracker-Windows/{typeof(App).Assembly.GetName().Version?.ToString(3)}");
        var api = new FestivalApiClient(new RequestGate(http), Options.BaseUri);
        Session = new FestivalSession(api, new JsonFileSettingsStore(JsonFileSettingsStore.DefaultPath));
        window = new MainWindow(Session, Options);
        window.Activate();
        PerfLog.Mark("window-activated");
    }
}
#endregion
