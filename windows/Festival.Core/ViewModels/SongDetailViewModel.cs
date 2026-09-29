using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Song detail
/// <summary>
/// Song Detail: header, Intensity for all charted instruments, the selected player's score history, and a top-10 card per
/// visible chart. Like the web (<c>SongDetailPage.tsx</c> <c>allReady</c>), the page stays on its spinner until the song,
/// the player's scores, the history and every chart's top rows (one <c>/all</c> read) are in, then reveals everything.
/// </summary>
public sealed partial class SongDetailViewModel : ObservableObject
{
    /// <summary>Rows per chart card.</summary>
    public const int PreviewTop = 10;

    /// <summary>Quick Links / scroll anchor of the history section.</summary>
    public const string HistoryQuickLinkId = "score-history";

    private readonly FestivalSession session;
    private string? lastAccount;

    /// <summary>Creates the page model for a route.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Detail route (song ID and optional initial chart).</param>
    public SongDetailViewModel(FestivalSession session, AppRoute.SongDetail route) : this(session, route.SongId, route.Instrument, false)
    {
    }

    /// <summary>Creates the page model for the score-history route: Song Detail scrolled to the history section.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">History route (song and chart).</param>
    public SongDetailViewModel(FestivalSession session, AppRoute.PlayerHistory route) : this(session, route.SongId, route.Instrument, true)
    {
    }

