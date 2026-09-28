using System.Globalization;

namespace Festival.Core.Domain;

#region Combined rank history
/// <summary>One snapshot of the combined chart.</summary>
/// <param name="AxisLabel">X-axis date, web <c>formatRankHistoryAxisDate</c> ("9/21/26").</param>
/// <param name="DisplayDate">Spoken/detail date ("Sep 21, 2026").</param>
/// <param name="Rank">Total Score rank.</param>
/// <param name="Value">Total Score (the bar), 0 when unknown.</param>
/// <param name="BarArgb">Bar colour, web <c>rankColor(rank, rankedAccountCount)</c>.</param>
public sealed record RankHistoryPoint(string AxisLabel, string DisplayDate, int Rank, long Value, uint BarArgb);

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
/// The player page's combined Rank History chart (web <c>RankHistoryChart</c> + <c>GraphCard</c>, metric Total Score):
/// Total Score bars coloured by rank on the left axis and the rank line (<c>#4C7DFF</c>) on a reversed right axis whose
/// domain spans all history, paged like the web's <c>useChartPagination</c> so one page holds as many 96 epx bars as fit,
/// newest page first.
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

    private RankHistoryCombinedChart(List<RankHistoryPoint> points, int best, int worst)
    {
        Points = points;
        Best = best;
        Worst = worst;
    }

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
        return new RankHistoryCombinedChart(points, best, worst);
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
        var top = Math.Max(1, visible.Max(p => p.Value));
        double span = Math.Max(1, Worst - Best);
        double X(int i) => (i + 0.5) / visible.Count;
        var bars = visible.Select((p, i) => new ChartBar(X(i), (double)p.Value / top)).ToList();
        var line = visible.Select((p, i) => new ChartPoint(X(i), (p.Rank - Best) / span, start + i == Points.Count - 1)).ToList();
        var mid = (int)Math.Round((Best + Worst) / 2.0);
        var rankTicks = new[] { Best, mid, Worst }.Distinct()
            .Select(r => new ChartTick((r - Best) / span, ScoreFormatting.Rank(r))).ToList();
        var valueTicks = new[] { top, top / 2.0, 0 }.Select(v => new ChartTick(1 - v / top, ValueTick(v))).ToList();
        var range = visible.Count == 1 ? visible[0].DisplayDate : $"{visible[0].DisplayDate} – {visible[^1].DisplayDate}";
        var summary = $"Rank history, {range}: " + string.Join("; ", visible.Select(p =>
            $"{p.DisplayDate} rank {ScoreFormatting.Rank(p.Rank)}, Total Score {ScoreFormatting.Score(p.Value)}"));
        return new RankHistoryPage(visible, bars, line, rankTicks, valueTicks, offset, maxOffset, range, summary);
    }
}
#endregion
