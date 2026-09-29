using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region States
/// <summary>Notifications flyout states (control spec).</summary>
public enum NotificationsState
{
    /// <summary>No profile selected: prompt, no request.</summary>
    NoPlayer,
    /// <summary>First read in flight.</summary>
    Loading,
    /// <summary>Read failed; Retry.</summary>
    Failed,
    /// <summary>No rows.</summary>
    Empty,
    /// <summary>Rows loaded.</summary>
    Loaded,
}
#endregion

#region Notifications
/// <summary>
/// Title-bar bell and flyout: loads the selected player's feed (on selection, launch and each open — no polling),
/// derives unread rows from per-account seen state, and marks rows seen on activation and when the flyout closes.
/// </summary>
public sealed partial class NotificationsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly NotificationSeenStore seenStore;
    private ImprovementNotificationsEnvelope? envelope;
    private string? loadedAccount;
    private string? requestedAccount;
    private CancellationTokenSource? load;

    /// <summary>Creates the model and loads the feed for a restored player.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="seenStore">Seen-state persistence.</param>
    public NotificationsViewModel(FestivalSession session, NotificationSeenStore seenStore)
    {
        this.session = session;
        this.seenStore = seenStore;
        session.PropertyChanged += OnSessionChanged;
        state = session.HasPlayer ? NotificationsState.Loading : NotificationsState.NoPlayer;
    }

    /// <summary>Current state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(IsFailed), nameof(IsEmpty), nameof(IsLoaded), nameof(IsNoPlayer), nameof(EmptyBody))]
    private NotificationsState state;

    /// <summary>Failure text.</summary>
    [ObservableProperty]
    private string errorText = "";

    /// <summary>Unread rows ("New").</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasNew))]
    private List<NotificationRowViewModel> newItems = [];

    /// <summary>Read rows ("Older").</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasOlder))]
    private List<NotificationRowViewModel> olderItems = [];

    /// <summary>Unread count shown on the bell.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasUnread), nameof(BadgeText), nameof(BellName))]
    private int unreadCount;

    /// <summary>Whether the first read is in flight.</summary>
    public bool IsLoading => State == NotificationsState.Loading;

    /// <summary>Whether the read failed.</summary>
    public bool IsFailed => State == NotificationsState.Failed;

    /// <summary>Whether the feed is empty.</summary>
    public bool IsEmpty => State == NotificationsState.Empty;

    /// <summary>Whether rows are shown.</summary>
    public bool IsLoaded => State == NotificationsState.Loaded;

    /// <summary>Whether no player is selected.</summary>
    public bool IsNoPlayer => State == NotificationsState.NoPlayer;

    /// <summary>Whether there are unread rows.</summary>
    public bool HasNew => NewItems.Count > 0;

    /// <summary>Whether there are read rows.</summary>
    public bool HasOlder => OlderItems.Count > 0;

    /// <summary>Whether the bell shows a badge.</summary>
    public bool HasUnread => UnreadCount > 0;

    /// <summary>Badge text (capped at 99+).</summary>
    public string BadgeText => UnreadCount > 99 ? "99+" : UnreadCount.ToString(CultureInfo.InvariantCulture);

    /// <summary>Accessible bell name.</summary>
    public string BellName => UnreadCount switch
    {
        0 => "Notifications",
        1 => "Notifications, 1 unread",
        _ => $"Notifications, {UnreadCount} unread",
    };

    /// <summary>Empty-state title (web <c>notifications.empty.title</c>).</summary>
    public string EmptyTitle => "No notifications available";

    /// <summary>Empty-state body: "generated but empty" differs from "never generated".</summary>
    public string EmptyBody => envelope?.IsGenerated == false
        ? "Notifications may appear here after the next leaderboard update. Set new high scores and compete with friends to see them!"
        : "Notifications will appear here when new high scores are set or global ranks improve. Set new high scores and compete with friends to see them!";

    /// <summary>Loads (or reloads) the feed for the selected player; cancels an older read.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task RefreshAsync()
    {
        load?.Cancel();
        requestedAccount = session.SelectedPlayer?.AccountId;
        if (session.SelectedPlayer is not { } player)
        {
            envelope = null;
            loadedAccount = null;
            Apply();
            State = NotificationsState.NoPlayer;
            return;
        }
        var cts = load = new CancellationTokenSource();
        if (loadedAccount != player.AccountId)
        {
            envelope = null;
            loadedAccount = null;
            NewItems = [];
            OlderItems = [];
            UnreadCount = 0;
            State = NotificationsState.Loading;
        }
        try
        {
            var feed = await session.Api.GetPlayerNotificationsAsync(player.AccountId, cancellationToken: cts.Token);
            if (cts.IsCancellationRequested) return;
            envelope = feed;
            loadedAccount = player.AccountId;
            Apply();
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer read.
        }
        catch (FestivalApiException error)
        {
            if (cts.IsCancellationRequested) return;
            if (loadedAccount == player.AccountId) return; // Keep showing the previous feed on a failed refresh.
            envelope = null;
            ErrorText = ServiceIssue.From(error).Message;
            Apply();
            State = NotificationsState.Failed;
        }
    }

    /// <summary>Marks one row seen; the caller navigates to its destination.</summary>
    /// <param name="row">Activated row.</param>
    /// <returns>The destination, if any.</returns>
    public NotificationDestination? Activate(NotificationRowViewModel row)
    {
        if (loadedAccount is { } account && row.IsUnread)
        {
            seenStore.MarkSeen(account, [row.Id], FeedIds());
            row.IsUnread = false;
            UnreadCount = Math.Max(0, UnreadCount - 1);
        }
        if (row.Destination is NotificationDestination.Rankings rankings)
            session.UpdateSettings(s => s with { LeaderboardRankBy = rankings.RankBy });
        return row.Destination;
    }

    /// <summary>Flyout closed: every loaded row becomes seen and moves to Older next time.</summary>
    public void MarkAllSeen()
    {
        if (loadedAccount is not { } account || envelope?.Items is not { Count: > 0 } items) return;
        seenStore.MarkSeen(account, items.Select(i => i.NotificationGuid), FeedIds());
        Apply();
    }

    /// <summary>Rebuilds sections and the unread count.</summary>
    private void Apply()
    {
        var items = envelope?.Items ?? [];
        var seen = loadedAccount is { } account ? seenStore.Seen(account) : new HashSet<string>();
        var rows = items.OrderByDescending(i => i.DetectedAt)
            .Select(i => new NotificationRowViewModel(
                NotificationText.Format(i, i.SongId is { } id ? session.FindSong(id)?.Title : null, i.SongId is { } artId ? session.FindSong(artId)?.AlbumArt : null),
                !seen.Contains(i.NotificationGuid), RelativeTime(i.DetectedAt)))
            .ToList();
        NewItems = rows.Where(r => r.IsUnread).ToList();
        OlderItems = rows.Where(r => !r.IsUnread).ToList();
        UnreadCount = NewItems.Count;
        OnPropertyChanged(nameof(EmptyBody));
        if (session.HasPlayer) State = rows.Count == 0 ? NotificationsState.Empty : NotificationsState.Loaded;
    }

    /// <summary>IDs in the current feed (for pruning expired seen IDs).</summary>
    /// <returns>GUIDs.</returns>
    private IEnumerable<string> FeedIds() => envelope?.Items?.Select(i => i.NotificationGuid) ?? [];

    /// <summary>Short relative time, e.g. "5m ago", "3h ago", "2d ago", else "Sep 28".</summary>
    /// <param name="when">Detection time.</param>
    /// <returns>Label.</returns>
    internal string RelativeTime(DateTimeOffset when)
    {
        var age = session.Time.GetUtcNow() - when;
        if (age < TimeSpan.FromMinutes(1)) return "Just now";
        if (age < TimeSpan.FromHours(1)) return $"{(int)age.TotalMinutes}m ago";
        if (age < TimeSpan.FromDays(1)) return $"{(int)age.TotalHours}h ago";
        if (age < TimeSpan.FromDays(7)) return $"{(int)age.TotalDays}d ago";
        return when.ToLocalTime().ToString("MMM d", CultureInfo.GetCultureInfo("en-US"));
    }

    /// <summary>Reloads when the selected player changes; re-titles rows when the catalogue arrives.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FestivalSession.Settings) && session.SelectedPlayer?.AccountId != requestedAccount)
            _ = RefreshAsync();
        else if (e.PropertyName == nameof(FestivalSession.Catalog) && envelope is not null)
            Apply();
    }
}

