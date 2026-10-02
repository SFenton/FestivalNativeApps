using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Festival.Core.Data;

#region Feedback
/// <summary>
/// In-app feedback (issue #78). <c>GET /api/features</c> decides whether Settings shows the two rows; one
/// user-initiated multipart <c>POST /api/feedback</c> per Submit answers 202 <c>{id, status}</c>; then
/// <c>GET /api/feedback/{id}</c> reports filing progress from service memory. None carries a key, profile or
/// publication header, and automation never POSTs to production (<c>.agents/platforms/service-safety.md</c>,
/// <c>.agents/controls/feedback-form/spec.md</c>).
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Reads whether the service accepts feedback (<c>feedback: true</c>); a pure, unpinned read.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns><see langword="true"/> only when the body's <c>feedback</c> is JSON <c>true</c>.</returns>
    /// <exception cref="FestivalApiException">Transport or status failure (callers keep the rows hidden).</exception>
    public async Task<bool> GetFeedbackEnabledAsync(CancellationToken cancellationToken = default)
    {
        using var request = RequestGate.CreateGet(ServiceEndpoints.Build(BaseUri, ["api", "features"]));
        var response = await gate.SendAsync(request, 16_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        return ParseFeedbackEnabled(response.Body);
    }

    /// <summary>Sends a report or request with its media.</summary>
    /// <param name="submission">Form contents from <see cref="FeedbackDraft.Submission"/>.</param>
    /// <param name="openAttachment">Opens a picked attachment for reading (caller-owned file access).</param>
    /// <param name="cancellationToken">Cancellation (the user discarded the form).</param>
    /// <returns>The accepted job (normally <see cref="FeedbackJobState.Queued"/> with an ID to poll).</returns>
    /// <exception cref="FeedbackException">Readable failure: unreadable attachment, offline, timeout or HTTP status.</exception>
    /// <exception cref="OperationCanceledException">The caller cancelled.</exception>
    public async Task<FeedbackJob> SubmitFeedbackAsync(
        FeedbackSubmission submission,
        Func<FeedbackAttachment, Stream> openAttachment,
        CancellationToken cancellationToken = default)
    {
        using var form = BuildFeedbackForm(submission, openAttachment);
        using var request = RequestGate.CreateFeedbackPost(ServiceEndpoints.Build(BaseUri, ["api", "feedback"]), form);
        GateResponse response;
        try
        {
            response = await gate.SendFeedbackAsync(request, cancellationToken).ConfigureAwait(false);
        }
        catch (FestivalApiException error)
        {
            throw error.Kind switch
            {
                FestivalApiErrorKind.Offline => FeedbackException.Offline(error),
                FestivalApiErrorKind.Timeout => FeedbackException.TimedOut(error),
                _ => new FeedbackException(error.Message, error.StatusCode, error),
            };
        }
        if (response.Status is < 200 or > 299)
            throw FeedbackException.ForStatus(response.Status, ParseFeedbackErrorCode(response.Body), RetryAfterSeconds(response));
        return ParseFeedbackJob(response.Body, null) ?? new FeedbackJob(null, FeedbackJobState.Queued);
    }

    /// <summary>Reads an accepted job's progress (in-memory on the service; lost after 60 minutes or a restart).</summary>
    /// <param name="id">Job ID from <see cref="SubmitFeedbackAsync"/>.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Latest state.</returns>
    /// <exception cref="ArgumentException">The ID is not 32 lowercase hex characters.</exception>
    /// <exception cref="FestivalApiException">Transport, status (404 = unknown or expired) or an unreadable body.</exception>
    public async Task<FeedbackJob> GetFeedbackStatusAsync(string id, CancellationToken cancellationToken = default)
    {
        if (!FeedbackJob.IsValidId(id)) throw new ArgumentException("Not a feedback job ID.", nameof(id));
        using var request = RequestGate.CreateGet(ServiceEndpoints.Build(BaseUri, ["api", "feedback", id]));
        var response = await gate.SendAsync(request, 256_000, cancellationToken).ConfigureAwait(false);
        RequestGate.MapStatus(response, acceptsSyncing: false);
        return ParseFeedbackJob(response.Body, id) ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse, response.Status);
    }

    /// <summary>Builds the multipart body: text fields in wire order, then one <c>media</c> file part per attachment.</summary>
    /// <param name="submission">Submission.</param>
    /// <param name="openAttachment">Opens an attachment.</param>
    /// <returns>Form content owning every opened stream.</returns>
    /// <exception cref="FeedbackException">An attachment could not be opened.</exception>
    internal static MultipartFormDataContent BuildFeedbackForm(
        FeedbackSubmission submission, Func<FeedbackAttachment, Stream> openAttachment)
    {
        var form = new MultipartFormDataContent();
        try
        {
            foreach (var (name, value) in submission.FormFields) form.Add(new StringContent(value), name);
            foreach (var attachment in submission.Attachments)
            {
                Stream stream;
                try
                {
                    stream = openAttachment(attachment);
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException
                                                  or NotSupportedException or System.Security.SecurityException)
                {
                    throw FeedbackException.Unreadable(attachment.Name, error);
                }
                var part = new StreamContent(stream);
                part.Headers.ContentType = MediaTypeHeaderValue.TryParse(attachment.MimeType, out var type) && type.MediaType is { } media &&
                                           (media.StartsWith("image/", StringComparison.OrdinalIgnoreCase) ||
                                            media.StartsWith("video/", StringComparison.OrdinalIgnoreCase))
                    ? new MediaTypeHeaderValue(media)
                    : new MediaTypeHeaderValue("application/octet-stream");
                form.Add(part, FeedbackSubmission.MediaPart, FeedbackSubmission.SafeFileName(attachment.Name));
            }
            return form;
        }
        catch
        {
            form.Dispose();
            throw;
        }
    }

    /// <summary>Reads the <c>feedback</c> flag; anything but JSON <c>true</c> (missing on older services) is off.</summary>
    /// <param name="body">Response bytes.</param>
    /// <returns>Whether the rows show.</returns>
    internal static bool ParseFeedbackEnabled(byte[] body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("feedback", out var flag) && flag.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>
    /// Reads a job body (<c>{id, status, issueNumber?, attachments[{outcome}]}</c>). A malformed ID falls back to
    /// <paramref name="knownId"/>; an unknown status reads as <see cref="FeedbackJobState.Processing"/> so polling continues.
    /// </summary>
    /// <param name="body">Response bytes.</param>
    /// <param name="knownId">ID already held (status reads), or <see langword="null"/> (the 202 answer).</param>
    /// <returns>Job, or <see langword="null"/> when the body is not a JSON object.</returns>
    internal static FeedbackJob? ParseFeedbackJob(byte[] body, string? knownId)
    {
        if (body.Length == 0) return null;
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var wireId = root.TryGetProperty("id", out var i) && i.ValueKind == JsonValueKind.String ? i.GetString() : null;
            var id = FeedbackJob.IsValidId(wireId) ? wireId : knownId;
            var state = root.TryGetProperty("status", out var s) && s.ValueKind == JsonValueKind.String
                ? FeedbackJob.ParseState(s.GetString()) ?? FeedbackJobState.Processing
                : FeedbackJobState.Processing;
            int? number = root.TryGetProperty("issueNumber", out var n) && n.ValueKind == JsonValueKind.Number &&
                          n.TryGetInt32(out var value) && value > 0
                ? value
                : null;
            var skipped = root.TryGetProperty("attachments", out var a) && a.ValueKind == JsonValueKind.Array
                ? a.EnumerateArray().Count(item => item.ValueKind == JsonValueKind.Object &&
                                                   item.TryGetProperty("outcome", out var o) && o.ValueKind == JsonValueKind.String &&
                                                   string.Equals(o.GetString(), "skipped", StringComparison.OrdinalIgnoreCase))
                : 0;
            return new FeedbackJob(id, state, number, skipped);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Reads the <c>code</c> of an <c>{error, code}</c> body.</summary>
    /// <param name="body">Response bytes.</param>
    /// <returns>Code, or <see langword="null"/>.</returns>
    internal static string? ParseFeedbackErrorCode(byte[] body)
    {
        if (body.Length == 0) return null;
        try
        {
            using var document = JsonDocument.Parse(body);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("code", out var code) && code.ValueKind == JsonValueKind.String
                ? code.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Parses a delta-seconds <c>Retry-After</c>.</summary>
    /// <param name="response">Response.</param>
    /// <returns>Positive seconds, or <see langword="null"/>.</returns>
    internal static int? RetryAfterSeconds(GateResponse response) =>
        int.TryParse(response.Header("Retry-After"), NumberStyles.None, CultureInfo.InvariantCulture, out var seconds) && seconds > 0
            ? seconds
            : null;
}
#endregion
