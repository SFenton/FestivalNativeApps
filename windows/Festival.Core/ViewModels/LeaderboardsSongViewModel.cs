using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Festival.Core.Domain;

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
    private double? loadedLeeway;
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
        LoadSwap = new LoadSwap(session.Time);
        LoadSwap.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(ShowRows));
            OnPropertyChanged(nameof(ShowEmpty));
            OnPropertyChanged(nameof(ShowError));
        };
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Pager.</summary>
    public RankingsPagerViewModel Pager { get; }

    /// <summary>Full-page failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Rows/content load-swap gate.</summary>
    public LoadSwap LoadSwap { get; }

    /// <summary>Whether load-swap motion is allowed; the app layer supplies <c>Motion.Allowed</c>.</summary>
    public Func<bool> AnimateLoadSwaps { get; set; } = () => false;

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
    [NotifyPropertyChangedFor(nameof(HasTotal))]
    private string totalText = "";

    /// <summary>Whether the totals line shows (no empty line above the rows otherwise).</summary>
    public bool HasTotal => TotalText.Length > 0;

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
    public bool IsLoading => LoadSwap.IsLoading;

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded && LoadSwap.ContentVisible;

    /// <summary>Whether "No scores yet." is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty && LoadSwap.ContentVisible;

    /// <summary>Whether the full-page failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed && LoadSwap.ContentVisible;

    /// <summary>
    /// Whether the song header and pager are shown. They stay in place while another page loads (web
    /// <c>PaginatedLeaderboard</c> keeps its pagination mounted after the first load): <see cref="State"/> only changes
    /// when a load commits, so only the rows swap for the spinner (issue #93).
    /// </summary>
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
        return State is LoadState.Idle or LoadState.Failed || LeewayChanged ? LoadAsync() : Task.CompletedTask;
    }

    /// <summary>The <c>leeway</c> query for the current settings (rounded to the slider's 0.1 step), or none when off.</summary>
    private double? CurrentLeeway => session.Settings.FilterInvalidScores ? Math.Round(session.Settings.Leeway, 1) : null;

    /// <summary>Whether shown rows were read with a different Filter Invalid Scores leeway than the current one.</summary>
    private bool LeewayChanged => State is LoadState.Loaded or LoadState.Empty && CurrentLeeway != loadedLeeway;

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
        var swap = LoadSwap.BeginReloadAsync(AnimateLoadSwaps(), State is LoadState.Loaded or LoadState.Empty or LoadState.Failed && LoadSwap.ContentVisible);
        if (State is LoadState.Idle) State = LoadState.Loading;
        IsRefreshing = true;
        try
        {
            var catalog = await session.LoadCatalogAsync();
            Song = catalog.Songs.FirstOrDefault(s => s.SongId == SongId) ?? throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404);
            var leeway = CurrentLeeway;
            var board = await session.Api.GetLeaderboardAsync(SongId, Instrument, requestedPage, LeaderboardPaging.PageSize, leeway);
            if (request != version) return;
            loadedLeeway = leeway;
            var pages = board.PageCount(LeaderboardPaging.PageSize);
            var corrected = LeaderboardPaging.Corrected(requestedPage, pages);
            if (corrected != requestedPage)
            {
                await GoToPageAsync(corrected);
                return;
            }
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Clear();
                entries = [.. board.Entries];
                TotalText = board.ShowLeaderboardEntryTotals == true
                    ? string.Create(CultureInfo.CurrentCulture, $"{board.TotalEntries:N0} {Instrument.Label()} entries") : "";
                Pager.Update(requestedPage, pages);
                ApplySelection();
                State = entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
                IsRefreshing = false;
            }, AnimateLoadSwaps());
        }
        catch (FestivalApiException error)
        {
            if (request != version) return;
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                IsRefreshing = false;
                Status.Report(error);
                State = LoadState.Failed;
            }, AnimateLoadSwaps());
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
        var rows = entries.Select(e => new SongLeaderboardRowViewModel(e, RankingSpotlight.SameAccount(e.AccountId, selected?.AccountId))).ToList();
        var spotlight = SelectedEntry() is { } own ? new SongLeaderboardRowViewModel(own, true) : null;
        // Web computeRankWidth / score "ch" width over the page and the pinned row: every row, including the pinned
        // selected-player row, gets the same columns at the same widths so they line up (operator batch 7.9, issue #37).
        var section = LeaderboardColumns.Measure(spotlight is null ? rows : [.. rows, spotlight]);
        Rows = [.. rows.Select(r => r with { Section = section })];
        Spotlight = spotlight is null ? null : spotlight with { Section = section };
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
        if (e.PropertyName == nameof(FestivalSession.Settings) && LeewayChanged) _ = LoadAsync();
        else if (relevant && State is LoadState.Loaded or LoadState.Empty) ApplySelection();
    }
}

/// <summary>One solo chart row. The selected player opens Statistics; everyone else opens their profile.</summary>
/// <param name="Entry">Wire row (or the selected player's synthetic row).</param>
/// <param name="IsSelected">Whether this is the selected player.</param>
public sealed record SongLeaderboardRowViewModel(LeaderboardEntry Entry, bool IsSelected) : ILeaderboardScoreRow
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

    /// <summary>Badge text: the accuracy alone; a full combo is shown by the gold badge style, not an "FC" prefix (web).</summary>
    public string AccuracyPill => Accuracy;

    /// <summary>Accuracy in ten-thousandths of a percent, for the badge tint.</summary>
    public double AccuracyValue => Entry.Accuracy ?? 0;

    /// <inheritdoc />
    public LeaderboardSection? Section { get; init; }

    /// <summary>Service stars (0 when missing), drawn as star images by the row.</summary>
    public int StarCount => Entry.Stars ?? 0;

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
