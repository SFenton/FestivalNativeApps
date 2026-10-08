using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Account row
/// <summary>
/// One account-rankings row shared by overview cards, their spotlight and Full Rankings. Opens the viewed
/// player's profile (web row link to <c>/player/:accountId</c>).
/// </summary>
public sealed partial class RankingRowViewModel : ObservableObject, ILeaderboardRankingRow
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

    /// <summary>
    /// Content of this board's rows and its pinned selected-player row (web <c>computeRankWidth</c> and the rating
    /// minimum), so ranks, names, songs labels and ratings line up down the card (operator batch 7.9, issue #37).
    /// Observable because the pinned row can arrive after the board.
    /// </summary>
    [ObservableProperty]
    private LeaderboardSection? section;

    /// <summary>Gives a board's rows and its pinned row one set of columns, measured over all of them.</summary>
    /// <param name="rows">Board rows.</param>
    /// <param name="pinned">Pinned selected-player row, if shown.</param>
    public static void ShareColumns(IReadOnlyList<RankingRowViewModel> rows, RankingRowViewModel? pinned)
    {
        var shared = LeaderboardColumns.Measure(pinned is null ? rows : [.. rows, pinned]);
        foreach (var row in rows) row.Section = shared;
        if (pinned is not null) pinned.Section = shared;
    }

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

    /// <summary>
    /// Destination: <see cref="JumpRoute"/> when set (a card's "your rank" row), else the profile; <see langword="null"/>
    /// for a row without a usable account ID.
    /// </summary>
    public AppRoute? Route => (AppRoute?)JumpRoute ?? (Entry.HasProfile ? new AppRoute.Player(Entry.AccountId, Entry.DisplayName) : null);

    /// <summary>
    /// Full board at the selected player's page, revealing their row (a Leaderboards card's "your rank" row, pattern
    /// <c>leaderboard-row</c> R7, issue #370); <see langword="null"/> for every other row.
    /// </summary>
    public AppRoute.FullRankings? JumpRoute { get; init; }

    /// <summary>UIA automation ID (<c>fst.rankings.row.&lt;accountId&gt;</c>, or <c>…row.rank-&lt;n&gt;</c> without an ID).</summary>
    public string AutomationId => "fst.rankings.row." + (Entry.HasProfile ? Entry.AccountId : "rank-" + Rank);

    /// <summary>
    /// For the selected player's separate row only (pattern <c>leaderboard-row</c> R7): on Full Rankings' pinned footer,
    /// jump to the player's page or open their profile (issue #318; the view runs the jump through the spotlight's command
    /// and the open through <see cref="Route"/>); on a Leaderboards card, open the full board at their page
    /// (<see cref="JumpRoute"/>, issue #370).
    /// </summary>
    public SelectedRowAction? PinnedAction { get; init; }

    /// <summary>
    /// Screen-reader name; the selected row leads with "Your rank, 12th." like Apple's VoiceOver label, and a pinned row
    /// then names its destination ("Jump to your position." / "Open your statistics.").
    /// </summary>
    public string Announcement => (IsSelected ? $"Your rank, {RankingFormatting.Ordinal(Rank)}. " : $"Rank {RankText}, ") +
                                  (PinnedAction is { } action ? $"{action.Destination(SelectedRowSubject.Player)}. " : "") +
                                  $"{Name}. {Metric.Label()} {RatingText}{(HasBayesian ? $" ({BayesianText})" : "")}, {SongsText} songs";
}
#endregion

