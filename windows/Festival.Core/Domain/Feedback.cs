using System.Globalization;

namespace Festival.Core.Domain;

#region Kind
/// <summary>The two in-app feedback forms (Settings → App Settings, issue #78).</summary>
public enum FeedbackKind
{
    /// <summary>Report an Issue: title, description, steps to reproduce, expected behavior.</summary>
    Bug,
    /// <summary>Request a Feature: title and description.</summary>
    Feature,
}

/// <summary>Per-kind wire values and copy (<c>.agents/controls/feedback-form/spec.md</c>).</summary>
public static class FeedbackKinds
{
    /// <summary><c>kind</c> form field sent to <c>POST /api/feedback</c>.</summary>
    /// <param name="kind">Form.</param>
    /// <returns><c>bug</c> or <c>feature</c>.</returns>
    public static string Wire(this FeedbackKind kind) => kind == FeedbackKind.Bug ? "bug" : "feature";

    /// <summary>Text the title starts with (and is restored to on submit).</summary>
    /// <param name="kind">Form.</param>
    /// <returns><c>"[Bug] "</c> or <c>"[Feature] "</c>.</returns>
    public static string TitlePrefix(this FeedbackKind kind) => kind == FeedbackKind.Bug ? "[Bug] " : "[Feature] ";

    /// <summary>Dialog title and Settings row label.</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Label.</returns>
    public static string FormTitle(this FeedbackKind kind) => kind == FeedbackKind.Bug ? "Report an Issue" : "Request a Feature";

    /// <summary>Settings row description.</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Description.</returns>
    public static string RowDescription(this FeedbackKind kind) => kind == FeedbackKind.Bug
        ? "Tell us about something that isn't working right."
        : "Suggest something new for Festival Score Tracker.";

    /// <summary>Lower-case noun used in messages.</summary>
    /// <param name="kind">Form.</param>
    /// <returns><c>report</c> or <c>request</c>.</returns>
    public static string Noun(this FeedbackKind kind) => kind == FeedbackKind.Bug ? "report" : "request";

    /// <summary>Whether the form shows Steps to Reproduce and Expected Behavior.</summary>
    /// <param name="kind">Form.</param>
    /// <returns><see langword="true"/> for bugs.</returns>
    public static bool HasBugFields(this FeedbackKind kind) => kind == FeedbackKind.Bug;

    /// <summary>Stable UI Automation suffix (<c>bug</c>/<c>feature</c>).</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Suffix.</returns>
    public static string AutomationSuffix(this FeedbackKind kind) => kind.Wire();
}
#endregion

#region Limits and copy
/// <summary>
/// Client-side mirrors of the service's <c>POST /api/feedback</c> bounds (FSTService <c>docs/components/in-app-feedback.md</c>).
/// The service fits each accepted file under GitHub's limits itself; these only stop uploads it would reject.
/// </summary>
public static class FeedbackLimits
{
    /// <summary>Most attachments one submission carries (service <c>MaxAttachments</c>).</summary>
    public const int MaxAttachments = 4;

    /// <summary>Largest whole request the service accepts (90 MiB; larger answers 413 <c>payload_too_large</c>).</summary>
    public const long MaxRequestBytes = 94_371_840;

    /// <summary>Combined attachment budget: the request cap less 512 KiB for text fields and multipart framing.</summary>
    public const long MaxTotalBytes = MaxRequestBytes - 512 * 1024;

    /// <summary>Largest single attachment (the whole budget; there is no separate per-file cap).</summary>
    public const long MaxAttachmentBytes = MaxTotalBytes;

    /// <summary>Longest title, prefix included.</summary>
    public const int MaxTitleLength = 200;

    /// <summary>Longest description, steps or expected-behavior text.</summary>
    public const int MaxTextLength = 10_000;

    /// <summary>Longest <c>appVersion</c> field.</summary>
    public const int MaxAppVersionLength = 64;

    /// <summary>Longest <c>clientInfo</c> field (OS and device).</summary>
    public const int MaxClientInfoLength = 256;
}

/// <summary>Field labels and the always-visible helper lines under them (they never disappear while typing).</summary>
public static class FeedbackCopy
{
    /// <summary>Title label.</summary>
    public const string Title = "Title";

    /// <summary>Description label.</summary>
    public const string Description = "Description";

