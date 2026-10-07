using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Player history
/// <summary>What the score-history page shows.</summary>
public enum PlayerHistoryPhase
{
    /// <summary>No player selected: no request is made.</summary>
    NoPlayer,
    /// <summary>Loading.</summary>
    Loading,
    /// <summary>HTTP 404: registered users only (never "no history").</summary>
    Unregistered,
    /// <summary>HTTP 202: still syncing.</summary>
    Syncing,
    /// <summary>No rows for this chart.</summary>
    Empty,
    /// <summary>Failed; see <see cref="PlayerHistoryViewModel.Status"/>.</summary>
    Failed,
    /// <summary>Rows shown.</summary>
    Loaded,
}

/// <summary>
/// Selected player's every score for one song and chart (<c>/songs/:songId/:instrument/history</c>, web
/// <c>PlayerHistoryPage</c>), opened by Song Detail's "View All Scores" (view-all-cta R8, issue #324): the song-first
/// header, then shared leaderboard rows with the web's sort modes (default Score, descending) and the personal best
/// highlighted wherever the sort puts it. Re-reads when the selected player changes; re-filters when the invalid-score
/// settings change.
/// </summary>
public sealed partial class PlayerHistoryViewModel : ObservableObject, IDisposable
{
    /// <summary>Automation-ID prefix of the page's rows (Song Detail's top five use their own).</summary>
    public const string RowIdPrefix = "fst.history.row.";

