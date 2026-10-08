using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Song score history
/// <summary>What the Song Detail score-history section shows.</summary>
public enum SongScoreHistoryPhase
{
    /// <summary>Nothing: no player, not registered, or no rows (web hides the card).</summary>
    Hidden,
    /// <summary>HTTP 202: the player's history is still being prepared (paused, never "no history").</summary>
    Syncing,
    /// <summary>Read failed; see <see cref="SongScoreHistoryViewModel.Status"/>.</summary>
    Failed,
    /// <summary>Chart and list.</summary>
    Loaded,
}

/// <summary>
/// The selected player's score history on Song Detail (web <c>ScoreHistoryChart</c> in <c>GraphCard</c>): an instrument
/// selector over the charts with history, a paged accuracy-bar + score-line chart whose bars select a detail row, the top
/// five scores by score and "View All Scores", which opens the selected chart's sortable Player History page
/// (<c>/songs/:id/:instrument/history</c>; view-all-cta R8, issue #324). One read per song:
/// <c>GET /api/player/{id}/history?songId=</c>.
/// </summary>
public sealed partial class SongScoreHistoryViewModel : ObservableObject
{
    private readonly FestivalSession? session;
    private List<ScoreHistoryEntry> entries = [];
    private Dictionary<Instrument, int> counts = [];
    private Song? song;
    private IReadOnlyList<Instrument> pool = [];

    /// <summary>Creates the section.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="songId">Song.</param>
    /// <param name="requested">Chart to show first (route instrument), if any.</param>
    public SongScoreHistoryViewModel(FestivalSession session, string songId, Instrument? requested)
        : this(session, songId, requested, session.Time)
    {
    }

    /// <summary>Creates the section, optionally without a session (<see cref="Demo"/>: never reads).</summary>
    /// <param name="session">Shared session, or null for fixed plays.</param>
    /// <param name="songId">Song.</param>
    /// <param name="requested">Chart to show first.</param>
    /// <param name="time">Clock for the status presenter.</param>
    private SongScoreHistoryViewModel(FestivalSession? session, string songId, Instrument? requested, TimeProvider time)
    {
        this.session = session;
        SongId = songId;
        Requested = requested;
        Status = new ServiceStatusViewModel("song-history", "Score history unavailable", () => LoadAsync(song, pool), time);
    }

    /// <summary>
    /// A loaded section over fixed plays that never reads the service: the First Run guide hosts the real
    /// <c>SongScoreHistoryChart</c> over it (issue #380), so the guide always shows the production chart.
    /// </summary>
    /// <param name="songId">Song the plays belong to.</param>
    /// <param name="chart">The only chart (the plays' instrument).</param>
    /// <param name="plays">Plays for <paramref name="chart"/>.</param>
    /// <param name="time">Clock for the status presenter.</param>
    /// <returns>Loaded model with no bar selected.</returns>
    public static SongScoreHistoryViewModel Demo(string songId, Instrument chart, IEnumerable<ScoreHistoryEntry> plays, TimeProvider time)
    {
        var model = new SongScoreHistoryViewModel(null, songId, chart, time) { pool = [chart] };
        model.Show(SongScoreHistoryPhase.Loaded, [.. plays]);
        return model;
    }

    /// <summary>Song.</summary>
    public string SongId { get; }

