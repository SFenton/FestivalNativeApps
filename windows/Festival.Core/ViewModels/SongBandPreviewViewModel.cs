using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Song band preview
/// <summary>
/// One band size's preview on Song Detail (web <c>SongBandLeaderboardPreview</c>, iOS <c>SongBandPreviewSection</c>): a
/// header, up to ten band rows that open Band Detail, the selected player's band highlighted in place or appended after the
/// ten, then View Full Leaderboard. Every size is filled from the page's single <c>/bands/all</c> read
/// (<see cref="SongDetailViewModel"/>); loading, empty and failed states each sit on the section's own card.
/// </summary>
public sealed partial class SongBandPreviewViewModel : ObservableObject
{
    /// <summary>Header subtitle of a size with no scores (web <c>songDetail.noScores</c>).</summary>
    public const string NoScoresText = "No scores recorded yet";

    /// <summary>Creates a section in its loading state.</summary>
    /// <param name="songId">Song.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="retry">Re-runs the page's band read (Retry).</param>
    /// <param name="time">Clock for the retry countdown.</param>
    public SongBandPreviewViewModel(string songId, BandType bandType, Func<Task> retry, TimeProvider time)
    {
        SongId = songId;
        BandType = bandType;
        Status = new ServiceStatusViewModel($"band-preview:{songId}:{TypeId}", $"{Title} scores unavailable", retry, time);
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Band size.</summary>
    public BandType BandType { get; }

    /// <summary>Service ID of the size (<c>Band_Duets</c>).</summary>
    public string TypeId => BandType.ServiceId();

    /// <summary>"Duos".</summary>
    public string Title => BandType.Label();

    /// <summary>Quick Links section ID (web <c>band-&lt;type&gt;</c>).</summary>
    public string QuickLinkId => "band-" + TypeId;

    /// <summary>Automation ID of the section header.</summary>
    public string HeaderAutomationId => "fst.song-detail.band-header." + TypeId;

    /// <summary>Automation ID of the empty-state text.</summary>
    public string EmptyAutomationId => "fst.song-detail.band-empty." + TypeId;

    /// <summary>Automation ID of the inline Retry button.</summary>
    public string RetryAutomationId => "fst.song-detail.band-retry." + TypeId;

    /// <summary>Automation ID of the full-leaderboard button.</summary>
    public string ViewAllAutomationId => "fst.song-detail.band-view-all." + TypeId;

    /// <summary>
    /// Accessible name of the full-leaderboard button: the visible label first, then the band size (WCAG 2.5.3 label in
    /// name, as the instrument cards): "View Full Leaderboard, Duos".
    /// </summary>
    public string ViewAllName => RankingViewAll.Name(LeaderboardPreviewViewModel.ViewAllText, Title);

    /// <summary>This song's full band leaderboard for the size.</summary>
    public AppRoute FullRoute => new AppRoute.SongBandLeaderboard(SongId, TypeId);

    /// <summary>Body of an empty section (web <c>songDetail.noBandScoresSubtitle</c>).</summary>
    public string EmptyText => $"When {Title} scores are submitted for this song, they will show up here on the next leaderboard update.";

    /// <summary>Inline failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError), nameof(ShowPlaceholder))]
    private LoadState state = LoadState.Loading;

    /// <summary>Top rows, then the selected player's band when it ranks outside them.</summary>
    [ObservableProperty]
    private List<SongBandPreviewRow> rows = [];

    /// <summary>"No scores recorded yet", "1,234 bands" when the service allows totals, or empty.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HeaderName))]
    private string subtitle = "";

    /// <summary>Accessible name of the section: "Duos, 1,234 bands".</summary>
    public string HeaderName => Subtitle.Length > 0 ? $"{Title}, {Subtitle}" : Title;

    /// <summary>Whether loading.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether rows and View Full Leaderboard show.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the section's own card shows (loading, empty or failed).</summary>
    public bool ShowPlaceholder => State != LoadState.Loaded;

    /// <summary>Whether the empty text shows.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the inline error shows.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Back to the spinner (a reload for Retry or another selected player).</summary>
    public void BeginLoading()
    {
        Status.Clear();
        Rows = [];
        Subtitle = "";
        State = LoadState.Loading;
    }

    /// <summary>Shows this size's rows from the <c>/bands/all</c> response.</summary>
    /// <param name="preview">This size's preview (empty when the service omitted it).</param>
    /// <param name="showTotals">Whether the service allows entry totals.</param>
    public void Apply(SongBandPreview preview, bool showTotals)
    {
        List<SongBandPreviewRow> rows =
            [.. preview.Entries.Select((e, i) => new SongBandPreviewRow(new SongBandRow(e), TypeId, i, preview.IsSelected(e), false))];
        if (preview.FooterEntry is { } footer) rows.Add(new SongBandPreviewRow(new SongBandRow(footer), TypeId, rows.Count, true, true));
        Subtitle = rows.Count == 0 ? NoScoresText : showTotals && preview.TotalEntries > 0
            ? string.Create(System.Globalization.CultureInfo.CurrentCulture, $"{preview.TotalEntries:N0} {(preview.TotalEntries == 1 ? "band" : "bands")}")
            : "";
        Status.Clear();
        Rows = rows;
        State = rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
    }

    /// <summary>Shows the inline error with Retry.</summary>
    /// <param name="error">Failure.</param>
    public void Fail(FestivalApiException error)
    {
        Rows = [];
        Subtitle = "";
        Status.Report(error);
        State = LoadState.Failed;
    }
}

/// <summary>A band row in a Song Detail band preview.</summary>
/// <param name="Band">Shared song band row (members, rank, score, accuracy, stars, Band Detail route).</param>
/// <param name="TypeId">Band size service ID, part of the automation ID.</param>
/// <param name="Index">Zero-based position in the section.</param>
/// <param name="IsSelected">Whether this is the selected player's band (purple highlight).</param>
/// <param name="IsFooter">Whether it is the selected band appended after the top rows.</param>
public sealed record SongBandPreviewRow(SongBandRow Band, string TypeId, int Index, bool IsSelected, bool IsFooter)
{
    /// <summary>UIA automation ID (<c>fst.song-detail.band-row.&lt;type&gt;.&lt;i&gt;</c> or <c>band-selected.&lt;type&gt;</c>, as Android).</summary>
    public string AutomationId => IsFooter ? "fst.song-detail.band-selected." + TypeId : $"fst.song-detail.band-row.{TypeId}.{Index}";

    /// <summary>
    /// Screen-reader summary in visual order (rank, members with their instruments, team score, FC, accuracy, stars),
    /// prefixed "Your band, " for the selected player's band.
    /// </summary>
    public string Announcement => (IsSelected ? "Your band, " : "") + Band.PreviewAnnouncement;

    /// <summary>Band Detail route.</summary>
    public AppRoute Route => Band.Route;

    /// <summary>Members with icons.</summary>
    public List<BandMemberRow> Members => Band.Members;

    /// <summary><c>#1</c>.</summary>
    public string Rank => Band.Rank;

    /// <summary>Grouped team score.</summary>
    public string Score => Band.Score;

    /// <summary>Accuracy text, empty when absent.</summary>
    public string Accuracy => Band.Accuracy;

    /// <summary>Whether an accuracy pill shows.</summary>
    public bool HasAccuracy => Band.HasAccuracy;

    /// <summary>Whether the FC badge shows.</summary>
    public bool IsFullCombo => Band.IsFullCombo;

    /// <summary>Stars (0 when missing).</summary>
    public int StarCount => Band.StarCount;
}
#endregion