    /// <summary>Shared constructor.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="songId">Song.</param>
    /// <param name="instrument">Initial chart.</param>
    /// <param name="scrollToHistory">Whether to open at the history section.</param>
    private SongDetailViewModel(FestivalSession session, string songId, Instrument? instrument, bool scrollToHistory)
    {
        this.session = session;
        SongId = songId;
        InitialInstrument = instrument;
        ScrollToHistory = scrollToHistory;
        lastAccount = session.SelectedPlayer?.AccountId;
        History = new SongScoreHistoryViewModel(session, songId, instrument);
        History.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SongScoreHistoryViewModel.Phase)) OnPropertyChanged(nameof(QuickLinkSections));
        };
        Status = new ServiceStatusViewModel("song-detail", "Song unavailable", LoadAsync, session.Time);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Stops following the session (page left).</summary>
    public void Detach() => session.PropertyChanged -= OnSessionChanged;

    /// <summary>Refreshes each card's player summary when the selected player's scores change state.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FestivalSession.Settings) && session.SelectedPlayer?.AccountId != lastAccount)
        {
            // Per-entity reset: another player's history (the cards follow through the score source below).
            lastAccount = session.SelectedPlayer?.AccountId;
            if (State == LoadState.Loaded) _ = History.LoadAsync(Song, VisibleCharted());
        }
        if (!SongScoreSource.AffectsRows(e.PropertyName) && e.PropertyName != nameof(FestivalSession.Catalog)) return;
        var scores = SongScoreSource.For(session);
        foreach (var card in Leaderboards) card.UpdatePlayer(scores);
    }

    /// <summary>The selected player's score history section.</summary>
    public SongScoreHistoryViewModel History { get; }

    /// <summary>Whether the page opens scrolled to the history section (the <c>/songs/:id/:instrument/history</c> route).</summary>
    public bool ScrollToHistory { get; }

    /// <summary>Requested song.</summary>
    public string SongId { get; }

    /// <summary>Chart to bring into view first, if any.</summary>
    public Instrument? InitialInstrument { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowContent), nameof(ShowError), nameof(IsLoading))]
    private LoadState state = LoadState.Idle;

    /// <summary>Resolved song.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(BandLinks))]
    private Song? song;

    /// <summary>Intensity rows for every charted instrument (including Settings-hidden ones).</summary>
    [ObservableProperty]
    private List<IntensityRow> intensity = [];

    /// <summary>Leaderboard previews for visible charted instruments.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(QuickLinkSections))]
    private List<LeaderboardPreviewViewModel> leaderboards = [];

    /// <summary>
    /// Quick Links (web <c>SongDetailPage.tsx:535-587</c>, offered on mobile only): <c>intensity</c>, <c>score-history</c> while
    /// that section shows, then one <c>instrument-&lt;key&gt;</c> per leaderboard card. Band sections have no Windows section yet.
    /// </summary>
    public List<QuickLinkSection> QuickLinkSections
    {
        get
        {
            if (Leaderboards.Count == 0) return [];
            List<QuickLinkSection> sections = [new("intensity", "Intensity", "\uE9D9")];
            if (History.IsVisible) sections.Add(new(HistoryQuickLinkId, "Score History", "\uE81C"));
            sections.AddRange(Leaderboards.Select(c => new QuickLinkSection(c.QuickLinkId, c.Title, Instrument: c.Instrument)));
            return sections;
        }
    }

    /// <summary>Validated offer for this song (none while the Shop is hidden).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasShopLink), nameof(ShopHighlight), nameof(ShopPulses), nameof(ShopButtonName))]
    private ShopSong? shopOffer;

    /// <summary>Why Shop status is unavailable, or <see langword="null"/>.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasShopIssue))]
    private string? shopIssueText;

    /// <summary>Visible, charted, path-capable instruments (Karaoke has no paths).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasPaths))]
    private List<Instrument> pathInstruments = [];

    /// <summary>Whether the official Item Shop action shows.</summary>
    public bool HasShopLink => ShopOffer?.ShopUri is not null;

    /// <summary>Effective Shop accent.</summary>
    public ShopHighlight? ShopHighlight => ShopPresentationPolicy.Highlight(ShopOffer, session.Settings.HideShop, session.Settings.DisableShopHighlighting);

    /// <summary>
    /// Whether the Item Shop button breathes in its status colour (web <c>shopPulse</c>: any offer while Shop
    /// highlighting is on). The status replaces the old "Item Shop: …" badge; <see cref="ShopButtonName"/> speaks it.
    /// </summary>
    public bool ShopPulses => HasShopLink && session.Settings.ShopHighlightEnabled;

    /// <summary>Accessible name of the Item Shop button, e.g. "Open in Item Shop, Leaving Tomorrow".</summary>
    public string ShopButtonName => ShopPulse.ButtonName(ShopHighlight);

    /// <summary>Whether the Shop-status error shows.</summary>
    public bool HasShopIssue => ShopIssueText is not null;

    /// <summary>Band leaderboard links (Duos, Trios, Quads) for this song.</summary>
    public List<BandLeaderboardLink> BandLinks => Song is { } song
        ? [.. BandTypeInfo.All.Select(b => new BandLeaderboardLink(b.Label(), new AppRoute.SongBandLeaderboard(song.SongId, b.ServiceId())))]
        : [];

    /// <summary>Whether the Paths action shows.</summary>
    public bool HasPaths => PathInstruments.Count > 0;

    /// <summary>Whether content is shown.</summary>
    public bool ShowContent => State == LoadState.Loaded;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the page is loading.</summary>
    public bool IsLoading => State == LoadState.Loading;

    /// <summary>
    /// Resolves the song against the catalogue, then reads the player's scores, their history for this song and every
    /// chart's top rows together; the page keeps its spinner until all of them settle (a failed chart read becomes each
    /// card's inline error with Retry, a failed history read the section's).
    /// </summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        State = LoadState.Loading;
        try
        {
            var catalog = await session.LoadCatalogAsync();
            var found = catalog.Songs.FirstOrDefault(s => s.SongId == SongId)
                        ?? throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404);
            Status.Clear();
            Song = found;
            Intensity = InstrumentInfo.All
                .Where(found.Supports)
                .Select(i => new IntensityRow(i, found.Difficulty!.ChartedValue(i)!.Value, found.UsesKeyboardIcon))
                .ToList();
            await SongScoreSource.LoadAsync(session);
            var scores = SongScoreSource.For(session);
            var charted = VisibleCharted();
            var cards = charted.Select(i => new LeaderboardPreviewViewModel(session, found, i, scores)).ToList();
            await Task.WhenAll(cards.Count == 0 ? Task.CompletedTask : LoadBoardsAsync(found, cards), History.LoadAsync(found, charted));
            // Scores may have settled while the reads ran (the session only updates published cards).
            var latest = SongScoreSource.For(session);
            foreach (var card in cards) card.UpdatePlayer(latest);
            Leaderboards = cards;
            PathInstruments = [.. charted.Where(i => i.HasPaths())];
            State = LoadState.Loaded;
            await LoadShopAsync();
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Visible charted instruments in display order (cards, history selector and Paths).</summary>
    /// <returns>Instruments.</returns>
    private List<Instrument> VisibleCharted()
    {
        var visible = session.Settings.VisibleInstruments;
        return Song is { } song ? [.. InstrumentInfo.All.Where(i => visible.Contains(i) && song.Supports(i))] : [];
    }

    /// <summary>
    /// Fills every card from one <c>/all</c> read, or reports its failure on each card. A 404 (a service or fixture
    /// without the combined route) falls back to one read per chart.
    /// </summary>
    /// <param name="song">Song.</param>
    /// <param name="cards">Cards.</param>
    /// <returns>Load task.</returns>
    private async Task LoadBoardsAsync(Song song, List<LeaderboardPreviewViewModel> cards)
    {
        try
        {
            double? leeway = session.Settings.FilterInvalidScores ? session.Settings.Leeway : null;
            var all = await session.Api.GetAllLeaderboardsAsync(song.SongId, PreviewTop, leeway);
            foreach (var card in cards) card.Apply(all.For(card.Instrument));
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            await Task.WhenAll(cards.Select(c => c.LoadAsync()));
        }
        catch (FestivalApiException error)
        {
            foreach (var card in cards) card.Fail(error);
        }
    }

    /// <summary>Resolves this song's offer from the session feed (loading it once), recording failures.</summary>
    /// <returns>Load task.</returns>
    public async Task LoadShopAsync()
    {
        if (session.Settings.HideShop || Song is not { } song)
        {
            ShopOffer = null;
            ShopIssueText = null;
            return;
        }
        await session.TryLoadShopAsync();
        ShopOffer = session.FindOffer(song.SongId);
        ShopIssueText = session.Shop is null && session.ShopIssue is { } issue ? "Item Shop status unavailable: " + issue.Message : null;
    }

    /// <summary>Opens a Paths session for this song.</summary>
    /// <returns>Paths model, or <see langword="null"/> when no chart has paths.</returns>
    public SongPathsViewModel? CreatePaths() =>
        Song is { } song && HasPaths ? new SongPathsViewModel(session, song, PathInstruments) : null;
}

