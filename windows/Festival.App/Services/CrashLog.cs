namespace Festival.App.Services;

#region Crash log
/// <summary>
/// Appends unhandled exceptions and XAML binding/resource failures to <c>diagnostics.log</c> in the app data folder
/// (<see cref="AppDataPaths"/>; local only, never uploaded).
/// </summary>
internal static class CrashLog
{
    private static string Path => AppStateFiles.Diagnostics.DefaultPath;

    /// <summary>Appends one entry.</summary>
    /// <param name="error">Exception, if any.</param>
    /// <param name="message">Message.</param>
    public static void Write(Exception? error, string message)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.AppendAllText(Path, $"{DateTime.UtcNow:O} {message}{Environment.NewLine}{error}{Environment.NewLine}");
        }
        catch (IOException)
        {
            // Diagnostics must never crash the app.
        }
    }
}
#endregion
