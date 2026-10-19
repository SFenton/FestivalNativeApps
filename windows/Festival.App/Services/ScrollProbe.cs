using System.Diagnostics;
using Festival.Core.Domain;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Services;

#region Scroll probe
/// <summary>
/// Measurement only (<c>--scroll-probe</c>, needs <c>--perf-log</c>): after the page settles, scrolls the routed page's
/// main scroller (or, with <c>--scroll-probe-target dialog</c>, the open dialog's) and logs per-pass frame, offset and
/// handler-cost statistics (#642, #668). Three wheel cycles step it like mouse-wheel notches (animated
/// <see cref="ScrollViewer.ChangeView(double?, double?, float?, bool)"/> steps down then up, the path a wheel notch or
/// touchpad pan takes); two drag cycles then move it every frame without animation from the top to the bottom and back,
/// like dragging the scrollbar thumb, so layout, realization and per-scroll handlers run inside every frame on the UI
/// thread. A smooth scroll moves the offset one way every frame (<c>reversals</c> counts frames moving against it), keeps
/// frame intervals near the display's refresh (<c>over33</c> counts stalls of two 60 Hz frames or more), keeps each
/// frame's UI-thread work short (<c>work95</c>, <c>work33</c>, <c>work100</c>: from <see cref="CompositionTarget.Rendering"/>
/// to the thread's next idle moment, or at most to the next frame's Rendering (<see cref="FrameWorkMeter"/>), so software
/// rendering or DWM pacing on a hosted runner does not count) and leaves the
/// frames to rendering (<see cref="ScrollCost"/>: the UI-thread time of per-scroll handlers). Each notch restarts the
/// scroll animation's ease, so the wheel speed varies from frame to frame by design. A pass names a <c>hidden=</c> reason when the
/// window was covered, cloaked, locked or on a display that turned off during it: DWM then throttles frames to its
/// timer, so such a pass measures the desktop, not the app. The probe keeps the display on while it runs. Subscribing to
/// rendering keeps XAML drawing every frame, so never enable it outside perf runs.
/// </summary>
internal static class ScrollProbe
{
    private const int Notches = 14;
    private const double NotchEpx = 120;
    private const int WheelCycles = 3;
    private const int DragCycles = 2;
    private const double DragMaxSpanEpx = 12000;
    private static readonly TimeSpan NotchInterval = TimeSpan.FromMilliseconds(90);
    private static readonly TimeSpan DragDuration = TimeSpan.FromSeconds(1.5);
    private static readonly TimeSpan FindTimeout = TimeSpan.FromSeconds(60);
    private static readonly List<double> Intervals = new(1024);
    private static readonly List<double> Deltas = new(1024);
    private static readonly FrameWorkMeter Work = new();
    private static readonly List<string> Trace = [];
    // One cached handler: a new delegate per frame would marshal a new COM wrapper each time.
    private static readonly DispatcherQueueHandler WorkDone = OnWorkDone;
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
    private static string? hidden;
    private static Drag? drag;

    /// <summary>One drag pass: the offset moves linearly from <see cref="From"/> to <see cref="To"/> over <see cref="DragDuration"/>.</summary>
    /// <param name="From">Start offset.</param>
    /// <param name="To">End offset.</param>
    /// <param name="Started">Stopwatch timestamp of the first frame.</param>
    /// <param name="Done">Completed when the offset reaches <see cref="To"/>.</param>
    private sealed record Drag(double From, double To, long Started, TaskCompletionSource Done);

    /// <summary>Starts the probe after the page has loaded.</summary>
    /// <param name="root">Window content.</param>
    /// <param name="target"><c>page</c> (the window's largest scroller) or <c>dialog</c> (an open dialog's, once automation opens one).</param>
    public static void Start(FrameworkElement root, string target)
    {
        // Held in a field: an unreferenced one-shot timer can be collected before it fires.
        start = root.DispatcherQueue.CreateTimer();
        start.Interval = TimeSpan.FromSeconds(8);
        start.IsRepeating = false;
        start.Tick += async (_, _) =>
        {
            try
            {
                await RunAsync(root, target == "dialog");
            }
            catch (Exception error)
            {
                PerfLog.Write($"scroll-probe error {error.GetType().Name}: {error.Message}");
            }
        };
        start.Start();
    }

