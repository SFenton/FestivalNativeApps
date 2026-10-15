using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Services;

#region Scroll probe
/// <summary>
/// Measurement only (<c>--scroll-probe</c>, needs <c>--perf-log</c>): after the page settles, scrolls the routed page's
/// main scroller like mouse-wheel notches (animated <see cref="ScrollViewer.ChangeView(double?, double?, float?, bool)"/>
/// steps down then up) and logs per-pass frame, offset and handler-cost statistics (#642). A smooth scroll moves the
/// offset one way every frame (<c>reversals</c> counts frames moving against it), keeps frame intervals near the
/// display's refresh (<c>over33</c> counts stalls of two 60 Hz frames or more) and leaves the frames to rendering
/// (<see cref="ScrollCost"/>: the UI-thread time of per-scroll handlers). Each notch restarts the scroll animation's ease,
/// so the speed varies from frame to frame by design. Subscribing to rendering keeps XAML drawing every frame, so never
/// enable it outside perf runs.
/// </summary>
internal static class ScrollProbe
{
    private const int Notches = 14;
    private const double NotchEpx = 120;
    private static readonly TimeSpan NotchInterval = TimeSpan.FromMilliseconds(90);
    private static readonly List<double> Intervals = new(1024);
    private static readonly List<double> Deltas = new(1024);
    private static readonly List<string> Trace = [];
    private static long allocated;
    private static int gen0;
    private static int gen2;
    private static TimeSpan gcPause;
    private static int layouts;
    private static DispatcherQueueTimer? start;
    private static ScrollViewer? viewer;
    private static long? lastFrame;
    private static double lastOffset;
    private static double lastExtent;
    private static int extentChanges;
    private static int direction;

    /// <summary>Starts the probe after the page has loaded.</summary>
    /// <param name="root">Window content.</param>
    public static void Start(FrameworkElement root)
    {
        // Held in a field: an unreferenced one-shot timer can be collected before it fires.
        start = root.DispatcherQueue.CreateTimer();
        start.Interval = TimeSpan.FromSeconds(8);
        start.IsRepeating = false;
        start.Tick += async (_, _) =>
        {
            try
            {
                await RunAsync(root);
            }
            catch (Exception error)
            {
                PerfLog.Write($"scroll-probe error {error.GetType().Name}: {error.Message}");
            }
        };
        start.Start();
    }

    /// <summary>Runs three down/up cycles and logs each pass.</summary>
    /// <param name="root">Window content.</param>
    /// <returns>Probe task.</returns>
    private static async Task RunAsync(FrameworkElement root)
    {
        viewer = FindMain(root);
        if (viewer is null)
        {
            PerfLog.Write("scroll-probe none");
            return;
        }
        PerfLog.Write($"scroll-probe target={Describe(viewer)} scrollable={viewer.ScrollableHeight:F1} anchor={viewer.VerticalAnchorRatio}");
        ScrollCost.Enabled = true;
        viewer.LayoutUpdated += (_, _) => layouts++;
        CompositionTarget.Rendering += OnRendering;
        // A still pass first: what the probe's own frame tick and idle page work cost without scrolling.
        Begin(1);
        await Task.Delay(2000);
        Flush("rest");
        for (var cycle = 0; cycle < 3; cycle++)
        {
            foreach (var down in new[] { true, false })
            {
                Begin(down ? 1 : -1);
                for (var i = 0; i < Notches; i++)
                {
                    var target = Math.Clamp(viewer.VerticalOffset + (down ? NotchEpx : -NotchEpx), 0, viewer.ScrollableHeight);
                    viewer.ChangeView(null, target, null, false);
                    await Task.Delay(NotchInterval);
                }
                await Task.Delay(600);
                Flush(down ? "down" : "up");
            }
        }
        CompositionTarget.Rendering -= OnRendering;
        ScrollCost.Enabled = false;
        PerfLog.Write("scroll-probe done");
    }

    /// <summary>Resets the per-pass samples.</summary>
    /// <param name="dir">Scroll direction (+1 down, -1 up).</param>
    private static void Begin(int dir)
    {
        Intervals.Clear();
        Deltas.Clear();
        Trace.Clear();
        allocated = GC.GetTotalAllocatedBytes();
        gen0 = GC.CollectionCount(0);
        gen2 = GC.CollectionCount(2);
        gcPause = GC.GetTotalPauseDuration();
        layouts = 0;
        ScrollCost.Drain();
        lastFrame = null;
        lastOffset = viewer!.VerticalOffset;
        lastExtent = viewer.ExtentHeight;
        extentChanges = 0;
        direction = dir;
    }

