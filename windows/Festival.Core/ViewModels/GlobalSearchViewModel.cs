using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Global search
/// <summary>
/// The one global-search engine (global-search spec): trimmed query, 2-character minimum, 250 ms debounce, local
/// song matches ready as soon as the debounce fires (title-bar suggestions and the Songs scope), players from the
/// keyless account search and bands from the keyless band search (both started together after the debounce in every
/// scope, like the web; issue #320), one page spinner that waits for every read the scope shows (issue #299),
/// per-scope empty/error states without Retry, cancellation of superseded queries and a polite count announcement.
/// <see cref="ForPlayers"/> is the same engine limited to players for the compact pickers (the title-bar profile
/// flyout and Find Rival); it never requests bands.
/// </summary>
public sealed partial class GlobalSearchViewModel : ObservableObject
{
    /// <summary>Debounce (web <c>DEBOUNCE_MS</c>).</summary>
    public static readonly TimeSpan Debounce = TimeSpan.FromMilliseconds(250);

    private readonly FestivalSession session;
    private readonly bool playersOnly;
    private readonly bool excludeSelected;
    private CancellationTokenSource? search;
    private bool seeding;

    /// <summary>Creates an empty search (title-bar box).</summary>
    /// <param name="session">Shared session.</param>
    public GlobalSearchViewModel(FestivalSession session)
    {
        this.session = session;
        PlayersStatus = new ServiceStatusViewModel("global-search.players", "Player search unavailable", RetryAsync, session.Time);
        BandsStatus = new ServiceStatusViewModel("global-search.bands", "Bands unavailable", RetryAsync, session.Time);
    }

    /// <summary>Creates the Search page's model from its route, reusing a settled title-bar search for the same query.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Initial query and scope.</param>
    /// <param name="seed">Title-bar model whose settled results may be reused (no second request).</param>
    public GlobalSearchViewModel(FestivalSession session, AppRoute.Search route, GlobalSearchViewModel? seed = null) : this(session)
    {
        Scope = route.Scope;
        var text = GlobalSearchResults.Normalize(route.Text);
        if (seed is { IsSettled: true } && seed.SettledQuery == text && text.Length >= GlobalSearchResults.MinQueryLength &&
            seed.PlayersState != LoadState.Failed && seed.BandsState != LoadState.Failed)
        {
            seeding = true;
            Query = text;
            seeding = false;
            SettledQuery = text;
            Songs = seed.Songs;
            SongsState = seed.SongsState;
            Players = seed.Players;
            PlayersState = seed.PlayersState;
            Bands = seed.Bands;
            BandsState = seed.BandsState;
            Suggestions = seed.Suggestions;
            Refresh();
            return;
        }
        seeding = true;
        Query = route.Text;
        seeding = false;
        if (GlobalSearchResults.IsSearchable(text)) Pending = Start(text, debounce: false);
    }

    /// <summary>Creates a players-only search (no catalogue matching, no suggestions).</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="excludeSelected">Drop the selected player from the rows (Find Rival).</param>
    private GlobalSearchViewModel(FestivalSession session, bool excludeSelected) : this(session)
    {
        playersOnly = true;
        this.excludeSelected = excludeSelected;
        Scope = SearchScope.Players;
    }

    /// <summary>Players-only search for the profile flyout and Find Rival: same debounce, limits and failure states.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="excludeSelected">Drop the selected player from the rows (Find Rival: you are not your own rival).</param>
    /// <returns>A search locked to <see cref="SearchScope.Players"/>.</returns>
    public static GlobalSearchViewModel ForPlayers(FestivalSession session, bool excludeSelected = false) => new(session, excludeSelected);

    /// <summary>Raised once per settled query with the result-count announcement ("3 songs, 10 players").</summary>
    public event EventHandler<string>? ResultsAnnounced;

    /// <summary>
    /// Raised when a results section appears (<see cref="SearchScope.Songs"/>, <see cref="SearchScope.Players"/> or
    /// <see cref="SearchScope.Bands"/>):
    /// its rows were held behind the one spinner until every read settled, so the page re-arms that list's stagger and
    /// the rows fade as the spinner clears (web: "rows fade up with a stagger"). Raised again only after the section
    /// was hidden (a new query, scope change or the spinner).
    /// </summary>
    public event EventHandler<SearchScope>? SectionShown;

