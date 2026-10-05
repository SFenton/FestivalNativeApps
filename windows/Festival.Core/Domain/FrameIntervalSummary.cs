using System.Globalization;

namespace Festival.Core.Domain;

#region Frame interval summary
/// <summary>
/// The <c>--frame-stats</c> perf-log line for one window of UI-thread frame intervals:
/// <c>ui-frames count=… p50=… p95=… p99=… max=… over33=…</c>. <c>max</c> is the longest UI-thread stall, which the
/// Songs scroll stress journey (issue #247) holds under 250 ms; <c>over33</c> counts frames slower than 30 fps.
/// </summary>
public static class FrameIntervalSummary
{
    /// <summary>A frame interval above this (ms) misses 30 fps.</summary>
    public const double SlowFrameMs = 33.4;

    /// <summary>Formats one window's summary.</summary>
    /// <param name="intervals">Frame intervals in milliseconds; sorted in place.</param>
    /// <returns>The perf-log line, or <see langword="null"/> when there are no intervals.</returns>
    public static string? Format(List<double> intervals)
    {
        if (intervals.Count == 0) return null;
        intervals.Sort();
        double At(double p) => intervals[Math.Min(intervals.Count - 1, (int)(intervals.Count * p))];
        var slow = intervals.Count - intervals.FindLastIndex(i => i <= SlowFrameMs) - 1;
        return string.Create(CultureInfo.InvariantCulture,
            $"ui-frames count={intervals.Count} p50={At(0.5):F2} p95={At(0.95):F2} p99={At(0.99):F2} max={intervals[^1]:F2} over33={slow}");
    }
}
#endregion