    /// <summary>Chart requested by the route.</summary>
    public Instrument? Requested { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Section title (web <c>chart.scoreHistory</c>).</summary>
    public string Title => "Score History";

    /// <summary>Card subtitle (web <c>chart.selectBarHint</c>).</summary>
    public string Subtitle => "Select a bar to see more score details.";

    /// <summary>"View All Scores" (web <c>chart.viewAllScores</c>, Title Case per the capitalization rule).</summary>
    public string ViewAllText => ViewAllCta.ScoresLabel;

    /// <summary>UIA name of View All Scores: the visible label, then the selected chart (<see cref="ViewAllCta.Name"/>),
    /// e.g. "View All Scores, Lead".</summary>
    public string ViewAllName => ViewAllCta.Name(ViewAllText, Selected is { } chart ? chart.Label() : Title);

    /// <summary>UI Automation ID of View All Scores (unchanged <c>fst.history.*</c> family).</summary>
    public string ViewAllAutomationId => "fst.history.view-all";

    /// <summary>Phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsVisible), nameof(ShowChart), nameof(ShowSyncing), nameof(ShowError))]
    private SongScoreHistoryPhase phase = SongScoreHistoryPhase.Hidden;

    /// <summary>Whether the section renders at all.</summary>
    public bool IsVisible => Phase != SongScoreHistoryPhase.Hidden;

    /// <summary>Chart and list.</summary>
    public bool ShowChart => Phase == SongScoreHistoryPhase.Loaded;

    /// <summary>Syncing message with Retry.</summary>
    public bool ShowSyncing => Phase == SongScoreHistoryPhase.Syncing;

    /// <summary>Inline service status.</summary>
    public bool ShowError => Phase == SongScoreHistoryPhase.Failed;

    /// <summary>Charts with history, in display order (the selector's instruments).</summary>
    [ObservableProperty]
    private List<Instrument> instruments = [];

    /// <summary>Selected chart.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(EmptyMessage), nameof(ViewAllName), nameof(ViewAllRoute))]
    private Instrument? selected;

    /// <summary>The selected chart's points, oldest first.</summary>
    [ObservableProperty]
    private List<ScoreHistoryPoint> points = [];

    /// <summary>Bar paging and selection.</summary>
    public ScoreHistoryPager Pager { get; } = new();

    /// <summary>Bars on the current page.</summary>
    [ObservableProperty]
    private List<ScoreHistoryBar> bars = [];

    /// <summary>Detail row for the selected bar.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasSelectedPoint), nameof(ShowDetailSlot))]
    private ScoreHistoryListRow? selectedRow;

    /// <summary>Whether a bar is selected.</summary>
    public bool HasSelectedPoint => SelectedRow is not null;

    /// <summary>
    /// Whether the detail row's space stays reserved (empty) because a chart switch closed an open detail row, so the card
    /// keeps its height on the new chart (issue #261). It ends when the player picks or clears a bar, or the history reloads.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowDetailSlot))]
    private bool reservesDetail;

    /// <summary>Whether the detail row's slot is laid out: a bar is selected, or a chart switch reserved its space.</summary>
    public bool ShowDetailSlot => HasSelectedPoint || ReservesDetail;

    /// <summary>Whether paging arrows show.</summary>
    public bool ShowPaging => Pager.NeedsPagination;

    /// <summary>
    /// Whether the pager row keeps its space: while paging, or whenever another selectable chart pages, so the card keeps
    /// its size when the chart changes (issue #61). The row is empty (and absent for Narrator) when this chart doesn't page.
    /// </summary>
    public bool ShowPagerSlot => ShowPaging || ScoreHistorySwap.ReservesPager(counts, Instruments, Pager.MaxBars);

    /// <summary>Whether « and » show.</summary>
    public bool ShowPageJumps => Pager.ShowPageJumps;

    /// <summary>Whether back arrows are enabled.</summary>
    public bool CanGoBack => !Pager.BackDisabled;

    /// <summary>Whether forward arrows are enabled.</summary>
    public bool CanGoForward => !Pager.ForwardDisabled;

    /// <summary>List rows: the selected chart's top five by score (web <c>visibleCards</c>), best first.</summary>
    [ObservableProperty]
    private List<ScoreHistoryListRow> rows = [];

    /// <summary>Whether "View All Scores" shows: the chart has more than five scores (web <c>GraphCard</c> <c>viewAllLabel</c>).</summary>
    public bool CanViewAll => Points.Count > SongScoreHistory.ListSize;

    /// <summary>
    /// Where "View All Scores" goes: the selected chart's Player History page, which lists every score with the web's sorts
    /// (view-all-cta R8: the card never expands in place; issue #324).
    /// </summary>
    public AppRoute.PlayerHistory? ViewAllRoute => Selected is { } chart ? new AppRoute.PlayerHistory(SongId, chart) : null;

    /// <summary>Message for a chart without rows (web <c>chart.noHistory</c>).</summary>
    public string EmptyMessage => $"No score history for {Selected?.Label() ?? "this instrument"}";

    /// <summary>Screen-reader summary of the chart page.</summary>
    [ObservableProperty]
    private string chartSummary = "";

    /// <summary>Whether the song's Lead is a keyboard chart (icon variant).</summary>
    public bool KeyboardLead => song?.UsesKeyboardIcon == true;

    /// <summary>
    /// Reads the player's history for this song (all charts), applies invalid-score filtering and picks the chart. Hidden
    /// without a player, for unregistered players and when no visible chart has rows.
    /// </summary>
    /// <param name="catalogSong">Resolved song (max scores for filtering).</param>
    /// <param name="visibleCharted">Visible charted instruments in display order.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Load task (never throws for service errors).</returns>
    public async Task LoadAsync(Song? catalogSong, IReadOnlyList<Instrument> visibleCharted, CancellationToken cancellationToken = default)
    {
        song = catalogSong;
        pool = visibleCharted;
        if (session is null || session.SelectedPlayer is not { } player)
        {
            Show(SongScoreHistoryPhase.Hidden, []);
            return;
        }
        try
        {
            var read = await session.Api.GetPlayerSongHistoryAsync(player.AccountId, SongId, cancellationToken);
            Status.Clear();
            if (read.State == PlayerHistoryState.Syncing)
            {
                Show(SongScoreHistoryPhase.Syncing, []);
                return;
            }
            var rows = read.Response.History.Where(h => h.SongId == SongId);
            Show(SongScoreHistoryPhase.Loaded,
                SongScoreHistory.FilterInvalid(rows, song, session.Settings.FilterInvalidScores, session.Settings.Leeway));
        }
        catch (FestivalApiException error)
        {
            Show(SongScoreHistoryPhase.Failed, []);
            Status.Report(error);
        }
    }

    /// <summary>Selects a chart (the selector is required: there is always one while loaded).</summary>
    /// <param name="instrument">Chart.</param>
    public void SelectInstrument(Instrument instrument)
    {
        if (!Instruments.Contains(instrument) || Selected == instrument) return;
        // Like the web, the new chart opens with no bar selected; the closed detail row keeps its space instead.
        ReservesDetail |= HasSelectedPoint;
        Selected = instrument;
        Rebuild();
    }

    /// <summary>Plot width changed: recompute bars per page.</summary>
    /// <param name="plotWidth">Width available to bars.</param>
    public void SetPlotWidth(double plotWidth)
    {
        var bars = ScoreHistoryChartScale.MaxBars(plotWidth);
        if (bars == Pager.MaxBars) return;
        Pager.SetMaxBars(bars);
        RefreshPage();
    }

    /// <summary>Selects (or clears) the bar at a point index.</summary>
    /// <param name="index">Point index.</param>
    [RelayCommand]
    public void ToggleBar(int index)
    {
        ReservesDetail = false;
        Pager.Toggle(index);
        RefreshPage();
    }

    /// <summary>Selects a point (never clears it) and pages so its bar shows: the guide's scripted bar selection.</summary>
    /// <param name="index">Point index; out of range is ignored.</param>
    public void SelectPoint(int index)
    {
        ReservesDetail = false;
        Pager.Select(index);
        RefreshPage();
    }

    /// <summary>«.</summary>
    [RelayCommand]
    public void BackPage() => Page(Pager.BackPage);

    /// <summary>‹.</summary>
    [RelayCommand]
    public void BackEntry() => Page(Pager.BackEntry);

    /// <summary>›.</summary>
    [RelayCommand]
    public void ForwardEntry() => Page(Pager.ForwardEntry);

    /// <summary>».</summary>
    [RelayCommand]
    public void ForwardPage() => Page(Pager.ForwardPage);

    /// <summary>Retries after a syncing (202) answer.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public Task RetryAsync() => LoadAsync(song, pool);

    /// <summary>Applies a phase and rows, choosing the chart.</summary>
    /// <param name="next">Phase.</param>
    /// <param name="loaded">Rows for this song.</param>
    private void Show(SongScoreHistoryPhase next, List<ScoreHistoryEntry> loaded)
    {
        entries = loaded;
        ReservesDetail = false;
        counts = SongScoreHistory.Counts(entries);
        Instruments = [.. pool.Where(i => counts.GetValueOrDefault(i) > 0)];
        var choice = SongScoreHistory.DefaultInstrument(pool, counts, Selected ?? Requested);
        if (next == SongScoreHistoryPhase.Loaded && choice is null) next = SongScoreHistoryPhase.Hidden;
        Selected = choice;
        Rebuild();
        Phase = next;
        OnPropertyChanged(nameof(KeyboardLead));
    }

    /// <summary>Rebuilds points, paging and list for the selected chart.</summary>
    private void Rebuild()
    {
        Points = Selected is { } instrument ? SongScoreHistory.Points(entries, instrument) : [];
        Pager.Reset(Points.Count);
        RefreshPage();
        RebuildRows();
    }

    /// <summary>Runs a paging action and refreshes.</summary>
    /// <param name="action">Pager action.</param>
    private void Page(Action action)
    {
        action();
        RefreshPage();
    }

    /// <summary>Recomputes visible bars, the selected row and arrow states.</summary>
    private void RefreshPage()
    {
        var start = Pager.PageStart;
        var end = Pager.PageEnd;
        Bars = [.. Enumerable.Range(start, Math.Max(0, end - start)).Select(i => new ScoreHistoryBar(i, Points[i], i == Pager.SelectedIndex))];
        SelectedRow = Pager.SelectedIndex >= 0 && Pager.SelectedIndex < Points.Count
            ? new ScoreHistoryListRow(Points[Pager.SelectedIndex], false) { IsDetail = true }
            : null;
        ChartSummary = Bars.Count == 0 ? "" :
            string.Create(CultureInfo.CurrentCulture,
                $"{Selected?.Label()} score history, {Bars.Count} of {Points.Count} scores from {Bars[0].Point.LongDate} to {Bars[^1].Point.LongDate}.");
        OnPropertyChanged(nameof(ShowPaging));
        OnPropertyChanged(nameof(ShowPagerSlot));
        OnPropertyChanged(nameof(ShowPageJumps));
        OnPropertyChanged(nameof(CanGoBack));
        OnPropertyChanged(nameof(CanGoForward));
    }

    /// <summary>Rebuilds the top-five list, highest score first; the first row (the personal best) is highlighted.</summary>
    private void RebuildRows()
    {
        var rows = SongScoreHistory.TopScores(Points).Select((p, i) => new ScoreHistoryListRow(p, i == 0)).ToList();
        // One set of columns for the list, so scores and accuracy badges line up (issue #37).
        var section = LeaderboardColumns.Measure(rows);
        Rows = [.. rows.Select(r => r with { Section = section })];
        OnPropertyChanged(nameof(CanViewAll));
    }
}

/// <summary>One chart bar.</summary>
/// <param name="Index">Point index (for selection).</param>
/// <param name="Point">Point.</param>
/// <param name="IsSelected">Whether this bar is selected (purple stroke).</param>
public sealed record ScoreHistoryBar(int Index, ScoreHistoryPoint Point, bool IsSelected);

/// <summary>A list or detail row: date, season/difficulty pills, score, accuracy (web <c>LeaderboardEntry</c> with a date label).</summary>
/// <param name="Point">Point.</param>
/// <param name="IsBest">Personal best (purple highlight and bold, web <c>isPlayer</c>).</param>
public sealed record ScoreHistoryListRow(ScoreHistoryPoint Point, bool IsBest) : ILeaderboardScoreRow
{
    /// <summary>History rows have no rank: the date is the first column (web <c>LeaderboardEntry</c> <c>label</c>).</summary>
    public string RankText => "";

