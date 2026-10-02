using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Filter draft
/// <summary>
/// Songs Filter flyout draft in the web <c>FilterModal</c> order: Global and Individual Score &amp; FC toggles (with a
/// player), Item Shop, then Selected Instrument Filters — the Instrument Selector revealing Season, Percentile, Stars
/// (with a player) and Song Intensity bucket switches with Select All / Clear All. Live once <see cref="Begin"/> has
/// loaded the applied filters: the page model commits every change (operator 2026-09-28; no Cancel/Apply).
/// </summary>
public sealed partial class SongFilterDraft : ObservableObject
{
    private readonly FestivalSession session;
    private IReadOnlyList<int> excludedDecades = [];
    private IReadOnlyList<int> excludedDurationBuckets = [];
    private IReadOnlyList<int> excludedIntensities = [];

    /// <summary>Creates the draft.</summary>
    /// <param name="session">Shared session.</param>
    public SongFilterDraft(FestivalSession session)
    {
        this.session = session;
        ShopRows =
        [
            new("Available in Item Shop", "Songs that are available in the Item Shop today.", "fst.songs.filter.shop-available",
                () => ShopAvailable, v => ShopAvailable = v),
            new("Not Available in Item Shop", "Songs that are not in the current Item Shop rotation.", "fst.songs.filter.shop-unavailable",
                () => ShopUnavailable, v => ShopUnavailable = v),
        ];
        DoubleBassRows =
        [
            new("Double Bass Support", "Songs with double bass charts for Pro Drums.", "fst.songs.filter.double-bass.supported",
                () => DoubleBassSupported, v => DoubleBassSupported = v),
            new("No Double Bass Support", "Songs without double bass charts for Pro Drums.", "fst.songs.filter.double-bass.unsupported",
                () => DoubleBassUnsupported, v => DoubleBassUnsupported = v),
        ];
        GlobalRows = BuildGlobalRows();
    }

    /// <summary>The global switches offered under the current Filter Invalid Scores setting (web <c>FilterModal</c>).</summary>
    /// <returns>Rows in form order.</returns>
    private List<FilterToggleRow> BuildGlobalRows() =>
        [.. SongScoreFilterKindInfo.Offered(session.Settings.FilterInvalidScores).Select(kind => new FilterToggleRow(
            kind.Label(), GlobalDescription(kind), "fst.songs.filter.score.global." + KindId(kind),
            () => ScoreFilter.AllVisible(kind, session.Settings.VisibleInstruments),
            v => ScoreFilter = ScoreFilter.WithAll(kind, session.Settings.VisibleInstruments, v)))];

    /// <summary>Whether changes commit immediately (set once <see cref="Begin"/> finishes loading).</summary>
    public bool IsLive { get; private set; }

    #region Draft values
    /// <summary>Selected instrument (web <c>instrumentFilter</c>), or <see langword="null"/> for all.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(HasInstrument))]
    private Instrument? selectedInstrument;

    /// <summary>Show current Shop members.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool shopAvailable = true;

    /// <summary>Show songs not in the current Shop rotation.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool shopUnavailable = true;

    /// <summary>Show songs with Double Bass support.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool doubleBassSupported = true;

    /// <summary>Show songs without Double Bass support.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool doubleBassUnsupported = true;

    /// <summary>Draft player score checks and Season / Percentile / Stars buckets.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(HasHiddenScoreChecks))]
    private SongPlayerScoreFilter scoreFilter = SongPlayerScoreFilter.None;

