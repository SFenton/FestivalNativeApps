using System.Security.Cryptography;
using System.Text;

namespace Festival.Core.Data;

#region App data folder
/// <summary>
/// Where the app keeps its per-user state files (<see cref="AppStateFiles"/>). Release always uses
/// <c>%LOCALAPPDATA%\FestivalScoreTracker</c>. Debug builds use <c>FST_DEBUG_DATA_DIR</c> when set, otherwise a folder
/// derived from the build's worktree (<c>%LOCALAPPDATA%\FestivalScoreTracker.Debug\&lt;worktree&gt;-&lt;hash&gt;</c>), so
/// Debug runs from parallel lane worktrees never share settings, the selected profile or seen-state.
/// </summary>
public static class AppDataPaths
{
    /// <summary>Debug-only environment variable naming an explicit data folder.</summary>
    public const string DataDirVariable = "FST_DEBUG_DATA_DIR";

    /// <summary>Release (and default) folder name under <c>%LOCALAPPDATA%</c>.</summary>
    public const string ReleaseFolderName = "FestivalScoreTracker";

    /// <summary>Parent folder name under <c>%LOCALAPPDATA%</c> for derived Debug folders.</summary>
    public const string DebugFolderName = "FestivalScoreTracker.Debug";

    /// <summary>The configured folder; the Release location until <see cref="Configure"/> runs at launch.</summary>
    public static string Folder { get; private set; } = ReleaseFolder(LocalAppData);

    /// <summary>Current user's <c>%LOCALAPPDATA%</c>.</summary>
    private static string LocalAppData => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

    /// <summary>Sets the process-wide folder. Call once at launch, before any store reads its default path.</summary>
    /// <param name="folder">Absolute or relative folder (made absolute).</param>
    public static void Configure(string folder) => Folder = Path.GetFullPath(folder);

    /// <summary>Resolves the data folder for a launch.</summary>
    /// <param name="debugBuild">Whether this is a Debug build (Release ignores the environment).</param>
    /// <param name="environment">Environment lookup.</param>
    /// <param name="baseDirectory">Executable folder (<see cref="AppContext.BaseDirectory"/>).</param>
    /// <param name="localAppData">The user's local app data root.</param>
    /// <returns>Absolute folder path.</returns>
    public static string Resolve(bool debugBuild, Func<string, string?> environment, string baseDirectory, string localAppData)
    {
        if (!debugBuild) return ReleaseFolder(localAppData);
        if (environment(DataDirVariable) is { Length: > 0 } explicitFolder) return Path.GetFullPath(explicitFolder);
        return Path.Combine(localAppData, DebugFolderName, DebugKey(baseDirectory));
    }

    /// <summary>Release folder under a local app data root.</summary>
    /// <param name="localAppData">Root.</param>
    /// <returns>Folder.</returns>
    public static string ReleaseFolder(string localAppData) => Path.Combine(localAppData, ReleaseFolderName);

    /// <summary>
    /// Stable, readable key for a build: the enclosing git worktree's folder name plus a short hash of its full path
    /// (two clones named alike stay apart). Outside a worktree the executable folder stands in for it.
    /// </summary>
    /// <param name="baseDirectory">Executable folder.</param>
    /// <returns>Key such as <c>win-shell-1a2b3c4d</c>.</returns>
    internal static string DebugKey(string baseDirectory)
    {
        var start = Path.GetFullPath(baseDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var root = WorktreeRoot(start) ?? start;
        var name = new string(Path.GetFileName(root).Select(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.' ? c : '_').ToArray());
        if (name.Length is 0 or > 40) name = name.Length == 0 ? "app" : name[..40];
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(root.ToUpperInvariant()));
        return $"{name}-{Convert.ToHexStringLower(hash)[..8]}";
    }

    /// <summary>The nearest ancestor holding a <c>.git</c> folder or worktree file.</summary>
    /// <param name="start">Folder to start from.</param>
    /// <returns>Root, or <see langword="null"/> when none.</returns>
    private static string? WorktreeRoot(string start)
    {
        for (var folder = start; !string.IsNullOrEmpty(folder); folder = Path.GetDirectoryName(folder))
        {
            var git = Path.Combine(folder, ".git");
            if (Directory.Exists(git) || File.Exists(git)) return folder;
        }
        return null;
    }
}
#endregion