    /// <summary>Whether the Songs section was showing at the last refresh.</summary>
    private bool songsShown;

    /// <summary>Whether the Players section was showing at the last refresh.</summary>
    private bool playersShown;

    /// <summary>Whether the Bands section was showing at the last refresh.</summary>
    private bool bandsShown;

    #region State
    /// <summary>User text.</summary>
    [ObservableProperty]
    private string query = "";

    /// <summary>Scope filter (All = the web's no-chip state).</summary>
    [ObservableProperty]
    private SearchScope scope;

    /// <summary>Song matches for <see cref="SettledQuery"/> (≤20, catalogue order).</summary>
    [ObservableProperty]
    private List<GlobalSongResult> songs = [];

    /// <summary>Player matches for <see cref="SettledQuery"/> (≤10).</summary>
    [ObservableProperty]
    private List<GlobalPlayerResult> players = [];

    /// <summary>Band matches for <see cref="SettledQuery"/> (≤10, the canonical band cards).</summary>
    [ObservableProperty]
    private List<PlayerBandCardViewModel> bands = [];

    /// <summary>Title-bar suggestion items.</summary>
    [ObservableProperty]
    private List<GlobalSuggestion> suggestions = [];

    /// <summary>Songs lifecycle for the settled query.</summary>
    [ObservableProperty]
    private LoadState songsState;

    /// <summary>Players lifecycle for the settled query.</summary>
    [ObservableProperty]
    private LoadState playersState;

    /// <summary>Bands lifecycle for the settled query (<see cref="LoadState.Empty"/> without a request for the pickers).</summary>
    [ObservableProperty]
    private LoadState bandsState;

    /// <summary>Whether a newer query is waiting for the debounce.</summary>
    [ObservableProperty]
    private bool isDebouncing;

    /// <summary>Query whose results are shown.</summary>
    public string SettledQuery { get; private set; } = "";

    /// <summary>Last announcement raised.</summary>
    public string LastAnnouncement { get; private set; } = "";

    /// <summary>Players failure presentation (freeze → "Scores are updating" with automatic retry).</summary>
    public ServiceStatusViewModel PlayersStatus { get; }

    /// <summary>Bands failure presentation (same rules as <see cref="PlayersStatus"/>).</summary>
    public ServiceStatusViewModel BandsStatus { get; }

    /// <summary>Current search task (tests and the view await nothing; exposed for determinism).</summary>
    internal Task? Pending { get; private set; }

    /// <summary>Whether songs, players and bands have all finished for the settled query.</summary>
    public bool IsSettled => SettledQuery.Length > 0 && !IsDebouncing && IsDone(SongsState) && IsDone(PlayersState) && IsDone(BandsState);

    /// <summary>Whether a read finished (rows, nothing or a failure).</summary>
    /// <param name="state">Lifecycle.</param>
    /// <returns><see langword="true"/> once settled.</returns>
    private static bool IsDone(LoadState state) => state is LoadState.Loaded or LoadState.Empty or LoadState.Failed;
    #endregion

    #region Presentation
    /// <summary>Whether the query is too short to search.</summary>
    public bool IsShortQuery => !GlobalSearchResults.IsSearchable(Query);

    /// <summary>Whether every scope finished with nothing (All view shows one "No results found.").</summary>
    private bool AllEmpty => SongsState == LoadState.Empty && PlayersState == LoadState.Empty && BandsState == LoadState.Empty;

    /// <summary>Whether results for the current text are on screen (not short and not behind the one centred spinner).</summary>
    private bool ShowsResults => !IsShortQuery && SettledQuery.Length > 0 && !IsBusy;

    /// <summary>Whether the Songs section is shown.</summary>
    public bool ShowSongsSection => ShowsResults && Scope is SearchScope.All or SearchScope.Songs &&
                                    (Songs.Count > 0 || SongsState == LoadState.Failed);

    /// <summary>Whether song rows are shown (their card is hidden otherwise).</summary>
    public bool HasSongRows => Songs.Count > 0;