    private readonly FestivalSession session;
    private CancellationTokenSource? load;
    private List<ScoreHistoryEntry> entries = [];
    private string? lastAccount;
    private (bool Filter, double Leeway) lastFilter;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">History route.</param>
    public PlayerHistoryViewModel(FestivalSession session, AppRoute.PlayerHistory route)
    {
        this.session = session;
        SongId = route.SongId;
        Instrument = route.Instrument;
        Song = session.FindSong(SongId);
        lastAccount = session.SelectedPlayer?.AccountId;
        lastFilter = (session.Settings.FilterInvalidScores, session.Settings.Leeway);
        Status = new ServiceStatusViewModel("player-history", "History unavailable", LoadAsync, session.Time);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Resolved song (header and invalid-score filtering).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(Subtitle), nameof(IconFile), nameof(Announcement))]
    private Song? song;

    /// <summary>Header title: the song (song-leaderboard-header R1; web <c>SongInfoHeader</c>).</summary>
    public string Title => Song?.Title ?? "";

    /// <summary>Header subtitle (artist).</summary>
    public string Subtitle => Song?.Artist ?? "";

    /// <summary>Chart icon (keys variant for keyboard songs).</summary>
    public string IconFile => Instrument.IconFile(Song?.UsesKeyboardIcon == true);

    /// <summary>Instrument name (the header's board line).</summary>
    public string InstrumentLabel => Instrument.Label();

    /// <summary>Page announcement: <c>Through the Fire and Flames, Lead score history</c>.</summary>
    public string Announcement => Title.Length > 0 ? $"{Title}, {InstrumentLabel} score history" : $"{InstrumentLabel} score history";

    /// <summary>Phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowError), nameof(ShowMessage), nameof(Message),
        nameof(MessageTitle), nameof(CanRetryMessage))]
    private PlayerHistoryPhase phase = PlayerHistoryPhase.Loading;

    /// <summary>Every score in the chosen order, as shared leaderboard rows (web <c>LeaderboardEntry</c>).</summary>
    [ObservableProperty]
    private List<ScoreHistoryListRow> rows = [];

    /// <summary>Sort key (default Score).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SortLabel), nameof(SortAnnouncement))]
    private PlayerScoreSortMode sortMode = PlayerScoreSortMode.Score;

    /// <summary>Sort direction (default descending).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SortLabel), nameof(SortAnnouncement))]
    private bool sortAscending;

    /// <summary>Spinner.</summary>
    public bool IsLoading => Phase == PlayerHistoryPhase.Loading;

    /// <summary>Rows and sort.</summary>
    public bool ShowRows => Phase == PlayerHistoryPhase.Loaded;

    /// <summary>Service status.</summary>
    public bool ShowError => Phase == PlayerHistoryPhase.Failed;

    /// <summary>Informational message (no player, unregistered, syncing, empty).</summary>
    public bool ShowMessage => Phase is PlayerHistoryPhase.NoPlayer or PlayerHistoryPhase.Unregistered or PlayerHistoryPhase.Syncing or PlayerHistoryPhase.Empty;

    /// <summary>Whether a retry is offered with the message (syncing only).</summary>
    public bool CanRetryMessage => Phase == PlayerHistoryPhase.Syncing;

    /// <summary>Message heading.</summary>
    public string MessageTitle => Phase switch
    {
        PlayerHistoryPhase.NoPlayer => "No Player Selected",
        PlayerHistoryPhase.Unregistered => "History Unavailable",
        PlayerHistoryPhase.Syncing => "Still Syncing",
        _ => "No History Yet",
    };

    /// <summary>Message body.</summary>
    public string Message => Phase switch
    {
        PlayerHistoryPhase.NoPlayer => "Select a player profile to see score history.",
        PlayerHistoryPhase.Unregistered => "Score history is only available for registered users.",
        PlayerHistoryPhase.Syncing => "This player's score history is still being prepared. Try again shortly.",
        PlayerHistoryPhase.Empty => $"No score history for {InstrumentLabel} on this song.",
        _ => "",
    };

    /// <summary>Sort button text, e.g. "Score ↓".</summary>
    public string SortLabel => $"{SortMode.Label()} {(SortAscending ? "↑" : "↓")}";

    /// <summary>Sort button accessible name.</summary>
    public string SortAnnouncement => $"Sort by {SortMode.Label()}, {(SortAscending ? "ascending" : "descending")}";

    /// <summary>Loads the catalogue song and the selected player's history for the chart.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        load?.Cancel();
        var token = (load = new CancellationTokenSource()).Token;
        if (session.SelectedPlayer is not { } player)
        {
            Show(PlayerHistoryPhase.NoPlayer, []);
            await ResolveSongAsync(token);
            return;
        }
        Show(PlayerHistoryPhase.Loading, []);
        await ResolveSongAsync(token);
        if (token.IsCancellationRequested) return;
        try
        {
            var read = await session.Api.GetPlayerHistoryAsync(player.AccountId, SongId, Instrument, token);
            if (token.IsCancellationRequested) return;
            Status.Clear();
            var matching = read.State == PlayerHistoryState.Available ? read.Entries(SongId, Instrument) : [];
            Show(read.State switch
            {
                PlayerHistoryState.Unregistered => PlayerHistoryPhase.Unregistered,
                PlayerHistoryState.Syncing => PlayerHistoryPhase.Syncing,
                _ => PlayerHistoryPhase.Loaded,
            }, matching);
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (token.IsCancellationRequested) return;
            Show(PlayerHistoryPhase.Failed, []);
            Status.Report(error);
        }
    }

    /// <summary>Chooses a sort key (keeps the direction).</summary>
    /// <param name="mode">Key.</param>
    [RelayCommand]
    public void SortBy(PlayerScoreSortMode mode) => SortMode = mode;

    /// <summary>Flips the direction.</summary>
    [RelayCommand]
    public void ToggleDirection() => SortAscending = !SortAscending;

    /// <summary>Restores Score, descending.</summary>
    [RelayCommand]
    public void ResetSort()
    {
        SortMode = PlayerScoreSortMode.Score;
        SortAscending = false;
    }

    /// <summary>Stops listening.</summary>
    public void Dispose()
    {
        load?.Cancel();
        session.PropertyChanged -= OnSessionChanged;
    }

    /// <summary>Re-sorts on mode change.</summary>
    /// <param name="value">Mode.</param>
    partial void OnSortModeChanged(PlayerScoreSortMode value) => Resort();

    /// <summary>Re-sorts on direction change.</summary>
    /// <param name="value">Direction.</param>
    partial void OnSortAscendingChanged(bool value) => Resort();

    /// <summary>Resolves the song from the catalogue (the header and the invalid-score filter need it).</summary>
    /// <param name="token">Cancellation.</param>
    /// <returns>Completes when resolved, or when the catalogue read failed (the header stays on the chart name).</returns>
    private async Task ResolveSongAsync(CancellationToken token)
    {
        if (Song is not null) return;
        try
        {
            await session.LoadCatalogAsync(cancellationToken: token);
            if (!token.IsCancellationRequested) Song = session.FindSong(SongId);
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException)
        {
            // The header falls back to the chart name; scores still show (unfiltered without a song).
        }
    }

    /// <summary>Applies a phase and the chart's raw rows.</summary>
    /// <param name="next">Phase (Loaded becomes Empty when nothing survives the invalid-score filter).</param>
    /// <param name="loaded">Rows.</param>
    private void Show(PlayerHistoryPhase next, List<ScoreHistoryEntry> loaded)
    {
        entries = loaded;
        Resort();
        Phase = next == PlayerHistoryPhase.Loaded && Rows.Count == 0 ? PlayerHistoryPhase.Empty : next;
    }

    /// <summary>
    /// Rebuilds rows in the current order after the invalid-score filter (web <c>filterHistory</c>); the personal best
    /// follows the sort (<see cref="PlayerScoreHistorySort.HighScoreIndex"/>) and every row shares one set of columns.
    /// </summary>
    private void Resort()
    {
        var kept = SongScoreHistory.FilterInvalid(entries, Song, session.Settings.FilterInvalidScores, session.Settings.Leeway);
        var points = SongScoreHistory.Points(kept, Instrument);
        var sorted = PlayerScoreHistorySort.Sorted(points.Select(p => p.Entry), SortMode, SortAscending);
        var best = PlayerScoreHistorySort.HighScoreIndex(sorted);
        var rows = sorted
            .Select((e, i) => new ScoreHistoryListRow(points.First(p => ReferenceEquals(p.Entry, e)), i == best) { RowIdPrefix = RowIdPrefix })
            .ToList();
        var section = LeaderboardColumns.Measure(rows);
        Rows = [.. rows.Select(r => r with { Section = section })];
    }

    /// <summary>Per-entity reset: re-read when the selected player changes; re-filter when the invalid-score settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        if (session.SelectedPlayer?.AccountId != lastAccount)
        {
            lastAccount = session.SelectedPlayer?.AccountId;
            _ = LoadAsync();
            return;
        }
        var filter = (session.Settings.FilterInvalidScores, session.Settings.Leeway);
        if (filter == lastFilter) return;
        lastFilter = filter;
        if (Phase is not (PlayerHistoryPhase.Loaded or PlayerHistoryPhase.Empty)) return;
        Resort();
        Phase = Rows.Count == 0 ? PlayerHistoryPhase.Empty : PlayerHistoryPhase.Loaded;
    }
}
#endregion
