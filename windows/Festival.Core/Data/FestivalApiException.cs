namespace Festival.Core.Data;

#region Error kinds
/// <summary>Distinct transport, safety and consistency failures from the service client.</summary>
public enum FestivalApiErrorKind
{
    /// <summary>The base URL is neither HTTPS nor loopback HTTP.</summary>
    InsecureBaseUrl,
    /// <summary>The request was not a plain GET or carried a forbidden header.</summary>
    ForbiddenRequest,
    /// <summary>A path segment or paging argument was unsafe or out of range.</summary>
    InvalidResource,
    /// <summary>The body could not be decoded or failed validation.</summary>
    InvalidResponse,
    /// <summary>Publication consistency could not be verified.</summary>
    InvalidPublication,
    /// <summary>An unmapped HTTP status.</summary>
    HttpStatus,
    /// <summary>HTTP 503 without a freeze reason.</summary>
    Unavailable,
    /// <summary>HTTP 503 carrying <c>X-FST-Public-Read-Freeze-Reason</c>.</summary>
    PublicReadFrozen,
    /// <summary>HTTP 202 from an endpoint without a syncing envelope.</summary>
    Syncing,
    /// <summary>A 304 without a usable cached body.</summary>
    UnexpectedNotModified,
    /// <summary>The 30-second request deadline elapsed.</summary>
    Timeout,
    /// <summary>The device could not reach the service.</summary>
    Offline,
}
#endregion

#region Exception
/// <summary>A service-client failure that the UI converts with <see cref="ServiceIssue.From(Exception)"/>.</summary>
public sealed class FestivalApiException : Exception
{
    /// <summary>Creates a typed failure.</summary>
    /// <param name="kind">Failure category.</param>
    /// <param name="statusCode">HTTP status, when one was received.</param>
    /// <param name="retryAfter">Raw <c>Retry-After</c> header value.</param>
    /// <param name="freezeReason">Raw freeze reason header value.</param>
    /// <param name="inner">Underlying transport exception.</param>
    public FestivalApiException(
        FestivalApiErrorKind kind, int? statusCode = null, string? retryAfter = null,
        string? freezeReason = null, Exception? inner = null)
        : base(Describe(kind, statusCode), inner)
    {
        Kind = kind;
        StatusCode = statusCode;
        RetryAfter = retryAfter;
        FreezeReason = freezeReason;
    }

    /// <summary>Failure category.</summary>
    public FestivalApiErrorKind Kind { get; }

    /// <summary>HTTP status, when one was received.</summary>
    public int? StatusCode { get; }

    /// <summary>Raw <c>Retry-After</c> value.</summary>
    public string? RetryAfter { get; }

    /// <summary>Raw <c>X-FST-Public-Read-Freeze-Reason</c> value.</summary>
    public string? FreezeReason { get; }

    /// <summary>Readable text that never echoes server content.</summary>
    /// <param name="kind">Failure category.</param>
    /// <param name="status">HTTP status, if any.</param>
    /// <returns>User-facing message.</returns>
    internal static string Describe(FestivalApiErrorKind kind, int? status) => kind switch
    {
        FestivalApiErrorKind.InsecureBaseUrl => "A secure service connection is required.",
        FestivalApiErrorKind.ForbiddenRequest => "The app blocked an unsafe request.",
        FestivalApiErrorKind.InvalidResource => "That song or chart is unavailable.",
        FestivalApiErrorKind.InvalidResponse => "The service returned data we could not read. Try again.",
        FestivalApiErrorKind.InvalidPublication => "The current scores could not be verified. Try again.",
        FestivalApiErrorKind.Unavailable or FestivalApiErrorKind.PublicReadFrozen =>
            "The service is temporarily unavailable. Try again.",
        FestivalApiErrorKind.Syncing => "This data is still syncing. Try again shortly.",
        FestivalApiErrorKind.UnexpectedNotModified => "The service returned an incomplete update. Try again.",
        FestivalApiErrorKind.Timeout => "The service took too long to respond. Try again.",
        FestivalApiErrorKind.Offline => "Check your connection and try again.",
        _ => status switch
        {
            404 => "That song or chart is no longer available.",
            429 => "Too many requests. Try again shortly.",
            >= 500 and <= 599 => "The service is temporarily unavailable. Try again.",
            _ => $"The service could not load this content (HTTP {status}).",
        },
    };
}
#endregion
