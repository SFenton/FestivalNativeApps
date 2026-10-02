using System.Net.Http.Headers;
using System.Text.Json;

namespace Festival.Core.Data;

#region Feedback submission
/// <summary>
/// The in-app feedback write (issue #78): one user-initiated multipart <c>POST /api/feedback</c> per Submit. It carries no
/// key, profile or publication headers and is never sent by automation against production
/// (<c>.agents/platforms/service-safety.md</c>, <c>.agents/controls/feedback-form/spec.md</c>).
/// </summary>
public sealed partial class FestivalApiClient
{
    /// <summary>Sends a report or request with its media.</summary>
    /// <param name="submission">Form contents from <see cref="FeedbackDraft.Submission"/>.</param>
    /// <param name="openAttachment">Opens a picked attachment for reading (caller-owned file access).</param>
    /// <param name="cancellationToken">Cancellation (the user discarded the form).</param>
    /// <returns>Created issue number and URL when the service reports them.</returns>
    /// <exception cref="FeedbackException">Readable failure: unreadable attachment, offline, timeout or HTTP status.</exception>
    /// <exception cref="OperationCanceledException">The caller cancelled.</exception>
    public async Task<FeedbackReceipt> SubmitFeedbackAsync(
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
        if (response.Status is < 200 or > 299) throw FeedbackException.ForStatus(response.Status);
        return ParseFeedbackReceipt(response.Body);
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

    /// <summary>Reads the optional receipt; any unreadable body is still a success without a link.</summary>
    /// <param name="body">Response bytes.</param>
    /// <returns>Receipt (positive issue number and GitHub URL only).</returns>
    internal static FeedbackReceipt ParseFeedbackReceipt(byte[] body)
    {
        if (body.Length == 0) return new FeedbackReceipt(null, null);
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return new FeedbackReceipt(null, null);
            int? number = document.RootElement.TryGetProperty("issueNumber", out var n) && n.ValueKind == JsonValueKind.Number &&
                          n.TryGetInt32(out var value) && value > 0
                ? value
                : null;
            var url = document.RootElement.TryGetProperty("issueUrl", out var u) && u.ValueKind == JsonValueKind.String
                ? FeedbackReceipt.SafeUrl(u.GetString())
                : null;
            return new FeedbackReceipt(number, url);
        }
        catch (JsonException)
        {
            return new FeedbackReceipt(null, null);
        }
    }
}
#endregion
