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
    private (SongSortMode Mode, bool Ascending)? builtSort;
    private bool publicationRefreshing;

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
        session.PublicationAdvanced += (_, _) => _ = RefreshForPublicationAsync();
        PublicationSwap = new LoadSwap(session.Time, initiallyVisible: true);
    }

    /// <summary>Minimum spinner hold during a publication refresh (load-transition R3/R9, Apple's 400 ms minimum).</summary>
    public static readonly TimeSpan PublicationRefreshHold = TimeSpan.FromMilliseconds(400);

    /// <summary>Screen-reader text for a publication refresh (load-transition R9).</summary>
    public const string PublicationRefreshText = "Loading new scores";

    /// <summary>
    /// In-place refresh for a new publication (load-transition R9, web <c>PublicationBoundary</c>): the list fades out, a
    /// spinner holds while the catalogue, Item Shop and player scores re-read for the new generation, then the rebuilt
    /// list fades in. The page stays put: search, filters, sort and page tools are unchanged.
    /// </summary>
    public LoadSwap PublicationSwap { get; }

    /// <summary>Whether the refresh fades (set by the view from its motion policy; tests leave it off).</summary>
    public bool AnimatePublicationRefresh { get; set; }

    /// <summary>Whether a publication refresh hides the list (rows and notices are held until it commits).</summary>
    public bool IsPublicationRefreshing => publicationRefreshing;

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
    private List<SongNotice> notices = [];

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
    public string EmptyMessage => IsFilterActive ? "No songs match your filters. Try adjusting your search or filters." : "No songs match your search.";

    /// <summary>Whether a non-default sort is applied (gold tint).</summary>
    public bool IsSortChanged => session.Settings.SongSort != SongSortMode.Title || !session.Settings.SongSortAscending;

    /// <summary>Whether any saved filter is set (gold tint).</summary>
    /// <remarks>General filters always count; selected-instrument and player filters count only with a player selected.</remarks>
    public bool IsFilterActive =>
        session.Settings.GeneralFilter.IsActive || (!session.Settings.HideShop && session.Settings.ShopFilter.IsActive) ||
        (session.HasPlayer && (session.Settings.SongFilter.IsActive ||
            (session.Settings.PlayerScoreFilter.IsValid && session.Settings.PlayerScoreFilter.AppliesTo(session.Settings.SongFilter.Instrument))));

    /// <summary>Filter button status for UI Automation: "Filters applied" while <see cref="IsFilterActive"/>, else empty.</summary>
    public string FilterStatus => IsFilterActive ? "Filters applied" : "";

    /// <summary>Whether the Filter button shows. General filters are available with or without a selected profile.</summary>
    public bool ShowFilterButton => true;

    /// <summary>Applied sort label, e.g. "Title ↑".</summary>
    public string SortSummary => session.Settings.SongSort.Label() + (session.Settings.SongSortAscending ? " ↑" : " ↓");

    /// <summary>
    /// Applied sort in words for UI Automation help text, e.g. "Title, ascending": the button's name stays "Sort Songs",
    /// so screen readers would otherwise not hear <see cref="SortSummary"/>'s arrow label.
    /// </summary>
    public string SortDescription => session.Settings.SongSort.Label() + (session.Settings.SongSortAscending ? ", ascending" : ", descending");

    /// <summary>Whether a saved filter is corrupt (the list waits for an explicit Reset).</summary>
    private bool InvalidSavedFilter =>
        !session.Settings.GeneralFilter.IsValid || !session.Settings.PlayerScoreFilter.IsValid || !session.Settings.SongFilter.IsValid;

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

    /// <summary>
    /// Refreshes in place for a newer publication (load-transition R9). Rows, notices and the count stay as they were
    /// behind the spinner, so the older list is never rebuilt against the newer generation (which would show "Player
    /// scores paused until songs update" until the reads finish, #616). The catalogue, Item Shop and player scores are
    /// re-read together and applied in one rebuild. A failed catalogue read still ends in the explicit paused and failed
    /// state, since the retained rows are from the older publication. Without a shown list this is a plain reload.
    /// </summary>
    /// <returns>Refresh task.</returns>
    public async Task RefreshForPublicationAsync()
    {
        if (session.Catalog is null || State is not (LoadState.Loaded or LoadState.Empty))
        {
            await LoadAsync(force: true);
            return;
        }
        SetPublicationRefreshing(true);
        var animate = AnimatePublicationRefresh;
        var hold = Task.Delay(PublicationRefreshHold, session.Time);
        var request = await PublicationSwap.BeginReloadAsync(animate, hasContent: true);
        FestivalApiException? failure = null;
        try
        {
            await session.LoadCatalogAsync(force: true);
        }
        catch (FestivalApiException error)
        {
            failure = error;
        }
        if (failure is null)
        {
            await session.TryLoadShopAsync(force: true);
            await SongScoreSource.LoadAsync(session, force: true);
        }
        await hold;
        await PublicationSwap.CommitAsync(request, () =>
        {
            SetPublicationRefreshing(false);
            Rebuild();
            if (failure is null)
            {
                Status.Clear();
                return;
            }
            Status.Report(failure);
            State = LoadState.Failed;
        }, animate);
    }

    /// <summary>Starts or ends the hold on rebuilds during a publication refresh.</summary>
    /// <param name="value">Whether the refresh hides the list.</param>
    private void SetPublicationRefreshing(bool value)
    {
        if (publicationRefreshing == value) return;
        publicationRefreshing = value;
        OnPropertyChanged(nameof(IsPublicationRefreshing));
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
    private void ApplyFilter()
    {
        session.UpdateSettings(FilterDraft.Apply);
        FilterDraft.SyncApplied();
    }

    /// <summary>Clears every applied filter (no-results and invalid-filter action).</summary>
    [RelayCommand]
    private void ClearFilter() => session.UpdateSettings(s => s with
    {
        GeneralFilter = SongGeneralFilter.None, SongFilter = SongFilter.None, ShopFilter = SongShopFilter.None,
        PlayerScoreFilter = SongPlayerScoreFilter.None,
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
        if (session.Catalog is not { } catalog || publicationRefreshing) return;
        var settings = session.Settings;
        OnPropertyChanged(nameof(IsSortChanged));
        OnPropertyChanged(nameof(IsFilterActive));
        OnPropertyChanged(nameof(FilterStatus));
        OnPropertyChanged(nameof(ShowFilterButton));
        OnPropertyChanged(nameof(SortSummary));
        OnPropertyChanged(nameof(SortDescription));
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

        var scores = SongScoreSource.ForSongs(session, catalog.Songs);
        var offers = settings.HideShop ? null : session.ShopOffersForCatalog;
        var result = SongListPipeline.Run(new SongListInputs
        {
            Songs = catalog.Songs,
            Search = appliedSearch,
            GeneralFilter = settings.GeneralFilter,
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
            Details = scores.Available ? scores.Detail : null,
        });

        var projector = new SongRowProjector(settings, catalog.CurrentSeason, offers, scores, result.EffectiveSort);
        IReadOnlyList<SongRowSection> next = [.. result.Sections.Select(s => new SongRowSection(s.Label, [.. s.Songs.Select(projector.Project)],
            SongListPipeline.SectionAutomationId(result.EffectiveSort, s.Label)))];
        // An unchanged list keeps its objects: Back to Songs re-runs this, and a rebind would replay the entrance fade
        // and re-estimate the virtualized layout at the old offset, landing sections away (back-keeps-place, issue #560).
        // A sort change always replaces it, since the page starts a new sort at the top.
        var sort = (settings.SongSort, settings.SongSortAscending);
        if (sort != builtSort || !SongRowSection.SameContent(Sections, next)) Sections = next;
        builtSort = sort;
        // No quick-jump under the Year sort (operator 2026-09-28): decade headers stay, the zoomed-out index does not.
        HasJumpIndex = settings.SongSort != SongSortMode.Year &&
                       (Sections.Count > 1 || (Sections.Count == 1 && Sections[0].Label.Length > 0));
        ResultCount = result.Count;
        var notices = new List<SongNotice>();
        if (scores.Notice is { } scoreNotice) notices.Add(new(SongNotice.ProfilePausedId, scoreNotice));
        if (result.SortPaused is { } sortPaused) notices.Add(new(SongNotice.SortPausedId, sortPaused));
        if (result.ShopFilterPaused is { } shopPaused) notices.Add(new(SongNotice.ShopFilterPausedId, shopPaused));
        if (result.ScoreFilterPaused is { } scorePaused) notices.Add(new(SongNotice.ScoreFilterPausedId, scorePaused));
        if (!Notices.SequenceEqual(notices)) Notices = notices;
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
/// <param name="sort">Sort actually applied (<see cref="SongListResult.EffectiveSort"/>); Last Played rows show their date.</param>
public sealed class SongRowProjector(AppSettings settings, int? currentSeason, IReadOnlyDictionary<string, ShopSong>? offers, SongScoreSource scores,
    SongSortMode sort = SongSortMode.Title)
{
    private readonly bool chips = SongInstrumentStatusPolicy.ShowsChips(
        scores.HasPlayer, scores.Available, settings.ShowInstrumentIcons, settings.SongFilter.Instrument);

    private readonly Instrument? metadataChart = settings.SongFilter.Instrument ?? settings.VisibleInstruments.FirstOrDefault();

    /// <summary>Last Played sort with no chart filter: rows lead with the latest play across charts (web <c>SongRow</c>).</summary>
    private readonly bool latestAcrossCharts = sort == SongSortMode.LastPlayed &&
        settings.SongFilter.ScopedTo(settings.VisibleInstruments).Instrument is null;

    private readonly Instrument[] playedCharts = [.. InstrumentInfo.All.Where(settings.VisibleInstruments.Contains)];

    /// <summary>Projects one song.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <returns>Row item.</returns>
    public SongRowItem Project(Song song)
    {
        var offer = offers?.GetValueOrDefault(song.SongId);
        var highlight = ShopPresentationPolicy.Highlight(offer, settings.HideShop, settings.DisableShopHighlighting);
        var inShop = offer is not null && !settings.HideShop && !settings.DisableShopHighlighting;
        var filterChart = scores.HasPlayer ? settings.SongFilter.Instrument : null;
        var filterRaw = filterChart is { } f ? song.Difficulty?.ChartedValue(f) : null;
        if (!scores.HasPlayer)
            return new SongRowItem(song) { Highlight = highlight, InShop = inShop, Chart = filterRaw is null ? null : filterChart, ChartRaw = filterRaw };
        if (chips)
        {
            return new SongRowItem(song)
            {
                Highlight = highlight, InShop = inShop,
                Chips = SongInstrumentStatusPolicy.Badges(song, settings.VisibleInstruments, chart => scores.Facts!(song.SongId, chart)),
                Metadata = LatestPlayed(song) is { } played ? [played] : [],
                Warning = Warning(song, filterChart),
            };
        }
        if (!scores.Available || metadataChart is not { } chart)
        {
            return new SongRowItem(song)
            {
                Highlight = highlight, InShop = inShop, Chart = filterRaw is null ? null : filterChart, ChartRaw = filterRaw,
                ScoreState = scores.RowState,
            };
        }
        var detail = scores.Detail!(song.SongId, chart);
        var fields = detail is null ? [] : SongMetadataPolicy.Fields(detail, chart, song, currentSeason, settings,
            lastPlayedSort: sort == SongSortMode.LastPlayed && !latestAcrossCharts);
        List<SongMetadataField> metadata = LatestPlayed(song) is { } latest ? [latest, .. fields] : fields;
        return new SongRowItem(song)
        {
            Highlight = highlight, InShop = inShop,
            Chart = chart,
            ChartRaw = metadata.Count == 0 ? song.Difficulty?.ChartedValue(chart) : null,
            Metadata = metadata,
            ScoreState = metadata.Count > 0 ? null : song.Supports(chart) ? "No score" : $"No {chart.Label()} chart",
            Warning = Warning(song, filterChart),
        };
    }

    /// <summary>
    /// The unfiltered Last Played sort's entry: the song's most recent play across Settings-visible charts, with that
    /// chart's icon (web <c>SongRow</c>); <see langword="null"/> under any other sort or a chart filter, or without a play.
    /// </summary>
    /// <param name="song">Catalogue row.</param>
    /// <returns>Entry, or <see langword="null"/>.</returns>
    private SongMetadataField? LatestPlayed(Song song) =>
        latestAcrossCharts && scores.Detail is { } detail &&
        SongMetadataPolicy.LatestPlay(playedCharts, chart => detail(song.SongId, chart)) is { } play
            ? SongMetadataPolicy.LastPlayedField(play.At, play.Chart)
            : null;

    /// <summary>
    /// The row's invalid-score indicator (web <c>SongRow</c> + <c>InvalidScoreIcon</c>): every visible chart whose shown
    /// score was replaced, dropped or kept over the CHOpt maximum, narrowed to the single-chart filter when one is set.
    /// </summary>
    /// <param name="song">Catalogue row.</param>
    /// <param name="filterChart">Single-chart filter.</param>
    /// <returns>Warning, or <see langword="null"/> when no described chart differs (or Filter Invalid Scores is off).</returns>
    private InvalidScoreWarning? Warning(Song song, Instrument? filterChart)
    {
        if (scores.Reason is not { } reason) return null;
        Dictionary<Instrument, InvalidScoreReason>? reasons = null;
        foreach (var chart in settings.VisibleInstruments)
            if (reason(song.SongId, chart) is { } why) (reasons ??= [])[chart] = why;
        return reasons is null ? null : InvalidScoreWarning.Of(song.Title, reasons, filterChart);
    }
}
#endregion

#region Sort draft
/// <summary>
/// Sort flyout state, shared by Songs and the Item Shop (issue #379). Once <see cref="Begin"/> has loaded the applied
/// sort the draft is live: the page model commits every change (and Reset) at once, so the flyout has no Cancel or
/// Apply.
/// </summary>
public sealed partial class SongSortDraft : ObservableObject
{
    private readonly Func<List<SongSortMode>> availableModes;
    private readonly Func<SongSortMode> appliedMode;
    private readonly Func<bool> appliedAscending;

    /// <summary>Creates the Songs sort draft (the web Sort modal's modes; applied values from the Songs sort).</summary>
    /// <param name="session">Shared session.</param>
    public SongSortDraft(FestivalSession session)
        : this(
            () => SongSortModeInfo.ModesFor(session.HasPlayer,
                session.Settings.SongFilter.ScopedTo(session.Settings.VisibleInstruments).Instrument is not null, session.Settings.HideShop),
            () => session.Settings.SongSort,
            () => session.Settings.SongSortAscending)
    {
    }

    /// <summary>Creates a draft over any applied sort.</summary>
    /// <param name="availableModes">Modes offered, in menu order.</param>
    /// <param name="appliedMode">Applied mode.</param>
    /// <param name="appliedAscending">Applied direction.</param>
    private SongSortDraft(Func<List<SongSortMode>> availableModes, Func<SongSortMode> appliedMode, Func<bool> appliedAscending)
    {
        this.availableModes = availableModes;
        this.appliedMode = appliedMode;
        this.appliedAscending = appliedAscending;
    }

    /// <summary>Creates the Item Shop sort draft (<see cref="ShopOfferSort.Modes"/>; applied values from the Shop sort).</summary>
    /// <param name="session">Shared session.</param>
    /// <returns>Draft.</returns>
    public static SongSortDraft ForShop(FestivalSession session) =>
        new(() => [.. ShopOfferSort.Modes], () => session.Settings.ShopSort, () => session.Settings.ShopSortAscending);

    /// <summary>
    /// Creates a detached draft for the First Run <c>songs-sort</c> demo (issue #380): the given modes with the default
    /// Title ascending sort applied, never live and bound to no settings, so the guide shows the real form without
    /// touching the user's sort.
    /// </summary>
    /// <param name="modes">Modes offered, in menu order.</param>
    /// <returns>Draft showing the default sort.</returns>
    public static SongSortDraft ForDemo(IReadOnlyList<SongSortMode> modes)
    {
        List<SongSortMode> offered = [.. modes];
        return new(() => offered, () => SongSortMode.Title, () => true);
    }

    /// <summary>Whether changes commit immediately (set once <see cref="Begin"/> finishes loading).</summary>
    public bool IsLive { get; private set; }

    /// <summary>Draft mode.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(ModeIndex))]
    private SongSortMode mode = SongSortMode.Title;

    /// <summary>Draft direction.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(Descending), nameof(DirectionIndex))]
    private bool ascending = true;

    /// <summary>The Descending choice (the inverse of <see cref="Ascending"/>, for the second direction row).</summary>
    public bool Descending
    {
        get => !Ascending;
        set => Ascending = !value;
    }

    /// <summary>Direction as an index for the Direction radio group: 0 Ascending, 1 Descending (other values are ignored).</summary>
    public int DirectionIndex
    {
        get => Ascending ? 0 : 1;
        set
        {
            if (value is 0 or 1) Ascending = value == 0;
        }
    }

    /// <summary>Ascending row subtitle (web <c>sort.ascendingHintSongs</c> without the repeated word).</summary>
    public const string AscendingHint = "A–Z, low–high";

    /// <summary>Descending row subtitle (web <c>sort.descendingHintSongs</c>).</summary>
    public const string DescendingHint = "Z–A, high–low";

    /// <summary>Available modes (on Songs, Item Shop is removed while the Shop is hidden).</summary>
    public List<SongSortMode> Modes => availableModes();

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
    public bool CanApply => Mode != appliedMode() || Ascending != appliedAscending();

    /// <summary>Loads the applied values (flyout opening).</summary>
    public void Begin()
    {
        IsLive = false;
        OnPropertyChanged(nameof(Modes));
        OnPropertyChanged(nameof(ModeLabels));
        Mode = appliedMode();
        Ascending = appliedAscending();
        OnPropertyChanged(nameof(ModeIndex));
        OnPropertyChanged(nameof(DirectionIndex));
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