    /// <summary>Samples one frame: interval, offset delta and extent change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private static void OnRendering(object? sender, object e)
    {
        if (viewer is null) return;
        var now = Stopwatch.GetTimestamp();
        if (lastFrame is { } previous) Intervals.Add(Stopwatch.GetElapsedTime(previous, now).TotalMilliseconds);
        lastFrame = now;
        var offset = viewer.VerticalOffset;
        var delta = offset - lastOffset;
        if (delta != 0 && Intervals.Count > 0) Deltas.Add(delta * direction);
        if (delta * direction < -0.01 && Trace.Count < 40) Trace.Add($"{Intervals.Count}:{lastOffset:F1}->{offset:F1}");
        lastOffset = offset;
        if (Math.Abs(viewer.ExtentHeight - lastExtent) > 0.01) extentChanges++;
        lastExtent = viewer.ExtentHeight;
    }

    /// <summary>Writes one pass's statistics.</summary>
    /// <param name="label">Pass label.</param>
    private static void Flush(string label)
    {
        if (Intervals.Count == 0) return;
        var sorted = Intervals.Order().ToList();
        var moving = Deltas.Where(d => d > 0).Order().ToList();
        var median = moving.Count > 0 ? moving[moving.Count / 2] : 0;
        var reversals = Deltas.Count(d => d < -0.01);
        double P(double q) => sorted[Math.Min(sorted.Count - 1, (int)(q * sorted.Count))];
        PerfLog.Write(
            $"scroll-probe {label} frames={sorted.Count} p50={P(0.5):F1} p95={P(0.95):F1} max={sorted[^1]:F1} over33={sorted.Count(i => i > 33.4)} " +
            $"moves={Deltas.Count} median={median:F2} reversals={reversals} worstBack={(reversals > 0 ? -Deltas.Min() : 0):F2} " +
            $"extentChanges={extentChanges} layouts={layouts} offset={viewer!.VerticalOffset:F2}");
        // Blocking collections pause the UI thread: each gen2 one is a long frame. C#/WinRT adds GC memory pressure per
        // wrapper it creates, so short-lived WinRT objects (event args, transforms) induce gen2 collections on a small
        // heap; fin= counts the dead finalizable objects (mostly such wrappers) the last collection found.
        var last = GC.GetGCMemoryInfo(GCKind.Any);
        PerfLog.Write(
            $"scroll-probe gc {label} allocMB={(GC.GetTotalAllocatedBytes() - allocated) / 1048576.0:F1} gc0={GC.CollectionCount(0) - gen0} gc2={GC.CollectionCount(2) - gen2} " +
            $"pause={(GC.GetTotalPauseDuration() - gcPause).TotalMilliseconds:F1}ms last=gen{last.Generation}{(last.Concurrent ? "-bg" : "")}{(last.Compacted ? "-compact" : "")} " +
            $"load={last.MemoryLoadBytes * 100.0 / Math.Max(1, last.TotalAvailableMemoryBytes):F0}%/{last.HighMemoryLoadThresholdBytes * 100.0 / Math.Max(1, last.TotalAvailableMemoryBytes):F0}% heapMB={last.HeapSizeBytes / 1048576.0:F0} fin={last.FinalizationPendingCount}");
        PerfLog.Write($"scroll-probe cost {label} {ScrollCost.Drain()}");
        if (Trace.Count > 0) PerfLog.Write($"scroll-probe back {string.Join(' ', Trace)}");
    }

    /// <summary>
    /// Finds the visible scroller with the largest viewport, the innermost of equal ones (a SemanticZoom wraps its list's
    /// scroller in a zoom scroller of the same size that pins its content at the middle).
    /// </summary>
    /// <param name="root">Window content.</param>
    /// <returns>Scroller or <see langword="null"/>.</returns>
    private static ScrollViewer? FindMain(DependencyObject root)
    {
        ScrollViewer? best = null;
        var bestArea = 0.0;
        var stack = new Stack<DependencyObject>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            var node = stack.Pop();
            if (node is UIElement { Visibility: Visibility.Collapsed }) continue;
            if (node is ScrollViewer sv && sv.ScrollableHeight > 0 && sv.ViewportHeight > 200
                && sv.ViewportHeight * sv.ViewportWidth >= bestArea - 1)
            {
                best = sv;
                bestArea = sv.ViewportHeight * sv.ViewportWidth;
            }
            for (var i = VisualTreeHelper.GetChildrenCount(node) - 1; i >= 0; i--) stack.Push(VisualTreeHelper.GetChild(node, i));
        }
        return best;
    }

    /// <summary>Names a scroller by its nearest named ancestor.</summary>
    /// <param name="element">Scroller.</param>
    /// <returns>Description.</returns>
    private static string Describe(FrameworkElement element)
    {
        var names = new List<string>();
        DependencyObject? node = element;
        while (node is FrameworkElement fe && names.Count < 4)
        {
            if (!string.IsNullOrEmpty(fe.Name) || fe is Page) names.Add($"{fe.GetType().Name}:{fe.Name}");
            node = VisualTreeHelper.GetParent(fe);
        }
        return string.Join('<', names) + $" start={((ScrollViewer)element).VerticalOffset:F1}";
    }
}
#endregion
