using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Account row
/// <summary>
/// One account-rankings row shared by overview cards, their spotlight and Full Rankings. Opens the viewed
/// player's profile (web row link to <c>/player/:accountId</c>).
/// </summary>
public sealed class RankingRowViewModel
{
    /// <summary>Creates a row.</summary>
    /// <param name="entry">Wire row.</param>
    /// <param name="metric">Displayed metric.</param>
    /// <param name="isSelected">Whether this is the selected player's row (accent treatment and "Your rank" label).</param>
    public RankingRowViewModel(AccountRankingEntry entry, RankingMetric metric, bool isSelected)
    {
        Entry = entry;
        Metric = metric;
        IsSelected = isSelected;
        var bayesian = entry.BayesianValue(metric);
        BayesianText = bayesian is { } value ? RankingFormatting.Bayesian(value) : "";
    }

    /// <summary>Wire row.</summary>
    public AccountRankingEntry Entry { get; }

    /// <summary>Displayed metric.</summary>
    public RankingMetric Metric { get; }

    /// <summary>Whether this is the selected player's row.</summary>
    public bool IsSelected { get; }

    /// <summary>Rank for the metric.</summary>
    public int Rank => Entry.Rank(Metric);

    /// <summary><c>#1,234</c>.</summary>
    public string RankText => ScoreFormatting.Rank(Rank);

    /// <summary>Display name.</summary>
    public string Name => Entry.Name;

    /// <summary>"X / Y" (songs, or full combos under FC Rate).</summary>
    public string SongsText => Entry.SongsLabel(Metric);

    /// <summary>Primary rating.</summary>
    public string RatingText => RankingFormatting.Rating(Entry.RatingValue(Metric), Metric);

    /// <summary>Bayesian rating beside a percentile, or empty.</summary>
    public string BayesianText { get; }

    /// <summary>Whether <see cref="BayesianText"/> is shown.</summary>
    public bool HasBayesian => BayesianText.Length > 0;

    /// <summary>Profile destination, or <see langword="null"/> for a row without a usable account ID.</summary>
    public AppRoute? Route => Entry.HasProfile ? new AppRoute.Player(Entry.AccountId, Entry.DisplayName) : null;

    /// <summary>UIA automation ID (<c>fst.rankings.row.&lt;accountId&gt;</c>, or <c>…row.rank-&lt;n&gt;</c> without an ID).</summary>
    public string AutomationId => "fst.rankings.row." + (Entry.HasProfile ? Entry.AccountId : "rank-" + Rank);

    /// <summary>Screen-reader name; the selected row leads with "Your rank, 12th." like Apple's VoiceOver label.</summary>
    public string Announcement => (IsSelected ? $"Your rank, {RankingFormatting.Ordinal(Rank)}. {Name}." : $"Rank {RankText}, {Name}.") +
                                  $" {Metric.Label()} {RatingText}{(HasBayesian ? $" ({BayesianText})" : "")}, {SongsText} songs";
}
#endregion

#region Band row
/// <summary>One band-rankings row. Opens Band Detail with the type and team key so it can use the safe rankings read.</summary>
public sealed class BandRankingRowViewModel
{
    /// <summary>Creates a row.</summary>
    /// <param name="entry">Wire row.</param>
    /// <param name="bandType">Board's band size.</param>
    /// <param name="metric">Displayed band metric.</param>
    public BandRankingRowViewModel(BandRankingEntry entry, BandType bandType, BandRankingMetric metric)
    {
        Entry = entry;
        BandType = bandType;
        Metric = metric;
        var bayesian = entry.BayesianValue(metric);
        BayesianText = bayesian is { } value ? RankingFormatting.Bayesian(value) : "";
    }

    /// <summary>Wire row.</summary>
    public BandRankingEntry Entry { get; }

    /// <summary>Board's band size.</summary>
    public BandType BandType { get; }

    /// <summary>Displayed metric.</summary>
    public BandRankingMetric Metric { get; }

    /// <summary><c>#12</c>.</summary>
    public string RankText => ScoreFormatting.Rank(Entry.Rank(Metric));

    /// <summary>Member roster.</summary>
    public string Name => Entry.MembersLabel;

    /// <summary>"X / Y" (songs, or full combos under FC Rate).</summary>
    public string SongsText => Entry.SongsLabel(Metric);

    /// <summary>Primary rating.</summary>
    public string RatingText => RankingFormatting.Rating(Entry.RatingValue(Metric), Metric.ToRankingMetric());

    /// <summary>Bayesian rating, or empty.</summary>
    public string BayesianText { get; }

    /// <summary>Whether <see cref="BayesianText"/> is shown.</summary>
    public bool HasBayesian => BayesianText.Length > 0;

    /// <summary>Band Detail route (never the side-effecting <c>/api/bands/{id}</c> lookup), or <see langword="null"/> without identity.</summary>
    public AppRoute? Route => Entry.HasDetail ? new AppRoute.Band(Entry.BandId, BandType.ServiceId(), Entry.TeamKey) : null;

