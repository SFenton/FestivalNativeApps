using System.Globalization;

namespace Festival.Core.Domain;

#region Combined rank history
/// <summary>One snapshot of the combined chart.</summary>
/// <param name="AxisLabel">X-axis date, web <c>formatRankHistoryAxisDate</c> ("9/21/26").</param>
/// <param name="DisplayDate">Spoken/detail date ("Sep 21, 2026").</param>
/// <param name="Rank">Rank for the chart's metric.</param>
/// <param name="Value">The metric's value (the bar): Total Score, a rating or a fraction; 0 when unknown.</param>
/// <param name="BarArgb">Bar colour, web <c>rankColor(rank, rankedAccountCount)</c>.</param>
public sealed record RankHistoryPoint(string AxisLabel, string DisplayDate, int Rank, double Value, uint BarArgb);

/// <summary>The snapshots visible in one page of the chart, laid out in unit coordinates.</summary>
/// <param name="Points">Visible snapshots, oldest first.</param>
/// <param name="Bars">Total Score bars (centre X, height fraction from the bottom).</param>
/// <param name="Line">Rank line (Y 0 is the best rank on the reversed axis).</param>
/// <param name="RankTicks">Right-axis rank labels.</param>
/// <param name="ValueTicks">Left-axis Total Score labels (Y 0 top, 1 bottom).</param>
/// <param name="Offset">Snapshots hidden to the right (0 shows the newest).</param>
/// <param name="MaxOffset">Largest offset.</param>
/// <param name="RangeText">"Sep 1 – Sep 5, 2026" for the visible page.</param>
/// <param name="Summary">Screen-reader sentence for the visible page.</param>
public sealed record RankHistoryPage(
    List<RankHistoryPoint> Points, List<ChartBar> Bars, List<ChartPoint> Line, List<ChartTick> RankTicks, List<ChartTick> ValueTicks,
    int Offset, int MaxOffset, string RangeText, string Summary)
{
    /// <summary>Whether older snapshots exist to the left.</summary>
    public bool CanOlder => Offset < MaxOffset;

    /// <summary>Whether newer snapshots exist to the right.</summary>
    public bool CanNewer => Offset > 0;
}

/// <summary>
/// The combined Rank History chart (web <c>RankHistoryChart</c> / <c>BandRankHistoryChart</c> + <c>GraphCard</c>): the
/// metric's value as bars coloured by rank on the left axis and the rank line (<c>#4C7DFF</c>) on a reversed right axis
/// whose domain spans all history, paged like the web's <c>useChartPagination</c> so one page holds as many 96 epx bars
/// as fit, newest page first. The player page charts Total Score; Band Detail charts the selected band metric.
/// </summary>
public sealed class RankHistoryCombinedChart
{
    /// <summary>Web <c>MIN_BAR_WIDTH</c>.</summary>
    public const double MinBarWidth = 96;

    /// <summary>Web <c>BAR_GAP</c>.</summary>
    public const double BarGap = 8;

    /// <summary>Rank line colour, web <c>accentBlueBright</c>.</summary>
    public const uint LineArgb = 0xFF4C7DFF;

    /// <summary>Bar colour when the field size is unknown, web <c>rgb(127,140,141)</c>.</summary>
    public const uint UnknownArgb = 0xFF7F8C8D;

    /// <summary>Narrowest left (value) gutter, the 100% text-scale layout.</summary>
    public const double MinValueGutter = 52;

    /// <summary>Narrowest right (rank) gutter, the 100% text-scale layout.</summary>
    public const double MinRankGutter = 48;

    /// <summary>Space between the plot and the axis tick labels.</summary>
    public const double AxisLabelGap = 6;

    /// <summary>Shortest date band under the bars, the 100% text-scale layout.</summary>
    public const double MinDateBand = 22;

