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
    [NotifyPropertyChangedFor(nameof(IsSelected), nameof(DisplayName), nameof(HasAccount))]
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
        new(BandsQuickLinkId, "Bands", "\uE716"),
    ];

    /// <summary>Quick Links section ID of Bands, the section after the instrument cards.</summary>
    public const string BandsQuickLinkId = "bands";

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


    /// <summary>
    /// Inline "{name}'s Bands" section after the instrument cards (issue #312), created with the profile content and
    /// loaded separately so it never holds the page; <see langword="null"/> while no profile shows.
    /// </summary>
    [ObservableProperty]
    private PlayerProfileBandsViewModel? bands;

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
        Bands?.Cancel();
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
        Bands?.Cancel();
        Bands = null;
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
        var catalogSize = session.Catalog?.Songs.Count ?? 0;
        Overview =
        [
            new("songs-played", "Songs Played", stats.SongsPlayed.ToString("N0", CultureInfo.CurrentCulture),
                catalogSize > 0 && stats.SongsPlayed >= catalogSize ? PlayerStatTint.Green : PlayerStatTint.Default,
                link: new PlayerStatLink.Songs(new SongsStatPreset(null, SongScoreFilterKind.HasScores))),
            new("full-combos", "Full Combos", stats.FullComboText,
                stats.SongsPlayed > 0 && stats.FullComboPercent >= 100 ? PlayerStatTint.Gold : PlayerStatTint.Default,
                link: new PlayerStatLink.Songs(new SongsStatPreset(null, SongScoreFilterKind.HasFCs))),
            new("gold-stars", "Gold Stars", stats.GoldStarCount.ToString("N0", CultureInfo.CurrentCulture), PlayerStatTint.Gold),
            new("avg-accuracy", "Avg Accuracy", stats.AverageAccuracyText),
            new("best-rank", "Best Rank", stats.BestRankText,
                link: stats.BestRankSongId is { } song && stats.BestRankInstrument is { } chart ? new PlayerStatLink.SongDetail(song, chart) : null),
        ];
        Instruments = [.. visible.Select(i => new PlayerInstrumentViewModel(session, AccountId, profile, i, catalogSize))];
        if (Bands?.AccountId != AccountId)
        {
            Bands?.Cancel();
            Bands = new PlayerProfileBandsViewModel(session, AccountId, DisplayName);
            _ = Bands.LoadAsync();
        }
        RefreshLinks();
    }

    /// <summary>Enables or pauses Songs links for the current identity state (plain tiles while selection is paused).</summary>
    private void RefreshLinks()
    {
        var songsAllowed = IsSelected || CanSelect;
        foreach (var tile in Overview) tile.LinkEnabled = tile.Link is not { RequiresSelection: true } || songsAllowed;
        foreach (var section in Instruments) section.SetSongsLinksEnabled(songsAllowed);
    }

    /// <summary>What the page must do before following a link (select first, confirm a switch, or blocked).</summary>
    /// <param name="link">Link.</param>
    /// <returns>Step.</returns>
    public PlayerLinkStep PlanLink(PlayerStatLink link) =>
        PlayerLinkPolicy.Plan(link, IsSelected, CanSelect, session.HasPlayer && !IsSelected);

    /// <summary>
    /// Follows a link after the page confirmed any switch: selects the shown player when needed, then applies a Songs
    /// preset to the saved Songs state (the caller shows Songs) or returns the route to push.
    /// </summary>
    /// <param name="link">Link.</param>
    /// <returns>Whether to navigate, and the route to push (<see langword="null"/> = show the Songs root).</returns>
    public (bool Followed, AppRoute? Route) FollowLink(PlayerStatLink link)
    {
        var step = PlanLink(link);
        if (step == PlayerLinkStep.Blocked) return (false, null);
        if (step is PlayerLinkStep.SelectThenGo or PlayerLinkStep.ConfirmSwitchThenGo)
        {
            Select();
            if (!IsSelected) return (false, null);
        }
        switch (link)
        {
            case PlayerStatLink.Songs songs:
                session.UpdateSettings(songs.Preset.ApplyTo);
                return (true, null);
            case PlayerStatLink.SongDetail detail:
                return (true, detail.Route);
            default:
                return (true, ((PlayerStatLink.FullRankings)link).Route);
        }
    }

    /// <summary>Raises every identity-derived property.</summary>
    private void RefreshIdentity()
    {
        foreach (var name in (string[])[nameof(IsSelected), nameof(DisplayName), nameof(IdentityAction),
                     nameof(CanSelect), nameof(CanDeselect), nameof(SelectNeedsConfirmation), nameof(SelectLabel),
                     nameof(IdentityNotice), nameof(HasIdentityNotice), nameof(SwitchMessage),
                     nameof(SyncingMessage)])
            OnPropertyChanged(name);
        if (Bands is { } section) section.PlayerName = DisplayName;
        RefreshLinks();
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
            case nameof(FestivalSession.ObservedPublicationId):
                // A newer publication makes a viewed read unselectable: swap Select for the "changed" notice now,
                // rather than only failing when Select is clicked.
                RefreshIdentity();
                break;
        }
    }
}