    /// <summary>Steps label.</summary>
    public const string Repro = "Steps to Reproduce";

    /// <summary>Expected label.</summary>
    public const string Expected = "Expected Behavior";

    /// <summary>Helper under Steps to Reproduce.</summary>
    public const string ReproHelp = "List the steps that make the problem happen, one per line.";

    /// <summary>Helper under Expected Behavior.</summary>
    public const string ExpectedHelp = "What did you expect to happen instead?";

    /// <summary>Attach button label.</summary>
    public const string Attach = "Attach Media";

    /// <summary>Helper above the attach button (count and size limits, and that selecting a tile opens it).</summary>
    public static string AttachHelp =>
        $"Add up to {FeedbackLimits.MaxAttachments} screenshots or screen recordings, " +
        $"{FeedbackFormat.Bytes(FeedbackLimits.MaxRequestBytes)} in total. Select one to open it.";

    /// <summary>Helper under the title.</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Guidance text.</returns>
    public static string TitleHelp(FeedbackKind kind) => kind == FeedbackKind.Bug
        ? $"A short summary of the problem, after {kind.TitlePrefix().Trim()}."
        : $"A short name for your idea, after {kind.TitlePrefix().Trim()}.";

    /// <summary>Helper under the description.</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Guidance text.</returns>
    public static string DescriptionHelp(FeedbackKind kind) => kind == FeedbackKind.Bug
        ? "What went wrong? Include the page, song, instrument or player involved."
        : "What would you like, and how would it help you? Mention the pages it affects.";
}
#endregion

#region Media types
/// <summary>Image/video file types the picker offers, with their MIME types (Windows pickers filter by extension).</summary>
public static class FeedbackMedia
{
    private static readonly Dictionary<string, string> Types = new(StringComparer.OrdinalIgnoreCase)
    {
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif",
        [".bmp"] = "image/bmp",
        [".webp"] = "image/webp",
        [".heic"] = "image/heic",
        [".heif"] = "image/heif",
        [".mp4"] = "video/mp4",
        [".m4v"] = "video/x-m4v",
        [".mov"] = "video/quicktime",
        [".wmv"] = "video/x-ms-wmv",
        [".avi"] = "video/x-msvideo",
        [".mkv"] = "video/x-matroska",
        [".webm"] = "video/webm",
    };

    /// <summary>Picker file-type filter, in a stable order.</summary>
    public static IReadOnlyList<string> Extensions { get; } = [.. Types.Keys];

    /// <summary>MIME type for a file name.</summary>
    /// <param name="fileName">File name or path.</param>
    /// <returns>The image/video MIME type, or <c>application/octet-stream</c> for anything else.</returns>
    public static string MimeType(string fileName) =>
        Types.GetValueOrDefault(Path.GetExtension(fileName) ?? "", "application/octet-stream");
}
#endregion

#region Attachment
/// <summary>One picked image or video. The app never decodes video or plays media; selecting it hands it to the system.</summary>
/// <param name="Id">Stable handle (the file path on Windows).</param>
/// <param name="Name">Display name sent as the multipart file name.</param>
/// <param name="MimeType">MIME type (<c>image/…</c> or <c>video/…</c>).</param>
/// <param name="SizeBytes">Size when known.</param>
public sealed record FeedbackAttachment(string Id, string Name, string MimeType, long? SizeBytes)
{
    /// <summary>Whether this is a video.</summary>
    public bool IsVideo => MimeType.StartsWith("video/", StringComparison.OrdinalIgnoreCase);

    /// <summary>Whether the type is an image or a video.</summary>
    public bool IsMedia => IsVideo || MimeType.StartsWith("image/", StringComparison.OrdinalIgnoreCase);

    /// <summary>Narrator label: kind, name and size.</summary>
    public string AccessibilityLabel =>
        $"{(IsVideo ? "Video" : "Image")}, {Name}{(SizeBytes is { } size ? ", " + FeedbackFormat.Bytes(size) : "")}";
}

/// <summary>Outcome of adding picked attachments.</summary>
/// <param name="Attachments">Resulting list.</param>
/// <param name="Notice">Readable reason some picks were skipped, or <see langword="null"/>.</param>
public sealed record AttachmentAddResult(IReadOnlyList<FeedbackAttachment> Attachments, string? Notice);
#endregion