/// <summary>One notification row.</summary>
public sealed partial class NotificationRowViewModel : ObservableObject
{
    /// <summary>Creates a row.</summary>
    /// <param name="presentation">Formatted text and destination.</param>
    /// <param name="isUnread">Whether it is unread.</param>
    /// <param name="timeText">Relative time.</param>
    public NotificationRowViewModel(NotificationPresentation presentation, bool isUnread, string timeText)
    {
        Presentation = presentation;
        this.isUnread = isUnread;
        TimeText = timeText;
    }

    /// <summary>Formatted content.</summary>
    public NotificationPresentation Presentation { get; }

    /// <summary>GUID.</summary>
    public string Id => Presentation.Id;

    /// <summary>Title.</summary>
    public string Title => Presentation.Title;

    /// <summary>Sentence.</summary>
    public string Message => Presentation.Message;

    /// <summary>Flag label (empty for shop songs).</summary>
    public string Flag => Presentation.Flag ?? "";

    /// <summary>Whether a flag is shown.</summary>
    public bool HasFlag => Presentation.Flag is not null;

    /// <summary>Leading album art reference, if any.</summary>
    public string? Art => Presentation.AlbumArt;

    /// <summary>Whether the leading rail shows album art.</summary>
    public bool HasArt => Presentation.AlbumArt is not null;

    /// <summary>Leading instrument icon file when there is no art ("" for none).</summary>
    public string MediaIconFile => Presentation.MediaInstrument?.IconFile() ?? "";

    /// <summary>Whether the leading rail shows an instrument icon.</summary>
    public bool HasMediaIcon => Presentation.AlbumArt is null && Presentation.MediaInstrument is not null;

    /// <summary>Relative time.</summary>
    public string TimeText { get; }

    /// <summary>Navigation target.</summary>
    public NotificationDestination? Destination => Presentation.Destination;

    /// <summary>Whether the row navigates.</summary>
    public bool HasDestination => Destination is not null;

    /// <summary>Automation ID.</summary>
    public string AutomationId => "fst.notifications.row." + Id;

    /// <summary>Unread marker.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(AccessibleName))]
    private bool isUnread;

    /// <summary>Narrator name: unread state, title, message and time.</summary>
    public string AccessibleName => (IsUnread ? "Unread. " : "") + $"{Title}. {Message} {TimeText}";
}
#endregion