    /// <summary>UIA automation ID (<c>fst.band-rankings.row.&lt;teamKey&gt;</c>).</summary>
    public string AutomationId => "fst.band-rankings.row." + Entry.TeamKey;

    /// <summary>Screen-reader name.</summary>
    public string Announcement => $"Rank {RankText}, {Name}. {Metric.Label()} {RatingText}{(HasBayesian ? $" ({BayesianText})" : "")}, {SongsText} songs";
}
#endregion

#region Spotlight
/// <summary>
/// Reads the selected player's own row on one instrument board (<c>GET /api/rankings/{instrument}/{accountId}</c>).
/// Returns <see langword="null"/> when the account is unranked (404).
/// </summary>
/// <param name="instrument">Board.</param>
/// <param name="accountId">Selected player.</param>
/// <param name="cancellationToken">Cancellation.</param>
/// <returns>The row, or <see langword="null"/> when unranked.</returns>
public delegate Task<AccountRankingEntry?> OwnRankingReader(Instrument instrument, string accountId, CancellationToken cancellationToken);

/// <summary>
/// The selected player's spotlight on one board: highlighted in place, loading, failed (inline retry),
/// unranked, or a separate "your rank" row with an optional jump to its page.
/// </summary>
public sealed partial class RankingSpotlightViewModel : ObservableObject
{
    private readonly OwnRankingReader? reader;
    private readonly Instrument instrument;
    private readonly Func<int, Task>? jump;
    private string? loadedFor;
    private bool ownLoaded;
    private AccountRankingEntry? own;
    private string? selected;
    private IReadOnlyList<AccountRankingEntry> visible = [];
    private RankingMetric metric;
    private int pageSize = LeaderboardPaging.PageSize;
    private int currentPage = 1;

    /// <summary>Creates the spotlight for one board.</summary>
    /// <param name="instrument">Board.</param>
    /// <param name="reader">Own-row reader; <see langword="null"/> keeps the spotlight pending.</param>
    /// <param name="time">Clock for the inline status.</param>
    /// <param name="scope">Backoff scope.</param>
    /// <param name="jump">Page change for "Jump to your page" (Full Rankings only).</param>
    public RankingSpotlightViewModel(Instrument instrument, OwnRankingReader? reader, TimeProvider time, string scope, Func<int, Task>? jump = null)
    {
        this.instrument = instrument;
        this.reader = reader;
        this.jump = jump;
        Status = new ServiceStatusViewModel(scope, "Your rank unavailable", RetryAsync, time);
    }

    /// <summary>Inline failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Current placement.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowLoading), nameof(ShowFailed), nameof(ShowUnranked), nameof(ShowRow), nameof(IsVisible))]
    private SpotlightPlacementKind kind;

    /// <summary>Whether the own-row read failed.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowLoading), nameof(ShowFailed))]
    private bool failed;

    /// <summary>Spotlight row (footer placement).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanJump))]
    [NotifyCanExecuteChangedFor(nameof(JumpCommand))]
    private RankingRowViewModel? row;

    /// <summary>Whether anything below the board is shown.</summary>
    public bool IsVisible => Kind is SpotlightPlacementKind.Pending or SpotlightPlacementKind.Unranked or SpotlightPlacementKind.Footer;

    /// <summary>"Loading your rank…".</summary>
    public bool ShowLoading => Kind == SpotlightPlacementKind.Pending && !Failed;

    /// <summary>Inline failure with Retry.</summary>
    public bool ShowFailed => Kind == SpotlightPlacementKind.Pending && Failed;

    /// <summary>"Not yet ranked".</summary>
    public bool ShowUnranked => Kind == SpotlightPlacementKind.Unranked;

    /// <summary>Separate "your rank" row.</summary>
    public bool ShowRow => Kind == SpotlightPlacementKind.Footer;

    /// <summary>Unranked text.</summary>
    public string UnrankedText => $"Not yet ranked on {instrument.Label()}.";

    /// <summary>Whether "Jump to your page" applies (Full Rankings, row on another page).</summary>
    public bool CanJump => jump is not null && Row is not null &&
                           LeaderboardPaging.PageForRank(Row.Rank, pageSize) != currentPage;

    /// <summary>Loads the own row once per account (skipped when <paramref name="needed"/> is false).</summary>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <param name="needed">Whether the row is off the visible rows (the web always reads; natives skip when visible).</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Load task.</returns>
    public async Task EnsureLoadedAsync(string? accountId, bool needed, CancellationToken cancellationToken = default)
    {
        if (accountId is null || !needed || reader is null) return;
        if (loadedFor is not null && RankingSpotlight.SameAccount(loadedFor, accountId) && (ownLoaded || !Failed)) return;
        loadedFor = accountId;
        ownLoaded = false;
        own = null;
        Failed = false;
        Status.Clear();
        Recompute();
        try
        {
            var result = await reader(instrument, accountId, cancellationToken);
            if (!RankingSpotlight.SameAccount(loadedFor, accountId)) return;
            own = result;
            ownLoaded = true;
        }
        catch (OperationCanceledException)
        {
            loadedFor = null;
            return;
        }
        catch (FestivalApiException error)
        {
            Failed = true;
            Status.Report(error);
        }
        Recompute();
    }