#region Draft
/// <summary>Why a draft cannot be submitted yet.</summary>
public enum FeedbackProblem
{
    /// <summary>Nothing but the prefix in the title.</summary>
    MissingTitle,
    /// <summary>Empty description.</summary>
    MissingDescription,
    /// <summary>A field is over its limit.</summary>
    TooLong,
}

/// <summary>Problem messages.</summary>
public static class FeedbackProblems
{
    /// <summary>Readable text for a problem.</summary>
    /// <param name="problem">Problem.</param>
    /// <returns>Message.</returns>
    public static string Message(this FeedbackProblem problem) => problem switch
    {
        FeedbackProblem.MissingTitle => "Add a title after the prefix.",
        FeedbackProblem.MissingDescription => "Add a description.",
        _ => "Shorten the text and try again.",
    };
}

/// <summary>The editable form. Pure value; <see cref="IsDirty"/> drives the discard confirmation.</summary>
/// <param name="Kind">Form.</param>
public sealed record FeedbackDraft(FeedbackKind Kind)
{
    /// <summary>Title text (pre-filled with the prefix).</summary>
    public string Title { get; init; } = Kind.TitlePrefix();

    /// <summary>Description.</summary>
    public string Description { get; init; } = "";

    /// <summary>Steps to reproduce (bugs only).</summary>
    public string ReproSteps { get; init; } = "";

    /// <summary>Expected behavior (bugs only).</summary>
    public string ExpectedBehavior { get; init; } = "";

    /// <summary>Picked media in pick order.</summary>
    public IReadOnlyList<FeedbackAttachment> Attachments { get; init; } = [];

    /// <summary>Title text after the kind prefix (the user's own words).</summary>
    public string TitleBody
    {
        get
        {
            var trimmed = Title.Trim();
            var tag = Kind.TitlePrefix().Trim();
            return trimmed.StartsWith(tag, StringComparison.OrdinalIgnoreCase) ? trimmed[tag.Length..].Trim() : trimmed;
        }
    }

    /// <summary>Whether closing would lose anything the user entered.</summary>
    public bool IsDirty =>
        TitleBody.Length > 0 || !string.IsNullOrWhiteSpace(Description) ||
        (Kind.HasBugFields() && (!string.IsNullOrWhiteSpace(ReproSteps) || !string.IsNullOrWhiteSpace(ExpectedBehavior))) ||
        Attachments.Count > 0;

    /// <summary>Title sent to the service: trimmed and always starting with the prefix, even if the user deleted it.</summary>
    public string NormalizedTitle => Kind.TitlePrefix() + TitleBody;

    /// <summary>The first problem blocking submission, or <see langword="null"/> when ready.</summary>
    public FeedbackProblem? Problem =>
        TitleBody.Length == 0 ? FeedbackProblem.MissingTitle
        : string.IsNullOrWhiteSpace(Description) ? FeedbackProblem.MissingDescription
        : NormalizedTitle.Length > FeedbackLimits.MaxTitleLength ||
          new[] { Description, ReproSteps, ExpectedBehavior }.Any(t => t.Trim().Length > FeedbackLimits.MaxTextLength)
            ? FeedbackProblem.TooLong
            : null;

    /// <summary>Adds picked media: skips duplicates and non-media, then enforces count and size bounds.</summary>
    /// <param name="picked">Newly picked items.</param>
    /// <returns>New list plus a notice naming anything skipped.</returns>
    public AttachmentAddResult Adding(IEnumerable<FeedbackAttachment> picked)
    {
        var result = Attachments.ToList();
        var total = Attachments.Sum(a => a.SizeBytes ?? 0);
        int skippedType = 0, skippedSize = 0, skippedCount = 0;
        foreach (var item in picked)
        {
            var size = item.SizeBytes ?? 0;
            if (result.Any(a => a.Id == item.Id)) continue;
            if (!item.IsMedia) skippedType++;
            else if (result.Count >= FeedbackLimits.MaxAttachments) skippedCount++;
            else if (size > FeedbackLimits.MaxAttachmentBytes || total + size > FeedbackLimits.MaxTotalBytes) skippedSize++;
            else
            {
                result.Add(item);
                total += size;
            }
        }
        var notices = new List<string>();
        if (skippedType > 0) notices.Add("Only images and videos can be attached.");
        if (skippedCount > 0) notices.Add($"You can attach up to {FeedbackLimits.MaxAttachments} files.");
        if (skippedSize > 0)
            notices.Add($"Attachments must add up to less than {FeedbackFormat.Bytes(FeedbackLimits.MaxRequestBytes)}.");
        return new AttachmentAddResult(result, notices.Count == 0 ? null : string.Join(" ", notices));
    }

