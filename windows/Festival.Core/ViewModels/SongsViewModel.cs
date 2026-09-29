using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Songs
/// <summary>
/// Songs catalogue page: load, search (250 ms debounce), sort and filter drafts, grouped row items with
/// same-publication Shop accents, selected-player status chips or metadata, and pause notices.
/// </summary>
public sealed partial class SongsViewModel : ObservableObject
{
    /// <summary>Web search debounce.</summary>
    public static readonly TimeSpan SearchDebounce = TimeSpan.FromMilliseconds(250);

    private readonly FestivalSession session;
    private CancellationTokenSource? searchDebounce;
    private string appliedSearch = "";

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    public SongsViewModel(FestivalSession session)
    {
        this.session = session;
        Status = new ServiceStatusViewModel("songs", "Songs unavailable", () => LoadAsync(force: true), session.Time);
        SortDraft = new SongSortDraft(session);
        FilterDraft = new SongFilterDraft(session);
        // Sort and filter flyouts apply live (operator 2026-09-28): every valid change commits; no Cancel/Apply.
        SortDraft.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SongSortDraft.CanApply) && SortDraft.IsLive && SortDraft.CanApply) ApplySort();
        };
        FilterDraft.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SongFilterDraft.CanApply) && FilterDraft.IsLive && FilterDraft.CanApply) ApplyFilter();
        };
        session.PropertyChanged += OnSessionChanged;
        session.PublicationAdvanced += (_, _) => _ = LoadAsync(force: true);
    }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Sort flyout draft.</summary>
    public SongSortDraft SortDraft { get; }

    /// <summary>Filter flyout draft.</summary>
    public SongFilterDraft FilterDraft { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowList), nameof(ShowEmpty), nameof(ShowError), nameof(ShowInvalidFilter))]
    private LoadState state = LoadState.Idle;

    /// <summary>Search box text (applied after <see cref="SearchDebounce"/>).</summary>
    [ObservableProperty]
    private string searchText = "";

    /// <summary>Grouped rows for the list.</summary>
    [ObservableProperty]
    private IReadOnlyList<SongRowSection> sections = [];

    /// <summary>Visible row count.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CountText))]
    private int resultCount;

    /// <summary>Pause and status notices shown above the list (sort, Shop filter, score filter, player scores).</summary>
    [ObservableProperty]
    private List<string> notices = [];

    /// <summary>Whether the sections carry headers (false for a single unlabeled Shop bucket).</summary>
    [ObservableProperty]
    private bool hasJumpIndex;

    /// <summary>Whether a request is in flight with nothing shown.</summary>
    public bool IsLoading => State == LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowList => State == LoadState.Loaded;

    /// <summary>Whether the no-results view is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed && !InvalidSavedFilter;

    /// <summary>Whether a corrupt saved player filter blocks the list until an explicit Reset.</summary>
    public bool ShowInvalidFilter => InvalidSavedFilter && session.Catalog is not null;

    /// <summary>Whether any notice is present.</summary>
    public bool HasNotices => Notices.Count > 0;

    /// <summary>"728 songs" style count.</summary>
    public string CountText => ResultCount == 1 ? "1 song" : string.Create(CultureInfo.CurrentCulture, $"{ResultCount:N0} songs");

    /// <summary>No-results message (names filters when they are active).</summary>
    public string EmptyMessage => IsFilterActive ? "No songs match the filters." : "No songs match your search.";

    /// <summary>Whether a non-default sort is applied (gold tint).</summary>
    public bool IsSortChanged => session.Settings.SongSort != SongSortMode.Title || !session.Settings.SongSortAscending;

    /// <summary>Whether any saved filter is set (gold tint).</summary>
    public bool IsFilterActive =>
        session.Settings.SongFilter.IsActive || session.Settings.ShopFilter.IsActive || session.Settings.PlayerScoreFilter.IsActive ||
        session.Settings.ScoreBandFilter is { IsActive: true };

    /// <summary>
    /// Whether the Filter button shows: the web offers no Songs filter without a selected profile, but a filter saved
    /// earlier still applies, so the button stays while one is active to let it be cleared.
    /// </summary>
    public bool ShowFilterButton => session.HasPlayer || IsFilterActive;

    /// <summary>Applied sort label, e.g. "Title ↑".</summary>
    public string SortSummary => session.Settings.SongSort.Label() + (session.Settings.SongSortAscending ? " ↑" : " ↓");

    /// <summary>Whether the saved player filter is corrupt.</summary>
    private bool InvalidSavedFilter => !session.Settings.PlayerScoreFilter.IsValid;

    /// <summary>Loads the catalogue (plus Shop and player scores, best-effort) and rebuilds the list.</summary>
    /// <param name="force">Re-read from the service.</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(bool force = false)
    {
        if (session.Catalog is null) State = LoadState.Loading;
        try
        {
            await session.LoadCatalogAsync(force);
            Status.Clear();
            Rebuild();
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
            return;
        }
        await session.TryLoadShopAsync(force);
        await SongScoreSource.LoadAsync(session, force);
        Rebuild();
    }

    /// <summary>Loads on first appearance (and retries a failed list when the page becomes visible again).</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task AppearAsync() => session.Catalog is null || State is LoadState.Idle or LoadState.Failed ? LoadAsync() : RefreshRelatedAsync();

    /// <summary>Re-reads from the service.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task RefreshAsync() => LoadAsync(force: true);

    /// <summary>Applies the sort draft.</summary>
    [RelayCommand]
    private void ApplySort() =>
        session.UpdateSettings(s => s with { SongSort = SortDraft.Mode, SongSortAscending = SortDraft.Ascending });

    /// <summary>Applies the filter draft.</summary>
    [RelayCommand]
    private void ApplyFilter() => session.UpdateSettings(FilterDraft.Apply);

    /// <summary>Clears every applied filter (no-results and invalid-filter action).</summary>
    [RelayCommand]
    private void ClearFilter() => session.UpdateSettings(s => s with
    {
        SongFilter = SongFilter.None, ShopFilter = SongShopFilter.None, PlayerScoreFilter = SongPlayerScoreFilter.None,
        ScoreBandFilter = null,
    });

    /// <summary>Debounces search input.</summary>
    /// <param name="value">New text.</param>
    partial void OnSearchTextChanged(string value)
    {
        searchDebounce?.Cancel();
        searchDebounce = new CancellationTokenSource();
        _ = ApplySearchAsync(value, searchDebounce.Token);
    }

    /// <summary>Applies search after the debounce.</summary>
    /// <param name="value">Text.</param>
    /// <param name="token">Cancelled by newer input.</param>
    /// <returns>Delay task.</returns>
    private async Task ApplySearchAsync(string value, CancellationToken token)
    {
        try
        {
            await Task.Delay(SearchDebounce, session.Time, token);
        }
        catch (OperationCanceledException)
        {
            return;
        }
        appliedSearch = value;
        Rebuild();
    }

    /// <summary>Applies search immediately (Enter key).</summary>
    [RelayCommand]
    private void SubmitSearch()
    {
        searchDebounce?.Cancel();
        appliedSearch = SearchText;
        Rebuild();
    }

    /// <summary>Loads Shop and player scores when the page reappears with a catalogue already shown.</summary>
    /// <returns>Load task.</returns>
    private async Task RefreshRelatedAsync()
    {
        await session.TryLoadShopAsync();
        await SongScoreSource.LoadAsync(session);
        Rebuild();
    }

    /// <summary>Recomputes rows when inputs change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (SongScoreSource.AffectsRows(e.PropertyName) || e.PropertyName is nameof(FestivalSession.Settings) or
            nameof(FestivalSession.Catalog) or nameof(FestivalSession.Shop) or nameof(FestivalSession.ShopOffersForCatalog))
            Rebuild();
        if (e.PropertyName == nameof(FestivalSession.Settings))
        {
            if (!session.Settings.HideShop && session.Shop is null && session.ShopIssue is null) _ = session.TryLoadShopAsync();
            if (session.HasPlayer) _ = SongScoreSource.LoadAsync(session);
        }
    }

    /// <summary>Runs the pipeline over the current catalogue and projects rows.</summary>
    private void Rebuild()
    {
        if (session.Catalog is not { } catalog) return;
        var settings = session.Settings;
        OnPropertyChanged(nameof(IsSortChanged));
        OnPropertyChanged(nameof(IsFilterActive));
        OnPropertyChanged(nameof(ShowFilterButton));
        OnPropertyChanged(nameof(SortSummary));
        OnPropertyChanged(nameof(EmptyMessage));
        if (InvalidSavedFilter)
        {
            Sections = [];
            ResultCount = 0;
            Notices = [];
            OnPropertyChanged(nameof(HasNotices));
            State = LoadState.Failed;
            OnPropertyChanged(nameof(ShowInvalidFilter));
            return;
        }

        var scores = SongScoreSource.For(session);
        var offers = settings.HideShop ? null : session.ShopOffersForCatalog;
        var result = SongListPipeline.Run(new SongListInputs
        {
            Songs = catalog.Songs,
            Search = appliedSearch,
            Filter = settings.SongFilter,
            ShopFilter = settings.ShopFilter,
            PlayerFilter = settings.PlayerScoreFilter,
            Sort = settings.SongSort,
            Ascending = settings.SongSortAscending,
            Visible = settings.VisibleInstruments,
            HideShop = settings.HideShop,
            Offers = offers,
            ShopPublicationMismatch = !settings.HideShop && session.ShopPublicationMismatch,
            HasPlayer = session.HasPlayer,
            FilterInvalidScores = settings.FilterInvalidScores,
            Scores = scores.Available ? scores.Facts : null,
            ScoreBand = settings.ScoreBandFilter,
            Details = scores.Available ? scores.Detail : null,
        });

        var projector = new SongRowProjector(settings, catalog.CurrentSeason, offers, scores);
        Sections = [.. result.Sections.Select(s => new SongRowSection(s.Label, [.. s.Songs.Select(projector.Project)]))];
        // No quick-jump under the Year sort (operator 2026-09-28): decade headers stay, the zoomed-out index does not.
        HasJumpIndex = settings.SongSort != SongSortMode.Year &&
                       (Sections.Count > 1 || (Sections.Count == 1 && Sections[0].Label.Length > 0));
        ResultCount = result.Count;
        var notices = new List<string>();
        if (scores.Notice is { } scoreNotice) notices.Add(scoreNotice);
        foreach (var notice in new[] { result.SortPaused, result.ShopFilterPaused, result.ScoreFilterPaused })
            if (notice is not null) notices.Add(notice);
        Notices = notices;
        OnPropertyChanged(nameof(HasNotices));
        State = result.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        OnPropertyChanged(nameof(ShowInvalidFilter));
        OnPropertyChanged(nameof(ShowError));
    }
}
#endregion

