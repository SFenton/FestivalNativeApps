using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Full rankings
/// <summary>
/// <c>/leaderboards/all</c>: paginated global rankings for one instrument and metric, with an instrument switcher
/// scoped to Settings-visible charts (plus the current one), the selected player highlighted on the page or
/// pinned below it with a "Jump to your page" action (native addition; the web footer only links to the profile).
/// </summary>
public sealed partial class FullRankingsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly OwnRankingReader? reader;
    private int version;
    private List<AccountRankingEntry> entries = [];

    /// <summary>Creates the page model for a route.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Instrument and metric.</param>
    /// <param name="reader">Own-row reader (defaults to the public single-account read).</param>
    public FullRankingsViewModel(FestivalSession session, AppRoute.FullRankings route, OwnRankingReader? reader = null)
    {
        this.session = session;
        this.reader = reader ?? LeaderboardPreferences.DefaultReader(session);
        instrument = route.Instrument;
        metric = RankingMetricInfo.Coerce(route.RankBy);
        page = Math.Max(1, route.Page);
        Pager = new RankingsPagerViewModel("fst.full-rankings", GoToPageAsync);
        Status = new ServiceStatusViewModel("full-rankings", "Rankings unavailable", LoadAsync, session.Time);
        spotlight = NewSpotlight();
    }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Metrics offered by Rank By.</summary>
    public IReadOnlyList<RankingMetric> MetricOptions => RankingMetricInfo.All;

    /// <summary>Instrument switcher options: Settings-visible charts, keeping the current one selectable.</summary>
    public List<Instrument> InstrumentOptions =>
        InstrumentInfo.All.Where(i => session.Settings.VisibleInstruments.Contains(i) || i == Instrument).ToList();

    /// <summary>Board.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(IconFile), nameof(InstrumentButtonName))]
    private Instrument instrument;

    /// <summary>Metric.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MetricLabel), nameof(MetricButtonName))]
    private RankingMetric metric;

    /// <summary>One-based page.</summary>
    [ObservableProperty]
    private int page = 1;

    /// <summary>Lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError), nameof(ShowContent))]
    private LoadState state = LoadState.Idle;

    /// <summary>Page rows.</summary>
    [ObservableProperty]
    private List<RankingRowViewModel> rows = [];

    /// <summary>Selected-player spotlight (rebuilt per instrument).</summary>
    [ObservableProperty]
    private RankingSpotlightViewModel spotlight;

    /// <summary>Ranked population text.</summary>
    [ObservableProperty]
    private string totalText = "";

    /// <summary>Page title.</summary>
    public string Title => $"{Instrument.Label()} Rankings";

    /// <summary>Instrument icon.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Accessible name of the instrument switcher.</summary>
    public string InstrumentButtonName => $"Instrument: {Instrument.Label()}";

    /// <summary>Rank By label.</summary>
    public string MetricLabel => Metric.Label();

    /// <summary>Accessible name of Rank By.</summary>
    public string MetricButtonName => $"Rank by: {Metric.Label()}";

    /// <summary>Whether the first load is in flight.</summary>
    public bool IsLoading => State is LoadState.Idle or LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether "No ranked players yet." is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the board chrome (pager, spotlight) is shown.</summary>
    public bool ShowContent => State is LoadState.Loaded or LoadState.Empty;

    /// <summary>Switches instrument (resets to page 1 and the spotlight).</summary>
    /// <param name="value">Instrument.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectInstrumentAsync(Instrument value)
    {
        if (value == Instrument) return Task.CompletedTask;
        Instrument = value;
        Spotlight = NewSpotlight();
        Page = 1;
        return LoadAsync();
    }

    /// <summary>Switches metric (resets to page 1).</summary>
    /// <param name="value">Metric.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectMetricAsync(RankingMetric value)
    {
        if (value == Metric) return Task.CompletedTask;
        Metric = value;
        Page = 1;
        return LoadAsync();
    }

    /// <summary>Moves to a page.</summary>
    /// <param name="value">One-based page.</param>
    /// <returns>Load task.</returns>
    public Task GoToPageAsync(int value)
    {
        Page = Math.Max(1, value);
        return LoadAsync();
    }

    /// <summary>Loads the current page, dropping late responses from a superseded request and clamping out-of-range pages.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var request = ++version;
        var (requestedInstrument, requestedMetric, requestedPage) = (Instrument, Metric, Page);
        if (State != LoadState.Loaded) State = LoadState.Loading;
        IsRefreshing = true;
        try
        {
            var board = await session.Api.GetRankingsAsync(requestedInstrument, requestedMetric, requestedPage, LeaderboardPaging.PageSize);
            if (request != version) return;
            var corrected = LeaderboardPaging.Corrected(requestedPage, board.PageCount);
            if (corrected != requestedPage)
            {
                await GoToPageAsync(corrected);
                return;
            }
            Status.Clear();
            entries = board.Entries;
            TotalText = $"{board.TotalAccounts:N0} ranked players";
            Pager.Update(requestedPage, board.PageCount);
            ApplyRows();
            State = entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
            IsRefreshing = false;
            var selected = session.SelectedPlayer?.AccountId;
            await Spotlight.EnsureLoadedAsync(selected, !entries.Any(e => RankingSpotlight.SameAccount(e.AccountId, selected)));
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            IsRefreshing = false;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Whether a page change is in flight over already-shown rows.</summary>
    [ObservableProperty]
    private bool isRefreshing;

    /// <summary>Re-evaluates selection highlights (selected player changed).</summary>
    public void RefreshSelection()
    {
        if (State is LoadState.Loaded or LoadState.Empty)
        {
            ApplyRows();
            var selected = session.SelectedPlayer?.AccountId;
            _ = Spotlight.EnsureLoadedAsync(selected, !entries.Any(e => RankingSpotlight.SameAccount(e.AccountId, selected)));
        }
    }

    /// <summary>Builds rows and applies the spotlight for the current page.</summary>
    private void ApplyRows()
    {
        var selected = session.SelectedPlayer?.AccountId;
        Rows = entries.Select(e => new RankingRowViewModel(e, Metric, RankingSpotlight.SameAccount(e.AccountId, selected))).ToList();
        Spotlight.Apply(selected, entries, Metric, Page, LeaderboardPaging.PageSize);
        RankingRowViewModel.ShareRankWidth(Rows, Spotlight.Row);
    }

    /// <summary>Creates the spotlight for the current instrument with a jump back into this board.</summary>
    /// <returns>Spotlight.</returns>
    private RankingSpotlightViewModel NewSpotlight()
    {
        var created = new RankingSpotlightViewModel(Instrument, reader, session.Time, "full-rankings.spotlight." + Instrument.ServiceId(), GoToPageAsync);
        // The pinned row arrives after the page: widen every rank column to fit it (operator batch 7.9).
        created.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(RankingSpotlightViewModel.Row)) RankingRowViewModel.ShareRankWidth(Rows, created.Row);
        };
        return created;
    }
}
#endregion