    /// <summary>Whether player rows are shown (their card is hidden otherwise).</summary>
    public bool HasPlayerRows => Players.Count > 0;

    /// <summary>Whether band cards are shown (their list is hidden otherwise).</summary>
    public bool HasBandRows => Bands.Count > 0;

    /// <summary>Whether the Songs section shows its failure line.</summary>
    public bool SongsFailed => SongsState == LoadState.Failed;

    /// <summary>
    /// Whether the Players section is shown (rows or failure; progress is the one centred spinner). An empty envelope
    /// never shows a section: in All it is hidden like the web (<c>shouldRenderGlobalSection</c>), in Players it is the
    /// centred empty state.
    /// </summary>
    public bool ShowPlayersSection => ShowsResults && Scope is SearchScope.All or SearchScope.Players &&
                                      PlayersState is LoadState.Loaded or LoadState.Failed;

    /// <summary>Whether the account search is running (the pickers' "Searching…"; the page's spinner waits for it).</summary>
    public bool PlayersLoading => PlayersState == LoadState.Loading;

    /// <summary>Whether the Players section shows the service-status card.</summary>
    public bool PlayersFailed => PlayersState == LoadState.Failed;

    /// <summary>Whether the account search finished with an empty envelope.</summary>
    public bool PlayersEmpty => PlayersState == LoadState.Empty;

    /// <summary>
    /// Whether the Bands section is shown (cards or failure), with the same rules as <see cref="ShowPlayersSection"/>:
    /// an empty envelope is hidden in All and the centred empty state in Bands.
    /// </summary>
    public bool ShowBandsSection => ShowsResults && Scope is SearchScope.All or SearchScope.Bands &&
                                    BandsState is LoadState.Loaded or LoadState.Failed;

    /// <summary>Whether the band search is running (the page's spinner waits for it in All and Bands).</summary>
    public bool BandsLoading => BandsState == LoadState.Loading;

    /// <summary>Whether the Bands section shows the service-status card (never read as "No bands found").</summary>
    public bool BandsFailed => BandsState == LoadState.Failed;

    /// <summary>Whether the band search finished with an empty envelope.</summary>
    public bool BandsEmpty => BandsState == LoadState.Empty;

    /// <summary>Songs failure text.</summary>
    public string SongsFailedText => GlobalSearchResults.SongsFailed;

    /// <summary>Centred short-query hint naming the scope (issue #299), else empty.</summary>
    public string Hint => IsShortQuery ? GlobalSearchResults.EnterQueryHintFor(Scope) : "";

    /// <summary>Whether <see cref="Hint"/> has text.</summary>
    public bool HasHint => Hint.Length > 0;

    /// <summary>Which centred empty state applies: every scope empty in All, or the chosen scope empty.</summary>
    private SearchScope? EmptyScope =>
        !ShowsResults ? null :
        Scope == SearchScope.All && AllEmpty ? SearchScope.All :
        Scope == SearchScope.Songs && SongsState == LoadState.Empty ? SearchScope.Songs :
        Scope == SearchScope.Players && PlayersEmpty ? SearchScope.Players :
        Scope == SearchScope.Bands && BandsEmpty ? SearchScope.Bands : null;

    /// <summary>Whether the centred title-and-subtitle empty state is shown (issue #99).</summary>
    public bool HasEmptyState => EmptyScope is not null;

    /// <summary>Empty-state title, else empty.</summary>
    public string EmptyTitle => EmptyScope switch
    {
        SearchScope.All => GlobalSearchResults.EmptyAllTitle,
        SearchScope.Songs => GlobalSearchResults.EmptySongsTitle,
        SearchScope.Players => GlobalSearchResults.EmptyPlayersTitle,
        SearchScope.Bands => GlobalSearchResults.EmptyBandsTitle,
        _ => "",
    };

    /// <summary>Empty-state subtitle, else empty.</summary>
    public string EmptySubtitle => EmptyScope switch
    {
        SearchScope.All => GlobalSearchResults.EmptyAllSubtitle,
        SearchScope.Songs => GlobalSearchResults.EmptySongsSubtitle,
        SearchScope.Players => GlobalSearchResults.EmptyPlayersSubtitle,
        SearchScope.Bands => GlobalSearchResults.EmptyBandsSubtitle,
        _ => "",
    };