    /// <summary>Date in the name column.</summary>
    public string Name => Date;

    /// <summary>The personal best is drawn like the selected player's row (web <c>scoreListCardBestStyle</c>).</summary>
    public bool IsSelected => IsBest;

    /// <inheritdoc />
    public LeaderboardSection? Section { get; init; }

    /// <summary>
    /// The tapped bar's detail row, which always shows the season (web <c>renderDetailCard</c>); list rows show it only
    /// from a 520 epx row (web <c>QUERY_SHOW_SEASON</c>; issue #62).
    /// </summary>
    public bool IsDetail { get; init; }

    /// <inheritdoc />
    public bool PinsSeason => IsDetail;

    /// <summary>History rows show no stars.</summary>
    public int StarCount => 0;

    /// <summary>History rows open nothing.</summary>
    public AppRoute? Route => null;

    /// <summary>
    /// Prefix of a list row's automation ID: Song Detail's top-five rows by default; Player History uses
    /// <c>fst.history.row.</c>.
    /// </summary>
    public string RowIdPrefix { get; init; } = "fst.song-detail.history.row.";

    /// <summary>
    /// UIA automation ID: <c>fst.history.detail</c> for the selected bar's detail row (it may show the same score as a list
    /// row, whose ID must stay unique), else <see cref="RowIdPrefix"/> + <c>&lt;yyyyMMddHHmmss&gt;</c>.
    /// </summary>
    public string AutomationId => IsDetail
        ? "fst.history.detail"
        : RowIdPrefix + Point.Date.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);

