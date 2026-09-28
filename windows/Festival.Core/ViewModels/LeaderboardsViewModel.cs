using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Overview
/// <summary>
/// <c>/leaderboards</c>: a top-ten card per Settings-visible instrument plus one per band size, sharing a Rank By
/// metric (web <c>LeaderboardsOverviewPage.tsx</c>, Apple <c>LeaderboardsScreen</c>). Cards load independently
/// and each has its own retry; the selected player is highlighted in place or spotlighted below each card.
/// </summary>
public sealed partial class LeaderboardsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly OwnRankingReader? reader;
    private CancellationTokenSource? load;
    private string? loadedKey;
    private bool attached;

    /// <summary>Creates the overview.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="reader">Selected player's own-row reader (defaults to the public single-account read).</param>
    public LeaderboardsViewModel(FestivalSession session, OwnRankingReader? reader = null)
    {
        this.session = session;
        this.reader = reader ?? LeaderboardPreferences.DefaultReader(session);
        metric = LeaderboardPreferences.RankBy(session);
    }

    /// <summary>Metrics offered by the Rank By picker.</summary>
    public IReadOnlyList<RankingMetric> MetricOptions => RankingMetricInfo.All;

    /// <summary>Shared Rank By metric (band cards narrow it; Max Score falls back to Total Score).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MetricLabel), nameof(MetricButtonName))]
    private RankingMetric metric;

    /// <summary>Instrument cards in Settings order.</summary>
    [ObservableProperty]
    private List<RankingCardViewModel> instrumentCards = [];

    /// <summary>Band cards (Duos, Trios, Quads).</summary>
    [ObservableProperty]
    private List<BandRankingCardViewModel> bandCards = [];

    /// <summary>Picker label.</summary>
    public string MetricLabel => Metric.Label();

    /// <summary>Accessible name of the Rank By button.</summary>
    public string MetricButtonName => $"Rank by: {Metric.Label()}";

    /// <summary>Reload identity: metric, visible instruments and selected player.</summary>
    private string Key => $"{Metric.ServiceId()}|{string.Join(',', session.Settings.VisibleInstruments)}|{session.SelectedPlayer?.AccountId}";

    /// <summary>Starts following selection and Settings changes, loading if anything changed.</summary>
    /// <returns>Load task.</returns>
    public Task ActivateAsync()
    {
        if (!attached)
        {
            session.PropertyChanged += OnSessionChanged;
            attached = true;
        }
        return loadedKey == Key ? Task.CompletedTask : LoadAsync();
    }

    /// <summary>
    /// Stops following the session while another page is shown (no background reloads). An unfinished load is
    /// cancelled and repeated on the next activation; finished cards are kept.
    /// </summary>
    public void Deactivate()
    {
        if (attached) session.PropertyChanged -= OnSessionChanged;
        attached = false;
        if (InstrumentCards.Any(c => c.IsLoading) || BandCards.Any(c => c.IsLoading))
        {
            load?.Cancel();
            loadedKey = null;
        }
    }

    /// <summary>Selects a metric, persists it (web <c>saveLeaderboardRankBy</c>) and reloads.</summary>
    /// <param name="value">Metric.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectMetricAsync(RankingMetric value)
    {
        if (value == Metric && loadedKey == Key) return Task.CompletedTask;
        Metric = value;
        session.UpdateSettings(s => s with { LeaderboardRankBy = value.ServiceId() });
        return LoadAsync();
    }

    /// <summary>Rebuilds every card and loads them concurrently.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        load?.Cancel();
        load = new CancellationTokenSource();
        var token = load.Token;
        loadedKey = Key;
        var visible = session.Settings.VisibleInstruments;
        var cards = InstrumentInfo.All.Where(visible.Contains)
            .Select(i => new RankingCardViewModel(session, i, Metric, reader)).ToList();
        var bands = BandTypeInfo.All.Select(b => new BandRankingCardViewModel(session, b, Metric.ToBandMetric())).ToList();
        InstrumentCards = cards;
        BandCards = bands;
        using var gate = new SemaphoreSlim(MaxConcurrentLoads);
        await Task.WhenAll(cards.Select(c => Throttled(gate, () => c.LoadAsync(token)))
            .Concat(bands.Select(b => Throttled(gate, () => b.LoadAsync(token)))));
    }

    /// <summary>Card reads in flight at once (twelve cards would otherwise open twelve connections together).</summary>
    public const int MaxConcurrentLoads = 4;

    /// <summary>Runs one card load inside the concurrency gate.</summary>
    /// <param name="gate">Shared gate.</param>
    /// <param name="load">Card load.</param>
    /// <returns>Load task.</returns>
    private static async Task Throttled(SemaphoreSlim gate, Func<Task> load)
    {
        await gate.WaitAsync();
        try
        {
            await load();
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Reloads when the selected player or visible instruments change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FestivalSession.Settings) && loadedKey != Key) _ = LoadAsync();
    }
}
#endregion