    /// <summary>Hidden Song Intensity buckets.</summary>
    public IReadOnlyList<int> ExcludedIntensities
    {
        get => excludedIntensities;
        set
        {
            var normalized = SongBuckets.Normalize(value);
            if (normalized.SequenceEqual(excludedIntensities)) return;
            excludedIntensities = normalized;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanApply));
        }
    }

    /// <summary>Hidden release-decade keys.</summary>
    public IReadOnlyList<int> ExcludedDecades
    {
        get => excludedDecades;
        set
        {
            var normalized = SongBuckets.Normalize(value);
            if (normalized.SequenceEqual(excludedDecades)) return;
            excludedDecades = normalized;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanApply));
        }
    }

    /// <summary>Hidden duration bucket keys.</summary>
    public IReadOnlyList<int> ExcludedDurationBuckets
    {
        get => excludedDurationBuckets;
        set
        {
            var normalized = SongBuckets.Normalize(value);
            if (normalized.SequenceEqual(excludedDurationBuckets)) return;
            excludedDurationBuckets = normalized;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanApply));
        }
    }
    #endregion

    #region Sections
    /// <summary>Instruments the selector offers (Settings-visible charts).</summary>
    public List<Instrument> Instruments => [.. session.Settings.VisibleInstruments];

    /// <summary>Whether an instrument is selected (its bucket sections show).</summary>
    public bool HasInstrument => SelectedInstrument is not null;

    /// <summary>Global Score &amp; FC switches (all visible charts at once).</summary>
    public List<FilterToggleRow> GlobalRows { get; private set; }

    /// <summary>Individual Score &amp; FC groups, one per visible chart.</summary>
    public List<ScoreFilterChartRow> ScoreRows { get; private set; } = [];

    /// <summary>Item Shop switches.</summary>
    public List<FilterToggleRow> ShopRows { get; }

    /// <summary>Year and Duration sections.</summary>
    public List<GeneralFilterSection> GeneralSections { get; private set; } = [];

    /// <summary>Double Bass switches.</summary>
    public List<FilterToggleRow> DoubleBassRows { get; }

    /// <summary>Selected-instrument bucket sections (Season / Percentile / Stars need a player).</summary>
    public List<FilterBucketSection> BucketSections { get; private set; } = [];

    /// <summary>Whether the Item Shop availability section shows.</summary>
    public bool ShowShopFilter => !session.Settings.HideShop;

    /// <summary>Whether the player score sections show.</summary>
    public bool ShowScoreFilters => session.HasPlayer;

    /// <summary>Whether the selected-instrument sections show.</summary>
    public bool ShowInstrumentFilters => session.HasPlayer;

    /// <summary>Whether hidden-chart checks are saved but inactive (disclosed).</summary>
    public bool HasHiddenScoreChecks => ScoreFilter.ScopedTo(session.Settings.VisibleInstruments) != ScoreFilter;
    #endregion

    /// <summary>Whether the draft differs from the applied filters.</summary>
    public bool CanApply
    {
        get
        {
            var applied = session.Settings;
            return ToGeneralFilter() != applied.GeneralFilter || ToFilter() != applied.SongFilter ||
                   new SongShopFilter(ShopAvailable, ShopUnavailable) != applied.ShopFilter ||
                   !Equals(ScoreFilter, applied.PlayerScoreFilter);
        }
    }

    /// <summary>Loads the applied filters (flyout opening) and rebuilds the sections.</summary>
    public void Begin()
    {
        IsLive = false;
        var applied = session.Settings;
        var general = applied.GeneralFilter.IsValid ? applied.GeneralFilter : SongGeneralFilter.None;
        var filter = applied.SongFilter.IsValid ? applied.SongFilter : SongFilter.None;
        SelectedInstrument = filter.Instrument is { } chart && applied.VisibleInstruments.Contains(chart) ? chart : null;
        ExcludedDecades = general.ExcludedDecades;
        ExcludedDurationBuckets = general.ExcludedDurationBuckets;
        DoubleBassSupported = general.DoubleBassSupported;
        DoubleBassUnsupported = general.DoubleBassUnsupported;
        ExcludedIntensities = filter.ExcludedIntensities;
        ShopAvailable = applied.ShopFilter.Available;
        ShopUnavailable = applied.ShopFilter.Unavailable;
        ScoreFilter = applied.PlayerScoreFilter.IsValid ? applied.PlayerScoreFilter : SongPlayerScoreFilter.None;
        GlobalRows = BuildGlobalRows();
        ScoreRows = [.. applied.VisibleInstruments.Select(i => new ScoreFilterChartRow(this, i, applied.FilterInvalidScores))];
        GeneralSections =
        [
            new(this, GeneralFilterSectionKind.Year, SongGeneralBuckets.Decades(session.Catalog?.Songs ?? [])),
            new(this, GeneralFilterSectionKind.Duration, SongGeneralBuckets.DurationBuckets(session.Catalog?.Songs ?? [])),
        ];
        BucketSections = [.. SongBuckets.All
            .Where(kind => session.HasPlayer || !kind.IsPlayerScoped())
            .Select(kind => new FilterBucketSection(this, kind, kind.Keys(AvailableSeasons())))];
        foreach (var row in ShopRows) row.IsEnabled = ShowShopFilter;
        OnPropertyChanged(nameof(Instruments));
        OnPropertyChanged(nameof(GlobalRows));
        OnPropertyChanged(nameof(ScoreRows));
        OnPropertyChanged(nameof(GeneralSections));
        OnPropertyChanged(nameof(BucketSections));
        OnPropertyChanged(nameof(ShowShopFilter));
        OnPropertyChanged(nameof(ShowScoreFilters));
        OnPropertyChanged(nameof(ShowInstrumentFilters));
        RefreshRows();
        IsLive = true;
        OnPropertyChanged(nameof(CanApply));
    }

    /// <summary>Builds the typed General filter from the draft.</summary>
    /// <returns>Filter.</returns>
    public SongGeneralFilter ToGeneralFilter() => new()
    {
        ExcludedDecades = ExcludedDecades,
        ExcludedDurationBuckets = ExcludedDurationBuckets,
        DoubleBassSupported = DoubleBassSupported,
        DoubleBassUnsupported = DoubleBassUnsupported,
    };

    /// <summary>Builds the typed public filter from the draft.</summary>
    /// <returns>Filter.</returns>
    public SongFilter ToFilter() => new(SelectedInstrument, ExcludedIntensities);

    /// <summary>Applies the draft to settings (hidden-chart score checks are removed, like source sanitization).</summary>
    /// <param name="settings">Current settings.</param>
    /// <returns>Updated settings.</returns>
    public AppSettings Apply(AppSettings settings) => settings with
    {
        GeneralFilter = ToGeneralFilter(),
        SongFilter = ToFilter(),
        ShopFilter = new SongShopFilter(ShopAvailable, ShopUnavailable),
        PlayerScoreFilter = ScoreFilter.ScopedTo(settings.VisibleInstruments),
    };

    /// <summary>
    /// After a live apply: adopts the applied score filter when applying only dropped hidden-chart checks, so the draft
    /// matches what is saved (and the hidden-checks notice closes).
    /// </summary>
    public void SyncApplied()
    {
        var applied = session.Settings.PlayerScoreFilter;
        if (!Equals(ScoreFilter, applied) && Equals(ScoreFilter.ScopedTo(session.Settings.VisibleInstruments), applied)) ScoreFilter = applied;
    }

    /// <summary>Reads one draft check.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns>Value.</returns>
    public bool Get(SongScoreFilterKind kind, Instrument instrument) => ScoreFilter.Contains(kind, instrument);

    /// <summary>Sets one draft check.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="value">Value.</param>
    public void Set(SongScoreFilterKind kind, Instrument instrument, bool value) => ScoreFilter = ScoreFilter.With(kind, instrument, value);

    /// <summary>Hidden keys of a bucket section.</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Hidden keys.</returns>
    public IReadOnlyList<int> Excluded(SongBucketKind kind) => kind == SongBucketKind.Intensity ? ExcludedIntensities : ScoreFilter.Excluded(kind);

    /// <summary>Replaces a bucket section's hidden keys.</summary>
    /// <param name="kind">Kind.</param>
    /// <param name="keys">Hidden keys.</param>
    public void SetExcluded(SongBucketKind kind, IEnumerable<int> keys)
    {
        if (kind == SongBucketKind.Intensity) ExcludedIntensities = [.. keys];
        else ScoreFilter = ScoreFilter.WithExcluded(kind, keys);
    }

    /// <summary>Hidden keys of a General section.</summary>
    /// <param name="kind">Section kind.</param>
    /// <returns>Hidden keys.</returns>
    public IReadOnlyList<int> GeneralExcluded(GeneralFilterSectionKind kind) =>
        kind == GeneralFilterSectionKind.Year ? ExcludedDecades : ExcludedDurationBuckets;

    /// <summary>Replaces a General section's hidden keys.</summary>
    /// <param name="kind">Section kind.</param>
    /// <param name="keys">Hidden keys.</param>
    public void SetGeneralExcluded(GeneralFilterSectionKind kind, IEnumerable<int> keys)
    {
        if (kind == GeneralFilterSectionKind.Year) ExcludedDecades = [.. keys];
        else ExcludedDurationBuckets = [.. keys];
    }

    /// <summary>Clears every filter (applied at once while live).</summary>
    [RelayCommand]
    private void Reset()
    {
        SelectedInstrument = null;
        ExcludedDecades = [];
        ExcludedDurationBuckets = [];
        ShopAvailable = true;
        ShopUnavailable = true;
        DoubleBassSupported = true;
        DoubleBassUnsupported = true;
        ExcludedIntensities = [];
        ScoreFilter = SongPlayerScoreFilter.None;
        RefreshRows();
    }

    /// <summary>Every change re-reads all switches (global switches mirror the per-chart ones).</summary>
    /// <param name="e">Change.</param>
    protected override void OnPropertyChanged(System.ComponentModel.PropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.PropertyName is nameof(ScoreFilter) or nameof(ExcludedIntensities) or nameof(ExcludedDecades) or
            nameof(ExcludedDurationBuckets) or nameof(ShopAvailable) or nameof(ShopUnavailable) or
            nameof(DoubleBassSupported) or nameof(DoubleBassUnsupported)) RefreshRows();
    }

    /// <summary>Re-reads every switch from the draft.</summary>
    private void RefreshRows()
    {
        foreach (var row in GlobalRows) row.Refresh();
        foreach (var row in ShopRows) row.Refresh();
        foreach (var row in DoubleBassRows) row.Refresh();
        foreach (var section in GeneralSections)
            foreach (var row in section.Rows) row.Refresh();
        foreach (var chart in ScoreRows)
            foreach (var row in chart.Toggles) row.Refresh();
        foreach (var section in BucketSections)
            foreach (var row in section.Rows) row.Refresh();
    }

    /// <summary>Seasons in the selected player's scores (web <c>availableSeasons</c>).</summary>
    /// <returns>Seasons, possibly empty.</returns>
    private IEnumerable<int> AvailableSeasons() =>
        session.SelectedScoreIndex?.Values.SelectMany(charts => charts.Values)
            .Where(s => s.Score > 0 && s.Season is > 0).Select(s => s.Season!.Value) ?? [];

    /// <summary>Web global switch description.</summary>
    /// <param name="kind">Check.</param>
    /// <returns>Sentence.</returns>
    private static string GlobalDescription(SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => "Songs missing scores on any visible instrument.",
        SongScoreFilterKind.HasScores => "Songs with scores on any visible instrument.",
        SongScoreFilterKind.MissingFCs => "Songs missing FCs on any visible instrument.",
        SongScoreFilterKind.OverThreshold => "Songs with scores above the configured CHOpt max score threshold in app settings.",
        _ => "Songs with FCs on any visible instrument.",
    };

    /// <summary>AutomationId segment for a check.</summary>
    /// <param name="kind">Check.</param>
    /// <returns>"missing-scores" etc.</returns>
    internal static string KindId(SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => "missing-scores",
        SongScoreFilterKind.HasScores => "has-scores",
        SongScoreFilterKind.MissingFCs => "missing-fcs",
        SongScoreFilterKind.OverThreshold => "over-threshold",
        _ => "has-fcs",
    };
}
#endregion