    /// <summary>Badge UIA ID (<c>fst.score.accuracy.history.&lt;yyyyMMddHHmmss&gt;</c>; <c>.detail</c> on the tapped bar's row).</summary>
    public string BadgeAutomationId => "fst.score.accuracy.history." +
                                       Point.Date.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture) + (IsDetail ? ".detail" : "");

    /// <summary>Date label.</summary>
    public string Date => Point.LongDate;

    /// <summary>Grouped score.</summary>
    public string Score => ScoreFormatting.Score(Point.Score);

    /// <summary>Accuracy text (e.g. <c>100%</c>).</summary>
    public string Accuracy => ScoreFormatting.Accuracy(Point.Entry.Accuracy);

    /// <summary>Accuracy percent for the badge tint.</summary>
    public double AccuracyValue => Point.Entry.Accuracy ?? 0;

    /// <summary>Whether an accuracy exists.</summary>
    public bool HasAccuracy => Accuracy.Length > 0;

    /// <summary>Full combo.</summary>
    public bool IsFullCombo => Point.IsFullCombo;

    /// <summary>"S13", or empty.</summary>
    public string Season => Point.Entry.Season is { } s ? "S" + s.ToString(CultureInfo.InvariantCulture) : "";

    /// <summary>Whether the season pill shows.</summary>
    public bool HasSeason => Season.Length > 0;

    /// <summary>Screen-reader text while the season column is hidden (list rows under 520 epx, web <c>QUERY_SHOW_SEASON</c>).</summary>
    public string Announcement => Announce(false);

    /// <summary>
    /// Screen-reader text with the season, read while the row shows it: list rows from 520 epx, the detail row always
    /// (issue #262), and the chart bars, whose selection opens that detail row.
    /// </summary>
    public string SeasonShownAnnouncement => Announce(true);

    /// <summary>Builds the screen-reader text.</summary>
    /// <param name="season">Whether to read the season.</param>
    /// <returns>Date, score, accuracy, full combo, season, then "personal best".</returns>
    private string Announce(bool season) => string.Join(", ", new[]
    {
        Date, $"score {Score}", HasAccuracy ? $"accuracy {Accuracy}" : "", IsFullCombo ? ScoreFormatting.FullComboAnnouncement(HasAccuracy) : "",
        season && Point.Entry.Season is { } s ? $"season {s}" : "", IsBest ? "personal best" : "",
    }.Where(p => p.Length > 0));
}
#endregion
