using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Festival.Core.Domain;

namespace Festival.Core.ViewModels;

#region Song band leaderboard
/// <summary>
/// <c>/songs/:songId/bands/:bandType</c>: a song's band scores for one band size, 25 per page, with an in-place
/// band-size switcher (web <c>SongBandLeaderboardPage</c>). Rows open Band Detail with the safe type/team-key lookup. The
/// selected player's best band of the size is highlighted in place and pinned as a footer row that follows the solo
/// board's rule (pattern <c>leaderboard-row</c> R7, issue #307): it jumps to its page when that page isn't shown, else
/// opens Band Detail.
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
        Pager = new BandsPagerViewModel(GoToPageAsync) { Page = Math.Max(1, route.Page) };
        RevealSelected = route.RevealSelected;
        Status = new ServiceStatusViewModel("song-bands:" + SongId, "Failed to load band leaderboard", LoadAsync, session.Time);
        LoadSwap = new LoadSwap(session.Time);
        LoadSwap.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(ShowRows));
            OnPropertyChanged(nameof(ShowEmpty));
            OnPropertyChanged(nameof(ShowError));
        };
    }

    /// <summary>Requested song.</summary>
    public string SongId { get; }

    /// <summary>
    /// Whether the view should bring the selected band's row into view after the next load (an arrival from Song Detail's
    /// appended row, or a footer jump); the view clears it once handled.
    /// </summary>
    public bool RevealSelected { get; set; }

    /// <summary>Paging state.</summary>
    public BandsPagerViewModel Pager { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Rows/content load-swap gate.</summary>
    public LoadSwap LoadSwap { get; }

    /// <summary>Whether load-swap motion is allowed; the app layer supplies <c>Motion.Allowed</c>.</summary>
    public Func<bool> AnimateLoadSwaps { get; set; } = () => false;

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

    /// <summary>The selected player's best band of this size, pinned below the list, or <see langword="null"/>.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowSpotlight))]
    [NotifyCanExecuteChangedFor(nameof(JumpCommand))]
    private SongBandSpotlightRow? spotlight;

    /// <summary>Whether the pinned footer row shows.</summary>
    public bool ShowSpotlight => Spotlight is not null;

    /// <summary>Whether the footer row jumps to its page (the shown page doesn't contain it).</summary>
    public bool CanJump => Spotlight?.Action.Jumps == true;

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
    public bool IsLoading => LoadSwap.IsLoading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded && LoadSwap.ContentVisible;

    /// <summary>Whether the empty state is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty && LoadSwap.ContentVisible;

    /// <summary>Whether the failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed && LoadSwap.ContentVisible;

    /// <summary>Switching size returns to page one.</summary>
    /// <param name="value">New size.</param>
    partial void OnBandTypeChanged(BandType value)
    {
        Pager.Page = 1;
        RevealSelected = false;
        _ = LoadAsync();
    }

    /// <summary>Loads the song header (best effort) and the current page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var requested = ++version;
        var (type, page) = (BandType, Pager.Page);
        var swap = LoadSwap.BeginReloadAsync(AnimateLoadSwaps(), State is LoadState.Loaded or LoadState.Empty or LoadState.Failed && LoadSwap.ContentVisible);
        if (State is LoadState.Idle) State = LoadState.Loading;
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
            var board = await session.Api.GetSongBandLeaderboardAsync(SongId, type, page, PageSize, session.SelectedPlayer?.AccountId);
            if (requested != version) return;
            var pages = board.PageCount(PageSize);
            if (page > pages)
            {
                Pager.PageCount = pages;
                Pager.Page = pages;
                await LoadAsync();
                return;
            }
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Clear();
                Population = board.Population;
                Pager.PageCount = pages;
                Rows = [.. board.Entries.Select(e => new SongBandRow(e) { IsSelected = board.IsSelected(e) })];
                Spotlight = board.SelectedEntry is { } selected
                    ? new SongBandSpotlightRow(selected, SelectedRowAction.Footer(selected.Rank,
                        board.Entries.Any(board.IsSelected) || LeaderboardPaging.PageForRank(selected.Rank, PageSize) == page, PageSize))
                    : null;
                State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
            }, AnimateLoadSwaps());
        }
        catch (FestivalApiException error)
        {
            if (requested != version) return;
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Report(error);
                Spotlight = null;
                State = LoadState.Failed;
            }, AnimateLoadSwaps());
        }
    }

    /// <summary>Footer row: loads the page containing the selected band's rank and asks the view to reveal it.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanJump))]
    private Task JumpAsync()
    {
        if (Spotlight?.Action.JumpPage is not { } page) return Task.CompletedTask;
        RevealSelected = true;
        return GoToPageAsync(page);
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

    /// <summary>Whether this is the selected player's band (purple highlight, web <c>isPlayer</c>).</summary>
    public bool IsSelected { get; init; }

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
                                  (StarRating.From(Entry.Stars) is { } stars ? $", {stars.Announcement}" : "");

    /// <summary>
    /// Song Band Leaderboard row name in visual order (rank, each member's name, instruments and per-song score, then the
    /// team footer), so the single Narrator stop carries everything the card shows.
    /// </summary>
    public string PageAnnouncement =>
        (IsSelected ? "Your band, " : "") + $"Rank {Entry.Rank}. " +
        string.Concat(Members.Select(m => $"{m.Name}, {m.InstrumentsText}" + (m.HasScore ? $", {m.ScoreText} points" : "") + ". ")) +
        $"Team score {Score} points" + (IsFullCombo ? ", full combo" : "") + (HasAccuracy ? $", {Accuracy} accuracy" : "") +
        (StarRating.From(Entry.Stars) is { } stars ? $", {stars.Announcement}" : "");
}

