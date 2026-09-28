using System.Diagnostics;
using System.Globalization;

namespace Festival.App.Services;

#region Perf log
/// <summary>
/// Startup/perf markers for <c>tools/windows/perf.ps1</c>: each line is <c>name=milliseconds</c> since the
/// OS recorded process start. Disabled unless <c>--perf-log</c> or <c>FST_PERF_LOG</c> is set.
/// </summary>
internal static class PerfLog
{
    private static readonly DateTime ProcessStart = Process.GetCurrentProcess().StartTime.ToUniversalTime();
    private static readonly List<string> Pending = [];
    private static readonly HashSet<string> Once = [];
    private static readonly Lock Gate = new();
    private static string? path;
    private static bool configured;

    /// <summary>Sets the output file and flushes buffered markers.</summary>
    /// <param name="file">Target path, or <see langword="null"/> to disable.</param>
    public static void Configure(string? file)
    {
        lock (Gate)
        {
            configured = true;
            path = file;
            if (path is null) Pending.Clear();
            else Flush();
        }
    }

    /// <summary>Records a marker once per process.</summary>
    /// <param name="name">Marker name.</param>
    public static void Mark(string name)
    {
        var ms = (DateTime.UtcNow - ProcessStart).TotalMilliseconds;
        lock (Gate)
        {
            if (!Once.Add(name) || (configured && path is null)) return;
            Pending.Add(string.Create(CultureInfo.InvariantCulture, $"{name}={ms:F1}"));
            if (path is not null) Flush();
        }
    }

    /// <summary>Appends a free-form line (repeatable, e.g. periodic frame statistics).</summary>
    /// <param name="line">Line text.</param>
    public static void Write(string line)
    {
        lock (Gate)
        {
            if (path is null) return;
            Pending.Add(line);
            Flush();
        }
    }

    /// <summary>Appends buffered lines (caller holds the lock).</summary>
    private static void Flush()
    {
        try
        {
            File.AppendAllLines(path!, Pending);
        }
        catch (IOException)
        {
            // Perf logging must never affect the app.
        }
        Pending.Clear();
    }
}
#endregion
