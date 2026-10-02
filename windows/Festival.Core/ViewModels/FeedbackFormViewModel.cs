using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Phase
/// <summary>Where an open feedback form is.</summary>
public enum FeedbackPhase
{
    /// <summary>Fields editable; Submit available.</summary>
    Editing,
    /// <summary>Upload in progress; fields locked.</summary>
    Submitting,
    /// <summary>Accepted by the service; only Done remains.</summary>
    Sent,
}
#endregion

#region Feedback form
/// <summary>
/// Settings → Report an Issue / Request a Feature (issue #78). One instance per open dialog; closing with unsent input
/// asks first, discarding cancels an upload, and a failure keeps every field with a readable error.
/// </summary>
public sealed class FeedbackFormViewModel : ObservableObject
{
    private readonly Func<FeedbackSubmission, CancellationToken, Task<FeedbackReceipt>> send;
    private readonly string appVersion;
    private readonly string osVersion;
    private FeedbackDraft draft;
    private FeedbackPhase phase;
    private string? error;
    private string? notice;
    private bool confirmingDiscard;
    private FeedbackReceipt? receipt;
    private CancellationTokenSource? upload;

    /// <summary>Opens a fresh form.</summary>
    /// <param name="kind">Bug or Feature.</param>
    /// <param name="send">Sends one submission (<see cref="Data.FestivalApiClient.SubmitFeedbackAsync"/> with file access).</param>
    /// <param name="appVersion">App version reported with the form.</param>
    /// <param name="osVersion">OS description reported with the form.</param>
    public FeedbackFormViewModel(
        FeedbackKind kind,
        Func<FeedbackSubmission, CancellationToken, Task<FeedbackReceipt>> send,
        string appVersion,
        string osVersion)
    {
        this.send = send;
        this.appVersion = appVersion;
        this.osVersion = osVersion;
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

    /// <summary>Progress caption while sending.</summary>
    public string SendingText => $"Sending your {Kind.Noun()}…";
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
            OnPropertyChanged(nameof(PrimaryText));
            OnPropertyChanged(nameof(CloseText));
        }
    }

    /// <summary>Whether fields are editable.</summary>
    public bool IsEditing => phase == FeedbackPhase.Editing;

    /// <summary>Whether the upload is running.</summary>
    public bool IsSubmitting => phase == FeedbackPhase.Submitting;

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

    /// <summary>Service receipt once sent.</summary>
    public FeedbackReceipt? Receipt
    {
        get => receipt;
        private set
        {
            if (!SetProperty(ref receipt, value)) return;
            OnPropertyChanged(nameof(SuccessMessage));
            OnPropertyChanged(nameof(IssueUri));
            OnPropertyChanged(nameof(HasIssueUri));
        }
    }

    /// <summary>Success text.</summary>
    public string SuccessMessage => receipt?.Message(Kind) ?? "";

    /// <summary>Created issue link (GitHub HTTPS only).</summary>
    public Uri? IssueUri => receipt?.IssueUrl is { } url && Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri : null;

    /// <summary>Whether View on GitHub shows.</summary>
    public bool HasIssueUri => IssueUri is not null;
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
    }

    /// <summary>Cancel, Esc or an outside click: whether the dialog may close now; otherwise shows the confirmation.</summary>
    /// <returns><see langword="true"/> when nothing would be lost (or the form was sent).</returns>
    public bool RequestClose()
    {
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
        var submission = draft.Submission(FeedbackSubmission.PlatformWindows, appVersion, osVersion);
        using var cts = new CancellationTokenSource();
        upload = cts;
        Error = null;
        ConfirmingDiscard = false;
        Phase = FeedbackPhase.Submitting;
        try
        {
            var result = await send(submission, cts.Token);
            if (cts.IsCancellationRequested) return;
            Receipt = result;
            ConfirmingDiscard = false;
            Phase = FeedbackPhase.Sent;
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

    /// <summary>Applies a field edit while editing and clears a stale error.</summary>
    /// <param name="next">New draft.</param>
    /// <param name="property">Changed property.</param>
    private void Edit(FeedbackDraft next, string property)
    {
        if (!IsEditing || next == draft) return;
        draft = next;
        Error = null;
        OnPropertyChanged(property);
    }
    #endregion
}
#endregion
