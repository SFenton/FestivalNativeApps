using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Rival song row
/// <summary>Who leads one shared song.</summary>
public enum RivalSongOutcome
{
    /// <summary>Same rank.</summary>
    Tie,
    /// <summary>The player leads.</summary>
    Winning,
    /// <summary>The rival leads.</summary>
    Losing,
}

/// <summary>One shared song, head to head (web <c>RivalSongRow</c>, standalone layout).</summary>
public sealed record RivalSongItem
{
    /// <summary>Builds a row, enriching it from the catalogue when the song is known.</summary>
    /// <param name="song">Comparison.</param>
    /// <param name="catalogSong">Catalogue song, if loaded.</param>
    /// <param name="playerName">Selected player's name.</param>
    /// <param name="rivalName">Rival's name.</param>
    public RivalSongItem(RivalSongComparison song, Song? catalogSong, string playerName, string rivalName)
    {
        Comparison = song;
        PlayerName = playerName;
        RivalName = rivalName;
        Title = song.Title ?? catalogSong?.Title ?? song.SongId;
        var artist = song.Artist ?? catalogSong?.Artist;
        Subtitle = catalogSong?.Year is { } year && artist is not null ? $"{artist} · {year}" : artist ?? "";
        AlbumArt = catalogSong?.AlbumArt;
        var keyboard = catalogSong?.UsesKeyboardIcon == true;
        InstrumentInfo.TryParse(song.UserInstrument ?? song.Instrument, out var user);
        InstrumentInfo.TryParse(song.RivalInstrument ?? song.Instrument, out var rival);
        UserIconFile = user.IconFile(keyboard);
        RivalIconFile = rival.IconFile(keyboard);
        IsMixedInstrument = user != rival;
        InstrumentInfo.TryParse(song.Instrument, out var chart);
        Route = new AppRoute.SongDetail(song.SongId, chart);
        InstrumentLabel = IsMixedInstrument ? $"{user.Label()} vs {rival.Label()}" : user.Label();
    }

    /// <summary>Underlying comparison.</summary>
    public RivalSongComparison Comparison { get; }

    /// <summary>Song title (service title, else catalogue, else ID).</summary>
    public string Title { get; }

    /// <summary><c>Artist · Year</c>.</summary>
    public string Subtitle { get; }

    /// <summary>Catalogue art reference, if known.</summary>
    public string? AlbumArt { get; }

    /// <summary>Player's chart icon.</summary>
    public string UserIconFile { get; }

    /// <summary>Rival's chart icon (differs only for mixed Pro Drums family comparisons).</summary>
    public string RivalIconFile { get; }

    /// <summary>Whether the two players' charts differ.</summary>
    public bool IsMixedInstrument { get; }

    /// <summary>Chart label(s) for screen readers.</summary>
    public string InstrumentLabel { get; }

    /// <summary>Song Detail route on this chart.</summary>
    public AppRoute.SongDetail Route { get; }

    /// <summary>Selected player's name.</summary>
    public string PlayerName { get; }

    /// <summary>Rival's name.</summary>
    public string RivalName { get; }

    /// <summary>Who leads.</summary>
    public RivalSongOutcome Outcome => Comparison.RankDelta switch
    {
        > 0 => RivalSongOutcome.Winning,
        < 0 => RivalSongOutcome.Losing,
        _ => RivalSongOutcome.Tie,
    };

    /// <summary>Whether the player leads.</summary>
    public bool IsWinning => Outcome == RivalSongOutcome.Winning;

    /// <summary>Whether the rival leads.</summary>
    public bool IsLosing => Outcome == RivalSongOutcome.Losing;

    /// <summary><c>#rank</c> for the player.</summary>
    public string UserRankText => string.Create(CultureInfo.CurrentCulture, $"#{Comparison.UserRank:N0}");

    /// <summary><c>#rank</c> for the rival.</summary>
    public string RivalRankText => string.Create(CultureInfo.CurrentCulture, $"#{Comparison.RivalRank:N0}");

    /// <summary>Player's score, or empty.</summary>
    public string UserScoreText => Comparison.UserScore?.ToString("N0", CultureInfo.CurrentCulture) ?? "";

    /// <summary>Rival's score, or empty.</summary>
    public string RivalScoreText => Comparison.RivalScore?.ToString("N0", CultureInfo.CurrentCulture) ?? "";

    /// <summary>Signed rank gap.</summary>
    public string RankDeltaText => RivalHeadToHead.FormatRankDelta(Comparison.RankDelta);

    /// <summary>Signed score gap.</summary>
    public string ScoreDiffText => RivalHeadToHead.FormatScoreDiff(Comparison);