    /// <summary>Re-evaluates placement for the board's current rows.</summary>
    /// <param name="selectedAccountId">Selected player.</param>
    /// <param name="visibleEntries">Visible rows.</param>
    /// <param name="displayMetric">Displayed metric.</param>
    /// <param name="page">Current page (for the jump).</param>
    /// <param name="rowsPerPage">Page size (for the jump).</param>
    public void Apply(string? selectedAccountId, IReadOnlyList<AccountRankingEntry> visibleEntries, RankingMetric displayMetric,
        int page = 1, int rowsPerPage = LeaderboardPaging.PageSize)
    {
        if (!RankingSpotlight.SameAccount(selectedAccountId, loadedFor))
        {
            loadedFor = null;
            ownLoaded = false;
            own = null;
            Failed = false;
        }
        selected = selectedAccountId;
        visible = visibleEntries;
        metric = displayMetric;
        currentPage = page;
        pageSize = rowsPerPage;
        Recompute();
    }

    /// <summary>Moves the owning board to the selected player's page.</summary>
    /// <returns>Page change task.</returns>
    [RelayCommand(CanExecute = nameof(CanJump))]
    private Task JumpAsync() => CanJump ? jump!(LeaderboardPaging.PageForRank(Row!.Rank, pageSize)) : Task.CompletedTask;

    /// <summary>Retries the own-row read.</summary>
    /// <returns>Load task.</returns>
    private Task RetryAsync()
    {
        var account = loadedFor ?? selected;
        loadedFor = null;
        Failed = false;
        return EnsureLoadedAsync(account, true);
    }

    /// <summary>Applies <see cref="RankingSpotlight.Place"/>.</summary>
    private void Recompute()
    {
        var placement = RankingSpotlight.Place(selected, visible, ownLoaded, own);
        Row = placement.Entry is { } entry ? new RankingRowViewModel(entry, metric, true) : null;
        Kind = placement.Kind;
        OnPropertyChanged(nameof(CanJump));
        JumpCommand.NotifyCanExecuteChanged();
    }
}
#endregion

#region Pager
/// <summary>First/Previous/"page / total"/Next/Last control shared by every paginated board.</summary>
/// <param name="idPrefix">Automation ID prefix, e.g. <c>fst.full-rankings</c>.</param>
/// <param name="move">Page change.</param>
public sealed partial class RankingsPagerViewModel(string idPrefix, Func<int, Task> move) : ObservableObject
{
    /// <summary>Automation ID prefix.</summary>
    public string IdPrefix { get; } = idPrefix;

    /// <summary>Current page.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(InfoText), nameof(InfoAnnouncement), nameof(CanGoBack), nameof(CanGoForward))]
    [NotifyCanExecuteChangedFor(nameof(FirstCommand), nameof(PreviousCommand), nameof(NextCommand), nameof(LastCommand))]
    private int page = 1;

    /// <summary>Page count.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(InfoText), nameof(InfoAnnouncement), nameof(CanGoBack), nameof(CanGoForward), nameof(IsPaged))]
    [NotifyCanExecuteChangedFor(nameof(FirstCommand), nameof(PreviousCommand), nameof(NextCommand), nameof(LastCommand))]
    private int totalPages = 1;

    /// <summary>"3 / 120" with grouping.</summary>
    public string InfoText => $"{Page:N0} / {TotalPages:N0}";

    /// <summary>Spoken page position.</summary>
    public string InfoAnnouncement => $"Page {Page:N0} of {TotalPages:N0}";

    /// <summary>Whether First/Previous are enabled.</summary>
    public bool CanGoBack => Page > 1;

    /// <summary>Whether Next/Last are enabled.</summary>
    public bool CanGoForward => Page < TotalPages;

    /// <summary>Whether there is more than one page.</summary>
    public bool IsPaged => TotalPages > 1;

    /// <summary>Updates both values.</summary>
    /// <param name="current">Current page.</param>
    /// <param name="total">Page count.</param>
    public void Update(int current, int total)
    {
        TotalPages = Math.Max(1, total);
        Page = Math.Clamp(current, 1, TotalPages);
    }

    /// <summary>Page 1.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoBack))]
    private Task FirstAsync() => move(1);

    /// <summary>Previous page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoBack))]
    private Task PreviousAsync() => move(Page - 1);

    /// <summary>Next page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward))]
    private Task NextAsync() => move(Page + 1);

    /// <summary>Last page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward))]
    private Task LastAsync() => move(TotalPages);
}
#endregion