#region Rows
/// <summary>One web <c>ToggleRow</c>: label (or star/intensity visual), optional description and a switch.</summary>
/// <param name="label">Label, also the switch's accessible name.</param>
/// <param name="description">Secondary text, or <see langword="null"/>.</param>
/// <param name="automationId">Stable AutomationId.</param>
/// <param name="get">Reads the draft value.</param>
/// <param name="set">Writes the draft value.</param>
public sealed partial class FilterToggleRow(string label, string? description, string automationId, Func<bool> get, Action<bool> set) : ObservableObject
{
    /// <summary>Label and accessible name.</summary>
    public string Label { get; } = label;

    /// <summary>Secondary text.</summary>
    public string Description { get; } = description ?? "";

    /// <summary>Whether <see cref="Description"/> shows.</summary>
    public bool HasDescription => Description.Length > 0;

    /// <summary>Stable AutomationId.</summary>
    public string AutomationId { get; } = automationId;

    /// <summary>Star count drawn instead of the label (1–6, 6 = gold), or 0.</summary>
    public int Stars { get; init; }

    /// <summary>Intensity bars drawn instead of the label (1–7), or 0.</summary>
    public int Bars { get; init; }

    /// <summary>Raw difficulty for the bar meter (<see cref="Bars"/> − 1).</summary>
    public double BarsRaw => Bars - 1;

