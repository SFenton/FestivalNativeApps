using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Band detail
/// <summary>
/// <c>/bands/:bandId</c>: members with instruments, summary, statistics, rank history and best/worst songs (web
/// <c>BandPage</c>). The band is resolved only through the pure rankings board filtered by <c>teamKey</c>, so the route
/// must carry <c>bandType</c> and <c>teamKey</c>; a bare <c>bandId</c> shows an explicit "open from a band list" state
/// because <c>/api/bands/{bandId}</c> writes on a GET.
/// </summary>
public sealed partial class BandDetailViewModel : ObservableObject
{
    /// <summary>Rank-history window in days (web default).</summary>
    public const int HistoryDays = 30;

    /// <summary>Songs per best/worst list (web default).</summary>
    public const int SongLimit = 5;

    /// <summary>Quick Links sections (web <c>BandPage.tsx:385-441</c> IDs and labels, in page order).</summary>
    public static IReadOnlyList<QuickLinkSection> QuickLinkSections { get; } =
    [
        new("members", "Members", "\uE716"),
        new("summary", "Summary", "\uE8A5"),
        new("statistics", "Statistics", "\uE9D2"),
        new("rank-history", "Rank History", "\uE81C"),
        new("songs", "Songs", "\uE8D6"),
    ];

    /// <summary>Most recent snapshots listed under the chart.</summary>
    public const int RecentHistoryRows = 10;

    private readonly FestivalSession session;
    private readonly BandType bandType;
    private readonly string teamKey = "";
    private BandDetail? detail;
    private BandRankHistoryResponse? history;
    private BandSongExtremesResponse? songs;
    private int version;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Band route.</param>
    public BandDetailViewModel(FestivalSession session, AppRoute.Band route)
    {
        this.session = session;
        BandId = route.BandId;
        IsResolvable = BandTypeInfo.TryParse(route.BandType, out bandType) && BandEndpoints.IsValidTeamKey(route.TeamKey);
        if (IsResolvable) teamKey = route.TeamKey!;
        Status = new ServiceStatusViewModel("band:" + BandId, "Band not found", LoadAsync, session.Time);
        HistoryStatus = new ServiceStatusViewModel("band-history:" + BandId, "Rank history unavailable", LoadHistoryAsync, session.Time);
        SongsStatus = new ServiceStatusViewModel("band-songs:" + BandId, "Band songs unavailable", LoadSongsAsync, session.Time);
    }

    /// <summary>Band hash from the route.</summary>
    public string BandId { get; }

    /// <summary>Whether the route carries a valid band type and team key.</summary>
    public bool IsResolvable { get; }

    /// <summary>Whether the explicit unresolvable-link state is shown.</summary>
    public bool ShowUnresolved => !IsResolvable;

    /// <summary>Band-row read failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Rank-history read failure.</summary>
    public ServiceStatusViewModel HistoryStatus { get; }

    /// <summary>Best/worst read failure.</summary>
    public ServiceStatusViewModel SongsStatus { get; }

    /// <summary>Rank-by choices for Statistics and Rank History.</summary>
    public List<BandRankingMetric> Metrics { get; } = [.. BandRankingMetricInfo.All];

    /// <summary>Rank By labels in <see cref="Metrics"/> order (the picker's items).</summary>
    public List<string> MetricLabels { get; } = [.. BandRankingMetricInfo.All.Select(m => m.Label())];

    /// <summary>
    /// Whether the Rank By picker shows: only with Settings' Experimental Ranks on (web <c>BandPage</c> shows experimental
    /// ranks only then); otherwise Statistics and Rank History stay on Total Score.
    /// </summary>
    public bool ShowRankBy => session.Settings.ExperimentalRanks;

    #region State
    /// <summary>Band-row lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowContent), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Rank-history lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HistoryLoading), nameof(ShowHistory), nameof(HistoryEmpty), nameof(HistoryFailed), nameof(ShowHistoryCard))]
    private LoadState historyState = LoadState.Idle;

    /// <summary>Best/worst lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SongsLoading), nameof(ShowSongs), nameof(SongsFailed))]
    private LoadState songsState = LoadState.Idle;

    /// <summary>Selected rank-by metric (web default Total Score without experimental ranks).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MetricIndex))]
    private BandRankingMetric metric = BandRankingMetric.TotalScore;

    /// <summary>Header title (joined member names).</summary>
    [ObservableProperty]
    private string title = "Band";

    /// <summary><c>Duos · 40 appearances</c>.</summary>
    [ObservableProperty]
    private string subtitle = "";

    /// <summary>Member rows.</summary>
    [ObservableProperty]
    private List<BandMemberRow> members = [];

    /// <summary>Summary cards (type, appearances, members).</summary>
    [ObservableProperty]
    private List<BandStatCard> summary = [];