/// <summary>Value colour of a stat tile (web <c>StatBox</c> <c>color</c>).</summary>
public enum PlayerStatTint
{
    /// <summary>Accent blue (web <c>accentBlueBright</c>).</summary>
    Default,
    /// <summary>Gold (gold stars, 100% FCs, top-5% percentile).</summary>
    Gold,
    /// <summary>Green (every catalogue song played).</summary>
    Green,
}

/// <summary>
/// One stat tile (value over an uppercase label, web <c>StatBox</c>). Tiles keep their identity for the page's lifetime;
/// late values (global rank) update <see cref="Value"/> in place so the grid never re-creates or re-flows them.
/// </summary>
public sealed partial class PlayerStatTile : ObservableObject
{
    /// <summary>Creates a tile.</summary>
    /// <param name="key">Stable key, e.g. <c>songs-played</c>.</param>
    /// <param name="label">Label.</param>
    /// <param name="value">Value text.</param>
    /// <param name="tint">Value colour.</param>
    /// <param name="goldStars">Draw five gold star images instead of the value (average stars of exactly six).</param>
    /// <param name="link">Destination when clickable.</param>
    public PlayerStatTile(string key, string label, string value, PlayerStatTint tint = PlayerStatTint.Default,
        bool goldStars = false, PlayerStatLink? link = null)
    {
        Key = key;
        Label = label;
        this.value = value;
        this.tint = tint;
        GoldStars = goldStars;
        this.link = link;
    }

    /// <summary>Stable key within its grid.</summary>
    public string Key { get; }

    /// <summary>Grid scope for the automation ID: <c>overview</c> or the chart's service ID.</summary>
    public string Scope { get; set; } = "overview";

    /// <summary>Automation ID, <c>fst.player.stat.&lt;scope&gt;.&lt;key&gt;</c>.</summary>
    public string AutomationId => $"fst.player.stat.{Scope}.{Key}";

    /// <summary>Label.</summary>
    public string Label { get; }

    /// <summary>Draw five gold stars instead of the value.</summary>
    public bool GoldStars { get; }

    /// <summary>Whether the value text shows (not replaced by gold stars).</summary>
    public bool ShowValue => !GoldStars;

    /// <summary>Value text.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Announcement))]
    private string value;

    /// <summary>Value colour.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Gold))]
    private PlayerStatTint tint;

    /// <summary>Whether the value is a loading placeholder (drawn dimmed at its final size).</summary>
    [ObservableProperty]
    private bool isPending;

    /// <summary>Destination, or <see langword="null"/> for a plain tile.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLinked), nameof(Hint))]
    private PlayerStatLink? link;

    /// <summary>Whether the link may be followed now (a Songs preset pauses while selection is paused).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLinked), nameof(Hint))]
    private bool linkEnabled = true;

    /// <summary>Whether the tile is drawn as a button with a chevron.</summary>
    public bool IsLinked => Link is not null && LinkEnabled;

    /// <summary>Gold tint.</summary>
    public bool Gold => Tint == PlayerStatTint.Gold;

    /// <summary>Narrator help text naming the destination.</summary>
    public string Hint => IsLinked ? Link!.Hint : "";

    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}: {Value}";
}

