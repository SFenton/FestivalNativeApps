using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Phase
/// <summary>What the Suggestions page shows.</summary>
public enum SuggestionsPhase
{
    /// <summary>No player selected: Choose Profile prompt.</summary>
    NoPlayer,
    /// <summary>Catalogue or scores in flight.</summary>
    Loading,
    /// <summary>Scores are syncing (HTTP 202).</summary>
    Syncing,
    /// <summary>Catalogue or score read failed; see <see cref="SuggestionsViewModel.Status"/>.</summary>
    Failed,
    /// <summary>Nothing to suggest (no generated categories, or all filtered out).</summary>
    Empty,
    /// <summary>Category cards shown.</summary>
    Loaded,
}
#endregion

#region Rows and cards
/// <summary>One tappable row inside a category card.</summary>
/// <param name="Presentation">Display values.</param>
/// <param name="Route">Song Detail destination.</param>
/// <param name="AlbumArt">Artwork reference.</param>
/// <param name="AutomationId">Stable automation ID (<c>fst.suggestions.row.&lt;songId or songId|Solo_X&gt;</c>).</param>
/// <param name="UsesKeyboardIcon">Whether Lead/Pro Lead icons use the keys variant.</param>
/// <param name="IsFirst">Whether this is the card's first row (no separator above it: the header sits outside the card).</param>
public sealed record SuggestionRowItem(SuggestionRowPresentation Presentation, AppRoute Route, string? AlbumArt, string AutomationId, bool UsesKeyboardIcon = false,
    bool IsFirst = false);

/// <summary>One category card.</summary>
/// <param name="Category">Generated (and filtered) category.</param>
/// <param name="Rows">Rows (a concrete <see cref="List{T}"/>: it is bound to <c>ItemsSource</c>, and NativeAOT's CsWinRT only
/// generates the vtables for statically visible concrete collection types; <c>IReadOnlyList</c> threw E_INVALIDARG).</param>
/// <param name="AutomationId">Stable automation ID (<c>fst.suggestions.category.&lt;key&gt;</c>).</param>
public sealed record SuggestionCardItem(SuggestionCategory Category, List<SuggestionRowItem> Rows, string AutomationId)
{
    /// <summary>Card title.</summary>
    public string Title => Category.Title;

    /// <summary>Card subtitle.</summary>
    public string Description => Category.Description;

    /// <summary>Header icon file for a single-instrument category, else empty.</summary>
    public string HeaderIcon => Category.Instrument?.IconFile() ?? "";

    /// <summary>Header icon label.</summary>
    public string HeaderIconLabel => Category.Instrument?.Label() ?? "";

    /// <summary>Whether the header shows an instrument icon.</summary>
    public bool HasHeaderIcon => Category.Instrument is not null;
}
#endregion

#region Suggestions
/// <summary>
/// Suggestions page: one <see cref="SuggestionGenerator"/> per (player, catalogue, score publication) source, web
/// batching (10 first, then 6 per scroll trigger, endless remix, 1,000-category cap), rival data spliced in when
/// <c>/rivals/all</c> answers, and a persisted instrument/type filter applied without regenerating.
/// </summary>
public sealed partial class SuggestionsViewModel : ObservableObject
{
    /// <summary>Categories generated on first appearance.</summary>
    public const int InitialBatch = 10;

    /// <summary>Categories generated per scroll trigger.</summary>
    public const int Batch = 6;

    /// <summary>Most categories kept in one session (web <c>SUGGESTIONS_CATEGORY_LIMIT</c>).</summary>
    public const int CategoryLimit = 1_000;

    private readonly FestivalSession session;
    private readonly ISuggestionFilterStore store;
    private readonly Func<uint> seeds;
    private readonly int categoryLimit;
    private readonly List<(SuggestionCategory Category, int Mix)> generated = [];
    private int mix;
    private bool loading;
    private SuggestionGenerator? generator;
    private object? sourceIdentity;
    private string? sourceAccount;
    private IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, SuggestionScore>>? scores;
    private CancellationTokenSource? rivalsLoad;
    private int loadVersion;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="store">Filter persistence.</param>
    /// <param name="seeds">Seed source per mix (tests and <c>FST_DEBUG_SUGGESTIONS_SEED</c> pass a fixed one).</param>
    /// <param name="categoryLimit">Session category cap; <see cref="CategoryLimit"/> unless a positive smaller cap is
    /// given (tests and <c>FST_DEBUG_SUGGESTIONS_LIMIT</c> reach the end-of-mix footer quickly).</param>
    public SuggestionsViewModel(FestivalSession session, ISuggestionFilterStore store, Func<uint>? seeds = null, int? categoryLimit = null)
    {
        this.session = session;
        this.store = store;
        this.seeds = seeds ?? (() => (uint)Random.Shared.NextInt64(0, uint.MaxValue + 1L));
        this.categoryLimit = categoryLimit is > 0 and < CategoryLimit ? categoryLimit.Value : CategoryLimit;
        filter = store.Load();
        Status = new ServiceStatusViewModel("suggestions", "Suggestions Unavailable", () => LoadAsync(force: true), session.Time);
        FilterDraft = new SuggestionsFilterDraft(this);
        session.PropertyChanged += OnSessionChanged;
        phase = session.HasPlayer ? SuggestionsPhase.Loading : SuggestionsPhase.NoPlayer;
    }