    /// <summary>
    /// Side gutter that fits the widest measured tick label plus its gap to the plot, so Windows text sizes up to 225%
    /// widen the gutter instead of clipping labels such as "49.5M".
    /// </summary>
    /// <param name="widestLabel">Widest tick label's measured width (epx, already text-scaled).</param>
    /// <param name="minimum">Gutter at 100% text (<see cref="MinValueGutter"/> or <see cref="MinRankGutter"/>).</param>
    /// <returns>Gutter width, at least <paramref name="minimum"/> (a non-finite or negative minimum counts as 0).</returns>
    public static double AxisGutter(double widestLabel, double minimum)
    {
        var floor = double.IsFinite(minimum) ? Math.Max(0, minimum) : 0;
        var needed = Math.Max(0, widestLabel) + AxisLabelGap;
        return double.IsFinite(needed) ? Math.Max(floor, Math.Ceiling(needed)) : floor;
    }

    /// <summary>Date band under the bars that fits a measured (text-scaled) date label.</summary>
    /// <param name="labelHeight">Measured date label height (epx).</param>
    /// <returns>Band height, at least <see cref="MinDateBand"/>.</returns>
    public static double DateBand(double labelHeight) =>
        double.IsFinite(labelHeight) ? Math.Max(MinDateBand, Math.Ceiling(labelHeight)) : MinDateBand;

    private RankHistoryCombinedChart(List<RankHistoryPoint> points, int best, int worst, string metricLabel,
        Func<double, string> tick, Func<double, string> detail)
    {
        Points = points;
        Best = best;
        Worst = worst;
        MetricLabel = metricLabel;
        tickFormat = tick;
        detailFormat = detail;
    }

    private readonly Func<double, string> tickFormat;
    private readonly Func<double, string> detailFormat;

    /// <summary>Bar metric name for the legend and screen reader ("Total Score", "Adjusted", …).</summary>
    public string MetricLabel { get; }

    /// <summary>Every snapshot, oldest first.</summary>
    public IReadOnlyList<RankHistoryPoint> Points { get; }

    /// <summary>Top of the reversed rank axis (web <c>getRankHistoryDomain</c>).</summary>
    public int Best { get; }

    /// <summary>Bottom of the reversed rank axis.</summary>
    public int Worst { get; }

    /// <summary>Builds the chart from ranked snapshots.</summary>
    /// <param name="ranked">Chronological snapshots with a positive Total Score rank.</param>
    /// <returns>Chart, or <see langword="null"/> when empty.</returns>
    public static RankHistoryCombinedChart? Build(IReadOnlyList<PlayerRankHistorySnapshot> ranked)
    {
        if (ranked.Count == 0) return null;
        var points = ranked.Select(r => new RankHistoryPoint(
            r.Date is { } day ? $"{day.Month}/{day.Day}/{day:yy}" : r.SnapshotDate,
            r.Date?.ToString("MMM d, yyyy", CultureInfo.CurrentCulture) ?? r.SnapshotDate,
            r.TotalScoreRank, r.TotalScore ?? 0, RankColor(r.TotalScoreRank, r.RankedAccountCount))).ToList();
        var (best, worst) = Domain(points.Select(p => p.Rank).ToList());
        return new RankHistoryCombinedChart(points, best, worst, "Total Score", ValueTick, v => ScoreFormatting.Score((long)v));
    }