#region Preferences
/// <summary>Persisted Rank By metric and the default own-row reader shared by the rankings pages.</summary>
public static class LeaderboardPreferences
{
    /// <summary>Saved Rank By metric (<c>AppSettings.LeaderboardRankBy</c>), coerced like <c>coerceRankingMetric</c>.</summary>
    /// <param name="session">Shared session.</param>
    /// <returns>Metric.</returns>
    public static RankingMetric RankBy(FestivalSession session) => RankingMetricInfo.Coerce(session.Settings.LeaderboardRankBy);

    /// <summary>
    /// Reads the selected player's own row through <c>GET /api/rankings/{instrument}/{accountId}</c>
    /// (pure read; 404 → unranked → <see langword="null"/>).
    /// </summary>
    /// <param name="session">Shared session.</param>
    /// <returns>Reader.</returns>
    public static OwnRankingReader DefaultReader(FestivalSession session) => async (instrument, accountId, cancellationToken) =>
        (await session.Api.GetPlayerInstrumentRankingAsync(instrument, accountId, cancellationToken)).Ranking;
}
#endregion

#region Instrument card
/// <summary>One instrument's top-ten card with loading, empty, failed and rows states plus the selected-player spotlight.</summary>
public sealed partial class RankingCardViewModel : ObservableObject
{
    private readonly FestivalSession session;

    /// <summary>Creates a card.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="instrument">Board.</param>
    /// <param name="metric">Rank By metric.</param>
    /// <param name="reader">Own-row reader.</param>
    public RankingCardViewModel(FestivalSession session, Instrument instrument, RankingMetric metric, OwnRankingReader? reader)
    {
        this.session = session;
        Instrument = instrument;
        Metric = metric;
        Status = new ServiceStatusViewModel($"leaderboards.{instrument.ServiceId()}", $"{instrument.Label()} unavailable",
            () => LoadAsync(), session.Time);
        Spotlight = new RankingSpotlightViewModel(instrument, reader, session.Time, $"leaderboards.spotlight.{instrument.ServiceId()}");
    }

    /// <summary>Board.</summary>
    public Instrument Instrument { get; }

    /// <summary>Displayed metric.</summary>
    public RankingMetric Metric { get; }

    /// <summary>Card title.</summary>
    public string Title => Instrument.Label();

    /// <summary>Metric subtitle.</summary>
    public string Subtitle => Metric.Label();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Card automation ID.</summary>
    public string AutomationId => "fst.leaderboards.card." + Instrument.ServiceId();

    /// <summary>"View All" automation ID.</summary>
    public string ViewAllAutomationId => AutomationId + ".view-all";

    /// <summary>Spotlight automation ID (<c>…spotlight</c>, <c>.loading</c>, <c>.unranked</c>).</summary>
    public string SpotlightAutomationId => AutomationId + ".spotlight";

    /// <summary>Accessible name of "View All".</summary>
    public string ViewAllName => $"View all {Instrument.Label()} rankings";

    /// <summary>Full Rankings route for this board and metric.</summary>
    public AppRoute ViewAllRoute => new AppRoute.FullRankings(Instrument, Metric.ServiceId());

