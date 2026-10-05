using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Load state
/// <summary>Lifecycle of one screen or section read.</summary>
public enum LoadState
{
    /// <summary>Not started.</summary>
    Idle,
    /// <summary>Request in flight with nothing to show yet.</summary>
    Loading,
    /// <summary>Content available.</summary>
    Loaded,
    /// <summary>Loaded but nothing matches.</summary>
    Empty,
    /// <summary>Failed; see the status view model.</summary>
    Failed,
}
#endregion

#region Service status
/// <summary>
/// Shared failed-read presentation: heading, message, Retry and — for a scrape freeze only — an automatic
/// countdown with capped backoff (service-status control).
/// </summary>
public sealed partial class ServiceStatusViewModel : ObservableObject
{
    private readonly TimeProvider time;
    private readonly ServiceRetryBackoff backoff;
    private readonly string scope;
    private readonly Func<Task> retry;
    private CancellationTokenSource? countdown;

    /// <summary>Creates the status for one scope.</summary>
    /// <param name="scope">Stable scope for backoff history.</param>
    /// <param name="fallbackTitle">Screen title used when the issue has none (e.g. "Songs unavailable").</param>
    /// <param name="retry">Reload action.</param>
    /// <param name="time">Clock.</param>
    /// <param name="backoff">Backoff shared by the screen.</param>
    public ServiceStatusViewModel(string scope, string fallbackTitle, Func<Task> retry, TimeProvider time, ServiceRetryBackoff? backoff = null)
    {
        this.scope = scope;
        FallbackTitle = fallbackTitle;
        this.retry = retry;
        this.time = time;
        this.backoff = backoff ?? new ServiceRetryBackoff();
    }

    /// <summary>Title used when the issue has no heading of its own.</summary>
    public string FallbackTitle { get; }

    /// <summary>Current issue, or <see langword="null"/> when healthy.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(Message), nameof(RetryLabel), nameof(HasIssue))]
    private ServiceIssue? issue;

    /// <summary>Seconds left before an automatic retry, or 0.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CountdownText), nameof(CountdownAnnouncement), nameof(HasCountdown))]
    private int secondsRemaining;

    /// <summary>Whether an automatic-retry countdown is running (the countdown line is shown only then).</summary>
    public bool HasCountdown => SecondsRemaining > 0;

    /// <summary>Whether an issue is shown.</summary>
    public bool HasIssue => Issue is not null;

    /// <summary>Heading.</summary>
    public string Title => Issue?.Title ?? FallbackTitle;

    /// <summary>Body.</summary>
    public string Message => Issue?.Message ?? "";

    /// <summary>Retry button label.</summary>
    public string RetryLabel => Issue?.RetryLabel ?? "Retry";

    /// <summary><c>m:ss</c> countdown, or empty.</summary>
    public string CountdownText => SecondsRemaining > 0
        ? string.Create(CultureInfo.InvariantCulture, $"{SecondsRemaining / 60}:{SecondsRemaining % 60:00}") : "";

    /// <summary>Spoken countdown label.</summary>
    public string CountdownAnnouncement => SecondsRemaining > 0
        ? $"Trying again automatically in {SecondsRemaining} seconds" : "";

    /// <summary>Shows a failure; starts the countdown for a scrape freeze.</summary>
    /// <param name="error">Thrown exception.</param>
    public void Report(Exception error) => Report(ServiceIssue.From(error));

    /// <summary>Shows an already-classified failure; starts the countdown for a scrape freeze.</summary>
    /// <param name="issue">Issue.</param>
    public void Report(ServiceIssue issue)
    {
        CancelCountdown();
        Issue = issue;
        if (Issue.RetriesAutomatically)
        {
            var delay = backoff.NextDelay(scope, Issue.RetryAfter, time.GetUtcNow());
            countdown = new CancellationTokenSource();
            _ = RunCountdownAsync(delay, countdown.Token);
        }
    }

    /// <summary>Clears the issue after a successful load.</summary>
    public void Clear()
    {
        CancelCountdown();
        backoff.Reset(scope);
        Issue = null;
    }

    /// <summary>Retries now (button).</summary>
    /// <returns>The reload task.</returns>
    [RelayCommand]
    private Task RetryAsync()
    {
        CancelCountdown();
        return retry();
    }

    /// <summary>Ticks once per second and retries at zero.</summary>
    /// <param name="seconds">Initial delay.</param>
    /// <param name="token">Cancellation when cleared or retried manually.</param>
    /// <returns>Countdown task.</returns>
    private async Task RunCountdownAsync(int seconds, CancellationToken token)
    {
        try
        {
            for (SecondsRemaining = seconds; SecondsRemaining > 0; SecondsRemaining--)
                await Task.Delay(TimeSpan.FromSeconds(1), time, token);
            await retry();
        }
        catch (OperationCanceledException)
        {
            // Cleared or retried manually.
        }
    }

    /// <summary>Stops any pending countdown.</summary>
    private void CancelCountdown()
    {
        countdown?.Cancel();
        countdown?.Dispose();
        countdown = null;
        SecondsRemaining = 0;
    }
}
#endregion