#region Row projection
/// <summary>Projects catalogue rows into row items for one rebuild.</summary>
/// <param name="settings">Current settings.</param>
/// <param name="currentSeason">Catalogue season.</param>
/// <param name="offers">Same-publication offers, or <see langword="null"/>.</param>
/// <param name="scores">Selected-player score source.</param>
public sealed class SongRowProjector(AppSettings settings, int? currentSeason, IReadOnlyDictionary<string, ShopSong>? offers, SongScoreSource scores)
{
    private readonly bool chips = SongInstrumentStatusPolicy.ShowsChips(
        scores.HasPlayer, scores.Available, settings.ShowInstrumentIcons, settings.SongFilter.Instrument, settings.FilterInvalidScores);

    private readonly Instrument? metadataChart = settings.SongFilter.Instrument ?? settings.VisibleInstruments.FirstOrDefault();

    /// <summary>Projects one song.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <returns>Row item.</returns>
    public SongRowItem Project(Song song)
    {
        var offer = offers?.GetValueOrDefault(song.SongId);
        var highlight = ShopPresentationPolicy.Highlight(offer, settings.HideShop, settings.DisableShopHighlighting);
        var inShop = offer is not null && !settings.HideShop && !settings.DisableShopHighlighting;
        var filterChart = settings.SongFilter.Instrument;
        var filterRaw = filterChart is { } f ? song.Difficulty?.ChartedValue(f) : null;
        if (!scores.HasPlayer)
            return new SongRowItem(song) { Highlight = highlight, InShop = inShop, Chart = filterRaw is null ? null : filterChart, ChartRaw = filterRaw };
        if (chips)
        {
            return new SongRowItem(song)
            {
                Highlight = highlight, InShop = inShop,
                Chips = SongInstrumentStatusPolicy.Badges(song, settings.VisibleInstruments, chart => scores.Facts!(song.SongId, chart)),
            };
        }
        if (!scores.Available || settings.FilterInvalidScores || metadataChart is not { } chart)
        {
            return new SongRowItem(song)
            {
                Highlight = highlight, InShop = inShop, Chart = filterRaw is null ? null : filterChart, ChartRaw = filterRaw,
                ScoreState = settings.FilterInvalidScores && scores.Available ? "Scores paused while Filter Invalid Scores is on" : scores.RowState,
            };
        }
        var detail = scores.Detail!(song.SongId, chart);
        var fields = detail is null ? [] : SongMetadataPolicy.Fields(detail, chart, song, currentSeason, settings);
        return new SongRowItem(song)
        {
            Highlight = highlight, InShop = inShop,
            Chart = chart,
            ChartRaw = fields.Count == 0 ? song.Difficulty?.ChartedValue(chart) : null,
            Metadata = fields,
            ScoreState = fields.Count > 0 ? null : song.Supports(chart) ? "No score" : $"No {chart.Label()} chart",
        };
    }
}
#endregion