    /// <summary>Screen-reader name.</summary>
    public string AccessibleName =>
        $"{Title}, {InstrumentLabel}, you rank {Comparison.UserRank:N0}, {RivalName} ranks {Comparison.RivalRank:N0}, " +
        (Outcome switch { RivalSongOutcome.Winning => "you lead", RivalSongOutcome.Losing => "they lead", _ => "tied" });

    /// <summary>UIA automation ID.</summary>
    public string AutomationId => $"fst.rivalry.song.{Comparison.SongId}.{Comparison.Instrument}";
}
#endregion

#region Shared page base
/// <summary>States of a rival page.</summary>
public enum RivalPageState
{
    /// <summary>No player selected.</summary>
    NoPlayer,
    /// <summary>Loading.</summary>
    Loading,
    /// <summary>Content.</summary>
    Loaded,
    /// <summary>Nothing to show.</summary>
    Empty,
    /// <summary>Failed; see <see cref="RivalPageViewModel.Status"/>.</summary>
    Failed,
    /// <summary>The route's scope could not be resolved.</summary>
    Unknown,
}

/// <summary>Lifecycle shared by All Rivals, Rival Detail and Rivalry: observe the player, load, report failures.</summary>
public abstract partial class RivalPageViewModel : ObservableObject
{
    private CancellationTokenSource? loading;
    private string? loadedFor;
    private bool active;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="scope">Backoff scope.</param>
    /// <param name="fallbackTitle">Status heading.</param>
    protected RivalPageViewModel(FestivalSession session, string scope, string fallbackTitle)
    {
        Session = session;
        Status = new ServiceStatusViewModel(scope, fallbackTitle, () => LoadAsync(), session.Time);
    }

    /// <summary>Shared session.</summary>
    protected FestivalSession Session { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Page state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowContent), nameof(ShowError), nameof(IsLoading), nameof(ShowEmpty), nameof(ShowNoPlayer))]
    private RivalPageState state = RivalPageState.Loading;

    /// <summary>Whether content is shown.</summary>
    public bool ShowContent => State == RivalPageState.Loaded;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == RivalPageState.Failed;

    /// <summary>Whether the progress ring is shown.</summary>
    public bool IsLoading => State == RivalPageState.Loading;

    /// <summary>Whether the empty/unknown message is shown.</summary>
    public bool ShowEmpty => State is RivalPageState.Empty or RivalPageState.Unknown;

    /// <summary>Whether the choose-a-player message is shown.</summary>
    public bool ShowNoPlayer => State == RivalPageState.NoPlayer;

    /// <summary>Empty/unknown heading.</summary>
    public abstract string EmptyTitle { get; }

    /// <summary>Selected player's name ("You" when unknown).</summary>
    protected string PlayerName => Session.SelectedPlayer?.DisplayName ?? "You";

    /// <summary>Starts observing the session and loads when the player or visible charts changed.</summary>
    public void Activate()
    {
        if (!active) Session.PropertyChanged += OnSessionChanged;
        active = true;
        if (loadedFor != LoadKey()) _ = LoadAsync();
    }

    /// <summary>Stops observing the session.</summary>
    public void Deactivate()
    {
        if (active) Session.PropertyChanged -= OnSessionChanged;
        active = false;
    }

    /// <summary>Reloads (Retry, F5).</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        loading?.Cancel();
        var cts = loading = new CancellationTokenSource();
        loadedFor = LoadKey();
        if (!Session.HasPlayer)
        {
            Status.Clear();
            State = RivalPageState.NoPlayer;
            return;
        }
        State = RivalPageState.Loading;
        try
        {
            var result = await LoadContentAsync(cts.Token);
            if (cts.IsCancellationRequested) return;
            Status.Clear();
            State = result;
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (cts.IsCancellationRequested) return;
            Status.Report(error);
            State = RivalPageState.Failed;
        }
    }

    /// <summary>Forces a fresh read (drops cached rivals first).</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task RefreshAsync()
    {
        Session.RivalsCache.Clear();
        return LoadAsync();
    }

    /// <summary>Loads page content.</summary>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Resulting state.</returns>
    protected abstract Task<RivalPageState> LoadContentAsync(CancellationToken cancellationToken);

    /// <summary>Loads the catalogue for titles and art, ignoring failures (rows fall back to service text).</summary>
    /// <returns>Catalogue songs by ID.</returns>
    protected async Task<Dictionary<string, Song>> CatalogLookupAsync()
    {
        try
        {
            var catalog = await Session.LoadCatalogAsync();
            return catalog.Songs.GroupBy(s => s.SongId, StringComparer.Ordinal).ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);
        }
        catch (FestivalApiException)
        {
            return [];
        }
    }

    /// <summary>Player and visible charts (what a reload depends on).</summary>
    /// <returns>Key.</returns>
    private string LoadKey() => $"{Session.SelectedPlayer?.AccountId}|{string.Join(',', Session.Settings.VisibleInstruments)}";

    /// <summary>Reloads when the player or visible charts change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FestivalSession.Settings) && loadedFor != LoadKey()) _ = LoadAsync();
    }
}
#endregion

