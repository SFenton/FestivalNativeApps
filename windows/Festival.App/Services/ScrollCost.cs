using System.Diagnostics;

namespace Festival.App.Services;

#region Scroll cost
/// <summary>
/// Measurement only (<c>--scroll-probe</c>): sums the UI-thread time of named per-scroll handlers so a probe pass can
/// attribute dropped frames. Inactive (one field read) outside a probe.
/// </summary>
internal static class ScrollCost
{
    private static readonly Dictionary<string, (double Ms, int Calls, double Max, long Bytes)> Totals = [];

    /// <summary>Whether a probe is collecting.</summary>
    public static bool Enabled { get; set; }

    /// <summary>A started measurement: timestamp (0 when disabled) and the UI thread's allocated bytes.</summary>
    /// <param name="Time">Stopwatch timestamp.</param>
    /// <param name="Bytes">Bytes allocated by the thread so far.</param>
    public readonly record struct Mark(long Time, long Bytes);

    /// <summary>Starts timing a handler.</summary>
    /// <returns>A mark, empty when disabled.</returns>
    public static Mark Begin() => Enabled ? new(Stopwatch.GetTimestamp(), GC.GetAllocatedBytesForCurrentThread()) : default;

    /// <summary>Adds a handler's elapsed time.</summary>
    /// <param name="name">Handler name.</param>
    /// <param name="start">Mark from <see cref="Begin"/>.</param>
    public static void End(string name, Mark start)
    {
        if (start.Time == 0) return;
        var ms = Stopwatch.GetElapsedTime(start.Time).TotalMilliseconds;
        var bytes = GC.GetAllocatedBytesForCurrentThread() - start.Bytes;
        var (total, calls, max, allocated) = Totals.GetValueOrDefault(name);
        Totals[name] = (total + ms, calls + 1, Math.Max(max, ms), allocated + bytes);
    }

    /// <summary>Formats and clears the totals.</summary>
    /// <returns>
    /// <c>handlers=</c> (the summed top-level handlers; a <c>parent:part</c> name times a part already inside its
    /// parent) followed by one <c>name=ms/calls/max/allocated</c> entry per handler.
    /// </returns>
    public static string Drain()
    {
        var total = Totals.Where(t => !t.Key.Contains(':')).Sum(t => t.Value.Ms);
        var text = $"handlers={total:F1}ms " + string.Join(' ', Totals.OrderByDescending(t => t.Value.Ms).Select(t => $"{t.Key}={t.Value.Ms:F1}ms/{t.Value.Calls}/max{t.Value.Max:F1}/{t.Value.Bytes / 1024}KB"));
        Totals.Clear();
        return text;
    }
}
#endregion