    /// <summary>Builds the wire submission.</summary>
    /// <param name="platform">Platform label (<c>windows</c>).</param>
    /// <param name="appVersion">App version.</param>
    /// <param name="clientInfo">OS and device description.</param>
    /// <returns>Submission with trimmed text; bug-only fields are empty for features.</returns>
    public FeedbackSubmission Submission(string platform, string appVersion, string clientInfo) => new(
        Kind,
        platform,
        NormalizedTitle,
        Description.Trim(),
        Kind.HasBugFields() ? ReproSteps.Trim() : "",
        Kind.HasBugFields() ? ExpectedBehavior.Trim() : "",
        appVersion,
        clientInfo,
        Attachments);
}
#endregion

#region Submission
/// <summary>What <c>POST /api/feedback</c> carries (<c>.agents/controls/feedback-form/spec.md</c>).</summary>
/// <param name="Kind">Form.</param>
/// <param name="Platform">Platform label the service turns into the issue's <c>surface:</c> label.</param>
/// <param name="Title">Prefixed title.</param>
/// <param name="Description">Description.</param>
/// <param name="ReproSteps">Steps (empty for features: omitted on the wire).</param>
/// <param name="ExpectedBehavior">Expected behavior (empty for features: omitted on the wire).</param>
/// <param name="AppVersion">App version.</param>
/// <param name="ClientInfo">OS and device description.</param>
/// <param name="Attachments">Media, each sent as a <c>media</c> file part.</param>
public sealed record FeedbackSubmission(
    FeedbackKind Kind,
    string Platform,
    string Title,
    string Description,
    string ReproSteps,
    string ExpectedBehavior,
    string AppVersion,
    string ClientInfo,
    IReadOnlyList<FeedbackAttachment> Attachments)
{
    /// <summary>Multipart name of every file part.</summary>
    public const string MediaPart = "media";

    /// <summary>Platform label Windows submits.</summary>
    public const string PlatformWindows = "windows";

    /// <summary>
    /// Text form fields in wire order (<c>kind</c>, <c>platform</c>, <c>title</c>, <c>description</c>, <c>repro</c>,
    /// <c>expected</c>, <c>appVersion</c>, <c>clientInfo</c>); empty optional fields are omitted and the two
    /// diagnostics are clipped to the service's limits.
    /// </summary>
    public IReadOnlyList<KeyValuePair<string, string>> FormFields
    {
        get
        {
            var fields = new List<KeyValuePair<string, string>>
            {
                new("kind", Kind.Wire()),
                new("platform", Platform),
                new("title", Title),
                new("description", Description),
            };
            if (ReproSteps.Length > 0) fields.Add(new("repro", ReproSteps));
            if (ExpectedBehavior.Length > 0) fields.Add(new("expected", ExpectedBehavior));
            if (Clip(AppVersion, FeedbackLimits.MaxAppVersionLength) is { Length: > 0 } version) fields.Add(new("appVersion", version));
            if (Clip(ClientInfo, FeedbackLimits.MaxClientInfoLength) is { Length: > 0 } info) fields.Add(new("clientInfo", info));
            return fields;
        }
    }

    /// <summary>Trims and cuts a diagnostic to a length limit.</summary>
    /// <param name="value">Value.</param>
    /// <param name="max">Limit.</param>
    /// <returns>Clipped text.</returns>
    private static string Clip(string value, int max)
    {
        var trimmed = value.Trim();
        return trimmed.Length > max ? trimmed[..max].TrimEnd() : trimmed;
    }

    /// <summary>
    /// Multipart file name: the last path segment without quotes, backslashes or control characters, at most 120
    /// characters, <c>attachment</c> when nothing is left.
    /// </summary>
    /// <param name="name">Picked name.</param>
    /// <returns>Header-safe file name.</returns>
    public static string SafeFileName(string name)
    {
        var last = name.Split('/', '\\').LastOrDefault() ?? "";
        var clean = new string(last.Where(c => c >= ' ' && c != '"' && c != 127).ToArray()).Trim();
        if (clean.Length > 120) clean = clean[..120];
        return clean.Length == 0 ? "attachment" : clean;
    }
}
#endregion