/// <summary>Song Detail layout rules.</summary>
public static class SongDetailLayout
{
    /// <summary>Width of one Intensity cell (web <c>minmax(106px, 1fr)</c>) plus its 16 epx gap.</summary>
    public const double IntensityCell = 106 + 16;

    /// <summary>Wide windows put every charted instrument on one row when it fits; otherwise three per row (3×3).</summary>
    /// <param name="width">Repeater width.</param>
    /// <param name="count">Charted instruments.</param>
    /// <returns>Columns.</returns>
    public static int IntensityColumns(double width, int count) =>
        count > 3 && double.IsFinite(width) && width + 16 >= count * IntensityCell ? count : 3;
}

/// <summary>A link to one band size's leaderboard for the song.</summary>
/// <param name="Label">"Duos".</param>
/// <param name="Route">Band leaderboard route.</param>
public sealed record BandLeaderboardLink(string Label, AppRoute Route);

/// <summary>One Intensity row: icon, meter and spoken level.</summary>
/// <param name="Instrument">Chart.</param>
/// <param name="Raw">Raw 0–6 difficulty.</param>
/// <param name="Keyboard">Whether to use the keys icon variant.</param>
public sealed record IntensityRow(Instrument Instrument, double Raw, bool Keyboard)
{
    /// <summary>Filled bars (1–7).</summary>
    public int Bars => DifficultyScale.BarsForRaw(Raw);

    /// <summary>Instrument label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Icon file name.</summary>
    public string IconFile => Instrument.IconFile(Keyboard);

    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}, {DifficultyScale.Announcement(Raw)}";
}
#endregion

#region Leaderboard preview
/// <summary>A per-chart top-10 card with its own loading, empty, error and rows states.</summary>
public sealed partial class LeaderboardPreviewViewModel : ObservableObject
{
    /// <summary>Rows in a Detail preview.</summary>
    public const int PreviewSize = 10;

    private readonly FestivalSession session;
    private List<LeaderboardRow> topRows = [];
    private SongScoreDetail? playerDetail;
    private bool started;