#region Sort draft
/// <summary>
/// Sort flyout state. Once <see cref="Begin"/> has loaded the applied sort the draft is live: the page model commits
/// every change (and Reset) at once, so the flyout has no Cancel or Apply.
/// </summary>
public sealed partial class SongSortDraft(FestivalSession session) : ObservableObject
{
    /// <summary>Whether changes commit immediately (set once <see cref="Begin"/> finishes loading).</summary>
    public bool IsLive { get; private set; }

    /// <summary>Draft mode.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(ModeIndex))]
    private SongSortMode mode = SongSortMode.Title;

    /// <summary>Draft direction.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(Descending))]
    private bool ascending = true;

    /// <summary>The Descending choice (the inverse of <see cref="Ascending"/>, for the second direction row).</summary>
    public bool Descending
    {
        get => !Ascending;
        set => Ascending = !value;
    }

    /// <summary>Ascending row subtitle (web <c>sort.ascendingHintSongs</c> without the repeated word).</summary>
    public const string AscendingHint = "A–Z, low–high";

    /// <summary>Descending row subtitle (web <c>sort.descendingHintSongs</c>).</summary>
    public const string DescendingHint = "Z–A, high–low";

    /// <summary>Available modes (Item Shop is removed while the Shop is hidden).</summary>
    public List<SongSortMode> Modes =>
        [.. SongSortModeInfo.All.Where(m => m != SongSortMode.Shop || !session.Settings.HideShop)];