#region All rivals
/// <summary><c>/rivals/all</c>: every rival for one scope, above then below.</summary>
public sealed partial class AllRivalsViewModel : RivalPageViewModel
{
    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Route with the scope.</param>
    public AllRivalsViewModel(FestivalSession session, AppRoute.AllRivals route)
        : base(session, "all-rivals", "Rivals Unavailable") => RouteScope = route.Scope;

    /// <summary>Scope from the route (may be Settings-derived).</summary>
    public RivalScope RouteScope { get; }

    /// <summary>Scope resolved against current Settings.</summary>
    public RivalScope? Scope => RouteScope.Resolve(Session.Settings.VisibleInstruments);

    /// <summary>Heading.</summary>
    public string Title => (Scope ?? RouteScope).ListTitle;

    /// <summary>Instrument icon for single-chart scopes.</summary>
    public string IconFile => Scope switch
    {
        RivalScope.Song { IsCommon: false } s => s.Instruments[0].IconFile(),
        RivalScope.Leaderboard l => l.Instrument.IconFile(),
        _ => "",
    };

    /// <summary>Whether an icon is shown.</summary>
    public bool HasIcon => IconFile.Length > 0;

    /// <summary>Rows (above, then below).</summary>
    [ObservableProperty]
    private List<RivalRowItem> rows = [];

    /// <summary>Secondary line: leaderboard metric and rank, or the Common Rivals charts.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasSubtitle))]
    private string subtitle = "";

    /// <summary>
    /// Whether the secondary line shows: single-chart song lists have none, and an empty line would push the icon off
    /// the title's centre and leave an empty text element in the UI Automation tree.
    /// </summary>
    public bool HasSubtitle => Subtitle.Length > 0;

    /// <inheritdoc />
    public override string EmptyTitle => State == RivalPageState.Unknown
        ? "This rivals list could not be identified."
        : "Not enough data to identify rivals yet.";

    /// <inheritdoc />
    protected override async Task<RivalPageState> LoadContentAsync(CancellationToken cancellationToken)
    {
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(IconFile));
        OnPropertyChanged(nameof(HasIcon));
        switch (Scope)
        {
            case RivalScope.Leaderboard l:
                var board = await Session.GetLeaderboardRivalsAsync(l.Instrument, l.RankBy, cancellationToken);
                Rows = [.. board.Above.Select(r => RivalRowItem.From(r, RivalDirection.Above, l)),
                        .. board.Below.Select(r => RivalRowItem.From(r, RivalDirection.Below, l))];
                Subtitle = board.UserRank is { } rank
                    ? string.Create(CultureInfo.CurrentCulture, $"Ranked by {l.RankBy.Label()} · You are #{rank:N0}")
                    : $"Ranked by {l.RankBy.Label()}";
                break;
            case RivalScope.Song { IsCommon: true } common:
                var (above, below) = await Session.GetCommonRivalsAsync(common.Instruments, cancellationToken);
                Rows = [.. RivalsHubViewModel.Rows(above, RivalDirection.Above, common), .. RivalsHubViewModel.Rows(below, RivalDirection.Below, common)];
                Subtitle = string.Join(", ", common.Instruments.Select(i => i.Label()));
                break;
            case RivalScope.Song song:
                Rows = await ListRows(song.Instruments[0].ServiceId(), song, cancellationToken);
                break;
            case RivalScope.Combo combo:
                Rows = await ListRows(combo.Token, combo, cancellationToken);
                Subtitle = string.Join(", ", combo.Instruments.Select(i => i.Label()));
                break;
            default:
                Rows = [];
                return RivalPageState.Unknown;
        }
        return Rows.Count == 0 ? RivalPageState.Empty : RivalPageState.Loaded;
    }

    /// <summary>Reads a shared-song list as rows.</summary>
    /// <param name="token">Chart or combo token.</param>
    /// <param name="scope">Row scope.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Rows.</returns>
    private async Task<List<RivalRowItem>> ListRows(string token, RivalScope scope, CancellationToken cancellationToken)
    {
        var list = await Session.GetRivalsListAsync(token, cancellationToken);
        return [.. RivalsHubViewModel.Rows(list.Above, RivalDirection.Above, scope), .. RivalsHubViewModel.Rows(list.Below, RivalDirection.Below, scope)];
    }
}
#endregion