/// <summary>One row of the percentile table (web <c>PlayerPercentileRow</c>): "Top N%" pill, song count, chevron.</summary>
/// <param name="bucket">Placement band.</param>
/// <param name="instrument">Chart.</param>
public sealed partial class PlayerPercentileRow(PlayerPercentileBucket bucket, Instrument instrument) : ObservableObject
{
    /// <summary>Band.</summary>
    public PlayerPercentileBucket Bucket { get; } = bucket;

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; } = instrument;

    /// <summary>Automation ID, <c>fst.player.percentile.&lt;Solo_…&gt;.&lt;top&gt;</c>.</summary>
    public string AutomationId => $"fst.player.percentile.{Instrument.ServiceId()}.{Bucket.TopPercent}";

    /// <summary>"Top 5%".</summary>
    public string Label => Bucket.Label;

    /// <summary>Count text.</summary>
    public string CountText => Bucket.Count.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary>Top-5% band: gold pill (web <c>goldOutline</c>).</summary>
    public bool Gold => Bucket.IsTopFive;

    /// <summary>Destination, or <see langword="null"/> while native Songs has no percentile filter.</summary>
    public PlayerStatLink? Link { get; init; }

    /// <summary>Whether the link may be followed now.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLinked))]
    private bool linkEnabled = true;

    /// <summary>Whether the row is clickable.</summary>
    public bool IsLinked => Link is not null && LinkEnabled;

    /// <summary>Screen-reader text.</summary>
    public string Announcement => $"{Label}: {CountText} {(Bucket.Count == 1 ? "song" : "songs")}";
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
    /// <param name="catalogSize">Catalogue song count (green Songs Played when complete), 0 when unknown.</param>
    public PlayerInstrumentViewModel(FestivalSession session, string accountId, PlayerProfileResponse profile, Instrument instrument, int catalogSize = 0)
    {
        this.session = session;
        this.accountId = accountId;
        Instrument = instrument;
        var stats = PlayerStatistics.ForInstrument(profile, instrument);
        HasScores = stats.SongsPlayed > 0;
        static string N(int n) => n.ToString("N0", CultureInfo.CurrentCulture);
        // Web InstrumentStatsSection order: played, FCs, star counts (non-zero), accuracy, avg stars, best rank, ranks.
        var tiles = new List<PlayerStatTile>
        {
            new("songs-played", "Songs Played", N(stats.SongsPlayed),
                catalogSize > 0 && stats.SongsPlayed >= catalogSize ? PlayerStatTint.Green : PlayerStatTint.Default,
                link: new PlayerStatLink.Songs(new SongsStatPreset(instrument, SongScoreFilterKind.HasScores))),
        };
        if (stats.FullComboCount > 0)
            tiles.Add(new("full-combos", "Full Combos", stats.FullComboText,
                stats.FullComboPercent >= 100 ? PlayerStatTint.Gold : PlayerStatTint.Default,
                link: new PlayerStatLink.Songs(new SongsStatPreset(instrument, SongScoreFilterKind.HasFCs))));
        foreach (var (stars, count) in PlayerStatistics.StarCounts(profile, instrument))
            if (count > 0)
                tiles.Add(new(stars == 6 ? "gold-stars" : $"stars-{stars}", SongScoreBandFilter.StarsLabel(stars), N(count),
                    stars == 6 ? PlayerStatTint.Gold : PlayerStatTint.Default,
                    link: new PlayerStatLink.Songs(new SongsStatPreset(instrument, null, Stars: stars))));
        tiles.Add(new("avg-accuracy", "Avg Accuracy", stats.AverageAccuracyText));
        tiles.Add(new("avg-stars", "Avg Stars", stats.AverageStarsText, goldStars: stats.AverageStarsGold));
        tiles.Add(new("best-rank", "Best Rank", stats.BestRankText,
            link: stats.BestRankSongId is { } song ? new PlayerStatLink.SongDetail(song, instrument) : null));
        // Global rank tiles hold their final place from the first frame (placeholders until the read lands).
        RankTiles =
        [
            new("global-rank", "Global Rank", "—", link: new PlayerStatLink.FullRankings(instrument)) { IsPending = true, LinkEnabled = false },
            new("total-score", "Total Score", "—") { IsPending = true },
            new("percentile", "Percentile", "—") { IsPending = true },
        ];
        if (HasScores) tiles.AddRange(RankTiles);
        foreach (var tile in tiles.Concat(RankTiles)) tile.Scope = instrument.ServiceId();
        Stats = tiles;
        Percentiles = [.. PlayerStatistics.PercentileBuckets(profile, instrument).Select(b => new PlayerPercentileRow(b, instrument)
        {
            Link = new PlayerStatLink.Songs(new SongsStatPreset(instrument, null, TopPercent: b.TopPercent)),
        })];
    }

    /// <summary>Pauses or resumes Songs links (selection paused on a viewed profile).</summary>
    /// <param name="enabled">Whether Songs presets may be followed.</param>
    internal void SetSongsLinksEnabled(bool enabled)
    {
        foreach (var tile in Stats)
            if (tile.Link is { RequiresSelection: true }) tile.LinkEnabled = enabled;
        foreach (var row in Percentiles)
            if (row.Link is { RequiresSelection: true }) row.LinkEnabled = enabled;
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

    /// <summary>Stat tiles, including the three global-rank tiles when the chart has scores.</summary>
    public List<PlayerStatTile> Stats { get; }

    /// <summary>The Global Rank, Total Score and Percentile tiles (updated in place).</summary>
    public List<PlayerStatTile> RankTiles { get; }

    /// <summary>Percentile table rows, best band first.</summary>
    public List<PlayerPercentileRow> Percentiles { get; }

    /// <summary>Whether the percentile card has bars.</summary>
    public bool HasPercentiles => Percentiles.Count > 0;

    /// <summary>Global-rank state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(RankLoading), nameof(RankUnranked), nameof(RankAvailable), nameof(RankFailed))]
    private PlayerRankLoad rankState = PlayerRankLoad.Loading;

    /// <summary>Global-rank failure text.</summary>
    [ObservableProperty]
    private string rankError = "";

    /// <summary>Rank-history chart, or <see langword="null"/> while loading, failed or without snapshots.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasRankHistory), nameof(ShowRankHistoryCard))]
    private RankHistoryChartModel? rankHistory;

    /// <summary>Rank-history failure text, or empty.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(RankHistoryFailed), nameof(ShowRankHistoryCard))]
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

    /// <summary>Whether the Rank History card shows its fixed-height placeholder (read not finished yet).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowRankHistoryCard))]
    private bool rankHistoryLoading = true;

    /// <summary>Whether the Rank History card is shown at all: while loading, with a chart, or with a retry.</summary>
    public bool ShowRankHistoryCard => HasScores && (RankHistoryLoading || HasRankHistory || RankHistoryFailed);

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
        foreach (var tile in RankTiles) tile.IsPending = true;
        RankState = PlayerRankLoad.Loading;
        try
        {
            var read = await session.Api.GetPlayerInstrumentRankingAsync(Instrument, accountId, token);
            if (token.IsCancellationRequested) return;
            if (read.Ranking is not { } ranking)
            {
                SetRankTiles("Unranked", "—", "—", false, linked: false);
                RankState = PlayerRankLoad.Unranked;
                return;
            }
            SetRankTiles(ranking.RankText, ranking.TotalScoreText, ranking.PercentileText, ranking.IsTopFive, linked: true);
            // Global Rank opens the rankings on the player's own page (orchestrator follow-up; web ?page=).
            RankTiles[0].Link = new PlayerStatLink.FullRankings(Instrument, ranking.TotalScoreRank);
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
            SetRankTiles("—", "—", "—", false, linked: false);
            RankState = PlayerRankLoad.Failed;
        }
    }

    /// <summary>Updates the rank tiles in place.</summary>
    /// <param name="rank">Global Rank value.</param>
    /// <param name="total">Total Score value.</param>
    /// <param name="percentile">Percentile value.</param>
    /// <param name="gold">Top-5% percentile.</param>
    /// <param name="linked">Whether Global Rank opens the full rankings.</param>
    private void SetRankTiles(string rank, string total, string percentile, bool gold, bool linked)
    {
        RankTiles[0].Value = rank;
        RankTiles[0].LinkEnabled = linked;
        RankTiles[1].Value = total;
        RankTiles[2].Value = percentile;
        RankTiles[2].Tint = gold ? PlayerStatTint.Gold : PlayerStatTint.Default;
        foreach (var tile in RankTiles) tile.IsPending = false;
    }

    /// <summary>Reads the 30-day rank history.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadRankHistoryAsync()
    {
        historyLoad?.Cancel();
        var token = (historyLoad = new CancellationTokenSource()).Token;
        RankHistoryError = "";
        RankHistoryLoading = true;
        try
        {
            var history = await session.Api.GetPlayerRankHistoryAsync(Instrument, accountId, 30, token);
            if (token.IsCancellationRequested) return;
            RankHistory = RankHistoryChartModel.Build(history.RankedChronological);
            RankHistoryLoading = false;
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
            RankHistoryLoading = false;
        }
    }
}
#endregion