    /// <summary>Labels for <see cref="Modes"/>.</summary>
    public List<string> ModeLabels => [.. Modes.Select(m => m.Label())];

    /// <summary>Mode as an index into <see cref="Modes"/> for radio buttons (−1 when the saved mode is hidden).</summary>
    public int ModeIndex
    {
        get => Modes.IndexOf(Mode);
        set
        {
            if (value >= 0 && value < Modes.Count) Mode = Modes[value];
        }
    }

    /// <summary>Whether the draft differs from the applied sort.</summary>
    public bool CanApply => Mode != session.Settings.SongSort || Ascending != session.Settings.SongSortAscending;

    /// <summary>Loads the applied values (flyout opening).</summary>
    public void Begin()
    {
        IsLive = false;
        OnPropertyChanged(nameof(Modes));
        OnPropertyChanged(nameof(ModeLabels));
        Mode = session.Settings.SongSort;
        Ascending = session.Settings.SongSortAscending;
        OnPropertyChanged(nameof(ModeIndex));
        IsLive = true;
        OnPropertyChanged(nameof(CanApply));
    }

    /// <summary>Restores the default sort (applied at once while live).</summary>
    [RelayCommand]
    private void Reset()
    {
        Mode = SongSortMode.Title;
        Ascending = true;
    }
}
#endregion

