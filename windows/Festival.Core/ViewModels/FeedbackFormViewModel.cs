using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Phase
/// <summary>Where an open feedback form is.</summary>
public enum FeedbackPhase
{
    /// <summary>Fields editable; Submit enabled once the form is valid.</summary>
    Editing,
    /// <summary>Upload in progress; fields locked.</summary>
    Submitting,
    /// <summary>Accepted (202); waiting for the service to file the issue. Closing loses nothing.</summary>
    Filing,
    /// <summary>Filed (or accepted with the outcome unknown); only Done remains.</summary>
    Sent,
}
#endregion

#region Feedback form
/// <summary>
/// Settings → Report an Issue / Request a Feature (issue #78). One instance per open dialog; closing with unsent input
/// asks first, discarding cancels an upload, and a failure keeps every field with a readable error. After the 202 the
/// form polls the job until it is filed or fails; a poll that cannot finish (timeout, expired or unreadable status)
/// still reports the accepted submission as received rather than inviting a duplicate.
/// </summary>
public sealed class FeedbackFormViewModel : ObservableObject
{
    /// <summary>Delay between status reads.</summary>
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(2);

    /// <summary>How long to wait for the service to file the issue before reporting it as received.</summary>
    public static readonly TimeSpan PollTimeout = TimeSpan.FromMinutes(5);

    private readonly Func<FeedbackSubmission, IProgress<double>, CancellationToken, Task<FeedbackJob>> send;
    private readonly Func<string, CancellationToken, Task<FeedbackJob>> status;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly Func<DateTimeOffset> now;
    private readonly string appVersion;
    private readonly string clientInfo;
    private FeedbackDraft draft;
    private FeedbackPhase phase;
    private string? error;
    private string? notice;
    private bool confirmingDiscard;
    private FeedbackJob? job;
    private CancellationTokenSource? upload;
    private double uploadFraction;

    /// <summary>Opens a fresh form whose sender does not report upload progress (the bar fills when the 202 arrives).</summary>
    /// <param name="kind">Bug or Feature.</param>
    /// <param name="send">Sends one submission.</param>
    /// <param name="status">Reads a job.</param>
    /// <param name="appVersion">App version reported with the form.</param>
    /// <param name="clientInfo">OS and device description reported with the form.</param>
    /// <param name="delay">Waits between polls.</param>
    /// <param name="now">Clock for the poll deadline.</param>
    public FeedbackFormViewModel(
        FeedbackKind kind,
        Func<FeedbackSubmission, CancellationToken, Task<FeedbackJob>> send,
        Func<string, CancellationToken, Task<FeedbackJob>> status,
        string appVersion,
        string clientInfo,
        Func<TimeSpan, CancellationToken, Task>? delay = null,
        Func<DateTimeOffset>? now = null)
        : this(kind, (submission, _, token) => send(submission, token), status, appVersion, clientInfo, delay, now)
    {
    }

    /// <summary>Opens a fresh form.</summary>
    /// <param name="kind">Bug or Feature.</param>
    /// <param name="send">
    /// Sends one submission (<see cref="Data.FestivalApiClient.SubmitFeedbackAsync"/> with file access), reporting the
    /// written fraction of the body to the given progress; the form ignores reports after the upload phase ends.
    /// </param>
    /// <param name="status">Reads a job (<see cref="Data.FestivalApiClient.GetFeedbackStatusAsync"/>).</param>
    /// <param name="appVersion">App version reported with the form.</param>
    /// <param name="clientInfo">OS and device description reported with the form.</param>
    /// <param name="delay">Waits between polls (tests replace it); defaults to <see cref="Task.Delay(TimeSpan, CancellationToken)"/>.</param>
    /// <param name="now">Clock for the poll deadline; defaults to the system clock.</param>
    public FeedbackFormViewModel(
        FeedbackKind kind,
        Func<FeedbackSubmission, IProgress<double>, CancellationToken, Task<FeedbackJob>> send,
        Func<string, CancellationToken, Task<FeedbackJob>> status,
        string appVersion,
        string clientInfo,
        Func<TimeSpan, CancellationToken, Task>? delay = null,
        Func<DateTimeOffset>? now = null)
    {
        this.send = send;
        this.status = status;
        this.delay = delay ?? Task.Delay;
        this.now = now ?? (() => DateTimeOffset.UtcNow);
        this.appVersion = appVersion;
        this.clientInfo = clientInfo;
        draft = new FeedbackDraft(kind);
    }

