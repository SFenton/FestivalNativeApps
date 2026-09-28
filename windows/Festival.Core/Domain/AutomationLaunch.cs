namespace Festival.Core.Domain;

#region Automation launch
/// <summary>
/// Test-only automation switch (<c>--automation</c> or <c>FST_AUTOMATION=1</c>). While it is on, the launch honours the
/// Debug <c>FST_*</c> environment hooks (tab/route deep links, loopback base URL, isolated data folder and settings),
/// first-run carousels default to off and no other UI presents itself unasked, so UI journeys run the same on a
/// Release/NativeAOT build as on Debug. Debug builds honour the request alone. Release builds honour it only when the
/// automation marker file sits next to the executable: tooling drops it into its own publish folder, so an installed
/// build can never be switched into automation by an environment variable or a crafted shortcut.
/// </summary>
public static class AutomationLaunch
{
    /// <summary>Command-line flag.</summary>
    public const string Flag = "--automation";

    /// <summary>Environment variable (value <c>1</c>).</summary>
    public const string Variable = "FST_AUTOMATION";

    /// <summary>Marker file, in the executable folder, that allows automation in a Release build.</summary>
    public const string MarkerFileName = "fst-automation.marker";

    /// <summary>Whether this launch asks for automation.</summary>
    /// <param name="args">Command-line arguments (without the executable).</param>
    /// <param name="environment">Process environment lookup (read even in Release: the marker gates it).</param>
    /// <returns><see langword="true"/> when the flag is present or the variable is <c>1</c>.</returns>
    public static bool IsRequested(IReadOnlyList<string> args, Func<string, string?> environment) =>
        args.Any(a => string.Equals(a, Flag, StringComparison.OrdinalIgnoreCase)) || environment(Variable)?.Trim() == "1";

    /// <summary>Resolves whether automation is on for this launch.</summary>
    /// <param name="debugBuild">Whether this is a Debug build.</param>
    /// <param name="args">Command-line arguments (without the executable).</param>
    /// <param name="environment">Process environment lookup.</param>
    /// <param name="baseDirectory">Executable folder (<see cref="AppContext.BaseDirectory"/>).</param>
    /// <param name="fileExists">File probe, e.g. <see cref="File.Exists(string)"/>.</param>
    /// <returns><see langword="true"/> when requested and allowed.</returns>
    public static bool Resolve(
        bool debugBuild, IReadOnlyList<string> args, Func<string, string?> environment, string baseDirectory, Func<string, bool> fileExists) =>
        IsRequested(args, environment) && (debugBuild || fileExists(Path.Combine(baseDirectory, MarkerFileName)));
}
#endregion