#region Filter draft
/// <summary>
/// Filter flyout draft: one charted instrument and a 1–7 difficulty range (public), Item Shop toggles, and the
/// selected player's per-chart score/FC checks. Live once <see cref="Begin"/> has loaded the applied filters: the page
/// model commits every valid change (an inverted difficulty range waits until it is valid again).
/// </summary>
public sealed partial class SongFilterDraft(FestivalSession session) : ObservableObject
{
    /// <summary>Whether changes commit immediately (set once <see cref="Begin"/> finishes loading).</summary>
    public bool IsLive { get; private set; }

    /// <summary>Choices for the instrument picker: index 0 is "All Instruments".</summary>
    public List<string> InstrumentChoices =>
        ["All Instruments", .. session.Settings.VisibleInstruments.Select(i => i.Label())];

    /// <summary>Selected picker index (0 = all).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private int instrumentIndex;

    /// <summary>Lowest difficulty (1–7).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(IsRangeValid))]
    private double minDifficulty = 1;

    /// <summary>Highest difficulty (1–7).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(IsRangeValid))]
    private double maxDifficulty = 7;

    /// <summary>Require current Shop membership.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool inShop;

    /// <summary>Require an offer leaving tomorrow.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool leavingTomorrow;

    /// <summary>Draft player score checks.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(AllMissingScores), nameof(AllHasScores), nameof(AllMissingFCs), nameof(AllHasFCs))]
    private SongPlayerScoreFilter scoreFilter = SongPlayerScoreFilter.None;

    /// <summary>Per-chart check rows for the visible charts.</summary>
    public List<ScoreFilterChartRow> ScoreRows { get; private set; } = [];

    /// <summary>Placement band picker index (0 = any band; then <see cref="PlayerStatistics.PercentileThresholds"/>).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private int percentileIndex;

    /// <summary>Star picker index (0 = any; 1 = Gold Stars; 2…6 = 5…1 stars).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private int starsIndex;

    /// <summary>Placement band choices.</summary>
    public List<string> PercentileChoices { get; } =
        ["Any Percentile", .. PlayerStatistics.PercentileThresholds.Select(SongScoreBandFilter.BandLabel)];

    /// <summary>Star choices, gold first.</summary>
    public List<string> StarsChoices { get; } = ["Any Stars", .. Enumerable.Range(1, 6).Reverse().Select(SongScoreBandFilter.StarsLabel)];

    /// <summary>Whether the percentile/star pickers show (web: one instrument selected and a player).</summary>
    public bool ShowScoreBand => session.HasPlayer && InstrumentIndex > 0;

    /// <summary>The draft placement-band/star filter, or <see langword="null"/> when none (or no single chart).</summary>
    /// <returns>Filter.</returns>
    public SongScoreBandFilter? ToScoreBand()
    {
        if (ToFilter().Instrument is not { } chart) return null;
        var thresholds = PlayerStatistics.PercentileThresholds;
        int? top = PercentileIndex > 0 && PercentileIndex <= thresholds.Count ? thresholds[PercentileIndex - 1] : null;
        int? stars = StarsIndex is > 0 and <= 6 ? 7 - StarsIndex : null;
        var band = new SongScoreBandFilter(chart, top, stars);
        return band.IsActive ? band : null;
    }

    /// <summary>Instrument change: the band pickers follow the chart.</summary>
    /// <param name="value">New index.</param>
    partial void OnInstrumentIndexChanged(int value) => OnPropertyChanged(nameof(ShowScoreBand));

    /// <summary>Whether Shop toggles can change (hidden Shop keeps them visible but disabled, still clearable by Reset).</summary>
    public bool ShopEnabled => !session.Settings.HideShop;

    /// <summary>Whether the player score section shows.</summary>
    public bool ShowScoreFilters => session.HasPlayer;

    /// <summary>Whether hidden-chart checks are saved but inactive (disclosed).</summary>
    public bool HasHiddenScoreChecks => ScoreFilter.ScopedTo(session.Settings.VisibleInstruments) != ScoreFilter;