    #region Copy
    /// <summary>Form.</summary>
    public FeedbackKind Kind => draft.Kind;

    /// <summary>Dialog title.</summary>
    public string FormTitle => Kind.FormTitle();

    /// <summary>Whether Steps to Reproduce and Expected Behavior show.</summary>
    public bool HasBugFields => Kind.HasBugFields();

    /// <summary>Helper under the title.</summary>
    public string TitleHelp => FeedbackCopy.TitleHelp(Kind);

    /// <summary>Helper under the description.</summary>
    public string DescriptionHelp => FeedbackCopy.DescriptionHelp(Kind);

    /// <summary>
    /// Busy-status title (issue #634): "Uploading Media" while attached media uploads, then "Filing Issue/Request";
    /// empty while editing or sent. A form with no media reads as filing from Submit: "Uploading Media" would be
    /// inaccurate and would flash for a fraction of a second (agent decision, shared with Android).
    /// </summary>
    public string StatusTitle => !IsSubmitting ? "" : UploadsMedia ? FeedbackCopy.UploadingTitle : FeedbackCopy.FilingTitle(Kind);

    /// <summary>Busy-status subtitle text: none while media uploads (the bar is the subtitle), the filing explanation otherwise.</summary>
    public string StatusSubtitle => IsSubmitting && !UploadsMedia ? FeedbackCopy.FilingSubtitle(Kind) : "";

    /// <summary>Whether the busy status is in its media upload step.</summary>
    private bool UploadsMedia => phase == FeedbackPhase.Submitting && HasAttachments;

    /// <summary>Accessible name of the busy ring, stable across both busy phases.</summary>
    public string BusyName => FeedbackCopy.BusyName(Kind);
    #endregion

    #region Fields
    /// <summary>Current draft.</summary>
    public FeedbackDraft Draft => draft;

    /// <summary>Title (pre-filled with the prefix).</summary>
    public string Title
    {
        get => draft.Title;
        set => Edit(draft with { Title = value ?? "" }, nameof(Title));
    }

    /// <summary>Description.</summary>
    public string Description
    {
        get => draft.Description;
        set => Edit(draft with { Description = value ?? "" }, nameof(Description));
    }

    /// <summary>Steps to reproduce.</summary>
    public string ReproSteps
    {
        get => draft.ReproSteps;
        set => Edit(draft with { ReproSteps = value ?? "" }, nameof(ReproSteps));
    }

    /// <summary>Expected behavior.</summary>
    public string ExpectedBehavior
    {
        get => draft.ExpectedBehavior;
        set => Edit(draft with { ExpectedBehavior = value ?? "" }, nameof(ExpectedBehavior));
    }

    /// <summary>Picked media, shown above Attach Media.</summary>
    public ObservableCollection<FeedbackAttachment> Attachments { get; } = [];

    /// <summary>Whether any media is attached.</summary>
    public bool HasAttachments => Attachments.Count > 0;
    #endregion

    #region State
    /// <summary>Phase.</summary>
    public FeedbackPhase Phase
    {
        get => phase;
        private set
        {
            if (!SetProperty(ref phase, value)) return;
            OnPropertyChanged(nameof(IsEditing));
            OnPropertyChanged(nameof(IsSubmitting));
            OnPropertyChanged(nameof(IsSent));
            OnPropertyChanged(nameof(ShowsUploadBar));
            OnPropertyChanged(nameof(StatusTitle));
            OnPropertyChanged(nameof(StatusSubtitle));
            OnPropertyChanged(nameof(PrimaryText));
            OnPropertyChanged(nameof(CloseText));
            OnPropertyChanged(nameof(CanSubmit));
            OnPropertyChanged(nameof(ValidationMessage));
        }
    }

    /// <summary>Whether fields are editable.</summary>
    public bool IsEditing => phase == FeedbackPhase.Editing;

    /// <summary>Whether Submit is enabled: editing a form with no blocking problem (spec: disabled while empty or invalid).</summary>
    public bool CanSubmit => IsEditing && draft.Problem is null;

    /// <summary>Inline reason Submit is disabled while editing, or <see langword="null"/> when the form can be sent.</summary>
    public string? ValidationMessage => IsEditing ? draft.Problem?.Message() : null;