    #region State
    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Filter flyout draft.</summary>
    public SuggestionsFilterDraft FilterDraft { get; }

    /// <summary>Visible category cards.</summary>
    public ObservableCollection<SuggestionCardItem> Cards { get; } = [];

    /// <summary>
    /// Raised after cards were added with the index of the first new card (web <c>revealedCountRef</c>): the end of
    /// the earlier cards for an appended batch, 0 when every card is new (first batch, new mix, filter change). The
    /// page fades only cards from that index; earlier cards were already revealed.
    /// </summary>
    public event EventHandler<int>? CardsAdded;

    /// <summary>Page phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowNoPlayer), nameof(ShowLoading), nameof(ShowSyncing), nameof(ShowError), nameof(ShowEmpty), nameof(ShowList), nameof(EmptyMessage), nameof(ShowHeader))]
    private SuggestionsPhase phase;

    /// <summary>Applied filter.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsFilterActive), nameof(EmptyMessage))]
    private SuggestionFilterSettings filter;

    /// <summary>Whether the generator can produce more categories in this session.</summary>
    [ObservableProperty]
    private bool hasMore;

    /// <summary>Whether the 1,000-category cap was reached.</summary>
    [ObservableProperty]
    private bool reachedLimit;

    /// <summary>
    /// Whether the applied filter hides something a Settings-visible chart could show (accent on the filter button);
    /// toggles left on instruments hidden in Settings don't count.
    /// </summary>
    public bool IsFilterActive => Filter.IsActiveFor(VisibleInstruments);

    /// <summary>
    /// Title and Filter action: hidden behind the spinner until content is ready, then faded in with the first cards
    /// (web <c>headerStagger</c> during <c>LoadPhase.Loading</c>), so the page never appears half-built.
    /// </summary>
    public bool ShowHeader => Phase != SuggestionsPhase.Loading;

    /// <summary>Choose Profile prompt.</summary>
    public bool ShowNoPlayer => Phase == SuggestionsPhase.NoPlayer;

    /// <summary>Progress ring.</summary>
    public bool ShowLoading => Phase == SuggestionsPhase.Loading;

    /// <summary>Syncing message.</summary>
    public bool ShowSyncing => Phase == SuggestionsPhase.Syncing;

    /// <summary>Status view.</summary>
    public bool ShowError => Phase == SuggestionsPhase.Failed;

    /// <summary>Empty message.</summary>
    public bool ShowEmpty => Phase == SuggestionsPhase.Empty;

    /// <summary>Card list.</summary>
    public bool ShowList => Phase == SuggestionsPhase.Loaded;

    /// <summary>Empty-state message; names the filter when it hides everything.</summary>
    public string EmptyMessage => IsFilterActive && generated.Count > 0
        ? "No suggestions match your filters."
        : "Play a few songs and suggestions will appear here.";

    /// <summary>Settings-visible charts in display order.</summary>
    public IReadOnlyList<Instrument> VisibleInstruments => InstrumentInfo.All.Where(session.Settings.VisibleInstruments.Contains).ToList();

    /// <summary>Every category generated in the current session (before filtering).</summary>
    public IReadOnlyList<SuggestionCategory> Generated => generated.Select(g => g.Category).ToList();
    #endregion

    #region Loading
    /// <summary>Loads on appearance; keeps the current mix when its source is unchanged.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task AppearAsync() => LoadAsync(force: false);