    /// <summary>Statistics cards.</summary>
    [ObservableProperty]
    private List<BandStatCard> statistics = [];

    /// <summary>Chart points, oldest first, normalized to 0–1 (rank 1 at the top).</summary>
    [ObservableProperty]
    private List<BandHistoryPoint> historyPoints = [];

    /// <summary>
    /// Combined chart for the selected metric (web <c>BandRankHistoryChart</c>): the metric's value as rank-coloured bars
    /// with the rank line, paged; replaces the plain rank line (Windows backlog).
    /// </summary>
    [ObservableProperty]
    private RankHistoryCombinedChart? historyChart;

    /// <summary>Most recent snapshots, newest first.</summary>
    [ObservableProperty]
    private List<BandHistoryRow> historyRows = [];

    /// <summary>History freshness note, if any.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HistoryHint))]
    private string? historyNote;

    /// <summary>Best songs.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(BestEmpty))]
    private List<BandSongRow> best = [];

    /// <summary>Worst songs.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(WorstEmpty))]
    private List<BandSongRow> worst = [];

    /// <summary>Whether the band row is loading.</summary>
    public bool IsLoading => IsResolvable && State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether sections are shown.</summary>
    public bool ShowContent => State == LoadState.Loaded;

    /// <summary>Whether the band-row failure is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the history is loading.</summary>
    public bool HistoryLoading => HistoryState is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether the chart and rows are shown.</summary>
    public bool ShowHistory => HistoryState == LoadState.Loaded;

    /// <summary>Whether "No band rank history yet." is shown.</summary>
    public bool HistoryEmpty => HistoryState == LoadState.Empty;

    /// <summary>Whether the history failure is shown.</summary>
    public bool HistoryFailed => HistoryState == LoadState.Failed;

    /// <summary>Whether the history card shows (loading, failed or loaded); empty is the shared card-less empty state (#377).</summary>
    public bool ShowHistoryCard => HistoryState != LoadState.Empty;

    /// <summary>Whether best/worst are loading.</summary>
    public bool SongsLoading => SongsState is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether best/worst lists are shown.</summary>
    public bool ShowSongs => SongsState == LoadState.Loaded;

    /// <summary>Whether the best/worst failure is shown.</summary>
    public bool SongsFailed => SongsState == LoadState.Failed;

    /// <summary>Whether the best list is empty.</summary>
    public bool BestEmpty => Best.Count == 0;

    /// <summary>Whether the worst list is empty.</summary>
    public bool WorstEmpty => Worst.Count == 0;

    /// <summary>Index of <see cref="Metric"/> in <see cref="Metrics"/> (picker binding; experimental metrics need
    /// Settings' Experimental Ranks).</summary>
    public int MetricIndex
    {
        get => Metrics.IndexOf(Metric);
        set
        {
            if (value >= 0 && value < Metrics.Count) Metric = Metrics[value].Gate(session.Settings.ExperimentalRanks);
        }
    }

    /// <summary>Hint under the history heading.</summary>
    public string HistoryHint =>
        $"Any-combo ranking progression over the past {HistoryDays} days." + (HistoryNote is { } note ? " " + note : "");

    /// <summary>Best-songs description.</summary>
    public string BestDescription => $"{Title}'s highest-ranked band songs, sorted by percentile.";

    /// <summary>Worst-songs description.</summary>
    public string WorstDescription => $"{Title}'s lowest-ranked band songs, sorted by percentile.";
    #endregion