    /// <summary>
    /// One-line status for the players-only pickers: the short-query prompt, "Searching…" (debounce or read), the
    /// failure message, "No players found." or nothing while rows are shown.
    /// </summary>
    public string PlayersHint =>
        IsShortQuery ? GlobalSearchResults.EnterQueryHint :
        IsDebouncing || SettledQuery.Length == 0 || PlayersLoading ? GlobalSearchResults.Searching :
        PlayersFailed ? (PlayersStatus.Message is { Length: > 0 } message ? message : PlayersStatus.Title) :
        PlayersEmpty ? GlobalSearchResults.NoPlayers : "";

    /// <summary>Whether a picker offers Retry (after a failure or an empty envelope, which never proves there is no match).</summary>
    public bool CanRetryPlayers => !IsShortQuery && !IsDebouncing && SettledQuery.Length > 0 && (PlayersFailed || PlayersEmpty);

    /// <summary>
    /// Whether the page shows its one centred spinner instead of results (issue #299, web <c>SearchModal</c>): during
    /// the debounce, and until every read the scope shows has settled. All waits for songs, players and bands; a single
    /// scope waits only for itself (Songs never waits for the network).
    /// </summary>
    public bool IsBusy => !IsShortQuery &&
                          (IsDebouncing || SettledQuery.Length == 0 ||
                           Scope is SearchScope.All or SearchScope.Songs && SongsState == LoadState.Loading ||
                           Scope is SearchScope.All or SearchScope.Players && PlayersLoading ||
                           Scope is SearchScope.All or SearchScope.Bands && BandsLoading);
    #endregion

    #region Commands
    /// <summary>Runs the current text now, skipping the debounce (Enter / query icon).</summary>
    [RelayCommand]
    private void Submit()
    {
        var text = GlobalSearchResults.Normalize(Query);
        if (text.Length < GlobalSearchResults.MinQueryLength) return;
        Pending = Start(text, debounce: false);
    }

    /// <summary>Runs the current text again (the pickers' Retry and the players freeze countdown; the Search page has no
    /// Retry and re-runs through <see cref="SubmitCommand"/>).</summary>
    /// <returns>Search task.</returns>
    [RelayCommand]
    private Task RetryAsync()
    {
        var text = GlobalSearchResults.Normalize(Query);
        if (text.Length < GlobalSearchResults.MinQueryLength) return Task.CompletedTask;
        return Pending = Start(text, debounce: false);
    }

    /// <summary>Clears the text and every result (surface closed or a result opened; nothing is remembered).</summary>
    public void Reset()
    {
        Query = "";
        Scope = playersOnly ? SearchScope.Players : SearchScope.All;
    }

    /// <summary>Stops pending work when the surface goes away (no automatic retry keeps running behind it).</summary>
    public void Deactivate()
    {
        Cancel();
        IsDebouncing = false;
        PlayersStatus.Clear();
        BandsStatus.Clear();
    }
    #endregion

    #region Search
    /// <summary>Debounces new text; short text clears at once.</summary>
    /// <param name="value">Text.</param>
    partial void OnQueryChanged(string value)
    {
        if (seeding) return;
        var text = GlobalSearchResults.Normalize(value);
        if (text == SettledQuery && !IsDebouncing && SettledQuery.Length > 0)
        {
            Refresh();
            return;
        }
        if (text.Length < GlobalSearchResults.MinQueryLength)
        {
            Cancel();
            IsDebouncing = false;
            Clear();
            return;
        }
        Pending = Start(text, debounce: true);
    }

    /// <summary>Updates the derived presentation.</summary>
    /// <param name="value">Scope.</param>
    partial void OnScopeChanged(SearchScope value) => Refresh();

    /// <summary>Cancels superseded work and starts a search.</summary>
    /// <param name="text">Trimmed query.</param>
    /// <param name="debounce">Whether to wait for the debounce.</param>
    /// <returns>Search task.</returns>
    private Task Start(string text, bool debounce)
    {
        Cancel();
        search = new CancellationTokenSource();
        return RunAsync(text, debounce, search.Token);
    }

    /// <summary>Cancels the in-flight search.</summary>
    private void Cancel()
    {
        search?.Cancel();
        search?.Dispose();
        search = null;
    }

