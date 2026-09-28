namespace Festival.App.Services;

#region Crash log
/// <summary>
/// Appends unhandled exceptions and XAML binding/resource failures to
/// <c>%LOCALAPPDATA%\FestivalScoreTracker\diagnostics.log</c> (local only; never uploaded).
/// </summary>
internal static class CrashLog
{
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FestivalScoreTracker", "diagnostics.log");

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