    /// <summary>Whether the star visual shows.</summary>
    public bool ShowStars => Stars > 0;

    /// <summary>Whether the intensity visual shows.</summary>
    public bool ShowBars => Bars > 0;

    /// <summary>Whether the text label shows.</summary>
    public bool ShowText => !ShowStars && !ShowBars;

    /// <summary>Whether the switch can change.</summary>
    [ObservableProperty]
    private bool isEnabled = true;

    /// <summary>Switch value.</summary>
    public bool IsOn
    {
        get => get();
        set
        {
            if (get() == value) return;
            set(value);
            OnPropertyChanged();
        }
    }

    /// <summary>Re-reads the value.</summary>
    public void Refresh() => OnPropertyChanged(nameof(IsOn));
}

/// <summary>One chart's Individual Score &amp; FC group (web per-instrument Accordion).</summary>
public sealed class ScoreFilterChartRow
{
    /// <summary>Creates the group.</summary>
    /// <param name="draft">Owning draft.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="filterInvalidScores">Filter Invalid Scores setting (offers the Over CHOpt Threshold switch).</param>
    public ScoreFilterChartRow(SongFilterDraft draft, Instrument instrument, bool filterInvalidScores = false)
    {
        Instrument = instrument;
        var name = instrument.Label();
        var id = "fst.songs.filter.score.chart." + instrument.ToString().ToLowerInvariant() + ".";
        Toggles = [.. SongScoreFilterKindInfo.Offered(filterInvalidScores).Select(kind => new FilterToggleRow(
            ChartLabel(kind, name), ChartDescription(kind, name), id + SongFilterDraft.KindId(kind),
            () => draft.Get(kind, instrument), v => draft.Set(kind, instrument, v)))];
    }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Chart label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Group AutomationId.</summary>
    public string AutomationId => "fst.songs.filter.score.chart." + Instrument.ToString().ToLowerInvariant();

