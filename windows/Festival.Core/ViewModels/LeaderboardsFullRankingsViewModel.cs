using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Festival.Core.Domain;

namespace Festival.Core.ViewModels;

#region Full rankings
/// <summary>
/// <c>/leaderboards/all</c>: paginated global rankings for one instrument and metric, with an instrument switcher
/// scoped to Settings-visible charts (plus the current one), the selected player highlighted on the page and always
/// pinned above the pager, their own page included (web <c>FullRankingsPage</c> <c>hasPlayerFooter = !!playerRanking</c>,
/// pattern <c>leaderboard-row</c> R7, issue #318). The pinned row is itself the control: while the player's row is on
/// another page it jumps there (native addition; the web footer only links to the profile), and once it is shown it opens
/// their profile (<see cref="SelectedRowAction.Footer"/>).
/// </summary>
public sealed partial class FullRankingsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly OwnRankingReader? reader;
    private Instrument spotlightInstrument;
    private bool spotlightShown;
    private int version;
    private RankingMetric requestedMetric;
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
        requestedMetric = RankingMetricInfo.Coerce(route.RankBy);
        metric = requestedMetric.Gate(session.Settings.ExperimentalRanks);
        page = Math.Max(1, route.Page);
        Pager = new RankingsPagerViewModel("fst.full-rankings", GoToPageAsync);
        Status = new ServiceStatusViewModel("full-rankings", "Rankings unavailable", LoadAsync, session.Time);
        spotlight = NewSpotlight(instrument);
        LoadSwap = new LoadSwap(session.Time);
        LoadSwap.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(ShowRows));
            OnPropertyChanged(nameof(ShowEmpty));
            OnPropertyChanged(nameof(ShowError));
            OnPropertyChanged(nameof(ShowContent));
        };
    }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Rows/content load-swap gate.</summary>
    public LoadSwap LoadSwap { get; }

    /// <summary>
    /// Whether the pinned "your rank" row follows <see cref="LoadSwap"/>: only for the first load and an instrument or
    /// Rank By change, like the web footer (keyed on instrument and metric); paging keeps it beside the spinner.
    /// </summary>
    public PinnedRowGate PinnedGate { get; } = new();

    /// <summary>Whether load-swap motion is allowed; the app layer supplies <c>Motion.Allowed</c>.</summary>
    public Func<bool> AnimateLoadSwaps { get; set; } = () => false;

    /// <summary>Metrics offered by Rank By (web <c>getEnabledRankingMetrics</c>).</summary>
    public IReadOnlyList<RankingMetric> MetricOptions => RankingMetricInfo.Enabled(session.Settings.ExperimentalRanks);

    /// <summary>Whether Rank By shows: only with Settings' Experimental Ranks on, as on the web.</summary>
    public bool ShowRankBy => session.Settings.ExperimentalRanks;

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

    /// <summary>
    /// Selected-player spotlight, rebuilt when a board for another instrument commits: the old pinned row fades out
    /// with the old rows instead of vanishing when the switch starts (issue #270, load-transition R2).
    /// </summary>
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
    public bool IsLoading => LoadSwap.IsLoading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded && LoadSwap.ContentVisible;

    /// <summary>Whether "No ranked players yet." is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty && LoadSwap.ContentVisible;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed && LoadSwap.ContentVisible;

    /// <summary>
    /// Whether the board chrome (pager) is shown: from the first loaded board on, it stays while another page swaps in,
    /// like the web's fixed pagination (<c>hasLoadedOnce &amp;&amp; !error</c>), so a focused pager button keeps keyboard
    /// focus across page changes (issue #208). Hidden for the full-page failure.
    /// </summary>
    public bool ShowContent => State is LoadState.Loaded or LoadState.Empty;

    /// <summary>Switches instrument (resets to page 1 and hides the pager until the new board's count commits, #575; the spotlight is rebuilt when the new board commits).</summary>
    /// <param name="value">Instrument.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectInstrumentAsync(Instrument value)
    {
        if (value == Instrument) return Task.CompletedTask;
        Instrument = value;
        Page = 1;
        Pager.Reset();
        return LoadAsync();
    }

    /// <summary>Switches metric (resets to page 1).</summary>
    /// <param name="value">Metric.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectMetricAsync(RankingMetric value)
    {
        value = value.Gate(session.Settings.ExperimentalRanks);
        if (value == Metric) return Task.CompletedTask;
        requestedMetric = value;
        Metric = value;
        Page = 1;
        Pager.Reset();
        return LoadAsync();
    }

    /// <summary>
    /// Re-applies Settings' Experimental Ranks to a cached page on revisit (web <c>coerceRankingMetric</c> on every
    /// render): turning it off falls back to Total Score, turning it back on restores the route's metric.
    /// </summary>
    /// <returns>The reload (page 1) when the allowed metric changed, otherwise <see langword="null"/>.</returns>
    public Task? SyncExperimentalRanks()
    {
        OnPropertyChanged(nameof(ShowRankBy));
        OnPropertyChanged(nameof(MetricOptions));
        var allowed = requestedMetric.Gate(session.Settings.ExperimentalRanks);
        if (allowed == Metric) return null;
        Metric = allowed;
        Page = 1;
        Pager.Reset();
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
        var key = (requestedInstrument, requestedMetric);
        PinnedGate.Begin(key, LoadSwap.Phase);
        var swap = LoadSwap.BeginReloadAsync(AnimateLoadSwaps(), State is LoadState.Loaded or LoadState.Empty or LoadState.Failed && LoadSwap.ContentVisible);
        if (State is LoadState.Idle) State = LoadState.Loading;
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
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Clear();
                PinnedGate.Commit(key);
                if (spotlightInstrument != requestedInstrument) Spotlight = NewSpotlight(requestedInstrument);
                entries = board.Entries;
                TotalText = $"{board.TotalAccounts:N0} ranked players";
                Pager.Update(requestedPage, board.PageCount);
                ApplyRows();
                State = entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
                IsRefreshing = false;
            }, AnimateLoadSwaps());
            var selected = session.SelectedPlayer?.AccountId;
            await Spotlight.EnsureLoadedAsync(selected, true);
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                IsRefreshing = false;
                PinnedGate.Commit(key);
                if (spotlightInstrument != requestedInstrument) Spotlight = NewSpotlight(requestedInstrument);
                Status.Report(error);
                State = LoadState.Failed;
            }, AnimateLoadSwaps());
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
            _ = Spotlight.EnsureLoadedAsync(selected, true);
        }
    }

    /// <summary>Builds rows and applies the spotlight for the current page.</summary>
    private void ApplyRows()
    {
        var selected = session.SelectedPlayer?.AccountId;
        Rows = entries.Select(e => new RankingRowViewModel(e, Metric, RankingSpotlight.SameAccount(e.AccountId, selected))).ToList();
        Spotlight.Apply(selected, entries, Metric, Page, LeaderboardPaging.PageSize);
        RankingRowViewModel.ShareColumns(Rows, Spotlight.Row);
    }

    /// <summary>Creates the spotlight for a board's instrument with a jump back into this board.</summary>
    /// <param name="board">Instrument of the board it pins to.</param>
    /// <returns>Spotlight.</returns>
    private RankingSpotlightViewModel NewSpotlight(Instrument board)
    {
        spotlightInstrument = board;
        var created = new RankingSpotlightViewModel(board, reader, session.Time, "full-rankings.spotlight." + board.ServiceId(), GoToPageAsync, pinned: true);
        // The pinned row arrives after the page: widen every rank column to fit it (operator batch 7.9).
        created.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(RankingSpotlightViewModel.Row)) RankingRowViewModel.ShareColumns(Rows, created.Row);
            if (e.PropertyName == nameof(RankingSpotlightViewModel.IsVisible) && ReferenceEquals(created, Spotlight)) PinnedRowShown(created.IsVisible);
        };
        return created;
    }

    /// <summary>Starts tracking a replacement spotlight's visibility (a new instrument's board committed).</summary>
    /// <param name="value">New spotlight.</param>
    partial void OnSpotlightChanged(RankingSpotlightViewModel value) => spotlightShown = value.IsVisible;

    /// <summary>Tracks the current spotlight's visibility; a row that newly appears joins <see cref="PinnedGate"/>.</summary>
    /// <param name="shown">Whether the pinned row is now shown.</param>
    private void PinnedRowShown(bool shown)
    {
        if (shown && !spotlightShown) PinnedGate.Arrived(LoadSwap.Phase);
        spotlightShown = shown;
    }
}
#endregion

