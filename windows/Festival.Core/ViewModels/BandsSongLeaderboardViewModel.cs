using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Song band leaderboard
/// <summary>
/// <c>/songs/:songId/bands/:bandType</c>: a song's band scores for one band size, 25 per page, with an in-place
/// band-size switcher (web <c>SongBandLeaderboardPage</c>). Rows open Band Detail with the safe type/team-key lookup.
/// </summary>
public sealed partial class SongBandLeaderboardViewModel : ObservableObject
{
    /// <summary>Rows per page.</summary>
    public const int PageSize = 25;

    private readonly FestivalSession session;
    private int version;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Route (an unknown band type falls back to Duos).</param>
    public SongBandLeaderboardViewModel(FestivalSession session, AppRoute.SongBandLeaderboard route)
    {
        this.session = session;
        SongId = route.SongId;
#pragma warning disable MVVMTK0034 // Initial value without triggering the change handler's load.
        bandType = BandTypeInfo.TryParse(route.BandType, out var parsed) ? parsed : BandType.Duets;
#pragma warning restore MVVMTK0034
        Pager = new BandsPagerViewModel(GoToPageAsync);
        Status = new ServiceStatusViewModel("song-bands:" + SongId, "Failed to load band leaderboard", LoadAsync, session.Time);
    }

    /// <summary>Requested song.</summary>
    public string SongId { get; }

    /// <summary>Paging state.</summary>
    public BandsPagerViewModel Pager { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Band sizes in switcher order.</summary>
    public List<BandType> BandTypes { get; } = [.. BandTypeInfo.All];

    /// <summary>Shown band size.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(Subtitle), nameof(EmptyMessage), nameof(BandTypeIndex), nameof(SwitcherName))]
    private BandType bandType;

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Resolved song (header and backdrop), once the catalogue is loaded.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SongTitle), nameof(SongSubtitle))]
    private Song? song;

    /// <summary>Score rows.</summary>
    [ObservableProperty]
    private List<SongBandRow> rows = [];

    /// <summary>Paging population, once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Subtitle))]
    private int? population;

    /// <summary><c>Duos Leaderboard</c>.</summary>
    public string Title => $"{BandType.Label()} Leaderboard";

    /// <summary>Song title, or the ID until resolved.</summary>
    public string SongTitle => Song?.Title ?? "";

    /// <summary>Artist · year · duration.</summary>
    public string SongSubtitle => Song?.Subtitle ?? "";

    /// <summary><c>Duos · 1,234 entries</c>.</summary>
    public string Subtitle => Population is { } count
        ? $"{BandType.Label()} · {BandFormatting.Count(count)} {(count == 1 ? "entry" : "entries")}" : BandType.Label();

    /// <summary>Empty-state body.</summary>
    public string EmptyMessage => $"No {BandType.Label()} scores have been recorded for this song yet.";

    /// <summary>Accessible name of the band-size switcher.</summary>
    public string SwitcherName => $"Band size: {BandType.Label()}";

    /// <summary>Index of <see cref="BandType"/> in <see cref="BandTypes"/> (segmented control binding).</summary>
    public int BandTypeIndex
    {
        get => (int)BandType;
        set
        {
            if (value >= 0 && value < BandTypes.Count) BandType = BandTypes[value];
        }
    }

    /// <summary>Whether a read with nothing to show is in flight.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the empty state is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Switching size returns to page one.</summary>
    /// <param name="value">New size.</param>
    partial void OnBandTypeChanged(BandType value)
    {
        Pager.Page = 1;
        _ = LoadAsync();
    }

    /// <summary>Loads the song header (best effort) and the current page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var requested = ++version;
        var (type, page) = (BandType, Pager.Page);
        State = LoadState.Loading;
        try
        {
            if (Song is null)
            {
                try
                {
                    await session.LoadCatalogAsync();
                    Song = session.FindSong(SongId);
                }
                catch (FestivalApiException)
                {
                    // The header stays empty; the board can still load.
                }
            }
            var board = await session.Api.GetSongBandLeaderboardAsync(SongId, type, page, PageSize);
            if (requested != version) return;
            var pages = board.PageCount(PageSize);
            if (page > pages)
            {
                Pager.PageCount = pages;
                Pager.Page = pages;
                await LoadAsync();
                return;
            }
            Status.Clear();
            Population = board.Population;
            Pager.PageCount = pages;
            Rows = [.. board.Entries.Select(e => new SongBandRow(e))];
            State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        }
        catch (FestivalApiException error)
        {
            if (requested != version) return;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Loads a page (pager commands).</summary>
    /// <param name="page">One-based page.</param>
    /// <returns>Load task.</returns>
    private Task GoToPageAsync(int page)
    {
        Pager.Page = Math.Clamp(page, 1, Pager.PageCount);
        return LoadAsync();
    }
}

/// <summary>One band score row: rank, members with instruments, score, accuracy, FC and stars.</summary>
public sealed record SongBandRow
{
    /// <summary>Creates a row.</summary>
    /// <param name="entry">Wire row.</param>
    public SongBandRow(SongBandLeaderboardEntry entry)
    {
        Entry = entry;
        Members = [.. entry.Members.DistinctBy(m => m.AccountId, StringComparer.Ordinal).Select(m => new BandMemberRow(m))];
    }

    /// <summary>Wire row.</summary>
    public SongBandLeaderboardEntry Entry { get; }

    /// <summary>Members with icons.</summary>
    public List<BandMemberRow> Members { get; }

    /// <summary><c>#1</c>.</summary>
    public string Rank => BandFormatting.Rank(Entry.Rank);

    /// <summary>Joined names.</summary>
    public string Names => Entry.MembersLabel;

    /// <summary>Grouped score.</summary>
    public string Score => BandFormatting.Count(Entry.Score);

    /// <summary>Accuracy text (one decimal), empty when absent.</summary>
    public string Accuracy => Entry.Accuracy is > 0 ? BandFormatting.Accuracy(Entry.Accuracy) : "";

    /// <summary>Whether an accuracy pill is shown.</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Whether the FC badge is shown.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>Service stars (0 when missing), drawn as star images by the row.</summary>
    public int StarCount => Entry.Stars ?? 0;

    /// <summary>Band Detail route with the safe lookup keys.</summary>
    public AppRoute Route => new AppRoute.Band(Entry.BandId.Length > 0 ? Entry.BandId : Entry.TeamKey, Entry.BandType, Entry.TeamKey);

    /// <summary>Automation ID (<c>fst.song-band-leaderboard.row.&lt;key&gt;:&lt;rank&gt;</c>).</summary>
    public string AutomationId => $"fst.song-band-leaderboard.row.{(Entry.BandId.Length > 0 ? Entry.BandId : Entry.TeamKey)}:{Entry.Rank}";

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"Rank {Entry.Rank}, {Names}, {Score} points" +
                                  (HasAccuracy ? $", {Accuracy} accuracy" : "") + (IsFullCombo ? ", full combo" : "") +
                                  (Entry.Stars is > 0 ? $", {Entry.Stars} stars" : "");
}
#endregion