    /// <summary>Runs the wheel and drag cycles and logs each pass.</summary>
    /// <param name="root">Window content.</param>
    /// <param name="dialog">Probe an open dialog's scroller instead of the page's.</param>
    /// <returns>Probe task.</returns>
    private static async Task RunAsync(FrameworkElement root, bool dialog)
    {
        var waited = Stopwatch.StartNew();
        while ((viewer = dialog ? FindInDialogs(root) : FindMain(root, 200)) is null && waited.Elapsed < FindTimeout)
            await Task.Delay(500);
        if (viewer is null)
        {
            PerfLog.Write($"scroll-probe none scrollers={Inventory(root, dialog)}");
            return;
        }
        // Content that is still arriving (an incremental list, a dialog's fade-in) settles first.
        await Task.Delay(dialog ? 1500 : 0);
        PerfLog.Write($"scroll-probe target={Describe(viewer)} scrollable={viewer.ScrollableHeight:F1} anchor={viewer.VerticalAnchorRatio}");
        var occlusion = OcclusionTracker.Current;
        void OnOcclusion(object? sender, EventArgs e) => hidden ??= OcclusionTracker.Current?.IsHidden == true ? OcclusionTracker.Current.Reason : "changed";
        if (occlusion is not null) occlusion.Changed += OnOcclusion;
        Win32.SetThreadExecutionState(Win32.ExecutionContinuous | Win32.ExecutionDisplayRequired | Win32.ExecutionSystemRequired);
        ScrollCost.Enabled = true;
        viewer.LayoutUpdated += OnLayoutUpdated;
        CompositionTarget.Rendering += OnRendering;
        try
        {
            // A still pass first: what the probe's own frame tick and idle page work cost without scrolling.
            Begin(1);
            await Task.Delay(2000);
            Flush("rest");
            for (var cycle = 0; cycle < WheelCycles; cycle++)
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
            viewer.ChangeView(null, 0, null, true);
            await Task.Delay(500);
            for (var cycle = 0; cycle < DragCycles; cycle++)
            {
                foreach (var down in new[] { true, false })
                {
                    // From where the scroller rests: a list that re-estimated its extent at the end stays put, so the
                    // probe never jumps the offset itself.
                    var from = viewer.VerticalOffset;
                    var to = down ? Math.Min(viewer.ScrollableHeight, from + DragMaxSpanEpx) : Math.Max(0, from - DragMaxSpanEpx);
                    Begin(down ? 1 : -1);
                    var pass = new Drag(from, to, 0, new TaskCompletionSource());
                    drag = pass;
                    await pass.Done.Task;
                    await Task.Delay(400);
                    Flush(down ? "drag-down" : "drag-up");
                }
            }
        }
        finally
        {
            drag = null;
            CompositionTarget.Rendering -= OnRendering;
            viewer.LayoutUpdated -= OnLayoutUpdated;
            ScrollCost.Enabled = false;
            Win32.SetThreadExecutionState(Win32.ExecutionContinuous);
            if (occlusion is not null) occlusion.Changed -= OnOcclusion;
        }
        PerfLog.Write("scroll-probe done");
    }

    /// <summary>Counts the scroller's layout passes.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private static void OnLayoutUpdated(object? sender, object e) => layouts++;

    /// <summary>Resets the per-pass samples.</summary>
    /// <param name="dir">Scroll direction (+1 down, -1 up).</param>
    private static void Begin(int dir)
    {
        Intervals.Clear();
        Deltas.Clear();
        Work.Reset();
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
        hidden = OcclusionTracker.Current is { IsHidden: true } tracker ? tracker.Reason : null;
    }

