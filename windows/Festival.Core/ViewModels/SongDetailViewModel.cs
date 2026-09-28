using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Song detail
/// <summary>Song Detail: header, Intensity for all charted instruments, and a top-10 card per visible chart.</summary>
public sealed partial class SongDetailViewModel : ObservableObject
{
    private readonly FestivalSession session;

    /// <summary>Creates the page model for a route.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Detail route (song ID and optional initial chart).</param>
    public SongDetailViewModel(FestivalSession session, AppRoute.SongDetail route)
    {
        this.session = session;
        SongId = route.SongId;
        InitialInstrument = route.Instrument;
        Status = new ServiceStatusViewModel("song-detail", "Song unavailable", LoadAsync, session.Time);
    }

    /// <summary>Requested song.</summary>
    public string SongId { get; }

    /// <summary>Chart to bring into view first, if any.</summary>
    public Instrument? InitialInstrument { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowContent), nameof(ShowError), nameof(IsLoading))]
    private LoadState state = LoadState.Idle;

    /// <summary>Resolved song.</summary>
    [ObservableProperty]
    private Song? song;

    /// <summary>Intensity rows for every charted instrument (including Settings-hidden ones).</summary>
    [ObservableProperty]
    private List<IntensityRow> intensity = [];

    /// <summary>Leaderboard previews for visible charted instruments.</summary>
    [ObservableProperty]
    private List<LeaderboardPreviewViewModel> leaderboards = [];

    /// <summary>Whether content is shown.</summary>
    public bool ShowContent => State == LoadState.Loaded;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the page is loading.</summary>
    public bool IsLoading => State == LoadState.Loading;

    /// <summary>Resolves the song against the catalogue and builds sections.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        State = LoadState.Loading;
        try
        {
            var catalog = await session.LoadCatalogAsync();
            var found = catalog.Songs.FirstOrDefault(s => s.SongId == SongId)
                        ?? throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404);
            Status.Clear();
            Song = found;
            Intensity = InstrumentInfo.All
                .Where(found.Supports)
                .Select(i => new IntensityRow(i, found.Difficulty!.ChartedValue(i)!.Value, found.UsesKeyboardIcon))
                .ToList();
            var visible = session.Settings.VisibleInstruments;
            Leaderboards = InstrumentInfo.All
                .Where(i => visible.Contains(i) && found.Supports(i))
                .Select(i => new LeaderboardPreviewViewModel(session, found, i))
                .ToList();
            State = LoadState.Loaded;
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
        }
    }
}

/// <summary>One Intensity row: icon, meter and spoken level.</summary>
/// <param name="Instrument">Chart.</param>
/// <param name="Raw">Raw 0–6 difficulty.</param>
/// <param name="Keyboard">Whether to use the keys icon variant.</param>
public sealed record IntensityRow(Instrument Instrument, double Raw, bool Keyboard)
{
    /// <summary>Filled bars (1–7).</summary>
    public int Bars => DifficultyScale.BarsForRaw(Raw);

    /// <summary>Instrument label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Icon file name.</summary>
    public string IconFile => Instrument.IconFile(Keyboard);

    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}, {DifficultyScale.Announcement(Raw)}";
}
#endregion

#region Leaderboard preview
/// <summary>A per-chart top-10 card with its own loading, empty, error and rows states.</summary>
public sealed partial class LeaderboardPreviewViewModel : ObservableObject
{
    /// <summary>Rows in a Detail preview.</summary>
    public const int PreviewSize = 10;

    private readonly FestivalSession session;
    private bool started;

    /// <summary>Creates a card.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="song">Song.</param>
    /// <param name="instrument">Chart.</param>
    public LeaderboardPreviewViewModel(FestivalSession session, Song song, Instrument instrument)
    {
        this.session = session;
        Song = song;
        Instrument = instrument;
        Status = new ServiceStatusViewModel($"preview:{song.SongId}:{instrument.ServiceId()}", $"{instrument.Label()} unavailable", LoadAsync, session.Time);
    }

    /// <summary>Song.</summary>
    public Song Song { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Card title.</summary>
    public string Title => Instrument.Label();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile(Song.UsesKeyboardIcon);

    /// <summary>Route for the full 25-row leaderboard.</summary>
    public AppRoute FullRoute => new AppRoute.SongLeaderboard(Song.SongId, Instrument);

    /// <summary>Inline failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Rows.</summary>
    [ObservableProperty]
    private List<LeaderboardRow> rows = [];

    /// <summary>Whether loading.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether "No scores yet" is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the inline error is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Starts loading once (called when the card is realized).</summary>
    /// <returns>Load task.</returns>
    public Task EnsureLoadedAsync()
    {
        if (started) return Task.CompletedTask;
        started = true;
        return LoadAsync();
    }

    /// <summary>Reads the top ten scores.</summary>
    /// <returns>Load task.</returns>
    public async Task LoadAsync()
    {
        started = true;
        State = LoadState.Loading;
        try
        {
            var board = await session.Api.GetLeaderboardAsync(Song.SongId, Instrument, 1, PreviewSize);
            Rows = board.Entries.Select(e => new LeaderboardRow(e)).ToList();
            Status.Clear();
            State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
        }
    }
}

/// <summary>Display projection of one leaderboard entry.</summary>
/// <param name="Entry">Wire row.</param>
public sealed record LeaderboardRow(LeaderboardEntry Entry)
{
    /// <summary><c>#1</c>.</summary>
    public string Rank => ScoreFormatting.Rank(Entry.Rank);

    /// <summary>Display name, or a neutral placeholder.</summary>
    public string Name => string.IsNullOrWhiteSpace(Entry.DisplayName) ? "Unknown player" : Entry.DisplayName!;

    /// <summary>Grouped score.</summary>
    public string Score => ScoreFormatting.Score(Entry.Score);

    /// <summary>Accuracy text, <c>FC</c> suffix handled by the view.</summary>
    public string Accuracy => ScoreFormatting.Accuracy(Entry.Accuracy);

    /// <summary>Whether an accuracy value exists (hides the empty pill).</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Whether the explicit FC flag is set.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"Rank {Entry.Rank}, {Name}, {Score} points" +
                                  (Accuracy.Length > 0 ? $", {Accuracy} accuracy" : "") + (IsFullCombo ? ", full combo" : "");
}
#endregion