    /// <summary>Loads catalogue and scores, then builds (or keeps) the generator.</summary>
    /// <param name="force">Re-read from the service (Retry).</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(bool force = false)
    {
        var version = ++loadVersion;
        if (session.SelectedPlayer is not { } player)
        {
            Reset();
            Phase = SuggestionsPhase.NoPlayer;
            return;
        }
        if (generator is null || force) Phase = SuggestionsPhase.Loading;
        loading = true;
        try
        {
            var catalog = await session.LoadCatalogAsync(force);
            await session.LoadSelectedProfileAsync(force);
            if (version != loadVersion) return;
            switch (session.SelectedProfileStatus)
            {
                case SelectedProfileStatus.Syncing:
                    Reset();
                    Phase = SuggestionsPhase.Syncing;
                    return;
                case SelectedProfileStatus.Failed:
                    Reset();
                    Status.Issue = session.SelectedProfileIssue ?? new ServiceIssue(ServiceIssueKind.Other);
                    Phase = SuggestionsPhase.Failed;
                    return;
                case SelectedProfileStatus.Available when session.SelectedScoreIndex is { } index && session.SelectedProfile is { } profile:
                    Status.Clear();
                    var identity = (player.AccountId, catalog, profile.ObservedPublicationId);
                    // The same source keeps the shown cards: Settings and filter changes re-derive them as they happen,
                    // so Back to the cached page must not rebuild the list and replay its fade-in (#276).
                    if (generator is null || force || !Equals(identity, sourceIdentity))
                        StartMix(identity, catalog, index, player.AccountId);
                    return;
                default:
                    Phase = SuggestionsPhase.Loading;
                    return;
            }
        }
        catch (FestivalApiException error)
        {
            if (version != loadVersion) return;
            Reset();
            Status.Report(error);
            Phase = SuggestionsPhase.Failed;
        }
        finally
        {
            if (version == loadVersion) loading = false;
        }
    }

    /// <summary>Builds a fresh generator for a source and generates the first batch.</summary>
    private void StartMix(object identity, SongsResponse catalog, IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>> index, string accountId)
    {
        Reset();
        sourceIdentity = identity;
        sourceAccount = accountId;
        scores = SuggestionScore.Index(index);
        var season = SuggestionSeason.Effective(catalog.CurrentSeason, scores);
        generator = new SuggestionGenerator(new SuggestionGenerator.Options(seeds(), CurrentSeason: season));
        generator.SetSource(catalog.Songs, scores);
        HasMore = true;
        Generate(InitialBatch);
        _ = LoadRivalsAsync(accountId, generator);
    }

    /// <summary>Best-effort <c>/rivals/all</c> read; spliced into the running generator when it answers.</summary>
    private async Task LoadRivalsAsync(string accountId, SuggestionGenerator target)
    {
        rivalsLoad?.Cancel();
        var cancellation = rivalsLoad = new CancellationTokenSource();
        try
        {
            var response = await session.Api.GetRivalsAllAsync(accountId, cancellation.Token);
            if (cancellation.IsCancellationRequested || !ReferenceEquals(target, generator)) return;
            target.SetRivalData(RivalDataIndex.Build(response));
            if (!HasMore && !ReachedLimit)
            {
                HasMore = true;
                LoadMore();
            }
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException)
        {
            // Rival families are optional; every other family still shows.
        }
    }

    /// <summary>Drops the generator and every card.</summary>
    private void Reset()
    {
        rivalsLoad?.Cancel();
        generator = null;
        sourceIdentity = null;
        sourceAccount = null;
        scores = null;
        generated.Clear();
        mix = 0;
        Cards.Clear();
        HasMore = false;
        ReachedLimit = false;
    }
    #endregion

    #region Incremental loading
    /// <summary>Generates the next batch (scroll trigger); remixes endlessly until the category cap.</summary>
    [RelayCommand]
    public void LoadMore()
    {
        if (generator is null || !HasMore) return;
        Generate(Batch);
    }

    /// <summary>Whether a realized card index should trigger <see cref="LoadMore"/> (third-from-last).</summary>
    /// <param name="index">Realized card index.</param>
    /// <returns><see langword="true"/> near the end of the list.</returns>
    public bool ShouldLoadMore(int index) => HasMore && index >= Cards.Count - 3;