    #region Loading
    /// <summary>Loads the band row, then its history and songs.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        if (!IsResolvable) return;
        var requested = ++version;
        State = LoadState.Loading;
        try
        {
            var loaded = await session.Api.GetBandProfileAsync(bandType, teamKey);
            if (requested != version) return;
            detail = loaded;
            Status.Clear();
            Title = BandMember.JoinNames(loaded.DisplayMembers);
            OnPropertyChanged(nameof(BestDescription));
            OnPropertyChanged(nameof(WorstDescription));
            Subtitle = $"{bandType.Label()} · {BandFormatting.Count(loaded.SongsPlayed)} appearances";
            Members = [.. loaded.DisplayMembers.DistinctBy(m => m.AccountId, StringComparer.Ordinal).Select(m => new BandMemberRow(m))];
            Summary =
            [
                new("type", "Type", bandType.Label()),
                new("appearances", "Appearances", BandFormatting.Count(loaded.SongsPlayed)),
                new("members", "Members", BandFormatting.Count(Members.Count)),
            ];
            BuildStatistics();
            State = LoadState.Loaded;
            await Task.WhenAll(LoadHistoryAsync(), LoadSongsAsync());
        }
        catch (FestivalApiException error)
        {
            if (requested != version) return;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Loads the rank history (also the inline Retry).</summary>
    /// <returns>Load task.</returns>
    public async Task LoadHistoryAsync()
    {
        HistoryState = LoadState.Loading;
        try
        {
            history = await session.Api.GetBandRankHistoryAsync(bandType, teamKey, HistoryDays);
            HistoryStatus.Clear();
            HistoryNote = HistoryNoteFor(history);
            BuildHistory();
        }
        catch (FestivalApiException error)
        {
            HistoryStatus.Report(error);
            HistoryState = LoadState.Failed;
        }
    }

    /// <summary>Loads best/worst songs and resolves them against the catalogue (also the inline Retry).</summary>
    /// <returns>Load task.</returns>
    public async Task LoadSongsAsync()
    {
        SongsState = LoadState.Loading;
        try
        {
            songs = await session.Api.GetBandSongExtremesAsync(bandType, teamKey, SongLimit);
            try
            {
                await session.LoadCatalogAsync();
            }
            catch (FestivalApiException)
            {
                // Best effort: rows fall back to "Unknown Song" without a link.
            }
            SongsStatus.Clear();
            Best = [.. songs.Best.Select(p => new BandSongRow(p, session.FindSong(p.SongId)))];
            Worst = [.. songs.Worst.Select(p => new BandSongRow(p, session.FindSong(p.SongId)))];
            BuildStatistics();
            SongsState = LoadState.Loaded;
        }
        catch (FestivalApiException error)
        {
            SongsStatus.Report(error);
            SongsState = LoadState.Failed;
        }
    }

    /// <summary>Re-projects cards and history for a new metric (no new request).</summary>
    /// <param name="value">New metric.</param>
    partial void OnMetricChanged(BandRankingMetric value)
    {
        BuildStatistics();
        BuildHistory();
    }
    #endregion

    #region Projection
    /// <summary>Builds the Statistics cards from the band row and (once loaded) the best song.</summary>
    private void BuildStatistics()
    {
        if (detail is not { } d) return;
        var rank = d.Rank(Metric);
        var bestSong = songs?.Best.FirstOrDefault()?.SongId;
        AppRoute rankings = new AppRoute.BandRankings(bandType.ServiceId());
        Statistics =
        [
            new("rank", $"{Metric.Label()} Rank", BandFormatting.Rank(rank), rank > 0 ? rankings : null),
            new("songs-played", "Songs Played", BandFormatting.Fraction(d.SongsPlayed, d.TotalChartedSongs)),
            new("full-combos", "Full Combos", BandFormatting.Fraction(d.FullComboCount, d.TotalChartedSongs)),
            new("total-score", "Total Score", BandFormatting.Count(d.TotalScore)),
            new("fc-rate", "FC Rate", BandFormatting.Percentage(d.FcRate)),
            new("avg-accuracy", "Avg Accuracy", BandFormatting.Accuracy(d.AvgAccuracy)),
            d.AvgStars == StarRating.GoldValue
                ? new("avg-stars", "Avg Stars", StarRating.From(StarRating.GoldValue)!.Value.Announcement, GoldStars: true)
                : new("avg-stars", "Avg Stars", BandFormatting.Stars(d.AvgStars)),
            new("best-rank", "Best Song Rank", BandFormatting.Rank(d.BestRank),
                bestSong is not null && d.BestRank > 0 && session.FindSong(bestSong) is not null ? new AppRoute.SongDetail(bestSong) : null),
            new("avg-rank", "Avg Rank", BandFormatting.AverageRank(d.AvgRank)),
        ];
    }

    /// <summary>Builds chart points and recent rows for the selected metric.</summary>
    private void BuildHistory()
    {
        if (history is null) return;
        var ranked = history.History.Where(h => h.Rank(Metric) > 0)
            .OrderBy(h => h.SnapshotDate, StringComparer.Ordinal).ToList();
        HistoryPoints = BandHistoryPoint.Normalize(ranked, Metric);
        HistoryChart = RankHistoryCombinedChart.BuildBand(ranked, Metric, detail?.TotalRankedTeams);
        HistoryRows = [.. Enumerable.Reverse(ranked).Take(RecentHistoryRows).Select(h => new BandHistoryRow(h, Metric))];
        HistoryState = ranked.Count == 0 ? LoadState.Empty : LoadState.Loaded;
    }

    /// <summary>Freshness text for a history response (web <c>band.rankHistory*</c> strings).</summary>
    /// <param name="response">History response.</param>
    /// <returns>Note, or <see langword="null"/> when current.</returns>
    internal static string? HistoryNoteFor(BandRankHistoryResponse response)
    {
        if (response.HistoryStatus == "failed") return "Rank history is temporarily unavailable.";
        if (!string.IsNullOrWhiteSpace(response.HistoryMessage)) return response.HistoryMessage.Trim();
        return response.HistoryStatus switch
        {
            "catching_up" => "History is catching up. Current rankings are already fresh.",
            "stale" => "Rank history is behind the latest current rankings.",
            "disabled" => "Rank history is disabled while current rankings remain available.",
            _ => null,
        };
    }
    #endregion
}
#endregion

#region History rows
/// <summary>A chart vertex: <c>X</c> 0–1 oldest to newest, <c>Y</c> 0–1 with the best rank at 0 (top).</summary>
/// <remarks>Get-only properties: XAML type info generates setters for init accessors, which fails to compile.</remarks>
public sealed record BandHistoryPoint
{
    /// <summary>Creates a vertex.</summary>
    /// <param name="x">Horizontal position.</param>
    /// <param name="y">Vertical position.</param>
    /// <param name="rank">Rank at this snapshot.</param>
    public BandHistoryPoint(double x, double y, int rank) => (X, Y, Rank) = (x, y, rank);