    /// <summary>Whether min ≤ max.</summary>
    public bool IsRangeValid => MinDifficulty <= MaxDifficulty;

    /// <summary>Whether the draft is valid and differs from the applied filters.</summary>
    public bool CanApply
    {
        get
        {
            if (!IsRangeValid) return false;
            var applied = session.Settings;
            return ToFilter() != applied.SongFilter || new SongShopFilter(InShop, LeavingTomorrow) != applied.ShopFilter ||
                   !Equals(ScoreFilter, applied.PlayerScoreFilter) || ToScoreBand() != applied.ScoreBandFilter;
        }
    }

    /// <summary>Global Missing Scores switch over visible charts.</summary>
    public bool AllMissingScores { get => All(SongScoreFilterKind.MissingScores); set => SetAll(SongScoreFilterKind.MissingScores, value); }

    /// <summary>Global Has Scores switch.</summary>
    public bool AllHasScores { get => All(SongScoreFilterKind.HasScores); set => SetAll(SongScoreFilterKind.HasScores, value); }

    /// <summary>Global Missing FCs switch.</summary>
    public bool AllMissingFCs { get => All(SongScoreFilterKind.MissingFCs); set => SetAll(SongScoreFilterKind.MissingFCs, value); }

    /// <summary>Global Has FCs switch.</summary>
    public bool AllHasFCs { get => All(SongScoreFilterKind.HasFCs); set => SetAll(SongScoreFilterKind.HasFCs, value); }

    /// <summary>Loads the applied filters (flyout opening).</summary>
    public void Begin()
    {
        IsLive = false;
        var applied = session.Settings;
        OnPropertyChanged(nameof(InstrumentChoices));
        InstrumentIndex = applied.SongFilter.Instrument is { } chart ? IndexOf(chart) : 0;
        MinDifficulty = applied.SongFilter.MinDifficulty;
        MaxDifficulty = applied.SongFilter.MaxDifficulty;
        InShop = applied.ShopFilter.InShop;
        LeavingTomorrow = applied.ShopFilter.LeavingTomorrow;
        ScoreFilter = applied.PlayerScoreFilter.IsValid ? applied.PlayerScoreFilter : SongPlayerScoreFilter.None;
        var band = applied.ScoreBandFilter is { } saved && saved.Instrument == applied.SongFilter.Instrument ? saved : null;
        PercentileIndex = band?.TopPercent is { } top ? PlayerStatistics.PercentileThresholds.ToList().IndexOf(top) + 1 : 0;
        StarsIndex = band?.Stars is { } stars ? 7 - stars : 0;
        OnPropertyChanged(nameof(ShowScoreBand));
        ScoreRows = [.. applied.VisibleInstruments.Select(i => new ScoreFilterChartRow(this, i))];
        OnPropertyChanged(nameof(ScoreRows));
        OnPropertyChanged(nameof(ShopEnabled));
        OnPropertyChanged(nameof(ShowScoreFilters));
        OnPropertyChanged(nameof(HasHiddenScoreChecks));
        IsLive = true;
        OnPropertyChanged(nameof(CanApply));
    }

    /// <summary>Builds the typed public filter from the draft.</summary>
    /// <returns>Filter.</returns>
    public SongFilter ToFilter()
    {
        var visible = session.Settings.VisibleInstruments;
        Instrument? chart = InstrumentIndex > 0 && InstrumentIndex <= visible.Count ? visible[InstrumentIndex - 1] : null;
        return new SongFilter(chart, (int)Math.Clamp(Math.Round(MinDifficulty), 1, 7), (int)Math.Clamp(Math.Round(MaxDifficulty), 1, 7));
    }

    /// <summary>Applies the draft to settings (hidden-chart score checks are removed, like source sanitization).</summary>
    /// <param name="settings">Current settings.</param>
    /// <returns>Updated settings.</returns>
    public AppSettings Apply(AppSettings settings) => settings with
    {
        SongFilter = ToFilter(),
        ShopFilter = new SongShopFilter(InShop, LeavingTomorrow),
        PlayerScoreFilter = ScoreFilter.ScopedTo(settings.VisibleInstruments),
        ScoreBandFilter = ToScoreBand(),
    };

