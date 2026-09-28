using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Identity action
/// <summary>What the header offers for the shown account.</summary>
public enum PlayerIdentityAction
{
    /// <summary>Nothing yet (loading, failed or syncing).</summary>
    None,
    /// <summary>No player selected: select directly.</summary>
    Select,
    /// <summary>Another player selected: switch after confirmation.</summary>
    Switch,
    /// <summary>This is the selected player: deselect after confirmation.</summary>
    Deselect,
    /// <summary>The read had no verified publication header; selection is paused.</summary>
    Unverified,
    /// <summary>Published scores changed since this read; reload before selecting.</summary>
    Changed,
}
#endregion

#region Player profile
/// <summary>
/// The player page (<c>/player/:accountId</c>) and the Statistics section (the selected player's profile; the web
/// renders both from <c>PlayerPage</c>). Reads only the keyless compact profile, the per-instrument rankings row and
/// rank history — never player-stats. Selecting, switching and deselecting never navigate away.
/// </summary>
public sealed partial class PlayerProfileViewModel : ObservableObject, IDisposable
{
    private readonly FestivalSession session;
    private readonly string? routeDisplayName;
    private CancellationTokenSource? load;
    private string? lastSelectedAccount;
    private IReadOnlyList<Instrument> lastVisible;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="accountId">Viewed account, or <see langword="null"/> to follow the selected player (Statistics).</param>
    /// <param name="routeDisplayName">Name known before the read (search result or leaderboard row).</param>
    public PlayerProfileViewModel(FestivalSession session, string? accountId, string? routeDisplayName = null)
    {
        this.session = session;
        this.routeDisplayName = routeDisplayName;
        FollowsSelection = accountId is null;
        this.accountId = accountId ?? session.SelectedPlayer?.AccountId ?? "";
        lastSelectedAccount = session.SelectedPlayer?.AccountId;
        lastVisible = session.Settings.VisibleInstruments;
        Status = new ServiceStatusViewModel("player-profile", "Profile unavailable", RetryAsync, session.Time);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Whether this is the Statistics root (always the selected player).</summary>
    public bool FollowsSelection { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Shown account.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsSelected), nameof(DisplayName), nameof(BandsRoute), nameof(HasAccount))]
    private string accountId;

    /// <summary>Load lifecycle (Empty = syncing).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowContent), nameof(ShowError), nameof(IsSyncing), nameof(QuickLinkSections))]
    private LoadState state = LoadState.Idle;

    /// <summary>Validated read backing the page.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DisplayName), nameof(IdentityAction))]
    private PlayerProfilePayload? payload;

    /// <summary>Overview tiles.</summary>
    [ObservableProperty]
    private List<PlayerStatTile> overview = [];

    /// <summary>One section per Settings-visible chart.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(QuickLinkSections))]
    private List<PlayerInstrumentViewModel> instruments = [];

    /// <summary>
    /// Quick Links sections while the profile shows (web <c>PlayerContent</c>): <c>global</c> "Global Statistics", one
    /// <c>instrument:&lt;key&gt;</c> per chart, <c>bands</c>. The web's <c>top-songs</c> has no Windows section yet.
    /// </summary>
    public List<QuickLinkSection> QuickLinkSections => !ShowContent || Instruments.Count == 0 ? [] :
    [
        new("global", "Global Statistics", "\uE9D2"),
        .. Instruments.Select(i => new QuickLinkSection(i.QuickLinkId, i.Label, Instrument: i.Instrument)),
        new("bands", "Bands", "\uE716"),
    ];

    /// <summary>Why the last Select failed.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasActionError))]
    private string? actionError;

    /// <summary>Whether <see cref="ActionError"/> is shown.</summary>
    public bool HasActionError => !string.IsNullOrEmpty(ActionError);

    /// <summary>Whether an account is shown (Statistics with no selection has none).</summary>
    public bool HasAccount => AccountId.Length > 0;

    /// <summary>Spinner.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle && HasAccount;

    /// <summary>Content.</summary>
    public bool ShowContent => State == LoadState.Loaded;

    /// <summary>Failure.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>HTTP 202: scores still syncing (never an empty profile).</summary>
    public bool IsSyncing => State == LoadState.Empty;

    /// <summary>Whether the shown account is the selected player.</summary>
    public bool IsSelected => HasAccount && string.Equals(session.SelectedPlayer?.AccountId, AccountId, StringComparison.OrdinalIgnoreCase);

    /// <summary>Server name, else the route/search name, else the account ID.</summary>
    public string DisplayName =>
        Payload?.Profile.DisplayName ??
        (IsSelected ? session.SelectedPlayer!.DisplayName : null) ?? routeDisplayName ?? AccountId;

    /// <summary>Syncing message.</summary>
    public string SyncingMessage => $"{DisplayName}'s public scores are still syncing. Try again shortly.";

    /// <summary>Header action for the current read.</summary>
    public PlayerIdentityAction IdentityAction
    {
        get
        {
            if (!ShowContent || Payload is not { } read) return PlayerIdentityAction.None;
            if (IsSelected) return PlayerIdentityAction.Deselect;
            if (read.PublicationId is null) return PlayerIdentityAction.Unverified;
            if (!read.IsSelectable(session.Api.CurrentPublication?.PublicationId)) return PlayerIdentityAction.Changed;
            return session.HasPlayer ? PlayerIdentityAction.Switch : PlayerIdentityAction.Select;
        }
    }

    /// <summary>Whether Select/Switch is offered.</summary>
    public bool CanSelect => IdentityAction is PlayerIdentityAction.Select or PlayerIdentityAction.Switch;

    /// <summary>Whether Deselect is offered.</summary>
    public bool CanDeselect => IdentityAction == PlayerIdentityAction.Deselect;

    /// <summary>Whether Select must be confirmed (switching away from another selected player).</summary>
    public bool SelectNeedsConfirmation => IdentityAction == PlayerIdentityAction.Switch;

    /// <summary>Select button label.</summary>
    public string SelectLabel => IdentityAction == PlayerIdentityAction.Switch ? "Switch to This Profile" : "Select Profile";

    /// <summary>Why selection is paused, or empty.</summary>
    public string IdentityNotice => IdentityAction switch
    {
        PlayerIdentityAction.Unverified => "These scores have no verified publication. Selection is paused.",
        PlayerIdentityAction.Changed => "Published scores changed. Reload this page before selecting.",
        _ => "",
    };

    /// <summary>Whether <see cref="IdentityNotice"/> is shown.</summary>
    public bool HasIdentityNotice => IdentityNotice.Length > 0;

    /// <summary>Switch confirmation body.</summary>
    public string SwitchMessage => $"Scores and profile-dependent pages will update to {DisplayName}.";

    /// <summary>Route to this player's bands.</summary>
    public AppRoute BandsRoute => new AppRoute.PlayerBands(AccountId);

    /// <summary>Bands link text.</summary>
    public string BandsLabel => $"View {DisplayName}'s Bands";

    /// <summary>Loads (or re-reads) the shown account.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        load?.Cancel();
        var current = load = new CancellationTokenSource();
        ActionError = null;
        if (!HasAccount)
        {
            Clear(LoadState.Idle);
            return;
        }
        if (IsSelected)
        {
            ApplyFromSession();
            await session.LoadSelectedProfileAsync();
            if (!current.IsCancellationRequested) ApplyFromSession();
            return;
        }
        Clear(LoadState.Loading);
        var account = AccountId;
        try
        {
            var read = await session.ViewPlayerAsync(account, current.Token);
            if (current.IsCancellationRequested || account != AccountId) return;
            Apply(read);
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (current.IsCancellationRequested) return;
            Clear(LoadState.Failed);
            Status.Report(error);
        }
    }

    /// <summary>Selects (or switches to) the shown player; the caller confirms a switch first.</summary>
    [RelayCommand]
    public void Select()
    {
        if (!CanSelect || Payload is not { } read) return;
        if (session.SelectPlayer(read, DisplayName))
        {
            ActionError = null;
            RefreshIdentity();
        }
        else
        {
            ActionError = "This profile could not be selected. Reload the page and try again.";
        }
    }

    /// <summary>Deselects the shown (selected) player; the caller confirms first.</summary>
    [RelayCommand]
    public void Deselect()
    {
        if (CanDeselect) session.DeselectPlayer();
    }

    /// <summary>Stops listening to the session (page unloaded).</summary>
    public void Dispose()
    {
        load?.Cancel();
        session.PropertyChanged -= OnSessionChanged;
        foreach (var section in Instruments) section.Cancel();
    }

    /// <summary>Retry: forces a fresh read.</summary>
    /// <returns>Load task.</returns>
    private async Task RetryAsync()
    {
        if (IsSelected)
        {
            Clear(LoadState.Loading);
            await session.LoadSelectedProfileAsync(force: true);
            ApplyFromSession();
            return;
        }
        await LoadAsync();
    }

    /// <summary>Mirrors the session's selected-player read.</summary>
    private void ApplyFromSession()
    {
        if (!IsSelected) return;
        switch (session.SelectedProfileStatus)
        {
            case SelectedProfileStatus.Available or SelectedProfileStatus.Syncing when session.SelectedProfile is { } read:
                if (!ReferenceEquals(read, Payload)) Apply(read);
                break;
            case SelectedProfileStatus.Failed:
                Clear(LoadState.Failed);
                Status.Report(session.SelectedProfileIssue ?? new ServiceIssue(ServiceIssueKind.Other));
                break;
            default:
                if (State != LoadState.Loading) Clear(LoadState.Loading);
                break;
        }
    }

    /// <summary>Shows a validated read.</summary>
    /// <param name="read">Read.</param>
    private void Apply(PlayerProfilePayload read)
    {
        Status.Clear();
        Payload = read;
        if (read.State == PlayerProfileState.Syncing)
        {
            Build(null);
            State = LoadState.Empty;
        }
        else
        {
            Build(read.Profile);
            State = LoadState.Loaded;
        }
        RefreshIdentity();
    }

    /// <summary>Drops content.</summary>
    /// <param name="next">Resulting state.</param>
    private void Clear(LoadState next)
    {
        foreach (var section in Instruments) section.Cancel();
        Payload = null;
        Overview = [];
        Instruments = [];
        State = next;
        RefreshIdentity();
    }

    /// <summary>Builds overview and per-instrument sections for the visible charts.</summary>
    /// <param name="profile">Available profile, or <see langword="null"/>.</param>
    private void Build(PlayerProfileResponse? profile)
    {
        foreach (var section in Instruments) section.Cancel();
        if (profile is null)
        {
            Overview = [];
            Instruments = [];
            return;
        }
        var visible = session.Settings.VisibleInstruments;
        var stats = PlayerStatistics.Overall(profile, visible);
        Overview =
        [
            new("Songs Played", stats.SongsPlayed.ToString("N0", CultureInfo.CurrentCulture)),
            new("Full Combos", stats.FullComboText),
            new("Gold Stars", stats.GoldStarCount.ToString("N0", CultureInfo.CurrentCulture), Gold: true),
            new("Avg Accuracy", stats.AverageAccuracyText),
            new("Best Rank", stats.BestRankText),
        ];
        Instruments = [.. visible.Select(i => new PlayerInstrumentViewModel(session, AccountId, profile, i))];
    }

    /// <summary>Raises every identity-derived property.</summary>
    private void RefreshIdentity()
    {
        foreach (var name in (string[])[nameof(IsSelected), nameof(DisplayName), nameof(IdentityAction),
                     nameof(CanSelect), nameof(CanDeselect), nameof(SelectNeedsConfirmation), nameof(SelectLabel),
                     nameof(IdentityNotice), nameof(HasIdentityNotice), nameof(SwitchMessage), nameof(BandsLabel),
                     nameof(SyncingMessage)])
            OnPropertyChanged(name);
    }

    /// <summary>Reacts to selection, visible charts and the selected player's read.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(FestivalSession.Settings):
                var selected = session.SelectedPlayer?.AccountId;
                if (selected != lastSelectedAccount)
                {
                    lastSelectedAccount = selected;
                    if (FollowsSelection)
                    {
                        // Per-entity reset: the Statistics root always shows the current selection.
                        AccountId = selected ?? "";
                        _ = LoadAsync();
                        return;
                    }
                    RefreshIdentity();
                }
                if (!lastVisible.SequenceEqual(session.Settings.VisibleInstruments))
                {
                    lastVisible = session.Settings.VisibleInstruments;
                    if (State == LoadState.Loaded) Build(Payload?.Profile);
                }
                break;
            case nameof(FestivalSession.SelectedProfileStatus) or nameof(FestivalSession.SelectedProfile):
                if (IsSelected && load is { IsCancellationRequested: false }) ApplyFromSession();
                break;
        }
    }
}