    /// <summary>
    /// Band Detail's chart for one band metric (web <c>BandRankHistoryChart</c>): that metric's value as bars, its rank as
    /// the line, bars coloured against the band field size.
    /// </summary>
    /// <param name="ranked">Chronological snapshots with a positive rank for <paramref name="metric"/>.</param>
    /// <param name="metric">Band metric.</param>
    /// <param name="totalRankedTeams">Field size from the ranking, if known (else each snapshot's own).</param>
    /// <returns>Chart, or <see langword="null"/> when empty.</returns>
    public static RankHistoryCombinedChart? BuildBand(IReadOnlyList<BandRankHistoryEntry> ranked, BandRankingMetric metric, int? totalRankedTeams)
    {
        if (ranked.Count == 0) return null;
        var field = totalRankedTeams is > 0 ? totalRankedTeams : ranked.LastOrDefault(r => r.TotalRankedTeams is > 0)?.TotalRankedTeams;
        var points = ranked.Select(r =>
        {
            DateOnly? day = DateOnly.TryParseExact(r.SnapshotDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;
            return new RankHistoryPoint(
                day is { } axis ? $"{axis.Month}/{axis.Day}/{axis:yy}" : r.SnapshotDate,
                day?.ToString("MMM d, yyyy", CultureInfo.CurrentCulture) ?? r.SnapshotDate,
                r.Rank(metric), r.Value(metric) ?? 0, RankColor(r.Rank(metric), field));
        }).ToList();
        var (best, worst) = Domain(points.Select(p => p.Rank).ToList());
        var rankingMetric = metric.ToRankingMetric();
        return new RankHistoryCombinedChart(points, best, worst, rankingMetric.Label(),
            v => MetricTick(v, rankingMetric), v => MetricDetail(v, rankingMetric));
    }

    /// <summary>Web <c>formatValueTick</c>: percentages for FC Rate / Max Score, two decimals for ratings, K/M/B for scores.</summary>
    /// <param name="value">Value.</param>
    /// <param name="metric">Metric.</param>
    /// <returns>Axis label.</returns>
    public static string MetricTick(double value, RankingMetric metric) => metric switch
    {
        RankingMetric.FcRate or RankingMetric.MaxScore => (value * 100).ToString("0", CultureInfo.InvariantCulture) + "%",
        RankingMetric.Adjusted or RankingMetric.Weighted => value.ToString("0.00", CultureInfo.InvariantCulture),
        _ => ValueTick(value),
    };

    /// <summary>Web <c>formatDetailValue</c>: the spoken/detail value for one snapshot.</summary>
    /// <param name="value">Value.</param>
    /// <param name="metric">Metric.</param>
    /// <returns>Formatted value.</returns>
    public static string MetricDetail(double value, RankingMetric metric)
    {
        switch (metric)
        {
            case RankingMetric.FcRate or RankingMetric.MaxScore:
                var percent = value * 100;
                return (percent % 1 == 0 ? percent.ToString("0", CultureInfo.InvariantCulture) : percent.ToString("0.0", CultureInfo.InvariantCulture)) + "%";
            case RankingMetric.Adjusted or RankingMetric.Weighted:
                return value % 1 == 0 ? value.ToString("0", CultureInfo.InvariantCulture) : value.ToString("0.0", CultureInfo.InvariantCulture);
            default:
                return ScoreFormatting.Score((long)Math.Round(value));
        }
    }

    /// <summary>Web <c>getRankHistoryDomain</c>: min/max rank padded by 10% (at least one rank each way here).</summary>
    /// <param name="ranks">Ranks.</param>
    /// <returns>Best (top) and worst (bottom) axis values.</returns>
    public static (int Best, int Worst) Domain(IReadOnlyCollection<int> ranks)
    {
        var positive = ranks.Where(r => r > 0).ToList();
        if (positive.Count == 0) return (1, 100);
        var min = positive.Min();
        var max = positive.Max();
        var padding = Math.Max(1, (int)Math.Ceiling((max - min) * 0.1));
        return (Math.Max(1, min - padding), max + padding);
    }

    /// <summary>Web <c>rankColor</c> → <c>accuracyColor</c>: red <c>(220,40,40)</c> to green <c>(46,204,113)</c> by placement.</summary>
    /// <param name="rank">Rank.</param>
    /// <param name="rankedAccounts">Field size, if known.</param>
    /// <returns>Opaque ARGB.</returns>
    public static uint RankColor(int rank, int? rankedAccounts)
    {
        if (rankedAccounts is not > 0 || rank <= 0) return UnknownArgb;
        var t = Math.Clamp(1 - (double)rank / rankedAccounts.Value, 0, 1);
        static uint Mix(double from, double to, double t) => (uint)Math.Round(from * (1 - t) + to * t);
        return 0xFF000000 | Mix(220, 46, t) << 16 | Mix(40, 204, t) << 8 | Mix(40, 113, t);
    }

    /// <summary>Web <c>formatValueTick</c> for Total Score: 1.2B, 3M, 12.5K or the plain number.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Axis label.</returns>
    public static string ValueTick(double value)
    {
        var sign = value < 0 ? "-" : "";
        var absolute = Math.Abs(value);
        static string Scaled(double v) => v % 1 == 0 ? v.ToString("0", CultureInfo.InvariantCulture) : v.ToString("0.0", CultureInfo.InvariantCulture);
        if (absolute >= 1_000_000_000) return sign + Scaled(absolute / 1_000_000_000) + "B";
        if (absolute >= 1_000_000) return sign + Scaled(absolute / 1_000_000) + "M";
        if (absolute >= 1_000) return sign + Scaled(absolute / 1_000) + "K";
        return Math.Round(value).ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>Web <c>useChartDimensions</c>: how many 96 epx bars (8 epx apart) fit the plot.</summary>
    /// <param name="plotWidth">Plot width in epx.</param>
    /// <returns>At least one.</returns>
    public static int MaxBars(double plotWidth) =>
        !double.IsFinite(plotWidth) || plotWidth <= 0 ? 1 : Math.Max(1, (int)Math.Floor((plotWidth + BarGap) / (MinBarWidth + BarGap)));

    /// <summary>Largest offset for a page size.</summary>
    /// <param name="maxBars">Bars per page.</param>
    /// <returns>Offset of the oldest page.</returns>
    public int MaxOffset(int maxBars) => Math.Max(0, Points.Count - Math.Max(1, maxBars));

    /// <summary>Lays out one page (web <c>visibleChartData</c>: the window ending <paramref name="offset"/> snapshots before the newest).</summary>
    /// <param name="maxBars">Bars per page.</param>
    /// <param name="offset">Snapshots hidden to the right (clamped).</param>
    /// <returns>Page geometry.</returns>
    public RankHistoryPage Page(int maxBars, int offset)
    {
        maxBars = Math.Max(1, maxBars);
        var maxOffset = MaxOffset(maxBars);
        offset = Math.Clamp(offset, 0, maxOffset);
        var end = Points.Count - offset;
        var start = Math.Max(0, end - maxBars);
        var visible = Points.Skip(start).Take(end - start).ToList();
        var highest = visible.Max(p => p.Value);
        var top = highest > 0 ? highest : 1;
        double span = Math.Max(1, Worst - Best);
        double X(int i) => (i + 0.5) / visible.Count;
        var bars = visible.Select((p, i) => new ChartBar(X(i), Math.Max(0, p.Value) / top)).ToList();
        var line = visible.Select((p, i) => new ChartPoint(X(i), (p.Rank - Best) / span, start + i == Points.Count - 1)).ToList();
        var mid = (int)Math.Round((Best + Worst) / 2.0);
        var rankTicks = new[] { Best, mid, Worst }.Distinct()
            .Select(r => new ChartTick((r - Best) / span, ScoreFormatting.Rank(r))).ToList();
        var valueTicks = new[] { top, top / 2.0, 0 }.Select(v => new ChartTick(1 - v / top, tickFormat(v))).ToList();
        var range = visible.Count == 1 ? visible[0].DisplayDate : $"{visible[0].DisplayDate} – {visible[^1].DisplayDate}";
        var summary = $"Rank history, {range}: " + string.Join("; ", visible.Select(p =>
            $"{p.DisplayDate} rank {ScoreFormatting.Rank(p.Rank)}, {MetricLabel} {detailFormat(p.Value)}"));
        return new RankHistoryPage(visible, bars, line, rankTicks, valueTicks, offset, maxOffset, range, summary);
    }
}
#endregion