    /// <summary>Reads one draft check.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Value.</returns>
    public bool Get(SongScoreFilterKind kind, Instrument instrument) => ScoreFilter.Contains(kind, instrument);

    /// <summary>Sets one draft check.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="value">Value.</param>
    public void Set(SongScoreFilterKind kind, Instrument instrument, bool value)
    {
        ScoreFilter = ScoreFilter.With(kind, instrument, value);
        foreach (var row in ScoreRows) row.Refresh();
    }

    /// <summary>Clears every filter (applied at once while live).</summary>
    [RelayCommand]
    private void Reset()
    {
        InstrumentIndex = 0;
        MinDifficulty = 1;
        MaxDifficulty = 7;
        InShop = false;
        LeavingTomorrow = false;
        ScoreFilter = SongPlayerScoreFilter.None;
        PercentileIndex = 0;
        StarsIndex = 0;
        foreach (var row in ScoreRows) row.Refresh();
        OnPropertyChanged(nameof(HasHiddenScoreChecks));
    }

    /// <summary>Global switch state over visible charts.</summary>
    /// <param name="kind">Check.</param>
    /// <returns>Whether all visible charts have it.</returns>
    private bool All(SongScoreFilterKind kind) => ScoreFilter.AllVisible(kind, session.Settings.VisibleInstruments);

    /// <summary>Sets a check on every visible chart.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="value">Value.</param>
    private void SetAll(SongScoreFilterKind kind, bool value)
    {
        if (All(kind) == value) return;
        ScoreFilter = ScoreFilter.WithAll(kind, session.Settings.VisibleInstruments, value);
        foreach (var row in ScoreRows) row.Refresh();
    }

    /// <summary>Picker index for a chart.</summary>
    /// <param name="chart">Chart.</param>
    /// <returns>1-based index among visible charts, or 0.</returns>
    private int IndexOf(Instrument chart)
    {
        var index = session.Settings.VisibleInstruments.ToList().IndexOf(chart);
        return index < 0 ? 0 : index + 1;
    }
}

/// <summary>One chart's four score/FC checks in the filter flyout.</summary>
/// <param name="draft">Owning draft.</param>
/// <param name="instrument">Chart.</param>
public sealed partial class ScoreFilterChartRow(SongFilterDraft draft, Instrument instrument) : ObservableObject
{
    /// <summary>Chart.</summary>
    public Instrument Instrument { get; } = instrument;

    /// <summary>Chart label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Missing Scores check.</summary>
    public bool MissingScores { get => draft.Get(SongScoreFilterKind.MissingScores, Instrument); set => draft.Set(SongScoreFilterKind.MissingScores, Instrument, value); }

    /// <summary>Has Scores check.</summary>
    public bool HasScores { get => draft.Get(SongScoreFilterKind.HasScores, Instrument); set => draft.Set(SongScoreFilterKind.HasScores, Instrument, value); }

    /// <summary>Missing FCs check.</summary>
    public bool MissingFCs { get => draft.Get(SongScoreFilterKind.MissingFCs, Instrument); set => draft.Set(SongScoreFilterKind.MissingFCs, Instrument, value); }

    /// <summary>Has FCs check.</summary>
    public bool HasFCs { get => draft.Get(SongScoreFilterKind.HasFCs, Instrument); set => draft.Set(SongScoreFilterKind.HasFCs, Instrument, value); }

    /// <summary>Accessible names for the four checks.</summary>
    public string MissingScoresName => $"{Label}: Missing Scores";

    /// <summary>Accessible name.</summary>
    public string HasScoresName => $"{Label}: Has Scores";

    /// <summary>Accessible name.</summary>
    public string MissingFCsName => $"{Label}: Missing FCs";

    /// <summary>Accessible name.</summary>
    public string HasFCsName => $"{Label}: Has FCs";

    /// <summary>Re-reads every check from the draft.</summary>
    public void Refresh() => OnPropertyChanged(string.Empty);
}
#endregion
