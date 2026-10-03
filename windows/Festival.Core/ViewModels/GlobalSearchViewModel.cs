using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Global search
/// <summary>
/// The one global-search engine (global-search spec): trimmed query, 2-character minimum, 250 ms debounce, local
/// song matches shown as soon as the debounce fires, players from the keyless account search with their own
/// progress, per-scope empty/error states, cancellation of superseded queries and a polite count announcement.
/// Bands are shown but never requested (the service's band search GET can write). <see cref="ForPlayers"/> is the same
/// engine limited to players for the compact pickers (the title-bar profile flyout and Find Rival).
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
            seed.PlayersState != LoadState.Failed)
        {
            seeding = true;
            Query = text;
            seeding = false;
            SettledQuery = text;
            Songs = seed.Songs;
            SongsState = seed.SongsState;
            Players = seed.Players;
            PlayersState = seed.PlayersState;
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

    /// <summary>Title-bar suggestion items.</summary>
    [ObservableProperty]
    private List<GlobalSuggestion> suggestions = [];

    /// <summary>Songs lifecycle for the settled query.</summary>
    [ObservableProperty]
    private LoadState songsState;

    /// <summary>Players lifecycle for the settled query.</summary>
    [ObservableProperty]
    private LoadState playersState;

    /// <summary>Whether a newer query is waiting for the debounce.</summary>
    [ObservableProperty]
    private bool isDebouncing;

    /// <summary>Query whose results are shown.</summary>
    public string SettledQuery { get; private set; } = "";

    /// <summary>Last announcement raised.</summary>
    public string LastAnnouncement { get; private set; } = "";

    /// <summary>Players failure presentation (freeze → "Scores are updating" with automatic retry).</summary>
    public ServiceStatusViewModel PlayersStatus { get; }

    /// <summary>Current search task (tests and the view await nothing; exposed for determinism).</summary>
    internal Task? Pending { get; private set; }

    /// <summary>Whether songs and players have both finished for the settled query.</summary>
    public bool IsSettled => SettledQuery.Length > 0 && !IsDebouncing &&
                             SongsState is LoadState.Loaded or LoadState.Empty or LoadState.Failed &&
                             PlayersState is LoadState.Loaded or LoadState.Empty or LoadState.Failed;
    #endregion

    #region Presentation
    /// <summary>Whether the query is too short to search.</summary>
    public bool IsShortQuery => !GlobalSearchResults.IsSearchable(Query);

    /// <summary>Whether the Bands scope (explanation, no request) is chosen.</summary>
    public bool IsBandsScope => Scope == SearchScope.Bands;

    /// <summary>Band explanation text.</summary>
    public string BandsExplanation => GlobalSearchResults.BandsUnavailable;

    /// <summary>Whether both live scopes finished with nothing (All view shows one "No results found.").</summary>
    private bool AllEmpty => SongsState == LoadState.Empty && PlayersState == LoadState.Empty;

    /// <summary>Whether results for the current text are on screen (not short, not replaced by the bands block).</summary>
    private bool ShowsResults => !IsShortQuery && !IsBandsScope && SettledQuery.Length > 0;

    /// <summary>Whether the Songs section is shown.</summary>
    public bool ShowSongsSection => ShowsResults && Scope is SearchScope.All or SearchScope.Songs &&
                                    (Songs.Count > 0 || SongsState == LoadState.Failed);

    /// <summary>Whether song rows are shown (their card is hidden otherwise).</summary>
    public bool HasSongRows => Songs.Count > 0;

    /// <summary>Whether player rows are shown (their card is hidden otherwise).</summary>
    public bool HasPlayerRows => Players.Count > 0;

    /// <summary>Whether the Songs section shows its failure line.</summary>
    public bool SongsFailed => SongsState == LoadState.Failed;

    /// <summary>
    /// Whether the Players section is shown (loading, rows or failure). An empty envelope never shows a section: in All
    /// it is hidden like the web (<c>shouldRenderGlobalSection</c>), in Players it is the centred empty state.
    /// </summary>
    public bool ShowPlayersSection => ShowsResults && Scope is SearchScope.All or SearchScope.Players &&
                                      PlayersState is not (LoadState.Idle or LoadState.Empty);

    /// <summary>Whether the Players section shows its inline progress.</summary>
    public bool PlayersLoading => PlayersState == LoadState.Loading;

    /// <summary>Whether the Players section shows the service-status card.</summary>
    public bool PlayersFailed => PlayersState == LoadState.Failed;

    /// <summary>Whether the account search finished with an empty envelope.</summary>
    public bool PlayersEmpty => PlayersState == LoadState.Empty;

    /// <summary>Songs failure text.</summary>
    public string SongsFailedText => GlobalSearchResults.SongsFailed;

    /// <summary>Centred short-query hint, else empty.</summary>
    public string Hint => !IsBandsScope && IsShortQuery ? GlobalSearchResults.EnterQueryHint : "";

    /// <summary>Whether <see cref="Hint"/> has text.</summary>
    public bool HasHint => Hint.Length > 0;

    /// <summary>Which centred empty state applies: every scope empty in All, Songs with no match, or Players empty.</summary>
    private SearchScope? EmptyScope =>
        !ShowsResults ? null :
        Scope == SearchScope.All && AllEmpty ? SearchScope.All :
        Scope == SearchScope.Songs && SongsState == LoadState.Empty ? SearchScope.Songs :
        Scope == SearchScope.Players && PlayersEmpty ? SearchScope.Players : null;

    /// <summary>Whether the centred title-and-subtitle empty state is shown (issue #99).</summary>
    public bool HasEmptyState => EmptyScope is not null;

    /// <summary>Empty-state title, else empty.</summary>
    public string EmptyTitle => EmptyScope switch
    {
        SearchScope.All => GlobalSearchResults.EmptyAllTitle,
        SearchScope.Songs => GlobalSearchResults.EmptySongsTitle,
        SearchScope.Players => GlobalSearchResults.EmptyPlayersTitle,
        _ => "",
    };

    /// <summary>Empty-state subtitle, else empty.</summary>
    public string EmptySubtitle => EmptyScope switch
    {
        SearchScope.All => GlobalSearchResults.EmptyAllSubtitle,
        SearchScope.Songs => GlobalSearchResults.EmptySongsSubtitle,
        SearchScope.Players => GlobalSearchResults.EmptyPlayersSubtitle,
        _ => "",
    };

    /// <summary>Whether Retry sits under the empty state: whenever the players envelope is part of it, since an empty
    /// envelope may be a server timeout.</summary>
    public bool CanRetryEmpty => EmptyScope is SearchScope.All or SearchScope.Players;

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

    /// <summary>Whether the page shows anything busy (debounce or a pending read) before the first rows.</summary>
    public bool IsBusy => !IsShortQuery && !IsBandsScope && (IsDebouncing || SettledQuery.Length == 0 || SongsState == LoadState.Loading);
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

    /// <summary>Runs the current text again (players empty envelope, failure or scrape-freeze countdown).</summary>
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
        Suggestions = [];
        SongsState = LoadState.Idle;
        PlayersState = LoadState.Idle;
        Refresh();
    }

    /// <summary>Runs one search: songs locally as soon as the debounce fires, then players over the network.</summary>
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
            PlayersState = GlobalSearchResults.CanSearchPlayers(text) ? LoadState.Loading : LoadState.Empty;
            // Earlier matches that still fit stay while the account search runs (the list no longer shrinks per keystroke).
            Players = PlayersState == LoadState.Loading ? GlobalSearchResults.RetainMatching(Players, text) : [];
            if (playersOnly)
            {
                SongsState = LoadState.Empty;
            }
            else
            {
                await LoadSongsAsync(text, token);
                token.ThrowIfCancellationRequested();
                Suggestions = GlobalSearchResults.Suggestions(text, Songs, Players);
            }
            Refresh();
            if (PlayersState == LoadState.Loading) await LoadPlayersAsync(text, token);
            if (!playersOnly) Suggestions = GlobalSearchResults.Suggestions(text, Songs, Players);
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
    /// <returns>Load task.</returns>
    private async Task LoadPlayersAsync(string text, CancellationToken token)
    {
        try
        {
            var response = await session.Api.SearchPlayersAsync(text, GlobalSearchResults.PlayerLimit, token);
            token.ThrowIfCancellationRequested();
            var selected = session.SelectedPlayer?.AccountId;
            var results = excludeSelected
                ? response.Results.Where(r => !string.Equals(r.AccountId, selected, StringComparison.OrdinalIgnoreCase))
                : response.Results;
            Players = GlobalSearchResults.Players(results, selected);
            // Status first: once the state flips, the query counts as settled and its status must already be current.
            PlayersStatus.Clear();
            PlayersState = Players.Count > 0 ? LoadState.Loaded : LoadState.Empty;
        }
        catch (FestivalApiException error) when (!token.IsCancellationRequested)
        {
            Players = [];
            PlayersStatus.Report(error);
            PlayersState = LoadState.Failed;
        }
    }

    /// <summary>Raises the count announcement once the query settles.</summary>
    private void Announce()
    {
        LastAnnouncement = GlobalSearchResults.Announcement(
            SongsState == LoadState.Failed ? null : Songs.Count,
            PlayersState == LoadState.Failed ? null : Players.Count);
        ResultsAnnounced?.Invoke(this, LastAnnouncement);
    }

    /// <summary>Raises change notifications for every derived property.</summary>
    private void Refresh()
    {
        foreach (var name in DerivedProperties) OnPropertyChanged(name);
    }

    /// <summary>Derived property names.</summary>
    private static readonly string[] DerivedProperties =
    [
        nameof(IsShortQuery), nameof(IsBandsScope), nameof(ShowSongsSection), nameof(SongsFailed), nameof(ShowPlayersSection),
        nameof(PlayersLoading), nameof(PlayersFailed), nameof(PlayersEmpty), nameof(Hint), nameof(HasHint),
        nameof(HasEmptyState), nameof(EmptyTitle), nameof(EmptySubtitle), nameof(CanRetryEmpty),
        nameof(IsBusy), nameof(IsSettled), nameof(HasSongRows), nameof(HasPlayerRows), nameof(PlayersHint), nameof(CanRetryPlayers),
    ];
    #endregion
}
#endregion
