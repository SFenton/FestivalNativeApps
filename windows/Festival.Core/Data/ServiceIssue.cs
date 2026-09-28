using System.Globalization;

namespace Festival.Core.Data;

#region Freeze reason
/// <summary>The service's <c>X-FST-Public-Read-Freeze-Reason</c> vocabulary (see service-safety.md).</summary>
public static class ServiceFreezeReason
{
    /// <summary>Response header naming why public reads are frozen.</summary>
    public const string Header = "X-FST-Public-Read-Freeze-Reason";

    /// <summary>Reasons belonging to the normal scrape → publish lifecycle.</summary>
    public static IReadOnlySet<string> ScoreUpdateReasons { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "scrape", "post-process", "publish", "publication-commit", "publication-commit-deferred",
    };

    /// <summary>Whether a reason means "scores are updating" rather than an outage.</summary>
    /// <param name="reason">Raw header value in any capitalization.</param>
    /// <returns><see langword="true"/> for a scrape-lifecycle reason.</returns>
    public static bool IsScoreUpdate(string? reason) =>
        reason is not null && ScoreUpdateReasons.Contains(reason.Trim().ToLowerInvariant());
}
#endregion

#region Service issue
/// <summary>User-facing categories for a failed public read.</summary>
public enum ServiceIssueKind
{
    /// <summary>Public reads are frozen while new scores publish; retries automatically.</summary>
    ScrapeInProgress,
    /// <summary>503 for another reason.</summary>
    Unavailable,
    /// <summary>202: data still being prepared.</summary>
    Syncing,
    /// <summary>404.</summary>
    NotFound,
    /// <summary>The device could not reach the service. Online-only: never implies cached data.</summary>
    Offline,
    /// <summary>Anything else, with a readable message.</summary>
    Other,
}

/// <summary>The one vocabulary every screen uses to render a failed read (service-status control).</summary>
/// <param name="Kind">Issue category.</param>
/// <param name="RetryAfter">Server-suggested wait in seconds.</param>
/// <param name="Detail">Readable message for <see cref="ServiceIssueKind.Other"/>.</param>
public sealed record ServiceIssue(ServiceIssueKind Kind, int? RetryAfter = null, string? Detail = null)
{
    /// <summary>Classifies any exception thrown by the service client or its transport.</summary>
    /// <param name="error">Thrown exception.</param>
    /// <returns>The matching issue.</returns>
    public static ServiceIssue From(Exception error) => error switch
    {
        FestivalApiException { Kind: FestivalApiErrorKind.PublicReadFrozen } e =>
            ServiceFreezeReason.IsScoreUpdate(e.FreezeReason)
                ? new(ServiceIssueKind.ScrapeInProgress, RetryAfterSeconds(e.RetryAfter))
                : new(ServiceIssueKind.Unavailable, RetryAfterSeconds(e.RetryAfter)),
        FestivalApiException { Kind: FestivalApiErrorKind.Unavailable } e =>
            new(ServiceIssueKind.Unavailable, RetryAfterSeconds(e.RetryAfter)),
        FestivalApiException { Kind: FestivalApiErrorKind.Syncing } => new(ServiceIssueKind.Syncing),
        FestivalApiException { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 } => new(ServiceIssueKind.NotFound),
        FestivalApiException { Kind: FestivalApiErrorKind.Offline or FestivalApiErrorKind.Timeout } =>
            new(ServiceIssueKind.Offline),
        _ => new(ServiceIssueKind.Other, null, error is FestivalApiException ? error.Message : "Something went wrong. Try again."),
    };

    /// <summary>Parses a delta-seconds <c>Retry-After</c>; HTTP-date forms are ignored.</summary>
    /// <param name="value">Raw header value.</param>
    /// <returns>Seconds in 1…86,400, or <see langword="null"/>.</returns>
    public static int? RetryAfterSeconds(string? value) =>
        int.TryParse(value?.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var seconds) &&
        seconds is >= 1 and <= 86_400 ? seconds : null;

    /// <summary>Whether the UI should count down and retry on its own (scrape freeze only).</summary>
    public bool RetriesAutomatically => Kind == ServiceIssueKind.ScrapeInProgress;

    /// <summary>Heading, or <see langword="null"/> to use the screen's own "… unavailable" title.</summary>
    public string? Title => Kind switch
    {
        ServiceIssueKind.ScrapeInProgress => "Scores are updating",
        ServiceIssueKind.Offline => "You're offline",
        ServiceIssueKind.Syncing => "Still syncing",
        _ => null,
    };

    /// <summary>Body text.</summary>
    public string Message => Kind switch
    {
        ServiceIssueKind.ScrapeInProgress => "New scores are being published. This page will try again automatically.",
        ServiceIssueKind.Unavailable => RetryAfter is { } s
            ? $"The service is temporarily unavailable. Try again in {s} seconds."
            : "The service is temporarily unavailable. Try again.",
        ServiceIssueKind.Syncing => "This data is still being prepared. Try again shortly.",
        ServiceIssueKind.NotFound => "This content is no longer available.",
        ServiceIssueKind.Offline => "Check your connection and try again.",
        _ => Detail ?? "Something went wrong. Try again.",
    };

    /// <summary>Label for the retry button.</summary>
    public string RetryLabel => RetriesAutomatically ? "Retry Now" : "Retry";
}
#endregion

#region Retry backoff
/// <summary>Consecutive automatic-retry delays per scope: honours <c>Retry-After</c>, doubles to a 300 s cap.</summary>
public sealed class ServiceRetryBackoff
{
    /// <summary>Delay used when the service sent no usable <c>Retry-After</c>.</summary>
    public const int DefaultDelay = 30;
    /// <summary>Longest automatic wait.</summary>
    public const int Cap = 300;
    /// <summary>Seconds after a countdown during which a failure still counts as consecutive.</summary>
    public static readonly TimeSpan Grace = TimeSpan.FromSeconds(20);

    private readonly Dictionary<string, (int Count, int Delay, DateTimeOffset At)> attempts = [];

    /// <summary>Records a failure and returns the wait before the next automatic retry.</summary>
    /// <param name="scope">Stable screen or request identifier.</param>
    /// <param name="retryAfter">Server-suggested delay in seconds.</param>
    /// <param name="now">Failure time.</param>
    /// <returns>Seconds to wait, 1…<see cref="Cap"/>.</returns>
    public int NextDelay(string scope, int? retryAfter, DateTimeOffset now)
    {
        var baseDelay = Math.Min(Cap, Math.Max(1, retryAfter ?? DefaultDelay));
        var count = 0;
        if (attempts.TryGetValue(scope, out var previous) &&
            now - previous.At <= TimeSpan.FromSeconds(previous.Delay) + Grace)
            count = previous.Count + 1;
        var delay = (int)Math.Min(Cap, (long)baseDelay << Math.Min(count, 8));
        attempts[scope] = (count, delay, now);
        return delay;
    }

    /// <summary>Forgets a scope after it loads successfully.</summary>
    /// <param name="scope">Identifier passed to <see cref="NextDelay"/>.</param>
    public void Reset(string scope) => attempts.Remove(scope);
}
#endregion