    /// <summary>Clears results after a short query.</summary>
    private void Clear()
    {
        SettledQuery = "";
        Songs = [];
        Players = [];
        Bands = [];
        Suggestions = [];
        SongsState = LoadState.Idle;
        PlayersState = LoadState.Idle;
        BandsState = LoadState.Idle;
        Refresh();
    }

    /// <summary>Runs one search: songs locally as soon as the debounce fires, then players and bands together over the network.</summary>
    /// <param name="text">Trimmed query.</param>
    /// <param name="debounce">Whether to wait first.</param>
    /// <param name="token">Cancelled by newer input.</param>
    /// <returns>Search task.</returns>
    private async Task RunAsync(string text, bool debounce, CancellationToken token)
    {
        try
        {
            if (debounce)
            {
                IsDebouncing = true;
                Refresh();
                await Task.Delay(Debounce, session.Time, token);
            }
            IsDebouncing = false;
            SettledQuery = text;
            // The band search takes the same query rules as the account search (2–200 characters, no unsafe text).
            var remote = GlobalSearchResults.CanSearchPlayers(text);
            PlayersState = remote ? LoadState.Loading : LoadState.Empty;
            BandsState = remote && !playersOnly ? LoadState.Loading : LoadState.Empty;
            // Earlier matches that still fit stay while the searches run (the lists no longer shrink per keystroke).
            Players = PlayersState == LoadState.Loading ? GlobalSearchResults.RetainMatching(Players, text) : [];
            Bands = BandsState == LoadState.Loading ? [.. Bands.Where(b => GlobalSearchResults.BandStillMatches(b.Entry, text))] : [];
            if (playersOnly)
            {
                SongsState = LoadState.Empty;
            }
            else
            {
                await LoadSongsAsync(text, token);
                token.ThrowIfCancellationRequested();
                UpdateSuggestions(text);
            }
            Refresh();
            // Both reads run together; each result is applied here, one at a time, as it arrives, so the Players
            // scope shows its rows without waiting for the band search (and state is never written concurrently).
            var pending = new List<Task<Action>>(2);
            if (PlayersState == LoadState.Loading) pending.Add(LoadPlayersAsync(text, token));
            if (BandsState == LoadState.Loading) pending.Add(LoadBandsAsync(text, token));
            while (pending.Count > 0)
            {
                var done = await Task.WhenAny(pending);
                pending.Remove(done);
                var apply = await done;
                token.ThrowIfCancellationRequested();
                apply();
                UpdateSuggestions(text);
                Refresh();
            }
            UpdateSuggestions(text);
            Refresh();
            Announce();
        }
        catch (OperationCanceledException)
        {
            // Superseded by newer input; its results are dropped.
        }
    }

    /// <summary>Matches the catalogue (loading it first if the shell has not yet).</summary>
    /// <param name="text">Trimmed query.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>Load task.</returns>
    private async Task LoadSongsAsync(string text, CancellationToken token)
    {
        try
        {
            if (session.Catalog is null)
            {
                SongsState = LoadState.Loading;
                Refresh();
            }
            var catalog = session.Catalog ?? await session.LoadCatalogAsync(cancellationToken: token);
            token.ThrowIfCancellationRequested();
            Songs = GlobalSearchResults.MatchSongs(catalog.Songs, text);
            SongsState = Songs.Count > 0 ? LoadState.Loaded : LoadState.Empty;
        }
        catch (FestivalApiException) when (!token.IsCancellationRequested)
        {
            Songs = [];
            SongsState = LoadState.Failed;
        }
    }

