using System.Diagnostics;
using Festival.Core.Domain;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Services;

#region Frame stats
/// <summary>
/// Measurement-only UI-thread frame intervals (<c>--frame-stats</c>): every 5 s writes
/// <c>ui-frames count=… p50=… p95=… p99=… max=… over33=…</c> (<see cref="FrameIntervalSummary"/>) to the perf log. Subscribing to
/// <see cref="CompositionTarget.Rendering"/> makes XAML render every frame, so never enable it outside perf runs.
/// </summary>
internal static class FrameStats
{
    private static readonly List<double> Intervals = new(2048);
    private static long? last;
    private static DateTime windowStart;

    /// <summary>Starts sampling.</summary>
    public static void Start()
    {
        windowStart = DateTime.UtcNow;
        CompositionTarget.Rendering += OnRendering;
    }

    /// <summary>Records one frame interval and flushes a summary every 5 s.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused: casting it to RenderingEventArgs fails under NativeAOT, so time the callbacks.</param>
    private static void OnRendering(object? sender, object e)
    {
        var now = Stopwatch.GetTimestamp();
        if (last is { } previous) Intervals.Add(Stopwatch.GetElapsedTime(previous, now).TotalMilliseconds);
        last = now;
        if (DateTime.UtcNow - windowStart < TimeSpan.FromSeconds(5) || FrameIntervalSummary.Format(Intervals) is not { } line) return;
        PerfLog.Write(line);
        Intervals.Clear();
        windowStart = DateTime.UtcNow;
    }
}
#endregion