#region Band row
/// <summary>One band-rankings row. Opens Band Detail with the type and team key so it can use the safe rankings read.</summary>
public sealed class BandRankingRowViewModel : ILeaderboardRankingRow
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

    /// <summary>Band rows are never the selected player's own row.</summary>
    public bool IsSelected => false;

    /// <inheritdoc />
    public LeaderboardSection? Section { get; set; }

    /// <summary>Gives a board's rows one set of columns, measured over all of them (issue #37).</summary>
    /// <param name="rows">Board rows.</param>
    public static void ShareColumns(IReadOnlyList<BandRankingRowViewModel> rows)
    {
        var shared = LeaderboardColumns.Measure(rows);
        foreach (var row in rows) row.Section = shared;
    }

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
/// unranked, or a separate "your rank" row. A pinned spotlight (Full Rankings) never
/// goes inline: the row stays above the pager on every page and is itself the control, jumping to the player's page while it is elsewhere and opening their profile once it is shown (pattern <c>leaderboard-row</c> R7, issue #318).
/// An overview card's separate row opens Full Rankings at the player's page and reveals their row (issue #370).
/// </summary>
public sealed partial class RankingSpotlightViewModel : ObservableObject
{
    private readonly OwnRankingReader? reader;
    private readonly Instrument instrument;
    private readonly Func<int, Task>? jump;
    private readonly bool pinned;
    private readonly bool opensFullBoard;
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
    /// <param name="jump">Page change run by the pinned row while the player's row is on another page (Full Rankings only).</param>
    /// <param name="pinned">
    /// Whether the row is pinned on every page, the player's own page included (<see cref="RankingSpotlight.PlacePinned"/>,
    /// Full Rankings); otherwise a visible player is only highlighted in place (<see cref="RankingSpotlight.Place"/>, overview cards).
    /// </param>
    /// <param name="opensFullBoard">
    /// Whether the separate row of an overview card opens the full board at the player's page and reveals their row
    /// (<see cref="SelectedRowAction.Preview"/>, pattern <c>leaderboard-row</c> R7, issue #370) instead of their profile.
    /// </param>
    public RankingSpotlightViewModel(Instrument instrument, OwnRankingReader? reader, TimeProvider time, string scope, Func<int, Task>? jump = null,
        bool pinned = false, bool opensFullBoard = false)
    {
        this.instrument = instrument;
        this.reader = reader;
        this.jump = jump;
        this.pinned = pinned;
        this.opensFullBoard = opensFullBoard;
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

    /// <summary>
    /// Placeholder under the loading ring, fitted to the board's columns so the loading row is as tall as the pinned row
    /// that replaces it (issue #281); <see langword="null"/> until the spotlight first waits.
    /// </summary>
    [ObservableProperty]
    private LeaderboardSkeletonRow? loadingRow;

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

    /// <summary>
    /// Whether activating the pinned row jumps to the player's page (Full Rankings, row on another page) rather than opening
    /// their profile (pattern <c>leaderboard-row</c> R7, issue #318; <see cref="SelectedRowAction.Footer"/>).
    /// </summary>
    public bool CanJump => jump is not null && Row?.PinnedAction is { Jumps: true };

    /// <summary>Loads the own row once per account (skipped when <paramref name="needed"/> is false).</summary>
    /// <param name="accountId">Selected player, or <see langword="null"/>.</param>
    /// <param name="needed">Whether the row is needed: off the visible rows, or always for a pinned board (the web always reads).</param>
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

    /// <summary>Pinned row: moves the owning board to the selected player's page (the view then reveals their row).</summary>
    /// <returns>Page change task.</returns>
    [RelayCommand(CanExecute = nameof(CanJump))]
    private Task JumpAsync() =>
        jump is not null && Row?.PinnedAction?.JumpPage is { } page ? jump(page) : Task.CompletedTask;

    /// <summary>Retries the own-row read.</summary>
    /// <returns>Load task.</returns>
    private Task RetryAsync()
    {
        var account = loadedFor ?? selected;
        loadedFor = null;
        Failed = false;
        return EnsureLoadedAsync(account, true);
    }

    /// <summary>Applies <see cref="RankingSpotlight.Place"/> (or <see cref="RankingSpotlight.PlacePinned"/> when pinned).</summary>
    private void Recompute()
    {
        var placement = pinned
            ? RankingSpotlight.PlacePinned(selected, visible, ownLoaded, own)
            : RankingSpotlight.Place(selected, visible, ownLoaded, own);
        Row = placement.Entry is { } entry ? SelectedRow(entry) : null;
        // The loading row fits the board's columns like the row it stands in for (issue #281), so the pinned row
        // doesn't jump in when it arrives at large text or under a percentile metric.
        if (placement.Kind == SpotlightPlacementKind.Pending)
            LoadingRow = new LeaderboardSkeletonRow(
                visible.Count == 0
                    ? LeaderboardRowMetrics.SkeletonSection(metric)
                    : LeaderboardColumns.Measure(visible.Select(e => new RankingRowViewModel(e, metric, false)).ToList()) with { HasRoutes = true },
                metric.IsPercentile(), "", showBars: false);
        Kind = placement.Kind;
        OnPropertyChanged(nameof(CanJump));
        JumpCommand.NotifyCanExecuteChanged();
    }

    /// <summary>
    /// The selected player's separate row and its action (pattern <c>leaderboard-row</c> R7): on Full Rankings it jumps
    /// in place or opens the profile (#318); on an overview card that opens the full board, a ranked row opens Full
    /// Rankings at the page containing its rank and reveals it (#370, as Song Detail's appended row); otherwise it opens
    /// the profile.
    /// </summary>
    /// <param name="entry">Selected player's entry.</param>
    /// <returns>Row.</returns>
    private RankingRowViewModel SelectedRow(AccountRankingEntry entry)
    {
        if (jump is not null) return new RankingRowViewModel(entry, metric, true) { PinnedAction = PinnedAction(entry) };
        if (opensFullBoard && SelectedRowAction.Preview(entry.Rank(metric), isAppended: true) is { JumpPage: { } page } action)
            return new RankingRowViewModel(entry, metric, true)
            {
                PinnedAction = action,
                JumpRoute = new AppRoute.FullRankings(instrument, metric.ServiceId(), page, RevealSelected: true),
            };
        return new RankingRowViewModel(entry, metric, true);
    }

    /// <summary>The pinned row's action: jump unless the shown page holds (or should hold) the selected player's row.</summary>
    /// <param name="entry">Selected player's entry.</param>
    /// <returns>Shared selected-row action.</returns>
    private SelectedRowAction PinnedAction(AccountRankingEntry entry)
    {
        var rank = entry.Rank(metric);
        return SelectedRowAction.Footer(rank,
            LeaderboardPaging.PageForRank(rank, pageSize) == currentPage ||
            visible.Any(e => RankingSpotlight.SameAccount(e.AccountId, entry.AccountId)), pageSize);
    }
}
#endregion

#region Pager
/// <summary>
/// First/Previous/"page / total"/Next/Last control shared by every paginated board. The commands stay enabled while a
/// page loads (only the page bounds disable them): a running async command reports CanExecute false, which disabled the
/// focused button and made the pager hand keyboard focus to another (Enter on Next then jumped to the last page, issue
/// #197). Boards drop superseded loads, so a second press during a load is safe.
/// </summary>
/// <param name="idPrefix">Automation ID prefix, e.g. <c>fst.full-rankings</c>.</param>
/// <param name="move">Page change.</param>
public sealed partial class RankingsPagerViewModel(string idPrefix, Func<int, Task> move) : ObservableObject, IBoardPager
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
    [RelayCommand(CanExecute = nameof(CanGoBack), AllowConcurrentExecutions = true)]
    private Task FirstAsync() => move(1);

    /// <summary>Previous page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoBack), AllowConcurrentExecutions = true)]
    private Task PreviousAsync() => move(Page - 1);

    /// <summary>Next page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward), AllowConcurrentExecutions = true)]
    private Task NextAsync() => move(Page + 1);

    /// <summary>Last page.</summary>
    /// <returns>Move task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward), AllowConcurrentExecutions = true)]
    private Task LastAsync() => move(TotalPages);

    ICommand IBoardPager.FirstCommand => FirstCommand;

    ICommand IBoardPager.PreviousCommand => PreviousCommand;

    ICommand IBoardPager.NextCommand => NextCommand;

    ICommand IBoardPager.LastCommand => LastCommand;
}
#endregion