    /// <summary>Horizontal position (0 oldest, 1 newest).</summary>
    public double X { get; }

    /// <summary>Vertical position (0 best rank).</summary>
    public double Y { get; }

    /// <summary>Rank at this snapshot.</summary>
    public int Rank { get; }

    /// <summary>Normalizes ranked snapshots (oldest first) into chart space.</summary>
    /// <param name="ranked">Snapshots with a rank for the metric.</param>
    /// <param name="metric">Metric.</param>
    /// <returns>Points; a single snapshot sits mid-height.</returns>
    public static List<BandHistoryPoint> Normalize(IReadOnlyList<BandRankHistoryEntry> ranked, BandRankingMetric metric)
    {
        if (ranked.Count == 0) return [];
        var ranks = ranked.Select(h => h.Rank(metric)).ToArray();
        int min = ranks.Min(), max = ranks.Max();
        var points = new List<BandHistoryPoint>(ranks.Length);
        for (var i = 0; i < ranks.Length; i++)
        {
            var x = ranks.Length == 1 ? 0.5 : (double)i / (ranks.Length - 1);
            var y = max == min ? 0.5 : (double)(ranks[i] - min) / (max - min);
            points.Add(new BandHistoryPoint(x, y, ranks[i]));
        }
        return points;
    }
}

/// <summary>One snapshot row: date, rank and metric value.</summary>
/// <param name="Entry">Wire snapshot.</param>
/// <param name="Metric">Metric.</param>
public sealed record BandHistoryRow(BandRankHistoryEntry Entry, BandRankingMetric Metric)
{
    /// <summary><c>Sep 27</c>.</summary>
    public string Date => BandFormatting.ShortDate(Entry.SnapshotDate);

    /// <summary><c>#1</c>.</summary>
    public string Rank => BandFormatting.Rank(Entry.Rank(Metric));

    /// <summary>Metric value.</summary>
    public string Value => BandFormatting.MetricValue(Entry.Value(Metric), Metric);

    /// <summary>Automation ID (<c>fst.band.history-row.&lt;date&gt;</c>).</summary>
    public string AutomationId => "fst.band.history-row." + Entry.SnapshotDate;

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"{Date}, rank {Rank}, {Value}";
}

/// <summary>A best/worst song row resolved against the catalogue.</summary>
/// <param name="Performance">Wire performance.</param>
/// <param name="Song">Catalogue song, when known.</param>
public sealed record BandSongRow(BandSongPerformance Performance, Song? Song)
{
    /// <summary>Title, or <c>Unknown Song</c>.</summary>
    public string Title => Song?.Title ?? "Unknown Song";

    /// <summary>Artist · year.</summary>
    public string Subtitle => Song is null ? "" : string.Join(" · ",
        new[] { Song.Artist, Song.Year?.ToString(System.Globalization.CultureInfo.InvariantCulture) }.Where(s => !string.IsNullOrEmpty(s)));

    /// <summary>Album-art reference.</summary>
    public string? AlbumArt => Song?.AlbumArt;

    /// <summary><c>Top 4%</c>.</summary>
    public string PercentileText => BandFormatting.Percentile(Performance.Percentile);

    /// <summary><c>#1 of 26</c>.</summary>
    public string RankText => $"{BandFormatting.Rank(Performance.Rank)} of {BandFormatting.Count(Performance.TotalEntries)}";

    /// <summary>Song Detail route when the song is in the catalogue.</summary>
    public AppRoute? Route => Song is null ? null : new AppRoute.SongDetail(Song.SongId);

    /// <summary>Whether the row navigates.</summary>
    public bool IsLink => Route is not null;

    /// <summary>Automation ID (<c>fst.band.song-row.&lt;songId&gt;</c>).</summary>
    public string AutomationId => "fst.band.song-row." + Performance.SongId;

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"{Title}, {PercentileText}, rank {RankText}";
}
#endregion
