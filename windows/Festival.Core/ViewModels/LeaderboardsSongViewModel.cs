using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Song leaderboard
/// <summary>
/// <c>/songs/:songId/:instrument</c>: one solo chart in 25-row pages (web <c>LeaderboardPage.tsx</c>, Apple
/// <c>SoloLeaderboardScreen</c>). Page count uses <c>localEntries ?? totalEntries</c>; an out-of-range deep-link page
/// is corrected once totals arrive. The selected player's row is highlighted in place and pinned below the list from
/// their already-loaded score index (no extra read), with a jump to its page when it is elsewhere.
/// </summary>
public sealed partial class SongLeaderboardViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private int version;
    private bool attached;
    private List<LeaderboardEntry> entries = [];

    /// <summary>Creates the page model for a route.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Song, chart and one-based page.</param>
    public SongLeaderboardViewModel(FestivalSession session, AppRoute.SongLeaderboard route)
    {
        this.session = session;
        SongId = route.SongId;
        Instrument = route.Instrument;
        page = Math.Max(1, route.Page);
        Pager = new RankingsPagerViewModel("fst.song-leaderboard", GoToPageAsync);
        Status = new ServiceStatusViewModel($"song-leaderboard:{route.SongId}:{route.Instrument.ServiceId()}", "Leaderboard unavailable",
            LoadAsync, session.Time);
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Instrument label.</summary>
    public string InstrumentLabel => Instrument.Label();

    /// <summary>Resolved song.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(Subtitle), nameof(IconFile))]
    private Song? song;

    /// <summary>One-based page.</summary>
    [ObservableProperty]
    private int page;

    /// <summary>Lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError), nameof(ShowContent))]
    private LoadState state = LoadState.Idle;

    /// <summary>Whether a page change is in flight over already-shown rows.</summary>
    [ObservableProperty]
    private bool isRefreshing;

    /// <summary>Page rows.</summary>
    [ObservableProperty]
    private List<SongLeaderboardRowViewModel> rows = [];

    /// <summary>"12,345 Lead entries" when the service allows totals, else empty.</summary>
    [ObservableProperty]
    private string totalText = "";

    /// <summary>Selected player's pinned row, when they have a score on this chart.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowSpotlight), nameof(CanJump))]
    [NotifyCanExecuteChangedFor(nameof(JumpCommand))]
    private SongLeaderboardRowViewModel? spotlight;

    /// <summary>Header title.</summary>
    public string Title => Song?.Title ?? "";

    /// <summary>Header subtitle (artist).</summary>
    public string Subtitle => Song?.Artist ?? "";

    /// <summary>Chart icon (keys variant for keyboard songs).</summary>
    public string IconFile => Instrument.IconFile(Song?.UsesKeyboardIcon == true);

    /// <summary>Whether the first load is in flight.</summary>
    public bool IsLoading => State is LoadState.Idle or LoadState.Loading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether "No scores yet." is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the header, spotlight and pager are shown.</summary>
    public bool ShowContent => State is LoadState.Loaded or LoadState.Empty;

    /// <summary>Whether the pinned row is shown.</summary>
    public bool ShowSpotlight => Spotlight is not null;

    /// <summary>Whether "Jump to your page" applies (ranked, on another page).</summary>
    public bool CanJump => Spotlight?.Entry.Rank is > 0 and var rank && LeaderboardPaging.PageForRank(rank) != Page &&
                           !entries.Any(e => RankingSpotlight.SameAccount(e.AccountId, Spotlight.Entry.AccountId));

    /// <summary>Starts following the selected player's scores; call when the page is shown.</summary>
    /// <returns>Load task.</returns>
    public Task ActivateAsync()
    {
        if (!attached)
        {
            session.PropertyChanged += OnSessionChanged;
            attached = true;
        }
        if (session.HasPlayer) _ = session.LoadSelectedProfileAsync();
        return State is LoadState.Idle or LoadState.Failed ? LoadAsync() : Task.CompletedTask;
    }

    /// <summary>Stops following the session (page left).</summary>
    public void Deactivate()
    {
        if (attached) session.PropertyChanged -= OnSessionChanged;
        attached = false;
    }

    /// <summary>Moves to a page.</summary>
    /// <param name="value">One-based page.</param>
    /// <returns>Load task.</returns>
    public Task GoToPageAsync(int value)
    {
        Page = Math.Max(1, value);
        return LoadAsync();
    }

    /// <summary>Resolves the song and loads the current page, dropping superseded responses.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var request = ++version;
        var requestedPage = Page;
        if (State != LoadState.Loaded) State = LoadState.Loading;
        IsRefreshing = true;
        try
        {
            var catalog = await session.LoadCatalogAsync();
            Song = catalog.Songs.FirstOrDefault(s => s.SongId == SongId) ?? throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404);
            var settings = session.Settings;
            double? leeway = settings.FilterInvalidScores ? Math.Round(settings.Leeway, 1) : null;
            var board = await session.Api.GetLeaderboardAsync(SongId, Instrument, requestedPage, LeaderboardPaging.PageSize, leeway);
            if (request != version) return;
            var pages = board.PageCount(LeaderboardPaging.PageSize);
            var corrected = LeaderboardPaging.Corrected(requestedPage, pages);
            if (corrected != requestedPage)
            {
                await GoToPageAsync(corrected);
                return;
            }
            Status.Clear();
            entries = [.. board.Entries];
            TotalText = board.ShowLeaderboardEntryTotals == true
                ? string.Create(CultureInfo.CurrentCulture, $"{board.TotalEntries:N0} {Instrument.Label()} entries") : "";
            Pager.Update(requestedPage, pages);
            ApplySelection();
            State = entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
            IsRefreshing = false;
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            IsRefreshing = false;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Jumps to the selected player's page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanJump))]
    private Task JumpAsync() => CanJump ? GoToPageAsync(LeaderboardPaging.PageForRank(Spotlight!.Entry.Rank)) : Task.CompletedTask;

    /// <summary>Builds rows (with the selected highlight) and the pinned row from the current score index.</summary>
    private void ApplySelection()
    {
        var selected = session.SelectedPlayer;
        Rows = entries.Select(e => new SongLeaderboardRowViewModel(e, RankingSpotlight.SameAccount(e.AccountId, selected?.AccountId))).ToList();
        Spotlight = SelectedEntry() is { } own ? new SongLeaderboardRowViewModel(own, true) : null;
        OnPropertyChanged(nameof(CanJump));
        JumpCommand.NotifyCanExecuteChanged();
    }

    /// <summary>
    /// The selected player's row for this chart from their score index, only when that index belongs to the current
    /// publication. With invalid-score filtering on, an invalid score falls back to its valid variant (unranked here).
    /// </summary>
    /// <returns>Synthetic entry, or <see langword="null"/>.</returns>
    private LeaderboardEntry? SelectedEntry()
    {
        if (session.SelectedPlayer is not { } player || !session.IsSelectedProfileCurrent ||
            session.SelectedScoreIndex?.GetValueOrDefault(SongId)?.GetValueOrDefault(Instrument) is not { } score)
            return null;
        if (session.Settings.FilterInvalidScores && score.IsValidScore == false)
        {
            if (score.ValidScore is not { } valid) return null;
            return new LeaderboardEntry
            {
                AccountId = player.AccountId, DisplayName = player.DisplayName, Score = valid,
                Accuracy = score.ValidAccuracy, IsFullCombo = score.ValidIsFullCombo, Stars = score.Stars, Season = score.Season,
            };
        }
        return new LeaderboardEntry
        {
            AccountId = player.AccountId, DisplayName = player.DisplayName, Score = score.Score, Rank = score.Rank ?? 0,
            Accuracy = score.Accuracy, IsFullCombo = score.IsFullCombo, Stars = score.Stars, Season = score.Season,
        };
    }

    /// <summary>Refreshes highlights when the selection or its scores change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        var relevant = e.PropertyName is nameof(FestivalSession.Settings) or nameof(FestivalSession.SelectedProfile) or
            nameof(FestivalSession.SelectedProfileStatus);
        if (relevant && State is LoadState.Loaded or LoadState.Empty) ApplySelection();
    }
}