#region Job status
/// <summary>Service processing state of an accepted submission (<c>GET /api/feedback/{id}</c>).</summary>
public enum FeedbackJobState
{
    /// <summary>Accepted (the 202 answer), waiting for a worker.</summary>
    Queued,
    /// <summary>Media being prepared or the issue being filed.</summary>
    Processing,
    /// <summary>Filed on GitHub.</summary>
    Submitted,
    /// <summary>Filing failed; nothing was created.</summary>
    Failed,
}

/// <summary>
/// An accepted submission as last seen. The 202 answer is <c>{id, status:"queued"}</c>; polling adds the issue number and
/// per-attachment outcomes. The service never returns an issue URL (the tracker may be private), so the app shows the
/// number only and opens no link.
/// </summary>
/// <param name="Id">32 lowercase hex characters, or <see langword="null"/> when the 2xx body carried none (no polling).</param>
/// <param name="State">Processing state.</param>
/// <param name="IssueNumber">Created issue number once submitted, when reported.</param>
/// <param name="SkippedAttachments">Attachments the service could not fit and left out.</param>
public sealed record FeedbackJob(string? Id, FeedbackJobState State, int? IssueNumber = null, int SkippedAttachments = 0)
{
    /// <summary>Whether polling can stop.</summary>
    public bool IsTerminal => State is FeedbackJobState.Submitted or FeedbackJobState.Failed;

    /// <summary>Whether a value is a well-formed job ID (the only shape the status route answers).</summary>
    /// <param name="id">Candidate.</param>
    /// <returns><see langword="true"/> for exactly 32 lowercase hex characters.</returns>
    public static bool IsValidId(string? id) => id is { Length: 32 } && id.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    /// <summary>Wire <c>status</c> value, case-insensitively.</summary>
    /// <param name="wire">Value.</param>
    /// <returns>State, or <see langword="null"/> for anything unknown.</returns>
    public static FeedbackJobState? ParseState(string? wire) => wire?.Trim().ToLowerInvariant() switch
    {
        "queued" => FeedbackJobState.Queued,
        "processing" => FeedbackJobState.Processing,
        "submitted" => FeedbackJobState.Submitted,
        "failed" => FeedbackJobState.Failed,
        _ => null,
    };

    /// <summary>
    /// Success text. A submitted job names its issue; an accepted job whose outcome is unknown (still processing when
    /// polling stopped, status expired or unreadable) says it will be filed shortly rather than inviting a duplicate.
    /// </summary>
    /// <param name="kind">Form.</param>
    /// <returns>Readable confirmation.</returns>
    public string Message(FeedbackKind kind)
    {
        var noun = kind.Noun();
        var text = State != FeedbackJobState.Submitted
            ? $"Thanks! Your {noun} was received and will be filed on GitHub shortly."
            : IssueNumber is { } number
                ? $"Thanks! Your {noun} was filed as issue #{number}."
                : $"Thanks! Your {noun} was filed on GitHub.";
        return SkippedAttachments switch
        {
            <= 0 => text,
            1 => text + " 1 attachment couldn't be attached.",
            var count => text + $" {count} attachments couldn't be attached.",
        };
    }
}

/// <summary>A failed submission with fixed, readable text (server <c>error</c> strings are never shown).</summary>
public sealed class FeedbackException : Exception
{
    /// <summary>Creates a failure.</summary>
    /// <param name="message">Readable text.</param>
    /// <param name="status">HTTP status, when one arrived.</param>
    /// <param name="inner">Cause.</param>
    public FeedbackException(string message, int? status = null, Exception? inner = null) : base(message, inner) => Status = status;

    /// <summary>HTTP status, when one arrived.</summary>
    public int? Status { get; }