    /// <summary>The switches (four, plus Over CHOpt Threshold under Filter Invalid Scores).</summary>
    public List<FilterToggleRow> Toggles { get; }

    /// <summary>Web <c>filter.instrument*</c> label.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="name">Chart name.</param>
    /// <returns>"Missing Lead Scores" etc.</returns>
    public static string ChartLabel(SongScoreFilterKind kind, string name) => kind switch
    {
        SongScoreFilterKind.MissingScores => $"Missing {name} Scores",
        SongScoreFilterKind.HasScores => $"Has {name} Scores",
        SongScoreFilterKind.MissingFCs => $"Missing {name} FCs",
        SongScoreFilterKind.OverThreshold => $"{name} Over CHOpt Threshold",
        _ => $"Has {name} FCs",
    };

    /// <summary>Web <c>filter.instrument*Desc</c>.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="name">Chart name.</param>
    /// <returns>Sentence.</returns>
    public static string ChartDescription(SongScoreFilterKind kind, string name) => kind switch
    {
        SongScoreFilterKind.MissingScores => $"Songs missing scores on {name}.",
        SongScoreFilterKind.HasScores => $"Songs with scores on {name}.",
        SongScoreFilterKind.MissingFCs => $"Songs missing FCs on {name}.",
        SongScoreFilterKind.OverThreshold => $"Songs with {name} scores above the configured CHOpt max score threshold in app settings.",
        _ => $"Songs with FCs on {name}.",
    };
}

/// <summary>General filter sections whose options come from the catalogue.</summary>
public enum GeneralFilterSectionKind
{
    /// <summary>Release decade.</summary>
    Year,
    /// <summary>Duration minute bucket.</summary>
    Duration,
}

/// <summary>A Year or Duration section with Select All / Clear All and catalogue-derived switches.</summary>
public sealed partial class GeneralFilterSection
{
    private readonly SongFilterDraft draft;

    /// <summary>Creates the section.</summary>
    /// <param name="draft">Owning draft.</param>
    /// <param name="kind">Section kind.</param>
    /// <param name="keys">Offered keys.</param>
    public GeneralFilterSection(SongFilterDraft draft, GeneralFilterSectionKind kind, IReadOnlyList<int> keys)
    {
        this.draft = draft;
        Kind = kind;
        Keys = keys;
        Rows = [.. keys.Select(key => new FilterToggleRow(LabelFor(key), null, $"{AutomationId}.{key}",
            () => !draft.GeneralExcluded(kind).Contains(key),
            on => draft.SetGeneralExcluded(kind, on ? draft.GeneralExcluded(kind).Where(k => k != key) : [.. draft.GeneralExcluded(kind), key])))];
    }