#region Rival detail
/// <summary>One category card on Rival Detail: five songs and a See All link.</summary>
/// <param name="Category">Category.</param>
/// <param name="Preview">First five songs.</param>
/// <param name="SeeAllRoute">Rivalry route for this category.</param>
public sealed record RivalCategoryItem(RivalCategory Category, List<RivalSongItem> Preview, AppRoute.Rivalry SeeAllRoute)
{
    /// <summary>Heading.</summary>
    public string Title => Category.Title;

    /// <summary>Description.</summary>
    public string Subtitle => Category.Subtitle;

    /// <summary>Tone.</summary>
    public RivalCategorySentiment Sentiment => Category.Sentiment;

    /// <summary>Web <c>rivals.detail.viewAll</c>.</summary>
    public string SeeAllText => Category.Songs.Count == 1
        ? "View 1 song"
        : string.Create(CultureInfo.CurrentCulture, $"View All {Category.Songs.Count:N0} Songs");

    /// <summary>UIA automation ID.</summary>
    public string AutomationId => "fst.rival-detail.category." + Category.Key;

    /// <summary>Quick Links section ID (web <c>rival-category:&lt;key&gt;</c>).</summary>
    public string QuickLinkId => "rival-category:" + Category.Key;
}

/// <summary><c>/rivals/:rivalId</c>: shared songs against one rival, grouped into web categories.</summary>
public sealed partial class RivalDetailViewModel : RivalPageViewModel
{
    /// <summary>Songs previewed per category (web <c>PREVIEW_COUNT</c>).</summary>
    public const int PreviewCount = 5;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Route.</param>
    public RivalDetailViewModel(FestivalSession session, AppRoute.RivalDetail route)
        : base(session, "rival-detail", "Rivals Unavailable")
    {
        Route = route;
        rivalName = route.Name;
    }

    /// <summary>Route.</summary>
    public AppRoute.RivalDetail Route { get; }

    /// <summary>Rival's name once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(ViewProfileLabel))]
    private string? rivalName;

    /// <summary>Head-to-head summary.</summary>
    [ObservableProperty]
    private string summary = "";

    /// <summary>Category cards.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(QuickLinkSections))]
    private List<RivalCategoryItem> categories = [];

    /// <summary>Quick Links: one per non-empty category (web <c>RivalDetailPage.tsx:136-168</c>; the web offers them on mobile only).</summary>
    public List<QuickLinkSection> QuickLinkSections => [.. Categories.Select(c => new QuickLinkSection(c.QuickLinkId, c.Title))];

    /// <summary>Heading.</summary>
    public string Title => RivalName ?? "Rival";

    /// <summary>Which scope the comparison covers.</summary>
    public string ScopeLabel => RivalDetailText.ScopeLabel(Route.Scope, Session.Settings.VisibleInstruments);

    /// <summary>Profile action label (web <c>common.viewNameProfile</c>).</summary>
    public string ViewProfileLabel => RivalName is { } name ? $"View {name}'s Profile" : "View Profile";

    /// <summary>Rival's player page.</summary>
    public AppRoute.Player ProfileRoute => new(Route.RivalId);

    /// <inheritdoc />
    public override string EmptyTitle => "No song data for this rival.";

    /// <inheritdoc />
    protected override async Task<RivalPageState> LoadContentAsync(CancellationToken cancellationToken)
    {
        OnPropertyChanged(nameof(ScopeLabel));
        var detailRead = Session.GetRivalDetailAsync(Route.Scope, Route.RivalId, Route.AllowLiveFallback, cancellationToken);
        var lookup = await CatalogLookupAsync();
        var detail = await detailRead;
        RivalName = detail.Rival.DisplayName ?? Route.Name;
        var rival = RivalName ?? "Them";
        Summary = RivalHeadToHead.Summary(detail.Songs);
        Categories = [.. RivalCategorization.Categorize(detail.Songs).Select(c => new RivalCategoryItem(c,
            [.. c.Songs.Take(PreviewCount).Select(s => new RivalSongItem(s, lookup.GetValueOrDefault(s.SongId), PlayerName, rival))],
            new AppRoute.Rivalry(Route.RivalId, c.Key, RivalName, Route.Scope, Route.AllowLiveFallback)))];
        return Categories.Count == 0 ? RivalPageState.Empty : RivalPageState.Loaded;
    }
}