    /// <summary>
    /// Pulls categories until <paramref name="count"/> new cards are visible (the filter may hide some) or the
    /// generator has nothing left even after a remix.
    /// </summary>
    /// <param name="count">Cards wanted.</param>
    /// <param name="announce">Whether to raise <see cref="CardsAdded"/> (a refilter announces its whole list itself).</param>
    private void Generate(int count, bool announce = true)
    {
        var target = generator!;
        var start = Cards.Count;
        var added = 0;
        // Every type switched off: nothing generated could ever show, so don't spin the generator.
        if (SuggestionCategoryTypeInfo.All.All(type => !Filter.IsGlobalEnabled(type)))
        {
            UpdateListPhase();
            return;
        }
        var remixed = false;
        for (var round = 0; added < count && round < 50; round++)
        {
            var remaining = categoryLimit - generated.Count;
            if (remaining <= 0)
            {
                ReachedLimit = true;
                HasMore = false;
                break;
            }
            var next = target.GetNext(Math.Min(count - added, remaining));
            if (next.Count == 0)
            {
                if (remixed || generated.Count == 0)
                {
                    HasMore = false;
                    break;
                }
                target.ResetForEndless();
                mix++;
                remixed = true;
                continue;
            }
            remixed = false;
            foreach (var category in next)
            {
                generated.Add((category, mix));
                if (Card(category, mix) is { } card)
                {
                    Cards.Add(card);
                    added++;
                }
            }
        }
        UpdateListPhase();
        if (announce && added > 0) CardsAdded?.Invoke(this, start);
    }

    /// <summary>Filters and presents one category, or returns <see langword="null"/> when hidden.</summary>
    /// <param name="category">Generated category.</param>
    /// <param name="mixNumber">Endless-remix count when generated; keys repeat across remixes, so later mixes suffix it.</param>
    private SuggestionCardItem? Card(SuggestionCategory category, int mixNumber)
    {
        var visible = VisibleInstruments;
        if (SuggestionCategoryFilter.Visible(category, Filter.EffectiveInstruments(visible), Filter) is not { } shown) return null;
        var rows = shown.Songs.Select((item, index) => new SuggestionRowItem(
            SuggestionRowPresentation.Create(shown, item, scores, visible),
            SuggestionRowPresentation.RouteFor(shown, item),
            item.Song.AlbumArt,
            $"fst.suggestions.row.{item.Id}",
            item.Song.UsesKeyboardIcon,
            IsFirst: index == 0)).ToList();
        var id = mixNumber == 0 ? $"fst.suggestions.category.{category.Key}" : $"fst.suggestions.category.{category.Key}.{mixNumber}";
        return new SuggestionCardItem(shown, rows, id);
    }

    /// <summary>Re-derives cards from the generated list (filter or visible-instrument change); never regenerates.</summary>
    private void Refilter()
    {
        if (generator is null) return;
        Cards.Clear();
        foreach (var (category, mixNumber) in generated)
            if (Card(category, mixNumber) is { } card) Cards.Add(card);
        if (Cards.Count < InitialBatch && HasMore) Generate(InitialBatch - Cards.Count, announce: false);
        else UpdateListPhase();
        if (Cards.Count > 0) CardsAdded?.Invoke(this, 0);
    }

    private void UpdateListPhase()
    {
        Phase = Cards.Count > 0 ? SuggestionsPhase.Loaded : SuggestionsPhase.Empty;
        OnPropertyChanged(nameof(EmptyMessage));
    }

    /// <summary>Starts a new mix from the same source (after the cap, or on request).</summary>
    [RelayCommand]
    private void StartNewMix()
    {
        if (sourceIdentity is null || session.Catalog is not { } catalog || session.SelectedScoreIndex is not { } index ||
            session.SelectedPlayer is not { } player) return;
        StartMix(sourceIdentity, catalog, index, player.AccountId);
    }
    #endregion

    #region Filter
    /// <summary>Applies and persists a filter, then re-derives the visible cards.</summary>
    /// <param name="next">New filter.</param>
    public void ApplyFilter(SuggestionFilterSettings next)
    {
        if (next.Equals(Filter)) return;
        Filter = next;
        store.Save(next);
        Refilter();
    }

    /// <summary>Tracks player, profile and instrument-visibility changes.</summary>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(FestivalSession.Settings):
                if (session.SelectedPlayer is null)
                {
                    loadVersion++;
                    Reset();
                    Phase = SuggestionsPhase.NoPlayer;
                }
                else if (sourceAccount is { } account &&
                         !string.Equals(account, session.SelectedPlayer.AccountId, StringComparison.OrdinalIgnoreCase))
                {
                    Reset();
                    _ = LoadAsync();
                }
                else
                {
                    OnPropertyChanged(nameof(VisibleInstruments));
                    OnPropertyChanged(nameof(IsFilterActive));
                    // An open filter follows Settings at once (instrument list, selector and switch states).
                    if (FilterDraft.IsLive) FilterDraft.Begin();
                    Refilter();
                }
                break;
            case nameof(FestivalSession.SelectedProfileStatus) when !loading && session.HasPlayer &&
                session.SelectedProfileStatus is not SelectedProfileStatus.Loading:
                // Another page (re)loaded the selected scores: rebuild if the source changed, else keep the mix.
                _ = LoadAsync();
                break;
        }
    }
    #endregion
}
#endregion
