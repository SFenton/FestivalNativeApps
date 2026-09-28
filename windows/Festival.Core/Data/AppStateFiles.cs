namespace Festival.Core.Data;

#region Registry
/// <summary>What Settings' Reset does with a state file.</summary>
public enum AppStateReset
{
    /// <summary>Kept (seen-state, logs, or a file Reset rewrites in place, like settings).</summary>
    Keep,

    /// <summary>Deleted, so its feature starts from defaults.</summary>
    Delete,
}

/// <summary>One persisted per-user state file in <see cref="AppDataPaths.Folder"/>.</summary>
/// <param name="FileName">File name inside the data folder.</param>
/// <param name="Reset">Settings Reset behaviour.</param>
/// <param name="Owner">Section whose cached pages hold this state in memory (dropped after a Reset deletes it).</param>
public sealed record AppStateFile(string FileName, AppStateReset Reset, AppSection? Owner = null)
{
    /// <summary>Full path in the configured data folder.</summary>
    public string DefaultPath => Path.Combine(AppDataPaths.Folder, FileName);
}

/// <summary>
/// Every state file the app writes. A feature that persists anything adds its file here (and reads
/// <see cref="AppStateFile.DefaultPath"/>), so Settings Reset and per-lane Debug isolation cover it automatically.
/// </summary>
public static class AppStateFiles
{
    /// <summary>App settings and the selected player; Reset rewrites it in place (profile and song filters stay).</summary>
    public static AppStateFile Settings { get; } = new("settings.json", AppStateReset.Keep);

    /// <summary>First-run slides already seen (the web keeps these through a settings reset).</summary>
    public static AppStateFile FirstRun { get; } = new("first-run.json", AppStateReset.Keep);

    /// <summary>Notification IDs already seen.</summary>
    public static AppStateFile NotificationsSeen { get; } = new("notifications-seen.json", AppStateReset.Keep);

    /// <summary>Saved Suggestions instrument/type filter.</summary>
    public static AppStateFile SuggestionsFilter { get; } = new("suggestions-filter.json", AppStateReset.Delete, AppSection.Suggestions);

    /// <summary>Local diagnostics log (never uploaded).</summary>
    public static AppStateFile Diagnostics { get; } = new("diagnostics.log", AppStateReset.Keep);

    /// <summary>All registered files.</summary>
    public static IReadOnlyList<AppStateFile> All { get; } = [Settings, FirstRun, NotificationsSeen, SuggestionsFilter, Diagnostics];

    /// <summary>Files Settings Reset deletes.</summary>
    public static IReadOnlyList<AppStateFile> DeletedByReset { get; } = [.. All.Where(f => f.Reset == AppStateReset.Delete)];

    /// <summary>Deletes the Reset-owned files (and any leftover atomic-write temp copies) from a folder.</summary>
    /// <param name="folder">Data folder.</param>
    /// <returns>Files that existed and were deleted.</returns>
    public static IReadOnlyList<AppStateFile> DeleteForReset(string folder)
    {
        var deleted = new List<AppStateFile>();
        foreach (var file in DeletedByReset)
        {
            var path = Path.Combine(folder, file.FileName);
            try
            {
                var existed = File.Exists(path);
                File.Delete(path);
                File.Delete(path + ".tmp");
                if (existed) deleted.Add(file);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // Best effort: a locked file keeps its value; the owning page is still reloaded from disk.
            }
        }
        return deleted;
    }
}
#endregion
