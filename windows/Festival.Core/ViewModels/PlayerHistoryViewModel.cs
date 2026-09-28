using System.ComponentModel;
using System.Globalization;
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
/// Selected player's score changes for one song and chart (<c>/songs/:songId/:instrument/history</c>), with the web's
/// sort modes and a native score-over-time chart. Re-reads when the selected player changes.
/// </summary>
public sealed partial class PlayerHistoryViewModel : ObservableObject, IDisposable
{
    private readonly FestivalSession session;
    private CancellationTokenSource? load;
    private List<ScoreHistoryEntry> entries = [];
    private string? lastAccount;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">History route.</param>
    public PlayerHistoryViewModel(FestivalSession session, AppRoute.PlayerHistory route)
    {
        this.session = session;
        SongId = route.SongId;
        Instrument = route.Instrument;
        lastAccount = session.SelectedPlayer?.AccountId;
        Status = new ServiceStatusViewModel("player-history", "History unavailable", LoadAsync, session.Time);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Page title.</summary>
    public string Title => "Score History";

    /// <summary>"Song · Lead", once the catalogue resolves.</summary>
    [ObservableProperty]
    private string subtitle = "";

    /// <summary>Instrument icon file.</summary>
    public string IconFile => Instrument.IconFile(session.FindSong(SongId)?.UsesKeyboardIcon == true);

    /// <summary>Instrument name.</summary>
    public string InstrumentLabel => Instrument.Label();

    /// <summary>Phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowError), nameof(ShowMessage), nameof(Message),
        nameof(MessageTitle), nameof(CanRetryMessage))]
    private PlayerHistoryPhase phase = PlayerHistoryPhase.Loading;

    /// <summary>Sorted rows.</summary>
    [ObservableProperty]
    private List<ScoreHistoryRow> rows = [];

    /// <summary>Score-over-time chart (two or more dated rows).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasChart))]
    private ScoreHistoryChartModel? chart;

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

    /// <summary>Rows and chart.</summary>
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

    /// <summary>Whether the chart is shown.</summary>
    public bool HasChart => Chart is not null;

    /// <summary>Sort button text, e.g. "Score ↓".</summary>
    public string SortLabel => $"{SortMode.Label()} {(SortAscending ? "↑" : "↓")}";

    /// <summary>Sort button accessible name.</summary>
    public string SortAnnouncement => $"Sort by {SortMode.Label()}, {(SortAscending ? "ascending" : "descending")}";

    /// <summary>Loads the selected player's history.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        load?.Cancel();
        var token = (load = new CancellationTokenSource()).Token;
        ResolveSubtitle();
        if (session.SelectedPlayer is not { } player)
        {
            Show(PlayerHistoryPhase.NoPlayer, []);
            return;
        }
        Show(PlayerHistoryPhase.Loading, []);
        try
        {
            var read = await session.Api.GetPlayerHistoryAsync(player.AccountId, SongId, Instrument, token);
            if (token.IsCancellationRequested) return;
            Status.Clear();
            var matching = read.Entries(SongId, Instrument);
            Show(read.State switch
            {
                PlayerHistoryState.Unregistered => PlayerHistoryPhase.Unregistered,
                PlayerHistoryState.Syncing => PlayerHistoryPhase.Syncing,
                _ => matching.Count == 0 ? PlayerHistoryPhase.Empty : PlayerHistoryPhase.Loaded,
            }, read.State == PlayerHistoryState.Available ? matching : []);
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
        try
        {
            await session.LoadCatalogAsync(cancellationToken: token);
            ResolveSubtitle();
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException)
        {
            // The subtitle falls back to the chart name.
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

    /// <summary>Applies a phase and rows.</summary>
    /// <param name="next">Phase.</param>
    /// <param name="loaded">Rows.</param>
    private void Show(PlayerHistoryPhase next, List<ScoreHistoryEntry> loaded)
    {
        entries = loaded;
        Chart = ScoreHistoryChartModel.Build(entries);
        Resort();
        Phase = next;
    }

    /// <summary>Rebuilds rows in the current order; the personal best follows the sort.</summary>
    private void Resort()
    {
        var sorted = PlayerScoreHistorySort.Sorted(entries, SortMode, SortAscending);
        var best = PlayerScoreHistorySort.HighScoreIndex(sorted);
        Rows = [.. sorted.Select((e, i) => new ScoreHistoryRow(e, i == best))];
    }

    /// <summary>"Song · Lead".</summary>
    private void ResolveSubtitle()
    {
        Subtitle = session.FindSong(SongId) is { } song ? $"{song.Title} · {InstrumentLabel}" : InstrumentLabel;
        OnPropertyChanged(nameof(IconFile));
    }

    /// <summary>Per-entity reset: re-read when the selected player changes.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings) || session.SelectedPlayer?.AccountId == lastAccount) return;
        lastAccount = session.SelectedPlayer?.AccountId;
        _ = LoadAsync();
    }
}

/// <summary>One history row.</summary>
/// <param name="Entry">Wire row.</param>
/// <param name="IsHighScore">Highest score in the displayed rows.</param>
public sealed record ScoreHistoryRow(ScoreHistoryEntry Entry, bool IsHighScore)
{
    /// <summary>Date text.</summary>
    public string Date => Entry.DateText;

    /// <summary>Score.</summary>
    public string Score => ScoreFormatting.Score(Entry.NewScore);

    /// <summary>"date · Season 9" second line.</summary>
    public string Detail => Season.Length > 0 ? $"{Date} · {Season}" : Date;

    /// <summary>Accuracy, or empty.</summary>
    public string Accuracy => ScoreFormatting.Accuracy(Entry.Accuracy);

    /// <summary>Whether accuracy is known.</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Full combo.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>"Season 9", or empty.</summary>
    public string Season => Entry.Season is { } s ? "Season " + s.ToString(CultureInfo.CurrentCulture) : "";

    /// <summary>Service stars (0 when missing), drawn as star images by the row.</summary>
    public int StarCount => Entry.Stars ?? 0;

    /// <summary>Screen-reader text.</summary>
    public string Announcement =>
        string.Join(", ", new[]
        {
            Date, $"score {Score}", HasAccuracy ? $"accuracy {Accuracy}" : "", IsFullCombo ? "full combo" : "",
            Entry.Stars is { } s ? $"{s} stars" : "", Season, IsHighScore ? "personal best" : "",
        }.Where(p => p.Length > 0));
}
#endregion
