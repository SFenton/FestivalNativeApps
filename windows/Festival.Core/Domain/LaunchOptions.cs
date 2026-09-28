using System.Globalization;

namespace Festival.Core.Domain;

#region Launch options
/// <summary>
/// Debug/automation launch arguments, mirroring Apple's <c>FST_DEBUG_TAB</c>/<c>FST_DEBUG_ROUTE</c>.
/// Command-line flags win over environment variables:
/// <c>--tab songs</c>, <c>--route /songs/{id}</c>, <c>--base-url http://127.0.0.1:8765/</c> (loopback only),
/// <c>--perf-log path</c>, <c>--width 1280 --height 800</c>, <c>--reduce-motion</c>, <c>--no-art</c>,
/// <c>--auto-scroll</c> (perf scenario: scroll the Songs list continuously), <c>--drift-fps N</c> (background drift steps/s),
/// <c>--frame-stats</c> (UI-thread frame intervals in the perf log), <c>--profile accountId:Name</c> (select a player in memory
/// only, never persisted), <c>--anonymous</c> (no player, in memory only), <c>--settings-path file</c> (isolated settings file).
/// </summary>
public sealed record LaunchOptions
{
    /// <summary>Initial section.</summary>
    public AppSection? Tab { get; init; }

    /// <summary>Initial route (pushed on the route's section).</summary>
    public AppRoute? Route { get; init; }

    /// <summary>Loopback fixture origin; <see langword="null"/> means production HTTPS.</summary>
    public Uri? BaseUri { get; init; }

    /// <summary>File that receives startup/perf markers.</summary>
    public string? PerfLogPath { get; init; }

    /// <summary>Requested client width in DIPs.</summary>
    public int? Width { get; init; }

    /// <summary>Requested client height in DIPs.</summary>
    public int? Height { get; init; }

    /// <summary>Forces reduced motion for this launch.</summary>
    public bool ReduceMotion { get; init; }

    /// <summary>Forces the no-art state for this launch.</summary>
    public bool NoArt { get; init; }

    /// <summary>Scrolls the Songs list continuously (frame-delivery perf scenario).</summary>
    public bool AutoScroll { get; init; }

    /// <summary>Logs UI-thread frame intervals to the perf log (measurement only; keeps XAML rendering every frame).</summary>
    public bool FrameStats { get; init; }

    /// <summary>Background drift update rate override (steps per second, 0 = every compositor frame).</summary>
    public int? DriftFps { get; init; }

    /// <summary>Player selected in memory for this launch only (<c>FST_DEBUG_PROFILE=accountId:Name</c>); never persisted.</summary>
    public SelectedPlayer? DebugProfile { get; init; }

    /// <summary>Launch with no selected player, in memory only (<c>FST_DEBUG_ANONYMOUS=1</c>).</summary>
    public bool Anonymous { get; init; }

    /// <summary>Settings file replacing the per-user default (<c>FST_SETTINGS_PATH</c>), so automation never touches real settings.</summary>
    public string? SettingsPath { get; init; }

    /// <summary>Whether settings must stay in memory (a debug profile or anonymous launch).</summary>
    public bool InMemorySettings => DebugProfile is not null || Anonymous;

    /// <summary>Problems found while parsing (unknown flags, rejected values).</summary>
    public IReadOnlyList<string> Warnings { get; init; } = [];