/// <summary>One stat tile (value over an uppercase label).</summary>
/// <param name="Label">Label.</param>
/// <param name="Value">Value text.</param>
/// <param name="Gold">Gold tint (gold stars, top-5%, full combos).</param>
public sealed record PlayerStatTile(string Label, string Value, bool Gold = false)
{
    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}: {Value}";
}
#endregion

#region Instrument section
/// <summary>Global-rank lifecycle for one chart.</summary>
public enum PlayerRankLoad
{
    /// <summary>Loading.</summary>
    Loading,
    /// <summary>HTTP 404: not ranked yet.</summary>
    Unranked,
    /// <summary>Rank shown.</summary>
    Available,
    /// <summary>Failed with an inline retry.</summary>
    Failed,
}

/// <summary>One Settings-visible chart: stats, global rank, rank-history chart and percentile bars.</summary>
public sealed partial class PlayerInstrumentViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly string accountId;
    private CancellationTokenSource? rankLoad;
    private CancellationTokenSource? historyLoad;
    private bool started;

    /// <summary>Creates a section and computes its client-side statistics.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="accountId">Shown account.</param>
    /// <param name="profile">Available profile.</param>
    /// <param name="instrument">Chart.</param>
    public PlayerInstrumentViewModel(FestivalSession session, string accountId, PlayerProfileResponse profile, Instrument instrument)
    {
        this.session = session;
        this.accountId = accountId;
        Instrument = instrument;
        var stats = PlayerStatistics.ForInstrument(profile, instrument);
        HasScores = stats.SongsPlayed > 0;
        Stats =
        [
            new("Songs Played", stats.SongsPlayed.ToString("N0", CultureInfo.CurrentCulture)),
            new("Full Combos", stats.FullComboText, Gold: stats.FullComboCount > 0),
            new("Gold Stars", stats.GoldStarCount.ToString("N0", CultureInfo.CurrentCulture), Gold: true),
            new("5 Stars", stats.FiveStarCount.ToString("N0", CultureInfo.CurrentCulture)),
            new("Avg Accuracy", stats.AverageAccuracyText),
            new("Best Rank", stats.BestRankText),
        ];
        Percentiles = PercentileBar.Build(PlayerStatistics.PercentileBuckets(profile, instrument));
    }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Instrument name.</summary>
    public string Label => Instrument.Label();

    /// <summary>Quick Links section ID (web <c>instrument:&lt;key&gt;</c>).</summary>
    public string QuickLinkId => "instrument:" + Instrument.ServiceId();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Stable automation suffix (service ID).</summary>
    public string AutomationKey => Instrument.ServiceId();

    /// <summary>Whether this chart has any scores.</summary>
    public bool HasScores { get; }

    /// <summary>Whether to show the empty footnote.</summary>
    public bool IsEmpty => !HasScores;

    /// <summary>Empty footnote.</summary>
    public string EmptyText => $"No {Label} scores recorded yet.";

    /// <summary>Stat tiles.</summary>
    public List<PlayerStatTile> Stats { get; }

    /// <summary>Placement distribution bars.</summary>
    public List<PercentileBar> Percentiles { get; }

    /// <summary>Whether the percentile card has bars.</summary>
    public bool HasPercentiles => Percentiles.Count > 0;

    /// <summary>Global-rank state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(RankLoading), nameof(RankUnranked), nameof(RankAvailable), nameof(RankFailed))]
    private PlayerRankLoad rankState = PlayerRankLoad.Loading;

    /// <summary>Global-rank tiles.</summary>
    [ObservableProperty]
    private List<PlayerStatTile> rankTiles = [];

    /// <summary>Global-rank failure text.</summary>
    [ObservableProperty]
    private string rankError = "";

    /// <summary>Rank-history chart, or <see langword="null"/> while loading, failed or without snapshots.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasRankHistory))]
    private RankHistoryChartModel? rankHistory;

    /// <summary>Rank-history failure text, or empty.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(RankHistoryFailed))]
    private string rankHistoryError = "";

    /// <summary>Loading.</summary>
    public bool RankLoading => HasScores && RankState == PlayerRankLoad.Loading;

    /// <summary>Unranked.</summary>
    public bool RankUnranked => RankState == PlayerRankLoad.Unranked;

    /// <summary>Available.</summary>
    public bool RankAvailable => RankState == PlayerRankLoad.Available;

    /// <summary>Failed.</summary>
    public bool RankFailed => RankState == PlayerRankLoad.Failed;

    /// <summary>Unranked footnote.</summary>
    public string UnrankedText => $"Not yet ranked globally on {Label}.";

    /// <summary>Whether the rank-history chart is shown.</summary>
    public bool HasRankHistory => RankHistory is not null;

    /// <summary>Whether the rank-history retry is shown.</summary>
    public bool RankHistoryFailed => RankHistoryError.Length > 0;

    /// <summary>Starts the rank and history reads once (when realized). Unplayed charts read nothing.</summary>
    /// <returns>Load task.</returns>
    public Task EnsureLoadedAsync()
    {
        if (started || !HasScores) return Task.CompletedTask;
        started = true;
        return Task.WhenAll(LoadRankAsync(), LoadRankHistoryAsync());
    }

    /// <summary>Stops in-flight reads.</summary>
    public void Cancel()
    {
        rankLoad?.Cancel();
        historyLoad?.Cancel();
    }

    /// <summary>Reads the global rank (Total Score, the web's default metric).</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadRankAsync()
    {
        rankLoad?.Cancel();
        var token = (rankLoad = new CancellationTokenSource()).Token;
        RankState = PlayerRankLoad.Loading;
        try
        {
            var read = await session.Api.GetPlayerInstrumentRankingAsync(Instrument, accountId, token);
            if (token.IsCancellationRequested) return;
            if (read.Ranking is not { } ranking)
            {
                RankState = PlayerRankLoad.Unranked;
                return;
            }
            RankTiles =
            [
                new("Global Rank", ranking.RankText),
                new("Total Score", ranking.TotalScoreText),
                new("Percentile", ranking.PercentileText, Gold: ranking.IsTopFive),
            ];
            RankState = PlayerRankLoad.Available;
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (token.IsCancellationRequested) return;
            RankError = $"Global rank unavailable: {ServiceIssue.From(error).Message}";
            RankState = PlayerRankLoad.Failed;
        }
    }

    /// <summary>Reads the 30-day rank history.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadRankHistoryAsync()
    {
        historyLoad?.Cancel();
        var token = (historyLoad = new CancellationTokenSource()).Token;
        RankHistoryError = "";
        try
        {
            var history = await session.Api.GetPlayerRankHistoryAsync(Instrument, accountId, 30, token);
            if (token.IsCancellationRequested) return;
            RankHistory = RankHistoryChartModel.Build(history.RankedChronological);
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (token.IsCancellationRequested) return;
            RankHistory = null;
            RankHistoryError = $"Rank history unavailable: {ServiceIssue.From(error).Message}";
        }
    }
}
#endregion
