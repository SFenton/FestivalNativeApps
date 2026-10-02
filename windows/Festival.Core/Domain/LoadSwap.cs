using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.Domain;

#region Load swap
/// <summary>Phases in the web load gate (<c>useLoadPhase</c>): hidden loading, spinner fade, visible content and reload fade-out.</summary>
public enum LoadSwapPhase
{
    /// <summary>Only the centered spinner is shown at full opacity.</summary>
    Loading,
    /// <summary>Existing content is fading out before new data is presented.</summary>
    ContentOut,
    /// <summary>The spinner is fading out while the new content remains hidden.</summary>
    SpinnerOut,
    /// <summary>The current content is visible and may run its staggered entrance.</summary>
    ContentIn,
}

/// <summary>Timing constants for the web load gate.</summary>
public static class LoadSwapTiming
{
    /// <summary>Web <c>CONTENT_OUT_MS</c>: existing content fades out before a user-requested reload.</summary>
    public static readonly TimeSpan ContentOut = TimeSpan.FromMilliseconds(300);

    /// <summary>Web <c>SPINNER_FADE_MS</c>: the spinner fades away before new content is shown.</summary>
    public static readonly TimeSpan SpinnerOut = TimeSpan.FromMilliseconds(500);
}

/// <summary>
/// UI-free state machine for page and board reloads that mirror the web sequence: content out → spinner → spinner out →
/// content in. Callers begin a load, wait until old content is hidden, apply new state through <see cref="CommitAsync"/>,
/// then replay their row stagger when <see cref="ContentRevealed"/> fires. A revision check makes rapid re-selection
/// latest-wins: superseded commits are ignored and stale content never becomes visible.
/// </summary>
public sealed partial class LoadSwap : ObservableObject
{
    private readonly TimeProvider time;
    private int revision;

    /// <summary>Creates a load-swap gate.</summary>
    /// <param name="time">Time provider; tests use <c>FakeTimeProvider</c>.</param>
    /// <param name="initiallyVisible">Whether cached content is already visible (return/navigation-cache visit).</param>
    public LoadSwap(TimeProvider time, bool initiallyVisible = false)
    {
        this.time = time;
        phase = initiallyVisible ? LoadSwapPhase.ContentIn : LoadSwapPhase.Loading;
    }

    /// <summary>Raised after the current revision enters <see cref="LoadSwapPhase.ContentIn"/>.</summary>
    public event EventHandler? ContentRevealed;

    /// <summary>Current web load phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ContentVisible), nameof(ContentOpacity), nameof(ContentHitTestVisible))]
    [NotifyPropertyChangedFor(nameof(SpinnerVisible), nameof(SpinnerOpacity), nameof(IsLoading))]
    private LoadSwapPhase phase;

    /// <summary>Whether content should be in the visual tree.</summary>
    public bool ContentVisible => Phase is LoadSwapPhase.ContentIn or LoadSwapPhase.ContentOut;

    /// <summary>Content opacity requested from the view.</summary>
    public double ContentOpacity => Phase == LoadSwapPhase.ContentIn ? 1 : 0;

    /// <summary>Whether the visible content may receive input and accessibility focus.</summary>
    public bool ContentHitTestVisible => Phase == LoadSwapPhase.ContentIn;

    /// <summary>Whether the spinner should be in the visual tree.</summary>
    public bool SpinnerVisible => Phase is LoadSwapPhase.Loading or LoadSwapPhase.SpinnerOut;

    /// <summary>Spinner opacity requested from the view.</summary>
    public double SpinnerOpacity => Phase == LoadSwapPhase.Loading ? 1 : 0;

    /// <summary>Whether the screen reader should consider this surface loading.</summary>
    public bool IsLoading => SpinnerVisible;

    /// <summary>
    /// Starts a load. If content is currently visible and motion is allowed, waits for the 300 ms content-out phase
    /// before returning; otherwise switches to loading immediately. The returned revision must be passed to
    /// <see cref="CommitAsync"/>.
    /// </summary>
    /// <param name="animate">Whether motion is allowed right now.</param>
    /// <param name="hasContent">Whether existing content should fade out. Initial loads pass <see langword="false"/>.</param>
    /// <returns>The revision that owns the request.</returns>
    public async Task<int> BeginReloadAsync(bool animate, bool hasContent)
    {
        var request = Interlocked.Increment(ref revision);
        if (animate && hasContent && Phase == LoadSwapPhase.ContentIn)
        {
            Phase = LoadSwapPhase.ContentOut;
            await DelayAsync(LoadSwapTiming.ContentOut, request).ConfigureAwait(true);
        }
        if (IsCurrent(request)) Phase = LoadSwapPhase.Loading;
        return request;
    }

    /// <summary>
    /// Applies a request's new state while hidden, fades the spinner out for 500 ms when motion is allowed, then reveals
    /// content and raises <see cref="ContentRevealed"/>. Superseded revisions do nothing.
    /// </summary>
    /// <param name="request">Revision from <see cref="BeginReloadAsync"/>.</param>
    /// <param name="apply">State mutation that presents the new rows, empty state or failure.</param>
    /// <param name="animate">Whether motion is allowed right now.</param>
    /// <returns><see langword="true"/> when the commit won the revision race.</returns>
    public async Task<bool> CommitAsync(int request, Action apply, bool animate)
    {
        if (!IsCurrent(request)) return false;
        apply();
        if (!IsCurrent(request)) return false;
        if (animate)
        {
            Phase = LoadSwapPhase.SpinnerOut;
            await DelayAsync(LoadSwapTiming.SpinnerOut, request).ConfigureAwait(true);
            if (!IsCurrent(request)) return false;
        }
        Phase = LoadSwapPhase.ContentIn;
        ContentRevealed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    /// <summary>Switches to visible content immediately (cached first visit or reduced-motion path).</summary>
    /// <param name="apply">State mutation to apply before reveal.</param>
    public void ShowImmediately(Action apply)
    {
        Interlocked.Increment(ref revision);
        apply();
        Phase = LoadSwapPhase.ContentIn;
        ContentRevealed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Invalidates any in-flight waits and returns to the spinner.</summary>
    public void CancelToLoading()
    {
        Interlocked.Increment(ref revision);
        Phase = LoadSwapPhase.Loading;
    }

    /// <summary>Waits for a phase duration unless a newer revision takes over.</summary>
    /// <param name="duration">Duration.</param>
    /// <param name="request">Owning revision.</param>
    private async Task DelayAsync(TimeSpan duration, int request)
    {
        if (duration <= TimeSpan.Zero) return;
        try
        {
            await Task.Delay(duration, time).ConfigureAwait(true);
        }
        catch (OperationCanceledException)
        {
            // FakeTimeProvider tests cancel timers by invalidating the revision instead of a token.
        }
        if (!IsCurrent(request)) return;
    }

    /// <summary>Whether a request still owns the visible sequence.</summary>
    /// <param name="request">Revision.</param>
    /// <returns><see langword="true"/> if current.</returns>
    private bool IsCurrent(int request) => Volatile.Read(ref revision) == request;
}
#endregion
