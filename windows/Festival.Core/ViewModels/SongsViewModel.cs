using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Songs
/// <summary>Songs catalogue page: load, search (250 ms debounce), sort and filter drafts, grouped sections.</summary>
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
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Sort dialog draft.</summary>
    public SongSortDraft SortDraft { get; }

    /// <summary>Filter dialog draft.</summary>
    public SongFilterDraft FilterDraft { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowList), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Search box text (applied after <see cref="SearchDebounce"/>).</summary>
    [ObservableProperty]
    private string searchText = "";

    /// <summary>Grouped rows for the list.</summary>
    [ObservableProperty]
    private IReadOnlyList<SongSection> sections = [];

    /// <summary>Visible row count.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CountText))]
    private int resultCount;

    /// <summary>Whether a request is in flight with nothing shown.</summary>
    public bool IsLoading => State == LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowList => State == LoadState.Loaded;

    /// <summary>Whether the no-results view is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>"728 songs" style count.</summary>
    public string CountText => ResultCount == 1 ? "1 song" : string.Create(CultureInfo.CurrentCulture, $"{ResultCount:N0} songs");

    /// <summary>No-results message (names filters when they are active).</summary>
    public string EmptyMessage => IsFilterActive ? "No songs match the filters." : "No songs match your search.";

    /// <summary>Whether a non-default sort is applied (gold tint).</summary>
    public bool IsSortChanged => session.Settings.SongSort != SongSortMode.Title || !session.Settings.SongSortAscending;

    /// <summary>Whether a filter is applied (gold tint).</summary>
    public bool IsFilterActive => session.Settings.SongFilter.IsActive;

    /// <summary>Applied sort label, e.g. "Title ↑".</summary>
    public string SortSummary => session.Settings.SongSort.Label() + (session.Settings.SongSortAscending ? " ↑" : " ↓");

    /// <summary>Loads the catalogue and rebuilds the list.</summary>
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
        }
    }

    /// <summary>Loads on first appearance.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task AppearAsync() => session.Catalog is null || State is LoadState.Idle or LoadState.Failed ? LoadAsync() : Task.CompletedTask;

    /// <summary>Re-reads from the service.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task RefreshAsync() => LoadAsync(force: true);

    /// <summary>Applies the sort draft.</summary>
    [RelayCommand]
    private void ApplySort()
    {
        session.UpdateSettings(s => s with { SongSort = SortDraft.Mode, SongSortAscending = SortDraft.Ascending });
    }

    /// <summary>Applies the filter draft.</summary>
    [RelayCommand]
    private void ApplyFilter() => session.UpdateSettings(s => s with { SongFilter = FilterDraft.ToFilter() });

    /// <summary>Clears the applied filter directly (no-results action).</summary>
    [RelayCommand]
    private void ClearFilter() => session.UpdateSettings(s => s with { SongFilter = SongFilter.None });

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

    /// <summary>Recomputes rows when settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(FestivalSession.Settings) or nameof(FestivalSession.Catalog)) Rebuild();
    }

    /// <summary>Runs search → filter → sort → group over the current catalogue.</summary>
    private void Rebuild()
    {
        if (session.Catalog is not { } catalog) return;
        var settings = session.Settings;
        var rows = SongCatalogQuery.Apply(catalog.Songs, appliedSearch, settings.SongFilter, settings.SongSort, settings.SongSortAscending);
        Sections = SongCatalogQuery.Sections(rows, settings.SongSort);
        ResultCount = rows.Count;
        State = rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        OnPropertyChanged(nameof(IsSortChanged));
        OnPropertyChanged(nameof(IsFilterActive));
        OnPropertyChanged(nameof(SortSummary));
        OnPropertyChanged(nameof(EmptyMessage));
    }
}
#endregion

#region Sort draft
/// <summary>Sort dialog draft: changes stay local until Apply; Reset restores defaults in the draft.</summary>
public sealed partial class SongSortDraft(FestivalSession session) : ObservableObject
{
    /// <summary>Draft mode.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply), nameof(ModeIndex))]
    private SongSortMode mode = SongSortMode.Title;

    /// <summary>Draft direction.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool ascending = true;

    /// <summary>Mode as a list index for radio buttons.</summary>
    public int ModeIndex
    {
        get => (int)Mode;
        set
        {
            if (value >= 0 && value < SongSortModeInfo.All.Count) Mode = (SongSortMode)value;
        }
    }

    /// <summary>Whether the draft differs from the applied sort.</summary>
    public bool CanApply => Mode != session.Settings.SongSort || Ascending != session.Settings.SongSortAscending;

    /// <summary>Loads the applied values (dialog opening).</summary>
    public void Begin()
    {
        Mode = session.Settings.SongSort;
        Ascending = session.Settings.SongSortAscending;
        OnPropertyChanged(nameof(CanApply));
    }

    /// <summary>Restores defaults in the draft only.</summary>
    [RelayCommand]
    private void Reset()
    {
        Mode = SongSortMode.Title;
        Ascending = true;
    }
}
#endregion

#region Filter draft
/// <summary>Filter dialog draft over public data: one charted instrument and a 1–7 difficulty range.</summary>
public sealed partial class SongFilterDraft(FestivalSession session) : ObservableObject
{
    /// <summary>Choices for the instrument picker: index 0 is "All instruments".</summary>
    public IReadOnlyList<string> InstrumentChoices =>
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

    /// <summary>Whether min ≤ max.</summary>
    public bool IsRangeValid => MinDifficulty <= MaxDifficulty;

    /// <summary>Whether the draft is valid and differs from the applied filter.</summary>
    public bool CanApply => IsRangeValid && ToFilter() != session.Settings.SongFilter;

    /// <summary>Loads the applied filter (dialog opening).</summary>
    public void Begin()
    {
        var applied = session.Settings.SongFilter;
        OnPropertyChanged(nameof(InstrumentChoices));
        InstrumentIndex = applied.Instrument is { } chart ? IndexOf(chart) : 0;
        MinDifficulty = applied.MinDifficulty;
        MaxDifficulty = applied.MaxDifficulty;
        OnPropertyChanged(nameof(CanApply));
    }

    /// <summary>Builds the typed filter from the draft.</summary>
    /// <returns>Filter.</returns>
    public SongFilter ToFilter()
    {
        var visible = session.Settings.VisibleInstruments;
        Instrument? chart = InstrumentIndex > 0 && InstrumentIndex <= visible.Count ? visible[InstrumentIndex - 1] : null;
        return new SongFilter(chart, (int)Math.Clamp(Math.Round(MinDifficulty), 1, 7), (int)Math.Clamp(Math.Round(MaxDifficulty), 1, 7));
    }

    /// <summary>Clears the draft (Apply still required).</summary>
    [RelayCommand]
    private void Reset()
    {
        InstrumentIndex = 0;
        MinDifficulty = 1;
        MaxDifficulty = 7;
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
#endregion
