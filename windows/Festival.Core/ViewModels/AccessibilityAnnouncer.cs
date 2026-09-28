using System.ComponentModel;

namespace Festival.Core.ViewModels;

#region Announcement
/// <summary>What an announcement reports (maps to a UIA notification kind and activity ID).</summary>
public enum AnnouncementKind
{
    /// <summary>A slow read started ("Loading songs").</summary>
    Progress,
    /// <summary>Content arrived or changed ("245 songs").</summary>
    Completed,
    /// <summary>A read failed (service-status heading and message).</summary>
    Error,
}

/// <summary>One screen-reader announcement.</summary>
/// <param name="Text">Spoken text.</param>
/// <param name="Kind">Kind.</param>
public readonly record struct Announcement(string Text, AnnouncementKind Kind)
{
    /// <summary>Stable UIA notification activity ID for the kind (later announcements of one kind replace earlier ones).</summary>
    public string ActivityId => Kind switch
    {
        AnnouncementKind.Progress => "fst.a11y.loading",
        AnnouncementKind.Error => "fst.a11y.error",
        _ => "fst.a11y.results",
    };

    /// <summary>Announcement for a failed read: heading plus message.</summary>
    /// <param name="title">Service-status heading.</param>
    /// <param name="message">Service-status message (may be empty).</param>
    /// <returns>Error announcement.</returns>
    public static Announcement Failure(string title, string message) =>
        new(string.IsNullOrWhiteSpace(message) ? title : $"{title}. {message}", AnnouncementKind.Error);
}
#endregion

#region Load announcer
/// <summary>
/// Turns a view model's loading state into Narrator announcements, because a visual spinner or a silently
/// replaced list is invisible to a screen reader (a UIA live region alone does not speak in WinUI).
/// <list type="bullet">
/// <item>A read that is still loading after <c>loadingDelay</c> announces <c>loadingText</c> once (fast reads stay silent).</item>
/// <item>When loading ends, or the summary changes while idle (search, filters, paging), the new summary is announced
/// after <c>settleDelay</c> without further changes, so typing a query speaks only the final count.</item>
/// <item>Content already present when the announcer attaches is not re-announced (navigation reads the page title).</item>
/// </list>
/// Failures are announced by the shared service-status view, not here.
/// </summary>
public sealed class LoadAnnouncer : IDisposable
{
    private readonly INotifyPropertyChanged[] sources;
    private readonly Func<bool> isLoading;
    private readonly Func<string?> summary;
    private readonly string? loadingText;
    private readonly TimeProvider time;
    private readonly TimeSpan loadingDelay;
    private readonly TimeSpan settleDelay;
    private readonly Action<Action> dispatch;
    private ITimer? loadingTimer;
    private ITimer? settleTimer;
    private bool wasLoading;
    private string? lastSummary;
    private bool disposed;

    /// <summary>Creates the announcer and captures the current state as already announced.</summary>
    /// <param name="sources">View models whose property changes can affect <paramref name="isLoading"/> or <paramref name="summary"/>.</param>
    /// <param name="isLoading">Whether a read is in flight with nothing to show yet.</param>
    /// <param name="summary">Result summary to speak (e.g. "245 songs"), or <see langword="null"/> when there is nothing to report.</param>
    /// <param name="loadingText">Text for a slow read (e.g. "Loading songs"), or <see langword="null"/> for none.</param>
    /// <param name="time">Clock for the delays.</param>
    /// <param name="loadingDelay">How long a read must run before <paramref name="loadingText"/> is spoken (default 1 s).</param>
    /// <param name="settleDelay">Quiet period before a summary is spoken (default 600 ms).</param>
    /// <param name="dispatch">Runs timer callbacks on the view models' thread (the App passes its dispatcher queue); default runs inline.</param>
    public LoadAnnouncer(IEnumerable<INotifyPropertyChanged> sources, Func<bool> isLoading, Func<string?> summary, string? loadingText,
        TimeProvider time, TimeSpan? loadingDelay = null, TimeSpan? settleDelay = null, Action<Action>? dispatch = null)
    {
        this.dispatch = dispatch ?? (action => action());
        this.sources = [.. sources];
        this.isLoading = isLoading;
        this.summary = summary;
        this.loadingText = loadingText;
        this.time = time;
        this.loadingDelay = loadingDelay ?? TimeSpan.FromSeconds(1);
        this.settleDelay = settleDelay ?? TimeSpan.FromMilliseconds(600);
        wasLoading = isLoading();
        lastSummary = wasLoading ? null : summary();
        if (wasLoading) StartLoadingTimer();
        foreach (var source in this.sources) source.PropertyChanged += OnSourceChanged;
    }

    /// <summary>Raised on the caller's thread or, for delayed announcements, through <c>dispatch</c>.</summary>
    public event EventHandler<Announcement>? Announced;

    /// <summary>Re-evaluates the state (also called for every source property change).</summary>
    public void Evaluate()
    {
        if (disposed) return;
        var loading = isLoading();
        if (loading && !wasLoading)
        {
            StartLoadingTimer();
        }
        else if (!loading)
        {
            CancelTimer(ref loadingTimer);
            var current = summary();
            if (!string.IsNullOrWhiteSpace(current) && current != lastSummary)
            {
                CancelTimer(ref settleTimer);
                settleTimer = time.CreateTimer(_ => dispatch(AnnounceSummary), null, settleDelay, Timeout.InfiniteTimeSpan);
            }
        }
        wasLoading = loading;
    }

    /// <summary>Stops listening and cancels pending announcements.</summary>
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        foreach (var source in sources) source.PropertyChanged -= OnSourceChanged;
        CancelTimer(ref loadingTimer);
        CancelTimer(ref settleTimer);
    }

    private void OnSourceChanged(object? sender, PropertyChangedEventArgs e) => Evaluate();

    private void StartLoadingTimer()
    {
        if (loadingText is null) return;
        CancelTimer(ref loadingTimer);
        loadingTimer = time.CreateTimer(_ => dispatch(() =>
        {
            if (!disposed && isLoading()) Announced?.Invoke(this, new Announcement(loadingText, AnnouncementKind.Progress));
        }), null, loadingDelay, Timeout.InfiniteTimeSpan);
    }

    private void AnnounceSummary()
    {
        if (disposed || isLoading()) return;
        var current = summary();
        if (string.IsNullOrWhiteSpace(current) || current == lastSummary) return;
        lastSummary = current;
        Announced?.Invoke(this, new Announcement(current, AnnouncementKind.Completed));
    }

    private static void CancelTimer(ref ITimer? timer)
    {
        timer?.Dispose();
        timer = null;
    }
}
#endregion