/// <summary>Scope descriptions for rival pages.</summary>
public static class RivalDetailText
{
    /// <summary>Describes the charts a comparison covers.</summary>
    /// <param name="scope">Route scope (<see langword="null"/> = every visible chart).</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns>Text such as <c>Lead · Leaderboard (Total Score)</c>.</returns>
    public static string ScopeLabel(RivalScope? scope, IReadOnlyList<Instrument> visible) => scope?.Resolve(visible) switch
    {
        RivalScope.Leaderboard l => $"{l.Instrument.Label()} · Leaderboard ({l.RankBy.Label()})",
        RivalScope.Combo c => $"{RivalCombo.Label(c.Token)}: {string.Join(", ", c.Instruments.Select(i => i.Label()))}",
        RivalScope.Song s when s.IsCommon && s.Instruments.SequenceEqual(visible) => "Common Rivals · All Visible Instruments",
        RivalScope.Song s => string.Join(", ", s.Instruments.Select(i => i.Label())),
        _ => "All Visible Instruments",
    };
}
#endregion

#region Rivalry
/// <summary><c>/rivals/:rivalId/rivalry?mode=</c>: every song in one category, with a native sort.</summary>
public sealed partial class RivalryViewModel : RivalPageViewModel
{
    private List<RivalSongItem> categorySongs = [];

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Route.</param>
    public RivalryViewModel(FestivalSession session, AppRoute.Rivalry route)
        : base(session, "rivalry", "Rivals Unavailable")
    {
        Route = route;
        rivalName = route.Name;
    }

    /// <summary>Route.</summary>
    public AppRoute.Rivalry Route { get; }

    /// <summary>Heading (category title; unknown keys show the key, as on the web).</summary>
    public string Title => RivalCategorization.Title(Route.Mode);

    /// <summary>Rival's name once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Subtitle), nameof(ViewProfileLabel))]
    private string? rivalName;

    /// <summary>Category description.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Subtitle))]
    private string description = "";

    /// <summary>Sorted rows.</summary>
    [ObservableProperty]
    private List<RivalSongItem> rows = [];

    /// <summary>Selected sort.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SortIndex))]
    private RivalrySort sort = RivalrySort.Category;

    /// <summary><c>vs. {name}</c> plus the category description.</summary>
    public string Subtitle => string.Join(" · ", new[] { RivalName is { } n ? $"vs. {n}" : null, Description.Length > 0 ? Description : null }
        .Where(p => p is not null));

    /// <summary>Profile action label.</summary>
    public string ViewProfileLabel => RivalName is { } name ? $"View {name}'s Profile" : "View Profile";

    /// <summary>Rival's player page.</summary>
    public AppRoute.Player ProfileRoute => new(Route.RivalId);

    /// <summary>Sort labels in picker order.</summary>
    public List<string> SortLabels { get; } = [.. Enum.GetValues<RivalrySort>().Select(s => s.Label())];

    /// <summary>Picker index of <see cref="Sort"/>.</summary>
    public int SortIndex
    {
        get => (int)Sort;
        set
        {
            if (Enum.IsDefined((RivalrySort)value)) Sort = (RivalrySort)value;
        }
    }

    /// <inheritdoc />
    public override string EmptyTitle => "No song data for this rival.";

    /// <summary>Re-sorts without reloading.</summary>
    /// <param name="value">New sort.</param>
    partial void OnSortChanged(RivalrySort value) => ApplySort();

    /// <inheritdoc />
    protected override async Task<RivalPageState> LoadContentAsync(CancellationToken cancellationToken)
    {
        var detailRead = Session.GetRivalDetailAsync(Route.Scope, Route.RivalId, Route.AllowLiveFallback, cancellationToken);
        var lookup = await CatalogLookupAsync();
        var detail = await detailRead;
        RivalName = detail.Rival.DisplayName ?? Route.Name;
        var category = RivalCategorization.Categorize(detail.Songs).FirstOrDefault(c => c.Key == Route.Mode);
        Description = category?.Subtitle ?? "";
        categorySongs = [.. (category?.Songs ?? []).Select(s => new RivalSongItem(s, lookup.GetValueOrDefault(s.SongId), PlayerName, RivalName ?? "Them"))];
        ApplySort();
        return categorySongs.Count == 0 ? RivalPageState.Empty : RivalPageState.Loaded;
    }

    /// <summary>Applies <see cref="Sort"/> to the loaded category.</summary>
    private void ApplySort()
    {
        Rows = RivalHeadToHead.Sort(categorySongs, s => s.Comparison, Sort);
    }
}
#endregion