    /// <summary>Creates a card.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="song">Song.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="scores">Selected-player score source at page load.</param>
    public LeaderboardPreviewViewModel(FestivalSession session, Song song, Instrument instrument, SongScoreSource? scores = null)
    {
        this.session = session;
        Song = song;
        Instrument = instrument;
        HasPlayer = session.HasPlayer;
        PlayerAccountId = session.SelectedPlayer?.AccountId;
        UpdatePlayer(scores);
        Status = new ServiceStatusViewModel($"preview:{song.SongId}:{instrument.ServiceId()}", $"{instrument.Label()} unavailable", LoadAsync, session.Time);
    }

    /// <summary>Song.</summary>
    public Song Song { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Card title.</summary>
    public string Title => Instrument.Label();

    /// <summary>Quick Links section ID (web <c>instrument-&lt;key&gt;</c>).</summary>
    public string QuickLinkId => "instrument-" + Instrument.ServiceId();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile(Song.UsesKeyboardIcon);

    /// <summary>Player-profile route for a top-ten row (none without an account).</summary>
    /// <param name="entry">Row.</param>
    /// <returns>Route or <see langword="null"/>.</returns>
    private static AppRoute? PlayerRoute(LeaderboardEntry entry) =>
        string.IsNullOrWhiteSpace(entry.AccountId) ? null : new AppRoute.Player(entry.AccountId, entry.DisplayName);

    /// <summary>Route for the full 25-row leaderboard.</summary>
    public AppRoute FullRoute => new AppRoute.SongLeaderboard(Song.SongId, Instrument);

    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer { get; }

    /// <summary>Selected player's account, for row highlighting.</summary>
    public string? PlayerAccountId { get; }

    /// <summary>Recomputes row eleven (scores finished loading, went syncing or paused).</summary>
    /// <param name="scores">Current score source.</param>
    public void UpdatePlayer(SongScoreSource? scores)
    {
        playerDetail = scores?.Detail?.Invoke(Song.SongId, Instrument) is { Score: > 0 } found ? found : null;
        if (State == LoadState.Loaded) ComposeRows();
    }

    /// <summary>Whether a row (highlighted top-ten row or row eleven) stands for the selected player.</summary>
    [ObservableProperty]
    private bool hasPlayerRow;

    /// <summary>"12,345 total entries" (web <c>leaderboard.totalEntries</c>) when the service allows totals; else empty.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasTotalEntries))]
    private string totalEntriesText = "";

    /// <summary>Header subtitle of a chart with no scores (web <c>songDetail.noScores</c>).</summary>
    public const string NoScoresText = "No scores recorded yet";

    /// <summary>Body of an empty card (web <c>songDetail.noScoresSubtitle</c>).</summary>
    public string EmptyText => $"When scores are submitted for {Title}, they will show up here on the next leaderboard update.";

    /// <summary>Whether the header subtitle shows.</summary>
    public bool HasTotalEntries => TotalEntriesText.Length > 0;

    /// <summary>Accessible name of the header group: "Lead, 12,345 total entries".</summary>
    public string HeaderName => HasTotalEntries ? $"{Title}, {TotalEntriesText}" : Title;

    /// <summary>Automation ID of the full-leaderboard button.</summary>
    public string ViewAllAutomationId => "fst.song-detail.view-all." + Instrument.ServiceId();

    /// <summary>Accessible name of the full-leaderboard button.</summary>
    public string ViewAllName => $"View full {Title} leaderboard";

    /// <summary>Appends the selected player's own score as row eleven when they rank outside the top ten.</summary>
    private void ComposeRows()
    {
        var inTop = PlayerAccountId is { } id && topRows.Any(r => string.Equals(r.Entry.AccountId, id, StringComparison.OrdinalIgnoreCase));
        List<LeaderboardRow> rows = [.. topRows.Select(r => r with { Route = PlayerRoute(r.Entry) })];
        if (!inTop && PlayerAccountId is { } account && playerDetail is { Rank: > PreviewSize } detail)
        {
            rows.Add(new LeaderboardRow(new LeaderboardEntry
            {
                AccountId = account,
                DisplayName = session.SelectedPlayer?.DisplayName,
                Score = detail.Score,
                Rank = detail.Rank.Value,
                Accuracy = detail.Accuracy,
                IsFullCombo = detail.IsFullCombo,
                Stars = detail.Stars,
                Season = detail.Season,
            })
            {
                IsSelectedPlayer = true,
                // Web spotlight row: the full board at the player's page (25 rows a page).
                Route = new AppRoute.SongLeaderboard(Song.SongId, Instrument, (detail.Rank.Value - 1) / 25 + 1),
            });
        }
        Rows = rows;
        HasPlayerRow = rows.Any(r => r.IsSelectedPlayer);
    }

    /// <summary>Inline failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Rows.</summary>
    [ObservableProperty]
    private List<LeaderboardRow> rows = [];

    /// <summary>Whether loading.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether "No scores yet" is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the inline error is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Starts loading once (called when the card is realized).</summary>
    /// <returns>Load task.</returns>
    public Task EnsureLoadedAsync()
    {
        if (started) return Task.CompletedTask;
        started = true;
        return LoadAsync();
    }

    /// <summary>Reads the top ten scores (Retry, or a card created without a prefetched page).</summary>
    /// <returns>Load task.</returns>
    public async Task LoadAsync()
    {
        started = true;
        State = LoadState.Loading;
        try
        {
            double? leeway = session.Settings.FilterInvalidScores ? session.Settings.Leeway : null;
            Apply(await session.Api.GetLeaderboardAsync(Song.SongId, Instrument, 1, PreviewSize, leeway));
        }
        catch (FestivalApiException error)
        {
            Fail(error);
        }
    }

    /// <summary>Shows a page of top rows (from the song's <c>/all</c> read or this chart's own read).</summary>
    /// <param name="board">Rows for this chart.</param>
    public void Apply(LeaderboardResponse board)
    {
        started = true;
        topRows = board.Entries.Select(e => new LeaderboardRow(e)
        {
            IsSelectedPlayer = PlayerAccountId is { } id && string.Equals(e.AccountId, id, StringComparison.OrdinalIgnoreCase),
        }).ToList();
        TotalEntriesText = board.Entries.Count == 0 ? NoScoresText : board.ShowLeaderboardEntryTotals == true && board.TotalEntries > 0
            ? string.Create(System.Globalization.CultureInfo.CurrentCulture, $"{board.TotalEntries:N0} total {(board.TotalEntries == 1 ? "entry" : "entries")}") : "";
        OnPropertyChanged(nameof(HeaderName));
        ComposeRows();
        Status.Clear();
        State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
    }

    /// <summary>Shows the inline error with Retry.</summary>
    /// <param name="error">Failure.</param>
    public void Fail(FestivalApiException error)
    {
        started = true;
        Status.Report(error);
        State = LoadState.Failed;
    }
}

/// <summary>Display projection of one leaderboard entry.</summary>
/// <param name="Entry">Wire row.</param>
public sealed record LeaderboardRow(LeaderboardEntry Entry)
{
    /// <summary><c>#1</c>.</summary>
    public string Rank => ScoreFormatting.Rank(Entry.Rank);

    /// <summary>Display name, or a neutral placeholder.</summary>
    public string Name => string.IsNullOrWhiteSpace(Entry.DisplayName) ? "Unknown player" : Entry.DisplayName!;

    /// <summary>Grouped score.</summary>
    public string Score => ScoreFormatting.Score(Entry.Score);

    /// <summary>Accuracy text, <c>FC</c> suffix handled by the view.</summary>
    public string Accuracy => ScoreFormatting.Accuracy(Entry.Accuracy);

    /// <summary>Expanded accuracy for the badge tint (0 when missing).</summary>
    public double AccuracyValue => Entry.Accuracy ?? 0;

    /// <summary>Whether an accuracy value exists (hides the empty pill).</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Whether the explicit FC flag is set.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>Whether this row is the selected player (highlighted).</summary>
    public bool IsSelectedPlayer { get; init; }

    /// <summary>Where the row leads (player profile, or the full board for the player's own row eleven).</summary>
    public AppRoute? Route { get; init; }

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"Rank {Entry.Rank}, {Name}, {Score} points" +
                                  (Accuracy.Length > 0 ? $", {Accuracy} accuracy" : "") + (IsFullCombo ? ", full combo" : "") + (IsSelectedPlayer ? ", you" : "");
}
#endregion