/// <summary>
/// The selected player's band pinned below a song band board, drawn by the same <c>LeaderboardEntryRow</c> as the solo
/// board's pinned row (pattern <c>leaderboard-row</c> R5/R7, Apple <c>LeaderboardEntry(selectedBand:)</c>).
/// </summary>
/// <param name="Entry">Wire row with its board rank.</param>
/// <param name="Action">Jump to its page, or open Band Detail when it is on the shown page.</param>
public sealed record SongBandSpotlightRow(SongBandLeaderboardEntry Entry, SelectedRowAction Action) : ILeaderboardScoreRow
{
    /// <inheritdoc />
    public string RankText => Entry.Rank > 0 ? BandFormatting.Rank(Entry.Rank) : "\u2014";

    /// <inheritdoc />
    public string Name => Entry.MembersLabel;

    /// <inheritdoc />
    public bool IsSelected => true;

    /// <inheritdoc />
    public LeaderboardSection? Section => null;

    /// <summary>Band Detail with the safe lookup keys; a jump is the view's command (<see cref="Action"/>).</summary>
    public AppRoute? Route => new AppRoute.Band(Entry.BandId.Length > 0 ? Entry.BandId : Entry.TeamKey, Entry.BandType, Entry.TeamKey);

    /// <inheritdoc />
    public string AutomationId => "fst.song-band-leaderboard.spotlight-footer";

    /// <inheritdoc />
    public string Season => "";

    /// <inheritdoc />
    public string Score => BandFormatting.Count(Entry.Score);

    /// <inheritdoc />
    public string Accuracy => Entry.Accuracy is > 0 ? BandFormatting.Accuracy(Entry.Accuracy) : "";

    /// <inheritdoc />
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <inheritdoc />
    public double AccuracyValue => Entry.Accuracy ?? 0;

    /// <inheritdoc />
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <inheritdoc />
    public string BadgeAutomationId => "fst.score.accuracy.song-band-spotlight";

    /// <inheritdoc />
    public int StarCount => Entry.Stars ?? 0;

    /// <summary>"Your band's rank, 29th. Jump to your band's position. …" then members and score details.</summary>
    public string Announcement =>
        (Entry.Rank > 0 ? $"Your band's rank, {RankingFormatting.Ordinal(Entry.Rank)}. " : "Your band. ") +
        $"{Action.Destination(SelectedRowSubject.Band)}. {Name}, {Score} points" +
        (HasAccuracy ? $", {Accuracy} accuracy" : "") + (IsFullCombo ? ", full combo" : "") +
        (StarRating.From(Entry.Stars) is { } stars ? $", {stars.Announcement}" : "");
}
#endregion