    /// <summary>Whether progress shows (uploading or waiting for the issue).</summary>
    public bool IsSubmitting => phase is FeedbackPhase.Submitting or FeedbackPhase.Filing;

    /// <summary>Whether the determinate upload bar shows (media uploading; otherwise the subtitle text shows instead).</summary>
    public bool ShowsUploadBar => UploadsMedia;

    /// <summary>
    /// Fraction of the body written so far, in [0, 1]; it only rises during one upload and resets on the next Submit.
    /// </summary>
    public double UploadFraction
    {
        get => uploadFraction;
        private set => SetProperty(ref uploadFraction, value);
    }

    /// <summary>Whether the service accepted the form.</summary>
    public bool IsSent => phase == FeedbackPhase.Sent;

    /// <summary>Primary command text (Submit; hidden once sent).</summary>
    public string PrimaryText => IsSent ? "" : "Submit";

    /// <summary>Close command text (Cancel; Done once sent).</summary>
    public string CloseText => IsSent ? "Done" : "Cancel";

    /// <summary>Readable validation or send failure, or <see langword="null"/>.</summary>
    public string? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value)) OnPropertyChanged(nameof(HasError));
        }
    }

    /// <summary>Whether <see cref="Error"/> shows.</summary>
    public bool HasError => error is not null;

    /// <summary>Why some picks were skipped, or <see langword="null"/>.</summary>
    public string? Notice
    {
        get => notice;
        private set
        {
            if (SetProperty(ref notice, value)) OnPropertyChanged(nameof(HasNotice));
        }
    }

    /// <summary>Whether <see cref="Notice"/> shows.</summary>
    public bool HasNotice => notice is not null;

    /// <summary>Whether the inline discard confirmation shows.</summary>
    public bool ConfirmingDiscard
    {
        get => confirmingDiscard;
        private set => SetProperty(ref confirmingDiscard, value);
    }

    /// <summary>Accepted job as last seen.</summary>
    public FeedbackJob? Job
    {
        get => job;
        private set
        {
            if (SetProperty(ref job, value)) OnPropertyChanged(nameof(SuccessMessage));
        }
    }

    /// <summary>Success text (issue number when filed; "received" when the outcome is unknown).</summary>
    public string SuccessMessage => phase == FeedbackPhase.Sent && job is not null ? job.Message(Kind) : "";
    #endregion

    #region Actions
    /// <summary>Adds picked media (duplicates, non-media and over-limit picks are skipped with a notice).</summary>
    /// <param name="picked">Picked attachments.</param>
    public void AddAttachments(IEnumerable<FeedbackAttachment> picked)
    {
        var items = picked.ToList();
        if (!IsEditing || items.Count == 0) return;
        var result = draft.Adding(items);
        foreach (var added in result.Attachments.Skip(draft.Attachments.Count)) Attachments.Add(added);
        draft = draft with { Attachments = result.Attachments };
        Notice = result.Notice;
        OnPropertyChanged(nameof(HasAttachments));
        RaiseValidity();
    }

    /// <summary>Removes one attachment.</summary>
    /// <param name="id">Attachment ID.</param>
    public void RemoveAttachment(string id)
    {
        if (!IsEditing) return;
        var kept = draft.Attachments.Where(a => a.Id != id).ToList();
        if (kept.Count == draft.Attachments.Count) return;
        draft = draft with { Attachments = kept };
        foreach (var gone in Attachments.Where(a => a.Id == id).ToList()) Attachments.Remove(gone);
        Notice = null;
        Error = null;
        OnPropertyChanged(nameof(HasAttachments));
        RaiseValidity();
    }

    /// <summary>Cancel, Esc or an outside click: whether the dialog may close now; otherwise shows the confirmation.</summary>
    /// <returns><see langword="true"/> when nothing would be lost (or the form was sent).</returns>
    public bool RequestClose()
    {
        if (phase == FeedbackPhase.Filing)
        {
            // Already accepted: stop waiting; the service files it regardless.
            upload?.Cancel();
            return true;
        }
        if (IsSent || (IsEditing && !draft.IsDirty)) return true;
        ConfirmingDiscard = true;
        return false;
    }

    /// <summary>Discard confirmed: cancels any upload; the dialog then closes.</summary>
    public void ConfirmDiscard()
    {
        upload?.Cancel();
        ConfirmingDiscard = false;
    }

    /// <summary>Keep Editing: dismisses the confirmation.</summary>
    public void KeepEditing() => ConfirmingDiscard = false;

    /// <summary>Validates, then sends; failure keeps every field and shows a readable error.</summary>
    /// <returns>Completes when the attempt ends (sent, failed or discarded).</returns>
    public async Task SubmitAsync()
    {
        if (!IsEditing) return;
        if (draft.Problem is { } problem)
        {
            Error = problem.Message();
            return;
        }
        var submission = draft.Submission(FeedbackSubmission.PlatformWindows, appVersion, clientInfo);
        using var cts = new CancellationTokenSource();
        upload = cts;
        Error = null;
        ConfirmingDiscard = false;
        UploadFraction = 0;
        Phase = FeedbackPhase.Submitting;
        var progress = new UploadProgress(fraction =>
        {
            if (cts.IsCancellationRequested || phase != FeedbackPhase.Submitting || upload != cts) return;
            var clamped = double.IsNaN(fraction) ? 0 : Math.Clamp(fraction, 0, 1);
            if (clamped > uploadFraction) UploadFraction = clamped;
        });
        try
        {
            var accepted = await send(submission, progress, cts.Token);
            if (cts.IsCancellationRequested) return;
            UploadFraction = 1;
            Job = accepted;
            ConfirmingDiscard = false;
            Phase = FeedbackPhase.Filing;
            var final = await FollowAsync(accepted, cts.Token);
            if (cts.IsCancellationRequested) return;
            Job = final;
            if (final.State == FeedbackJobState.Failed)
            {
                Fail(FeedbackException.FilingFailed(Kind).Message);
                return;
            }
            Phase = FeedbackPhase.Sent;
            OnPropertyChanged(nameof(SuccessMessage));
        }
        catch (OperationCanceledException) when (cts.IsCancellationRequested)
        {
        }
        catch (FeedbackException failure)
        {
            Fail(failure.Message);
        }
        catch (Exception)
        {
            Fail(FeedbackException.Offline().Message);
        }
        finally
        {
            upload = null;
        }

        void Fail(string message)
        {
            if (cts.IsCancellationRequested) return;
            Phase = FeedbackPhase.Editing;
            Error = message;
        }
    }

    /// <summary>
    /// Polls an accepted job until it is filed or fails. Without an ID, after <see cref="PollTimeout"/>, or when a
    /// status read fails (expired, unknown, offline), returns the last known state so the form reports it as received.
    /// </summary>
    /// <param name="accepted">The 202 job.</param>
    /// <param name="token">Cancelled when the user closes the form.</param>
    /// <returns>Terminal job, or the last known one.</returns>
    /// <exception cref="OperationCanceledException">The user closed the form.</exception>
    private async Task<FeedbackJob> FollowAsync(FeedbackJob accepted, CancellationToken token)
    {
        if (accepted.IsTerminal || accepted.Id is not { } id) return accepted;
        var latest = accepted;
        var deadline = now() + PollTimeout;
        while (now() < deadline)
        {
            await delay(PollInterval, token);
            try
            {
                latest = await status(id, token);
            }
            catch (Exception error) when (error is not OperationCanceledException || !token.IsCancellationRequested)
            {
                return latest;
            }
            Job = latest;
            if (latest.IsTerminal) return latest;
        }
        return latest;
    }

    /// <summary>Applies a field edit while editing and clears a stale error.</summary>
    /// <param name="next">New draft.</param>
    /// <param name="property">Changed property.</param>
    private void Edit(FeedbackDraft next, string property)
    {
        if (!IsEditing || next == draft) return;
        draft = next;
        Error = null;
        OnPropertyChanged(property);
        RaiseValidity();
    }

    /// <summary>Raises <see cref="CanSubmit"/> and <see cref="ValidationMessage"/> after the draft changes.</summary>
    private void RaiseValidity()
    {
        OnPropertyChanged(nameof(CanSubmit));
        OnPropertyChanged(nameof(ValidationMessage));
    }
    #endregion

    #region Upload progress
    /// <summary>
    /// Synchronous progress sink: the sender (or the dialog's UI-thread <see cref="Progress{T}"/> wrapper) decides the
    /// thread, so tests observe each report immediately.
    /// </summary>
    /// <param name="report">Applies one reported fraction.</param>
    private sealed class UploadProgress(Action<double> report) : IProgress<double>
    {
        /// <inheritdoc />
        public void Report(double value) => report(value);
    }
    #endregion
}
#endregion