    /// <summary>Parses arguments and environment.</summary>
    /// <param name="args">Command-line arguments (without the executable).</param>
    /// <param name="environment">Environment lookup, e.g. <see cref="Environment.GetEnvironmentVariable(string)"/>.</param>
    /// <returns>Parsed options.</returns>
    public static LaunchOptions Parse(IReadOnlyList<string> args, Func<string, string?> environment)
    {
        var values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
        {
            ["tab"] = environment("FST_DEBUG_TAB"),
            ["route"] = environment("FST_DEBUG_ROUTE"),
            ["base-url"] = environment("FST_BASE_URL"),
            ["perf-log"] = environment("FST_PERF_LOG"),
            ["profile"] = environment("FST_DEBUG_PROFILE"),
            ["settings-path"] = environment("FST_SETTINGS_PATH"),
        };
        var flags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (environment("FST_DEBUG_ANONYMOUS") == "1") flags.Add("anonymous");
        var warnings = new List<string>();
        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i];
            if (!arg.StartsWith("--", StringComparison.Ordinal))
            {
                warnings.Add($"Ignored argument '{arg}'.");
                continue;
            }
            var name = arg[2..];
            var equals = name.IndexOf('=');
            if (equals > 0)
                values[name[..equals]] = name[(equals + 1)..];
            else if (name is "reduce-motion" or "no-art" or "auto-scroll" or "frame-stats" or "anonymous")
                flags.Add(name);
            else if (i + 1 < args.Count)
                values[name] = args[++i];
            else
                warnings.Add($"Missing value for '{arg}'.");
        }

        AppSection? tab = null;
        if (values.GetValueOrDefault("tab") is { Length: > 0 } tabText)
        {
            if (AppSections.TryParse(tabText, out var parsedTab)) tab = parsedTab;
            else warnings.Add($"Unknown tab '{tabText}'.");
        }
        AppRoute? route = null;
        if (values.GetValueOrDefault("route") is { Length: > 0 } routeText)
        {
            if (AppRouteParser.TryParse(routeText, out var parsedRoute, out var section))
            {
                route = parsedRoute;
                tab ??= section;
            }
            else
            {
                warnings.Add($"Unknown route '{routeText}'.");
            }
        }
        Uri? baseUri = null;
        if (values.GetValueOrDefault("base-url") is { Length: > 0 } baseText)
        {
            if (Uri.TryCreate(baseText, UriKind.Absolute, out var parsed) && parsed.IsLoopback && parsed.Scheme == Uri.UriSchemeHttp)
                baseUri = parsed;
            else
                warnings.Add("Only a loopback http:// base URL may replace production.");
        }
        SelectedPlayer? profile = null;
        if (values.GetValueOrDefault("profile") is { Length: > 0 } profileText)
        {
            var colon = profileText.IndexOf(':');
            var candidate = colon > 0 ? new SelectedPlayer(profileText[..colon], profileText[(colon + 1)..].Trim()) : null;
            if (candidate is { IsValid: true }) profile = candidate;
            else warnings.Add("Debug profile must be 'accountId:Display Name'.");
        }
        return new LaunchOptions
        {
            DebugProfile = profile,
            Anonymous = flags.Contains("anonymous") && profile is null,
            SettingsPath = values.GetValueOrDefault("settings-path") is { Length: > 0 } settingsPath ? settingsPath : null,
            Tab = tab,
            Route = route,
            BaseUri = baseUri,
            PerfLogPath = values.GetValueOrDefault("perf-log") is { Length: > 0 } log ? log : null,
            Width = Dimension(values.GetValueOrDefault("width")),
            Height = Dimension(values.GetValueOrDefault("height")),
            ReduceMotion = flags.Contains("reduce-motion"),
            NoArt = flags.Contains("no-art"),
            AutoScroll = flags.Contains("auto-scroll"),
            FrameStats = flags.Contains("frame-stats"),
            DriftFps = int.TryParse(values.GetValueOrDefault("drift-fps"), NumberStyles.None, CultureInfo.InvariantCulture, out var fps) && fps <= 240 ? fps : null,
            Warnings = warnings,
        };
    }

    /// <summary>Parses a window dimension in 320–7680 DIPs.</summary>
    /// <param name="value">Text.</param>
    /// <returns>Dimension or <see langword="null"/>.</returns>
    private static int? Dimension(string? value) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var n) && n is >= 320 and <= 7680 ? n : null;
}
#endregion