#region Band rankings
/// <summary><c>/leaderboards/bands/:bandType</c>: paginated band rankings with a band-size switcher and band metrics.</summary>
public sealed partial class BandRankingsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private int version;
    private BandRankingMetric requestedMetric;

    /// <summary>Creates the page model for a route (unknown types fall back to Duos).</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Band type.</param>
    public BandRankingsViewModel(FestivalSession session, AppRoute.BandRankings route)
    {
        this.session = session;
        bandType = BandTypeInfo.TryParse(route.BandType, out var parsed) ? parsed : BandType.Duets;
        requestedMetric = RankingMetricInfo.Coerce(session.Settings.LeaderboardRankBy).ToBandMetric();
        metric = requestedMetric.Gate(session.Settings.ExperimentalRanks);
        Pager = new RankingsPagerViewModel("fst.band-rankings", GoToPageAsync);
        Status = new ServiceStatusViewModel("band-rankings", "Rankings unavailable", LoadAsync, session.Time);
        LoadSwap = new LoadSwap(session.Time);
        LoadSwap.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(ShowRows));
            OnPropertyChanged(nameof(ShowEmpty));
            OnPropertyChanged(nameof(ShowError));
        };
    }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Rows/content load-swap gate.</summary>
    public LoadSwap LoadSwap { get; }

    /// <summary>Whether load-swap motion is allowed; the app layer supplies <c>Motion.Allowed</c>.</summary>
    public Func<bool> AnimateLoadSwaps { get; set; } = () => false;

    /// <summary>Band sizes.</summary>
    public IReadOnlyList<BandType> BandTypeOptions => BandTypeInfo.All;

    /// <summary>Band metrics (no Max Score; web <c>getEnabledBandRankingMetrics</c>).</summary>
    public IReadOnlyList<BandRankingMetric> MetricOptions => BandRankingMetricInfo.Enabled(session.Settings.ExperimentalRanks);

    /// <summary>Whether Rank By shows: only with Settings' Experimental Ranks on, as on the web.</summary>
    public bool ShowRankBy => session.Settings.ExperimentalRanks;

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
    public bool IsLoading => LoadSwap.IsLoading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded && LoadSwap.ContentVisible;

    /// <summary>Whether the empty text is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty && LoadSwap.ContentVisible;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed && LoadSwap.ContentVisible;

    /// <summary>
    /// Whether the pager is shown. It stays in place while another page loads, like the song leaderboard (issue #93):
    /// <see cref="State"/> only changes when a load commits, so only the rows swap for the spinner and keyboard focus
    /// stays on the pager button that paged (issue #209).
    /// </summary>
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
        Pager.Reset();
        return LoadAsync();
    }

    /// <summary>Switches metric (resets to page 1).</summary>
    /// <param name="value">Band metric.</param>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task SelectMetricAsync(BandRankingMetric value)
    {
        value = value.Gate(session.Settings.ExperimentalRanks);
        if (value == Metric) return Task.CompletedTask;
        requestedMetric = value;
        Metric = value;
        Page = 1;
        Pager.Reset();
        return LoadAsync();
    }

    /// <summary>
    /// Re-applies Settings' Experimental Ranks to a cached page on revisit (web <c>coerceBandRankingMetric</c> on every
    /// render): turning it off falls back to Total Score, turning it back on restores the chosen metric.
    /// </summary>
    /// <returns>The reload (page 1) when the allowed metric changed, otherwise <see langword="null"/>.</returns>
    public Task? SyncExperimentalRanks()
    {
        OnPropertyChanged(nameof(ShowRankBy));
        OnPropertyChanged(nameof(MetricOptions));
        var allowed = requestedMetric.Gate(session.Settings.ExperimentalRanks);
        if (allowed == Metric) return null;
        Metric = allowed;
        Page = 1;
        Pager.Reset();
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
        var swap = LoadSwap.BeginReloadAsync(AnimateLoadSwaps(), State is LoadState.Loaded or LoadState.Empty or LoadState.Failed && LoadSwap.ContentVisible);
        if (State is LoadState.Idle) State = LoadState.Loading;
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
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Clear();
                TotalText = $"{board.TotalTeams:N0} ranked bands";
                Pager.Update(requestedPage, board.PageCount);
                var rows = board.Entries.Select(e => new BandRankingRowViewModel(e, requestedType, requestedMetric)).ToList();
                BandRankingRowViewModel.ShareColumns(rows);
                Rows = rows;
                State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
                IsRefreshing = false;
            }, AnimateLoadSwaps());
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                IsRefreshing = false;
                Status.Report(error);
                State = LoadState.Failed;
            }, AnimateLoadSwaps());
        }
    }
}
#endregion