    /// <summary>Reads the keyless account search; late or cancelled results are dropped.</summary>
    /// <param name="text">Trimmed query.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>The state change to apply on the search's continuation.</returns>
    private async Task<Action> LoadPlayersAsync(string text, CancellationToken token)
    {
        try
        {
            var response = await session.Api.SearchPlayersAsync(text, GlobalSearchResults.PlayerLimit, token);
            var selected = session.SelectedPlayer?.AccountId;
            var results = excludeSelected
                ? response.Results.Where(r => !string.Equals(r.AccountId, selected, StringComparison.OrdinalIgnoreCase))
                : response.Results;
            var players = GlobalSearchResults.Players(results, selected);
            return () =>
            {
                Players = players;
                // Status first: once the state flips, the query counts as settled and its status must already be current.
                PlayersStatus.Clear();
                PlayersState = players.Count > 0 ? LoadState.Loaded : LoadState.Empty;
            };
        }
        catch (FestivalApiException error) when (!token.IsCancellationRequested)
        {
            return () =>
            {
                Players = [];
                PlayersStatus.Report(error);
                PlayersState = LoadState.Failed;
            };
        }
    }

    /// <summary>Reads the keyless band search (first page); late or cancelled results are dropped.</summary>
    /// <param name="text">Trimmed query.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>The state change to apply on the search's continuation.</returns>
    private async Task<Action> LoadBandsAsync(string text, CancellationToken token)
    {
        try
        {
            var response = await session.Api.SearchBandsAsync(text, GlobalSearchResults.BandLimit, token);
            List<PlayerBandCardViewModel> bands = [.. response.Results.Take(GlobalSearchResults.BandLimit)
                .Select(entry => new PlayerBandCardViewModel(entry, GlobalSearchResults.BandResultId))];
            return () =>
            {
                Bands = bands;
                BandsStatus.Clear();
                BandsState = bands.Count > 0 ? LoadState.Loaded : LoadState.Empty;
            };
        }
        catch (FestivalApiException error) when (!token.IsCancellationRequested)
        {
            return () =>
            {
                Bands = [];
                BandsStatus.Report(error);
                BandsState = LoadState.Failed;
            };
        }
    }

    /// <summary>Rebuilds the title-bar suggestions (the players-only pickers have none).</summary>
    /// <param name="text">Trimmed query.</param>
    private void UpdateSuggestions(string text)
    {
        if (!playersOnly) Suggestions = GlobalSearchResults.Suggestions(text, Songs, Players, [.. Bands.Select(b => b.Entry)]);
    }

    /// <summary>Raises the count announcement once the query settles.</summary>
    private void Announce()
    {
        LastAnnouncement = playersOnly
            ? GlobalSearchResults.PlayersAnnouncement(PlayersState == LoadState.Failed ? null : Players.Count, PlayersHint)
            : GlobalSearchResults.Announcement(
                SongsState == LoadState.Failed ? null : Songs.Count,
                PlayersState == LoadState.Failed ? null : Players.Count,
                BandsState == LoadState.Failed ? null : Bands.Count);
        ResultsAnnounced?.Invoke(this, LastAnnouncement);
    }

    /// <summary>Raises change notifications for every derived property, then <see cref="SectionShown"/> for each section that appeared.</summary>
    private void Refresh()
    {
        foreach (var name in DerivedProperties) OnPropertyChanged(name);
        var songsWasShown = songsShown;
        var playersWasShown = playersShown;
        var bandsWasShown = bandsShown;
        songsShown = ShowSongsSection;
        playersShown = ShowPlayersSection;
        bandsShown = ShowBandsSection;
        if (songsShown && !songsWasShown) SectionShown?.Invoke(this, SearchScope.Songs);
        if (playersShown && !playersWasShown) SectionShown?.Invoke(this, SearchScope.Players);
        if (bandsShown && !bandsWasShown) SectionShown?.Invoke(this, SearchScope.Bands);
    }

    /// <summary>Derived property names.</summary>
    private static readonly string[] DerivedProperties =
    [
        nameof(IsShortQuery), nameof(ShowSongsSection), nameof(SongsFailed), nameof(ShowPlayersSection),
        nameof(PlayersLoading), nameof(PlayersFailed), nameof(PlayersEmpty), nameof(Hint), nameof(HasHint),
        nameof(HasEmptyState), nameof(EmptyTitle), nameof(EmptySubtitle), nameof(ShowBandsSection), nameof(BandsLoading),
        nameof(BandsFailed), nameof(BandsEmpty), nameof(HasBandRows),
        nameof(IsBusy), nameof(IsSettled), nameof(HasSongRows), nameof(HasPlayerRows), nameof(PlayersHint), nameof(CanRetryPlayers),
    ];
    #endregion
}
#endregion
