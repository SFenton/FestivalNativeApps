using System.Globalization;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Services;

#region Frame stats
/// <summary>
/// Measurement-only UI-thread frame intervals (<c>--frame-stats</c>): every 5 s writes
/// <c>ui-frames count=… p50=… p95=… p99=… over33=…</c> to the perf log. Subscribing to
/// <see cref="CompositionTarget.Rendering"/> makes XAML render every frame, so never enable it outside perf runs.
/// </summary>
internal static class FrameStats
{
    private static readonly List<double> Intervals = new(2048);
    private static TimeSpan? last;
    private static DateTime windowStart;

    /// <summary>Starts sampling.</summary>
    public static void Start()
    {
        windowStart = DateTime.UtcNow;
        CompositionTarget.Rendering += OnRendering;
    }

    /// <summary>Records one frame interval and flushes a summary every 5 s.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Rendering arguments.</param>
    private static void OnRendering(object? sender, object e)
    {
        var time = ((RenderingEventArgs)e).RenderingTime;
        if (last is { } previous && time > previous) Intervals.Add((time - previous).TotalMilliseconds);
        last = time;
        if (DateTime.UtcNow - windowStart < TimeSpan.FromSeconds(5) || Intervals.Count == 0) return;
        Intervals.Sort();
        double At(double p) => Intervals[Math.Min(Intervals.Count - 1, (int)(Intervals.Count * p))];
        PerfLog.Write(string.Create(CultureInfo.InvariantCulture,
            $"ui-frames count={Intervals.Count} p50={At(0.5):F2} p95={At(0.95):F2} p99={At(0.99):F2} over33={Intervals.Count(i => i > 33.4)}"));
        Intervals.Clear();
        windowStart = DateTime.UtcNow;
    }
}
#endregion