#region Band rankings
/// <summary><c>/leaderboards/bands/:bandType</c>: paginated band rankings with a band-size switcher and band metrics.</summary>
public sealed partial class BandRankingsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private int version;

    /// <summary>Creates the page model for a route (unknown types fall back to Duos).</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Band type.</param>
    public BandRankingsViewModel(FestivalSession session, AppRoute.BandRankings route)
    {
        this.session = session;
        bandType = BandTypeInfo.TryParse(route.BandType, out var parsed) ? parsed : BandType.Duets;
        metric = LeaderboardPreferences.RankBy(session).ToBandMetric();
        Pager = new RankingsPagerViewModel("fst.band-rankings", GoToPageAsync);
        Status = new ServiceStatusViewModel("band-rankings", "Rankings unavailable", LoadAsync, session.Time);
    }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Band sizes.</summary>
    public IReadOnlyList<BandType> BandTypeOptions => BandTypeInfo.All;

    /// <summary>Band metrics (no Max Score).</summary>
    public IReadOnlyList<BandRankingMetric> MetricOptions => BandRankingMetricInfo.All;

    /// <summary>Band size.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(BandTypeButtonName), nameof(EmptyText))]
    private BandType bandType;

    /// <summary>Metric.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MetricLabel), nameof(MetricButtonName))]
    private BandRankingMetric metric;

    /// <summary>One-based page.</summary>
    [ObservableProperty]
    private int page = 1;

    /// <summary>Lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError), nameof(ShowContent))]
    private LoadState state = LoadState.Idle;

    /// <summary>Page rows.</summary>
    [ObservableProperty]
    private List<BandRankingRowViewModel> rows = [];

    /// <summary>Ranked population text.</summary>
    [ObservableProperty]
    private string totalText = "";

    /// <summary>Whether a page change is in flight over already-shown rows.</summary>
    [ObservableProperty]
    private bool isRefreshing;

    /// <summary>Page title.</summary>
    public string Title => $"{BandType.Label()} Rankings";

    /// <summary>Accessible name of the band-size switcher.</summary>
    public string BandTypeButtonName => $"Band size: {BandType.Label()}";

    /// <summary>Rank By label.</summary>
    public string MetricLabel => Metric.ToRankingMetric().Label();

    /// <summary>Accessible name of Rank By.</summary>
    public string MetricButtonName => $"Rank by: {MetricLabel}";

    /// <summary>Empty text.</summary>
    public string EmptyText => $"No ranked {BandType.Label().ToLowerInvariant()} yet.";

    /// <summary>Whether the first load is in flight.</summary>
    public bool IsLoading => State is LoadState.Idle or LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the empty text is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the pager is shown.</summary>
    public bool ShowContent => State is LoadState.Loaded or LoadState.Empty;

    /// <summary>Switches band size (resets to page 1).</summary>
    /// <param name="value">Band size.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectBandTypeAsync(BandType value)
    {
        if (value == BandType) return Task.CompletedTask;
        BandType = value;
        Page = 1;
        return LoadAsync();
    }

    /// <summary>Switches metric (resets to page 1).</summary>
    /// <param name="value">Band metric.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectMetricAsync(BandRankingMetric value)
    {
        if (value == Metric) return Task.CompletedTask;
        Metric = value;
        Page = 1;
        return LoadAsync();
    }

    /// <summary>Moves to a page.</summary>
    /// <param name="value">One-based page.</param>
    /// <returns>Load task.</returns>
    public Task GoToPageAsync(int value)
    {
        Page = Math.Max(1, value);
        return LoadAsync();
    }

    /// <summary>Loads the current page, dropping superseded responses and clamping out-of-range pages.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var request = ++version;
        var (requestedType, requestedMetric, requestedPage) = (BandType, Metric, Page);
        if (State != LoadState.Loaded) State = LoadState.Loading;
        IsRefreshing = true;
        try
        {
            var board = await session.Api.GetBandRankingsAsync(requestedType, requestedMetric, requestedPage, LeaderboardPaging.PageSize);
            if (request != version) return;
            var corrected = LeaderboardPaging.Corrected(requestedPage, board.PageCount);
            if (corrected != requestedPage)
            {
                await GoToPageAsync(corrected);
                return;
            }
            Status.Clear();
            TotalText = $"{board.TotalTeams:N0} ranked bands";
            Pager.Update(requestedPage, board.PageCount);
            Rows = board.Entries.Select(e => new BandRankingRowViewModel(e, requestedType, requestedMetric)).ToList();
            State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
            IsRefreshing = false;
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            IsRefreshing = false;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }
}
#endregion