    /// <summary>Section kind.</summary>
    public GeneralFilterSectionKind Kind { get; }

    /// <summary>Offered keys.</summary>
    public IReadOnlyList<int> Keys { get; }

    /// <summary>Section title.</summary>
    public string Title => Kind == GeneralFilterSectionKind.Year ? "Year" : "Duration";

    /// <summary>Section hint.</summary>
    public string Hint => Kind == GeneralFilterSectionKind.Year ? "Filter songs by their release decade." : "Filter songs by their duration.";

    /// <summary>Section AutomationId.</summary>
    public string AutomationId => Kind == GeneralFilterSectionKind.Year ? "fst.songs.filter.year" : "fst.songs.filter.duration";

    /// <summary>Select All AutomationId.</summary>
    public string SelectAllId => AutomationId + ".select-all";

    /// <summary>Clear All AutomationId.</summary>
    public string ClearAllId => AutomationId + ".clear-all";

    /// <summary>Accessible name for Select All.</summary>
    public string SelectAllName => $"Select All {Title}";

    /// <summary>Accessible name for Clear All.</summary>
    public string ClearAllName => $"Clear All {Title}";

    /// <summary>Bucket switches.</summary>
    public List<FilterToggleRow> Rows { get; }

    /// <summary>Shows every bucket.</summary>
    [RelayCommand]
    private void SelectAll() => draft.SetGeneralExcluded(Kind, []);

    /// <summary>Hides every offered bucket.</summary>
    [RelayCommand]
    private void ClearAll() => draft.SetGeneralExcluded(Kind, draft.GeneralExcluded(Kind).Concat(Keys));

    private string LabelFor(int key) =>
        Kind == GeneralFilterSectionKind.Year ? SongGeneralBuckets.DecadeLabel(key) : SongGeneralBuckets.DurationLabel(key);
}

/// <summary>A Season / Percentile / Stars / Song Intensity section with its bucket switches.</summary>
public sealed partial class FilterBucketSection
{
    private readonly SongFilterDraft draft;

    /// <summary>Creates the section.</summary>
    /// <param name="draft">Owning draft.</param>
    /// <param name="kind">Kind.</param>
    /// <param name="keys">Offered keys in menu order.</param>
    public FilterBucketSection(SongFilterDraft draft, SongBucketKind kind, IReadOnlyList<int> keys)
    {
        this.draft = draft;
        Kind = kind;
        Keys = keys;
        Rows = [.. keys.Select(key => new FilterToggleRow(kind.Label(key), null, $"{AutomationId}.{key}",
            () => !draft.Excluded(kind).Contains(key),
            on => draft.SetExcluded(kind, on ? draft.Excluded(kind).Where(k => k != key) : [.. draft.Excluded(kind), key]))
        {
            Stars = kind == SongBucketKind.Stars ? key : 0,
            Bars = kind == SongBucketKind.Intensity ? key : 0,
        })];
    }

    /// <summary>Kind.</summary>
    public SongBucketKind Kind { get; }

    /// <summary>Offered keys.</summary>
    public IReadOnlyList<int> Keys { get; }

    /// <summary>Section title.</summary>
    public string Title => Kind.Title();

    /// <summary>Section hint.</summary>
    public string Hint => Kind.Hint();

    /// <summary>Section AutomationId (<c>fst.songs.filter.season</c> …).</summary>
    public string AutomationId => "fst.songs.filter." + Kind.Id();

    /// <summary>Select All AutomationId.</summary>
    public string SelectAllId => AutomationId + ".select-all";

    /// <summary>Clear All AutomationId.</summary>
    public string ClearAllId => AutomationId + ".clear-all";

    /// <summary>Accessible name for Select All.</summary>
    public string SelectAllName => $"Select All {Title}";

    /// <summary>Accessible name for Clear All.</summary>
    public string ClearAllName => $"Clear All {Title}";

    /// <summary>Bucket switches.</summary>
    public List<FilterToggleRow> Rows { get; }

    /// <summary>Shows every bucket (saved keys outside this list, e.g. an old season, are shown again too).</summary>
    [RelayCommand]
    private void SelectAll() => draft.SetExcluded(Kind, []);

    /// <summary>Hides every offered bucket.</summary>
    [RelayCommand]
    private void ClearAll() => draft.SetExcluded(Kind, draft.Excluded(Kind).Concat(Keys));
}
#endregion