/// <summary>One solo chart row. The selected player opens Statistics; everyone else opens their profile.</summary>
/// <param name="Entry">Wire row (or the selected player's synthetic row).</param>
/// <param name="IsSelected">Whether this is the selected player.</param>
public sealed record SongLeaderboardRowViewModel(LeaderboardEntry Entry, bool IsSelected)
{
    /// <summary><c>#1,234</c>, or an em dash when unranked.</summary>
    public string RankText => Entry.Rank > 0 ? ScoreFormatting.Rank(Entry.Rank) : "—";

    /// <summary>Display name.</summary>
    public string Name => string.IsNullOrWhiteSpace(Entry.DisplayName) ? "Unknown User" : Entry.DisplayName!;

    /// <summary>Grouped score.</summary>
    public string Score => ScoreFormatting.Score(Entry.Score);

    /// <summary>Accuracy text.</summary>
    public string Accuracy => ScoreFormatting.Accuracy(Entry.Accuracy);

    /// <summary>Whether the accuracy pill is shown.</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Explicit full combo.</summary>
    public bool IsFullCombo => Entry.IsFullCombo == true;

    /// <summary>Pill text ("98.5%" or "FC 100%").</summary>
    public string AccuracyPill => IsFullCombo ? "FC " + Accuracy : Accuracy;

    /// <summary>Stars text (★ × n), or empty.</summary>
    public string Stars => Entry.Stars is > 0 and var n ? new string('★', Math.Min(n, 5)) : "";

    /// <summary>Season text (<c>S15</c>), or empty.</summary>
    public string Season => Entry.Season is { } s ? string.Create(CultureInfo.InvariantCulture, $"S{s}") : "";

    /// <summary>Statistics for the selected player, the profile otherwise, or <see langword="null"/> without a usable ID.</summary>
    public AppRoute? Route => IsSelected ? new AppRoute.Statistics() :
        ProfileText.IsValidAccountId(Entry.AccountId) ? new AppRoute.Player(Entry.AccountId, Entry.DisplayName) : null;

    /// <summary>UIA automation ID (<c>fst.song-leaderboard.row.&lt;accountId&gt;</c>).</summary>
    public string AutomationId => "fst.song-leaderboard.row." + Entry.AccountId;

    /// <summary>Screen-reader name.</summary>
    public string Announcement =>
        (IsSelected && Entry.Rank > 0 ? $"Your rank, {RankingFormatting.Ordinal(Entry.Rank)}. {Name}" :
         IsSelected ? $"Your score. {Name}" : $"Rank {RankText}, {Name}") +
        $", {Score} points" + (HasAccuracy ? $", {Accuracy} accuracy" : "") + (IsFullCombo ? ", full combo" : "") +
        (Entry.Stars is > 0 ? $", {Entry.Stars} stars" : "");
}
#endregion