    /// <summary>Inline failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Selected-player spotlight.</summary>
    public RankingSpotlightViewModel Spotlight { get; }

    /// <summary>Lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Top rows.</summary>
    [ObservableProperty]
    private List<RankingRowViewModel> rows = [];

    /// <summary>Whether the skeleton is shown.</summary>
    public bool IsLoading => State is LoadState.Idle or LoadState.Loading;

    /// <summary>Whether rows (and View All) are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the empty text is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the inline failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Empty text.</summary>
    public string EmptyText => $"No ranked {Instrument.Label()} players yet.";

    /// <summary>Loads the top ten, then the spotlight when the selected player is not among them.</summary>
    /// <param name="cancellationToken">Cancelled by a newer overview load.</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        State = LoadState.Loading;
        List<AccountRankingEntry> entries;
        try
        {
            var board = await session.Api.GetRankingsAsync(Instrument, Metric, 1, LeaderboardPaging.CardSize, cancellationToken);
            entries = board.Entries;
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
            return;
        }
        Status.Clear();
        var selected = session.SelectedPlayer?.AccountId;
        Rows = entries.Select(e => new RankingRowViewModel(e, Metric, RankingSpotlight.SameAccount(e.AccountId, selected))).ToList();
        State = entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        Spotlight.Apply(selected, entries, Metric, 1, LeaderboardPaging.CardSize);
        await Spotlight.EnsureLoadedAsync(selected, !entries.Any(e => RankingSpotlight.SameAccount(e.AccountId, selected)), cancellationToken);
    }
}
#endregion

#region Band card
/// <summary>One band size's top-ten card (no selected-band spotlight: Windows has no selected-band identity yet).</summary>
public sealed partial class BandRankingCardViewModel : ObservableObject
{
    private readonly FestivalSession session;

    /// <summary>Creates a card.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="bandType">Band size.</param>
    /// <param name="metric">Band-safe metric.</param>
    public BandRankingCardViewModel(FestivalSession session, BandType bandType, BandRankingMetric metric)
    {
        this.session = session;
        BandType = bandType;
        Metric = metric;
        Status = new ServiceStatusViewModel($"leaderboards.{bandType.ServiceId()}", $"{bandType.Label()} unavailable",
            () => LoadAsync(), session.Time);
    }

    /// <summary>Band size.</summary>
    public BandType BandType { get; }

    /// <summary>Displayed metric.</summary>
    public BandRankingMetric Metric { get; }

    /// <summary>Card title.</summary>
    public string Title => BandType.Label();

    /// <summary>Metric subtitle.</summary>
    public string Subtitle => Metric.ToRankingMetric().Label();

    /// <summary>Card automation ID.</summary>
    public string AutomationId => "fst.leaderboards.band-card." + BandType.ServiceId();

    /// <summary>"View All" automation ID.</summary>
    public string ViewAllAutomationId => AutomationId + ".view-all";

    /// <summary>Accessible name of "View All".</summary>
    public string ViewAllName => $"View all {BandType.Label()} rankings";

    /// <summary>Band Rankings route.</summary>
    public AppRoute ViewAllRoute => new AppRoute.BandRankings(BandType.ServiceId());

    /// <summary>Inline failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Top rows.</summary>
    [ObservableProperty]
    private List<BandRankingRowViewModel> rows = [];

    /// <summary>Whether the skeleton is shown.</summary>
    public bool IsLoading => State is LoadState.Idle or LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the empty text is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the inline failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Empty text.</summary>
    public string EmptyText => $"No ranked {BandType.Label().ToLowerInvariant()} yet.";

    /// <summary>Loads the top ten.</summary>
    /// <param name="cancellationToken">Cancelled by a newer overview load.</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        State = LoadState.Loading;
        try
        {
            var board = await session.Api.GetBandRankingsAsync(BandType, Metric, 1, LeaderboardPaging.CardSize, cancellationToken);
            Status.Clear();
            Rows = board.Entries.Select(e => new BandRankingRowViewModel(e, BandType, Metric)).ToList();
            State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer overview load.
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
        }
    }
}
#endregion