    /// <summary>Maps a non-2xx answer (status, the body's <c>code</c> and <c>Retry-After</c>) to readable text.</summary>
    /// <param name="status">Status.</param>
    /// <param name="code">Service error code from the <c>{error, code}</c> body, when present.</param>
    /// <param name="retryAfterSeconds">Parsed <c>Retry-After</c> seconds, when present.</param>
    /// <returns>Exception to surface.</returns>
    public static FeedbackException ForStatus(int status, string? code = null, int? retryAfterSeconds = null) => new(code switch
    {
        "payload_too_large" => $"The attachments are too large. Keep them under {FeedbackFormat.Bytes(FeedbackLimits.MaxRequestBytes)} in total.",
        "too_many_attachments" => $"Attach up to {FeedbackLimits.MaxAttachments} files.",
        "unsupported_media" => "Only image and video attachments are supported.",
        "feedback_disabled" => "Sending feedback isn't available right now.",
        "feedback_busy" => "Feedback is busy right now. Try again in a minute.",
        "title_required" => "Add a title after the prefix.",
        "description_required" => "Add a description.",
        "field_too_long" => "One of the fields is too long. Shorten it and try again.",
        _ => status switch
        {
            429 => retryAfterSeconds is > 0 and var seconds
                ? $"Too many submissions from this network. Try again in {FeedbackFormat.Wait(seconds)}."
                : "Too many submissions from this network. Try again later.",
            400 or 422 => "The service couldn't accept this form. Check the fields and try again.",
            404 or 405 or 501 => "Sending feedback isn't available right now.",
            413 => $"The attachments are too large. Keep them under {FeedbackFormat.Bytes(FeedbackLimits.MaxRequestBytes)} in total.",
            415 => "Only image and video attachments are supported.",
            503 => "Feedback is busy right now. Try again in a minute.",
            >= 500 and <= 599 => "The service is temporarily unavailable. Try again.",
            _ => $"Your feedback couldn't be sent (HTTP {status}). Try again.",
        },
    }, status);

    /// <summary>The service accepted the form but could not file the issue.</summary>
    /// <param name="kind">Form.</param>
    /// <returns>Exception to surface (the form stays filled for a retry).</returns>
    public static FeedbackException FilingFailed(FeedbackKind kind) =>
        new($"Your {kind.Noun()} couldn't be filed on GitHub. Try again in a few minutes.");

    /// <summary>Connectivity failure.</summary>
    /// <param name="inner">Cause.</param>
    /// <returns>Exception to surface.</returns>
    public static FeedbackException Offline(Exception? inner = null) => new("Check your connection and try again.", inner: inner);

    /// <summary>The upload took too long.</summary>
    /// <param name="inner">Cause.</param>
    /// <returns>Exception to surface.</returns>
    public static FeedbackException TimedOut(Exception? inner = null) =>
        new("Sending took too long. Check your connection, or remove large videos, and try again.", inner: inner);

    /// <summary>An attachment could not be read.</summary>
    /// <param name="name">Attachment name.</param>
    /// <param name="inner">Cause.</param>
    /// <returns>Exception to surface.</returns>
    public static FeedbackException Unreadable(string name, Exception? inner = null) =>
        new($"\"{name}\" couldn't be read. Remove it and try again.", inner: inner);
}
#endregion

#region Formatting
/// <summary>Small formatting helpers shared by the form.</summary>
public static class FeedbackFormat
{
    /// <summary>Human file size (one decimal for MB/GB, trailing <c>.0</c> dropped).</summary>
    /// <param name="bytes">Size.</param>
    /// <returns>E.g. <c>512 KB</c>, <c>3.4 MB</c>.</returns>
    public static string Bytes(long bytes)
    {
        const double kb = 1024, mb = kb * 1024, gb = mb * 1024;
        return bytes switch
        {
            < 1024 => $"{bytes} B",
            < 1024 * 1024 => $"{(long)(bytes / kb)} KB",
            < 1024L * 1024 * 1024 => (bytes / mb).ToString("0.#", CultureInfo.InvariantCulture) + " MB",
            _ => (bytes / gb).ToString("0.#", CultureInfo.InvariantCulture) + " GB",
        };
    }

    /// <summary>A short wait for retry messages.</summary>
    /// <param name="seconds">Seconds (positive).</param>
    /// <returns>E.g. <c>45 seconds</c>, <c>1 minute</c>, <c>10 minutes</c> (rounded up).</returns>
    public static string Wait(int seconds)
    {
        if (seconds < 60) return seconds == 1 ? "1 second" : $"{seconds} seconds";
        var minutes = (seconds + 59) / 60;
        return minutes == 1 ? "1 minute" : $"{minutes} minutes";
    }
}
#endregion
