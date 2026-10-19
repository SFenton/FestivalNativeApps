namespace Festival.Core.Domain;

#region Frame work meter
/// <summary>
/// The scroll probe's per-frame UI-thread work samples (<c>work95</c>, <c>work33</c>, <c>work100</c>; issues #668, #676).
/// A frame's work runs from its <c>CompositionTarget.Rendering</c> to the UI thread's next idle moment, which a
/// low-priority dispatcher item marks. One marker is pending at a time. The next frame's Rendering runs on the same
/// thread, so it can only start once the previous frame's layout and render walk are done: a marker still pending then
/// has been held back by other dispatcher work, not by the frame, and the sample ends there, at the frame interval.
/// Frames that pass while that marker stays pending add no sample. Without the cap, a scrollbar drag that kept the
/// thread busy between on-time frames for a whole pass (frames at most 95 ms apart) logged one 1.1 s "frame" (#676).
/// </summary>
public sealed class FrameWorkMeter
{
    private double? start;
    private bool ended;

    /// <summary>The pass's work samples in milliseconds, one per marked frame.</summary>
    public List<double> Samples { get; } = new(1024);

    /// <summary>Starts a new pass: clears the samples and forgets a pending marker.</summary>
    public void Reset()
    {
        Samples.Clear();
        start = null;
        ended = false;
    }

    /// <summary>
    /// Handles a frame's Rendering: ends a sample whose marker is still pending at the frame interval, and says whether
    /// the caller should queue a marker for this frame.
    /// </summary>
    /// <param name="nowMs">This Rendering's time in milliseconds.</param>
    /// <returns><see langword="true"/> when no marker is pending, so this frame starts a sample once one is queued.</returns>
    public bool Frame(double nowMs)
    {
        if (start is not { } began) return true;
        if (!ended)
        {
            Samples.Add(nowMs - began);
            ended = true;
        }
        return false;
    }

    /// <summary>Starts a sample for a frame whose marker the caller queued.</summary>
    /// <param name="nowMs">The frame's Rendering time in milliseconds.</param>
    public void Marked(double nowMs)
    {
        start = nowMs;
        ended = false;
    }

    /// <summary>Handles the marker running (the UI thread is idle): ends the sample unless a later frame already did.</summary>
    /// <param name="nowMs">The marker's time in milliseconds.</param>
    public void Idle(double nowMs)
    {
        if (start is not { } began) return;
        if (!ended) Samples.Add(nowMs - began);
        start = null;
        ended = false;
    }
}
#endregion