    /// <summary>Samples one frame (interval, offset delta and extent change) and moves an active drag.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private static void OnRendering(object? sender, object e)
    {
        if (viewer is null) return;
        var now = Stopwatch.GetTimestamp();
        if (lastFrame is { } previous) Intervals.Add(Stopwatch.GetElapsedTime(previous, now).TotalMilliseconds);
        lastFrame = now;
        // The frame's layout and render walk run after this event in the same dispatch, so a low-priority item queued
        // now runs once the UI thread is idle again: the gap is the frame's UI-thread work, whatever DWM's pacing. A
        // marker still pending at this Rendering ends its sample here (FrameWorkMeter).
        var nowMs = Stopwatch.GetElapsedTime(0, now).TotalMilliseconds;
        if (Work.Frame(nowMs) && viewer.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, WorkDone)) Work.Marked(nowMs);
        var offset = viewer.VerticalOffset;
        var delta = offset - lastOffset;
        if (delta != 0 && Intervals.Count > 0) Deltas.Add(delta * direction);
        if (delta * direction < -0.01 && Trace.Count < 40) Trace.Add($"{Intervals.Count}:{lastOffset:F1}->{offset:F1}");
        lastOffset = offset;
        if (Math.Abs(viewer.ExtentHeight - lastExtent) > 0.01) extentChanges++;
        lastExtent = viewer.ExtentHeight;
        if (drag is { } pass)
        {
            if (pass.Started == 0) drag = pass = pass with { Started = now };
            var progress = Math.Min(1, Stopwatch.GetElapsedTime(pass.Started, now) / DragDuration);
            viewer.ChangeView(null, pass.From + (pass.To - pass.From) * progress, null, true);
            if (progress >= 1)
            {
                drag = null;
                pass.Done.TrySetResult();
            }
        }
    }

    /// <summary>
    /// Records one frame's UI-thread work: from its <see cref="CompositionTarget.Rendering"/> to the UI thread's next idle
    /// moment (layout, realization, render walk and per-scroll handlers), unless the next frame's Rendering already
    /// ended the sample at the frame interval (<see cref="FrameWorkMeter"/>; a frame that overruns counts for its whole
    /// length, since the next Rendering waits for it).
    /// </summary>
    private static void OnWorkDone() => Work.Idle(Stopwatch.GetElapsedTime(0, Stopwatch.GetTimestamp()).TotalMilliseconds);

    /// <summary>Writes one pass's statistics.</summary>
    /// <param name="label">Pass label.</param>
    private static void Flush(string label)
    {
        if (Intervals.Count == 0) return;
        var sorted = Intervals.Order().ToList();
        var moving = Deltas.Where(d => d > 0).Order().ToList();
        var median = moving.Count > 0 ? moving[moving.Count / 2] : 0;
        var reversals = Deltas.Count(d => d < -0.01);
        var foreground = MainWindow.Instance is { } window && Win32.GetForegroundWindow() == WinRT.Interop.WindowNative.GetWindowHandle(window);
        if (OcclusionTracker.Current is { IsHidden: true } tracker) hidden ??= tracker.Reason;
        double P(double q) => sorted[Math.Min(sorted.Count - 1, (int)(q * sorted.Count))];
        var work = Work.Samples.Order().ToList();
        double W(double q) => work.Count == 0 ? 0 : work[Math.Min(work.Count - 1, (int)(q * work.Count))];
        PerfLog.Write(
            $"scroll-probe {label} frames={sorted.Count} p50={P(0.5):F1} p95={P(0.95):F1} max={sorted[^1]:F1} over33={sorted.Count(i => i > 33.4)} " +
            $"moves={Deltas.Count} median={median:F2} reversals={reversals} worstBack={(reversals > 0 ? -Deltas.Min() : 0):F2} " +
            $"extentChanges={extentChanges} layouts={layouts} offset={viewer!.VerticalOffset:F2} hidden={hidden ?? "0"} fg={(foreground ? 1 : 0)} " +
            $"work50={W(0.5):F1} work95={W(0.95):F1} workMax={W(1):F1} work33={work.Count(w => w > 33.4)} work100={work.Count(w => w > 100)}");
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

    /// <summary>Finds the scroller of an open dialog (a <see cref="ContentDialog"/> or other modal popup).</summary>
    /// <param name="root">Window content (for its XAML root).</param>
    /// <returns>Scroller or <see langword="null"/> while no open popup has scrollable content.</returns>
    private static ScrollViewer? FindInDialogs(FrameworkElement root)
    {
        if (root.XamlRoot is null) return null;
        ScrollViewer? best = null;
        foreach (var popup in VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot))
        {
            if (popup.Child is not { } child) continue;
            var found = FindMain(child, 100);
            if (found is not null && (best is null || found.ViewportHeight * found.ViewportWidth > best.ViewportHeight * best.ViewportWidth))
                best = found;
        }
        return best;
    }

    /// <summary>
    /// Finds the visible scroller with the largest viewport, the innermost of equal ones (a SemanticZoom wraps its list's
    /// scroller in a zoom scroller of the same size that pins its content at the middle).
    /// </summary>
    /// <param name="root">Subtree to search.</param>
    /// <param name="minViewport">Smallest viewport height in epx that counts (skips chips and small inner lists).</param>
    /// <returns>Scroller or <see langword="null"/>.</returns>
    private static ScrollViewer? FindMain(DependencyObject root, double minViewport)
    {
        ScrollViewer? best = null;
        var bestArea = 0.0;
        var stack = new Stack<DependencyObject>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            var node = stack.Pop();
            if (node is UIElement { Visibility: Visibility.Collapsed }) continue;
            if (node is ScrollViewer sv && sv.ScrollableHeight > 0 && sv.ViewportHeight > minViewport
                && sv.ViewportHeight * sv.ViewportWidth >= bestArea - 1)
            {
                best = sv;
                bestArea = sv.ViewportHeight * sv.ViewportWidth;
            }
            for (var i = VisualTreeHelper.GetChildrenCount(node) - 1; i >= 0; i--) stack.Push(VisualTreeHelper.GetChild(node, i));
        }
        return best;
    }

    /// <summary>
    /// Lists the visible scrollers (name, viewport and scrollable height) when none qualifies, so a "none" result says
    /// whether the page fit its window, had not loaded or put its rows in an unexpected scroller.
    /// </summary>
    /// <param name="root">Window content.</param>
    /// <param name="dialog">Search open popups instead of the page.</param>
    /// <returns>Up to eight scrollers, or "-".</returns>
    private static string Inventory(FrameworkElement root, bool dialog)
    {
        var roots = new List<DependencyObject>();
        if (!dialog) roots.Add(root);
        else if (root.XamlRoot is not null)
            foreach (var popup in VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot))
                if (popup.Child is { } child) roots.Add(child);
        var found = new List<string>();
        var stack = new Stack<DependencyObject>(roots);
        while (stack.Count > 0 && found.Count < 8)
        {
            var node = stack.Pop();
            if (node is UIElement { Visibility: Visibility.Collapsed }) continue;
            if (node is ScrollViewer sv)
                found.Add($"{Describe(sv).Split(' ')[0]}/{sv.ViewportHeight:F0}+{sv.ScrollableHeight:F0}");
            for (var i = VisualTreeHelper.GetChildrenCount(node) - 1; i >= 0; i--) stack.Push(VisualTreeHelper.GetChild(node, i));
        }
        return found.Count == 0 ? "-" : string.Join(',', found);
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
            if (!string.IsNullOrEmpty(fe.Name) || fe is Page or ContentDialog) names.Add($"{fe.GetType().Name}:{fe.Name}");
            node = VisualTreeHelper.GetParent(fe);
        }
        return string.Join('<', names) + $" start={((ScrollViewer)element).VerticalOffset:F1}";
    }
}
#endregion